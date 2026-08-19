import AppKit
import SwiftUI

@available(macOS 15.0, *)
struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.isScanning {
                Label("正在扫描虚拟机", systemImage: "arrow.triangle.2.circlepath")
            }

            if model.virtualMachines.isEmpty && !model.isScanning {
                Label("未发现虚拟机", systemImage: "tray")
            }

            ForEach(model.virtualMachines) { virtualMachine in
                if let index = model.virtualMachines.firstIndex(where: { $0.id == virtualMachine.id }),
                   isFirstOfPlatform(virtualMachine, at: index) {
                    sectionHeader(for: virtualMachine.platform)
                }
                virtualMachineMenu(virtualMachine)
            }

            if let message = model.operationMessage {
                Divider()
                Text(message)
                    .foregroundStyle(.secondary)
            }

            if let error = model.lastErrorMessage {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle")
            }

            Divider()

            Button {
                model.refreshVirtualMachines()
            } label: {
                Label("刷新列表", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning)

            Button {
                model.openSettingsWindow()
            } label: {
                Label("设置", systemImage: "gearshape")
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
        }
        .onAppear {
            model.refreshIfNeeded()
        }
    }

    private func isFirstOfPlatform(_ virtualMachine: VirtualMachine, at index: Int) -> Bool {
        index == 0 || model.virtualMachines[index - 1].platform != virtualMachine.platform
    }

    private func sectionHeader(for platform: VirtualMachinePlatform) -> some View {
        switch platform {
        case .android:
            Label("Android", systemImage: "a.square.fill")
        case .iOS:
            Label("iOS", systemImage: "apple.terminal.on.rectangle")
        }
    }

    @ViewBuilder
    private func virtualMachineMenu(_ virtualMachine: VirtualMachine) -> some View {
        let isOperating = model.isOperating(virtualMachine)

        Menu {
            Text(virtualMachine.subtitle)
            Text(virtualMachine.location.path)
                .foregroundStyle(.secondary)

            Divider()

            Button {
                model.start(virtualMachine)
            } label: {
                Label("启动", systemImage: "play.fill")
            }
            .disabled(
                isOperating || [VirtualMachineStatus.running, .starting, .stopping, .unavailable]
                    .contains(virtualMachine.status)
            )

            Button {
                model.stop(virtualMachine)
            } label: {
                Label("停止", systemImage: "stop.fill")
            }
            .disabled(isOperating || virtualMachine.status != .running)

            Button {
                model.restart(virtualMachine)
            } label: {
                Label("重启", systemImage: "arrow.clockwise")
            }
            .disabled(isOperating || virtualMachine.status != .running)

            Divider()

            Button {
                model.screenshot(virtualMachine)
            } label: {
                Label("截屏到剪贴板", systemImage: "camera.on.rectangle")
            }
            .disabled(isOperating || virtualMachine.status != .running)

            Divider()

            Button {
                model.revealInFinder(virtualMachine)
            } label: {
                Label("打开所在目录", systemImage: "folder")
            }
        } label: {
            Label {
                Text("\(virtualMachine.name) · \(virtualMachine.status.title)")
            } icon: {
                Image(systemName: iconName(for: virtualMachine))
            }
        }
    }

    private func iconName(for virtualMachine: VirtualMachine) -> String {
        switch (virtualMachine.platform, virtualMachine.status) {
        case (.android, .running), (.iOS, .running):
            return "play.rectangle.fill"
        case (.android, .starting), (.iOS, .starting), (.android, .stopping), (.iOS, .stopping):
            return "hourglass"
        case (.android, _):
            return "apps.iphone"
        case (.iOS, _):
            return "iphone"
        }
    }
}
