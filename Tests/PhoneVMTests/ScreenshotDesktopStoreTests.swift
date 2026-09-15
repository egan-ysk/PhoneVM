import AppKit
import XCTest
@testable import PhoneVM

final class ScreenshotDesktopStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PhoneVMDesktopTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testSameTimestampProducesSeparatePNGFilesWithOriginalBytes() throws {
        let store = ScreenshotDesktopStore(desktopDirectory: directory)
        let data = try bitmapData(type: .png)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try store.save(data, date: date)
        let second = try store.save(data, date: date)
        XCTAssertNotEqual(first, second)
        for url in [first, second] {
            XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
            XCTAssertEqual(url.pathExtension, "png")
            XCTAssertTrue(url.lastPathComponent.hasPrefix("PhoneVM-"))
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testExistingFileIsNeverOverwritten() throws {
        let store = ScreenshotDesktopStore(desktopDirectory: directory)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let identifier = UUID()
        let original = try bitmapData(type: .png)
        let url = try store.save(original, date: date, identifier: identifier)
        XCTAssertThrowsError(try store.save(bitmapData(type: .png, width: 8), date: date, identifier: identifier))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }

    func testOtherImageFormatsBecomePNGWithoutChangingDimensions() throws {
        let url = try ScreenshotDesktopStore(desktopDirectory: directory).save(bitmapData(type: .tiff))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(decoded.pixelsWide, 4)
        XCTAssertEqual(decoded.pixelsHigh, 6)
    }

    func testInvalidImageCreatesNoFileAndWriteFailureExplainsDesktopAccess() throws {
        let store = ScreenshotDesktopStore(desktopDirectory: directory)
        XCTAssertThrowsError(try store.save(Data("not an image".utf8)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 0)

        let notADirectory = directory.appendingPathComponent("file")
        try Data([1]).write(to: notADirectory)
        XCTAssertThrowsError(try ScreenshotDesktopStore(desktopDirectory: notADirectory).save(bitmapData(type: .png))) { error in
            XCTAssertTrue(error.localizedDescription.contains("无法保存截屏到桌面"))
        }
        XCTAssertEqual(try Data(contentsOf: notADirectory), Data([1]))
    }

    private func bitmapData(type: NSBitmapImageRep.FileType, width: Int = 4) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 6, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try XCTUnwrap(bitmap.representation(using: type, properties: [:]))
    }
}
