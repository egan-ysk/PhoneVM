import Foundation

struct VirtualMachineScanContext: Sendable {
    let customDirectories: [URL]
    let includeRuntimeStatus: Bool
}

protocol VirtualMachineProvider {
    var id: VirtualMachineProviderID { get }
    var displayName: String { get }
    var platform: VirtualMachinePlatform { get }

    func scan(context: VirtualMachineScanContext) throws -> [VirtualMachine]
    func start(_ virtualMachine: VirtualMachine) throws
    func stop(_ virtualMachine: VirtualMachine) throws
    func status(for virtualMachine: VirtualMachine) throws -> VirtualMachineStatus
}

enum VirtualMachineProviderError: LocalizedError {
    case executableNotFound(String)
    case unsupportedOperation(String)
    case invalidVirtualMachine(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return "未找到可执行文件：\(name)"
        case .unsupportedOperation(let message):
            return message
        case .invalidVirtualMachine(let message):
            return message
        case .processFailed(let message):
            return message
        }
    }
}
