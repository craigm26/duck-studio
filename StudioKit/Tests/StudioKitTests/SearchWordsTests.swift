import XCTest
import DuckKit
@testable import StudioKit

/// Words that change a search, on both of the screens that run one.
final class SearchWordsTests: XCTestCase {

    let file = "best_r3_vault_60mm.json"

    func move() throws -> StairsChallenge.Move { try StairsChallenge.move(named: file) }

    func spec(_ handles: [MoveSearch.Handle] = []) -> MoveSearch.Spec {
        MoveSearch.Spec.everythingHeld(file, rise: 0.060).with(handles: handles)
    }

    func handle(_ move: StairsChallenge.Move, keyframe: Int, joint: String,
                degrees: Double = 5) throws -> MoveSearch.Handle {
        let keys = MoveSearch.draft(of: move).keys
        let index = try XCTUnwrap(DuckModel.jointIndex(of: joint))
        return .init(kind: .pose(keyframe: keys[keyframe].id, .joint(index)), room: degrees)
    }

    func reading(_ edits: [SearchWords.Edit]) -> SearchWords.Reading {
        SearchWords.Reading(summary: "a test", edits: edits)
    }

    // MARK: - holding

    func testHoldingAJointEverywhereRemovesEveryHandleThatTouchesIt() throws {
        let m = try move()
        let left = try handle(m, keyframe: 1, joint: "left_hip_pitch")
        let right = try handle(m, keyframe: 3, joint: "right_hip_pitch")
        let knee = try handle(m, keyframe: 1, joint: "left_knee")

        let outcome = try SearchWords.outcome(reading([.hold(word: "hips", at: nil)]),
                                              applyingTo: spec([left, right, knee]), move: m)
        XCTAssertEqual(outcome.spec.handles.map(\.id), [knee.id])
        XCTAssertEqual(outcome.notes.count, 1)
        XCTAssertTrue(outcome.notes[0].contains("hips"))
        XCTAssertTrue(outcome.notes[0].contains("2 handles removed"))
        XCTAssertTrue(outcome.refusals.isEmpty)
    }

    /// WITHOUT THE ECHO A LOCK LANDS ON THE WRONG KEYFRAME FOR A WHOLE RUN AND
    /// NOBODY SEES IT. The note names the keyframe by its index AND its time.
    func testAStatedMomentResolvesToAKeyframeAndTheNoteEchoesItsIndexAndTime() throws {
        let m = try move()
        let keys = MoveSearch.draft(of: m).keys.sorted { $0.time < $1.time }
        XCTAssertEqual(keys[1].time, 0.546, accuracy: 1e-9)

        let left = try handle(m, keyframe: 1, joint: "left_hip_pitch")
        let elsewhere = try handle(m, keyframe: 3, joint: "left_hip_pitch")
        let outcome = try SearchWords.outcome(reading([.hold(word: "hips", at: 0.50)]),
                                              applyingTo: spec([left, elsewhere]), move: m)
        XCTAssertTrue(outcome.notes[0].contains("keyframe 2"), outcome.notes[0])
        XCTAssertTrue(outcome.notes[0].contains("0.55 s"), outcome.notes[0])
        // ONLY the keyframe named: the other hip handle is untouched.
        XCTAssertEqual(outcome.spec.handles.map(\.id), [elsewhere.id])
    }

    func testAMomentNoKeyframeIsNearIsRefusedRatherThanSnapped() throws {
        let m = try move()
        let before = spec([try handle(m, keyframe: 0, joint: "left_knee")])
        XCTAssertThrowsError(try SearchWords.outcome(reading([.hold(word: "hips", at: 3.9)]),
                                                     applyingTo: before, move: m)) { error in
            XCTAssertEqual(error as? SearchWords.Failure, .noKeyframeNear(3.9))
            XCTAssertTrue((error as! SearchWords.Failure).message.hasSuffix("Nothing was changed."))
        }
    }

    // MARK: - freeing

    func testFreeingAPartAddsAHandlePerJointAtTheKeyframeItNames() throws {
        let m = try move()
        let outcome = try SearchWords.outcome(
            reading([.free(word: "knees", at: 0.55, degrees: 7)]),
            applyingTo: spec(), move: m)
        XCTAssertEqual(outcome.spec.handles.count, 2)
        XCTAssertTrue(outcome.spec.handles.allSatisfy { $0.room == 7 })
        XCTAssertTrue(outcome.notes[0].contains("keyframe 2"))
        XCTAssertTrue(outcome.notes[0].contains("±7°"))
    }

    func testFreeingWithNoMomentIsRefusedByNameRatherThanSpreadOverEveryKeyframe() throws {
        let m = try move()
        let outcome = try SearchWords.outcome(
            reading([.free(word: "knees", at: nil, degrees: 7)]),
            applyingTo: spec(), move: m)
        XCTAssertTrue(outcome.notes.isEmpty)
        XCTAssertEqual(outcome.refusals, [SearchWords.freeNeedsAMoment])
        XCTAssertEqual(outcome.spec, spec())
    }

    func testAnInventedJointGetsARefusalWithTheNearestRealName() throws {
        let m = try move()
        // Alone, the whole sentence failed, so it throws and says so.
        XCTAssertThrowsError(try SearchWords.outcome(
            reading([.free(word: "wing", at: 0.55, degrees: 5)]),
            applyingTo: spec(), move: m)) { error in
            let failure = error as? SearchWords.Failure
            XCTAssertNotNil(failure)
            XCTAssertTrue(failure!.message.contains("\"wing\""))
            let offered = MotionProposal.jointVocabulary.map(\.word)
            XCTAssertTrue(offered.contains { failure!.message.contains($0) },
                          failure!.message)
        }
        // Beside an edit that landed, it is a skipped instruction and named.
        let outcome = try SearchWords.outcome(
            reading([.generations(9), .free(word: "wing", at: 0.55, degrees: 5)]),
            applyingTo: spec(), move: m)
        XCTAssertEqual(outcome.notes.count, 1)
        XCTAssertEqual(outcome.refusals.count, 1)
        XCTAssertTrue(outcome.refusals[0].contains("\"wing\""))
        XCTAssertTrue(outcome.refusals[0].hasSuffix("That instruction was skipped."))
    }

    func testTheBeakIsRefusedWithTheReasonTheBenchCannotSeeIt() throws {
        let m = try move()
        let outcome = try SearchWords.outcome(
            reading([.free(word: "beak", at: 0.55, degrees: 5)]),
            applyingTo: spec(), move: m)
        XCTAssertEqual(outcome.refusals, [MoveSearch.mouthIsNotSearched])
        XCTAssertTrue(outcome.notes.isEmpty)
        XCTAssertEqual(outcome.spec, spec())
    }

    // MARK: - what words may not change

    func testATermWeightIsRefusedByNameAndNothingIsSet() throws {
        let m = try move()
        let read = try SearchWords.read(fromJSON:
            #"{"summary":"weigh it","edits":[{"term":"upright","weight":3}]}"#)
        XCTAssertEqual(read.edits, [.termWeight(term: "upright", weight: 3)])

        let before = spec()
        let outcome = try SearchWords.outcome(read, applyingTo: before, move: m)
        XCTAssertEqual(outcome.refusals.count, 1)
        XCTAssertTrue(outcome.refusals[0].hasPrefix(SearchWords.termWeightsAreNotYours))
        XCTAssertTrue(outcome.refusals[0].contains("upright"))
        XCTAssertTrue(outcome.notes.isEmpty)
        XCTAssertEqual(outcome.spec, before)
    }

    func testAPartialSentenceKeepsWhatLandedAndNamesWhatDidNot() throws {
        let m = try move()
        let outcome = try SearchWords.outcome(
            reading([.free(word: "knees", at: 0.55, degrees: 5),
                     .hold(word: "hips", at: 3.9)]),
            applyingTo: spec(), move: m)
        XCTAssertEqual(outcome.notes.count, 1)
        XCTAssertEqual(outcome.refusals.count, 1)
        XCTAssertEqual(outcome.spec.handles.count, 2)
    }

    func testNothingUnderstoodThrowsRatherThanReturningAnEmptySeal() {
        XCTAssertThrowsError(try SearchWords.read(fromJSON: #"{"edits":[]}"#)) { error in
            XCTAssertEqual(error as? SearchWords.Failure, .nothingUnderstood)
            XCTAssertTrue((error as! SearchWords.Failure).message
                .hasSuffix("Nothing was changed."))
        }
        XCTAssertThrowsError(try SearchWords.read(fromJSON: "not json at all"))
        XCTAssertTrue(SearchWords.nothingWasRead.contains("hold the hips in the second pose"))
    }

    func testTheReaderTakesTheShapeTheInstructionsAskFor() throws {
        let read = try SearchWords.read(fromJSON: """
            {"summary":"held the hips","edits":[{"hold":"hips","at":0.42},\
            {"free":"left leg","at":0.42,"degrees":5},{"at":0.42,"time":0.1},\
            {"generations":6}]}
            """)
        XCTAssertEqual(read.summary, "held the hips")
        XCTAssertEqual(read.edits, [
            .hold(word: "hips", at: 0.42),
            .free(word: "left leg", at: 0.42, degrees: 5),
            .time(at: 0.42, seconds: 0.1),
            .generations(6),
        ])
    }

    // MARK: - the same edits on the OTHER search

    func testTheScheduleApplierRefusesEditsItHasNoSeatForRatherThanIgnoringThem() {
        let outcome = DuckTuner.Schedule.onAPhone.outcome(applying: [
            .shape(key: "blend", span: 0.2),
            .generations(20),
        ])
        XCTAssertEqual(outcome.schedule.generations, 20)
        XCTAssertEqual(outcome.notes, ["20 generations."])
        XCTAssertEqual(outcome.refusals.count, 1)
        XCTAssertTrue(outcome.refusals[0].contains("blend"))
        XCTAssertTrue(outcome.refusals[0].contains("keyframe search"))
    }

    func testHoldingTheKneesOnTheTunerMovesThemOutOfSearchedSlots() throws {
        let before = DuckTuner.Schedule.onAPhone
        let leftKnee = try XCTUnwrap(DuckModel.jointIndex(of: "left_knee"))
        let rightKnee = try XCTUnwrap(DuckModel.jointIndex(of: "right_knee"))
        let leftSlot = leftKnee < DuckModel.mouthIndex ? leftKnee : leftKnee - 1
        let rightSlot = rightKnee < DuckModel.mouthIndex ? rightKnee : rightKnee - 1
        XCTAssertTrue(before.searchedSlots.contains(leftSlot))
        XCTAssertTrue(before.searchedSlots.contains(rightSlot))

        let outcome = before.outcome(applying: [.hold(word: "knees", at: nil)])
        XCTAssertFalse(outcome.schedule.searchedSlots.contains(leftSlot))
        XCTAssertFalse(outcome.schedule.searchedSlots.contains(rightSlot))
        XCTAssertEqual(outcome.schedule.searchedSlots.count, before.searchedSlots.count - 2)
        XCTAssertTrue(outcome.schedule.heldSlots.contains(leftSlot))
        XCTAssertTrue(outcome.schedule.heldSlots.contains(rightSlot))
        XCTAssertEqual(outcome.schedule.heldSlots.count,
                       DuckModel.policyJointCount - outcome.schedule.searchedSlots.count)

        // THE LINE REDRAWS FROM THE EDITED SCHEDULE, so the sentence and the
        // numbers cannot disagree.
        XCTAssertNotEqual(outcome.schedule.described, before.described)
        XCTAssertTrue(outcome.schedule.described
            .contains("\(outcome.schedule.searchedSlots.count) leg gains"))
    }

    func testAMomentHasNoSeatOnTheTunerAndIsRefusedRatherThanAppliedEverywhere() {
        let outcome = DuckTuner.Schedule.onAPhone
            .outcome(applying: [.hold(word: "knees", at: 0.42)])
        XCTAssertEqual(outcome.schedule, DuckTuner.Schedule.onAPhone)
        XCTAssertTrue(outcome.notes.isEmpty)
        XCTAssertEqual(outcome.refusals.count, 1)
    }

    func testATermWeightIsRefusedOnTheTunerToo() {
        let outcome = DuckTuner.Schedule.onAPhone
            .outcome(applying: [.termWeight(term: "lin_vel", weight: 4)])
        XCTAssertEqual(outcome.schedule, DuckTuner.Schedule.onAPhone)
        XCTAssertTrue(outcome.refusals[0].hasPrefix(SearchWords.termWeightsAreNotYours))
        XCTAssertTrue(DuckTuner.whatWordsMayNotChange.contains("read, never typed"))
    }

    // MARK: - the instructions

    func testTheInstructionsOfferOnlyWordsTheResolverAccepts() throws {
        let m = try move()
        let text = SearchWords.instructions(for: m, spec: spec())
        for word in MotionProposal.offeredWords {
            XCTAssertTrue(text.contains(word), "\(word) is offered and not in the instructions")
            XCTAssertNotNil(MotionTweak.targets(for: word),
                            "\(word) is offered and the resolver does not take it")
        }
        XCTAssertTrue(text.contains("You may NOT change what the score is."))
        XCTAssertTrue(text.contains("There is no reward weight here and no term to weigh."))
    }

    func testTheGroundingShowsTheKeyframeTableTheEditorShows() throws {
        let m = try move()
        let text = SearchWords.instructions(for: m, spec: spec())
        XCTAssertTrue(text.contains(MotionTweak.describe(m.toDraft())))
        XCTAssertTrue(text.contains(MotionProposal.grounding()))
    }

    func testTheInstructionsSayWhichShapeFieldsThisFileActuallyDeclares() throws {
        let plain = SearchWords.instructions(for: try move(), spec: spec())
        XCTAssertTrue(plain.contains("declares no searchable shape parameters"))
        let declared = SearchWords.instructions(
            for: try StairsChallenge.move(named: "best_r5_servoland_kcore_60mm.json"),
            spec: MoveSearch.Spec.everythingHeld("best_r5_servoland_kcore_60mm.json",
                                                 rise: 0.060))
        XCTAssertTrue(declared.contains("declares search bounds for: blend, side"))
    }

    /// THE POLICY SEARCH'S INSTRUCTIONS SAY WHAT IT DOES NOT HAVE. A model
    /// asked for a moment or a shape on this host would be refused afterwards,
    /// which is a round trip spent on a refusal the prompt could have avoided.
    func testTheTunersInstructionsSayItHasNoKeyframesAndNoScoreToChange() {
        let text = DuckTuner.wordsInstructions(for: .onAPhone)
        XCTAssertTrue(text.contains(DuckTuner.Schedule.onAPhone.described))
        XCTAssertTrue(text.contains(MotionProposal.grounding()))
        XCTAssertTrue(text.contains("NO keyframes here and no moments"))
        XCTAssertTrue(text.contains("You may NOT change what the score is."))
        // THE FOUR HEAD SLOTS ARE HELD BEFORE ANYBODY SAYS ANYTHING — the
        // schedule ships that way and `headIsNotSearched` says why — so the
        // opening state names them rather than claiming nothing is held.
        XCTAssertTrue(text.contains("Held out of the search right now: "))
        for word in ["neck", "head nod", "head turn", "head tilt"] {
            XCTAssertTrue(text.contains(word), word)
        }
        XCTAssertFalse(text.contains("RLHF"))

        // And once something is held, it says which parts by name.
        let held = DuckTuner.Schedule.onAPhone.outcome(applying: [.hold(word: "knees", at: nil)])
        let after = DuckTuner.wordsInstructions(for: held.schedule)
        XCTAssertTrue(after.contains("left knee"))
        XCTAssertTrue(after.contains("right knee"))
    }

    // MARK: - routing

    /// `tweak` AND `search` ARE ABSENT ON PURPOSE, and the list is DATA so a
    /// seventh kind cannot quietly become routable.
    func testSearchIsNotARoutableKind() {
        XCTAssertFalse(ChatDraft.Kind.routable.contains(.tweak))
        XCTAssertFalse(ChatDraft.Kind.routable.contains(.search))
        XCTAssertEqual(ChatDraft.Kind.routable, [.motion, .rule, .retrieval, .training])
        XCTAssertThrowsError(try DraftRouting.read(fromJSON: #"{"kind":"search"}"#)) { error in
            XCTAssertEqual(error as? DraftRouting.RoutingError, .unknownKind("search"))
        }
        XCTAssertEqual(ChatDraft.Kind.search.spoken, "a change to a search")
        XCTAssertTrue(ChatDraft.instructions(for: .search)
            .contains("SearchWords.instructions(for:spec:)"))
    }
}
