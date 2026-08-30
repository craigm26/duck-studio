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

    /// A single pose IS a legitimate thing to want, and the two gates have to
    /// say so together: what the Checks tab accepts, the share sheet exports.
    func testASinglePoseHeldIsAMotionABeginnerCanExport() throws {
        var open = DuckModel.homePose
        open[DuckModel.mouthIndex] = DuckModel.mouthOpen
        let draft = IntentDraft(name: "beak open", keys: [.init(time: 0.5, pose: open)])
        XCTAssertTrue(draft.isPlayable, "\(draft.problems.map(\.text))")
        XCTAssertFalse(draft.problems.contains { $0.severity == .broken })
        // Half a second of real motion: the duck travels from the base stance
        // to the pose and holds it, which is what a still is.
        let contents = try DuckMoveFile.decode(try draft.exported())
        XCTAssertEqual(contents.move.duration, 0.5, accuracy: 1e-9)
        XCTAssertEqual(contents.move.pose(at: 0.5)[DuckModel.mouthIndex],
                       DuckModel.mouthOpen, accuracy: 1e-9)
    }

    /// The one cardinality case that really is not a motion — and the refusal
    /// names the knob that fixes it rather than the rule it broke.
    func testASinglePoseAtZeroIsRefusedWithSomethingToDoAboutIt() {
        let draft = IntentDraft(name: "x", keys: [.init(time: 0, pose: DuckModel.homePose)])
        XCTAssertFalse(draft.isPlayable)
        XCTAssertEqual(draft.problems.map(\.text), [
            "A motion of one keyframe at 0.00 s has no time to happen in. "
          + "Move that keyframe later — half a second is plenty — or add a second one.",
        ])
    }

    /// The gate the export used to skip. The screen drew the orange triangle
    /// and the share sheet handed the file out anyway.
    func testAMotionTheScreenCallsBrokenIsNotHandedOver() {
        let draft = IntentDraft(name: "x", keys: [.init(time: 0, pose: DuckModel.homePose)])
        XCTAssertThrowsError(try draft.exported()) { error in
            XCTAssertEqual(error as? IntentDraft.ExportRefusal, .notPlayable([
                "A motion of one keyframe at 0.00 s has no time to happen in. "
              + "Move that keyframe later — half a second is plenty — or add a second one.",
            ]))
        }
    }

    /// The refusal has to survive BOTH of the app's catch chains without
    /// either view learning a new error type: `IntentAuthorView.share()` falls
    /// back to "\(error)" and `PublishMotionView` to `localizedDescription`.
    /// A refusal a person cannot read is not a refusal.
    func testTheExportRefusalReadsAsASentenceThroughEitherCatchChain() {
        let expected = "The motion cannot be exported as written. "
                     + "A motion of one keyframe at 0.00 s has no time to happen in. "
                     + "Move that keyframe later — half a second is plenty — or add a second one."
        let draft = IntentDraft(name: "x", keys: [.init(time: 0, pose: DuckModel.homePose)])
        do {
            _ = try draft.exported()
            XCTFail("a broken draft must not export")
        } catch {
            XCTAssertEqual("\(error)", expected)
            XCTAssertEqual(error.localizedDescription, expected)
            XCTAssertEqual((error as? IntentDraft.ExportRefusal)?.message, expected)
        }
    }

    /// Nothing at all is still nothing, and it says which end it is.
    func testADraftWithNoKeyframesIsRefused() {
        let draft = IntentDraft(name: "x", keys: [])
        XCTAssertFalse(draft.isPlayable)
        XCTAssertEqual(draft.problems.map(\.text),
                       ["A motion needs at least one keyframe — there is no pose here to hold."])
        XCTAssertThrowsError(try draft.exported())
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
        // And the export refuses it in the screen's own words, not the
        // format's — the person who dragged the slider needs the joint's name.
        XCTAssertThrowsError(try draft.exported()) { error in
            XCTAssertTrue("\(error)".contains(DuckModel.jointNames[3]), "\(error)")
        }
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

    /// Every one of them, because ten of the seventeen used to arrive broken.
    ///
    /// The sampler put angles a hair outside the model's declared travel and
    /// handed the user a draft that neither exported nor previewed — a fault
    /// they had not authored, on the app's second-most-prominent create path.
    func testEveryBundledClipRemixesIntoADraftThatPlaysAndExports() throws {
        let clips = try DuckIntentClip.bundled()
        XCTAssertGreaterThanOrEqual(clips.count, 17, "the corpus should not have shrunk")
        for (name, clip) in clips {
            let draft = IntentDraft.remix(clip)
            XCTAssertTrue(draft.isPlayable, "\(name): \(draft.problems.map(\.text))")
            XCTAssertNoThrow(try draft.exported(), name)
        }
    }

    /// THE CLAMP IS BOUNDED FROM THE CORPUS SIDE, and this is the assertion
    /// that notices when it stops being an artefact. Holding a recorded angle
    /// at the stop is honest while the overshoot is a solver rounding — today
    /// the worst across all seventeen clips is 0.0079 rad (0.45°, back_roll's
    /// neck_pitch), against a 1e-6 validation tolerance and against the
    /// 1.877 rad the eight-keyframe sampling already throws away. A future
    /// recording genuinely half a radian out of travel would be a corpus/range
    /// disagreement worth a person's attention, and clamping it silently while
    /// still calling the result a remix is exactly the silent rewrite this app
    /// refuses to do. So: fail here instead.
    func testTheRemixClampStaysAnArtefactRatherThanARewrite() throws {
        var worst = 0.0, worstClip = "", worstJoint = ""
        for (name, clip) in try DuckIntentClip.bundled() {
            for i in 0..<8 {
                let time = clip.duration * Double(i) / 7
                let sampled = clip.pose(at: time).jointAngles
                for joint in 0..<DuckModel.jointCount {
                    let range = DuckModel.jointRanges[joint]
                    let outside = max(range.lower - sampled[joint], sampled[joint] - range.upper, 0)
                    if outside > worst {
                        worst = outside; worstClip = name; worstJoint = DuckModel.jointNames[joint]
                    }
                }
            }
        }
        XCTAssertGreaterThan(worst, 0,
            "nothing is outside travel any more — the clamp is dead code and remix should stop claiming it")
        XCTAssertLessThan(worst, 0.02,
            "\(worstClip)/\(worstJoint) sits \(worst) rad outside its travel; that is a corpus/range "
          + "disagreement to look at, not a rounding artefact to hold at the stop")
    }

    /// And it only says it when it happened: seven clips need no holding, and
    /// a provenance line claiming otherwise would be this app overclaiming
    /// about its own artefact.
    func testARemixSaysWhenItHeldAnAngleAtTheStopAndIsSilentWhenItDidNot() throws {
        let clips = try DuckIntentClip.bundled()
        let held = IntentDraft.remix(try XCTUnwrap(clips["step_up"]))
        XCTAssertTrue(held.provenance.contains("held at the stop"), held.provenance)
        XCTAssertTrue(held.provenance.contains("0.0065"), held.provenance)
        let untouched = IntentDraft.remix(try XCTUnwrap(clips["kick_left"]))
        XCTAssertFalse(untouched.provenance.contains("held at the stop"), untouched.provenance)
    }

    // MARK: - the keyframe at 0.00 s

    /// THE FIRST KEYFRAME IS WHAT THE PREVIEW SHOWS, and for a long time it was
    /// not. `pose(at:)` answered the home stance for every non-positive time,
    /// so the 0.00 s keyframe — the one the editor opens on, every time, from
    /// both create paths — could be sampled at every instant except its own.
    /// Somebody dragged a joint for a minute and the duck did not move. Fixed
    /// in DuckKit; pinned here because this is the layer the app talks to.
    func testAPosedFirstKeyframeIsWhatABlankDraftShowsAtZero() {
        var draft = IntentDraft.blank()
        var crouch = DuckModel.homePose
        crouch[3] = min(DuckModel.homePose[3] + 0.3, DuckModel.jointRanges[3].upper)
        draft.keys[0].pose = crouch
        XCTAssertEqual(draft.keys[0].time, 0, "blank() opens the editor on a keyframe at exactly zero")
        XCTAssertEqual(draft.pose(at: 0), crouch)
        XCTAssertNotEqual(draft.pose(at: 0), DuckModel.homePose,
                          "the stage would be drawing the home stance instead of the authored pose")
    }

    /// Same for the other door in, where it was worse: a remix opened on the
    /// home stance with fourteen of fifteen joints wrong, before the user had
    /// touched anything.
    func testARemixShowsItsOwnFirstFrameAtZeroAndNotTheHomeStance() throws {
        let clips = try DuckIntentClip.bundled()
        var everDiffersFromHome = false
        for (name, clip) in clips {
            let draft = IntentDraft.remix(clip)
            XCTAssertEqual(draft.keys[0].time, 0, "\(name): remix starts at exactly zero")
            XCTAssertEqual(draft.pose(at: 0), draft.keys[0].pose, "\(name)")
            if draft.keys[0].pose != DuckModel.homePose { everDiffersFromHome = true }
        }
        XCTAssertTrue(everDiffersFromHome,
            "if every clip's first frame were the home stance this test could not tell the two apart")
    }

    /// The app's own round trip: export a motion, read it back, and the pose
    /// you started from is still there. `decode` used to re-SAMPLE the move at
    /// each keyframe's time instead of reading the keyframe, and at t = 0 that
    /// sample was the base stance — so a motion that started from a crouch
    /// came back starting from standing, with no message.
    func testAMotionThatStartsFromACrouchStillDoesAfterARoundTrip() throws {
        var crouch = DuckModel.homePose
        crouch[3] = min(DuckModel.homePose[3] + 0.3, DuckModel.jointRanges[3].upper)
        let draft = IntentDraft(name: "crouch start", keys: [
            .init(time: 0, pose: crouch),
            .init(time: 0.6, pose: DuckModel.homePose),
        ])
        XCTAssertTrue(draft.isPlayable, "\(draft.problems.map(\.text))")
        let back = try IntentDraft.decode(try draft.exported())
        XCTAssertEqual(back.keys.count, 2)
        XCTAssertEqual(back.keys[0].time, 0, accuracy: 1e-12)
        for joint in 0..<DuckModel.jointCount {
            XCTAssertEqual(back.keys[0].pose[joint], crouch[joint], accuracy: 1e-12,
                           DuckModel.jointNames[joint])
        }
        XCTAssertGreaterThan(abs(back.keys[0].pose[3] - DuckModel.homePose[3]), 0.2,
            "the crouch it started from was replaced by the home stance on the way back in")
    }

    // MARK: - the name on the file

    /// A NAME IS NOT A PATH COMPONENT. "walk / bow" addressed a folder that
    /// does not exist, so the share failed with "The file could not be
    /// written." — honest, naming the wrong cause, and with nothing to act on.
    func testANameWithASeparatorBecomesOneFilename() {
        var draft = IntentDraft.blank(named: "walk / bow")
        XCTAssertEqual(draft.suggestedFilename, "walk-bow.duckmove")
        // The operation that used to fail, done here: one path component.
        let url = URL(fileURLWithPath: "/tmp").appendingPathComponent(draft.suggestedFilename)
        XCTAssertEqual(url.lastPathComponent, "walk-bow.duckmove")
        XCTAssertEqual(url.deletingLastPathComponent().path, "/tmp")

        draft.name = "3/4 turn"
        XCTAssertEqual(draft.suggestedFilename, "3-4 turn.duckmove")
        draft.name = "back\\flip"
        XCTAssertEqual(draft.suggestedFilename, "back-flip.duckmove")
    }

    /// An empty name used to give ".duckmove", a dotfile AirDrop and Files
    /// show as nameless. A file has to arrive somewhere a person can point at.
    func testAMotionWithNoUsableNameStillGetsAFilename() {
        var draft = IntentDraft.blank(named: "")
        XCTAssertEqual(draft.suggestedFilename, "microduck-motion.duckmove")
        draft.name = "   ///  "
        XCTAssertEqual(draft.suggestedFilename, "microduck-motion.duckmove")
        draft.name = ".hidden"
        XCTAssertEqual(draft.suggestedFilename, "hidden.duckmove")
    }

    /// NOT `MotionPublication.slug`, whose ASCII-only rule exists for a Hugging
    /// Face repository name. A filesystem takes these fine, and collapsing them
    /// would have two motions overwrite each other in the temporary directory —
    /// a silent wrong file in place of a visible wrong cause.
    func testAFilenameKeepsLettersTheFilesystemHasNoProblemWith() {
        var draft = IntentDraft.blank(named: "Élan")
        XCTAssertEqual(draft.suggestedFilename, "Élan.duckmove")
        draft.name = "お辞儀"
        XCTAssertEqual(draft.suggestedFilename, "お辞儀.duckmove")
        draft.name = "New motion"
        XCTAssertEqual(draft.suggestedFilename, "New motion.duckmove")
        XCTAssertNotEqual(IntentDraft.filenameStem(for: "お辞儀"),
                          IntentDraft.filenameStem(for: "こんにちは"),
                          "two motions must not share a stem and overwrite each other")
    }

    /// Slugging the filename must not slug the motion. The name is written
    /// verbatim into the file, so the typed one survives the trip.
    func testTheTypedNameSurvivesEvenWhenTheFilenameIsSlugged() throws {
        let draft = IntentDraft.blank(named: "walk / bow")
        XCTAssertEqual(draft.suggestedFilename, "walk-bow.duckmove")
        XCTAssertEqual(try IntentDraft.decode(try draft.exported()).name, "walk / bow")
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

extension IntentDraftTests {

    /// The interop the whole pipeline rests on: what the authoring screen
    /// exports, DuckKit's shared reader opens — which is what OpenCastor uses
    /// to play a motion as a goal celebration.
    func testWhatTheEditorExportsTheSharedReaderOpens() throws {
        var open = DuckModel.homePose
        open[DuckModel.mouthIndex] = DuckModel.mouthOpen
        let draft = IntentDraft(name: "celebration", keys: [
            .init(time: 0, pose: DuckModel.homePose),
            .init(time: 0.5, pose: open),
            .init(time: 1.0, pose: DuckModel.homePose),
        ])
        let contents = try DuckMoveFile.decode(try draft.exported())
        XCTAssertEqual(contents.name, "celebration")
        XCTAssertEqual(contents.move.duration, 1.0, accuracy: 1e-9)
        XCTAssertTrue(contents.note?.contains("no physics ran") == true,
                      "the caveat travels with the file")
        XCTAssertEqual(contents.move.pose(at: 0.5)[DuckModel.mouthIndex],
                       DuckModel.mouthOpen, accuracy: 1e-9)
    }
}
