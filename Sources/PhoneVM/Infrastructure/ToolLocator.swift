import Foundation

struct ToolLocator {
    let environment: [String: String]
    let fileManager: FileManager
    let homeDirectory: URL

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    func androidSDKDirectories() -> [URL] {
        var directories: [URL] = []

        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let value = environment[key], !value.isEmpty {
                directories.append(URL(fileURLWithPath: value, isDirectory: true))
            }
        }

        directories.append(homeDirectory.appendingPathComponent("Library/Android/sdk", isDirectory: true))
        return directories.uniqueStandardized()
    }

    func androidAVDDirectories() -> [URL] {
        if let value = environment["ANDROID_AVD_HOME"], !value.isEmpty {
            return [URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL]
        }

        if let value = environment["ANDROID_USER_HOME"], !value.isEmpty {
            return [
                URL(fileURLWithPath: value, isDirectory: true)
                    .appendingPathComponent("avd", isDirectory: true)
                    .standardizedFileURL
            ]
        }

        return [homeDirectory.appendingPathComponent(".android/avd", isDirectory: true)]
    }

    func androidUserDirectories() -> [URL] {
        var directories = [homeDirectory.appendingPathComponent(".android", isDirectory: true)]
        if let value = environment["ANDROID_USER_HOME"], !value.isEmpty {
            directories.insert(URL(fileURLWithPath: value, isDirectory: true), at: 0)
        }
        return directories.uniqueStandardized()
    }

    func androidEmulatorExecutable() -> URL? {
        for sdkDirectory in androidSDKDirectories() {
            let candidate = sdkDirectory.appendingPathComponent("emulator/emulator", isDirectory: false)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return executableOnPATH(named: "emulator")
    }

    func adbExecutable() -> URL? {
        for sdkDirectory in androidSDKDirectories() {
            let candidate = sdkDirectory.appendingPathComponent("platform-tools/adb", isDirectory: false)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return executableOnPATH(named: "adb")
    }

    func xcrunExecutable() -> URL? {
        let systemXcrun = URL(fileURLWithPath: "/usr/bin/xcrun", isDirectory: false)
        if fileManager.isExecutableFile(atPath: systemXcrun.path) {
            return systemXcrun
        }
        return executableOnPATH(named: "xcrun")
    }

    func openExecutable() -> URL? {
        let systemOpen = URL(fileURLWithPath: "/usr/bin/open", isDirectory: false)
        if fileManager.isExecutableFile(atPath: systemOpen.path) {
            return systemOpen
        }
        return executableOnPATH(named: "open")
    }

    func pymobiledevice3Executable(customPath: String? = nil) -> URL? {
        if let path = customPath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            return fileManager.isExecutableFile(atPath: url.path) && !fileManager.directoryExists(at: url) ? url : nil
        }
        // Finder 启动的应用不继承交互式 shell 的 PATH，因此显式检查常用安装目录。
        let candidates = [
            homeDirectory.appendingPathComponent("Library/Application Support/PhoneVM/tools/pymobiledevice3/bin/pymobiledevice3"),
            homeDirectory.appendingPathComponent(".local/bin/pymobiledevice3"),
            URL(fileURLWithPath: "/opt/homebrew/bin/pymobiledevice3"),
            URL(fileURLWithPath: "/usr/local/bin/pymobiledevice3")
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) && !fileManager.directoryExists(at: $0) }
            ?? executableOnPATH(named: "pymobiledevice3")
    }

    private func executableOnPATH(named name: String) -> URL? {
        let pathValue = environment["PATH"] ?? ""
        for rawDirectory in pathValue.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(rawDirectory), isDirectory: true)
                .appendingPathComponent(name, isDirectory: false)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

extension Array where Element == URL {
    func uniqueStandardized() -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for url in self {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else {
                continue
            }
            result.append(standardized)
        }

        return result
    }
}
