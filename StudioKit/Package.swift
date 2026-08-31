// swift-tools-version:5.9
import PackageDescription

// StudioKit — Duck Studio's presentation core.
//
// THE RULE THIS PACKAGE EXISTS TO ENFORCE: StudioKit computes, DuckStudio
// displays. No arithmetic in the app target, and no robot knowledge here that
// DuckKit already holds. DuckKit is the single source of robot truth; this is
// the single source of *presentation* truth — the exact sentences on screen —
// and the app only draws them.
//
// It is UI-free on purpose, so every string a person will read is asserted by
// `swift test` on Linux rather than eyeballed on a phone. A refusal message is
// this app's whole value proposition, and a value proposition you cannot test
// is one you find out about in review.
let package = Package(
    name: "StudioKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "StudioKit", targets: ["StudioKit"])
    ],
    dependencies: [
        // By tag, never by sibling path: an inspector that reports which
        // network it loaded has to be built against a pinned reader, or its
        // report describes a parser nobody can identify later.
        .package(url: "https://github.com/craigm26/duckkit.git", from: "1.31.1")
    ],
    targets: [
        .target(
            name: "StudioKit",
            dependencies: [
                .product(name: "DuckKit", package: "duckkit"),
                // For the fingerprint. A library that deduplicates policies has
                // to be able to say when two files are the same network, and
                // that is a digest question, not a filename one.
                .product(name: "DuckEvidence", package: "duckkit"),
            ]
        ),
        .testTarget(
            name: "StudioKitTests",
            dependencies: ["StudioKit", .product(name: "DuckEvidence", package: "duckkit")],
            // The synthesized refusal corpus — each file carries exactly one
            // defect, so the message naming it can be asserted literally — plus
            // tree listings captured from Pollen's real repositories, so the
            // catalogue is parsed against what GitHub actually answers rather
            // than against JSON written to match the parser.
            resources: [.copy("Fixtures")]
        ),
    ]
)
