// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "manifests", platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../../StudioKit")],
    targets: [.executableTarget(name: "manifests", dependencies: [.product(name: "StudioKit", package: "StudioKit")])])
