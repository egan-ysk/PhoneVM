import Foundation

enum SelfTestError: Error, CustomStringConvertible {
    case assertionFailed(String)

    var description: String {
        switch self {
        case .assertionFailed(let message):
            return message
        }
    }
}

func assertEqual<T: Equatable>(_ actual: T?, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw SelfTestError.assertionFailed("\(message). actual=\(String(describing: actual)), expected=\(expected)")
    }
}

func assertTrue(_ condition: Bool, _ message: String) throws {
    guard condition else {
        throw SelfTestError.assertionFailed(message)
    }
}

func testKeyValueParser() throws {
    let values = KeyValueFileParser.parse("""
    # comment
    ; another comment
    target = android-35
    image.sysdir.1 = system-images;android-35;google_apis_playstore;arm64-v8a
    ignored
    """)

    try assertEqual(values["target"], "android-35", "target should be parsed")
    try assertEqual(
        values["image.sysdir.1"],
        "system-images;android-35;google_apis_playstore;arm64-v8a",
        "value should keep separators after the first '='"
    )
    try assertTrue(values["ignored"] == nil, "lines without '=' should be ignored")
}

func testAndroidAVDScan() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("PhoneVMSelfTests-\(UUID().uuidString)", isDirectory: true)
    let home = root.appendingPathComponent("home", isDirectory: true)
    let avdRoot = home.appendingPathComponent(".android/avd", isDirectory: true)
    let avdDirectory = avdRoot.appendingPathComponent("Pixel_8.avd", isDirectory: true)

    try fileManager.createDirectory(at: avdDirectory, withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: root)
    }

    try """
    path=\(avdDirectory.path)
    avdId=Pixel_8
    avd.ini.displayname=Pixel 8
    """.write(
        to: avdRoot.appendingPathComponent("Pixel_8.ini"),
        atomically: true,
        encoding: .utf8
    )

    try """
    AvdId=Pixel_8
    target=android-35
    abi.type=arm64-v8a
    hw.device.name=pixel_8
    """.write(
        to: avdDirectory.appendingPathComponent("config.ini"),
        atomically: true,
        encoding: .utf8
    )

    let provider = AndroidAVDProvider(
        fileManager: fileManager,
        toolLocator: ToolLocator(environment: ["PATH": ""], fileManager: fileManager, homeDirectory: home)
    )
    let machines = try provider.scan(
        context: VirtualMachineScanContext(customDirectories: [], includeRuntimeStatus: false)
    )

    try assertEqual(machines.count, 1, "one AVD should be discovered")
    try assertEqual(machines.first?.name, "Pixel_8", "AVD id should come from config")
    try assertEqual(machines.first?.metadata["apiLevel"], "35", "API level should be extracted")
    try assertEqual(machines.first?.status, .stopped, "status should be stopped when runtime status is disabled")
}

do {
    try testKeyValueParser()
    try testAndroidAVDScan()
    print("Self-tests passed")
} catch {
    fputs("Self-tests failed: \(error)\n", stderr)
    exit(1)
}
