// swift-tools-version:5.9
import PackageDescription

// StudioKit — Microduck Studio's presentation core.
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
        // 1.34.0 is the tag that added `DuckPolicyWriter.folding` — the one
        // operation that lets a per-joint gain and trim found by searching in a
        // simulator reach a robot at all, because robotd takes an ONNX and a
        // handful of config keys and has no hook for "and then multiply the
        // ninth output by 1.07". `DuckTuner` is built on it, so the floor moves
        // with it rather than being left at a tag where the search would have
        // nowhere to put its answer.
        .package(url: "https://github.com/craigm26/duckkit.git", from: "1.35.0")
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
            ],
            // THE CHALLENGE TRAVELS WITH THE APP, BYTE FOR BYTE. The stairs
            // challenge is a published dataset — a leaderboard and the intent
            // files behind its rows — and an app that retyped either would be
            // showing numbers nobody can trace. So the files themselves ship,
            // copied from duck-sounds/challenge without a byte changed, and
            // `StairsChallengeResourceTests` pins every one of them by sha256
            // against the list the dataset publishes. `.copy` rather than
            // `.process`: processing is free to rewrite what it recognises,
            // and a rewritten intent file is a different intent.
            resources: [.copy("Resources/StairsChallenge")]
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
