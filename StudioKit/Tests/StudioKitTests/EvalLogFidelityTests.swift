import XCTest
import Crypto
@testable import StudioKit

/// The cheapest strong gate this feature has: upstream's own log, read here and
/// written back byte for byte.
///
/// WHY THIS TEST IS THE ONE THAT MATTERS. Everything else in the evaluation
/// feature rests on the claim that a file this app writes is a file
/// `inspect-robots` reads and `inspect-robots view` renders. That claim can be
/// checked three ways: by reading their source, by running their library, or by
/// reproducing their output. Only the third needs nothing but `swift test`, and
/// a gate that needs a venv and a Pi is a gate somebody skips. So the fixture
/// beside this file is a REAL log, written by inspect-robots 0.58.0 on
/// 2026-09-05 from a mock cubepick-reach run, four scenes by three epochs, and
/// this test parses it, re-encodes it, and requires the same 5897 bytes back.
///
/// Passing it proves, all at once and against their output rather than against
/// this repository's idea of it: the key sort, the two-space indent, the
/// integer and float split, the string escaping, the null conventions, and the
/// absent trailing newline.
///
/// THE DIGEST IS PINNED THE WAY THE CHALLENGE CORPUS IS PINNED
/// (`StairsChallengeTests`), because a fixture that can be edited to make a
/// test pass is not a fixture. If this digest ever has to change, the reason is
/// a new capture from their library and the new bytes have to be checked in
/// with it.
final class EvalLogFidelityTests: XCTestCase {

    /// `sha256` of `Fixtures/evallog/reference-cubepick.json`, which is
    /// `scratchpad/reference-evallog.json` vendored without a byte changed.
    static let referenceDigest =
        "9b829c9609369e6ea88e15305cf1b451d6353f11235b3c6b85cd38a7b74de36f"
    static let referenceBytes = 5897

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func referenceData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "reference-cubepick",
                                                  withExtension: "json",
                                                  subdirectory: "Fixtures/evallog"),
                                "missing Fixtures/evallog/reference-cubepick.json")
        return try Data(contentsOf: url)
    }

    func testTheFixtureIsTheBytesInspectRobotsWrote() throws {
        let data = try referenceData()
        XCTAssertEqual(data.count, Self.referenceBytes)
        XCTAssertEqual(Self.digest(data), Self.referenceDigest,
                       "the reference log has been edited; a fixture that can be edited to make "
                     + "a test pass proves nothing")
        XCTAssertEqual(data.last, UInt8(ascii: "}"), "their writer leaves no trailing newline")
    }

    /// THE GATE. Parse, re-encode, compare bytes.
    func testUpstreamsOwnLogReEncodesByteForByte() throws {
        let data = try referenceData()
        let parsed = try EvalLogJSON.parse(data)
        XCTAssertEqual(parsed.encoded(), data,
                       "this writer no longer spells JSON the way json.dumps spells it")
    }

    /// The same round trip THROUGH THE FIVE SCHEMA STRUCTS, which is a strictly
    /// stronger claim: the first test proves the serializer, this one proves
    /// that every one of the forty keys survives being turned into a typed
    /// field and back. A field this app forgot to carry would show up here as a
    /// missing key, and nowhere else.
    func testTheSchemaStructsCarryEveryKeyBackOutAgain() throws {
        let data = try referenceData()
        let log = try EvalLog.decoded(from: data)
        XCTAssertEqual(log.encoded(), data,
                       "a field went missing between the file and the structs")
    }

    func testWhatTheReferenceLogActuallySays() throws {
        let log = try EvalLog.decoded(from: try referenceData())
        XCTAssertEqual(log.version, 1)
        XCTAssertEqual(log.status, .success)
        XCTAssertEqual(log.eval.task, "cubepick-reach")
        XCTAssertEqual(log.eval.policy, "scripted")
        XCTAssertEqual(log.eval.embodiment, "cubepick")
        XCTAssertEqual(log.eval.inspectRobotsVersion, "0.58.0")
        XCTAssertEqual(log.eval.seed, 7)
        XCTAssertEqual(log.eval.maxSteps, 80)
        XCTAssertNil(log.eval.maxSeconds)
        XCTAssertNil(log.eval.gitCommit)
        XCTAssertEqual(log.results.totalScenes, 4)
        XCTAssertEqual(log.results.totalTrials, 12)
        XCTAssertEqual(log.results.erroredTrials, 0)
        XCTAssertEqual(log.results.metrics["success_at_end"], 1.0)
        XCTAssertEqual(log.stats.totalSteps, 111)
        XCTAssertNil(log.stats.framesDir)
        XCTAssertNil(log.stats.meanInferenceLatencySeconds)
        XCTAssertEqual(log.samples.count, 4)
        XCTAssertEqual(log.samples.first?.sceneID, "scene-0")
        XCTAssertEqual(log.samples.first?.instruction, "reach the cube")
        XCTAssertEqual(log.samples.first?.epochs.count, 3)
    }

    /// EIGHT ARRAYS, ONE LENGTH. Their schema puts one trial's verdict, one
    /// trial's termination reason and one trial's metadata at the same index, so
    /// a short array quietly files one trial's answer against another trial.
    func testEveryParallelArrayInTheirOwnLogIsTheSameLength() throws {
        let log = try EvalLog.decoded(from: try referenceData())
        for sample in log.samples {
            XCTAssertEqual(Set(sample.parallelLengths.values), [sample.epochs.count],
                           "scene \(sample.sceneID) has ragged arrays: \(sample.parallelLengths)")
        }
    }

    // MARK: - as strict as their reader

    func testAVersionThatIsNotOneIsRefused() throws {
        let data = try referenceData()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
            .replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2")
        XCTAssertThrowsError(try EvalLog.decoded(from: Data(text.utf8))) { error in
            XCTAssertEqual(error as? EvalLogRefusal, .unsupportedVersion("2"))
        }
    }

    /// Their `EvalSpec(**data["eval"])` raises `TypeError` on an extra keyword,
    /// measured this session. A reader here that shrugged one off would show a
    /// log their own tools refuse to open.
    func testAnUnknownKeyIsRefusedByNameAndByTheObjectItSatIn() throws {
        let data = try referenceData()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
            .replacingOccurrences(of: "\"created\":", with: "\"extra\": 1,\n    \"created\":")
        XCTAssertThrowsError(try EvalLog.decoded(from: Data(text.utf8))) { error in
            XCTAssertEqual(error as? EvalLogRefusal, .unknownKey("extra", in: "eval"))
        }
    }

    func testARequiredFieldThatIsMissingIsRefusedByName() throws {
        let data = try referenceData()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
            .replacingOccurrences(of: "\"total_steps\": 111", with: "\"total_stepz\": 111")
        XCTAssertThrowsError(try EvalLog.decoded(from: Data(text.utf8))) { error in
            // The renamed key is unknown before the real one is missing, and
            // naming the unknown one is the more useful of the two sentences.
            XCTAssertEqual(error as? EvalLogRefusal, .unknownKey("total_stepz", in: "stats"))
        }
    }

    func testEveryRefusalSaysSomethingAPersonCanActOn() {
        let refusals: [EvalLogRefusal] = [
            .notJSON("no"), .notAnObject("eval"), .unsupportedVersion("2"),
            .unknownKey("extra", in: "eval"), .missing("status", in: "the log"),
            .wrongType("version", in: "the log", wanted: "a whole number"),
        ]
        for refusal in refusals {
            XCTAssertFalse(refusal.message.isEmpty)
            XCTAssertFalse(refusal.message.contains("\u{2014}"), refusal.message)
        }
    }

    // MARK: - the forty keys

    func testTheKeyListIsFortyDistinctStrings() {
        XCTAssertEqual(EvalLog.Key.all.count, 40)
        XCTAssertEqual(Set(EvalLog.Key.all).count, 40)
    }

    /// `Key.topLevel` IS THE WRITING SIDE'S LIST, so it is checked against what
    /// the writer writes rather than against what the reader refuses. The
    /// reader holds no log to it: `from_dict` reads the top level by name and
    /// ignores a key it has no field for, and so does this.
    func testTheTopLevelListIsWhatThisAppActuallyWrites() throws {
        for entry in try EvalFixtures.corpus() {
            let parsed = try EvalLogJSON.parse(entry.file.bytes)
            let keys = Set(parsed.objectValue?.keys ?? [:].keys)
            XCTAssertEqual(keys, EvalLog.Key.topLevel, entry.name)
        }
    }

    /// The union of the five objects in their own log IS the list. Two
    /// independent statements of the same fact, which is the point: the list is
    /// typed out in `EvalLog.swift` and this reads it off the file.
    func testTheKeyListIsExactlyWhatTheirOwnLogCarries() throws {
        let parsed = try EvalLogJSON.parse(try referenceData())
        func keys(_ value: EvalLogJSON?) -> [String] {
            Array(value?.objectValue?.keys ?? [:].keys)
        }
        var found = Set(keys(parsed))
        for object in ["eval", "results", "stats"] { found.formUnion(keys(parsed[object])) }
        for sample in parsed["samples"]?.arrayValue ?? [] { found.formUnion(keys(sample)) }
        XCTAssertEqual(found, Set(EvalLog.Key.all))
    }
}
