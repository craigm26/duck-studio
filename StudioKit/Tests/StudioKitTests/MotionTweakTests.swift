import XCTest
import DuckKit
@testable import StudioKit

final class MotionTweakTests: XCTestCase {

    private func bow() -> IntentDraft {
        var draft = IntentDraft.blank()
        draft.name = "Bow"
        let home = DuckModel.homePose
        var down = home
        let neck = DuckModel.jointIndex(of: "neck_pitch")!
        down[neck] = home[neck] + 20 * .pi / 180
        draft.keys = [.init(time: 0, pose: home),
                      .init(time: 0.8, pose: down),
                      .init(time: 1.6, pose: home)]
        return draft
    }

    private func degrees(_ draft: IntentDraft, _ joint: String, at index: Int) -> Double {
        let slot = DuckModel.jointIndex(of: joint)!
        let ordered = draft.keys.sorted { $0.time < $1.time }
        return (ordered[index].pose[slot] - DuckModel.homePose[slot]) * 180 / .pi
    }

    /// THE PROPERTY THAT MAKES A SECOND SENTENCE SAFE: everything not mentioned
    /// is left alone. A model asked to reproduce a whole motion quietly changes
    /// joints nobody asked about.
    func testAnEditTouchesOnlyWhatItNames() throws {
        let tweak = MotionTweak(summary: "deeper",
                                edits: [.joint(at: 0.8, word: "neck", degrees: 40)])
        let (edited, notes) = try tweak.applied(to: bow())
        XCTAssertEqual(degrees(edited, "neck_pitch", at: 1), 40, accuracy: 0.5)
        XCTAssertEqual(degrees(edited, "neck_pitch", at: 0), 0, accuracy: 0.5)
        XCTAssertEqual(degrees(edited, "neck_pitch", at: 2), 0, accuracy: 0.5)
        XCTAssertEqual(edited.keys.count, 3)
        XCTAssertEqual(notes.count, 1)
    }

    /// A named moment does not have to be exact. "The bow at 1.5" with frames
    /// at 1.48 and 2.0 means the first, and demanding an exact match would
    /// refuse a correct answer over rounding.
    func testANearbyMomentFindsTheKeyframe() throws {
        let tweak = MotionTweak(summary: "x", edits: [.joint(at: 0.9, word: "neck", degrees: 10)])
        let (edited, _) = try tweak.applied(to: bow())
        XCTAssertEqual(degrees(edited, "neck_pitch", at: 1), 10, accuracy: 0.5)
    }

    func testAMomentWithNoKeyframeIsRefusedRatherThanGuessed() {
        let tweak = MotionTweak(summary: "x", edits: [.joint(at: 5.0, word: "neck", degrees: 10)])
        XCTAssertThrowsError(try tweak.applied(to: bow())) {
            XCTAssertEqual($0 as? MotionTweak.Failure, .noKeyframeNear(5.0))
        }
    }

    /// Pair words mirror, exactly as they do when drafting — so one vocabulary
    /// means one thing whether a sentence writes a motion or edits one.
    func testPairWordsMirror() throws {
        let tweak = MotionTweak(summary: "x",
                                edits: [.joint(at: 0.8, word: "both hips", degrees: 15)])
        let (edited, _) = try tweak.applied(to: bow())
        XCTAssertEqual(degrees(edited, "left_hip_pitch", at: 1), 15, accuracy: 0.5)
        XCTAssertEqual(degrees(edited, "right_hip_pitch", at: 1), -15, accuracy: 0.5)
    }

    /// A sentence is not a licence to ask for an angle the robot does not have.
    func testAnImpossibleAngleIsClampedToTheTravel() throws {
        let tweak = MotionTweak(summary: "x",
                                edits: [.joint(at: 0.8, word: "neck", degrees: 500)])
        let (edited, _) = try tweak.applied(to: bow())
        let slot = DuckModel.jointIndex(of: "neck_pitch")!
        let ordered = edited.keys.sorted { $0.time < $1.time }
        XCTAssertLessThanOrEqual(ordered[1].pose[slot], DuckModel.jointRanges[slot].upper)
    }

    func testAnUnknownJointIsNamedBack() {
        let tweak = MotionTweak(summary: "x", edits: [.joint(at: 0.8, word: "tail", degrees: 10)])
        XCTAssertThrowsError(try tweak.applied(to: bow())) {
            XCTAssertEqual($0 as? MotionTweak.Failure, .unknownJoint("tail"))
        }
    }

    /// Adding a keyframe captures the pose the motion was ALREADY passing
    /// through, so every pose that was pinned stays pinned.
    ///
    /// BUT IT DOES CHANGE THE MOTION, and the first version of this test
    /// asserted otherwise and failed — correctly. Each span between keyframes
    /// is smoothstepped separately, easing in and out at both ends, so cutting
    /// one span into two makes the duck slow down in the middle where it used
    /// to sail through. Two degrees at the half-second, on this bow. The app
    /// said "changes nothing until you move something" in two places and that
    /// was simply wrong.
    func testAddingAKeyframePinsThePosesAndStillReshapesTheCurve() throws {
        let before = bow()
        let (edited, _) = try MotionTweak(summary: "x", edits: [.addKey(at: 0.4)])
            .applied(to: before)
        XCTAssertEqual(edited.keys.count, 4)

        // Every moment that was already a keyframe is untouched, and so is the
        // moment the new one was taken from.
        for t in [0.0, 0.4, 0.8, 1.6] {
            assertPose(edited.pose(at: t), before.pose(at: t), at: t)
        }

        // Between them, the re-easing shows.
        let slot = DuckModel.jointIndex(of: "neck_pitch")!
        let drift = abs(edited.pose(at: 0.5)[slot] - before.pose(at: 0.5)[slot]) * 180 / .pi
        XCTAssertGreaterThan(drift, 1.0, "smoothstep re-eases each span; it is not a no-op")
        XCTAssertLessThan(drift, 5.0, "and it is a reshaping, not a different motion")
    }

    func testMovingAndRemovingKeyframes() throws {
        let (moved, _) = try MotionTweak(summary: "x", edits: [.moveKey(at: 0.8, to: 1.2)])
            .applied(to: bow())
        XCTAssertEqual(moved.keys.sorted { $0.time < $1.time }[1].time, 1.2, accuracy: 1e-9)
        let (fewer, _) = try MotionTweak(summary: "x", edits: [.removeKey(at: 0.8)])
            .applied(to: bow())
        XCTAssertEqual(fewer.keys.count, 2)
    }

    func testTheLastKeyframeCannotBeRemoved() {
        var single = IntentDraft.blank()
        single.keys = [.init(time: 0, pose: DuckModel.homePose)]
        XCTAssertThrowsError(try MotionTweak(summary: "x", edits: [.removeKey(at: 0)])
            .applied(to: single)) {
            XCTAssertEqual($0 as? MotionTweak.Failure, .wouldEmptyTheMotion)
        }
    }

    func testNoEditsIsSaidPlainly() {
        XCTAssertThrowsError(try MotionTweak(summary: "", edits: []).applied(to: bow())) {
            XCTAssertEqual($0 as? MotionTweak.Failure, .noEdits)
        }
    }

    // MARK: - what the model is told, and what it sends back

    /// Without the motion described, a model is guessing at what moments exist.
    func testTheMotionIsDescribedToTheModel() {
        let text = MotionTweak.describe(bow())
        XCTAssertTrue(text.contains("\"Bow\""))
        XCTAssertTrue(text.contains("3 keyframes"))
        XCTAssertTrue(text.contains("0.80 s"))
        XCTAssertTrue(text.contains("neck +20°"))
        XCTAssertTrue(text.contains("standing"), "a keyframe at home should say so")
    }

    func testEveryEditShapeIsRead() throws {
        let json = """
        {"summary":"deeper and longer","edits":[
          {"at":0.8,"joint":"neck","degrees":35},
          {"at":1.2,"action":"add"},
          {"at":1.6,"to":2.0},
          {"at":0.0,"action":"remove"},
          {"name":"A deeper bow"}]}
        """
        let tweak = try ChatDraft.tweak(fromJSON: json)
        XCTAssertEqual(tweak.summary, "deeper and longer")
        XCTAssertEqual(tweak.edits.count, 5)
        XCTAssertEqual(tweak.edits[0], .joint(at: 0.8, word: "neck", degrees: 35))
        XCTAssertEqual(tweak.edits[1], .addKey(at: 1.2))
        XCTAssertEqual(tweak.edits[2], .moveKey(at: 1.6, to: 2.0))
        XCTAssertEqual(tweak.edits[3], .removeKey(at: 0.0))
        XCTAssertEqual(tweak.edits[4], .rename("A deeper bow"))
    }

    /// A half-understood edit applied to somebody's motion is worse than one
    /// that did not happen, so anything unrecognised is dropped.
    func testNonsenseEditsAreDroppedNotGuessed() throws {
        let json = #"{"summary":"x","edits":[{"wobble":true},{"at":0.8,"joint":"neck","degrees":5}]}"#
        XCTAssertEqual(try ChatDraft.tweak(fromJSON: json).edits.count, 1)
    }
}

private extension XCTestCase {
    /// Named rather than overloading XCTAssertEqual: an overload on XCTestCase
    /// shadows the global and every accuracy assertion in the file resolves to
    /// the wrong one.
    func assertPose(_ a: [Double], _ b: [Double], at time: Double,
                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, "pose length at \(time)", file: file, line: line)
        for (x, y) in zip(a, b) {
            XCTAssertEqual(x, y, accuracy: 1e-6, "at \(time)", file: file, line: line)
        }
    }
}
