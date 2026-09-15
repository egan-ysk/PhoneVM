import AppKit
import Combine
import XCTest
@testable import PhoneVM

final class PhysicalDeviceTests: XCTestCase {
    private var root: URL!
    private var executable: URL!
    private var locator: ToolLocator!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PhoneVMPhysicalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        executable = root.appendingPathComponent("adb")
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        locator = ToolLocator(environment: ["PATH": root.path], homeDirectory: root)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testAndroidDiscoverySeparatesEmulatorsAndAuthorizationStates() throws {
        let runner = DeviceProcessRunner()
        runner.text = { _ in .init(exitCode: 0, standardOutput: """
        List of devices attached
        emulator-5554 device product:sdk model:sdk
        phone-a device product:pixel model:Pixel_9 transport_id:1
        phone-b unauthorized transport_id:2
        phone-c offline transport_id:3
        phone-d recovery
        phone-e no permissions (missing udev rules)
        phone-a device model:Pixel_9
        """, standardError: "") }
        let devices = try AndroidPhysicalDeviceProvider(toolLocator: locator, processRunner: runner).scan(settings: AppSettings())
        XCTAssertEqual(devices.map(\.identifier), ["phone-a", "phone-b", "phone-c", "phone-d", "phone-e"])
        XCTAssertEqual(devices.map(\.connectionState), [.connected, .unauthorized, .disconnected, .unknown, .unauthorized])
        XCTAssertEqual(devices.first?.name, "Pixel 9")
        XCTAssertEqual(devices.filter(\.canScreenshot).map(\.identifier), ["phone-a"])
    }

    func testAndroidScreenshotTargetsSelectedSerialAndRejectsBadData() throws {
        let runner = DeviceProcessRunner()
        let png = try imageData()
        runner.binary = { command in
            XCTAssertEqual(command.arguments, ["-s", "second-device", "exec-out", "screencap", "-p"])
            return .init(exitCode: 0, standardOutput: png, standardError: "")
        }
        let provider = AndroidPhysicalDeviceProvider(toolLocator: locator, processRunner: runner)
        let device = PhysicalDevice(name: "Phone", identifier: "second-device", platform: .android, connectionState: .connected)
        XCTAssertEqual(try provider.screenshot(device, settings: AppSettings()), png)
        for invalid in [Data(), Data("not a PNG".utf8), Data([0x89, 0x50, 0x4e, 0x47])] {
            runner.binary = { _ in .init(exitCode: 0, standardOutput: invalid, standardError: "") }
            XCTAssertThrowsError(try provider.screenshot(device, settings: AppSettings()))
        }
        runner.binary = { _ in .init(exitCode: 1, standardOutput: png, standardError: "device offline") }
        XCTAssertThrowsError(try provider.screenshot(device, settings: AppSettings()))
    }

    func testIOSDiscoveryUsesHardwareUDIDAndGatesUnavailableDevices() throws {
        let runner = DeviceProcessRunner()
        let fixtures = [
            iosRecord(udid: "online"),
            iosRecord(udid: "offline", tunnel: "disconnected"),
            iosRecord(udid: "unpaired", pairing: "unpaired"),
            iosRecord(udid: "developer-disabled", developer: "disabled"),
            iosRecord(udid: "not-prepared", ddi: false),
            iosRecord(udid: "unknown-state", tunnel: "future-state"),
            iosRecord(udid: "tv", platform: "tvOS"),
            iosRecord(udid: "simulator", reality: "simulated"),
            iosRecord(udid: nil)
        ]
        var temporaryDirectory: URL?
        runner.text = { command in
            XCTAssertEqual(Array(command.arguments.prefix(7)), ["devicectl", "list", "devices", "--timeout", "10", "--json-output", command.arguments.last!])
            let url = URL(fileURLWithPath: command.arguments.last!)
            temporaryDirectory = url.deletingLastPathComponent()
            try self.writeDeviceList(fixtures, to: url)
            // 只允许消费 JSON 文件，stdout 故意不是 JSON。
            return .init(exitCode: 0, standardOutput: "human readable table", standardError: "")
        }
        let provider = IOSPhysicalDeviceProvider(toolLocator: locator, processRunner: runner)
        let devices = try provider.scan(settings: AppSettings(iOSScreenshotToolPath: executable.path))
        XCTAssertEqual(devices.map(\.identifier), ["online", "offline", "unpaired", "developer-disabled", "not-prepared", "unknown-state"])
        XCTAssertEqual(devices.filter(\.canScreenshot).map(\.identifier), ["online"])
        XCTAssertEqual(devices[0].id, "physical:iOS:online")
        XCTAssertTrue(devices[3].screenshotUnavailableReason!.contains("开发者模式"))
        XCTAssertTrue(devices[4].screenshotUnavailableReason!.contains("Xcode"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(temporaryDirectory).path))
        let missingToolDevices = try provider.scan(settings: AppSettings(iOSScreenshotToolPath: root.appendingPathComponent("missing").path))
        XCTAssertFalse(missingToolDevices[0].canScreenshot)
        XCTAssertTrue(missingToolDevices[0].screenshotUnavailableReason!.contains("pymobiledevice3"))
    }

    func testIOSMalformedDiscoveryFailsAndRemovesTemporaryFiles() throws {
        let runner = DeviceProcessRunner()
        var temporaryDirectory: URL?
        runner.text = { command in
            let url = URL(fileURLWithPath: command.arguments.last!)
            temporaryDirectory = url.deletingLastPathComponent()
            try Data("invalid JSON".utf8).write(to: url)
            return .init(exitCode: 0, standardOutput: "", standardError: "")
        }
        XCTAssertThrowsError(try IOSPhysicalDeviceProvider(processRunner: runner).scan(settings: AppSettings()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(temporaryDirectory).path))
    }

    func testIOSScreenshotAcceptsWarningsButRequiresSuccessfulExitAndValidImage() throws {
        let runner = DeviceProcessRunner()
        let png = try imageData()
        let provider = IOSPhysicalDeviceProvider(toolLocator: locator, processRunner: runner)
        let device = PhysicalDevice(name: "iPhone", identifier: "selected-hardware-udid", platform: .iOS, connectionState: .connected)
        let settings = AppSettings(iOSScreenshotToolPath: executable.path)
        var temporaryDirectories: [URL] = []
        for scenario in 0..<5 {
            runner.text = { command in
                XCTAssertEqual(command.executableURL, self.executable)
                XCTAssertEqual(Array(command.arguments.prefix(5)), ["developer", "dvt", "screenshot", "--udid", device.identifier])
                XCTAssertEqual(command.timeout, 45)
                let url = URL(fileURLWithPath: command.arguments.last!)
                temporaryDirectories.append(url.deletingLastPathComponent())
                if scenario == 3 {
                    throw VirtualMachineProviderError.processFailed("执行超时")
                }
                if scenario != 2 {
                    try (scenario == 4 ? Data("bad PNG".utf8) : png).write(to: url)
                }
                return .init(exitCode: scenario == 1 ? 1 : 0, standardOutput: "", standardError: "WARNING native tunnel retry\nDeprecationWarning")
            }
            if scenario == 0 {
                XCTAssertEqual(try provider.screenshot(device, settings: settings), png)
            } else {
                XCTAssertThrowsError(try provider.screenshot(device, settings: settings))
            }
        }
        XCTAssertEqual(Set(temporaryDirectories).count, 5)
        XCTAssertTrue(temporaryDirectories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testProvidersRejectUnauthorizedDevicesWithoutLaunchingScreenshot() throws {
        let runner = DeviceProcessRunner()
        for platform in [VirtualMachinePlatform.android, .iOS] {
            let provider: PhysicalDeviceProvider = platform == .iOS
                ? IOSPhysicalDeviceProvider(toolLocator: locator, processRunner: runner)
                : AndroidPhysicalDeviceProvider(toolLocator: locator, processRunner: runner)
            let device = PhysicalDevice(name: "Phone", identifier: "udid", platform: platform, connectionState: .unauthorized)
            XCTAssertThrowsError(try provider.screenshot(device, settings: AppSettings(iOSScreenshotToolPath: executable.path)))
        }
        XCTAssertEqual(runner.commands.count, 0)
    }

    func testManagerKeepsOtherPlatformWhenOneScanFailsAndRechecksSelectedDevice() throws {
        let android = StubPhysicalProvider(platform: .android)
        android.scanHandler = { throw VirtualMachineProviderError.executableNotFound("adb") }
        let ios = StubPhysicalProvider(platform: .iOS)
        let selected = PhysicalDevice(name: "Phone", identifier: "selected", platform: .iOS, connectionState: .connected)
        ios.scanHandler = { [selected] }
        let manager = PhysicalDeviceManager(providers: [android, ios])
        let result = manager.scan(settings: AppSettings())
        XCTAssertEqual(result.devices, [selected])
        XCTAssertEqual(result.warnings.count, 1)
        let another = PhysicalDevice(name: "Phone", identifier: "another", platform: .iOS, connectionState: .connected)
        ios.scanHandler = { [another] }
        XCTAssertThrowsError(try manager.screenshot(selected, settings: AppSettings()))
        ios.scanHandler = { [PhysicalDevice(name: selected.name, identifier: selected.identifier, platform: .iOS, connectionState: .disconnected)] }
        XCTAssertThrowsError(try manager.screenshot(selected, settings: AppSettings()))
        XCTAssertEqual(ios.screenshotCount, 0)
    }

    func testToolLocatorFindsManagedEnvironmentWithGUIPathAndRejectsInvalidOverride() throws {
        let managed = root.appendingPathComponent("Library/Application Support/PhoneVM/tools/pymobiledevice3/bin/pymobiledevice3")
        try FileManager.default.createDirectory(at: managed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: executable, to: managed)
        let guiLocator = ToolLocator(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: root)
        XCTAssertEqual(guiLocator.pymobiledevice3Executable(), managed)
        XCTAssertNil(guiLocator.pymobiledevice3Executable(customPath: root.appendingPathComponent("missing").path))
        XCTAssertNil(guiLocator.pymobiledevice3Executable(customPath: root.path))
        XCTAssertEqual(guiLocator.pymobiledevice3Executable(customPath: executable.path), executable)
    }

    func testSettingsRemainCompatibleWithExistingDirectories() throws {
        let oldJSON = Data(#"{"customScanDirectories":["file:///tmp/avd/"]}"#.utf8)
        var settings = try JSONDecoder().decode(AppSettings.self, from: oldJSON)
        XCTAssertNil(settings.iOSScreenshotToolPath)
        XCTAssertEqual(settings.customScanDirectories.first?.path, "/tmp/avd")
        settings.iOSScreenshotToolPath = executable.path
        let store = SettingsStore(settingsURL: root.appendingPathComponent("settings.json"))
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testScreenshotPipelineDeduplicatesAndPublishesClipboardOnMainThread() throws {
        let provider = StubPhysicalProvider(platform: .iOS)
        let device = PhysicalDevice(name: "Test iPhone", identifier: "udid", platform: .iOS, connectionState: .connected)
        provider.scanHandler = { [device] }
        let png = try imageData()
        provider.screenshotHandler = { _ in png }
        let copied = expectation(description: "clipboard copied")
        copied.assertForOverFulfill = true
        let model = AppModel(
            settingsStore: SettingsStore(settingsURL: root.appendingPathComponent("settings.json")),
            manager: VirtualMachineManager(providers: []),
            physicalDeviceManager: PhysicalDeviceManager(providers: [provider]),
            copyScreenshot: { data in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(data, png)
                copied.fulfill()
            }
        )
        model.screenshot(device)
        model.screenshot(device)
        XCTAssertTrue(model.isOperating(device))
        wait(for: [copied], timeout: 3)
        XCTAssertEqual(provider.screenshotCount, 1)
        XCTAssertFalse(model.isOperating(device))
        XCTAssertEqual(model.operationMessage, "已复制屏幕截图：Test iPhone")
    }

    func testClipboardFailureDoesNotReportScreenshotSuccess() throws {
        let provider = StubPhysicalProvider(platform: .iOS)
        let device = PhysicalDevice(name: "Phone", identifier: "udid", platform: .iOS, connectionState: .connected)
        provider.scanHandler = { [device] }
        let png = try imageData()
        provider.screenshotHandler = { _ in png }
        let model = AppModel(
            settingsStore: SettingsStore(settingsURL: root.appendingPathComponent("settings.json")),
            manager: VirtualMachineManager(providers: []),
            physicalDeviceManager: PhysicalDeviceManager(providers: [provider]),
            copyScreenshot: { _ in throw VirtualMachineProviderError.processFailed("剪贴板写入失败") }
        )
        let failed = expectation(description: "clipboard failed")
        let subscription = model.$operationErrorMessage.compactMap { $0 }.sink { _ in failed.fulfill() }
        model.screenshot(device)
        wait(for: [failed], timeout: 3)
        XCTAssertFalse(model.operationMessage?.contains("已复制") == true)
        XCTAssertEqual(model.operationErrorMessage, "剪贴板写入失败")
        withExtendedLifetime(subscription) {}
    }

    func testDesktopScreenshotWritesOffMainThreadAndSharesOperationLockWithClipboard() throws {
        let provider = StubPhysicalProvider(platform: .iOS)
        let device = PhysicalDevice(name: "Phone", identifier: "udid", platform: .iOS, connectionState: .connected)
        provider.scanHandler = { [device] }
        let png = try imageData()
        provider.screenshotHandler = { _ in png }
        let directory = root!
        let model = AppModel(
            settingsStore: SettingsStore(settingsURL: root.appendingPathComponent("settings.json")),
            manager: VirtualMachineManager(providers: []),
            physicalDeviceManager: PhysicalDeviceManager(providers: [provider]),
            copyScreenshot: { _ in XCTFail("Desktop action must not change the clipboard") },
            saveScreenshotToDesktop: { data in
                XCTAssertFalse(Thread.isMainThread)
                return try ScreenshotDesktopStore(desktopDirectory: directory).save(data)
            }
        )
        let saved = expectation(description: "saved to desktop")
        let subscription = model.$operationMessage.compactMap { $0 }.sink { message in
            XCTAssertTrue(message.hasPrefix("已保存到桌面：PhoneVM-"))
            saved.fulfill()
        }
        model.screenshot(device, destination: .desktop)
        model.screenshot(device)
        XCTAssertTrue(model.isOperating(device))
        wait(for: [saved], timeout: 3)
        XCTAssertFalse(model.isOperating(device))
        XCTAssertEqual(provider.screenshotCount, 1)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.first)), png)
        withExtendedLifetime(subscription) {}
    }

    func testDesktopWriteFailureShowsErrorAndReleasesDevice() throws {
        let provider = StubPhysicalProvider(platform: .iOS)
        let device = PhysicalDevice(name: "Phone", identifier: "udid", platform: .iOS, connectionState: .connected)
        provider.scanHandler = { [device] }
        let png = try imageData()
        provider.screenshotHandler = { _ in png }
        let model = AppModel(
            settingsStore: SettingsStore(settingsURL: root.appendingPathComponent("settings.json")),
            manager: VirtualMachineManager(providers: []),
            physicalDeviceManager: PhysicalDeviceManager(providers: [provider]),
            copyScreenshot: { _ in XCTFail("Save failure must not fall back to clipboard") },
            saveScreenshotToDesktop: { _ in throw VirtualMachineProviderError.processFailed("桌面写入失败") }
        )
        let failed = expectation(description: "save failed")
        let subscription = model.$operationErrorMessage.compactMap { $0 }.sink { _ in failed.fulfill() }
        model.screenshot(device, destination: .desktop)
        wait(for: [failed], timeout: 3)
        XCTAssertEqual(model.operationErrorMessage, "桌面写入失败")
        XCTAssertFalse(model.operationMessage?.contains("已保存") == true)
        XCTAssertFalse(model.isOperating(device))
        withExtendedLifetime(subscription) {}
    }

    func testSimulatorScreenshotSupportsDesktopDestination() throws {
        let png = try imageData()
        let runner = DeviceProcessRunner()
        runner.binary = { command in
            XCTAssertEqual(command.arguments, ["simctl", "io", "simulator-udid", "screenshot", "-"])
            return .init(exitCode: 0, standardOutput: png, standardError: "")
        }
        let simulator = VirtualMachine(
            id: "simulator", name: "Simulator", identifier: "simulator-udid", platform: .iOS,
            providerID: .iOSSimulator, providerName: "iOS Simulator", location: root,
            metadata: [:], status: .running
        )
        let directory = root!
        let model = AppModel(
            settingsStore: SettingsStore(settingsURL: root.appendingPathComponent("settings.json")),
            manager: VirtualMachineManager(providers: [IOSSimulatorProvider(processRunner: runner)]),
            physicalDeviceManager: PhysicalDeviceManager(providers: []),
            copyScreenshot: { _ in XCTFail("Desktop action must not copy") },
            saveScreenshotToDesktop: { try ScreenshotDesktopStore(desktopDirectory: directory).save($0) }
        )
        let saved = expectation(description: "simulator saved")
        let subscription = model.$operationMessage.compactMap { $0 }.sink { _ in saved.fulfill() }
        model.screenshot(simulator, destination: .desktop)
        wait(for: [saved], timeout: 3)
        XCTAssertTrue(model.operationMessage?.hasPrefix("已保存到桌面") == true)
        XCTAssertFalse(model.isOperating(simulator))
        withExtendedLifetime(subscription) {}
    }

    private func imageData() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func iosRecord(
        udid: String?, platform: String = "iOS", reality: String = "physical",
        tunnel: String = "connected", pairing: String = "paired", developer: String = "enabled", ddi: Bool = true
    ) -> [String: Any] {
        var hardware: [String: Any] = ["platform": platform, "reality": reality, "marketingName": "iPhone"]
        hardware["udid"] = udid
        return [
            "identifier": "core-device-id-must-not-be-used",
            "hardwareProperties": hardware,
            "deviceProperties": ["name": "Test Phone", "osVersionNumber": "26.6.2", "developerModeStatus": developer, "ddiServicesAvailable": ddi],
            "connectionProperties": ["tunnelState": tunnel, "pairingState": pairing]
        ]
    }

    private func writeDeviceList(_ records: [[String: Any]], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: ["result": ["devices": records]]).write(to: url)
    }
}

private final class DeviceProcessRunner: ProcessRunning {
    struct Command {
        let executableURL: URL
        let arguments: [String]
        let timeout: TimeInterval
    }
    var commands: [Command] = []
    var text: ((Command) throws -> ProcessOutput)?
    var binary: ((Command) throws -> ProcessBinaryOutput)?

    func runAndCapture(executableURL: URL, arguments: [String], environment: [String: String]?, timeout: TimeInterval) throws -> ProcessOutput {
        let command = Command(executableURL: executableURL, arguments: arguments, timeout: timeout)
        commands.append(command)
        return try XCTUnwrap(text)(command)
    }

    func runAndCaptureBinary(executableURL: URL, arguments: [String], environment: [String: String]?, timeout: TimeInterval) throws -> ProcessBinaryOutput {
        let command = Command(executableURL: executableURL, arguments: arguments, timeout: timeout)
        commands.append(command)
        return try XCTUnwrap(binary)(command)
    }

    func launchDetached(executableURL: URL, arguments: [String], environment: [String: String]?) throws {
        XCTFail("Unexpected detached launch")
    }
}

private final class StubPhysicalProvider: PhysicalDeviceProvider {
    let platform: VirtualMachinePlatform
    var displayName: String { platform.rawValue }
    var scanHandler: () throws -> [PhysicalDevice] = { [] }
    var screenshotHandler: (PhysicalDevice) throws -> Data = { _ in Data() }
    private(set) var screenshotCount = 0

    init(platform: VirtualMachinePlatform) { self.platform = platform }
    func scan(settings: AppSettings) throws -> [PhysicalDevice] { try scanHandler() }
    func screenshot(_ device: PhysicalDevice, settings: AppSettings) throws -> Data {
        screenshotCount += 1
        return try screenshotHandler(device)
    }
}
