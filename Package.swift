// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clipp",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Clipp", targets: ["Clipp"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .executableTarget(name: "Clipp", dependencies: ["CSQLite"]),
        .testTarget(name: "ClippTests", dependencies: ["Clipp"])
    ]
)
