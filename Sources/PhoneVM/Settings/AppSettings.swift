import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var customScanDirectories: [URL]

    init(customScanDirectories: [URL] = []) {
        self.customScanDirectories = customScanDirectories
    }
}
