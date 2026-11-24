// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SysMon",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "SysMon", targets: ["SysMon"])],
    targets: [.executableTarget(name: "SysMon")]
)
