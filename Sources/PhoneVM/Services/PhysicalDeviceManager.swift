import Foundation

final class PhysicalDeviceManager {
    private let providers: [PhysicalDeviceProvider]

    init(providers: [PhysicalDeviceProvider] = [AndroidPhysicalDeviceProvider(), IOSPhysicalDeviceProvider()]) {
        self.providers = providers
    }

    func scan(settings: AppSettings) -> PhysicalDeviceScanResult {
        var result = PhysicalDeviceScanResult()
        for provider in providers {
            do {
                result.devices.append(contentsOf: try provider.scan(settings: settings))
            } catch {
                result.warnings.append("\(provider.displayName)：\(error.localizedDescription)")
            }
        }
        result.devices.sort {
            if $0.platform != $1.platform { return $0.platform.rawValue < $1.platform.rawValue }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.identifier < $1.identifier
        }
        return result
    }

    func screenshot(_ device: PhysicalDevice, settings: AppSettings) throws -> Data {
        guard let provider = providers.first(where: { $0.platform == device.platform }) else {
            throw VirtualMachineProviderError.unsupportedOperation("未找到真机截屏服务")
        }
        // 菜单中的状态可能已过期；操作前重新确认同一设备，绝不回退到第一台设备。
        guard let current = try provider.scan(settings: settings).first(where: { $0.id == device.id }) else {
            throw VirtualMachineProviderError.unsupportedOperation("设备已断开，请重新连接后刷新")
        }
        if let reason = current.screenshotUnavailableReason {
            throw VirtualMachineProviderError.unsupportedOperation(reason)
        }
        return try provider.screenshot(current, settings: settings)
    }
}
