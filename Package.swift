// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LabelKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LabelKit", targets: ["LabelKit"]),
        .executable(name: "example-label", targets: ["LabelCLI"]),
        .executable(name: "example-reminderlist", targets: ["ReminderList"]),
        .executable(name: "labelprint", targets: ["labelprint"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/stencilproject/Stencil.git",
            from: "0.15.1"
        ),
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.3.0"
        )
    ],
    targets: [
        .target(
            name: "LabelKit",
            dependencies: [
                .product(name: "Stencil", package: "Stencil")
            ],
            resources: [
                .copy("Helpers/zpl2png")
            ]),
        .testTarget(name: "LabelKitTests", dependencies: ["LabelKit"]),
        .executableTarget(
            name: "LabelCLI",
            dependencies: [
                "LabelKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Examples/LabelCLI"
        ),
        .executableTarget(
            name: "ReminderList",
            dependencies: [
                "LabelKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Examples/ReminderList",
            sources: ["ReminderList.swift", "Reminders.swift"]
        ),
        .executableTarget(
            name: "labelprint",
            dependencies: [
                "LabelKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Examples/labelprint"
        ),
        .testTarget(
            name: "LabelPrintTests",
            dependencies: ["labelprint", "LabelKit"],
            path: "Tests/LabelPrintTests"
        )
    ]
)
