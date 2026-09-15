import Foundation

final class AndroidPhysicalDeviceProvider: PhysicalDeviceProvider {
    let platform: VirtualMachinePlatform = .android
    let displayName = "Android 真机"
    private let toolLocator: ToolLocator
    private let processRunner: any ProcessRunning

    init(toolLocator: ToolLocator = ToolLocator(), processRunner: any ProcessRunning = ProcessRunner()) {
        self.toolLocator = toolLocator
        self.processRunner = processRunner
    }

    func scan(settings: AppSettings) throws -> [PhysicalDevice] {
        let output = try processRunner.runAndCapture(
            executableURL: adb(), arguments: ["devices", "-l"], timeout: 5
        )
        guard output.exitCode == 0 else {
            throw VirtualMachineProviderError.processFailed("读取设备失败：\(output.standardError)")
        }
        var seen = Set<String>()
        return output.standardOutput.split(whereSeparator: \.isNewline).compactMap { line in
            let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard columns.count >= 2,
                  !line.hasPrefix("List of devices"), !line.hasPrefix("*"),
                  !columns[0].hasPrefix("emulator-"), seen.insert(columns[0]).inserted else { return nil }

            let state: PhysicalDeviceConnectionState
            switch columns[1] {
            case "device": state = .connected
            case "offline": state = .disconnected
            case "unauthorized", "no": state = .unauthorized
            default: state = .unknown
            }
            let model = columns.first(where: { $0.hasPrefix("model:") })
                .map { String($0.dropFirst("model:".count)).replacingOccurrences(of: "_", with: " ") }
            return PhysicalDevice(
                name: model ?? columns[0], identifier: columns[0], platform: platform,
                connectionState: state, detail: "Android"
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
        let output = try processRunner.runAndCaptureBinary(
            executableURL: adb(),
            arguments: ["-s", device.identifier, "exec-out", "screencap", "-p"], timeout: 20
        )
        guard output.exitCode == 0 else {
            throw VirtualMachineProviderError.processFailed("Android 截屏失败，请确认设备连接和 USB 调试授权。\n\(output.standardError)")
        }
        try ScreenshotClipboard.validate(output.standardOutput)
        return output.standardOutput
    }

    private func adb() throws -> URL {
        guard let url = toolLocator.adbExecutable() else {
            throw VirtualMachineProviderError.executableNotFound("adb（请安装 Android SDK Platform-Tools）")
        }
        return url
    }
}
