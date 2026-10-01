// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "trgen",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../../StudioKit")],
    targets: [.executableTarget(name: "trgen", dependencies: [.product(name: "StudioKit", package: "StudioKit")])]
)
