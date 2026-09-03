import XCTest
import DuckKit
@testable import StudioKit

/// The router replaced a segmented control, so what it does with an answer —
/// and what it does without a model — is asserted rather than assumed.
final class DraftRoutingTests: XCTestCase {

    private func read(_ json: [String: Any]) throws -> DraftRouting.Routed {
        try DraftRouting.read(fromJSON: json)
    }

    func testADecidedKindCarriesItsReason() throws {
        let r = try read(["kind": "motion", "because": "it moves the duck's own body"])
        XCTAssertEqual(r, .kind(.motion, because: "it moves the duck's own body"))
    }

    func testTheKindIsReadCaseInsensitively() throws {
        XCTAssertEqual(try read(["kind": "Retrieval", "because": "x"]),
                       .kind(.retrieval, because: "x"))
    }

    /// A QUESTION IS A FIRST-CLASS OUTCOME. Guessing wrong costs a round trip
    /// and answers a question nobody asked.
    func testAQuestionComesBackAsAQuestion() throws {
        XCTAssertEqual(try read(["question": "  Do you want it to fetch the ball, or kick it?  "]),
                       .ask("Do you want it to fetch the ball, or kick it?"))
    }

    /// An empty question is not a question — falling through to `kind` is what
    /// keeps a blank string from becoming a dialog with nothing in it.
    func testAnEmptyQuestionIsNotTreatedAsOne() throws {
        XCTAssertEqual(try read(["question": "   ", "kind": "rule", "because": "it has a trigger"]),
                       .kind(.rule, because: "it has a trigger"))
    }

    func testAnAnswerWithNeitherIsRefused() {
        XCTAssertThrowsError(try read(["summary": "I made a bow"])) {
            XCTAssertEqual($0 as? DraftRouting.RoutingError, .unreadable)
        }
    }

    /// `tweak` edits a motion already on screen and is reached from that
    /// screen. A router that returned it would send somebody to a door that
    /// needs a motion this path does not have.
    func testTweakIsNotRoutableFromASentence() {
        XCTAssertThrowsError(try read(["kind": "tweak", "because": "x"])) {
            XCTAssertEqual($0 as? DraftRouting.RoutingError, .unknownKind("tweak"))
        }
        XCTAssertThrowsError(try read(["kind": "poem", "because": "x"])) {
            XCTAssertEqual($0 as? DraftRouting.RoutingError, .unknownKind("poem"))
        }
    }

    // MARK: - the no-model path the picker used to provide

    /// FETCH NEVER NEEDED A MODEL, and removing the tab must not remove that.
    func testAFetchIsRoutedWithNoModelAtAll() throws {
        for sentence in ["fetch the stick 1 m away", "get me the pencil",
                         "drag the broom standing in the corner"] {
            let r = try XCTUnwrap(DraftRouting.withoutAModel(sentence), sentence)
            guard case .kind(let kind, _) = r else { return XCTFail("asked a question: \(sentence)") }
            XCTAssertEqual(kind, .retrieval, sentence)
        }
    }

    /// And it refuses to guess at the other three, because a deterministic
    /// reader guessing is a worse router than none.
    func testAnythingElseGetsNoAnswerWithoutAModel() {
        for sentence in ["take a slow bow", "when something is close, sit down",
                         "teach it to jump", "fetch me a beer"] {
            XCTAssertNil(DraftRouting.withoutAModel(sentence),
                         "\(sentence) was routed without a model that could read it")
        }
    }

    /// The sentence a person gets instead names what they can do about it —
    /// and names ALL THREE routes.
    ///
    /// IT USED TO NAME TWO, and one of them ambiguously: "anything speaking the
    /// OpenAI chat API will do, including one running on this phone" meant the
    /// localhost preset, where another app serves a model. Once a model can be
    /// downloaded into THIS app, that clause reads as the new kind and is wrong
    /// about it — a downloaded model speaks no HTTP at all.
    func testTheNoModelSentenceNamesEveryRouteThereIs() {
        let s = DraftRouting.needsAModel
        XCTAssertTrue(s.contains("Settings"), s)
        XCTAssertTrue(s.contains("Apple's on-device model"), s)
        XCTAssertTrue(s.contains("downloaded onto this phone"), s)
        XCTAssertTrue(s.contains("OpenAI chat API"), s)
        // TWO KINDS, NOT ONE. The Control tab's driving grammar reads a
        // sentence against measurements the same way `Retrieval` reads a
        // fetching one, so "one kind of request" became false the moment
        // `DuckPadMap`/`PadPilot` shipped. Nothing in that track prints this
        // sentence; the Draft tab does.
        XCTAssertTrue(s.contains("two kinds of request"), s)
        XCTAssertTrue(s.contains("fetching something, and driving"), s)
        XCTAssertTrue(s.contains("both are measured rather than written"), s)
        XCTAssertFalse(s.contains("one kind of request"), s)
    }

    /// AND THE APPLE REFUSALS NAME IT TOO. Somebody on a device without Apple
    /// Intelligence is exactly who a downloaded model is for, and it was the
    /// one option those two sentences did not mention.
    func testTheAppleRefusalsOfferTheDownloadedModel() {
        for sentence in [DraftRouting.appleUnavailable, DraftRouting.appleTooOld] {
            XCTAssertTrue(sentence.contains("download a model onto this phone"), sentence)
            XCTAssertTrue(sentence.contains("on your network"), sentence)
            XCTAssertTrue(sentence.contains("Settings"), sentence)
        }
    }

    // MARK: - what the model is told

    /// The catalogue is what the model sorts by, so every kind it may answer
    /// with has to be described in it — with examples, because a router given
    /// only category names sorts by vocabulary and nobody says "motion".
    func testEveryRoutableKindIsDescribedWithExamples() {
        let c = DraftRouting.catalogue
        // `routable` AND NOT `allCases where kind != .tweak`. A sixth kind —
        // `search` — landed, and a loop written as "everything but tweak" would
        // have started demanding a catalogue row for a kind no sentence can be
        // routed to. The list is data so this loop cannot silently widen.
        for kind in ChatDraft.Kind.routable {
            XCTAssertTrue(c.contains(kind.rawValue), "\(kind.rawValue) is missing from the catalogue")
        }
        XCTAssertFalse(c.contains("tweak"), "tweak is not routable from a sentence")
        XCTAssertFalse(c.contains("search"), "search is not routable from a sentence")
        for example in ["take a slow bow", "fetch the stick", "when something is close",
                        "teach it to jump"] {
            XCTAssertTrue(c.contains(example), "the catalogue lost the \(example) example")
        }
    }

    /// The ambiguous case the four tabs could not express at all: a trigger
    /// whose action is a motion nobody has written yet.
    func testTheInstructionsSettleTheRuleVersusMotionAmbiguity() {
        let i = DraftRouting.instructions()
        XCTAssertTrue(i.contains("it is a rule: the motion can be written afterwards"), i)
        XCTAssertTrue(i.contains("Ask only when"), i)
    }

    func testKnownIntentsAreOfferedToTheRouterWhenThereAreAny() {
        XCTAssertFalse(DraftRouting.instructions().contains("Motions that already exist"))
        let i = DraftRouting.instructions(knownIntents: ["back_roll", "step_up"])
        XCTAssertTrue(i.contains("back_roll, step_up"), i)
    }

    /// The door the view actually uses takes text, like every other reader.
    func testItReadsTheModelsRawReply() throws {
        XCTAssertEqual(try DraftRouting.read(fromJSON: #"{"kind":"training","because":"a new ability"}"#),
                       .kind(.training, because: "a new ability"))
        XCTAssertEqual(try DraftRouting.read(fromJSON: #"{"question":"Fetch it or kick it?"}"#),
                       .ask("Fetch it or kick it?"))
        XCTAssertThrowsError(try DraftRouting.read(fromJSON: "not json at all")) {
            XCTAssertEqual($0 as? DraftRouting.RoutingError, .unreadable)
        }
    }
}
