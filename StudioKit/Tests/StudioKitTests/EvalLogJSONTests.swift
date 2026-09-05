import XCTest
@testable import StudioKit

/// The six rules of the log writer, one test each, plus the number table.
///
/// WHY THE TABLE IS THE GATE. `EvalLogJSON.spelled(_:)` is `"\(value)"` and
/// that is a claim about two languages agreeing, not a line of code. Sixteen
/// values were put through Swift 6.3.3 and CPython's `json.dumps` in the same
/// session and every spelling matched, `1e15` written `1000000000000000.0`
/// included. The table below is that measurement, kept where a change to the
/// writer has to walk past it. A rule resting on "we will never write a number
/// like that" is not a rule.
final class EvalLogJSONTests: XCTestCase {

    private func text(_ value: EvalLogJSON) -> String { value.encodedText() }

    // MARK: - rule 1, the shape

    func testAnObjectIsIndentedTwoSpacesWithAColonSpaceAfterEachKey() {
        let value = EvalLogJSON.object(["a": .integer(1), "b": .string("x")])
        XCTAssertEqual(text(value), "{\n  \"a\": 1,\n  \"b\": \"x\"\n}")
    }

    func testNestingIndentsByTwoMoreEachTime() {
        let value = EvalLogJSON.object(["outer": .object(["inner": .array([.integer(1)])])])
        XCTAssertEqual(text(value),
                       "{\n  \"outer\": {\n    \"inner\": [\n      1\n    ]\n  }\n}")
    }

    func testAnEmptyContainerIsTwoCharacters() {
        XCTAssertEqual(text(.object([:])), "{}")
        XCTAssertEqual(text(.array([])), "[]")
        XCTAssertEqual(text(.object(["a": .object([:]), "b": .array([])])),
                       "{\n  \"a\": {},\n  \"b\": []\n}")
    }

    // MARK: - rule 2, the key order

    /// THE PAIR THAT SEPARATES THE TWO COMPARISONS. Python sorts by code point,
    /// so U+0100 comes before U+212B. Swift's own `String.<` normalises first,
    /// which turns U+212B into U+00C5 and puts it FIRST. A writer that used
    /// `sorted()` would pass every ASCII test in this file and write the wrong
    /// order the first time a log carried an accented scorer name.
    func testKeysSortByUTF8BytesAndNotBySwiftsOwnComparison() {
        let angstrom = "\u{212B}", aMacron = "\u{0100}"
        XCTAssertTrue(angstrom < aMacron, "the premise of this test has changed")
        XCTAssertFalse(angstrom.utf8.lexicographicallyPrecedes(aMacron.utf8))
        let value = EvalLogJSON.object([angstrom: .integer(1), aMacron: .integer(2)])
        XCTAssertEqual(text(value), "{\n  \"\\u0100\": 2,\n  \"\\u212b\": 1\n}")
    }

    func testKeysSortAsciiTheWayPythonDoes() {
        let value = EvalLogJSON.object(["Z": .integer(1), "a": .integer(2), "A": .integer(3)])
        XCTAssertEqual(text(value), "{\n  \"A\": 3,\n  \"Z\": 1,\n  \"a\": 2\n}")
    }

    // MARK: - rule 3, the number table

    /// Measured against `json.dumps` on 2026-09-05, Swift 6.3.3, CPython 3.13.
    /// Left is the value, right is what BOTH languages print.
    static let spellings: [(Double, String)] = [
        (1e15, "1000000000000000.0"),
        (-0.0, "-0.0"),
        (1e-05, "1e-05"),
        (1e16, "1e+16"),
        (1e21, "1e+21"),
        (5e-324, "5e-324"),
        (1.2345678901234568e17, "1.2345678901234568e+17"),
        (0.1, "0.1"),
        (1.0, "1.0"),
        (3.0, "3.0"),
        (0.03826616399601335, "0.03826616399601335"),
        (1e-07, "1e-07"),
        (0.1163, "0.1163"),
        (123456789.0, "123456789.0"),
        (2.5, "2.5"),
        (-1.5, "-1.5"),
    ]

    func testEveryMeasuredDoubleIsSpelledTheWayPythonSpellsIt() {
        for (value, wanted) in Self.spellings {
            XCTAssertEqual(EvalLogJSON.spelled(value), wanted)
            XCTAssertEqual(text(.double(value)), wanted)
        }
        XCTAssertEqual(Self.spellings.count, 16)
    }

    // MARK: - rule 4, integers and doubles stay apart

    func testAWholeNumberAndAScoreOfOneAreDifferentTokens() {
        XCTAssertEqual(text(.integer(3)), "3")
        XCTAssertEqual(text(.double(1.0)), "1.0")
        XCTAssertEqual(text(.object(["n": .number(3), "s": .number(1.0)])),
                       "{\n  \"n\": 3,\n  \"s\": 1.0\n}")
    }

    func testParsingKeepsTheDistinctionTheSourceTextMade() throws {
        let value = try EvalLogJSON.parse(Data("{\"a\": 80, \"b\": 80.0, \"c\": 8e1}".utf8))
        XCTAssertEqual(value["a"], .integer(80))
        XCTAssertEqual(value["b"], .double(80.0))
        XCTAssertEqual(value["c"], .double(80.0))
        XCTAssertEqual(text(value), "{\n  \"a\": 80,\n  \"b\": 80.0,\n  \"c\": 80.0\n}")
    }

    // MARK: - rule 5, the escaping

    /// The whole `py_encode_basestring_ascii` rule in one string: a short
    /// escape, a DEL, an accented letter, two characters that are in the bench's
    /// own criterion sentence, an emoji that needs a surrogate pair, and a
    /// forward slash that must NOT be escaped.
    func testStringsEscapeExactlyTheWayPythonDoesWithEnsureAscii() {
        let value = "a\tb\u{7f}c\u{e9}d\u{2014}e\u{2212}f\u{1F986}g/h\"i\\j"
        XCTAssertEqual(EvalLogJSON.escaped(value),
                       "\"a\\tb\\u007fc\\u00e9d\\u2014e\\u2212f\\ud83e\\udd86g/h\\\"i\\\\j\"")
    }

    func testTheFiveShortEscapesAreTheShortOnes() {
        XCTAssertEqual(EvalLogJSON.escaped("\u{08}\u{0C}\n\r\t"), "\"\\b\\f\\n\\r\\t\"")
    }

    func testAControlCharacterBelowSpaceIsAFourDigitEscape() {
        XCTAssertEqual(EvalLogJSON.escaped("\u{01}\u{1f}"), "\"\\u0001\\u001f\"")
    }

    func testAKeyIsEscapedTheSameWayAValueIs() {
        XCTAssertEqual(text(.object(["\u{e9}": .string("\u{e9}")])),
                       "{\n  \"\\u00e9\": \"\\u00e9\"\n}")
    }

    // MARK: - rule 6, no trailing newline

    func testThereIsNoTrailingNewline() {
        let data = EvalLogJSON.object(["a": .integer(1)]).encoded()
        XCTAssertEqual(data.last, UInt8(ascii: "}"))
    }

    // MARK: - the sanitiser

    func testANonFiniteDoubleIsNullAtConstruction() {
        XCTAssertEqual(EvalLogJSON.number(Double.nan), .null)
        XCTAssertEqual(EvalLogJSON.number(Double.infinity), .null)
        XCTAssertEqual(EvalLogJSON.number(-Double.infinity), .null)
        XCTAssertEqual(EvalLogJSON.numbers(["a": .nan, "b": 1.0]),
                       .object(["a": .null, "b": .double(1.0)]))
    }

    func testTheSanitiserWalksTheWholeTree() {
        let dirty = EvalLogJSON.object(["a": .array([.double(.nan), .double(2)]),
                                        "b": .object(["c": .double(.infinity)])])
        XCTAssertEqual(dirty.sanitized(),
                       .object(["a": .array([.null, .double(2)]),
                                "b": .object(["c": .null])]))
    }

    /// Belt as well as braces: a tree assembled by hand out of `.double(.nan)`
    /// still cannot write a token no JSON parser accepts.
    func testAHandBuiltNonFiniteStillWritesNull() {
        XCTAssertEqual(text(.double(.nan)), "null")
    }

    // MARK: - the parser

    func testItReadsTheThingsAJSONFileIsMadeOf() throws {
        let value = try EvalLogJSON.parse(Data(
            "{\"n\": null, \"t\": true, \"f\": false, \"s\": \"x\", \"a\": [1, 2.5]}".utf8))
        XCTAssertEqual(value["n"], .null)
        XCTAssertEqual(value["t"], .bool(true))
        XCTAssertEqual(value["f"], .bool(false))
        XCTAssertEqual(value["s"], .string("x"))
        XCTAssertEqual(value["a"], .array([.integer(1), .double(2.5)]))
    }

    func testItReadsAnEscapeBackToTheCharacterItStandsFor() throws {
        let value = try EvalLogJSON.parse(Data(
            "{\"k\": \"\\u00e9\\ud83e\\udd86\\t\\/\"}".utf8))
        XCTAssertEqual(value["k"]?.stringValue, "\u{e9}\u{1F986}\t/")
    }

    func testASecondValueAfterTheFirstIsRefused() {
        XCTAssertThrowsError(try EvalLogJSON.parse(Data("{} {}".utf8)))
    }

    func testATruncatedFileIsRefused() {
        XCTAssertThrowsError(try EvalLogJSON.parse(Data("{\"a\": ".utf8)))
    }
}
