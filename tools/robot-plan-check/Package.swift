// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "robot-plan-check",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../StudioKit")],
    targets: [.executableTarget(name: "robot-plan-check",
                                dependencies: [.product(name: "StudioKit", package: "StudioKit")])]
)
