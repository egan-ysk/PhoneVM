import Foundation

final class IOSPhysicalDeviceProvider: PhysicalDeviceProvider {
    let platform: VirtualMachinePlatform = .iOS
    let displayName = "iOS 真机"
    private let toolLocator: ToolLocator
    private let processRunner: any ProcessRunning
    private let fileManager: FileManager

    init(
        toolLocator: ToolLocator = ToolLocator(), processRunner: any ProcessRunning = ProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.toolLocator = toolLocator
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    func scan(settings: AppSettings) throws -> [PhysicalDevice] {
        guard let xcrun = toolLocator.xcrunExecutable() else {
            throw VirtualMachineProviderError.executableNotFound("xcrun（请安装并选择完整 Xcode）")
        }
        let directory = try temporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let jsonURL = directory.appendingPathComponent("devices.json")
        let output = try processRunner.runAndCapture(
            executableURL: xcrun,
            arguments: ["devicectl", "list", "devices", "--timeout", "10", "--json-output", jsonURL.path],
            timeout: 15
        )
        guard output.exitCode == 0 else {
            throw VirtualMachineProviderError.processFailed("读取设备失败，请确认已安装并选择完整 Xcode。\n\(failureDetail(output))")
        }
        let response: DeviceList
        do {
            response = try JSONDecoder().decode(DeviceList.self, from: Data(contentsOf: jsonURL))
        } catch {
            throw VirtualMachineProviderError.processFailed("无法解析 devicectl 设备列表")
        }
        let hasScreenshotTool = toolLocator.pymobiledevice3Executable(customPath: settings.iOSScreenshotToolPath) != nil
        var seen = Set<String>()
        return response.result.devices.compactMap { record in
            let hardware = record.hardwareProperties
            guard ["iOS", "iPadOS"].contains(hardware.platform),
                  hardware.reality == nil || hardware.reality == "physical",
                  let udid = hardware.udid, !udid.isEmpty, seen.insert(udid).inserted else { return nil }
            let connection = record.connectionProperties
            let properties = record.deviceProperties
            let state: PhysicalDeviceConnectionState
            if let pairing = connection.pairingState, pairing != "paired" {
                state = .unauthorized
            } else {
                switch connection.tunnelState {
                case "connected": state = .connected
                case "disconnected", "unavailable": state = .disconnected
                default: state = .unknown
                }
            }
            let blockedReason: String?
            if properties.developerModeStatus == "disabled" {
                blockedReason = "请在设备上开启开发者模式，然后刷新列表"
            } else if properties.ddiServicesAvailable == false {
                blockedReason = "请在 Xcode 的 Devices and Simulators 中完成设备准备，然后刷新列表"
            } else if !hasScreenshotTool {
                blockedReason = "未找到 iOS 截屏工具，请在设置中配置 pymobiledevice3"
            } else {
                blockedReason = nil
            }
            return PhysicalDevice(
                name: properties.name ?? hardware.marketingName ?? "iOS 设备",
                identifier: udid, platform: platform, connectionState: state,
                detail: [hardware.marketingName, properties.osVersionNumber.map { "iOS \($0)" }]
                    .compactMap { $0 }.joined(separator: " · "),
                screenshotBlockedReason: blockedReason
            )
        }
    }

    func screenshot(_ device: PhysicalDevice, settings: AppSettings) throws -> Data {
        guard device.platform == platform else {
            throw VirtualMachineProviderError.unsupportedOperation("设备平台不匹配")
        }
        if let reason = device.screenshotUnavailableReason {
            throw VirtualMachineProviderError.unsupportedOperation(reason)
        }
        guard let tool = toolLocator.pymobiledevice3Executable(customPath: settings.iOSScreenshotToolPath) else {
            throw VirtualMachineProviderError.executableNotFound("pymobiledevice3，请在设置中配置 iOS 截屏工具")
        }
        let directory = try temporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("screenshot.png")
        let output = try processRunner.runAndCapture(
            executableURL: tool,
            arguments: ["developer", "dvt", "screenshot", "--udid", device.identifier, imageURL.path],
            environment: ["NO_COLOR": "1", "TERM": "dumb"], timeout: 45
        )
        // pymobiledevice3 的 native tunnel 重试和 Python 警告会写 stderr；以退出状态及图片为准。
        guard output.exitCode == 0 else {
            throw VirtualMachineProviderError.processFailed(
                "iOS 截屏失败，请确认设备已连接、解锁并开启开发者模式。\n\(failureDetail(output))"
            )
        }
        guard let data = try? Data(contentsOf: imageURL) else {
            throw VirtualMachineProviderError.processFailed("iOS 截屏未生成图片，请确认 Xcode 已完成设备准备后重试")
        }
        try ScreenshotClipboard.validate(data)
        return data
    }

    private func temporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent("PhoneVM-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func failureDetail(_ output: ProcessOutput) -> String {
        let text = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (text.isEmpty ? output.standardOutput : text).split(whereSeparator: \.isNewline).last
        // Python traceback 可能很长，菜单只显示最后一行原因，不让整段堆栈撑满屏幕。
        return detail.map { String($0.prefix(240)) } ?? "命令退出码：\(output.exitCode)"
    }
}

private struct DeviceList: Decodable {
    let result: Result
    struct Result: Decodable { let devices: [Device] }
    struct Device: Decodable {
        let hardwareProperties: Hardware
        let deviceProperties: Properties
        let connectionProperties: Connection
    }
    struct Hardware: Decodable {
        let platform: String
        let reality: String?
        let udid: String?
        let marketingName: String?
    }
    struct Properties: Decodable {
        let name: String?
        let osVersionNumber: String?
        let developerModeStatus: String?
        let ddiServicesAvailable: Bool?
    }
    struct Connection: Decodable {
        let pairingState: String?
        let tunnelState: String?
    }
}
