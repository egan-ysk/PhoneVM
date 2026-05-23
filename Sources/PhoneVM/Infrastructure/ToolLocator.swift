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

    func genymotionPlayerExecutable() -> URL? {
        if let value = environment["GENYMOTION_PLAYER"], !value.isEmpty {
            let candidate = URL(fileURLWithPath: value, isDirectory: false)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        let candidates = [
            URL(fileURLWithPath: "/Applications/Genymotion.app/Contents/MacOS/player", isDirectory: false),
            homeDirectory.appendingPathComponent("Applications/Genymotion.app/Contents/MacOS/player", isDirectory: false)
        ]

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
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
