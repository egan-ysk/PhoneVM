import AppKit
import Foundation

final class VirtualMachineManager {
    private let providers: [VirtualMachineProvider]

    init(providers: [VirtualMachineProvider] = [
        AndroidAVDProvider(),
        GenymotionProvider()
    ]) {
        self.providers = providers
    }

    func scan(settings: AppSettings, includeRuntimeStatus: Bool = true) throws -> [VirtualMachine] {
        let context = VirtualMachineScanContext(
            customDirectories: settings.customScanDirectories,
            includeRuntimeStatus: includeRuntimeStatus
        )

        var result: [VirtualMachine] = []
        for provider in providers {
            result.append(contentsOf: try provider.scan(context: context))
        }

        return result.sorted { left, right in
            if left.platform != right.platform {
                return left.platform.rawValue < right.platform.rawValue
            }
            if left.providerName != right.providerName {
                return left.providerName < right.providerName
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    func start(_ virtualMachine: VirtualMachine) throws {
        try provider(for: virtualMachine).start(virtualMachine)
    }

    func stop(_ virtualMachine: VirtualMachine) throws {
        try provider(for: virtualMachine).stop(virtualMachine)
    }

    func restart(_ virtualMachine: VirtualMachine) throws {
        let provider = try provider(for: virtualMachine)
        try provider.stop(virtualMachine)
        Thread.sleep(forTimeInterval: 1.0)
        try provider.start(virtualMachine)
    }

    func refreshStatus(for virtualMachine: VirtualMachine) throws -> VirtualMachineStatus {
        try provider(for: virtualMachine).status(for: virtualMachine)
    }

    func revealInFinder(_ virtualMachine: VirtualMachine) {
        NSWorkspace.shared.activateFileViewerSelecting([virtualMachine.location])
    }

    private func provider(for virtualMachine: VirtualMachine) throws -> VirtualMachineProvider {
        guard let provider = providers.first(where: { $0.id == virtualMachine.providerID }) else {
            throw VirtualMachineProviderError.invalidVirtualMachine("未找到虚拟机 Provider")
        }
        return provider
    }
}
