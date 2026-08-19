import AppKit
import Foundation

final class VirtualMachineManager {
    private let providers: [VirtualMachineProvider]

    init(providers: [VirtualMachineProvider] = [
        AndroidAVDProvider(),
        IOSSimulatorProvider()
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

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            switch try provider.status(for: virtualMachine) {
            case .stopped:
                try provider.start(virtualMachine)
                return
            case .unavailable:
                throw VirtualMachineProviderError.invalidVirtualMachine("虚拟机已不可用")
            case .starting, .running, .stopping, .unknown:
                Thread.sleep(forTimeInterval: 0.25)
            }
        }

        throw VirtualMachineProviderError.processFailed("等待虚拟机停止超时：\(virtualMachine.name)")
    }

    func refreshStatus(for virtualMachine: VirtualMachine) throws -> VirtualMachineStatus {
        try provider(for: virtualMachine).status(for: virtualMachine)
    }

    func screenshot(_ virtualMachine: VirtualMachine) throws -> Data {
        try provider(for: virtualMachine).screenshot(virtualMachine)
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
