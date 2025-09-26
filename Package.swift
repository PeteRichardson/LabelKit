// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LabelKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LabelKit", targets: ["LabelKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/stencilproject/Stencil.git", from: "0.15.1")
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
    ]
)
