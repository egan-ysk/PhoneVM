// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "PhoneVM",
    platforms: [.macOS(.v15)],
    products: [
        .executable(
            name: "PhoneVM",
            targets: ["PhoneVM"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "PhoneVM",
            path: "Sources/PhoneVM",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PhoneVMTests",
            dependencies: ["PhoneVM"],
            path: "Tests/PhoneVMTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
