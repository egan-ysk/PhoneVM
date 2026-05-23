import Foundation

final class IOSSimulatorProvider: VirtualMachineProvider {
    let id: VirtualMachineProviderID = .iOSSimulator
    let displayName = "iOS Simulator"
    let platform: VirtualMachinePlatform = .iOS

    func scan(context: VirtualMachineScanContext) throws -> [VirtualMachine] {
        []
    }

    func start(_ virtualMachine: VirtualMachine) throws {
        throw VirtualMachineProviderError.unsupportedOperation("iOS Simulator 支持将在后续版本实现")
    }

    func stop(_ virtualMachine: VirtualMachine) throws {
        throw VirtualMachineProviderError.unsupportedOperation("iOS Simulator 支持将在后续版本实现")
    }

    func status(for virtualMachine: VirtualMachine) throws -> VirtualMachineStatus {
        .unavailable
    }
}
