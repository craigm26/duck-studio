import XCTest
import Crypto
@testable import StudioKit

/// `DuckWorld.Bank` AGAINST THE FILES IT WAS TRANSCRIBED FROM, when
/// `duck-sounds` is checked out beside this repository.
///
/// WHY A TRANSCRIPTION NEEDS A TEST. Every number in `DuckWorld.Bank.pinned`
/// is a copy of something the harness owns — five constants in
/// `site/stairs.js` and four wall geoms in `sim/scene_physics.xml` — and the
/// app uses them to decide whether a scene can be sent at all. A drifted copy
/// does not fail loudly: it refuses a flight that would have fitted, or sends
/// one that pushes a 200 kg block through a static wall, and the sentence
/// beside either of those is confidently wrong.
///
/// THE HARNESS WINS. If this fails, `DuckWorld.swift` is what changes.
///
/// AND IT SKIPS RATHER THAN FAILING when `duck-sounds` is not beside this
/// repository — a phone build and a checkout of `duck-studio` alone are both
/// legitimate, and a test that failed there would train somebody to ignore it.
/// Every skip names exactly what was missing. Same shape as `BallFixtureTests`.
final class WorldConstantsFixtureTests: XCTestCase {

    /// A HARNESS THAT IS THERE AND HAS CHANGED IS A FAILURE, NOT A SKIP. Only
    /// a missing checkout skips; a constant that has been renamed or a geom
    /// that has moved has to be read by somebody.
    struct Missing: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static var duckSounds: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // StudioKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // StudioKit
            .deletingLastPathComponent()   // duck-studio
            .deletingLastPathComponent()   // projects
            .appendingPathComponent("duck-sounds")
    }

    private func text(_ relative: String) throws -> String {
        let url = Self.duckSounds.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(url.path) is not checked out beside duck-studio, so the harness's "
                        + "own numbers cannot be read")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - reading the harness's own files

    /// The right-hand side of `export const NAME = …;`, verbatim.
    ///
    /// THE TEXT RATHER THAN A VALUE, because one of the five is an expression.
    /// `STAIR_Y` is written as `1.5 - 0.025 - STAIR_HALF_WIDTH` with a doc
    /// comment explaining that the 0.025 is WRONG — `wall_n` is 50 mm
    /// half-thick, not 25 — and that the number stays because the bodies are
    /// compiled there. A parser that evaluated arbitrary arithmetic would hide
    /// that; asserting the expression letter for letter means a change to it
    /// arrives here as a failure somebody has to read.
    private func constant(_ name: String, in source: String) throws -> String {
        let marker = "export const \(name) = "
        guard let start = source.range(of: marker),
              let end = source.range(of: ";", range: start.upperBound..<source.endIndex) else {
            throw Missing("site/stairs.js no longer declares \(name) as an exported const — "
                        + "the transcription in DuckWorld.Bank has nothing to check itself "
                        + "against, which is a failure and not a skip")
        }
        return String(source[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One attribute of the geom named `geom`, as its numbers.
    private func geomNumbers(_ geom: String, _ attribute: String,
                             in xml: String) throws -> [Double] {
        guard let anchor = xml.range(of: "name=\"\(geom)\"") else {
            throw Missing("scene_physics.xml has no geom called \(geom)")
        }
        // The geom tag ends at the next `/>`; attributes are looked for only
        // inside it, so a later geom cannot answer for this one.
        guard let close = xml.range(of: "/>", range: anchor.upperBound..<xml.endIndex),
              let value = xml.range(of: "\(attribute)=\"",
                                    range: anchor.upperBound..<close.lowerBound),
              let quote = xml.range(of: "\"", range: value.upperBound..<close.lowerBound) else {
            throw Missing("\(geom) has no \(attribute)")
        }
        return xml[value.upperBound..<quote.lowerBound]
            .split(separator: " ")
            .compactMap { Double($0) }
    }

    // MARK: - the five constants in site/stairs.js

    func testTheBankIsTheOneSiteStairsJsDeclares() throws {
        let source = try text("site/stairs.js")
        let bank = DuckWorld.Bank.pinned

        XCTAssertEqual(try constant("STAIR_COUNT", in: source), "\(bank.count)")

        let halfWidth = try XCTUnwrap(Double(try constant("STAIR_HALF_WIDTH", in: source)))
        XCTAssertEqual(halfWidth, bank.halfWidth, accuracy: 1e-12)

        let halfDepth = try XCTUnwrap(Double(try constant("STEP_HALF_DEPTH", in: source)))
        XCTAssertEqual(halfDepth, bank.halfDepth, accuracy: 1e-12)

        let halfHeight = try XCTUnwrap(Double(try constant("STEP_HALF_HEIGHT", in: source)))
        XCTAssertEqual(halfHeight, bank.halfHeight, accuracy: 1e-12)

        // THE ONE THAT IS AN EXPRESSION, AND THE 0.025 IN IT IS A KNOWN
        // MISTAKE THAT IS DELIBERATELY NOT FIXED — `wall_n` is 50 mm
        // half-thick, so the outer 25 mm of every tread sits inside it. The
        // blocks are COMPILED at this y with x and z slides only, so this is
        // where they are, and the app's lateral arithmetic has to be measured
        // from where they are rather than from where they should be.
        XCTAssertEqual(try constant("STAIR_Y", in: source), "1.5 - 0.025 - STAIR_HALF_WIDTH",
                       "STAIR_Y's expression changed; DuckWorld.Bank.y has to be re-derived")
        XCTAssertEqual(1.5 - 0.025 - halfWidth, bank.y, accuracy: 1e-12)
    }

    // MARK: - the plant itself

    func testEveryBlockInThePlantIsTheSizeAndTheMassTheBankClaims() throws {
        let xml = try text("sim/scene_physics.xml")
        let bank = DuckWorld.Bank.pinned

        // FOURTEEN BODIES, COUNTED. `STAIR_COUNT` is a constant in a JavaScript
        // file and the bodies are in the MJCF; nothing but this makes them
        // agree.
        let bodies = (0..<bank.count).filter { xml.contains("<body name=\"step\($0)\"") }
        XCTAssertEqual(bodies.count, bank.count)
        XCTAssertFalse(xml.contains("<body name=\"step\(bank.count)\""),
                       "there is a step\(bank.count) in the plant and the bank says there are "
                     + "only \(bank.count)")

        for i in [0, bank.count - 1] {
            let size = try geomNumbers("step\(i)_geom", "size", in: xml)
            XCTAssertEqual(size, [bank.halfDepth, bank.halfWidth, bank.halfHeight],
                           "step\(i)_geom")
            let mass = try geomNumbers("step\(i)_geom", "mass", in: xml)
            // The refusal message says "200 kg" out loud, so the mass is part
            // of the transcription even though the bank does not store it.
            XCTAssertEqual(mass, [200], "step\(i)_geom's mass")
        }

        // The compiled y of the bodies IS `STAIR_Y`, to the last digit the
        // compiler wrote.
        XCTAssertTrue(xml.contains("<body name=\"step0\" pos=\"0 1.3050000000000002 0\""),
                      "step0 is no longer compiled at STAIR_Y")
    }

    /// THE FOUR WALLS THE ARENA IS, and the 1.45 m every footprint is refused
    /// against.
    func testTheArenaIsTheFourWallsInThePlant() throws {
        let xml = try text("sim/scene_physics.xml")
        let arena = DuckWorld.Arena.pinned
        let bank = DuckWorld.Bank.pinned

        for wall in arena.walls {
            let size = try geomNumbers(wall.name, "size", in: xml)
            let pos = try geomNumbers(wall.name, "pos", in: xml)
            XCTAssertEqual(size.count, 3, wall.name)
            XCTAssertEqual(pos.count, 3, wall.name)
            XCTAssertEqual(pos[0], wall.x, accuracy: 1e-12, wall.name)
            XCTAssertEqual(pos[1], wall.y, accuracy: 1e-12, wall.name)

            // A wall runs along the axis its LONG half size is on, and it is
            // half-thick on the other.
            let alongX = wall.along == "x"
            XCTAssertEqual(size[alongX ? 0 : 1], wall.halfLength, accuracy: 1e-12, wall.name)
            XCTAssertEqual(size[alongX ? 1 : 0], wall.halfThickness, accuracy: 1e-12, wall.name)

            // The geom is half as tall as the wall and sits at that half
            // height, so its top is `height`.
            XCTAssertEqual(size[2] * 2, wall.height, accuracy: 1e-12, wall.name)
            XCTAssertEqual(pos[2], size[2], accuracy: 1e-12, wall.name)

            // THE FACE A BODY MEETS. This is the number every arena refusal is
            // measured against, and it is derived here rather than trusted.
            let centre = alongX ? wall.y : wall.x
            XCTAssertEqual(abs(centre) - wall.halfThickness, bank.arenaInner, accuracy: 1e-12,
                           wall.name)
        }
        XCTAssertEqual(arena.innerX, bank.arenaInner, accuracy: 1e-12)
        XCTAssertEqual(arena.innerY, bank.arenaInner, accuracy: 1e-12)
    }

    /// The ball this app draws is the one in the plant: 50 mm radius, 30 g.
    func testTheBallIsThePlantsBall() throws {
        let xml = try text("sim/scene_physics.xml")
        XCTAssertEqual(try geomNumbers("ball_geom", "size", in: xml), [DuckWorld.ballRadius])
        XCTAssertEqual(try geomNumbers("ball_geom", "mass", in: xml), [0.03])
        let drawn = DuckScene.ball()
        XCTAssertEqual(drawn.grams, 30, accuracy: 1e-9)
        XCTAssertEqual(drawn.length, 0.1, accuracy: 1e-9)
    }

    // MARK: - the bench fixtures are the ones the bench published

    /// EVERY CAPTURED BENCH BODY, BY SHA-256.
    ///
    /// A fixture is evidence only while nobody edits it to agree with the
    /// reader it feeds — that is exactly how a placeholder shipped here once.
    /// So the bytes are pinned, and swapping a hand-written fixture for a
    /// captured one is a reviewable act rather than a quiet edit.
    ///
    /// All three came off a bench: `world.json` is a `POST /world` readback,
    /// and `perform-stood.json` / `climb-clip.json` are the build-47 captures
    /// the bench publishes as `sim/parity/perform-stood-v1.json` and
    /// `sim/parity/climb-clip-v1.json`, copied in without a byte changed.
    func testTheBenchFixturesAreTheOnesTheBenchPublished() throws {
        let digests = [
            "world": "112115ff0839022b83b32ac1d45a8079c81330c3ac9e2ed5fe2dd8b8e4a4dd99",
            "perform-stood": "f43c1d9d23df5e0e6f4bfc5113f1f28b38b7f47f05377c36085e65c0217c539a",
            "climb-clip": "4f8f4a3a7cdc1f7f89458b90f270af93e757ad59efbda1c0c9eaf6f9578dae62",
        ]
        for (name, wanted) in digests.sorted(by: { $0.key < $1.key }) {
            let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/bench/\(name)",
                                                      withExtension: "json"),
                                    "the \(name) fixture is missing")
            let got = SHA256.hash(data: try Data(contentsOf: url))
                .map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(got, wanted, "\(name).json is not the bytes this build pinned")
        }
    }

}
