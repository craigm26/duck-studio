import XCTest
@testable import StudioKit

/// Sentences added for the Settings screen, and the two that were already
/// false before it existed.
final class UXSurfaceTests: XCTestCase {

    /// THIS TEST PROTECTS HONESTY, NOT THE WORD "LAB". The modes preamble opens
    /// with the bare fact byte-identically, the bare fact names no container,
    /// and the sentence after it still says out loud that no robot is on the
    /// other end. Those are the three things a person is owed; which tab the
    /// rows happen to be drawn under this month is not one of them, and the
    /// last assertion used to pin a tab name that no longer exists.
    ///
    /// If the first two drift apart, a screen quoting `noRobotYet` and a screen
    /// quoting `modesPreamble` start disagreeing about the date.
    func testThePreambleStillOpensWithTheBareFact() {
        XCTAssertTrue(LabCatalogue.modesPreamble.hasPrefix(LabCatalogue.noRobotYet),
                      LabCatalogue.modesPreamble)
        for container in ["Lab", "tab", "Studio", "Modes"] {
            XCTAssertFalse(LabCatalogue.noRobotYet.contains(container),
                           "the reusable fact must not claim anything about a container: \(container)")
        }
        XCTAssertTrue(LabCatalogue.modesPreamble.contains("Nothing in these modes is talking to a robot"),
                      LabCatalogue.modesPreamble)
    }

    /// THE OLD CATALOGUE SENTENCE WAS FALSE WHEN IT WAS WRITTEN. "This app
    /// holds no account and there is nowhere to paste a token" — PublishMotionView
    /// has always had a token field. The replacement narrows the claim to the
    /// screens it is drawn on, which is what was true all along.
    func testTheCatalogueClaimsOnlyThatItSendsNoToken() {
        let s = PolicyCatalogue.tokenNote
        XCTAssertTrue(s.contains("Nothing on this screen sends a token"), s)
        XCTAssertTrue(s.contains("401"), s)
        XCTAssertFalse(s.contains("nowhere to paste"),
                       "the app does have somewhere to paste one: \(s)")
        XCTAssertFalse(s.contains("holds no account"), s)
    }

    /// Removing a Keychain item is not revocation, and the sentence says which
    /// one it is doing.
    func testRemovingATokenDoesNotClaimToRevokeIt() {
        let s = HuggingFacePublish.tokenRemovedNote
        XCTAssertTrue(s.contains("does not revoke it"), s)
        XCTAssertTrue(s.contains("huggingface.co/settings/tokens"),
                      "and it says where revocation actually happens: \(s)")
    }

    /// A saved token is not a verified identity. Nothing persists the account
    /// name, so a screen must not imply it knows whose token this is.
    func testTheHeldNoteNamesNoAccount() {
        let s = HuggingFacePublish.tokenHeldNote
        XCTAssertFalse(s.contains("account"), s)
        XCTAssertTrue(s.contains("one kind of request only"), s)
        XCTAssertTrue(HuggingFacePublish.tokenAbsentNote.contains("nothing else in this app uses it"),
                      HuggingFacePublish.tokenAbsentNote)
    }
}
