import Foundation

final class GenymotionProvider: VirtualMachineProvider {
    let id: VirtualMachineProviderID = .genymotion
    let displayName = "Genymotion"
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
        let roots = defaultRoots() + context.customDirectories
        var seen = Set<String>()
        var machines: [VirtualMachine] = []

        for directory in roots.flatMap(genymotionCandidates(in:)).uniqueStandardized() {
            guard seen.insert(directory.path).inserted else {
                continue
            }

            machines.append(
                VirtualMachine(
                    id: "\(id.rawValue):\(directory.lastPathComponent)",
                    name: directory.lastPathComponent,
                    platform: platform,
                    providerID: id,
                    providerName: displayName,
                    location: directory,
                    metadata: genymotionMetadata(in: directory),
                    status: .unknown
                )
            )
        }

        return machines.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func start(_ virtualMachine: VirtualMachine) throws {
        guard let player = toolLocator.genymotionPlayerExecutable() else {
            throw VirtualMachineProviderError.executableNotFound("Genymotion player")
        }

        try processRunner.launchDetached(
            executableURL: player,
            arguments: ["--vm-name", virtualMachine.name]
        )
    }

    func stop(_ virtualMachine: VirtualMachine) throws {
        throw VirtualMachineProviderError.unsupportedOperation("Genymotion 停止操作暂未提供稳定实现，请在虚拟机窗口中关闭")
    }

    func status(for virtualMachine: VirtualMachine) throws -> VirtualMachineStatus {
        .unknown
    }

    private func defaultRoots() -> [URL] {
        [
            toolLocator.homeDirectory.appendingPathComponent("Library/Genymobile/Genymotion/deployed", isDirectory: true)
        ]
    }

    private func genymotionCandidates(in root: URL) -> [URL] {
        let standardizedRoot = root.standardizedFileURL
        guard fileManager.directoryExists(at: standardizedRoot) else {
            return []
        }

        if isGenymotionMachineDirectory(standardizedRoot) {
            return [standardizedRoot]
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: standardizedRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.filter(isGenymotionMachineDirectory)
    }

    private func isGenymotionMachineDirectory(_ directory: URL) -> Bool {
        guard fileManager.directoryExists(at: directory),
              let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return false
        }

        return children.contains { file in
            file.pathExtension == "vbox" || file.pathExtension == "gminfo"
        }
    }

    private func genymotionMetadata(in directory: URL) -> [String: String] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var metadata: [String: String] = [:]
        if let vbox = children.first(where: { $0.pathExtension == "vbox" }) {
            metadata["vbox"] = vbox.lastPathComponent
        }
        return metadata
    }
}
