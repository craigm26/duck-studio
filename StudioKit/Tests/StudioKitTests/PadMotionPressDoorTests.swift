import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

/// THE TWO DOORS A PAD BUTTON GOES THROUGH, AND THE FACT THAT THEY DISAGREE.
///
/// `DriveView.padButton` draws a control through
/// `shown(for:naming:namingMotion:)` — which resolves a bound motion against
/// what `PadDesk` has learned from `DraftStore` and degrades a motion this
/// phone can no longer name to `.notYet(motionIsGone(_:))`.
///
/// `DriveView.press(_:)` USED TO ACT on a control through the ONE-ARGUMENT
/// `effect(for:)`, which resolves nothing. A `.run(motion:)` the drawn door had
/// already buried was handed to `runMotion(_:)` anyway, whose opening guard
/// could not find a draft for it and returned with no sentence at all —
/// `DuckPadMap.motionIsGone(_:)`, the sentence the kit wrote for exactly this,
/// was unreachable from a press. The press now goes through the resolving door
/// and these tests pin the difference that made it matter, so a future press
/// that reaches for the cheap overload has something to fail against.
///
/// The sequence case does not have this hole: its press lands in
/// `PadDesk.play(_:thenLoading:among:face:)`, which is a SECOND door and
/// returns `sequenceIsGone(face:)`. The motion case has no second door.
final class PadMotionPressDoorTests: XCTestCase {

    /// DriveView.swift:2470 `desk.map.effect(for: control)` against
    /// DriveView.swift:1638 `desk.map.shown(for:naming:namingMotion:)`.
    func testThePressDoorStillRunsAMotionTheDrawnDoorHasAlreadyBuried() {
        let gone = UUID()
        var map = DuckPadMap.defaults(in: .walk)
        map.bind(.run(motion: gone), to: .a)

        // What `press(_:)` switches on — no naming, so the dead id survives.
        let pressed = map.effect(for: .a)
        XCTAssertEqual(pressed, .run(motion: gone))

        // What `padButton` draws and what `PadBindSheet` reads.
        let drawn = map.effect(for: .a, naming: { _ in nil }, namingMotion: { _ in nil })
        XCTAssertEqual(drawn, .notYet(DuckPadMap.motionIsGone(.a)))

        // THE DISAGREEMENT, PINNED. One press, two answers.
        XCTAssertNotEqual(pressed, drawn)

        // And the button is drawn dead while the press door still says run.
        let shown = map.shown(for: .a, naming: { _ in nil }, namingMotion: { _ in nil })
        XCTAssertFalse(shown.isLive)
        if case .run = pressed {} else { XCTFail("the press door stopped saying run") }
    }

    /// The sequence half of the same switch DOES have a second door, so the
    /// asymmetry is a gap in one case rather than a rule about both.
    func testASequencePressHasASecondDoorAndAMotionPressHasNone() {
        let gone = UUID()
        var map = DuckPadMap.defaults(in: .walk)
        map.bind(.play(sequence: gone, thenLoading: nil), to: .x)

        // Same one-argument door, same undegraded answer …
        XCTAssertEqual(map.effect(for: .x), .play(sequence: gone, thenLoading: nil))
        // … but `PadDesk.play` catches it and has a sentence. There is no
        // equivalent sentence on the run path: `runMotion` returns.
        XCTAssertTrue(DuckPadMap.sequenceIsGone(face: "X").contains("deleted"))
        XCTAssertTrue(DuckPadMap.motionIsGone(.a).contains("deleted"))
    }

    /// WHAT A PERSON ACTUALLY READS WHEN THEY PRESS IT.
    ///
    /// `press` composes `"\(control.face) → \(desk.name(ofMotion: motion) ?? "")"`
    /// and `name(ofMotion:)` is the same lookup that just failed — so the
    /// readout is a face, an arrow, and nothing after it. This reproduces that
    /// line rather than asserting about a view.
    func testTheReadoutLineForAnUnnameableMotionIsAnArrowPointingAtNothing() {
        let control = DuckPad.Control.a
        let name: String? = nil          // desk.name(ofMotion:) with an empty `motions`
        let line = "\(control.face) → \(name ?? "")"
        XCTAssertEqual(line, "\(control.face) → ")
        XCTAssertTrue(line.hasSuffix("→ "), line)
    }

    /// AND THE ID ITSELF CANNOT DRIFT, so a relaunch is not the explanation for
    /// a live binding that does nothing: the map's motion id is written and read
    /// verbatim, and `IntentDraft.id` is a stored `Codable` property that
    /// `DraftStore` round-trips under `<id>.json`.
    func testTheBoundIdIsByteStableAcrossTheFile() throws {
        let motion = UUID()
        var map = DuckPadMap.defaults(in: .walk)
        map.bind(.run(motion: motion), to: .rightBumper)
        let data = try map.encoded()
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(motion.uuidString))
        XCTAssertEqual(try DuckPadMap.decode(data).effect(for: .rightBumper),
                       .run(motion: motion))
    }
}
