// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PicPocket",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PicPocket", path: "Sources/PicPocket"),
        .testTarget(name: "PicPocketTests", dependencies: ["PicPocket"])
    ]
)
