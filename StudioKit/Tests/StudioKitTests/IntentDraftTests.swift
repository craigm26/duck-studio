import XCTest
import DuckKit
@testable import StudioKit

final class IntentDraftTests: XCTestCase {

    /// The constant has to keep up with the corpus, or the editor starts
    /// warning about motions Pollen ship.
    func testThePeakRateIsAtLeastWhatTheCorpusDoes() throws {
        let clips = try DuckIntentClip.bundled()
        var peak = 0.0, worst = ""
        for (name, clip) in clips {
            for i in 1..<clip.frames.count {
                for slot in 0..<min(clip.frames[i].count, clip.frames[i - 1].count) {
                    let rate = abs(clip.frames[i][slot] - clip.frames[i - 1][slot]) * clip.hz
                    if rate > peak { peak = rate; worst = name }
                }
            }
        }
        XCTAssertGreaterThan(peak, 1, "the corpus should move at all")
        XCTAssertGreaterThanOrEqual(IntentDraft.observedPeakJointRate, peak,
            "\(worst) moves at \(peak) rad/s, above the constant — the editor would warn about a shipped motion")
        // And not absurdly above it, or the check never fires.
        XCTAssertLessThan(IntentDraft.observedPeakJointRate, peak * 1.2)
    }

    func testABlankDraftIsPlayableAndGoesNowhere() {
        let draft = IntentDraft.blank()
        XCTAssertTrue(draft.isPlayable)
        XCTAssertEqual(draft.duration, 0.5, accuracy: 1e-12)
        XCTAssertEqual(draft.pose(at: 0.25), DuckModel.homePose)
    }

    /// One pose is a pose, not a motion.
    func testASingleKeyframeIsRefused() {
        let draft = IntentDraft(name: "x", keys: [.init(time: 0, pose: DuckModel.homePose)])
        XCTAssertFalse(draft.isPlayable)
        XCTAssertTrue(draft.problems.contains { $0.text.contains("at least two keyframes") })
    }

    func testAPoseOutsideTravelIsNamedByJoint() {
        var bad = DuckModel.homePose
        bad[3] = DuckModel.jointRanges[3].upper + 0.5
        let draft = IntentDraft(name: "x", keys: [
            .init(time: 0, pose: DuckModel.homePose),
            .init(time: 0.4, pose: bad),
        ])
        XCTAssertFalse(draft.isPlayable)
        XCTAssertTrue(draft.problems.contains { $0.text.contains(DuckModel.jointNames[3]) })
        XCTAssertThrowsError(try draft.move())
    }

    /// The editor's most useful warning: a pose change nobody's servo will make.
    func testAnImpossiblyFastKeyframeIsFlaggedWithoutBlockingPlayback() {
        var far = DuckModel.homePose
        far[3] = DuckModel.jointRanges[3].lower + 0.01
        let draft = IntentDraft(name: "x", keys: [
            .init(time: 0, pose: DuckModel.homePose),
            .init(time: 0.02, pose: far),
        ])
        let impossible = draft.problems.filter { $0.severity == .impossible }
        XCTAssertEqual(impossible.count, 1)
        XCTAssertTrue(impossible[0].text.contains("rad/s"))
        // Still playable: a warning is not a refusal, and somebody adjusting a
        // keyframe needs to see the robot while they do it.
        XCTAssertTrue(draft.isPlayable)
    }

    /// A draft is 15 wide because a person can open the beak and no policy can.
    func testDrivingTheMouthIsCalledOutAsSomethingNoPolicyDoes() {
        var open = DuckModel.homePose
        open[DuckModel.mouthIndex] = DuckModel.mouthOpen
        let draft = IntentDraft(name: "quack", keys: [
            .init(time: 0, pose: DuckModel.homePose),
            .init(time: 0.3, pose: open),
        ])
        let caution = draft.problems.filter { $0.severity == .caution }
        XCTAssertEqual(caution.count, 1)
        XCTAssertTrue(caution[0].text.contains("outside every"))
        XCTAssertTrue(draft.isPlayable)
    }

    func testItRoundTripsThroughItsOwnFile() throws {
        var open = DuckModel.homePose
        open[DuckModel.mouthIndex] = DuckModel.mouthOpen
        let draft = IntentDraft(name: "quack", keys: [
            .init(time: 0, pose: DuckModel.homePose),
            .init(time: 0.3, pose: open),
        ])
        let back = try IntentDraft.decode(try draft.exported())
        XCTAssertEqual(back.keys.count, 2)
        // Fifteen wide on the wire. Narrowing to the policy's fourteen would
        // silently drop the mouth, which is the one thing authoring adds.
        XCTAssertEqual(back.keys[1].pose.count, DuckModel.jointCount)
        // WITHIN AN ULP, NOT BIT-EXACT. The file is decimal text and
        // JSONSerialization emits a shortest round-tripping representation that
        // is occasionally one unit in the last place away from the double it
        // started as — 30° in radians comes back as ...89 rather than ...88.
        // That is 1e-16 rad on a joint whose travel is 0.6 rad, and the
        // validating initializer's 1e-6 tolerance swallows it, so the file is
        // safe to share; what is NOT safe is a downstream equality check that
        // assumes exactness.
        XCTAssertEqual(back.keys[1].pose[DuckModel.mouthIndex], DuckModel.mouthOpen,
                       accuracy: 1e-12)
        for joint in 0..<DuckModel.jointCount {
            XCTAssertEqual(back.pose(at: 0.3)[joint], draft.pose(at: 0.3)[joint],
                           accuracy: 1e-12)
        }
    }

    /// The caveat travels with the file, because the file is what gets shared
    /// and the caveat is what gets lost.
    func testTheExportCarriesTheDisclaimer() throws {
        let data = try IntentDraft.blank().exported()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("no physics ran"))
    }

    func testAnUnknownFormatIsRefusedByName() {
        XCTAssertThrowsError(try IntentDraft.decode(Data(#"{"format":"duck-move/9"}"#.utf8))) {
            XCTAssertEqual($0 as? IntentDraft.ImportError, .unsupportedFormat("duck-move/9"))
        }
    }

    // MARK: - remixing

    /// A remix keeps the shapes and loses the physics, and the provenance line
    /// has to say the second part — a remix of a clip that works is not a
    /// motion that works.
    func testARemixSaysWhatItThrewAway() throws {
        let clip = try XCTUnwrap(try DuckIntentClip.bundled()["kick_left"])
        let draft = IntentDraft.remix(clip)
        XCTAssertEqual(draft.keys.count, 8)
        XCTAssertEqual(draft.duration, clip.duration, accuracy: 1e-9)
        XCTAssertTrue(draft.provenance.contains("Sampled"))
        XCTAssertTrue(draft.provenance.contains("physics that produced them is not"))
        XCTAssertTrue(draft.isPlayable, "a remix of a valid clip must at least play")
    }

    /// And it really is a different curve — eight smoothstepped keyframes are
    /// not a recording at fifty hertz, so the app must not present one as the
    /// other.
    func testARemixIsNotTheRecordingItCameFrom() throws {
        let clip = try XCTUnwrap(try DuckIntentClip.bundled()["kick_left"])
        let draft = IntentDraft.remix(clip)
        var worst = 0.0
        for tick in 0..<clip.frames.count {
            let time = Double(tick) / clip.hz
            let recorded = clip.pose(at: time).jointAngles
            let remixed = draft.pose(at: time)
            for joint in 0..<DuckModel.jointCount {
                worst = max(worst, abs(recorded[joint] - remixed[joint]))
            }
        }
        XCTAssertGreaterThan(worst, 0.05,
            "if the remix matched the recording to within a hair there would be nothing to warn about")
    }
}

final class JointGroupTests: XCTestCase {

    /// A hand-written group list is a list somebody adds a joint to and
    /// forgets. This is the assertion that notices.
    func testEveryJointIsInExactlyOneGroup() {
        XCTAssertTrue(JointGroup.coversEveryJoint)
        let listed = JointGroup.all.flatMap(\.joints)
        XCTAssertEqual(Set(listed).count, listed.count, "a joint appears twice")
        XCTAssertEqual(listed.count, DuckModel.jointCount)
    }

    /// The mouth note makes three factual claims about the policies. All three
    /// have to come from the model rather than from memory.
    func testTheMouthNoteMatchesTheActualPolicyShape() throws {
        let mouth = try XCTUnwrap(JointGroup.all.first { $0.title == "Mouth" })
        let note = try XCTUnwrap(mouth.note)
        XCTAssertEqual(mouth.joints, [DuckModel.mouthIndex])
        XCTAssertTrue(note.contains("\(DuckObservation.length) inputs"))
        XCTAssertTrue(note.contains("\(DuckModel.policyJointCount)"))
        XCTAssertEqual(DuckObservation.length, 61)
        XCTAssertEqual(DuckModel.policyJointCount, 14)
        XCTAssertEqual(DuckModel.mouthIndex, 9)
    }

    /// A control's ends ARE the joint's travel, so nothing behind it can ask
    /// for an angle the joint does not have.
    func testAControlsEndsAreTheJointsTravel() {
        for index in 0..<DuckModel.jointCount {
            let control = JointControl(index: index)
            XCTAssertEqual(control.lower, DuckModel.jointRanges[index].lower)
            XCTAssertEqual(control.upper, DuckModel.jointRanges[index].upper)
            XCTAssertEqual(control.name, DuckModel.jointNames[index])
            XCTAssertGreaterThanOrEqual(control.home, control.lower)
            XCTAssertLessThanOrEqual(control.home, control.upper)
        }
    }

    func testTheMouthControlSpansClosedToOpen() {
        let mouth = JointControl(index: DuckModel.mouthIndex)
        XCTAssertEqual(mouth.lower, DuckModel.mouthClosed)
        XCTAssertEqual(mouth.upper, DuckModel.mouthOpen)
        XCTAssertEqual(mouth.travelLabel.upper, "30°")
    }
}
