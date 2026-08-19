import Foundation
import XCTest
@testable import PhoneVM

final class PhoneVMTests: XCTestCase {
    func testKeyValueParserKeepsTextAfterFirstSeparator() {
        let values = KeyValueFileParser.parse("""
        # comment
        target = android-35
        image.sysdir.1 = system-images;android-35;google_apis_playstore;arm64-v8a
        ignored
        """)

        XCTAssertEqual(values["target"], "android-35")
        XCTAssertEqual(values["image.sysdir.1"], "system-images;android-35;google_apis_playstore;arm64-v8a")
        XCTAssertNil(values["ignored"])
    }

    func testAndroidAVDUsesDisplayNameAndStableDirectoryID() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let avdDirectory = home.appendingPathComponent(".android/avd/Pixel_8.avd", isDirectory: true)
        try FileManager.default.createDirectory(at: avdDirectory, withIntermediateDirectories: true)
        try """
        AvdId=Pixel_8
        avd.ini.displayname=Personal Pixel
        target=android-35
        """.write(
            to: avdDirectory.appendingPathComponent("config.ini"),
            atomically: true,
            encoding: .utf8
        )

        let provider = AndroidAVDProvider(
            toolLocator: ToolLocator(environment: ["PATH": ""], homeDirectory: home)
        )
        let machine = try XCTUnwrap(provider.scan(
            context: VirtualMachineScanContext(customDirectories: [], includeRuntimeStatus: false)
        ).first)

        XCTAssertEqual(machine.name, "Personal Pixel")
        XCTAssertEqual(machine.identifier, "Pixel_8")
        XCTAssertEqual(machine.id, "androidAVD:\(avdDirectory.standardizedFileURL.path)")
        XCTAssertEqual(machine.status, .stopped)
    }

    func testAndroidAVDResolvesRelativePathFromCustomDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let scanRoot = root.appendingPathComponent("custom-avd", isDirectory: true)
        let avdDirectory = scanRoot.appendingPathComponent("Devices/Relative_Pixel.avd", isDirectory: true)
        try FileManager.default.createDirectory(at: avdDirectory, withIntermediateDirectories: true)
        try "AvdId=Relative_Pixel".write(
            to: avdDirectory.appendingPathComponent("config.ini"),
            atomically: true,
            encoding: .utf8
        )
        try """
        avdId=Relative_Pixel
        avd.ini.displayname=Relative Pixel
        path.rel=Devices/Relative_Pixel.avd
        """.write(
            to: scanRoot.appendingPathComponent("Relative_Pixel.ini"),
            atomically: true,
            encoding: .utf8
        )

        let provider = AndroidAVDProvider(
            toolLocator: ToolLocator(environment: ["PATH": ""], homeDirectory: root)
        )
        let machine = try XCTUnwrap(provider.scan(
            context: VirtualMachineScanContext(customDirectories: [scanRoot], includeRuntimeStatus: false)
        ).first)

        XCTAssertEqual(machine.name, "Relative Pixel")
        XCTAssertEqual(machine.identifier, "Relative_Pixel")
        XCTAssertEqual(machine.location.standardizedFileURL, avdDirectory.standardizedFileURL)
    }

    func testIOSSimulatorScanMapsRuntimeAndStableUDID() throws {
        let runner = FakeProcessRunner(outputs: [ProcessOutput(exitCode: 0, standardOutput: simulatorJSON, standardError: "")])
        let provider = IOSSimulatorProvider(processRunner: runner)

        let machines = try provider.scan(
            context: VirtualMachineScanContext(customDirectories: [], includeRuntimeStatus: true)
        )

        XCTAssertEqual(machines.count, 3)
        let booted = try XCTUnwrap(machines.first { $0.identifier == "BOOTED-UDID" })
        XCTAssertEqual(booted.id, "iOSSimulator:BOOTED-UDID")
        XCTAssertEqual(booted.name, "iPhone 16")
        XCTAssertEqual(booted.status, .running)
        XCTAssertEqual(booted.metadata["runtime"], "iOS 18.5")
        XCTAssertEqual(booted.location.path, "/tmp/BOOTED-UDID")

        let unavailable = try XCTUnwrap(machines.first { $0.identifier == "UNAVAILABLE-UDID" })
        XCTAssertEqual(unavailable.status, .unavailable)
        XCTAssertFalse(machines.contains { $0.name == "Apple TV" })
    }

    func testIOSSimulatorStartAndStopUseExpectedCommands() throws {
        let runner = FakeProcessRunner(outputs: [
            ProcessOutput(exitCode: 0, standardOutput: simulatorJSON, standardError: ""),
            ProcessOutput(exitCode: 0, standardOutput: "", standardError: ""),
            ProcessOutput(exitCode: 0, standardOutput: "", standardError: "")
        ])
        let provider = IOSSimulatorProvider(processRunner: runner)
        let machine = try XCTUnwrap(provider.scan(
            context: VirtualMachineScanContext(customDirectories: [], includeRuntimeStatus: true)
        ).first { $0.identifier == "SHUTDOWN-UDID" })

        try provider.start(machine)
        var runningMachine = machine
        runningMachine.status = .running
        try provider.stop(runningMachine)

        XCTAssertEqual(runner.capturedCommands.map(\.arguments), [
            ["simctl", "list", "devices", "--json"],
            ["simctl", "boot", "SHUTDOWN-UDID"],
            ["simctl", "shutdown", "SHUTDOWN-UDID"]
        ])
        XCTAssertEqual(runner.detachedCommands.map(\.arguments), [
            ["-a", "Simulator", "--args", "-CurrentDeviceUDID", "SHUTDOWN-UDID"]
        ])
    }

    func testIOSSimulatorScreenshotUsesSimctlIO() throws {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])
        let runner = FakeProcessRunner(
            outputs: [ProcessOutput(exitCode: 0, standardOutput: simulatorJSON, standardError: "")],
            binaryOutputs: [ProcessBinaryOutput(exitCode: 0, standardOutput: pngData, standardError: "")]
        )
        let provider = IOSSimulatorProvider(processRunner: runner)
        var machine = try XCTUnwrap(provider.scan(
            context: VirtualMachineScanContext(customDirectories: [], includeRuntimeStatus: true)
        ).first { $0.identifier == "BOOTED-UDID" })
        machine.status = .running

        let imageData = try provider.screenshot(machine)

        XCTAssertEqual(imageData, pngData)
        XCTAssertEqual(runner.capturedCommands.last?.arguments, [
            "simctl", "io", "BOOTED-UDID", "screenshot", "-"
        ])
    }

    func testIOSSimulatorScreenshotRejectsStoppedDevice() throws {
        let runner = FakeProcessRunner(outputs: [
            ProcessOutput(exitCode: 0, standardOutput: simulatorJSON, standardError: "")
        ])
        let provider = IOSSimulatorProvider(processRunner: runner)
        let machine = try XCTUnwrap(provider.scan(
            context: VirtualMachineScanContext(customDirectories: [], includeRuntimeStatus: true)
        ).first { $0.identifier == "SHUTDOWN-UDID" })

        XCTAssertThrowsError(try provider.screenshot(machine))
    }

    func testSettingsStoreRoundTripsCustomDirectories() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let settingsURL = root.appendingPathComponent("settings/settings.json")
        let store = SettingsStore(settingsURL: settingsURL)
        let settings = AppSettings(customScanDirectories: [root.appendingPathComponent("avd", isDirectory: true)])

        try store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testProcessRunnerTerminatesTimedOutCommand() {
        let startedAt = Date()

        XCTAssertThrowsError(
            try ProcessRunner().runAndCapture(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"],
                timeout: 0.05
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("执行超时"))
        }

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhoneVMTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class FakeProcessRunner: ProcessRunning {
    struct Command: Equatable {
        let executableURL: URL
        let arguments: [String]
    }

    private var outputs: [ProcessOutput]
    private var binaryOutputs: [ProcessBinaryOutput]
    private(set) var capturedCommands: [Command] = []
    private(set) var detachedCommands: [Command] = []

    init(outputs: [ProcessOutput] = [], binaryOutputs: [ProcessBinaryOutput] = []) {
        self.outputs = outputs
        self.binaryOutputs = binaryOutputs
    }

    func runAndCapture(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) throws -> ProcessOutput {
        capturedCommands.append(Command(executableURL: executableURL, arguments: arguments))
        guard !outputs.isEmpty else {
            XCTFail("Unexpected process invocation: \(arguments)")
            return ProcessOutput(exitCode: 1, standardOutput: "", standardError: "")
        }
        return outputs.removeFirst()
    }

    func runAndCaptureBinary(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) throws -> ProcessBinaryOutput {
        capturedCommands.append(Command(executableURL: executableURL, arguments: arguments))
        guard !binaryOutputs.isEmpty else {
            XCTFail("Unexpected binary process invocation: \(arguments)")
            return ProcessBinaryOutput(exitCode: 1, standardOutput: Data(), standardError: "")
        }
        return binaryOutputs.removeFirst()
    }

    func launchDetached(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?
    ) throws {
        detachedCommands.append(Command(executableURL: executableURL, arguments: arguments))
    }
}

private let simulatorJSON = """
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
      {
        "name": "iPhone 16",
        "udid": "BOOTED-UDID",
        "state": "Booted",
        "isAvailable": true,
        "osVersion": "18.5",
        "dataPath": "/tmp/BOOTED-UDID",
        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
      },
      {
        "name": "iPhone 16",
        "udid": "SHUTDOWN-UDID",
        "state": "Shutdown",
        "isAvailable": true,
        "osVersion": "18.5",
        "dataPath": "/tmp/SHUTDOWN-UDID"
      },
      {
        "name": "Unavailable iPhone",
        "udid": "UNAVAILABLE-UDID",
        "state": "Shutdown",
        "isAvailable": false,
        "osVersion": "18.5",
        "dataPath": "/tmp/UNAVAILABLE-UDID"
      }
    ],
    "com.apple.CoreSimulator.SimRuntime.tvOS-18-5": [
      {
        "name": "Apple TV",
        "udid": "TV-UDID",
        "state": "Shutdown",
        "isAvailable": true
      }
    ]
  }
}
"""
