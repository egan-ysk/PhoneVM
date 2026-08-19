import Foundation

final class IOSSimulatorProvider: VirtualMachineProvider {
    let id: VirtualMachineProviderID = .iOSSimulator
    let displayName = "iOS Simulator"
    let platform: VirtualMachinePlatform = .iOS

    private let toolLocator: ToolLocator
    private let processRunner: any ProcessRunning

    init(
        toolLocator: ToolLocator = ToolLocator(),
        processRunner: any ProcessRunning = ProcessRunner()
    ) {
        self.toolLocator = toolLocator
        self.processRunner = processRunner
    }

    func scan(context: VirtualMachineScanContext) throws -> [VirtualMachine] {
        guard toolLocator.xcrunExecutable() != nil else {
            return []
        }

        return try simulatorDevices().compactMap { runtimeIdentifier, device in
            guard runtimeIdentifier.hasPrefix("com.apple.CoreSimulator.SimRuntime.iOS-") else {
                return nil
            }

            return virtualMachine(
                from: device,
                runtimeIdentifier: runtimeIdentifier,
                includeRuntimeStatus: context.includeRuntimeStatus
            )
        }
        .sorted { left, right in
            let runtimeOrder = (left.metadata["runtime"] ?? "").localizedStandardCompare(right.metadata["runtime"] ?? "")
            if runtimeOrder != .orderedSame {
                return runtimeOrder == .orderedAscending
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    func start(_ virtualMachine: VirtualMachine) throws {
        try validate(virtualMachine)
        guard virtualMachine.status != .unavailable else {
            throw VirtualMachineProviderError.invalidVirtualMachine("iOS Simulator 设备不可用")
        }

        let currentStatus = virtualMachine.status == .unknown
            ? try status(for: virtualMachine)
            : virtualMachine.status
        if currentStatus == .unavailable {
            throw VirtualMachineProviderError.invalidVirtualMachine("iOS Simulator 设备不可用")
        }

        if currentStatus != .running && currentStatus != .starting {
            let output = try runSimctl(arguments: ["simctl", "boot", virtualMachine.identifier], timeout: 30)
            guard output.exitCode == 0 else {
                throw VirtualMachineProviderError.processFailed(output.message(or: "启动 iOS Simulator 失败"))
            }
        }

        guard let open = toolLocator.openExecutable() else {
            throw VirtualMachineProviderError.executableNotFound("open")
        }
        try processRunner.launchDetached(
            executableURL: open,
            arguments: ["-a", "Simulator", "--args", "-CurrentDeviceUDID", virtualMachine.identifier]
        )
    }

    func stop(_ virtualMachine: VirtualMachine) throws {
        try validate(virtualMachine)
        let currentStatus = virtualMachine.status == .unknown
            ? try status(for: virtualMachine)
            : virtualMachine.status

        switch currentStatus {
        case .stopped:
            return
        case .unavailable:
            throw VirtualMachineProviderError.invalidVirtualMachine("iOS Simulator 设备不可用")
        case .starting, .running, .stopping, .unknown:
            let output = try runSimctl(arguments: ["simctl", "shutdown", virtualMachine.identifier])
            guard output.exitCode == 0 else {
                throw VirtualMachineProviderError.processFailed(output.message(or: "停止 iOS Simulator 失败"))
            }
        }
    }

    func status(for virtualMachine: VirtualMachine) throws -> VirtualMachineStatus {
        try validate(virtualMachine)
        guard let match = try simulatorDevices().first(where: { $0.device.udid == virtualMachine.identifier }) else {
            return .unavailable
        }

        return status(for: match.device)
    }

    func screenshot(_ virtualMachine: VirtualMachine) throws -> Data {
        try validate(virtualMachine)
        guard virtualMachine.status == .running else {
            throw VirtualMachineProviderError.unsupportedOperation("仅运行中的设备支持截屏")
        }

        let output = try runSimctlBinary(
            arguments: ["simctl", "io", virtualMachine.identifier, "screenshot", "-"],
            timeout: 15
        )
        guard output.exitCode == 0, !output.standardOutput.isEmpty else {
            throw VirtualMachineProviderError.processFailed(output.message(or: "截取 iOS Simulator 屏幕失败"))
        }

        return output.standardOutput
    }

    private func simulatorDevices() throws -> [(runtimeIdentifier: String, device: SimctlDevice)] {
        guard let xcrun = toolLocator.xcrunExecutable() else {
            throw VirtualMachineProviderError.executableNotFound("xcrun")
        }

        let output = try processRunner.runAndCapture(
            executableURL: xcrun,
            arguments: ["simctl", "list", "devices", "--json"]
        )
        guard output.exitCode == 0 else {
            throw VirtualMachineProviderError.processFailed(output.message(or: "读取 iOS Simulator 设备列表失败"))
        }

        do {
            let response = try JSONDecoder().decode(SimctlDevicesResponse.self, from: Data(output.standardOutput.utf8))
            return response.devices.flatMap { runtimeIdentifier, devices in
                devices.map { (runtimeIdentifier, $0) }
            }
        } catch {
            throw VirtualMachineProviderError.processFailed("无法解析 iOS Simulator 设备列表")
        }
    }

    private func virtualMachine(
        from device: SimctlDevice,
        runtimeIdentifier: String,
        includeRuntimeStatus: Bool
    ) -> VirtualMachine {
        var metadata = [
            "runtime": device.runtimeName(for: runtimeIdentifier),
            "runtimeIdentifier": runtimeIdentifier,
            "udid": device.udid
        ]
        if let deviceTypeIdentifier = device.deviceTypeIdentifier, !deviceTypeIdentifier.isEmpty {
            metadata["deviceTypeIdentifier"] = deviceTypeIdentifier
        }

        let location = device.dataPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? toolLocator.homeDirectory
                .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
                .appendingPathComponent(device.udid, isDirectory: true)

        return VirtualMachine(
            id: "\(id.rawValue):\(device.udid)",
            name: device.name,
            identifier: device.udid,
            platform: platform,
            providerID: id,
            providerName: displayName,
            location: location.standardizedFileURL,
            metadata: metadata,
            status: includeRuntimeStatus ? status(for: device) : .unknown
        )
    }

    private func status(for device: SimctlDevice) -> VirtualMachineStatus {
        guard device.isAvailable else {
            return .unavailable
        }

        switch device.state.lowercased() {
        case "booted":
            return .running
        case "booting", "creating":
            return .starting
        case "shutdown":
            return .stopped
        case "shutting down":
            return .stopping
        default:
            return .unknown
        }
    }

    private func runSimctl(arguments: [String], timeout: TimeInterval = 10) throws -> ProcessOutput {
        guard let xcrun = toolLocator.xcrunExecutable() else {
            throw VirtualMachineProviderError.executableNotFound("xcrun")
        }
        return try processRunner.runAndCapture(executableURL: xcrun, arguments: arguments, timeout: timeout)
    }

    private func runSimctlBinary(arguments: [String], timeout: TimeInterval = 10) throws -> ProcessBinaryOutput {
        guard let xcrun = toolLocator.xcrunExecutable() else {
            throw VirtualMachineProviderError.executableNotFound("xcrun")
        }
        return try processRunner.runAndCaptureBinary(executableURL: xcrun, arguments: arguments, timeout: timeout)
    }

    private func validate(_ virtualMachine: VirtualMachine) throws {
        guard virtualMachine.providerID == id else {
            throw VirtualMachineProviderError.invalidVirtualMachine("虚拟机类型不匹配")
        }
    }
}

private struct SimctlDevicesResponse: Decodable {
    let devices: [String: [SimctlDevice]]
}

private struct SimctlDevice: Decodable {
    let name: String
    let udid: String
    let state: String
    let isAvailableValue: Bool?
    let availability: String?
    let osVersion: String?
    let dataPath: String?
    let deviceTypeIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case name
        case udid
        case state
        case isAvailableValue = "isAvailable"
        case availability
        case osVersion
        case dataPath
        case deviceTypeIdentifier
    }

    var isAvailable: Bool {
        if let isAvailableValue {
            return isAvailableValue
        }
        return !(availability?.localizedCaseInsensitiveContains("unavailable") ?? false)
    }

    func runtimeName(for runtimeIdentifier: String) -> String {
        if let osVersion, !osVersion.isEmpty {
            return "iOS \(osVersion)"
        }

        let prefix = "com.apple.CoreSimulator.SimRuntime."
        let rawRuntime = runtimeIdentifier.hasPrefix(prefix)
            ? String(runtimeIdentifier.dropFirst(prefix.count))
            : runtimeIdentifier
        let components = rawRuntime.split(separator: "-")
        guard let platform = components.first else {
            return runtimeIdentifier
        }
        let version = components.dropFirst().joined(separator: ".")
        return version.isEmpty ? String(platform) : "\(platform) \(version)"
    }
}

private extension ProcessOutput {
    func message(or fallback: String) -> String {
        let errorText = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !errorText.isEmpty {
            return errorText
        }

        let outputText = standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return outputText.isEmpty ? fallback : outputText
    }
}

private extension ProcessBinaryOutput {
    func message(or fallback: String) -> String {
        let errorText = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !errorText.isEmpty {
            return errorText
        }

        let outputText = String(data: standardOutput.prefix(512), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return outputText.isEmpty ? fallback : outputText
    }
}
