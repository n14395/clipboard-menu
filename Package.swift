// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipboardMenu",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClipboardMenu", targets: ["ClipboardMenu"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.24.0")
    ],
    targets: [
        .executableTarget(
            name: "ClipboardMenu",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "ClipboardMenu",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ClipboardMenuTests",
            dependencies: [
                "ClipboardMenu",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Tests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
