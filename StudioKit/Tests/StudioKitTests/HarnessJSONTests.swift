import XCTest
@testable import StudioKit

/// The parser that exists because Foundation's loses the two things a stairs
/// challenge entry is identified by: the order of an object's keys, and the
/// exact digits of its numbers.
final class HarnessJSONTests: XCTestCase {

    // MARK: - the property everything else rests on

    /// EVERY BUNDLED CHALLENGE FILE RE-ENCODES TO ITS OWN BYTES. Not "parses",
    /// not "round-trips semantically" — the same bytes. If this ever fails,
    /// every move this app sends to a bench is a different move from the one
    /// on the leaderboard, and every number it shows is filed under a hash
    /// nobody can look up.
    func testEveryBundledIntentReEncodesByteForByte() throws {
        for file in StairsChallenge.bundledFiles {
            let original = try StairsChallenge.intentData(named: file)
            let parsed = try HarnessJSON.parse(original)
            XCTAssertEqual(parsed.encoded(.pretty), original,
                           "\(file) did not survive a round trip byte for byte")
        }
    }

    func testKeyOrderSurvives() throws {
        let source = Data(#"{"z":1,"a":2,"m":{"q":3,"b":4}}"#.utf8)
        let value = try HarnessJSON.parse(source)
        XCTAssertEqual(value.members?.map(\.key), ["z", "a", "m"])
        XCTAssertEqual(value["m"]?.members?.map(\.key), ["q", "b"])
        XCTAssertEqual(String(data: value.encoded(.compact), encoding: .utf8),
                       #"{"z":1,"a":2,"m":{"q":3,"b":4}}"#)
    }

    /// A keyframe is `{"t": …, "pose": […]}` and the harness hashes it in that
    /// order. Written the other way round it is a different move.
    func testAKeyframesKeyOrderIsTheOneTheHashSees() throws {
        let file = try StairsChallenge.intentData(named: "best_r6_ceilvaultC_60mm")
        let move = try HarnessJSON.parse(file)
        let first = try XCTUnwrap(move["keyframes"]?.arrayValue?.first)
        XCTAssertEqual(first.members?.map(\.key), ["t", "pose"])
    }

    func testNumberDigitsSurviveExactly() throws {
        // 2.1153 is a blend parameter; 0.6405 is the plant's torque ceiling.
        let value = try HarnessJSON.parse(Data(#"{"blend":2.1153,"tq":0.6405,"n":4,"z":0}"#.utf8))
        XCTAssertEqual(String(data: value.encoded(.compact), encoding: .utf8),
                       #"{"blend":2.1153,"tq":0.6405,"n":4,"z":0}"#)
        XCTAssertEqual(value["blend"]?.doubleValue, 2.1153)
        XCTAssertEqual(value["n"]?.doubleValue, 4)
    }

    /// An integer written as `4` must not come back as `4.0`: JavaScript's
    /// `JSON.stringify` writes `4`, and the hash is taken over its output.
    func testAWholeNumberWritesTheWayJavaScriptWritesIt() {
        XCTAssertEqual(HarnessJSON.literal(for: 4), "4")
        XCTAssertEqual(HarnessJSON.literal(for: 0), "0")
        XCTAssertEqual(HarnessJSON.literal(for: -1), "-1")
        XCTAssertEqual(HarnessJSON.literal(for: 2.1153), "2.1153")
        XCTAssertEqual(HarnessJSON.literal(for: -0.0873), "-0.0873")
        // Swift spells this "1e-07"; JavaScript spells it "1e-7".
        XCTAssertEqual(HarnessJSON.literal(for: 1e-7), "1e-7")
    }

    func testEscapesAndNonASCIISurvive() throws {
        // The corner-climb file carries an escaped quote; three round-6 files
        // carry an em dash raw, which is what JSON.stringify emits.
        let quoted = try HarnessJSON.parse(Data(#"{"a":"say \"hi\"","b":"R6 — vault"}"#.utf8))
        XCTAssertEqual(quoted["a"]?.stringValue, "say \"hi\"")
        XCTAssertEqual(quoted["b"]?.stringValue, "R6 — vault")
        XCTAssertEqual(String(data: quoted.encoded(.compact), encoding: .utf8),
                       #"{"a":"say \"hi\"","b":"R6 — vault"}"#)
    }

    /// A string this app BUILDS has no source text to copy, so the writer's
    /// own escaping has to match `JSON.stringify`'s: the two structural
    /// characters and the control range, and non-ASCII left alone.
    func testAStringBuiltHereIsEscapedTheWayJavaScriptEscapesIt() {
        XCTAssertEqual(HarnessJSON.quote("a\"b\\c"), #""a\"b\\c""#)
        XCTAssertEqual(HarnessJSON.quote("line\nbreak"), #""line\nbreak""#)
        XCTAssertEqual(HarnessJSON.quote("é — ok"), "\"é — ok\"")
    }

    func testPrettyIsTwoSpacesLikeJSONStringifyWithTwo() throws {
        let value = try HarnessJSON.parse(Data(#"{"a":[1,2],"b":{}}"#.utf8))
        XCTAssertEqual(String(data: value.encoded(.pretty), encoding: .utf8), """
        {
          "a": [
            1,
            2
          ],
          "b": {}
        }
        """)
    }

    func testSettingKeepsAKeysPosition() throws {
        let value = try HarnessJSON.parse(Data(#"{"a":1,"b":2,"c":3}"#.utf8))
        let changed = value.setting("b", to: .number(9))
        XCTAssertEqual(String(data: changed.encoded(.compact), encoding: .utf8),
                       #"{"a":1,"b":9,"c":3}"#)
        let added = value.setting("d", to: .number(4))
        XCTAssertEqual(String(data: added.encoded(.compact), encoding: .utf8),
                       #"{"a":1,"b":2,"c":3,"d":4}"#)
    }

    func testRubbishIsRefusedRatherThanGuessedAt() {
        XCTAssertThrowsError(try HarnessJSON.parse(Data("{".utf8)))
        XCTAssertThrowsError(try HarnessJSON.parse(Data(#"{"a":}"#.utf8)))
        XCTAssertThrowsError(try HarnessJSON.parse(Data(#"{"a":1} {"b":2}"#.utf8)))
        XCTAssertThrowsError(try HarnessJSON.parse(Data(#"{"a":1,}"#.utf8)))
    }
}
