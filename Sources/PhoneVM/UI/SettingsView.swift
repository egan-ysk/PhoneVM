import SwiftUI

@available(macOS 15.0, *)
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            customDirectoriesSection

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 360)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PhoneVM")
                .font(.title2)
                .fontWeight(.semibold)
            Text("管理 Android 虚拟机扫描目录与快捷启动能力")
                .foregroundStyle(.secondary)
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
