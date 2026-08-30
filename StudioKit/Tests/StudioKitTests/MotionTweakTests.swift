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
    ///
    /// AND THE NOTE HAS TO SAY SO. This test used to throw the notes away with
    /// a `_`, which is how "neck set to 500°" shipped over a keyframe holding
    /// 40° — see `testAClampedAngleIsReportedAsClamped` below.
    func testAnImpossibleAngleIsClampedToTheTravel() throws {
        let tweak = MotionTweak(summary: "x",
                                edits: [.joint(at: 0.8, word: "neck", degrees: 500)])
        let (edited, notes) = try tweak.applied(to: bow())
        let slot = DuckModel.jointIndex(of: "neck_pitch")!
        let ordered = edited.keys.sorted { $0.time < $1.time }
        XCTAssertLessThanOrEqual(ordered[1].pose[slot], DuckModel.jointRanges[slot].upper)
        XCTAssertFalse(notes.contains { $0.contains("set to 500") },
                       "the note must not claim an angle the keyframe does not hold")
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

    // MARK: - two keyframes cannot share one instant

    /// "Hold the bow until the end" is the most natural retiming sentence
    /// there is, and a model answers it with the time of the keyframe that is
    /// already there. That used to be written straight in: the times became
    /// [0.0, 1.6, 1.6], `IntentDraft.pose(at:)` swallowed the throw and drew
    /// the duck standing still at every playhead position, export refused —
    /// and the Ask panel said "Moved 0.80 s to 1.60 s." with a checkmark.
    func testMovingAKeyframeOntoAnOccupiedInstantIsRefusedRatherThanDone() {
        let before = bow()
        XCTAssertThrowsError(try MotionTweak(summary: "hold it longer",
                                             edits: [.moveKey(at: 0.8, to: 1.6)])
            .applied(to: before)) {
            XCTAssertEqual($0 as? MotionTweak.Failure, .timeAlreadyTaken(1.6))
            XCTAssertEqual(($0 as? MotionTweak.Failure)?.message,
                           "There is already a keyframe at 1.60 s, and two keyframes cannot "
                         + "share one instant. Nothing was changed.")
        }
    }

    /// A NEAR miss is the worse half of the same bug and needs the same window.
    /// A move to 1.599 s beside a keyframe at 1.6 s sorts fine, plays, EXPORTS
    /// — and asks the neck for hundreds of radians a second to get there. A
    /// loud refusal beats a shippable file that jolts a real servo.
    func testANearlyIdenticalInstantIsRefusedTooBecauseThatOneWouldExport() {
        XCTAssertThrowsError(try MotionTweak(summary: "x", edits: [.moveKey(at: 0.8, to: 1.599)])
            .applied(to: bow())) {
            XCTAssertEqual($0 as? MotionTweak.Failure, .timeAlreadyTaken(1.599))
        }
    }

    /// The guard excludes the moved keyframe BY ID: its own current time is
    /// inside the window, so a time-only test would refuse a legal small
    /// retime, and a no-op self-move with it.
    func testAKeyframeDoesNotCollideWithItself() throws {
        let (nudged, _) = try MotionTweak(summary: "x", edits: [.moveKey(at: 0.8, to: 0.802)])
            .applied(to: bow())
        XCTAssertEqual(nudged.keys.sorted { $0.time < $1.time }[1].time, 0.802, accuracy: 1e-9)
        let (still, notes) = try MotionTweak(summary: "x", edits: [.moveKey(at: 0.8, to: 0.8)])
            .applied(to: bow())
        XCTAssertEqual(still.keys.count, 3)
        XCTAssertEqual(notes, ["Moved 0.80 s to 0.80 s."])
    }

    /// THE INVARIANT THAT WOULD HAVE CAUGHT ALL OF THIS: a tweak never hands
    /// back a draft the same package calls broken. Every edit below is one a
    /// model plausibly emits for a sentence a person plausibly types.
    func testNoTweakEverReturnsABrokenDraft() {
        let lists: [[MotionTweak.Edit]] = [
            [.moveKey(at: 0.8, to: 1.6)],
            [.moveKey(at: 0.8, to: 0.0)],
            [.moveKey(at: 1.6, to: -3)],
            [.moveKey(at: 0.0, to: 0.8), .moveKey(at: 0.8, to: 0.0)],
            [.addKey(at: 0.8)],
            [.removeKey(at: 0.8), .removeKey(at: 1.6)],
            [.removeKey(at: 0.0), .removeKey(at: 0.8), .removeKey(at: 1.6)],
            [.joint(at: 0.8, word: "neck", degrees: 4000)],
            [.joint(at: 0.8, word: "legs", degrees: -900)],
        ]
        for edits in lists {
            guard let (edited, _) = try? MotionTweak(summary: "x", edits: edits).applied(to: bow())
            else { continue }  // a refusal is a fine outcome; a broken draft is not
            XCTAssertTrue(edited.problems.filter { $0.severity == .broken }.isEmpty,
                          "\(edits) left \(edited.problems.map(\.text))")
            XCTAssertTrue(edited.isPlayable, "\(edits)")
        }
    }

    /// WHY THE COLLISION IS A CRASH AND NOT ONLY AN UNPLAYABLE MOTION.
    /// `DuckMove.init(name:keyframes:)` carries a `precondition` on strictly
    /// increasing times, and a precondition TRAPS. This pins the one thing
    /// that keeps duplicate times off that door: `IntentDraft.move()` goes
    /// through the RAW validating initialiser, which throws. If a refactor
    /// ever routes a draft through the literal initialiser instead, this test
    /// is the only thing standing between a tweak and a hard crash — which is
    /// why the tweak must not be able to make the duplicate in the first place.
    func testDuplicateTimesReachTheThrowingDoorAndNotTheTrappingOne() {
        var doubled = bow()
        doubled.keys[2].time = 0.8
        XCTAssertThrowsError(try doubled.move()) {
            XCTAssertEqual($0 as? DuckMove.Invalid, .timesNotIncreasing(keyframe: 2))
        }
        XCTAssertFalse(doubled.isPlayable)
    }

    // MARK: - one refusal does not throw away the rest of the sentence

    /// "Bow deeper and look left at the end", answered with one joint word the
    /// resolver cannot place, used to lose the deeper bow as well — and the
    /// message never mentioned that anything else had been dropped, so the
    /// obvious retry dropped it again.
    func testAnInstructionItCannotApplyDoesNotDiscardTheOnesItCan() throws {
        let outcome = try MotionTweak(summary: "deeper, then look left",
                                      edits: [.joint(at: 0.8, word: "neck", degrees: 35),
                                              .joint(at: 1.6, word: "wing", degrees: 25)])
            .outcome(applyingTo: bow())
        XCTAssertEqual(degrees(outcome.draft, "neck_pitch", at: 1), 35, accuracy: 0.5)
        XCTAssertEqual(outcome.notes, ["neck set to 35° at 0.80 s."])
        XCTAssertEqual(outcome.refusals,
                       ["wing is not a joint this robot has. It has a neck, a head that nods, "
                      + "turns and tilts, a beak, and hips, knees and ankles on both sides. "
                      + "That instruction was skipped."])
        // The flat door a caller that cannot tell them apart still reads.
        let (_, notes) = try MotionTweak(summary: "x",
                                         edits: [.joint(at: 0.8, word: "neck", degrees: 35),
                                                 .joint(at: 1.6, word: "wing", degrees: 25)])
            .applied(to: bow())
        XCTAssertEqual(notes.count, 2)
    }

    /// When nothing survived, the refusal IS the answer — and it says that,
    /// rather than leaving the person to guess whether the rest landed.
    func testARefusalThatChangedNothingSaysNothingWasChanged() {
        XCTAssertThrowsError(try MotionTweak(summary: "x",
                                             edits: [.joint(at: 0.8, word: "tail", degrees: 10)])
            .applied(to: bow())) {
            XCTAssertEqual($0 as? MotionTweak.Failure, .unknownJoint("tail"))
            XCTAssertTrue(($0 as? MotionTweak.Failure)?.message.hasSuffix("Nothing was changed.")
                          ?? false)
        }
    }

    /// An instruction that was sent and did nothing has to be visible, or the
    /// panel is silent about a sentence the person watched themselves send.
    func testAnEmptyRenameIsSaidRatherThanDroppedInSilence() throws {
        let outcome = try MotionTweak(summary: "x", edits: [.rename("   "),
                                                            .joint(at: 0.8, word: "neck", degrees: 5)])
            .outcome(applyingTo: bow())
        XCTAssertEqual(outcome.draft.name, "Bow")
        XCTAssertEqual(outcome.refusals,
                       ["An empty name is not a name, so the motion is still called \"Bow\"."])
    }

    // MARK: - the same vocabulary drafting uses

    /// THE PROMPT TEACHES THIS EXACT STRING. `ChatDraft.tweakInstructions`
    /// embeds `MotionProposal.grounding()` verbatim, annotations and all, so a
    /// small model echoes "neck (-110° to 40°)" back — and the tweak resolver
    /// used to answer that the robot has no such joint.
    func testTheAnnotatedJointFormTheGroundingItselfTeachesIsAccepted() throws {
        XCTAssertTrue(MotionProposal.grounding().contains("neck (-110° to 40°)"),
                      "if the grounding stops teaching this form, this test is the record of why")
        let (edited, notes) = try MotionTweak(summary: "deeper",
                                              edits: [.joint(at: 0.8,
                                                             word: "neck (-110° to 40°)",
                                                             degrees: 20)])
            .applied(to: bow())
        XCTAssertEqual(degrees(edited, "neck_pitch", at: 1), 20, accuracy: 0.5)
        XCTAssertEqual(notes, ["neck set to 20° at 0.80 s."],
                       "the note speaks the app's plain voice, not the model's echo")
    }

    /// The twin of `MotionProposalTests.testWireNamesAndSloppyFormattingResolve`,
    /// which the tweak path never had — which is how the two drifted apart.
    func testWireNamesAndSloppyFormattingResolve() {
        for word in ["left_hip", "left-hip", "LEFT HIP", "  left hip  "] {
            XCTAssertEqual(MotionTweak.targets(for: word)?.map(\.joint), ["left_hip_pitch"], word)
        }
        XCTAssertEqual(MotionTweak.targets(for: "head-turn")?.map(\.joint), ["head_yaw"])
        XCTAssertEqual(MotionTweak.targets(for: "head nod\n")?.map(\.joint), ["head_pitch"])
        XCTAssertEqual(MotionTweak.targets(for: "both-hips")?.map(\.joint),
                       ["left_hip_pitch", "right_hip_pitch"])
        XCTAssertEqual(MotionTweak.targets(for: "neck\n")?.map(\.joint), ["neck_pitch"])
        // Still refused, because a wrong hint is worse than none — and only a
        // TRAILING annotation is stripped, so this does not vanish as a blank.
        for word in ["tail", "wing", "elbow", "", "(left) knee"] {
            XCTAssertNil(MotionTweak.targets(for: word), word)
        }
    }

    /// ONE VOCABULARY IN FACT, NOT MERELY BY ASSERTION. `MotionTweak.targets`
    /// and `MotionProposal.expand` are two copies of one ladder; this is what
    /// notices when they part — a sixteenth DuckKit joint forgiven by drafting
    /// and refused by editing would fail here first.
    func testEveryWordDraftingKnowsMeansTheSameThingWhenEditing() {
        let words = MotionProposal.offeredWords
            + Array(MotionProposal.synonyms.keys)
            + DuckModel.jointNames
        for word in words {
            let editing = MotionTweak.targets(for: word)
            let drafting = MotionProposal.expand(.init(joint: word, degrees: 10))
            XCTAssertEqual(editing?.map(\.joint), drafting?.map(\.joint), word)
            // Mirror signs too: "both hips 15°" must mean the same pair of
            // numbers in a sentence that writes a motion and one that edits it.
            XCTAssertEqual(editing?.map { $0.mirror * 10 }, drafting?.map(\.degrees), word)
        }
    }

    // MARK: - the note says what happened, not what was asked for

    /// THE APP'S OWN SUCCESS LIST STATED AN ACT IT DID NOT PERFORM. The note
    /// was formatted from the model's number, so a request for 500° printed
    /// "neck set to 500°" over a keyframe holding 40° — and the person, seeing
    /// a shallower bow than the number implies, types a bigger number that
    /// clamps to the same 40° again.
    func testAClampedAngleIsReportedAsClampedAndNamesTheStop() throws {
        let (_, notes) = try MotionTweak(summary: "much deeper",
                                         edits: [.joint(at: 0.8, word: "neck", degrees: 500)])
            .applied(to: bow())
        XCTAssertEqual(notes, ["neck asked for 500° at 0.80 s and stopped at 40° — "
                             + "that is the end of its travel."])
    }

    /// The clamp is only mentioned when it BITES. `neck_pitch`'s real headroom
    /// is 39.998°, so an ordinary "bow to 40°" clamps by 0.002° — reporting
    /// that would be a lie of the opposite kind.
    func testAnAngleTheJointCanReachIsReportedPlainly() throws {
        let (_, notes) = try MotionTweak(summary: "x",
                                         edits: [.joint(at: 0.8, word: "neck", degrees: 40)])
            .applied(to: bow())
        XCTAssertEqual(notes, ["neck set to 40° at 0.80 s."])
    }

    /// The right half of a mirrored pair stores the negated angle. Reading it
    /// back without dividing the mirror out would report every pair word as
    /// clamped, and print the wrong sign.
    func testTheMirroredHalfOfAPairIsNotMistakenForAClamp() throws {
        let (edited, notes) = try MotionTweak(summary: "x",
                                              edits: [.joint(at: 0.8, word: "both hips", degrees: 15)])
            .applied(to: bow())
        XCTAssertEqual(degrees(edited, "right_hip_pitch", at: 1), -15, accuracy: 0.5)
        XCTAssertEqual(notes, ["both hips set to 15° at 0.80 s."])
    }

    /// A GROUP WORD HAS NO SINGLE ACHIEVED NUMBER. "legs" at 100° reaches 100°
    /// at the hips and stops at 90° at the knees, so neither the request nor
    /// any one achieved angle is an honest summary — the sentence has to name
    /// what stopped.
    func testAGroupThatStopsUnevenlyNamesTheJointsThatStopped() throws {
        let (_, notes) = try MotionTweak(summary: "x",
                                         edits: [.joint(at: 0.8, word: "legs", degrees: 100)])
            .applied(to: bow())
        XCTAssertEqual(notes, ["legs set to 100° at 0.80 s, except left knee at 90°, "
                             + "right knee at 90°, which stopped at the end of travel."])
    }

    /// A pair that stops together still gets the short sentence.
    func testAPairThatStopsTogetherGetsOneNumber() throws {
        let (_, notes) = try MotionTweak(summary: "x",
                                         edits: [.joint(at: 0.8, word: "both hips", degrees: 200)])
            .applied(to: bow())
        XCTAssertEqual(notes, ["both hips asked for 200° at 0.80 s and stopped at 116° — "
                             + "that is the end of its travel."])
    }

    // MARK: - what a removal may leave behind

    /// "Drop the second pose" on a two-keyframe motion used to report success
    /// and leave a single keyframe at 0.00 s: duration 0, a scrubber that
    /// cannot move, and a draft `IntentDraft.problems` calls broken. The tweak
    /// vocabulary and the draft's own validity rule now agree.
    func testRemovingDownToOnePoseWithNoTimeToHappenInIsRefused() {
        XCTAssertThrowsError(try MotionTweak(summary: "drop the second pose",
                                             edits: [.removeKey(at: 0.5)])
            .applied(to: .blank())) {
            XCTAssertEqual($0 as? MotionTweak.Failure, .wouldLeaveNoTimeToHappenIn)
        }
    }

    /// ONE POSE IS A MOTION PROVIDED IT HAS TIME TO HAPPEN IN, which is the
    /// draft's own rule — so the mirror-image removal is allowed, and the
    /// guard is not simply "never fewer than two".
    func testRemovingDownToOnePoseThatStillHasTimeIsAllowed() throws {
        let (edited, notes) = try MotionTweak(summary: "x", edits: [.removeKey(at: 0.0)])
            .applied(to: .blank())
        XCTAssertEqual(edited.keys.map(\.time), [0.5])
        XCTAssertTrue(edited.isPlayable)
        XCTAssertEqual(notes, ["Removed the keyframe at 0.00 s."])
    }

    /// THE PRICE OF BLAMING THE EDIT RATHER THAN THE END STATE, paid out loud.
    /// "Move the second pose out to a second", answered as remove-then-add,
    /// passes through a momentarily timeless motion. The removal is refused,
    /// the add still happens, and the sentence says which half did not — where
    /// the alternative, judging only the final state, would have to keep an
    /// invalid draft alive in between.
    func testARefusedRemovalStillLetsTheRestOfTheListThrough() throws {
        let outcome = try MotionTweak(summary: "put the second pose a second in",
                                      edits: [.removeKey(at: 0.5), .addKey(at: 1.0)])
            .outcome(applyingTo: .blank())
        XCTAssertEqual(outcome.draft.keys.map(\.time), [0.0, 0.5, 1.0])
        XCTAssertTrue(outcome.draft.isPlayable)
        XCTAssertEqual(outcome.notes, ["Added a keyframe at 1.00 s."])
        XCTAssertEqual(outcome.refusals.count, 1)
        XCTAssertTrue(outcome.refusals[0].hasSuffix("That instruction was skipped."))
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
