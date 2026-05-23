# PhoneVM

PhoneVM 是一个原生 macOS 菜单栏应用，用于快速发现、管理和启动本机 Android 虚拟机。项目第一版聚焦 Android Studio AVD 与 Genymotion，并通过 Provider 架构为后续 iPhone/iOS Simulator 管理能力预留扩展点。

## Features

- macOS 菜单栏常驻入口，支持刷新、设置、退出和虚拟机快捷操作。
- 自动扫描 Android Studio AVD：`~/.android/avd/*.ini` 与 `.avd/config.ini`。
- 自动扫描 Genymotion 常见部署目录。
- 支持添加、移除自定义虚拟机扫描目录。
- 支持启动、停止、重启、打开所在目录等常用操作。
- AVD 运行状态通过 `adb` 按需查询，避免高频后台轮询。
- 配置持久化到当前用户的 Application Support 目录。
- Provider 架构隔离 Android 与未来 iOS Simulator 支持。

## Requirements

- macOS 15.0 or later.
- Swift toolchain with Swift Package Manager.
- Android Studio AVD 管理能力需要本机已安装 Android SDK `emulator`。
- AVD 停止和运行状态查询需要本机已安装 `adb`。
- Genymotion 启动能力需要本机已安装 Genymotion。

## Installation

从 [GitHub Releases](https://github.com/egan-ysk/PhoneVM/releases) 下载最新的 `PhoneVM-v*-macos.zip`，解压后运行 `PhoneVM.app`。

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

## Supported Virtual Machines

| 类型 | 扫描 | 启动 | 停止 | 状态 |
| --- | --- | --- | --- | --- |
| Android Studio AVD | 支持 | `emulator -avd <name>` | `adb emu kill` | `adb devices` + `adb emu avd name` |
| Genymotion | 支持 | `player --vm-name <name>` | 暂不稳定支持 | 未知 |
| iOS Simulator | 架构预留 | 后续支持 | 后续支持 | 后续支持 |

## Architecture

- `Domain`：虚拟机实体、状态、平台、Provider 协议。
- `Providers`：Android AVD、Genymotion 与 iOS Simulator 预留实现。
- `Services`：统一扫描、启动、停止、重启和 Finder 打开入口。
- `Settings`：用户配置目录与 JSON 持久化。
- `Infrastructure`：进程执行、工具定位、文件解析、文件系统辅助。
- `UI/App`：SwiftUI `MenuBarExtra`、设置窗口与应用状态。

新增虚拟机类型时，应实现 `VirtualMachineProvider`，并将平台相关的 scan/start/stop/status 逻辑隔离在独立 Provider 中。

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
