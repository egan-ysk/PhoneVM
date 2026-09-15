import Foundation

enum PhysicalDeviceConnectionState: String, Sendable {
    case connected
    case disconnected
    case unauthorized
    case unknown

    var title: String {
        switch self {
        case .connected: return "已连接"
        case .disconnected: return "离线"
        case .unauthorized: return "未授权"
        case .unknown: return "状态未知"
        }
    }

    var screenshotUnavailableReason: String? {
        switch self {
        case .connected: return nil
        case .disconnected: return "设备已离线，请连接设备后刷新"
        case .unauthorized: return "请解锁设备并授权此 Mac，然后刷新列表"
        case .unknown: return "暂时无法确认设备连接状态，请刷新后重试"
        }
    }
}

struct PhysicalDevice: Identifiable, Equatable, Sendable {
    let name: String
    /// Android serial 或 Apple 硬件 UDID；不能使用 CoreDevice identifier 代替 UDID。
    let identifier: String
    let platform: VirtualMachinePlatform
    let connectionState: PhysicalDeviceConnectionState
    var detail: String = ""
    var screenshotBlockedReason: String?

    var id: String { "physical:\(platform.rawValue):\(identifier)" }
    var screenshotUnavailableReason: String? {
        connectionState.screenshotUnavailableReason ?? screenshotBlockedReason
    }
    var canScreenshot: Bool { screenshotUnavailableReason == nil }
}

protocol PhysicalDeviceProvider {
    var platform: VirtualMachinePlatform { get }
    var displayName: String { get }
    func scan(settings: AppSettings) throws -> [PhysicalDevice]
    func screenshot(_ device: PhysicalDevice, settings: AppSettings) throws -> Data
}

struct PhysicalDeviceScanResult {
    var devices: [PhysicalDevice] = []
    var warnings: [String] = []
}
