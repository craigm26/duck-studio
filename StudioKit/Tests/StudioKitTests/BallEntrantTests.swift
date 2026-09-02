import XCTest
import DuckKit
@testable import StudioKit

/// The two entrant kinds, the four bundled ones, and the editor round trip.
final class BallEntrantTests: XCTestCase {

    // MARK: - the four that ship

    func testTheFourBundledEntrantsParseAndAreTheContractsFour() throws {
        XCTAssertEqual(BallChallenge.controls.map(\.file),
                       ["ctrl_do_nothing.json", "ctrl_ball_kick_left.json",
                        "ctrl_ball_kick_right.json", "ctrl_alpha_walking.json"])
        for control in BallChallenge.controls {
            let text = try XCTUnwrap(BallChallenge.Entrants.text(control.file))
            let entrant = try BallChallenge.Entrant.decode(Data(text.utf8))
            XCTAssertEqual(entrant, control.entrant, control.file)
            XCTAssertGreaterThan(entrant.seconds, 0, control.file)
        }
    }

    /// THE DO-NOTHING CONTROL IS THE HOME POSE HELD STILL, which is what makes
    /// it a control: a criterion this row passes is not a chasing test, and it
    /// can only be that row if the pose really is home.
    func testTheDoNothingControlIsTheHomePoseHeldForFiveSeconds() throws {
        let entrant = BallChallenge.Entrants.doNothing
        XCTAssertEqual(entrant.kind, .move)
        XCTAssertEqual(entrant.seconds, 5)
        let move = try XCTUnwrap(entrant.move)
        XCTAssertEqual(move.keyframes.count, 2)
        XCTAssertEqual(move.blend, 1)
        let home = (0..<DuckModel.policyJointCount)
            .map { DuckModel.homePose[DuckModel.jointOfPolicySlot($0)] }
        for frame in move.keyframes {
            XCTAssertEqual(frame.pose.count, DuckModel.policyJointCount)
            for (slot, value) in frame.pose.enumerated() {
                XCTAssertEqual(value, home[slot], accuracy: 1e-12, "slot \(slot)")
            }
        }
        XCTAssertEqual(move.keyframes.map(\.t), [1.0, 4.9])
    }

    /// THE KICK POLICIES ARE COMMANDED AT THE CENTRE OF THE DISTRIBUTION THEY
    /// WERE TRAINED UNDER — all three twist ranges are centred on zero and
    /// resampled once per episode — and for the episode length they were
    /// trained at. Commanding them to walk would be commanding them fifty
    /// times outside their own lin_vel_x range and calling the result a
    /// measurement of Pollen's policy.
    func testTheKickPoliciesAreHeldAtRestForTheirOwnEpisodeLength() throws {
        for entrant in [BallChallenge.Entrants.ballKickLeft,
                        BallChallenge.Entrants.ballKickRight] {
            XCTAssertEqual(entrant.kind, .policy)
            XCTAssertEqual(entrant.seconds, 5)
            XCTAssertEqual(entrant.schedule, [DuckBench.Step(at: 0, vx: 0, vy: 0, vyaw: 0)])
            XCTAssertEqual(entrant.commandSaid, "held at rest")
            XCTAssertNil(entrant.move)
            XCTAssertFalse(entrant.isEditable)
        }
        XCTAssertEqual(BallChallenge.Entrants.ballKickLeft.policy, "ball_kick_left.onnx")
        XCTAssertEqual(BallChallenge.Entrants.ballKickRight.policy, "ball_kick_right.onnx")
    }

    func testTheNaiveChaserWalksStraightAheadForFourSeconds() {
        let entrant = BallChallenge.Entrants.alphaWalking
        XCTAssertEqual(entrant.name, "ctrl_alpha_walking")
        XCTAssertEqual(entrant.kind, .policy)
        XCTAssertEqual(entrant.policy, "alpha_walking.onnx")
        XCTAssertEqual(entrant.seconds, 4)
        XCTAssertEqual(entrant.schedule, [DuckBench.Step(at: 0, vx: 0.5, vy: 0, vyaw: 0)])
        XCTAssertEqual(entrant.commandSaid, "vx 0.5")
    }

    /// The three policies cannot be edited and the one move can. That split is
    /// the whole reason `policyNotEditable` exists.
    func testOnlyTheMoveEntrantIsEditable() {
        XCTAssertEqual(BallChallenge.editableControls.map(\.file), ["ctrl_do_nothing.json"])
        XCTAssertEqual(BallChallenge.controls.filter { !$0.isEditable }.count, 3)
    }

    /// alpha_walking was trained under a different config, and its terms carry
    /// that caveat rather than being dropped or presented as the kick's.
    func testTheVelocityPolicyCarriesItsOwnCaveatAndTheKicksDoNot() {
        XCTAssertNil(BallChallenge.rewardCaveat(forPolicy: "ball_kick_left.onnx"))
        XCTAssertNil(BallChallenge.rewardCaveat(forPolicy: "ball_kick_right.onnx"))
        XCTAssertEqual(BallChallenge.rewardCaveat(forPolicy: "alpha_walking.onnx"),
                       BallChallenge.velocityPolicyCaveat)
        let stranger = BallChallenge.rewardCaveat(forPolicy: "roulade.onnx")
        XCTAssertNotNil(stranger)
        XCTAssertTrue(stranger!.contains("roulade.onnx"))
        XCTAssertNil(BallChallenge.rewardCaveat(forPolicy: nil))
    }

    // MARK: - what a bad entrant is told

    func testAnEntrantWithoutAKnownKindIsRefusedByName() {
        let data = Data(#"{"name":"x","kind":"vibes","seconds":5}"#.utf8)
        XCTAssertThrowsError(try BallChallenge.Entrant.decode(data)) { error in
            guard let refusal = error as? BallChallenge.Entrant.Refusal else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(refusal, .unknownKind("vibes"))
            XCTAssertTrue(refusal.message.contains("\"vibes\""))
            XCTAssertTrue(refusal.message.contains("\"move\""))
            XCTAssertTrue(refusal.message.contains("\"policy\""))
        }
    }

    func testAPolicyEntrantWithNoScheduleIsRefused() {
        let data = Data(#"{"name":"x","kind":"policy","seconds":4,"policy":"p.onnx"}"#.utf8)
        XCTAssertThrowsError(try BallChallenge.Entrant.decode(data)) {
            XCTAssertEqual($0 as? BallChallenge.Entrant.Refusal, .noSchedule)
        }
    }

    func testAPolicyEntrantThatNamesNoPolicyIsRefused() {
        let data = Data(#"{"name":"x","kind":"policy","seconds":4,"schedule":[[0,{}]]}"#.utf8)
        XCTAssertThrowsError(try BallChallenge.Entrant.decode(data)) {
            XCTAssertEqual($0 as? BallChallenge.Entrant.Refusal, .noPolicyNamed)
        }
    }

    func testAnEpisodeOfNoSecondsIsRefused() {
        let data = Data(#"{"name":"x","kind":"policy","seconds":0,"policy":"p.onnx","schedule":[[0,{}]]}"#.utf8)
        XCTAssertThrowsError(try BallChallenge.Entrant.decode(data)) {
            XCTAssertEqual($0 as? BallChallenge.Entrant.Refusal, .badSeconds(0))
        }
    }

    /// A MOVE ENTRANT'S INTENT IS A HARNESS INTENT, and it is checked by the
    /// same type the stairs challenge uses — so a thirteen-wide pose is caught
    /// here with the sentence that names the mouth, rather than reaching the
    /// bench.
    func testAMoveEntrantWithAWrongWidthPoseIsRefusedWithTheHarnessSentence() {
        let data = Data(#"{"name":"x","kind":"move","seconds":5,"intent":{"keyframes":[{"t":1,"pose":[0,0,0]}]}}"#.utf8)
        XCTAssertThrowsError(try BallChallenge.Entrant.decode(data)) { error in
            guard let refusal = error as? BallChallenge.Entrant.Refusal,
                  case .notAMove(let why) = refusal else { return XCTFail("\(error)") }
            XCTAssertTrue(why.contains("14 joints"), why)
            XCTAssertTrue(why.contains("mouth"), why)
        }
    }

    func testAnEntrantThatIsNotAnObjectIsRefused() {
        XCTAssertThrowsError(try BallChallenge.Entrant.decode(Data("[1,2]".utf8))) {
            XCTAssertEqual($0 as? BallChallenge.Entrant.Refusal, .notAnObject)
        }
    }

    // MARK: - into the editor and back

    /// A DRAFT LIFTED OUT OF THIS CHALLENGE SAYS WHICH CHALLENGE. The moment
    /// it is in the Studio's draft list it looks like something the person
    /// wrote, and a draft that said "Stairs Challenge" would be a provenance
    /// line worse than none.
    func testTheProvenanceNamesTheBallChallenge() throws {
        let draft = try BallChallenge.Entrants.doNothing.toDraft(hash: "abc123abc123")
        XCTAssertTrue(draft.provenance.hasPrefix("From the Microduck Ball Challenge"),
                      draft.provenance)
        XCTAssertTrue(draft.provenance.contains("move abc123abc123"))
        XCTAssertTrue(draft.provenance.contains("Simulation only"))
        XCTAssertEqual(draft.name, "ctrl_do_nothing")
    }

    /// The convenience that mirrors `StairsChallenge.draft(for:)` writes the
    /// published hash in, and refuses a policy the same way.
    func testDraftForAControlCarriesItsPublishedHash() throws {
        let doNothing = try XCTUnwrap(BallChallenge.control(file: "ctrl_do_nothing.json"))
        let draft = try BallChallenge.draft(for: doNothing)
        XCTAssertTrue(draft.provenance.contains("move bc77453e40c6"), draft.provenance)
        XCTAssertFalse(draft.provenance.contains("rank"), draft.provenance)
        let walker = try XCTUnwrap(BallChallenge.control(file: "ctrl_alpha_walking.json"))
        XCTAssertThrowsError(try BallChallenge.draft(for: walker)) {
            XCTAssertEqual($0 as? BallChallenge.Entrant.Refusal, .notEditable)
        }
    }

    /// And the stairs sentence is untouched by the generalisation.
    func testTheStairsProvenanceIsUnchanged() throws {
        let draft = try StairsChallenge.draft(for: StairsChallenge.record)
        XCTAssertTrue(draft.provenance.hasPrefix("From the Microduck Stairs Challenge"))
    }

    /// Fourteen joints become fifteen through `jointOfPolicySlot`, which is
    /// the stairs machinery, reused rather than re-transcribed.
    func testTheDraftIsFifteenWideWithTheMouthAtHome() throws {
        let draft = try BallChallenge.Entrants.doNothing.toDraft()
        for key in draft.keys {
            XCTAssertEqual(key.pose, DuckModel.homePose)
        }
    }

    /// A POLICY REFUSES TO OPEN rather than opening an empty draft, and the
    /// refusal is the sentence the screen shows.
    func testAPolicyEntrantRefusesToOpenInTheEditor() {
        XCTAssertThrowsError(try BallChallenge.Entrants.alphaWalking.toDraft()) { error in
            XCTAssertEqual(error as? BallChallenge.Entrant.Refusal, .notEditable)
            XCTAssertEqual((error as? BallChallenge.Entrant.Refusal)?.message,
                           BallChallenge.policyNotEditable)
        }
    }

    /// AN UNEDITED ROUND TRIP CHANGES NO VALUE, AND THEREFORE NO HASH.
    ///
    /// IT DOES CHANGE ONE NUMBER TOKEN, and that is worth stating rather than
    /// hiding: `ctrl_do_nothing.json` is hand-authored and writes its first
    /// keyframe time as `1.0`, while `applying(draft:)` re-emits the value
    /// 1.0 in the shape `JSON.stringify` writes it, which is `1`. The bench
    /// hashes `entrantHashPayload`, a canonical string with keys sorted at
    /// every depth and numbers serialised by the JavaScript rule — under which
    /// 1.0 and 1 are the same token — so the identity survives. Every VALUE is
    /// unchanged, which is what this asserts.
    func testAnUneditedRoundTripChangesNoValue() throws {
        let entrant = BallChallenge.Entrants.doNothing
        let again = try entrant.applying(draft: entrant.toDraft())
        XCTAssertEqual(again.name, entrant.name)
        XCTAssertEqual(again.seconds, entrant.seconds)
        XCTAssertEqual(again.note, entrant.note)
        XCTAssertEqual(again.move?.blend, entrant.move?.blend)
        XCTAssertEqual(again.move?.keyframes, entrant.move?.keyframes)
        XCTAssertEqual(again.move?.keyframes.map(\.t), [1.0, 4.9])
        // And the two files differ only in that one token.
        let before = String(decoding: entrant.encoded(), as: UTF8.self)
        let after = String(decoding: again.encoded(), as: UTF8.self)
        XCTAssertEqual(after, before.replacingOccurrences(of: "\"t\": 1.0", with: "\"t\": 1"))
    }

    /// AND THE HARNESS'S OWN BYTES ARE WHAT THE APP CARRIES. `text(_:)` is the
    /// file; `encoded()` is the canonical two-space form, which these
    /// hand-authored files are deliberately not in — the bench normalises
    /// before it hashes, so the shape does not matter and the CONTENT does.
    func testTheAppCarriesTheHarnessesBytesAndParsesThemToTheSameValue() throws {
        for control in BallChallenge.controls {
            let text = try XCTUnwrap(BallChallenge.Entrants.text(control.file))
            XCTAssertTrue(text.hasSuffix("}\n"), control.file)
            let parsed = try HarnessJSON.parse(Data(text.utf8))
            XCTAssertEqual(parsed, control.entrant.json, control.file)
            // The canonical re-emission parses back to the same value, which
            // is what the request body and the bundle rely on.
            XCTAssertEqual(try HarnessJSON.parse(control.entrant.encoded()), parsed, control.file)
        }
    }

    /// AN EDIT REPLACES THE KEYFRAMES AND NOTHING ELSE. `seconds`, `note`,
    /// `blend`, the entrant's name and every field this type does not model
    /// come back untouched.
    func testAnEditKeepsEverythingButTheKeyframes() throws {
        let entrant = BallChallenge.Entrants.doNothing
        var draft = try entrant.toDraft()
        draft.keys[0].pose[DuckModel.jointOfPolicySlot(3)] = -0.75
        let edited = try entrant.applying(draft: draft)

        XCTAssertEqual(edited.name, entrant.name)
        XCTAssertEqual(edited.seconds, entrant.seconds)
        XCTAssertEqual(edited.note, entrant.note)
        XCTAssertEqual(edited.kind, .move)
        XCTAssertEqual(edited.move?.blend, 1)
        XCTAssertEqual(edited.move?.keyframes[0].pose[3], -0.75)
        XCTAssertEqual(edited.move?.keyframes[1].pose, entrant.move?.keyframes[1].pose)
        XCTAssertNotEqual(edited.encoded(), entrant.encoded())
    }

    /// The mouth is the one joint the format cannot carry, and the caveat only
    /// shows when an edit actually moved it.
    func testTheMouthCaveatOnlyFiresWhenTheMouthMoved() throws {
        let entrant = BallChallenge.Entrants.doNothing
        var draft = try entrant.toDraft()
        XCTAssertFalse(BallChallenge.Entrant.movedMouth(in: draft))
        draft.keys[0].pose[DuckModel.mouthIndex] = 0.4
        XCTAssertTrue(BallChallenge.Entrant.movedMouth(in: draft))
    }

    // MARK: - what a row says

    func testAnEntrantSaysItselfInOneLine() {
        XCTAssertEqual(BallChallenge.Entrants.alphaWalking.subtitle,
                       "policy · 4 s · alpha_walking.onnx · vx 0.5")
        XCTAssertEqual(BallChallenge.Entrants.doNothing.subtitle,
                       "authored move · 5 s · 2 keyframes")
    }

    /// A MOVE HAS NO COMMAND AT ALL, and printing "held at rest" for one would
    /// say it was commanded to stand still rather than that nothing commands
    /// it.
    func testAMoveHasNoCommandRatherThanACommandOfZero() {
        XCTAssertNil(BallChallenge.Entrants.doNothing.commandSaid)
    }
}
