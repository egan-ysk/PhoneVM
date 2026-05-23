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

    @ViewBuilder
    private func virtualMachineMenu(_ virtualMachine: VirtualMachine) -> some View {
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
            .disabled(virtualMachine.status == .running || virtualMachine.status == .starting)

            Button {
                model.stop(virtualMachine)
            } label: {
                Label("停止", systemImage: "stop.fill")
            }
            .disabled(virtualMachine.status == .stopped || virtualMachine.status == .unavailable)

            Button {
                model.restart(virtualMachine)
            } label: {
                Label("重启", systemImage: "arrow.clockwise")
            }
            .disabled(virtualMachine.status == .unavailable)

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
        case (.android, .starting), (.iOS, .starting):
            return "hourglass"
        case (.android, _):
            return "apps.iphone"
        case (.iOS, _):
            return "iphone"
        }
    }
}
