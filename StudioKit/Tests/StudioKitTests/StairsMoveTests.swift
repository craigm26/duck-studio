import XCTest
import DuckKit
@testable import StudioKit

/// The harness intent, and the two conversions that let somebody edit one.
final class StairsMoveTests: XCTestCase {

    func record() throws -> StairsChallenge.Move {
        try StairsChallenge.move(for: StairsChallenge.record)
    }

    // MARK: - reading one

    func testEveryBundledMoveParses() throws {
        for file in StairsChallenge.bundledFiles {
            let move = try StairsChallenge.move(named: file)
            XCTAssertFalse(move.keyframes.isEmpty, file)
            for frame in move.keyframes {
                XCTAssertEqual(frame.pose.count, DuckModel.policyJointCount, file)
            }
        }
    }

    func testTheRecordReadsTheWayTheDatasetDescribesIt() throws {
        let move = try record()
        XCTAssertEqual(move.name, "beak_strut_vault_r6_ceiling_60mm")
        XCTAssertEqual(move.family, "R6 ceiling — beak-strut vault launch")
        XCTAssertEqual(move.keyframes.count, 6)
        XCTAssertEqual(move.blend, 2.1153)
        XCTAssertEqual(move.gap, 0.0194)
        XCTAssertEqual(move.side, 0.0102)
        XCTAssertEqual(move.approach, 0.1653)
        XCTAssertTrue(move.isolate)
        XCTAssertEqual(move.stepCount, 4)
        // The record is a plain launch: no landing law of any kind.
        XCTAssertFalse(move.hasEvent)
        XCTAssertFalse(move.hasServo)
        XCTAssertFalse(move.hasSpawn)
    }

    /// The fields that are INSIDE the identity when a file has them.
    func testTheFamiliesThatCarryALandingLawSaySo() throws {
        XCTAssertTrue(try StairsChallenge.move(named: "best_r4_famA_60mm").hasEvent)
        XCTAssertTrue(try StairsChallenge.move(named: "best_r5_servo_60mm").hasServo)
        XCTAssertTrue(try StairsChallenge.move(named: "r4_ctrl_on_tread_60mm").hasSpawn)
    }

    /// THE HARNESS DEFAULTS `isolate` TO TRUE AND THIS USED TO READ FALSE.
    /// `climb_score.mjs`'s `isoOf` is `intent.isolate !== false`, so a file
    /// that says nothing is scored WITH the step-step isolation on. It was
    /// display-only until `Move.authored` became the first writer to put the
    /// key on the wire; a fresh intent minted with `isolate: false` would be
    /// scored in a different plant from every published row.
    func testAFileThatDoesNotMentionIsolateIsScoredWithItOn() throws {
        // ctrl_do_nothing has no `isolate` and no `stepCount`; the harness
        // defaults them, and so does this.
        let move = try StairsChallenge.move(named: "ctrl_do_nothing")
        XCTAssertTrue(move.isolate)
        XCTAssertEqual(move.stepCount, 4)
        XCTAssertEqual(move.blend, 1)
        XCTAssertEqual(move.gap, 0.05)
    }

    func testAnIntentWithNoKeyframesIsRefused() {
        XCTAssertThrowsError(try StairsChallenge.Move.decode(Data(#"{"name":"x"}"#.utf8))) {
            XCTAssertEqual($0 as? StairsChallenge.Move.Refusal, .noKeyframes)
        }
    }

    func testAPoseOfTheWrongWidthIsRefusedRatherThanPadded() {
        let source = Data(#"{"keyframes":[{"t":1,"pose":[0,0,0]}]}"#.utf8)
        XCTAssertThrowsError(try StairsChallenge.Move.decode(source)) {
            XCTAssertEqual($0 as? StairsChallenge.Move.Refusal, .wrongPoseWidth(3))
        }
    }

    func testAnArrayIsNotAnIntent() {
        XCTAssertThrowsError(try StairsChallenge.Move.decode(Data("[1,2]".utf8))) {
            XCTAssertEqual($0 as? StairsChallenge.Move.Refusal, .notAnObject)
        }
    }

    // MARK: - the round trip that keeps a hash meaningful

    /// EVERY BUNDLED MOVE RE-ENCODES TO ITS OWN BYTES. This is the claim the
    /// leaderboard rests on: the file this app sends a bench is the file the
    /// dataset published.
    func testEveryBundledMoveReEncodesByteForByte() throws {
        for file in StairsChallenge.bundledFiles {
            let original = try StairsChallenge.intentData(named: file)
            XCTAssertEqual(try StairsChallenge.Move.decode(original).encoded(), original, file)
        }
    }

    /// THE FIELDS THIS TYPE HAS NO OPINION ABOUT COME BACK ANYWAY — including
    /// the ones `intentHash` folds in.
    func testUnknownFieldsSurviveVerbatim() throws {
        let move = try StairsChallenge.move(named: "best_r5_servo_60mm")
        let again = try StairsChallenge.Move.decode(move.encoded())
        XCTAssertEqual(again.json["servo"], move.json["servo"])
        XCTAssertEqual(again.json["robust"], move.json["robust"])
        XCTAssertEqual(again.json["params"], move.json["params"])
        XCTAssertEqual(again.json.members?.map(\.key), move.json.members?.map(\.key))
    }

    // MARK: - into the editor

    /// FOURTEEN JOINTS BECOME FIFTEEN THROUGH `jointOfPolicySlot`, AND NOTHING
    /// ELSE CHANGES. Every harness value lands on the joint the policy would
    /// have driven, the mouth arrives at its home angle, and the times are the
    /// keyframe times.
    func testADraftCarriesEveryPoseValueOntoTheRightJoint() throws {
        let move = try record()
        let draft = move.toDraft(hash: StairsChallenge.record.hash, rank: 1)
        XCTAssertEqual(draft.keys.count, move.keyframes.count)
        for (key, frame) in zip(draft.keys, move.keyframes) {
            XCTAssertEqual(key.time, frame.t)
            XCTAssertEqual(key.pose.count, DuckModel.jointCount)
            for slot in 0..<DuckModel.policyJointCount {
                XCTAssertEqual(key.pose[DuckModel.jointOfPolicySlot(slot)], frame.pose[slot],
                               "slot \(slot) at t \(frame.t)")
            }
            XCTAssertEqual(key.pose[DuckModel.mouthIndex],
                           DuckModel.homePose[DuckModel.mouthIndex])
        }
    }

    /// The do-nothing control is the home pose held still, which is what makes
    /// it a control — so its draft has to be the home pose, all fifteen wide.
    func testTheDoNothingControlOpensAsTheHomePose() throws {
        let draft = try StairsChallenge.move(named: "ctrl_do_nothing").toDraft()
        for key in draft.keys {
            XCTAssertEqual(key.pose, DuckModel.homePose)
        }
    }

    /// A draft lifted out of the challenge SAYS SO. The moment it is in the
    /// Studio's list it looks like something the person wrote.
    func testTheProvenanceNamesTheChallengeTheRankAndTheHash() throws {
        let draft = try StairsChallenge.draft(for: StairsChallenge.record)
        XCTAssertEqual(draft.provenance,
            "From the Microduck Stairs Challenge, rank 1, move a56d459fb649. R6 ceiling — "
          + "beak-strut vault launch. Simulation only — nothing in the challenge has been run "
          + "on hardware.")
        XCTAssertEqual(draft.name, "beak_strut_vault_r6_ceiling_60mm")
    }

    func testAnUnrankedRowsProvenanceDoesNotInventARank() throws {
        let row = try XCTUnwrap(StairsChallenge.row(file: "best_r3_vault_70mm.json"))
        let draft = try StairsChallenge.draft(for: row)
        XCTAssertFalse(draft.provenance.contains("rank"))
        XCTAssertTrue(draft.provenance.contains("move 4b9110c448ec"))
    }

    /// The draft the challenge hands over has to be one the editor will
    /// actually play — otherwise "Open in the editor" opens a refusal.
    func testEveryChallengeDraftIsPlayableInTheEditor() throws {
        for row in StairsChallenge.leaderboard {
            let draft = try StairsChallenge.draft(for: row)
            XCTAssertTrue(draft.isPlayable,
                          "\(row.file): \(draft.problems.map(\.text).joined(separator: " | "))")
        }
    }

    // MARK: - back out of the editor

    /// AN UNEDITED ROUND TRIP IS THE SAME BYTES. Open the record in the
    /// editor, change nothing, put it back: the same file, so the same hash,
    /// so the same row on the leaderboard.
    func testOpeningAndClosingWithoutEditingGivesTheSameBytes() throws {
        let move = try record()
        let again = try move.applying(draft: move.toDraft())
        XCTAssertEqual(again.encoded(), try StairsChallenge.intentData(
            named: StairsChallenge.record.file))
    }

    func testEveryBundledMoveSurvivesTheEditorRoundTripByteForByte() throws {
        for file in StairsChallenge.bundledFiles {
            let move = try StairsChallenge.move(named: file)
            XCTAssertEqual(try move.applying(draft: move.toDraft()).encoded(),
                           try StairsChallenge.intentData(named: file), file)
        }
    }

    /// An edit reaches the file, and everything that is not a keyframe stays
    /// exactly where it was — including the fields the identity folds in.
    func testAnEditReachesTheFileAndNothingElseMoves() throws {
        let move = try StairsChallenge.move(named: "best_r4_famA_60mm")
        var draft = move.toDraft()
        draft.keys[1].pose[DuckModel.jointOfPolicySlot(4)] = 0.5

        let edited = try move.applying(draft: draft)
        XCTAssertEqual(edited.keyframes[1].pose[4], 0.5)
        XCTAssertEqual(edited.blend, move.blend)
        XCTAssertEqual(edited.gap, move.gap)
        XCTAssertEqual(edited.side, move.side)
        XCTAssertEqual(edited.approach, move.approach)
        XCTAssertEqual(edited.isolate, move.isolate)
        XCTAssertEqual(edited.stepCount, move.stepCount)
        XCTAssertEqual(edited.json["event"], move.json["event"])
        XCTAssertEqual(edited.json["bounds"], move.json["bounds"])
        XCTAssertEqual(edited.json.members?.map(\.key), move.json.members?.map(\.key))
        // Every other keyframe is untouched.
        XCTAssertEqual(edited.keyframes[0].pose, move.keyframes[0].pose)
    }

    /// Keyframes go back in time order, because a track out of order is a
    /// different move and the editor lets somebody drag one past another.
    func testKeyframesGoBackInTimeOrder() throws {
        let move = try record()
        var draft = move.toDraft()
        draft.keys.swapAt(0, 5)
        let times = try move.applying(draft: draft).keyframes.map(\.t)
        XCTAssertEqual(times, times.sorted())
    }

    /// The one thing the format cannot carry, said only when it was used.
    func testTheMouthCaveatIsTrueOnlyWhenTheMouthActuallyMoved() throws {
        let move = try record()
        var draft = move.toDraft()
        XCTAssertFalse(StairsChallenge.Move.movedMouth(in: draft))
        draft.keys[0].pose[DuckModel.mouthIndex] = DuckModel.mouthOpen
        XCTAssertTrue(StairsChallenge.Move.movedMouth(in: draft))
        // And it really is dropped, rather than pushed into a leg.
        let edited = try move.applying(draft: draft)
        XCTAssertEqual(edited.keyframes[0].pose.count, DuckModel.policyJointCount)
        XCTAssertEqual(edited.keyframes[0].pose, move.keyframes[0].pose)
    }

    func testTheMouthNoteSaysWhyItIsDropped() {
        XCTAssertEqual(StairsChallenge.mouthDroppedNote,
            "The mouth moves in this draft and the challenge format has no room for it: a "
          + "harness pose is the 14 joints a policy commands, and the mouth is the one they all "
          + "skip. Everything else goes across unchanged.")
    }

    /// A placed spawn comes through as the floor point the harness wrote,
    /// and a move without one, or with a malformed one, has none.
    func testASpawnIsReadAsAFloorPoint() throws {
        let placed = try StairsChallenge.Move(json: HarnessJSON.parse(Data(
            """
            {"name":"placed","keyframes":[{"t":0,"pose":[0,0,0,0,0,0,0,0,0,0,0,0,0,0]}],
             "spawn":{"x":0.212,"y":-0.004,"z":0.180}}
            """.utf8)))
        let spawn = try XCTUnwrap(placed.spawn)
        XCTAssertEqual(spawn.x, 0.212)
        XCTAssertEqual(spawn.y, -0.004)
        let plain = try StairsChallenge.Move(json: HarnessJSON.parse(Data(
            """
            {"name":"plain","keyframes":[{"t":0,"pose":[0,0,0,0,0,0,0,0,0,0,0,0,0,0]}]}
            """.utf8)))
        XCTAssertNil(plain.spawn)
        let broken = try StairsChallenge.Move(json: HarnessJSON.parse(Data(
            """
            {"name":"broken","keyframes":[{"t":0,"pose":[0,0,0,0,0,0,0,0,0,0,0,0,0,0]}],
             "spawn":"tread"}
            """.utf8)))
        XCTAssertNil(broken.spawn)
    }

    // MARK: - a draft with no published file behind it

    private func scoredRoom() throws -> DuckScene.ChallengeRoom {
        try XCTUnwrap(RoomFixture.scene().challengeRoom)
    }

    func testADraftWithNoSourceMoveBecomesAScorableIntent() throws {
        let draft = RoomFixture.draft(named: "lever_up")
        let move = try StairsChallenge.Move.authored(draft: draft, room: try scoredRoom())
        let back = try StairsChallenge.Move.decode(move.encoded())
        XCTAssertEqual(back.name, "lever_up")
        XCTAssertEqual(back.blend, 1)
        XCTAssertTrue(back.isolate)
        XCTAssertEqual(back.stepCount, 4)
        XCTAssertEqual(back.gap, 0, accuracy: 1e-12)
        XCTAssertEqual(back.side, 0, accuracy: 1e-12)
        XCTAssertEqual(back.keyframes.count, draft.benchTrack.count)
        for (frame, key) in zip(back.keyframes, draft.benchTrack) {
            XCTAssertEqual(frame.pose.count, DuckModel.policyJointCount)
            XCTAssertEqual(frame.t, key.at, accuracy: 1e-12)
            for (a, b) in zip(frame.pose, key.pose) {
                XCTAssertEqual(a, b, accuracy: 1e-12)
            }
        }
    }

    /// A FRESH INTENT IS NEVER PASSED OFF AS A PUBLISHED ONE.
    func testAFreshIntentIsNeverPassedOffAsAPublishedOne() throws {
        let move = try StairsChallenge.Move.authored(draft: RoomFixture.draft(),
                                                     room: try scoredRoom())
        XCTAssertNil(move.json["family"])
        XCTAssertNil(move.json["hash"])
        XCTAssertNil(move.json["rank"])
        XCTAssertEqual(move.json["authoredIn"]?.stringValue, "Microduck Studio")
        XCTAssertEqual(move.json.members?.map(\.key),
                       ["name", "authoredIn", "blend", "gap", "side", "approach",
                        "isolate", "stepCount", "keyframes"])
    }

    /// A ROOM THAT PLACED ITS SPAWN CARRIES IT, because the harness ignores
    /// gap and side for a move that has one.
    func testAPlacedSpawnRoomMintsAnIntentThatCarriesTheSpawn() throws {
        let scene = RoomFixture.scene(spawn: (x: 0.25, y: 1.3050000000000002))
        let room = try XCTUnwrap(scene.challengeRoom)
        let move = try StairsChallenge.Move.authored(draft: RoomFixture.draft(), room: room)
        XCTAssertEqual(move.json.members?.map(\.key),
                       ["name", "authoredIn", "blend", "gap", "side", "approach",
                        "isolate", "stepCount", "spawn", "keyframes"])
        XCTAssertEqual(move.spawn?.x ?? 0, 0.25, accuracy: 1e-9)
        // THE HEIGHT IS THE TREAD'S, NOT A LITERAL. x 0.25 is over the first
        // block (0.12 to 0.46) of a 60 mm flight, so the duck is put down at
        // the harness's drop above that tread, as the published placed-spawn
        // files are (0.18 at 60 mm). A fixed 0.120 here would spawn it inside
        // the block.
        XCTAssertEqual(try XCTUnwrap(move.json["spawn"]?["z"]?.doubleValue),
                       0.06 + DuckWorld.spawnHeight, accuracy: 1e-9)
    }

    /// A SOURCE FILE IS ALWAYS PREFERRED TO A FRESH ONE: `applying(draft:)`
    /// keeps `event`, `servo`, `bounds` and `params`, every one of which the
    /// leaderboard hash folds in.
    func testASourceMoveIsAlwaysPreferredToAFreshOne() throws {
        let source = try StairsChallenge.move(named: "best_r4_famA_60mm")
        let scene = RoomFixture.scene()
        var draft = source.toDraft()
        draft.sceneID = scene.id
        draft.challengeIntent = source.encoded()

        guard case .climb(_, _, let intent, _) = BenchRoute.of(draft: draft, scene: scene,
                                                               blend: source.blend) else {
            return XCTFail("a scored room with a source file still goes to /climb")
        }
        let sent = try StairsChallenge.Move.decode(intent)
        XCTAssertTrue(sent.hasEvent, "the landing law survived")
        for member in source.json.members ?? [] where member.key != "keyframes" {
            XCTAssertEqual(sent.json[member.key], member.value,
                           "\(member.key) is the source file's, byte for byte")
        }
    }

}
