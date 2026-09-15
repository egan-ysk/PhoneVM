import SwiftUI

@available(macOS 15.0, *)
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            customDirectoriesSection

            Divider()

            iosScreenshotSection

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 540)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PhoneVM")
                .font(.title2)
                .fontWeight(.semibold)
            Text("管理虚拟机扫描目录与真机截屏")
                .foregroundStyle(.secondary)
        }
    }

    private var iosScreenshotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iOS 真机截屏").font(.headline)
            Text("设备需信任此 Mac 并开启开发者模式；首次连接请在 Xcode 中完成设备准备。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("pymobiledevice3 路径，留空自动检测", text: $model.iOSScreenshotToolPathInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.saveIOSScreenshotToolPath() }
                Button("保存") { model.saveIOSScreenshotToolPath() }
                Button("选择…") { model.chooseIOSScreenshotTool() }
            }
            Text(model.iOSScreenshotToolDescription)
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var customDirectoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自定义虚拟机目录")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("输入目录路径", text: $model.customDirectoryInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.addCustomDirectoryFromInput()
                    }

                Button {
                    model.addCustomDirectoryFromInput()
                } label: {
                    Label("添加", systemImage: "plus")
                }

                Button {
                    model.chooseAndAddDirectory()
                } label: {
                    Label("选择", systemImage: "folder.badge.plus")
                }
            }

            if model.settings.customScanDirectories.isEmpty {
                ContentUnavailableView("暂无自定义目录", systemImage: "folder")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List {
                    ForEach(model.settings.customScanDirectories, id: \.path) { directory in
                        HStack(spacing: 12) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(directory.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                model.removeCustomDirectory(directory)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("移除目录")
                        }
                    }
                }
                .frame(minHeight: 140)
            }

            if let error = model.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }
}
