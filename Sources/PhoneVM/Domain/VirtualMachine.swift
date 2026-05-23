import Foundation

enum VirtualMachinePlatform: String, Codable, CaseIterable, Sendable {
    case android
    case iOS
}

enum VirtualMachineProviderID: String, Codable, CaseIterable, Sendable {
    case androidAVD
    case genymotion
    case iOSSimulator
}

enum VirtualMachineStatus: String, Codable, Sendable {
    case stopped
    case starting
    case running
    case unavailable
    case unknown

    var title: String {
        switch self {
        case .stopped:
            return "已停止"
        case .starting:
            return "启动中"
        case .running:
            return "运行中"
        case .unavailable:
            return "不可用"
        case .unknown:
            return "未知"
        }
    }
}

struct VirtualMachine: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let platform: VirtualMachinePlatform
    let providerID: VirtualMachineProviderID
    let providerName: String
    let location: URL
    let metadata: [String: String]
    var status: VirtualMachineStatus

    var subtitle: String {
        var parts: [String] = [providerName, status.title]
        if let apiLevel = metadata["apiLevel"], !apiLevel.isEmpty {
            parts.append("API \(apiLevel)")
        } else if let target = metadata["target"], !target.isEmpty {
            parts.append(target)
        }
        return parts.joined(separator: " · ")
    }
}
