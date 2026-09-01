import XCTest
@testable import StudioKit

/// A fetch drafted in this app could only leave as a `.duck` — quackd's format
/// — which this app cannot read. So the loop was open at its worst point:
/// describe a fetch, get a file, and be told on re-import that "nothing was
/// added".
final class DuckPlanFileTests: XCTestCase {

    private func stick() -> Retrieval.Stick {
        Retrieval.Stick(grams: 25, thicknessMillimetres: 20, metresAway: 1.0,
                        graspHeightMillimetres: nil, floorFriction: 0.6)
    }

    private func file() -> DuckPlanFile {
        DuckPlanFile(name: "Fetch the stick", stick: stick(),
                     asked: "fetch the stick", provenance: "Qwen3 4B on this phone")
    }

    /// THE CLAIM THAT MATTERS: what this app writes, this app reads.
    func testAPlanSurvivesBeingWrittenAndReadAgain() throws {
        let back = try DuckPlanFile.read(try file().encoded())
        XCTAssertEqual(back, file())
    }

    /// IT STORES THE MEASUREMENT AND RECOMPUTES THE PLAN. A frozen plan would
    /// let a file written last month disagree with the app that opened it, and
    /// the file would win.
    func testThePlanIsDerivedOnReadRatherThanStored() throws {
        let text = String(decoding: try file().encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("steps"), text)
        XCTAssertFalse(text.contains("refusals"), text)
        XCTAssertTrue(text.contains("grams"), text)

        let back = try DuckPlanFile.read(try file().encoded())
        XCTAssertEqual(back.plan, Retrieval.plan(for: stick()))
        XCTAssertFalse(back.plan.steps.isEmpty)
    }

    /// The sentence is kept because it is the only record of what was ASKED
    /// for, as opposed to what the app measured.
    func testWhatWasAskedForSurvives() throws {
        let back = try DuckPlanFile.read(try file().encoded())
        XCTAssertEqual(back.asked, "fetch the stick")
        XCTAssertEqual(back.provenance, "Qwen3 4B on this phone")
    }

    func testAnOptionalGraspHeightSurvivesBothWays() throws {
        let withHeight = DuckPlanFile(
            name: "n",
            stick: Retrieval.Stick(grams: 20, thicknessMillimetres: 18, metresAway: 0.8,
                                   graspHeightMillimetres: 12, floorFriction: 0.5),
            asked: nil, provenance: "Written here")
        XCTAssertEqual(try DuckPlanFile.read(try withHeight.encoded()).stick
                        .graspHeightMillimetres, 12)
        XCTAssertNil(try DuckPlanFile.read(try file().encoded()).stick.graspHeightMillimetres)
    }

    // MARK: - what it refuses

    /// EVERY NUMBER IS REQUIRED. A plan with a defaulted mass is a plan about a
    /// different object, and it would still print a confident verdict about
    /// whether the duck can lift it.
    func testAMissingMeasurementIsRefusedRatherThanDefaulted() {
        let text = """
        {"format":"duck-plan/1","name":"x",
         "object":{"thicknessMillimetres":20,"metresAway":1.0,"floorFriction":0.6}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try DuckPlanFile.read(text)) {
            XCTAssertEqual($0 as? DuckPlanFile.ReadError, .missing("grams"))
        }
    }

    func testAFutureFormatIsNamedRatherThanGuessedAt() {
        let text = #"{"format":"duck-plan/9","name":"x","object":{}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try DuckPlanFile.read(text)) { error in
            XCTAssertEqual(error as? DuckPlanFile.ReadError, .wrongFormat("duck-plan/9"))
            XCTAssertTrue((error as! DuckPlanFile.ReadError).message.contains("does not read"))
        }
    }

    func testSomethingElseEntirelyIsRefused() {
        XCTAssertThrowsError(try DuckPlanFile.read(Data("not json".utf8))) {
            XCTAssertEqual($0 as? DuckPlanFile.ReadError, .notJSON)
        }
        // A .duckmove is JSON, and is not this.
        let move = #"{"format":"duck-move/2","times":[0],"poses":[[]]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try DuckPlanFile.read(move))
    }

    /// The extension is ours and is not `.duck`, which belongs to quackd.
    func testTheFileNameUsesOurOwnExtension() {
        XCTAssertEqual(file().fileName, "Fetch the stick.duckplan")
        XCTAssertFalse(file().fileName.hasSuffix(".duck"))
    }
}
