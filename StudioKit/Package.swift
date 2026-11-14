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
        .library(name: "StudioKit", targets: ["StudioKit"]),
        // The MCP client (brains-layer.md 5.3), a separate product so StudioKit itself never
        // imports the SDK and StopPath cannot reach it.
        .library(name: "StudioMCP", targets: ["StudioMCP"]),
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
        // 1.36.0: `DuckPolicy.load` takes narrower students of the alpha
        // graph, `PolicyBlend` depends on `shapeProblem`'s contract, and the
        // refusal corpus's `hidden_narrowed.onnx` is expected to load.
        // 1.37.0: Pollen's set @d5a8b55 — sit-stand v6, velstand leads the walk slot.
        .package(url: "https://github.com/craigm26/duckkit.git", from: "1.37.0"),
        // THE MCP SDK, PINNED EXACTLY. modelcontextprotocol/swift-sdk 0.12.1 (a0ae212, 2026-05-07).
        // Licence: Apache-2.0, with contributions from before the project's relicensing still
        // under MIT (its LICENSE says so); both are permissive. Exact, not `from:`, because a
        // client that decides what a planner may read must be built against a reader somebody
        // can name. Used only by `StudioMCP`, and only on Apple platforms (see that target).
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        // The SDK's logger type, so the client can hand it a silent one by name.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        // THE APRILTAG LIBRARY, VENDORED, NOT RE-WRITTEN. AprilRobotics/apriltag
        // at b7c0ebe (BSD-2, LICENSE.md beside it): the detector, tag36h11 and
        // the `common/` it needs, unchanged. The duck's own card reader
        // (`cardreader/`, through pupil_apriltags) runs the same C, so a Duck Card
        // the phone finds in a frame is one the duck would find in it too.
        .target(
            name: "CAprilTag",
            exclude: ["LICENSE.md"],
            cSettings: [.headerSearchPath("include"), .headerSearchPath("include/common")],
            linkerSettings: [.linkedLibrary("m", .when(platforms: [.linux])),
                             .linkedLibrary("pthread", .when(platforms: [.linux]))]
        ),
        .target(
            name: "StudioKit",
            dependencies: [
                .product(name: "DuckKit", package: "duckkit"),
                // For the fingerprint. A library that deduplicates policies has
                // to be able to say when two files are the same network, and
                // that is a digest question, not a filename one.
                .product(name: "DuckEvidence", package: "duckkit"),
                "CAprilTag",
            ],
            // THE CHALLENGE TRAVELS WITH THE APP, BYTE FOR BYTE. The stairs
            // challenge is a published dataset — a leaderboard and the intent
            // files behind its rows — and an app that retyped either would be
            // showing numbers nobody can trace. So the files themselves ship,
            // copied from duckbench/challenge without a byte changed, and
            // `StairsChallengeResourceTests` pins every one of them by sha256
            // against the list the dataset publishes. `.copy` rather than
            // `.process`: processing is free to rewrite what it recognises,
            // and a rewritten intent file is a different intent. The Duck Cards
            // deck is the same kind of file: microduckstudio.com's
            // `duck-cards.json`, pinned by sha256 in `DuckCardsTests`. The Duck Card packs
            // are copied too: `cardreader/duckcards/packs` holds the same files, byte for
            // byte (`scripts/check_duckcards_vectors.sh`).
            resources: [.copy("Resources/StairsChallenge"), .copy("Resources/Planner"),
                        .copy("Resources/DuckCards"), .copy("Resources/DuckPacks")]
        ),
        // THE ONLY TARGET THAT IMPORTS THE MCP SDK. Apple platforms only: the SDK's HTTP client
        // has no server-sent events on Linux, and the kit's Linux tests must not depend on a
        // network library they do not use. On Linux this target compiles to nothing (its source
        // is behind `#if canImport(MCP)`), and every rule it follows is in StudioKit, tested there.
        .target(
            name: "StudioMCP",
            dependencies: [
                "StudioKit",
                .product(name: "MCP", package: "swift-sdk", condition: .when(platforms: [.iOS, .macOS])),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "StudioMCPTests",
            dependencies: [
                "StudioMCP", "StudioKit",
                .product(name: "MCP", package: "swift-sdk", condition: .when(platforms: [.iOS, .macOS])),
                .product(name: "Logging", package: "swift-log"),
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
