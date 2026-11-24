// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mac-sysmonitor",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "mac-sysmonitor", targets: ["MacSysMonitor"])],
    targets: [.executableTarget(name: "MacSysMonitor")]
)
