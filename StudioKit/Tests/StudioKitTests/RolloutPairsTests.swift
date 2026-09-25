import XCTest
import DuckKit
@testable import StudioKit

/// A person's choice between two ducks is only worth recording if the two ducks
/// were in the same world, the side was drawn fairly and written down, and the
/// record names networks rather than screen positions. Those three are what
/// these tests hold.
final class RolloutPairsTests: XCTestCase {

    /// Two policies, two commands, two envs, three frames: small enough to read.
    static func tiny(frame: (Double) -> [Double] = { t in
        [t, 0, 0.12, 1, 0, 0, 0] + Array(repeating: t / 10, count: DuckModel.jointCount)
    }) -> String {
        let clip = "[" + [0.0, 1.0, 2.0].map { t in
            "[" + frame(t).map { String($0) }.joined(separator: ",") + "]"
        }.joined(separator: ",") + "]"
        let envs = "[\(clip),\(clip)]"
        return """
        {"format": "duck-preference-pairs/0",
         "source": {"batch": "p001", "seed": 3001, "simulated": true},
         "hz": 1.0, "seconds": 8.0, "envs": 2,
         "policies": {
           "teacher": {"repo": "pollen-robotics/microduck-policies", "file": "velstand.onnx", "fingerprint": "sha256:aa"},
           "student": {"repo": "craigm26/microduck-duckbatch-b002-128x128", "fingerprint": "sha256:bb"}},
         "commands": {"fwd": [0.15, 0.0, 0.0], "turn": [0.0, 0.0, 0.6]},
         "close_first": {"fwd": [{"a": "teacher", "b": "student", "distance": 0.1}],
                         "turn": [{"a": "student", "b": "teacher", "distance": 0.2}]},
         "clips": {"teacher__fwd": \(envs), "teacher__turn": \(envs),
                   "student__fwd": \(envs), "student__turn": \(envs)}}
        """
    }

    private func pairs(_ json: String = tiny()) throws -> RolloutPairs {
        try RolloutPairs.read(Data(json.utf8))
    }

    /// Always the same side, so a test can say which network is where.
    private struct Fixed: RandomNumberGenerator {
        let value: UInt64
        mutating func next() -> UInt64 { value }
    }

    // MARK: - reading

    func testPairsReadWithTheirNetworksCommandsAndOrder() throws {
        let p = try pairs()
        XCTAssertEqual(p.policies["teacher"]?.file, "velstand.onnx")
        XCTAssertEqual(p.policies["student"]?.fingerprint, "sha256:bb")
        XCTAssertEqual(p.commandNames, ["fwd", "turn"])
        XCTAssertEqual(p.closeFirst["turn"]?.first?.a, "student")
        XCTAssertEqual(p.seed, 3001)
    }

    func testAFrameOfTheWrongWidthRefusesThePairsRatherThanDrawingAWrongDuck() {
        let narrow = Self.tiny { t in [t, 0, 0.12, 1, 0, 0, 0] + Array(repeating: 0, count: 14) }
        XCTAssertThrowsError(try pairs(narrow)) { error in
            guard case RolloutPairs.ReadError.badFrame = error else { return XCTFail("\(error)") }
        }
    }

    func testAMissingClipIsRefusedByName() {
        let gone = Self.tiny().replacingOccurrences(of: "\"student__turn\"", with: "\"student__spin\"")
        XCTAssertThrowsError(try pairs(gone)) { error in
            XCTAssertEqual(error as? RolloutPairs.ReadError,
                           .missing("the clip of student under turn"))
        }
    }

    // MARK: - drawing

    func testTheStanceIsInterpolatedBetweenRecordedFrames() throws {
        let s = try pairs().stance("teacher", "fwd", env: 0, at: 0.5)
        XCTAssertEqual(s.root.x, 0.5, accuracy: 1e-12)
        XCTAssertEqual(s.jointAngles.count, DuckModel.jointCount)
        XCTAssertEqual(s.jointAngles[0], 0.05, accuracy: 1e-12)
    }

    func testARolloutHoldsItsLastFrameRatherThanLooping() throws {
        let p = try pairs()
        XCTAssertEqual(p.stance("teacher", "fwd", env: 0, at: 60).root.x, 2,
                       "a duck that fell stays fallen")
        XCTAssertEqual(p.duration("teacher", "fwd", env: 0), 2)
    }

    func testAQuaternionThatFlipsSignBetweenFramesTakesTheShortWay() throws {
        // q and -q are the same orientation; halfway between them is still it.
        let p = try pairs(Self.tiny { t in
            let q = t == 1 ? [-1.0, 0, 0, 0] : [1.0, 0, 0, 0]
            return [0, 0, 0.12] + q + Array(repeating: 0, count: DuckModel.jointCount)
        })
        let q = p.stance("teacher", "fwd", env: 0, at: 0.5).root.quaternion
        XCTAssertEqual(abs(q.0), 1, accuracy: 1e-12)
    }

    // MARK: - the deck

    func testEveryCommandsClosestPairComesBeforeAnySecondPair() throws {
        var deck = PreferenceDeck(try pairs())
        var rng = Fixed(value: 0)
        let first = deck.next(using: &rng), second = deck.next(using: &rng)
        XCTAssertEqual([first?.command, second?.command], ["fwd", "turn"])
    }

    func testBothSidesOfAShowingAreInTheSameEnv() throws {
        var deck = PreferenceDeck(try pairs())
        var rng = Fixed(value: 0)
        for _ in 0..<6 {
            let s = try XCTUnwrap(deck.next(using: &rng))
            XCTAssertTrue((0..<2).contains(s.env))
            XCTAssertNotEqual(s.left, s.right)
        }
    }

    func testTheSideIsDrawnAndBothSidesHappen() throws {
        var deck = PreferenceDeck(try pairs())
        var sides = Set<DuckFeedback.Order>()
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<64 { if let s = deck.next(using: &rng) { sides.insert(s.order) } }
        XCTAssertEqual(sides, [.aLeft, .bLeft])
    }

    func testAFileWithoutUsableEnvsShowsEveryEnv() throws {
        XCTAssertEqual(try pairs().usableEnvs["fwd"], [0, 1])
    }

    func testTheDeckNeverShowsASlotTheExporterDropped() throws {
        let json = Self.tiny().replacingOccurrences(
            of: #""clips":"#, with: #""usable_envs": {"fwd": [1], "turn": []}, "clips":"#)
        var deck = PreferenceDeck(try pairs(json))
        var rng = Fixed(value: 0)
        for _ in 0..<8 {
            let s = try XCTUnwrap(deck.next(using: &rng))
            XCTAssertEqual(s.command, "fwd", "a command with no usable env is skipped")
            XCTAssertEqual(s.env, 1)
        }
    }

    // MARK: - the record

    func testPickingTheLeftDuckRecordsTheNetworkThatWasOnTheLeft() throws {
        let p = try pairs()
        let showing = RolloutPairs.Showing(command: "fwd", env: 1, a: "teacher", b: "student",
                                           order: .bLeft)
        XCTAssertEqual(showing.left, "student")
        let line = try p.record(.left, reasons: [.steadier], for: showing, share: .local,
                                client: "t").jsonLine()
        XCTAssertTrue(line.contains(#""choice":"b""#), "b was on the left")
        XCTAssertTrue(line.contains(#""order":"b_left""#))
        XCTAssertTrue(line.contains(#""pair_id":"p001/fwd/1""#))
        XCTAssertTrue(line.contains(#""where":"sim""#))
        XCTAssertTrue(line.contains(#""seed":3001"#))
        XCTAssertTrue(line.contains(#""fingerprint":"sha256:bb""#))
    }

    func testATieAndBothBadAreAnswersInTheirOwnRight() throws {
        let p = try pairs()
        let showing = RolloutPairs.Showing(command: "turn", env: 0, a: "student", b: "teacher",
                                           order: .aLeft)
        XCTAssertTrue(try p.record(.tie, reasons: [], for: showing, share: .local, client: "t")
            .jsonLine().contains(#""choice":"tie""#))
        XCTAssertTrue(try p.record(.bothBad, reasons: [.fell], for: showing, share: .local, client: "t")
            .jsonLine().contains(#""choice":"both_bad""#))
    }

    // MARK: - the file the app ships

    /// The bundled export, found from this file rather than from a machine's
    /// home directory, so it runs wherever the repository is checked out.
    static var bundled: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DuckStudio/Resources/p001-pairs.json")
    }

    func testTheBundledPairsReadAndNameAlphaWalkingByItsOfficialFingerprint() throws {
        let p = try RolloutPairs.read(Data(contentsOf: Self.bundled))
        XCTAssertEqual(p.policies.count, 4)
        XCTAssertEqual(p.commandNames.count, 5)
        XCTAssertEqual(p.envs, 4)
        XCTAssertEqual(p.policies["alpha_walking"]?.fingerprint,
                       "sha256:da820b718aa8bdb3317c018afba3ad3f461e0cf42256811c204dc005546ec4a3",
                       "duckkit's recorded official value")
        XCTAssertTrue(p.closeFirst.values.allSatisfy { $0.count == 6 }, "every pair of four, per command")
        XCTAssertFalse(p.usableEnvs["fwd_025"]?.contains(3) ?? true,
                       "env 3 never received a moving command in p001")
        XCTAssertEqual(p.usableEnvs["stand"], [0, 1, 2, 3])
    }

    func testTheBundledFirstFrameIsThePolicysOwnStandingPoseWithTheMouthShut() throws {
        let p = try RolloutPairs.read(Data(contentsOf: Self.bundled))
        let s = p.stance("velstand", "stand", env: 0, at: 0)
        XCTAssertEqual(s.jointAngles[DuckModel.mouthIndex], 0)
        XCTAssertEqual(s.root.x, 0, "re-zeroed per env")
        XCTAssertEqual(s.root.z, 0.121, accuracy: 0.01, "standing height")
    }

    /// Writes a few preferences over the real pairs for duckbatch's reader:
    /// `DUCK_PAIRS_FEEDBACK_OUT=… swift test --filter RolloutPairsTests`.
    func testWritesPreferencesForTheReaderCrossCheck() throws {
        guard let out = ProcessInfo.processInfo.environment["DUCK_PAIRS_FEEDBACK_OUT"] else { return }
        let p = try RolloutPairs.read(Data(contentsOf: Self.bundled))
        var deck = PreferenceDeck(p)
        var lines: [String] = []
        for pick in RolloutPairs.Pick.allCases {
            let s = try XCTUnwrap(deck.next())
            lines.append(try p.record(pick, reasons: [.moreNatural], for: s, share: .research,
                                      client: "Microduck Studio test").jsonLine())
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }
}

final class RolloutPreferenceWordsTests: XCTestCase {

    func testTheCommandIsSaidInWordsForEachKindOfRollout() {
        XCTAssertEqual(RolloutPreferenceWords.asked([0, 0, 0]), "Both were asked to stand still.")
        XCTAssertEqual(RolloutPreferenceWords.asked([0.15, 0, 0]),
                       "Both were asked to walk forward at 0.15 m/s.")
        XCTAssertEqual(RolloutPreferenceWords.asked([0, 0, 0.6]),
                       "Both were asked to turn on the spot at 0.6 rad/s.")
        XCTAssertTrue(RolloutPreferenceWords.asked([0.15, 0, 0.4]).contains("arc"))
    }

    func testEveryReasonOnTheFixedListHasWords() {
        let words = DuckFeedback.Reason.allCases.map(RolloutPreferenceWords.reason)
        XCTAssertEqual(Set(words).count, DuckFeedback.Reason.allCases.count)
    }

    func testTheTallySaysNothingIsRankedHere() {
        XCTAssertTrue(RolloutPreferenceWords.tally(3).hasPrefix("3 choices on this phone."))
        XCTAssertTrue(RolloutPreferenceWords.tally(3).contains("ranks nothing"))
    }

    func testTheScreenNeverNamesTheWalkers() {
        let all = [RolloutPreferenceWords.intro, RolloutPreferenceWords.simulated,
                   RolloutPreferenceWords.left, RolloutPreferenceWords.right]
        for word in ["teacher", "student", "velstand", "alpha"] {
            XCTAssertFalse(all.contains { $0.lowercased().contains(word) }, word)
        }
    }
}
