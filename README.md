# PhoneVM

PhoneVM 是一个原生 macOS 菜单栏应用，用于快速发现、管理和启动本机手机虚拟机，以及对连接的手机真机截屏。支持 Android Studio AVD、iOS Simulator、Android 真机和 iPhone/iPad 真机。

## Features

- macOS 菜单栏常驻入口，支持刷新、设置、退出和虚拟机快捷操作。
- 自动扫描 Android Studio AVD：`~/.android/avd/*.ini` 与 `.avd/config.ini`。
- 自动扫描 iOS Simulator 设备（`xcrun simctl`）。
- 发现真实设备，显示连接/授权状态，并截屏到剪贴板。
- 每次打开菜单或手动刷新时更新设备列表；真机截屏前重新确认目标设备。
- 支持添加、移除自定义虚拟机扫描目录。
- 支持启动、停止、重启、打开所在目录等常用操作。
- AVD 运行状态通过 `adb` 按需查询，避免高频后台轮询。
- 配置持久化到当前用户的 Application Support 目录。
- Provider 架构隔离各平台实现，便于后续扩展。

## Requirements

- macOS 15.0 or later.
- Swift toolchain with Swift Package Manager.
- Android Studio AVD 管理能力需要本机已安装 Android SDK `emulator`。
- AVD 停止和运行状态查询需要本机已安装 `adb`。
- iOS Simulator 管理能力需要本机已安装 Xcode 或 Command Line Tools（`xcrun`）。

## Installation

从 [GitHub Releases](https://github.com/egan-ysk/PhoneVM/releases) 下载最新的 `PhoneVM-v*-macos.zip`，解压后运行 `PhoneVM.app`。

当前版本为 **v0.3.0**，变更见 [更新记录](CHANGELOG.md)。Release ZIP 适用于 Apple Silicon Mac，要求 macOS 15.0+。下载后可使用同一 Release 中的 `SHA256SUMS.txt` 校验文件。

当前 Release 产物未做 Apple notarization。首次运行时，macOS 可能需要用户在系统安全设置中确认打开。

## Build From Source

```bash
swift build
.build/debug/PhoneVM
```

打包为 `.app`：

```bash
Scripts/build-app.sh
open "dist/PhoneVM.app"
```

运行轻量自检：

```bash
Scripts/run-self-tests.sh
```

## 真机截屏

菜单中进入「真实设备 → 设备名称 → 截屏到剪贴板」。真机不提供虚拟机的启动、停止、重启和目录操作。

### Android

安装 Android SDK Platform-Tools，在手机上开启 USB 调试并授权此 Mac。使用 `adb devices -l` 发现设备，使用 `adb -s <serial> exec-out screencap -p` 截屏。未授权、离线和未知状态的设备不能截屏。模拟器仍显示在原有虚拟机分组中。

### iPhone / iPad

1. 安装并选择完整 Xcode；连接、解锁设备并信任此 Mac，开启开发者模式。
2. 首次连接时在 Xcode 的 **Window → Devices and Simulators** 中完成设备准备。
3. 在项目目录执行一次安装脚本（需要 Python 3.9+）：

   ```bash
   Scripts/setup-ios-screenshot.sh
   ```

   脚本将已验证版本 `pymobiledevice3==11.12.5` 安装到 `~/Library/Application Support/PhoneVM/tools/pymobiledevice3` 的独立 Python 环境，不修改系统 Python。即使从 Finder 启动 PhoneVM，也会自动检测这个位置。

   如果使用 Release 应用，可从同一 Release 下载 `setup-ios-screenshot.sh`，在终端运行 `bash setup-ios-screenshot.sh`；已有可用工具环境时无需再次安装。

4. 打开 PhoneVM 并刷新列表，即可截屏。已配对但离线的设备会显示为离线。

也可以在设置的「iOS 真机截屏」中选择已有环境的 `bin/pymobiledevice3` **可执行文件**，不要填写 Python 命令或参数；路径留空并保存恢复自动检测。自动检测也覆盖 `~/.local/bin`、Homebrew 常用目录和应用进程的 `PATH`。不建议长期使用 `/tmp` 下的临时环境。

设备发现读取 `devicectl --json-output` 结果；截屏使用硬件 UDID 调用 `pymobiledevice3 developer dvt screenshot --udid <UDID> <临时文件>`。各次操作使用独立临时目录并在成功/失败后清理。只有命令成功、图片可解码且剪贴板写入成功才提示已复制；Python 警告和 native tunnel 重试日志本身不视为失败。

设备断开、未授权、未开启开发者模式、缺少工具、超时和截屏失败会给出提示。单个平台发现失败不影响其他平台的设备列表。iOS 截屏超时为 45 秒，Android 为 20 秒。

`pymobiledevice3` 是单独安装的可选外部工具，不包含在 `.app` 中，其许可证见[上游项目](https://github.com/doronz88/pymobiledevice3)。iOS 版本兼容性取决于 Xcode 与该工具；已在 iPhone 12 / iOS 26.6.2 上通过 AppModel 验证设备发现、截屏和剪贴板读回，图片为 1170 × 2532。Android 暂未进行真机实测。

## Supported Virtual Machines

| 类型 | 扫描 | 启动 | 停止 | 状态 |
| --- | --- | --- | --- | --- |
| Android Studio AVD | 支持 | `emulator -avd <name>` | `adb emu kill` | `adb devices` + `adb emu avd name` |
| iOS Simulator | 支持 | `simctl boot` + `open -a Simulator` | `simctl shutdown` | `simctl list devices --json` |

## Architecture

- `Domain`：虚拟机实体、状态、平台、Provider 协议。
- `Providers`：模拟器与真机各平台实现。
- `Services`：统一扫描、启动、停止、重启和 Finder 打开入口。
- `Settings`：用户配置目录与 JSON 持久化。
- `Infrastructure`：进程执行、工具定位、文件解析、文件系统辅助。
- `UI/App`：SwiftUI `MenuBarExtra`、设置窗口与应用状态。

新增虚拟机类型时，应实现 `VirtualMachineProvider`，并将平台相关的 scan/start/stop/status 逻辑隔离在独立 Provider 中。

真机使用独立的 `PhysicalDevice` / `PhysicalDeviceProvider` / `PhysicalDeviceManager`，连接状态与虚拟机生命周期分开。两者共用截屏校验和剪贴板发布流程。

运行回归测试：`swift test`。真机解析、设备选择、断连保护、警告日志、图片有效性、临时文件清理、旧配置兼容和剪贴板发布均有测试覆盖；实际设备验证仍需连接对应平台的真机。

## Security and Privacy

- 启动和停止虚拟机时使用 `Process` 与参数数组，不拼接 shell 字符串。
- 默认扫描路径基于当前用户目录动态推导，不在源码中硬编码个人路径。
- 自定义扫描目录仅保存在本机用户目录下。
- 应用不需要云端账号、访问令牌或远程服务凭据。
- 提交 issue 或日志前，请移除本机私有路径、账号信息和敏感数据。

## Contributing

欢迎通过 issue 或 pull request 参与改进。贡献前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 与 [SECURITY.md](SECURITY.md)。

## License

PhoneVM is released under the [MIT License](LICENSE).

MIT License 允许任何人自由使用、复制、修改、合并、发布、分发、再许可和销售本项目的副本，但需要在副本或重要部分中保留原始版权声明和许可声明。

本项目按 “as is” 形式提供，不附带任何明示或暗示担保。使用者需自行评估在自己环境中运行虚拟机管理命令的风险。
