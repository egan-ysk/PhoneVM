// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "PhoneVM",
    products: [
        .executable(
            name: "PhoneVM",
            targets: ["PhoneVM"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PhoneVM",
            path: "Sources/PhoneVM"
        )
    ]
)
