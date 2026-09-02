import XCTest
@testable import StudioKit

/// The independence claim, which is the one sentence in this kit that is about
/// somebody else.
///
/// WHAT THESE TESTS ARE GUARDING, AND WHY IT IS NOT SPELLING. The defect that
/// produced `Provenance` was not a typo: it was a claim that existed only in a
/// comment, in `Theme.swift`, asserting that the app "says it is independent on
/// its own store listing, its website and its Policies tab" when a grep of the
/// whole repository for `not affiliated`, `unofficial` or `independent` found
/// that comment and nothing else. A claim nothing renders is a claim nobody
/// reads, and it took a person opening a source file to notice.
///
/// So these assertions are about the PROPERTIES a disclaimer has to keep, not
/// about the exact paragraph. Rewording it is allowed and expected; dropping
/// one of the three relationships being denied, hedging one of them, or letting
/// the short form quietly become a different claim from the long one is not.
///
/// The wording deliberately matches the shape `duckkit`'s README already uses
/// ("DuckKit is not affiliated with Pollen Robotics"), because the two ship
/// together and a reader who meets both should not have to work out whether
/// they mean the same thing.
final class ProvenanceTests: XCTestCase {

    // MARK: - the long form

    func testTheLongFormIsTheSentenceThatShipped() {
        XCTAssertEqual(Provenance.independence,
                       "Microduck Studio is an independent project. It is not made by, endorsed "
                     + "by, or affiliated with Pollen Robotics. Microduck is their robot; this is "
                     + "an independent owner's app for it.")
    }

    /// THREE RELATIONSHIPS, DENIED BY NAME. "Not affiliated" alone leaves a
    /// reader free to assume Pollen at least blessed this, and "not made by"
    /// alone leaves them free to assume it is a licensed thing. Each of the
    /// three is an assumption somebody would otherwise be entitled to make from
    /// an app that wears the robot's palette and speaks its protocol.
    func testTheLongFormDeniesAllThreeRelationships() {
        for relationship in ["made by", "endorsed by", "affiliated with"] {
            XCTAssertTrue(Provenance.independence.contains(relationship),
                          "the disclaimer stopped denying \"\(relationship)\"")
        }
    }

    /// IT NAMES THEM, WHICH IS HALF THE POINT. A disclaimer that said only
    /// "this is an independent project" would be true and useless: the reader
    /// has to know WHICH company is not answerable for this app, and the same
    /// sentence is the only place this kit credits them for the robot.
    func testTheLongFormNamesPollenAndCreditsThemForTheRobot() {
        XCTAssertTrue(Provenance.independence.contains("Pollen Robotics"))
        XCTAssertTrue(Provenance.independence.contains("Microduck is their robot"))
    }

    /// NO HEDGE. "Not officially affiliated" invites the reader to wonder about
    /// the unofficial kind, and "not currently" invites them to wait. The claim
    /// is unqualified or it is not a claim.
    func testTheLongFormDoesNotHedge() {
        for hedge in ["officially", "currently", "not yet", "at this time", "as far as"] {
            XCTAssertFalse(Provenance.independence.lowercased().contains(hedge),
                           "the disclaimer picked up the hedge \"\(hedge)\"")
        }
    }

    // MARK: - the short form

    func testTheShortFormIsTheSentenceThatShipped() {
        XCTAssertEqual(Provenance.independenceShort,
                       "An independent project. Not made by, endorsed by, or affiliated with "
                     + "Pollen Robotics.")
    }

    /// THE SHORT FORM IS SHORTER, NOT WEAKER. It drops the sentence that
    /// credits Pollen for the robot — a footer sits under a screen already full
    /// of that name — and it keeps every one of the three denials and the
    /// company's name.
    func testTheShortFormKeepsTheWholeClaim() {
        for relationship in ["made by", "endorsed by", "affiliated with"] {
            XCTAssertTrue(Provenance.independenceShort.contains(relationship),
                          "the footer stopped denying \"\(relationship)\"")
        }
        XCTAssertTrue(Provenance.independenceShort.contains("Pollen Robotics"))
    }

    /// A FOOTER HAS A LINE OR TWO. This is not a style preference: the long
    /// form is three sentences and would wrap to four lines under a list, which
    /// is how a disclaimer becomes something a designer asks to remove.
    func testTheShortFormFitsUnderAScreen() {
        XCTAssertLessThan(Provenance.independenceShort.count, 100)
        XCTAssertLessThan(Provenance.independenceShort.count, Provenance.independence.count)
    }

    /// THE WORD "UNOFFICIAL" IS NOT A SUBSTITUTE AND MUST NOT CREEP IN. It
    /// reads to a lot of people as "not official YET", which is the one
    /// impression this sentence exists to prevent.
    func testNeitherFormLeansOnTheWordUnofficial() {
        XCTAssertFalse(Provenance.independence.lowercased().contains("unofficial"))
        XCTAssertFalse(Provenance.independenceShort.lowercased().contains("unofficial"))
    }

    // MARK: - both of them

    /// BOTH ARE WHOLE SENTENCES. These get pasted into a store listing, an
    /// issue comment and a footer, and a fragment that ends without a full stop
    /// reads as truncated text — which is exactly what a reader distrusts most
    /// in a disclaimer.
    func testBothFormsAreFinishedSentences() {
        for claim in [Provenance.independence, Provenance.independenceShort] {
            XCTAssertTrue(claim.hasSuffix("."), "\"\(claim)\" does not end")
            XCTAssertFalse(claim.hasPrefix(" "))
            XCTAssertFalse(claim.hasSuffix(" ."))
        }
    }

    /// THE APP'S NAME IS THE ONE ON THE STORE. It was Duck Studio and is
    /// Microduck Studio, and a disclaimer naming a product nobody can find is
    /// worth nothing to the person trying to work out who to complain to.
    func testTheLongFormNamesThisApp() {
        XCTAssertTrue(Provenance.independence.hasPrefix("Microduck Studio is"))
    }
}
