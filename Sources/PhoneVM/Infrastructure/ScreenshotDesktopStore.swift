import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotDesktopStore {
    private let desktopDirectory: URL?

    init(desktopDirectory: URL? = nil) {
        self.desktopDirectory = desktopDirectory
    }

    func save(_ data: Data, date: Date = Date(), identifier: UUID = UUID()) throws -> URL {
        let png = try pngData(from: data)
        let directory: URL
        do {
            directory = try desktopDirectory ?? FileManager.default.url(
                for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false
            )
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
            // 文件名不包含设备名称、UDID 等个人信息；同一时刻截屏也使用独立文件。
            let filename = "PhoneVM-\(formatter.string(from: date))-\(identifier.uuidString.prefix(8)).png"
            let url = directory.appendingPathComponent(filename, isDirectory: false)
            try png.write(to: url, options: .withoutOverwriting)
            return url
        } catch {
            throw VirtualMachineProviderError.processFailed(
                "无法保存截屏到桌面，请检查桌面访问权限、可用空间或重试。\n\(error.localizedDescription)"
            )
        }
    }

    private func pngData(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw VirtualMachineProviderError.processFailed("截屏数据无法解析为有效图片")
        }
        // PNG 原样保存，保留真机原始分辨率和位深；其他可解码图片统一转为 PNG。
        if CGImageSourceGetType(source) as String? == UTType.png.identifier {
            return data
        }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else {
            throw VirtualMachineProviderError.processFailed("无法生成 PNG 截屏")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw VirtualMachineProviderError.processFailed("无法生成 PNG 截屏")
        }
        return result as Data
    }
}
