import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var customScanDirectories: [URL]
    var iOSScreenshotToolPath: String?

    init(customScanDirectories: [URL] = [], iOSScreenshotToolPath: String? = nil) {
        self.customScanDirectories = customScanDirectories
        self.iOSScreenshotToolPath = iOSScreenshotToolPath
    }
}
