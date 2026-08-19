import AppKit
import Foundation
import SwiftUI

@available(macOS 15.0, *)
final class AppModel: ObservableObject {
    @Published private(set) var virtualMachines: [VirtualMachine] = []
    @Published private(set) var settings: AppSettings
    @Published private(set) var isScanning = false
    @Published private(set) var operationMessage: String?
    @Published private(set) var scanErrorMessage: String?
    @Published private(set) var operationErrorMessage: String?
    @Published private(set) var operatingVirtualMachineIDs: Set<String> = []
    @Published var customDirectoryInput = ""

    var lastErrorMessage: String? {
        operationErrorMessage ?? scanErrorMessage
    }

    private let settingsStore: SettingsStore
    private let manager: VirtualMachineManager
    private let workerQueue = DispatchQueue(label: "PhoneVM.worker", qos: .utility, attributes: .concurrent)
    private var settingsWindowController: SettingsWindowController?
    private var hasLoadedInitialData = false

    init(
        settingsStore: SettingsStore = SettingsStore(),
        manager: VirtualMachineManager = VirtualMachineManager()
    ) {
        self.settingsStore = settingsStore
        self.manager = manager
        self.settings = settingsStore.load()
    }

    func refreshIfNeeded() {
        guard !hasLoadedInitialData else {
            return
        }
        hasLoadedInitialData = true
        refreshVirtualMachines()
    }

    func refreshVirtualMachines(includeRuntimeStatus: Bool = true) {
        guard !isScanning else {
            return
        }

        isScanning = true
        scanErrorMessage = nil
        let settingsSnapshot = settings
        let manager = manager

        workerQueue.async { [weak self] in
            let result = Result {
                try manager.scan(settings: settingsSnapshot, includeRuntimeStatus: includeRuntimeStatus)
            }

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.isScanning = false
                switch result {
                case .success(let virtualMachines):
                    self.virtualMachines = virtualMachines
                    self.operationMessage = "已刷新 \(virtualMachines.count) 台虚拟机"
                case .failure(let error):
                    self.scanErrorMessage = Self.message(from: error)
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
        operatingVirtualMachineIDs.contains(virtualMachine.id)
    }

    func screenshot(_ virtualMachine: VirtualMachine) {
        runOperation(
            for: virtualMachine,
            status: virtualMachine.status,
            successMessage: "已复制屏幕截图：\(virtualMachine.name)"
        ) { manager in
            let imageData = try manager.screenshot(virtualMachine)
            guard let image = NSImage(data: imageData) else {
                throw VirtualMachineProviderError.processFailed("截图数据无法解析为图片")
            }

            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
        }
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
        guard !operatingVirtualMachineIDs.contains(virtualMachine.id) else {
            return
        }

        operationErrorMessage = nil
        operationMessage = nil
        operatingVirtualMachineIDs.insert(virtualMachine.id)
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

                self.operatingVirtualMachineIDs.remove(virtualMachine.id)
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
