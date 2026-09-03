import XCTest
import DuckKit
@testable import StudioKit

/// The keyframe search: what it may move, what it counts, and what it refuses.
final class MoveSearchTests: XCTestCase {

    // MARK: - helpers

    func move(_ file: String) throws -> StairsChallenge.Move {
        try StairsChallenge.move(named: file)
    }

    /// Every bundled intent with six keyframes — the shape the vaults share.
    func sixKeyframeMoves() throws -> [(file: String, move: StairsChallenge.Move)] {
        try StairsChallenge.bundledFiles.compactMap { file in
            let move = try StairsChallenge.move(named: file)
            return move.keyframes.count == 6 ? (file, move) : nil
        }
    }

    func spec(_ file: String, _ handles: [MoveSearch.Handle]) -> MoveSearch.Spec {
        MoveSearch.Spec.everythingHeld(file, rise: 0.060).with(handles: handles)
    }

    /// The four leg-and-head groups, on one keyframe. The Mouth is not offered.
    func groupHandles(_ move: StairsChallenge.Move, keyframe: Int,
                      degrees: Double = 5) -> [MoveSearch.Handle] {
        let keys = MoveSearch.draft(of: move).keys
        guard keys.indices.contains(keyframe) else { return [] }
        return JointGroup.all
            .filter { $0.title != "Mouth" }
            .map { .init(kind: .pose(keyframe: keys[keyframe].id, .group($0.title)),
                         room: degrees) }
    }

    // MARK: - everything starts held

    func testEverySpecStartsWithNothingUnlocked() {
        let spec = MoveSearch.Spec.everythingHeld("best_r3_vault_60mm.json", rise: 0.060)
        XCTAssertTrue(spec.handles.isEmpty)
        let budget = MoveSearch.budget(for: spec)
        XCTAssertEqual(budget.dimensions, 0)
        XCTAssertFalse(budget.isResolvable)
        XCTAssertTrue(MoveSearch.everythingIsHeldToStart.contains("Everything starts held"))
    }

    // MARK: - the budget

    func testTheRequestCountIsCountedNotEstimated() throws {
        let m = try move("best_r3_vault_60mm.json")
        let three = spec("best_r3_vault_60mm.json", Array(groupHandles(m, keyframe: 2).prefix(3)))
        var counted = three; counted.lambda = 4; counted.generations = 6

        let budget = MoveSearch.budget(for: counted)
        XCTAssertEqual(budget.baselineRequests, 14)
        XCTAssertEqual(budget.swingRequests, 54)
        XCTAssertEqual(budget.searchRequests, 216)
        XCTAssertEqual(budget.checkRequests, 5)
        XCTAssertEqual(budget.totalRequests, 289)

        var one = counted; one.handles = Array(counted.handles.prefix(1))
        XCTAssertEqual(MoveSearch.budget(for: one).totalRequests, 253)
        var two = counted; two.handles = Array(counted.handles.prefix(2))
        XCTAssertEqual(MoveSearch.budget(for: two).totalRequests, 271)

        // The sentence carries the number, so a screen cannot print a
        // different one beside it.
        XCTAssertTrue(budget.described.contains("289"))
    }

    /// ASSERTED AGAINST THE GRID, NOT A LITERAL. The five held-out cells are
    /// the five the round-4 audit added, and if the grid ever grows the check
    /// grows with it.
    func testTheHeldOutCheckIsTheFiveExtendedCells() throws {
        let m = try move("best_r3_vault_60mm.json")
        let budget = MoveSearch.budget(for: spec("best_r3_vault_60mm.json",
                                                 groupHandles(m, keyframe: 0)))
        XCTAssertEqual(budget.checkRequests,
                       StairsChallenge.Grid.count - StairsChallenge.Grid.coreCount)
        XCTAssertEqual(budget.baselineRequests, StairsChallenge.Grid.count)
    }

    func testTheBudgetRefusesMoreDirectionsThanTheChildrenCanResolve() throws {
        let m = try move("best_r3_vault_60mm.json")
        let keys = MoveSearch.draft(of: m).keys
        var five = spec("best_r3_vault_60mm.json",
                        groupHandles(m, keyframe: 1) + [
                            .init(kind: .time(keyframe: keys[1].id), room: 0.1),
                            .init(kind: .time(keyframe: keys[2].id), room: 0.1)])
        five.lambda = 4; five.generations = 6
        let budget = MoveSearch.budget(for: five)
        XCTAssertEqual(budget.dimensions, 5)
        XCTAssertEqual(budget.candidates, 24)
        XCTAssertEqual(budget.resolvable, 4)
        XCTAssertFalse(budget.isResolvable)

        let said = MoveSearch.budgetTooThin(dimensions: 5, resolvable: 4)
        XCTAssertTrue(said.contains("5"))
        XCTAssertTrue(said.contains("4"))
    }

    // MARK: - the clamp, which is the failure PreferenceSearch found the hard way

    /// THE `PreferenceSearch.swift:256-268` FAILURE, ASSERTED RATHER THAN
    /// REMEMBERED. `IntentDraft.exported()` does not clamp, it REFUSES, so a
    /// handle that could walk a joint past its stop is a stepper on a dead end.
    func testAPoseHandleNeverWalksAJointPastItsStop() throws {
        var rng = DuckTuner.Seeded(seed: 11)
        var checked = 0
        for (file, m) in try sixKeyframeMoves() {
            let keys = MoveSearch.draft(of: m).keys
            for index in keys.indices {
                let handles = groupHandles(m, keyframe: index, degrees: 20)
                let s = spec(file, handles)
                for _ in 0..<200 {
                    // Pushed to the ends of its room on purpose: a random walk
                    // inside the box is not the case that broke.
                    var offsets: [String: Double] = [:]
                    for handle in handles {
                        offsets[handle.id] = rng.uniform() < 0.5 ? -handle.room : handle.room
                    }
                    let edited = try MoveSearch.apply(MoveSearch.Point(offsets: offsets),
                                                      to: m, spec: s)
                    for frame in edited.keyframes {
                        for slot in frame.pose.indices {
                            let joint = DuckModel.jointOfPolicySlot(slot)
                            let travel = DuckModel.jointRanges[joint]
                            XCTAssertGreaterThanOrEqual(frame.pose[slot], travel.lower - 1e-9,
                                                        "\(file) slot \(slot)")
                            XCTAssertLessThanOrEqual(frame.pose[slot], travel.upper + 1e-9,
                                                     "\(file) slot \(slot)")
                        }
                    }
                    _ = try MoveSearch.draft(of: edited).exported()
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 1000, "the sweep has to have actually run")
    }

    func testHeadroomReportsWhatTheClampWillActuallyDeliver() throws {
        let m = try move("best_r3_vault_60mm.json")
        let keys = MoveSearch.draft(of: m).keys
        // The deepest leg keyframe: the one whose left leg sits furthest from
        // its home pose.
        let deepest = keys.indices.max { a, b in
            legDepth(keys[a].pose) < legDepth(keys[b].pose)
        }!
        let handle = MoveSearch.Handle(
            kind: .pose(keyframe: keys[deepest].id, .group("Left leg")), room: 20)
        let room = try XCTUnwrap(MoveSearch.headroom(handle, in: m))
        XCTAssertEqual(room.asked, 20)
        XCTAssertLessThan(room.delivered, room.asked)
        XCTAssertEqual(room.bindingJoint, "left_hip_roll")
        XCTAssertEqual(room.up, 30, accuracy: 0.01)
        XCTAssertEqual(room.down, 9.82, accuracy: 0.01)
        XCTAssertEqual(room.delivered, 9.82, accuracy: 0.01)
        XCTAssertTrue(room.sentence.contains("the search gets 20.0° one way and 9.8° the other"),
                      room.sentence)
        XCTAssertFalse(room.sentence.contains("gets 30.0° one way"), room.sentence)
        XCTAssertTrue(room.sentence.contains("You asked ±20°"))
        XCTAssertTrue(room.sentence.contains(
            MotionTweak.plainName(try XCTUnwrap(room.bindingJoint))))

        // AND THIS FILE HAS NO SECOND TIGHT JOINT, WHICH IS A MEASUREMENT AND
        // NOT AN OVERSIGHT. `left_hip_roll` at 9.82° is the tightest joint in
        // the whole of this move's pose, so nothing is tighter still. The plan
        // asserted `othersTighter > 0` here; recomputed, it is 0 on every
        // keyframe and every group of `best_r3_vault_60mm`, so the count is
        // asserted where the corpus actually has one.
        XCTAssertEqual(room.othersTighter, 0)
    }

    func testHeadroomCountsTheOtherJointsTheSameAskWouldAlsoClamp() throws {
        let m = try move("best_r4_famB_beat1_90mm.json")
        let keys = MoveSearch.draft(of: m).keys
        let handle = MoveSearch.Handle(
            kind: .pose(keyframe: keys[1].id, .group("Left leg")), room: 20)
        let room = try XCTUnwrap(MoveSearch.headroom(handle, in: m))
        XCTAssertEqual(room.bindingJoint, "left_knee")
        XCTAssertGreaterThan(room.othersTighter, 0)
        XCTAssertTrue(room.sentence.contains("also inside what you asked for"))
    }

    func legDepth(_ pose: [Double]) -> Double {
        JointGroup.all.first { $0.title == "Left leg" }!.joints
            .map { abs(pose[$0] - DuckModel.homePose[$0]) }.reduce(0, +)
    }

    func testHeadroomIsNilWhereTheIdeaDoesNotApply() throws {
        let m = try move("best_r3_vault_60mm.json")
        let keys = MoveSearch.draft(of: m).keys
        XCTAssertNil(MoveSearch.headroom(.init(kind: .time(keyframe: keys[0].id), room: 0.1),
                                         in: m))
        XCTAssertNil(MoveSearch.headroom(.init(kind: .shape("blend"), room: 0.2), in: m))
    }

    // MARK: - the mouth

    func testTheMouthCannotBeUnlocked() throws {
        let m = try move("best_r3_vault_60mm.json")
        let keys = MoveSearch.draft(of: m).keys
        let handle = MoveSearch.Handle(
            kind: .pose(keyframe: keys[0].id, .joint(DuckModel.mouthIndex)), room: 5)
        XCTAssertThrowsError(try MoveSearch.apply(MoveSearch.Point(offsets: [handle.id: 5]),
                                                  to: m,
                                                  spec: spec("best_r3_vault_60mm.json", [handle])))
        { error in
            XCTAssertEqual(error as? MoveSearch.Refusal, .mouthIsNotSearched)
        }
        // And the group spelling of the same thing.
        let group = MoveSearch.Handle(kind: .pose(keyframe: keys[0].id, .group("Mouth")), room: 5)
        XCTAssertThrowsError(try MoveSearch.apply(.unchanged, to: m,
                                                  spec: spec("best_r3_vault_60mm.json", [group])))
    }

    // MARK: - the shape parameters

    func testAShapeHandleIsRefusedOnAFileThatDeclaresNoBounds() throws {
        let plain = try move("best_r3_vault_60mm.json")
        let handle = MoveSearch.Handle(kind: .shape("blend"), room: 0.2)
        XCTAssertThrowsError(try MoveSearch.apply(MoveSearch.Point(offsets: [handle.id: 0.2]),
                                                  to: plain,
                                                  spec: spec("best_r3_vault_60mm.json", [handle])))
        { error in
            XCTAssertEqual(error as? MoveSearch.Refusal, .shapeHasNoDeclaredBounds("blend"))
        }

        let declared = try move("best_r4_famA_60mm.json")
        let bounds = try XCTUnwrap(MoveSearch.declaredBounds(for: "blend", in: declared))
        XCTAssertEqual(bounds.low, 0.8, accuracy: 1e-12)
        XCTAssertEqual(bounds.high, 2.4, accuracy: 1e-12)
        let edited = try MoveSearch.apply(MoveSearch.Point(offsets: [handle.id: -0.2]),
                                          to: declared,
                                          spec: spec("best_r4_famA_60mm.json", [handle]))
        XCTAssertEqual(edited.blend, declared.blend - 0.2, accuracy: 1e-9)
    }

    func testAShapeHandleNeverLeavesTheFilesOwnDeclaredBounds() throws {
        let m = try move("best_r5_servoland_kcore_60mm.json")
        let blend = MoveSearch.Handle(kind: .shape("blend"), room: 5)
        let side = MoveSearch.Handle(kind: .shape("side"), room: 5)
        let s = spec("best_r5_servoland_kcore_60mm.json", [blend, side])
        XCTAssertEqual(try XCTUnwrap(MoveSearch.declaredBounds(for: "blend", in: m)).low, 0.7,
                       accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(MoveSearch.declaredBounds(for: "side", in: m)).high, 0.09,
                       accuracy: 1e-12)

        var rng = DuckTuner.Seeded(seed: 3)
        var point = MoveSearch.Point.unchanged
        for _ in 0..<500 {
            point = MoveSearch.mutate(point, with: s, using: &rng)
            let edited = try MoveSearch.apply(point, to: m, spec: s)
            XCTAssertGreaterThanOrEqual(edited.blend, 0.7)
            XCTAssertLessThanOrEqual(edited.blend, 2.4)
            XCTAssertGreaterThanOrEqual(edited.side, -0.02)
            XCTAssertLessThanOrEqual(edited.side, 0.09)
        }
    }

    /// WHY LANDING-LAW FILES ARE CAVEATED AND NOT EXCLUDED: excluding them
    /// would make the shape controls unreachable on every file.
    func testTheTwoFilesThatDeclareBoundsAlsoCarryALandingLaw() throws {
        var declaring: [String] = [], landing: [String] = []
        for file in StairsChallenge.bundledFiles {
            let m = try StairsChallenge.move(named: file)
            if MoveSearch.shapeKeys.contains(where: {
                MoveSearch.declaredBounds(for: $0, in: m) != nil
            }) { declaring.append(file) }
            if MoveSearch.carriesALandingLaw(m) { landing.append(file) }
        }
        XCTAssertEqual(declaring.sorted(),
                       ["best_r4_famA_60mm.json", "best_r5_servoland_kcore_60mm.json"])
        XCTAssertEqual(landing.sorted(),
                       ["best_r4_famA_60mm.json", "best_r5_servo_60mm.json",
                        "best_r5_servoland_kcore_60mm.json"])
        XCTAssertTrue(Set(declaring).isSubset(of: Set(landing)))
        XCTAssertTrue(MoveSearch.landingLawNotSearched.contains("not searched"))
    }

    // MARK: - what an edit leaves alone

    func testAnUnmovedPointReEncodesTheFileByteForByte() throws {
        for file in StairsChallenge.bundledFiles {
            let m = try StairsChallenge.move(named: file)
            let same = try MoveSearch.apply(.unchanged, to: m,
                                            spec: MoveSearch.Spec.everythingHeld(file,
                                                                                 rise: 0.060))
            XCTAssertEqual(same.encoded(), try StairsChallenge.intentData(named: file), file)
        }
    }

    func testEditingKeyframesLeavesEveryFieldTheFormatCarriesUntouched() throws {
        let file = "best_r5_servoland_kcore_60mm.json"
        let m = try move(file)
        let handles = groupHandles(m, keyframe: 2)
        let s = spec(file, handles)
        let edited = try MoveSearch.apply(
            MoveSearch.Point(offsets: Dictionary(uniqueKeysWithValues:
                handles.map { ($0.id, $0.room) })), to: m, spec: s)

        // Key order, byte for byte, outside `keyframes`.
        XCTAssertEqual(keyOrder(edited.json), keyOrder(m.json))
        for key in ["params", "servo", "bounds", "name", "family", "note", "robust",
                    "blend", "gap", "side", "approach", "isolate", "stepCount"] {
            XCTAssertEqual(edited.json[key], m.json[key], key)
        }
        // And the keyframes DID change, or this asserts nothing.
        XCTAssertNotEqual(edited.json["keyframes"], m.json["keyframes"])
    }

    func keyOrder(_ json: HarnessJSON) -> [String] { (json.members ?? []).map(\.key) }

    // MARK: - timing

    func testTimingHandlesRefuseACollisionRatherThanCreatingOne() throws {
        let file = "best_r3_vault_60mm.json"
        let m = try move(file)
        let keys = MoveSearch.draft(of: m).keys.sorted { $0.time < $1.time }
        let gap = keys[1].time - keys[0].time
        let handle = MoveSearch.Handle(kind: .time(keyframe: keys[0].id), room: gap + 0.05)
        let s = spec(file, [handle])
        // Moved onto its neighbour exactly.
        let point = MoveSearch.Point(offsets: [handle.id: gap])
        XCTAssertThrowsError(try MoveSearch.apply(point, to: m, spec: s)) { error in
            guard case .timesWouldCollide(let time)? = error as? MoveSearch.Refusal else {
                return XCTFail("expected a collision refusal, got \(error)")
            }
            XCTAssertEqual(time, keys[1].time, accuracy: 1e-9)
        }
        // A smaller nudge is fine and actually moves it.
        let nudged = try MoveSearch.apply(MoveSearch.Point(offsets: [handle.id: 0.02]),
                                          to: m, spec: s)
        XCTAssertEqual(nudged.keyframes.map(\.t).min()!, keys[0].time + 0.02, accuracy: 1e-9)
    }

    // MARK: - the run

    func testASeedReproducesTheWholeRun() throws {
        let file = "best_r3_vault_60mm.json"
        let m = try move(file)
        let s = spec(file, groupHandles(m, keyframe: 3))
        func walk() -> [MoveSearch.Point] {
            var rng = DuckTuner.Seeded(seed: 7)
            var point = MoveSearch.Point.unchanged
            return (0..<50).map { _ in
                point = MoveSearch.mutate(point, with: s, using: &rng)
                return point
            }
        }
        XCTAssertEqual(walk(), walk())
    }

    func testAHeldHandleIsUntouchedByEveryCandidate() throws {
        let file = "best_r3_vault_60mm.json"
        let m = try move(file)
        let all = groupHandles(m, keyframe: 3)
        let unlocked = Array(all.prefix(1))
        let held = all[1]                       // never put in the spec
        let s = spec(file, unlocked)

        var rng = DuckTuner.Seeded(seed: 19)
        var point = MoveSearch.Point.unchanged
        let heldJoints = JointGroup.all.first { $0.title == "Right leg" }!.joints
        let before = MoveSearch.draft(of: m).keys[3].pose
        for _ in 0..<200 {
            point = MoveSearch.mutate(point, with: s, using: &rng)
            XCTAssertNil(point.offsets[held.id])
            XCTAssertEqual(Set(point.offsets.keys), Set(unlocked.map(\.id)))
            let edited = try MoveSearch.apply(point, to: m, spec: s)
            let after = MoveSearch.draft(of: edited).keys[3].pose
            for joint in heldJoints {
                // EXACT EQUALITY, never "close enough".
                XCTAssertEqual(after[joint], before[joint])
            }
        }
    }

    func testAProbeMovesOneHandleAndOnlyOne() throws {
        let file = "best_r3_vault_60mm.json"
        let m = try move(file)
        let handles = groupHandles(m, keyframe: 2)
        let s = spec(file, handles)
        for handle in handles {
            for direction in [1.0, -1.0] {
                let point = MoveSearch.probe(s, handle: handle, direction: direction)
                XCTAssertEqual(point.offsets.filter { $0.value != 0 }.count, 1)
                XCTAssertEqual(point.offsets[handle.id], handle.room * direction)
            }
        }
    }

    // MARK: - the swing table

    func testTheSwingTableSplitsOnTheMeasuredSpreadAndNothingElse() throws {
        let m = try move("best_r3_vault_60mm.json")
        let handles = groupHandles(m, keyframe: 1)
        let small = MoveSearch.Swing(handle: handles[0], base: 0, up: 0.05, down: 0)
        let large = MoveSearch.Swing(handle: handles[1], base: 0, up: 1.2, down: 0)
        XCTAssertEqual(small.swing, 0.05, accuracy: 1e-12)
        XCTAssertEqual(large.swing, 1.2, accuracy: 1e-12)

        let ranked = MoveSearch.ranked([small, large], spread: 0.9)
        XCTAssertEqual(ranked.above.map(\.swing), [1.2])
        XCTAssertEqual(ranked.below.map(\.swing), [0.05])
        XCTAssertTrue(MoveSearch.swingsUnderTheSpread(1, spread: 0.9).contains("0.9"))

        // WITH NO SPREAD MEASURED, NOTHING IS RANKED. Not "everything is
        // important"; nothing is comparable.
        let withheld = MoveSearch.ranked([small, large], spread: nil)
        XCTAssertTrue(withheld.above.isEmpty)
        XCTAssertEqual(withheld.below.count, 2)
    }

    func testTheSwingSentenceSaysOnlyOneHandleMoved() throws {
        let m = try move("best_r3_vault_60mm.json")
        let handle = groupHandles(m, keyframe: 1)[0]
        let line = MoveSearch.swingLine(
            MoveSearch.Swing(handle: handle, base: 0.5, up: 0.81, down: 0.4), in: m)
        XCTAssertTrue(line.contains("when this moved"))
        XCTAssertFalse(line.lowercased().contains("gradient"))
        XCTAssertFalse(line.lowercased().contains("most important"))
        XCTAssertTrue(line.contains("0.31"))
    }

    func testAGenerationLineNamesWhatWasThrownAwayAndWhy() {
        let clean = MoveSearch.generationLine(.init(index: 2, best: 0.7412,
                                                    rejectedAsInvalid: 0,
                                                    rejectedAsNeverReachedFlight: 0))
        XCTAssertEqual(clean, "Generation 2: best 0.7412 over the core nine.")
        let thrown = MoveSearch.generationLine(.init(index: 3, best: 0.5,
                                                     rejectedAsInvalid: 1,
                                                     rejectedAsNeverReachedFlight: 2))
        XCTAssertTrue(thrown.contains("1 outside the box"))
        XCTAssertTrue(thrown.contains("2 never reached flight"))
    }

    // MARK: - every sentence

    func testEverySentenceThisScreenShowsIsHere() {
        let sentences: [(String, String)] = [
            ("notTraining", MoveSearch.notTraining),
            ("whatItSearches", MoveSearch.whatItSearches),
            ("everythingIsHeldToStart", MoveSearch.everythingIsHeldToStart),
            ("mouthIsNotSearched", MoveSearch.mouthIsNotSearched),
            ("reachIsNotZeroAtRest", MoveSearch.reachIsNotZeroAtRest),
            ("nothingToImproveYet", MoveSearch.nothingToImproveYet),
            ("howMuchTheConditionsMove", MoveSearch.howMuchTheConditionsMove),
            ("objectiveIsOurs", MoveSearch.objectiveIsOurs),
            ("aScoreHereIsNotALeaderboardRow", MoveSearch.aScoreHereIsNotALeaderboardRow),
            ("noBlendPerTransition", MoveSearch.noBlendPerTransition),
            ("spreadNotMeasuredYet", MoveSearch.spreadNotMeasuredYet),
            ("theOtherBlend", MoveSearch.theOtherBlend),
            ("shapeNeedsDeclaredBounds", MoveSearch.shapeNeedsDeclaredBounds),
            ("landingLawNotSearched", MoveSearch.landingLawNotSearched),
            ("paramsAreNowStale", MoveSearch.paramsAreNowStale),
            ("onlyTheStairs", MoveSearch.onlyTheStairs),
            ("noConditionSpread", MoveSearch.noConditionSpread),
            ("theOtherSearchIsHere", MoveSearch.theOtherSearchIsHere),
            ("invalid", MoveSearch.Rejection.invalid.message),
            ("neverReachedFlight", MoveSearch.Rejection.neverReachedFlight.message),
            ("whatWordsMayNotChange", DuckTuner.whatWordsMayNotChange),
            ("termWeightsAreNotYours", SearchWords.termWeightsAreNotYours),
            ("nothingWasRead", SearchWords.nothingWasRead),
            ("freeNeedsAMoment", SearchWords.freeNeedsAMoment),
        ]
        for (name, text) in sentences {
            XCTAssertFalse(text.isEmpty, name)
            XCTAssertFalse(text.contains("  "), "\(name) has a double space")
            XCTAssertFalse(text.contains("RLHF"), name)
            // "reward model" IS ALLOWED ONLY INSIDE A DENIAL. `notTraining`
            // opens "it is not a reward model", which is the sentence the whole
            // screen exists to say; a ban that could not tell the denial from
            // the claim would delete the correction and keep the confusion.
            // `scripts/check_no_rlhf_in_copy.sh` is scoped the same way.
            if text.lowercased().contains("reward model") {
                XCTAssertTrue(text.lowercased().contains("not a reward model"), name)
            }
            XCTAssertFalse(text.lowercased().contains("gradient descent"), name)
            XCTAssertTrue(text.hasSuffix(".") || text.hasSuffix("\"") || text.hasSuffix("?"), name)
        }
        // The two sentences that carry a number the fixtures produce.
        XCTAssertTrue(MoveSearch.reachIsNotZeroAtRest.contains("0.59"))
        XCTAssertTrue(MoveSearch.reachIsNotZeroAtRest.contains("66 mm"))
        XCTAssertTrue(MoveSearch.howMuchTheConditionsMove.contains("0.91"))
        XCTAssertTrue(MoveSearch.howMuchTheConditionsMove.contains("0.004"))
        // And the two that must not be mistaken for each other.
        XCTAssertTrue(MoveSearch.noBlendPerTransition.contains("smoothstep"))
        XCTAssertTrue(MoveSearch.theOtherBlend.contains("GENERATE"))
    }

    /// The one word that may never appear in product copy. The loop is edit,
    /// score, keep.
    func testTheKitNeverSaysTheWordThisAppRefusesToSay() {
        for text in [MoveSearch.notTraining, MoveSearch.objectiveIsOurs,
                     SearchWords.termWeightsAreNotYours, DuckTuner.whatWordsMayNotChange] {
            XCTAssertFalse(text.contains("RLHF"))
        }
        XCTAssertTrue(MoveSearch.notTraining.contains("not a reward model"))
        XCTAssertTrue(MoveSearch.notTraining.contains("You edit, the bench scores"))
    }

    // MARK: - handles a stored spec named and the move no longer has

    func testAHandleNamingAKeyframeThisMoveNoLongerHasIsRefusedNotReHomed() throws {
        let file = "best_r3_vault_60mm.json"
        let m = try move(file)
        let ghost = MoveSearch.Handle(
            kind: .pose(keyframe: UUID(uuidString: "00000000-0000-4000-8000-000000000000")!,
                        .group("Left leg")), room: 5)
        XCTAssertThrowsError(try MoveSearch.apply(MoveSearch.Point(offsets: [ghost.id: 5]),
                                                  to: m, spec: spec(file, [ghost]))) { error in
            guard case .notThisMove? = error as? MoveSearch.Refusal else {
                return XCTFail("expected notThisMove, got \(error)")
            }
        }
        XCTAssertTrue(MoveSearch.handlesDropped(2).contains("2 saved handles"))
    }

    /// The identities a handle is keyed by do not move between two reads of the
    /// same file, which is the whole reason a saved spec can be reopened.
    func testTheKeyframeIdentitiesAreStableAcrossTwoReadsOfTheSameFile() throws {
        let a = try move("best_r3_vault_60mm.json")
        let b = try move("best_r3_vault_60mm.json")
        XCTAssertEqual(MoveSearch.draft(of: a).keys.map(\.id),
                       MoveSearch.draft(of: b).keys.map(\.id))
        // And they are not shared between two different moves.
        let other = try move("best_r6_ceilvaultC_60mm.json")
        XCTAssertTrue(Set(MoveSearch.draft(of: a).keys.map(\.id))
            .isDisjoint(with: Set(MoveSearch.draft(of: other).keys.map(\.id))))
    }

    /// The two search-size controls are labels, not sentences, and their
    /// ranges are the ones the words path clamps to.
    func testTheSearchSizeControlsAreLabelledAndShareTheWordsRanges() {
        XCTAssertEqual(MoveSearch.generationsSaid, "Generations")
        XCTAssertEqual(MoveSearch.childrenSaid, "Children per generation")
        XCTAssertEqual(MoveSearch.generationsRange, 1...40)
        XCTAssertEqual(MoveSearch.childrenRange, 1...20)
    }
}
