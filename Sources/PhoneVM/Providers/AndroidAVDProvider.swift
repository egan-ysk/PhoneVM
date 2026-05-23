import Foundation

final class AndroidAVDProvider: VirtualMachineProvider {
    let id: VirtualMachineProviderID = .androidAVD
    let displayName = "Android AVD"
    let platform: VirtualMachinePlatform = .android

    private let fileManager: FileManager
    private let toolLocator: ToolLocator
    private let processRunner: ProcessRunner

    init(
        fileManager: FileManager = .default,
        toolLocator: ToolLocator = ToolLocator(),
        processRunner: ProcessRunner = ProcessRunner()
    ) {
        self.fileManager = fileManager
        self.toolLocator = toolLocator
        self.processRunner = processRunner
    }

    func scan(context: VirtualMachineScanContext) throws -> [VirtualMachine] {
        let runningDevices = context.includeRuntimeStatus ? runningAVDDevices() : [:]
        let descriptors = avdDescriptors(customDirectories: context.customDirectories)

        return descriptors.map { descriptor in
            var metadata = descriptor.metadata
            if let serial = runningDevices?[descriptor.name] {
                metadata["serial"] = serial
            }

            return VirtualMachine(
                id: "\(id.rawValue):\(descriptor.name)",
                name: descriptor.name,
                platform: platform,
                providerID: id,
                providerName: displayName,
                location: descriptor.directory,
                metadata: metadata,
                status: status(for: descriptor.name, runningDevices: runningDevices)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func start(_ virtualMachine: VirtualMachine) throws {
        guard virtualMachine.providerID == id else {
            throw VirtualMachineProviderError.invalidVirtualMachine("虚拟机类型不匹配")
        }
        guard let emulator = toolLocator.androidEmulatorExecutable() else {
            throw VirtualMachineProviderError.executableNotFound("emulator")
        }

        try processRunner.launchDetached(
            executableURL: emulator,
            arguments: ["-avd", virtualMachine.name]
        )
    }

    func stop(_ virtualMachine: VirtualMachine) throws {
        guard let adb = toolLocator.adbExecutable() else {
            throw VirtualMachineProviderError.executableNotFound("adb")
        }

        let serial = virtualMachine.metadata["serial"] ?? runningAVDDevices()?[virtualMachine.name]
        guard let serial else {
            throw VirtualMachineProviderError.unsupportedOperation("未找到正在运行的模拟器实例")
        }

        let output = try processRunner.runAndCapture(
            executableURL: adb,
            arguments: ["-s", serial, "emu", "kill"],
            timeout: 5
        )

        guard output.exitCode == 0 else {
            throw VirtualMachineProviderError.processFailed(output.standardError.trimmedOrDefault("停止模拟器失败"))
        }
    }

    func status(for virtualMachine: VirtualMachine) throws -> VirtualMachineStatus {
        let runningDevices = runningAVDDevices()
        return status(for: virtualMachine.name, runningDevices: runningDevices)
    }

    private func status(for name: String, runningDevices: [String: String]?) -> VirtualMachineStatus {
        guard let runningDevices else {
            return .unknown
        }
        return runningDevices[name] == nil ? .stopped : .running
    }

    private func avdDescriptors(customDirectories: [URL]) -> [AVDDescriptor] {
        let roots = defaultAVDRoots() + customDirectories
        let candidates = roots.flatMap(avdCandidates(in:)).uniqueStandardized()
        var descriptors: [AVDDescriptor] = []
        var seen = Set<String>()

        for directory in candidates where fileManager.directoryExists(at: directory) {
            let descriptor = descriptor(fromAVDDirectory: directory)
            guard seen.insert(descriptor.directory.path).inserted else {
                continue
            }
            descriptors.append(descriptor)
        }

        for iniFile in iniFiles(in: roots) {
            guard let descriptor = descriptor(fromINIFile: iniFile),
                  seen.insert(descriptor.directory.path).inserted else {
                continue
            }
            descriptors.append(descriptor)
        }

        return descriptors
    }

    private func defaultAVDRoots() -> [URL] {
        [
            toolLocator.homeDirectory.appendingPathComponent(".android/avd", isDirectory: true)
        ]
    }

    private func avdCandidates(in root: URL) -> [URL] {
        let standardizedRoot = root.standardizedFileURL
        var candidates: [URL] = []

        if standardizedRoot.pathExtension == "avd" {
            candidates.append(standardizedRoot)
        }

        let nestedAVDRoot = standardizedRoot.appendingPathComponent("avd", isDirectory: true)
        if fileManager.directoryExists(at: nestedAVDRoot) {
            candidates.append(contentsOf: childAVDDirectories(in: nestedAVDRoot))
        }

        candidates.append(contentsOf: childAVDDirectories(in: standardizedRoot))
        return candidates
    }

    private func childAVDDirectories(in root: URL) -> [URL] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.filter { url in
            url.pathExtension == "avd" && fileManager.directoryExists(at: url)
        }
    }

    private func iniFiles(in roots: [URL]) -> [URL] {
        roots.flatMap { root -> [URL] in
            let iniRoot = root.pathExtension == "avd" ? root.deletingLastPathComponent() : root
            guard let children = try? fileManager.contentsOfDirectory(
                at: iniRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            return children.filter { $0.pathExtension == "ini" }
        }
        .uniqueStandardized()
    }

    private func descriptor(fromINIFile iniFile: URL) -> AVDDescriptor? {
        let values = KeyValueFileParser.parseFile(at: iniFile)
        let directory: URL?

        if let path = values["path"], !path.isEmpty {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else if let relativePath = values["path.rel"], !relativePath.isEmpty {
            directory = toolLocator.homeDirectory
                .appendingPathComponent(".android", isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: true)
        } else {
            directory = nil
        }

        guard let directory, fileManager.directoryExists(at: directory) else {
            return nil
        }

        let config = KeyValueFileParser.parseFile(at: directory.appendingPathComponent("config.ini"))
        let name = values["avd.ini.displayname"] ?? values["avdId"] ?? iniFile.deletingPathExtension().lastPathComponent
        return AVDDescriptor(name: name, directory: directory.standardizedFileURL, metadata: avdMetadata(from: config))
    }

    private func descriptor(fromAVDDirectory directory: URL) -> AVDDescriptor {
        let config = KeyValueFileParser.parseFile(at: directory.appendingPathComponent("config.ini"))
        let fallbackName = directory.deletingPathExtension().lastPathComponent
        let name = config["AvdId"] ?? config["avd.ini.displayname"] ?? fallbackName
        return AVDDescriptor(name: name, directory: directory.standardizedFileURL, metadata: avdMetadata(from: config))
    }

    private func avdMetadata(from config: [String: String]) -> [String: String] {
        var metadata: [String: String] = [:]

        for key in ["target", "abi.type", "hw.device.name", "PlayStore.enabled"] {
            if let value = config[key], !value.isEmpty {
                metadata[key] = value
            }
        }

        if let target = config["target"], let apiLevel = apiLevel(from: target) {
            metadata["apiLevel"] = apiLevel
        }

        return metadata
    }

    private func apiLevel(from target: String) -> String? {
        guard let range = target.range(of: "android-") else {
            return nil
        }

        let suffix = target[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    private func runningAVDDevices() -> [String: String]? {
        guard let adb = toolLocator.adbExecutable(),
              let devicesOutput = try? processRunner.runAndCapture(executableURL: adb, arguments: ["devices"], timeout: 4),
              devicesOutput.exitCode == 0 else {
            return nil
        }

        let serials = devicesOutput.standardOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let columns = line.split(whereSeparator: \.isWhitespace)
                guard columns.count >= 2,
                      columns[0].hasPrefix("emulator-"),
                      columns[1] == "device" else {
                    return nil
                }
                return String(columns[0])
            }

        var result: [String: String] = [:]
        for serial in serials {
            guard let avdName = avdName(forSerial: serial, adb: adb) else {
                continue
            }
            result[avdName] = serial
        }
        return result
    }

    private func avdName(forSerial serial: String, adb: URL) -> String? {
        guard let output = try? processRunner.runAndCapture(
            executableURL: adb,
            arguments: ["-s", serial, "emu", "avd", "name"],
            timeout: 3
        ), output.exitCode == 0 else {
            return nil
        }

        return output.standardOutput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "OK" }
    }
}

private struct AVDDescriptor {
    let name: String
    let directory: URL
    let metadata: [String: String]
}

private extension String {
    func trimmedOrDefault(_ defaultValue: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    }
}
