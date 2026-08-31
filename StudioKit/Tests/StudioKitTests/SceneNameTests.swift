import XCTest
@testable import StudioKit

/// The editor's name field is the only writer of a scene's name, so this is the
/// only gate between a person's keyboard and a row nobody can pick.
final class SceneNameTests: XCTestCase {

    func testANameWithNothingInItIsRefusedAndTheOldNameIsQuotedBack() {
        let refusal = SceneName.refusal("", keeping: "Front porch")
        XCTAssertEqual(refusal,
                       "A scene with no name is a blank row in every menu that offers it. "
                       + "The name is still \u{201C}Front porch\u{201D}.")
    }

    /// SPACES ARE NOT A NAME. A row called " " is exactly as unpickable as a row
    /// called nothing, and it is easier to type by accident.
    func testWhitespaceOnlyIsRefusedTheSameWayAsEmpty() {
        XCTAssertEqual(SceneName.refusal("   ", keeping: "Corridor"),
                       SceneName.refusal("", keeping: "Corridor"))
        XCTAssertNotNil(SceneName.refusal("\n\t ", keeping: "Corridor"))
    }

    func testTheRefusalNamesTheConsequenceAndEndsInASentence() throws {
        let refusal = try XCTUnwrap(SceneName.refusal("", keeping: "Staircase"))
        XCTAssertTrue(refusal.contains("blank row"), refusal)
        XCTAssertTrue(refusal.contains("Staircase"), refusal)
        XCTAssertTrue(refusal.hasSuffix("."), refusal)
    }

    func testAnyNameWithACharacterInItIsAccepted() {
        XCTAssertNil(SceneName.refusal("Front porch", keeping: "New scene"))
        XCTAssertNil(SceneName.refusal("x", keeping: "New scene"))
        XCTAssertNil(SceneName.refusal(" a ", keeping: "New scene"))
    }

    /// NO DUPLICATE IS REFUSED, and that is a decision rather than an omission.
    /// Nothing resolves a scene by name — the id is the only cross-object
    /// reference — so refusing a label no code reads would be the app overruling
    /// the operator for tidiness.
    func testTwoScenesMayShareAName() {
        XCTAssertNil(SceneName.refusal("Front porch", keeping: "Front porch"))
    }
}
