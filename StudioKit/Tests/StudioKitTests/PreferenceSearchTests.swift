import XCTest
import DuckKit
@testable import StudioKit

/// Preference search is the one part of RLHF that fits on a phone, so what it
/// claims about itself is asserted here rather than believed.
final class PreferenceSearchTests: XCTestCase {

    private func draft() -> IntentDraft {
        var d = IntentDraft.blank(named: "bow")
        var deep = DuckModel.homePose
        deep[0] += 0.4                       // a leg
        deep[5] += 0.3                       // the neck
        deep[DuckModel.mouthIndex] += 0.2    // the mouth
        d.keys = [
            IntentDraft.Key(time: 0.0, pose: DuckModel.homePose),
            IntentDraft.Key(time: 0.5, pose: deep),
            IntentDraft.Key(time: 1.0, pose: DuckModel.homePose),
        ]
        return d
    }

    // MARK: - the pair

    /// A PAIR THAT DIFFERS ON ONE KNOB IS THE WHOLE METHOD. Differing on
    /// several would answer "which of these two motions do you prefer", which
    /// is an answer the search cannot spend: it does not say which change did
    /// the work.
    func testTheTwoCandidatesDifferOnExactlyOneKnob() {
        let search = PreferenceSearch()
        let (a, b) = search.nextPair()
        let differing = PreferenceSearch.Knob.allCases.filter { abs(a[$0] - b[$0]) > 1e-9 }
        XCTAssertEqual(differing, [search.knob])
    }

    func testEveryKnobGetsATurnBeforeAnyRepeats() {
        var search = PreferenceSearch()
        var seen: [PreferenceSearch.Knob] = []
        for _ in PreferenceSearch.Knob.allCases {
            seen.append(search.knob)
            let (a, b) = search.nextPair()
            search.record(.left, left: a, right: b)
        }
        XCTAssertEqual(Set(seen).count, PreferenceSearch.Knob.allCases.count)
    }

    /// A knob cannot wander out of the neighbourhood of the motion somebody
    /// wrote. Past its span it is a different motion, not a variant.
    func testAKnobCannotLeaveItsSpanHoweverManyTimesItIsPushed() {
        var search = PreferenceSearch()
        for _ in 0..<200 {
            let (a, b) = search.nextPair()
            search.record(.right, left: a, right: b)   // always push the same way
        }
        for knob in PreferenceSearch.Knob.allCases {
            XCTAssertLessThanOrEqual(search.best[knob], 1 + knob.span + 1e-9, knob.rawValue)
            XCTAssertGreaterThanOrEqual(search.best[knob], 1 - knob.span - 1e-9, knob.rawValue)
        }
    }

    // MARK: - "cannot tell" is an answer

    /// FORCING A CHOICE MANUFACTURES SIGNAL. Two motions somebody cannot tell
    /// apart carry no information about direction, and recording a coin flip as
    /// a preference is how a search convinces itself of something nobody said.
    func testCannotTellMovesNothingAndIsStillKept() {
        var search = PreferenceSearch()
        let (a, b) = search.nextPair()
        let before = search.best
        search.record(.cannotTell, left: a, right: b)
        XCTAssertEqual(search.best, before, "an undecidable pair must not move the answer")
        XCTAssertEqual(search.history.count, 1, "and it is still recorded")
        XCTAssertEqual(search.decided, 0, "but it does not count as a decision")
        XCTAssertTrue(search.standing.contains("too close to call"), search.standing)
        XCTAssertFalse(search.standing.contains("Nothing has been chosen yet"),
                       "one undecidable answer is still an answer somebody gave")
    }

    // MARK: - what it is entitled to say about itself

    func testItClaimsNothingBeforeAnybodyHasChosen() {
        let s = PreferenceSearch().standing
        XCTAssertTrue(s.contains("Nothing has been chosen yet"), s)
        XCTAssertEqual(PreferenceSearch().resolution, 0)
    }

    /// A FEW ANSWERS DO NOT SETTLE A KNOB, and the sentence says so rather than
    /// implying the motion has been tuned.
    func testAHandfulOfAnswersIsCalledSteeringAndNotTuning() {
        var search = PreferenceSearch()
        for _ in 0..<4 {
            let (a, b) = search.nextPair()
            search.record(.left, left: a, right: b)
        }
        XCTAssertEqual(search.resolution, 0)
        XCTAssertTrue(search.standing.contains("steering rather than one that has been tuned"),
                      search.standing)
    }

    /// And when it has earned a number, it still refuses the two claims it can
    /// never support: that this is anybody else's preference, or a measurement.
    func testEvenWithManyAnswersItSaysThisIsOnePersonAndNotAMeasurement() {
        var search = PreferenceSearch()
        for _ in 0..<40 {
            let (a, b) = search.nextPair()
            search.record(.left, left: a, right: b)
        }
        XCTAssertGreaterThan(search.resolution, 0)
        let s = search.standing
        XCTAssertTrue(s.contains("your preference on this phone, not a measurement"), s)
        XCTAssertTrue(s.contains("nothing here has been run in physics"), s)
    }

    /// Resolution never exceeds the number of knobs actually varied, however
    /// many answers pile up on one of them.
    func testResolutionNeverOutrunsTheKnobsActuallyVaried() {
        var search = PreferenceSearch()
        let (a, b) = search.nextPair()
        for _ in 0..<50 { search.record(.left, left: a, right: b) }
        XCTAssertLessThanOrEqual(search.resolution, 1)
    }

    // MARK: - applying it to a real motion

    func testUnchangedSettingsLeaveTheMotionAlone() {
        let d = draft()
        let out = PreferenceSearch.apply(.unchanged, to: d)
        XCTAssertEqual(out.keys.map(\.time), d.keys.map(\.time))
        for (a, b) in zip(out.keys, d.keys) {
            for (x, y) in zip(a.pose, b.pose) { XCTAssertEqual(x, y, accuracy: 1e-12) }
        }
    }

    /// Depth scales around the standing pose, because that is the pose a motion
    /// is written against — not around zero, which is not a pose at all.
    ///
    /// THE EXPECTATION IS CLAMPED, and finding that out is what caught the bug:
    /// `left_hip_yaw`'s travel stops this scaling short of the arithmetic, and
    /// the first version of this test asserted the arithmetic. Scaling and the
    /// stop are both real; the stop wins.
    func testLegDepthScalesTheDistanceFromStandingAndLeavesTheHeadAlone() {
        var s = PreferenceSearch.Settings()
        s[.legDepth] = 1.4
        let out = PreferenceSearch.apply(s, to: draft())
        let home = DuckModel.homePose
        let deep = out.keys[1].pose

        let wanted = home[0] + 0.4 * 1.4
        let travel = DuckModel.jointRanges[0]
        XCTAssertEqual(deep[0], min(max(wanted, travel.lower), travel.upper), accuracy: 1e-9)
        XCTAssertGreaterThan(deep[0] - home[0], 0.4, "it still moved further than it was written")

        XCTAssertEqual(deep[5] - home[5], 0.3, accuracy: 1e-9, "the head knob did not move")
    }

    func testTheMouthHasItsOwnKnobBecauseNoPolicyDrivesIt() {
        var s = PreferenceSearch.Settings()
        s[.mouthTravel] = 0.6
        let out = PreferenceSearch.apply(s, to: draft())
        let m = DuckModel.mouthIndex
        XCTAssertEqual(out.keys[1].pose[m] - DuckModel.homePose[m], 0.2 * 0.6, accuracy: 1e-9)
    }

    func testTempoStretchesEveryKeyframeAndKeepsTheirOrder() {
        var s = PreferenceSearch.Settings()
        s[.tempo] = 1.3
        let out = PreferenceSearch.apply(s, to: draft())
        let times = out.keys.map(\.time)
        XCTAssertEqual(times, times.sorted())
        XCTAssertEqual(times.last! - times.first!, 1.0 * 1.3, accuracy: 1e-9)
    }

    func testNoKnobCanPushAKeyframeBeforeZero() {
        var s = PreferenceSearch.Settings()
        s[.lead] = 1 - PreferenceSearch.Knob.lead.span
        s[.tempo] = 1 - PreferenceSearch.Knob.tempo.span
        let out = PreferenceSearch.apply(s, to: draft())
        for key in out.keys { XCTAssertGreaterThanOrEqual(key.time, 0, "\(key.time)") }
    }

    /// Every knob says what it does to the file, because somebody choosing
    /// between two ducks deserves to know what changed.
    func testEveryKnobSaysWhatItActuallyChanges() {
        for knob in PreferenceSearch.Knob.allCases {
            XCTAssertFalse(knob.title.isEmpty)
            XCTAssertGreaterThan(knob.effect.count, 25, knob.rawValue)
            XCTAssertGreaterThan(knob.span, 0)
        }
    }

    /// The result stays a motion the rest of the app will accept — a knob
    /// cannot make something `IntentDraft` would refuse.
    func testAnyPointInKnobSpaceIsStillAMotionTheAppAccepts() {
        for knob in PreferenceSearch.Knob.allCases {
            for value in [1 - knob.span, 1 + knob.span] {
                var s = PreferenceSearch.Settings()
                s[knob] = value
                let out = PreferenceSearch.apply(s, to: draft())
                XCTAssertNoThrow(try out.exported(),
                                 "\(knob.rawValue) at \(value) produced a motion the app refuses")
            }
        }
    }

    /// THE CLAMP IS REAL, NOT INHERITED. `IntentDraft` refuses an out-of-travel
    /// pose rather than clamping it, so a knob that could push past a stop
    /// would produce a motion with a slider and no export.
    func testAKnobStopsAtTheJointStopRatherThanPushingPastIt() {
        var s = PreferenceSearch.Settings()
        s[.legDepth] = 1 + PreferenceSearch.Knob.legDepth.span
        let out = PreferenceSearch.apply(s, to: draft())
        for key in out.keys {
            for (j, angle) in key.pose.enumerated() {
                let travel = DuckModel.jointRanges[j]
                XCTAssertGreaterThanOrEqual(angle, travel.lower - 1e-9)
                XCTAssertLessThanOrEqual(angle, travel.upper + 1e-9)
            }
        }
    }
}
