import AppKit
import Foundation
import SwiftUI

enum ScreenshotDestination {
    case clipboard
    case desktop
}

@available(macOS 15.0, *)
final class AppModel: ObservableObject {
    @Published private(set) var virtualMachines: [VirtualMachine] = []
    @Published private(set) var physicalDevices: [PhysicalDevice] = []
    @Published private(set) var physicalDeviceWarnings: [String] = []
    @Published private(set) var settings: AppSettings
    @Published private(set) var isScanning = false
    @Published private(set) var operationMessage: String?
    @Published private(set) var scanErrorMessage: String?
    @Published private(set) var operationErrorMessage: String?
    @Published private(set) var operatingDeviceIDs: Set<String> = []
    @Published var customDirectoryInput = ""
    @Published var iOSScreenshotToolPathInput = ""

    var lastErrorMessage: String? {
        operationErrorMessage ?? scanErrorMessage
    }

    private let settingsStore: SettingsStore
    private let manager: VirtualMachineManager
    private let physicalDeviceManager: PhysicalDeviceManager
    private let copyScreenshot: (Data) throws -> Void
    private let saveScreenshotToDesktop: (Data) throws -> URL
    private let workerQueue = DispatchQueue(label: "PhoneVM.worker", qos: .utility, attributes: .concurrent)
    private var settingsWindowController: SettingsWindowController?
    private var needsAnotherRefresh = false

    init(
        settingsStore: SettingsStore = SettingsStore(),
        manager: VirtualMachineManager = VirtualMachineManager(),
        physicalDeviceManager: PhysicalDeviceManager = PhysicalDeviceManager(),
        copyScreenshot: @escaping (Data) throws -> Void = ScreenshotClipboard.copy,
        saveScreenshotToDesktop: @escaping (Data) throws -> URL = { try ScreenshotDesktopStore().save($0) }
    ) {
        self.settingsStore = settingsStore
        self.manager = manager
        self.physicalDeviceManager = physicalDeviceManager
        self.copyScreenshot = copyScreenshot
        self.saveScreenshotToDesktop = saveScreenshotToDesktop
        self.settings = settingsStore.load()
        self.iOSScreenshotToolPathInput = self.settings.iOSScreenshotToolPath ?? ""
    }

    func refreshIfNeeded() {
        // 每次打开菜单刷新连接状态，仍由 isScanning 合并并发请求。
        refreshVirtualMachines()
    }

    func refreshVirtualMachines(includeRuntimeStatus: Bool = true) {
        guard !isScanning else {
            needsAnotherRefresh = true
            return
        }

        isScanning = true
        scanErrorMessage = nil
        let settingsSnapshot = settings
        let manager = manager
        let physicalDeviceManager = physicalDeviceManager

        workerQueue.async { [weak self] in
            let result = Result {
                try manager.scan(settings: settingsSnapshot, includeRuntimeStatus: includeRuntimeStatus)
            }
            // 与模拟器扫描分别收集结果；单个平台缺少工具不影响其他设备。
            let physicalResult = physicalDeviceManager.scan(settings: settingsSnapshot)

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.isScanning = false
                self.physicalDevices = physicalResult.devices
                self.physicalDeviceWarnings = physicalResult.warnings
                switch result {
                case .success(let virtualMachines):
                    self.virtualMachines = virtualMachines
                case .failure(let error):
                    self.scanErrorMessage = Self.message(from: error)
                }
                if self.operatingDeviceIDs.isEmpty,
                   self.operationMessage == nil || self.operationMessage?.hasPrefix("已刷新") == true {
                    self.operationMessage = "已刷新 \(self.virtualMachines.count) 台虚拟机、\(self.physicalDevices.count) 台真机"
                }
                if self.needsAnotherRefresh {
                    self.needsAnotherRefresh = false
                    self.refreshVirtualMachines()
                }
            }
        }
    }

    func start(_ virtualMachine: VirtualMachine) {
        runOperation(
            for: virtualMachine,
            status: .starting,
            successMessage: "已发送启动命令：\(virtualMachine.name)"
        ) { manager in
            try manager.start(virtualMachine)
        }
    }

    func stop(_ virtualMachine: VirtualMachine) {
        runOperation(
            for: virtualMachine,
            status: .stopping,
            successMessage: "已发送停止命令：\(virtualMachine.name)"
        ) { manager in
            try manager.stop(virtualMachine)
        }
    }

    func restart(_ virtualMachine: VirtualMachine) {
        runOperation(
            for: virtualMachine,
            status: .stopping,
            successMessage: "已发送重启命令：\(virtualMachine.name)"
        ) { manager in
            try manager.restart(virtualMachine)
        }
    }

    func isOperating(_ virtualMachine: VirtualMachine) -> Bool {
        operatingDeviceIDs.contains(virtualMachine.id)
    }

    func isOperating(_ device: PhysicalDevice) -> Bool {
        operatingDeviceIDs.contains(device.id)
    }

    func screenshot(_ virtualMachine: VirtualMachine, destination: ScreenshotDestination = .clipboard) {
        captureScreenshot(id: virtualMachine.id, name: virtualMachine.name, destination: destination) { [manager] in
            try manager.screenshot(virtualMachine)
        }
    }

    func screenshot(_ device: PhysicalDevice, destination: ScreenshotDestination = .clipboard) {
        let settingsSnapshot = settings
        captureScreenshot(id: device.id, name: device.name, destination: destination) { [physicalDeviceManager] in
            try physicalDeviceManager.screenshot(device, settings: settingsSnapshot)
        }
    }

    private func captureScreenshot(
        id: String, name: String, destination: ScreenshotDestination, capture: @escaping () throws -> Data
    ) {
        guard operatingDeviceIDs.insert(id).inserted else { return }
        operationErrorMessage = nil
        operationMessage = nil
        let saveToDesktop = saveScreenshotToDesktop
        workerQueue.async { [weak self] in
            let result = Result {
                let data = try capture()
                try ScreenshotClipboard.validate(data)
                let savedURL = destination == .desktop ? try saveToDesktop(data) : nil
                return (data: data, savedURL: savedURL)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                defer { self.operatingDeviceIDs.remove(id) }
                do {
                    let output = try result.get()
                    if let url = output.savedURL {
                        self.operationMessage = "已保存到桌面：\(url.lastPathComponent)"
                    } else {
                        try self.copyScreenshot(output.data)
                        self.operationMessage = "已复制屏幕截图：\(name)"
                    }
                } catch {
                    self.operationErrorMessage = Self.message(from: error)
                    self.refreshVirtualMachines()
                }
            }
        }
    }

    var iOSScreenshotToolDescription: String {
        if let url = ToolLocator().pymobiledevice3Executable(customPath: settings.iOSScreenshotToolPath) {
            return "当前工具：\(url.path)"
        }
        return "未找到截屏工具，请安装 pymobiledevice3 或选择已安装的可执行文件"
    }

    func saveIOSScreenshotToolPath() {
        let path = iOSScreenshotToolPathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty, ToolLocator().pymobiledevice3Executable(customPath: path) == nil {
            operationErrorMessage = "请选择有效的 pymobiledevice3 可执行文件，不要填写 Python 命令或参数"
            return
        }
        settings.iOSScreenshotToolPath = path.isEmpty ? nil : NSString(string: path).expandingTildeInPath
        operationErrorMessage = nil
        persistSettingsAndRefresh()
    }

    func chooseIOSScreenshotTool() {
        let panel = NSOpenPanel()
        panel.title = "选择 pymobiledevice3 可执行文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        iOSScreenshotToolPathInput = url.path
        saveIOSScreenshotToolPath()
    }

    func revealInFinder(_ virtualMachine: VirtualMachine) {
        manager.revealInFinder(virtualMachine)
    }

    func openSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: self)
        }
        settingsWindowController?.show()
    }

    func chooseAndAddDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择虚拟机目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        addCustomDirectory(url)
    }

    func addCustomDirectoryFromInput() {
        let path = customDirectoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return
        }
        addCustomDirectory(URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true))
        customDirectoryInput = ""
    }

    func addCustomDirectory(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard FileManager.default.directoryExists(at: standardized) else {
            operationErrorMessage = "目录不存在：\(standardized.path)"
            return
        }
        guard !settings.customScanDirectories.contains(where: { $0.standardizedFileURL.path == standardized.path }) else {
            return
        }

        settings.customScanDirectories.append(standardized)
        persistSettingsAndRefresh()
    }

    func removeCustomDirectory(_ url: URL) {
        let path = url.standardizedFileURL.path
        settings.customScanDirectories.removeAll { $0.standardizedFileURL.path == path }
        persistSettingsAndRefresh()
    }

    private func runOperation(
        for virtualMachine: VirtualMachine,
        status: VirtualMachineStatus,
        successMessage: String,
        operation: @escaping (VirtualMachineManager) throws -> Void
    ) {
        guard !operatingDeviceIDs.contains(virtualMachine.id) else {
            return
        }

        operationErrorMessage = nil
        operationMessage = nil
        operatingDeviceIDs.insert(virtualMachine.id)
        updateStatus(for: virtualMachine, status: status)
        let manager = manager

        workerQueue.async { [weak self] in
            let result = Result {
                try operation(manager)
            }

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.operatingDeviceIDs.remove(virtualMachine.id)
                switch result {
                case .success:
                    self.operationMessage = successMessage
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.refreshVirtualMachines()
                    }
                case .failure(let error):
                    self.operationErrorMessage = Self.message(from: error)
                    self.refreshVirtualMachines()
                }
            }
        }
    }

    private func updateStatus(for virtualMachine: VirtualMachine, status: VirtualMachineStatus) {
        virtualMachines = virtualMachines.map { current in
            guard current.id == virtualMachine.id else {
                return current
            }
            var updated = current
            updated.status = status
            return updated
        }
    }

    private func persistSettingsAndRefresh() {
        do {
            try settingsStore.save(settings)
            refreshVirtualMachines()
        } catch {
            operationErrorMessage = Self.message(from: error)
        }
    }

    private static func message(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
