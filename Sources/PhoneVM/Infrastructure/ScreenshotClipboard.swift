import AppKit
import ImageIO

enum ScreenshotClipboard {
    static func validate(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw VirtualMachineProviderError.processFailed("截屏数据无法解析为有效图片")
        }
    }

    /// 在主线程发布图片，只有实际写入成功才显示成功提示。
    static func copy(_ data: Data) throws {
        try validate(data)
        guard let image = NSImage(data: data) else {
            throw VirtualMachineProviderError.processFailed("截屏数据无法解析为有效图片")
        }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([image]) else {
            throw VirtualMachineProviderError.processFailed("无法写入剪贴板，请重试")
        }
    }
}
