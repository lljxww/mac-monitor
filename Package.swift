// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacMonitor", targets: ["MacMonitor"]),
        .executable(name: "MonitorProbe", targets: ["MonitorProbe"])
    ],
    targets: [
        .target(name: "MonitorCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "MacMonitor", dependencies: ["MonitorCore"]),
        .executableTarget(name: "MonitorProbe", dependencies: ["MonitorCore"]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"])
    ]
)
