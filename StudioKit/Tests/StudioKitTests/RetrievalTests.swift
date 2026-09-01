import XCTest
@testable import StudioKit

final class RetrievalTests: XCTestCase {

    /// The constants are upstream's, and a drift in either direction is a bug.
    func testTheScheduleMatchesUpstream() {
        XCTAssertEqual(Retrieval.phasePeriod, 4.0)            // GP_PERIOD, ground_pick_period
        XCTAssertEqual(Retrieval.endPhase, 0.7)               // GROUND_PICK_END_PHASE
        XCTAssertEqual(Retrieval.pickDuration, 2.8, accuracy: 1e-9)
        XCTAssertEqual(Retrieval.payloadRange.lowerBound, 0.010)
        XCTAssertEqual(Retrieval.payloadRange.upperBound, 0.040)
    }

    /// The grasp instant is MEASURED and lands before the config's nominal
    /// hold, not inside it. If these ever agree, one of them has changed.
    func testTheGraspInstantDisagreesWithTheConfigsHold() {
        let nominalHoldStart = 0.375 * Retrieval.phasePeriod   // DESCENT_END
        let nominalHoldEnd = 0.425 * Retrieval.phasePeriod     // HOLD_END
        XCTAssertEqual(nominalHoldStart, 1.5, accuracy: 1e-9)
        XCTAssertLessThan(Retrieval.graspInstant, nominalHoldStart)
        XCTAssertTrue(Retrieval.graspWindow.contains(Retrieval.graspInstant))
        // The measured window CLOSES where the config's hold opens.
        XCTAssertEqual(Retrieval.graspWindow.upperBound, nominalHoldStart, accuracy: 1e-9)
        XCTAssertFalse(Retrieval.graspWindow.contains(nominalHoldEnd),
                       "closing the jaw on the config's hold closes it on the way up")
    }

    func testAPencilIsTooThinToPickUp() {
        let (reading, plan) = Retrieval.plan(for: "go and fetch the pencil")
        XCTAssertEqual(reading.object, "pencil")
        XCTAssertFalse(plan.isPossible)
        XCTAssertEqual(plan.refusals.first, .tooThin(millimetres: 7))
        XCTAssertTrue(plan.refusals.first!.message.contains("20 mm above the floor"))
    }

    /// TOO HEAVY TO LIFT IS NOT THE END OF IT. The floor can take the weight,
    /// so the plan switches to dragging instead of stopping — and says plainly
    /// that nobody has measured a duck towing anything.
    func testACarrotIsTooHeavyToLiftAndSoItDragsIt() {
        let (_, plan) = Retrieval.plan(for: "bring me the carrot")
        XCTAssertTrue(plan.isPossible, "60 g is nothing to drag")
        XCTAssertTrue(plan.steps.contains(.dragBack(metres: 1.0)))
        XCTAssertFalse(plan.steps.contains(.lift), "it never stands the load up")
        guard case .tooHeavyToLift? = plan.refusals.first else {
            return XCTFail("expected the lift refusal, got \(plan.refusals)")
        }
        XCTAssertTrue(plan.refusals.first!.message.contains("Staying upright while dragging"))
    }

    /// A 20 mm dowel at 25 g is inside every envelope, so the plan stands.
    func testADowelIsFetchable() {
        let (_, plan) = Retrieval.plan(for: "pick up the dowel 1 m away and bring it back")
        XCTAssertTrue(plan.isPossible, "\(plan.refusals.map(\.message))")
        XCTAssertEqual(plan.steps.count, 7)
        XCTAssertEqual(plan.steps.first, .approach(metres: 1.0))
        XCTAssertEqual(plan.steps.last, .release)
    }

    /// Distance warns, it does not refuse. Slow is not impossible.
    func testDistanceWarnsWithoutStopping() {
        let (_, plan) = Retrieval.plan(for: "fetch the stick 5 m away")
        XCTAssertTrue(plan.isPossible)
        guard case .tooFar(let metres, let minutes)? = plan.refusals.first else {
            return XCTFail("expected a distance warning, got \(plan.refusals)")
        }
        XCTAssertEqual(metres, 5, accuracy: 1e-9)
        XCTAssertEqual(minutes, 2 * 5 / 0.106 / 60, accuracy: 1e-9)
    }

    /// "2 mm thick" must not be read as a distance, and "2 m away" must not be
    /// read as a thickness.
    func testUnitsAreReadInContext() {
        let thin = Retrieval.read("a stick 4 mm thick, 2 m away")
        XCTAssertEqual(thin.stick.thicknessMillimetres, 4, accuracy: 1e-9)
        XCTAssertEqual(thin.stick.metresAway, 2, accuracy: 1e-9)
    }

    func testGramsAndKilogramsBothRead() {
        XCTAssertEqual(Retrieval.read("fetch the 30 g stick").stick.grams, 30, accuracy: 1e-9)
        XCTAssertEqual(Retrieval.read("fetch the 0.02 kg stick").stick.grams, 20, accuracy: 1e-9)
    }

    /// What was guessed has to be visible. A plan built on three defaults and
    /// presented as an answer is a guess wearing a timeline.
    func testEverythingUnsaidIsReportedAsAnAssumption() {
        let reading = Retrieval.read("fetch it")
        XCTAssertNil(reading.object)
        XCTAssertTrue(reading.understood.isEmpty)
        XCTAssertEqual(reading.assumed.count, 3)
        XCTAssertTrue(reading.assumed.contains { $0.contains("weight") })
        XCTAssertTrue(reading.assumed.contains { $0.contains("thickness") })
        XCTAssertTrue(reading.assumed.contains { $0.contains("distance") })
    }

    /// The timeline adds up, and the two policy segments together are exactly
    /// one truncated ground-pick.
    func testTheTimelineAddsUp() {
        let plan = Retrieval.plan(for: .init(grams: 25, thicknessMillimetres: 22, metresAway: 0.5))
        let walk = 0.5 / Retrieval.walkSpeed
        XCTAssertEqual(plan.seconds,
                       walk * 2 + Retrieval.pickDuration + 0.25 + 0.25 + Retrieval.settleAfterLift,
                       accuracy: 1e-9)
        let pick = plan.steps.filter { $0.policy == "alpha_ground_pick" }
        XCTAssertEqual(pick.reduce(0) { $0 + $1.seconds }, Retrieval.pickDuration, accuracy: 1e-9)
        XCTAssertEqual(plan.schedule.first!.start, 0)
        XCTAssertEqual(plan.schedule.map(\.start).sorted(), plan.schedule.map(\.start))
    }

    /// No policy drives the mouth, which is the whole reason a grasp can be
    /// scheduled at all.
    func testTheGraspIsNotAPolicyStep() {
        XCTAssertNil(Retrieval.Step.closeMouth.policy)
        XCTAssertNil(Retrieval.Step.release.policy)
        XCTAssertEqual(Retrieval.Step.approach(metres: 1).policy, "alpha_walking")
        XCTAssertEqual(Retrieval.Step.reachDown.policy, "alpha_ground_pick")
    }

    // FOUR TESTS ABOUT THE `.duck` EXPORT CAME OUT WITH IT. They asserted that
    // quackd's task file carried the battery floor, the repeat-failure stop and
    // a refusal — real properties of a format this app no longer writes. The
    // constraints they were protecting are still measured and still shown; what
    // is gone is the claim that they travel inside somebody else's schema.
    // `DuckPlanFileTests` covers the format that replaced it.

}

extension RetrievalTests {

}

// MARK: - the half of the file a machine acts on

/// EVERY EXPORT USED TO CARRY THREE ADVISORY SENTENCES AND NOTHING ELSE, so a
/// task written here reached quackd with no battery floor and no repeat-failure
/// stop while the export screen's footer claimed the file "carries the
/// constraints in its own body". These pin the machine-readable half.
extension RetrievalTests {

    private func fetchablePlan() -> Retrieval.Plan {
        Retrieval.plan(for: .init(grams: 25, thicknessMillimetres: 22, metresAway: 0.8))
    }

}

// MARK: - whether the sentence was understood at all

/// A PLAN FOR AN INVENTED DOWEL USED TO BE BYTE-IDENTICAL TO A PLAN FOR A BEER.
/// "fetch me a beer", "asdfghjkl" and an empty field all fell through to the
/// same 20 g / 20 mm / 1 m defaults, and the screen answered with a green
/// "Inside every envelope." and a 22.8 s seven-step schedule. These pin the
/// three states and every sentence that goes with them.
extension RetrievalTests {

    func testASentenceThatNamesNothingIsNotUnderstood() {
        for sentence in ["", "asdfghjkl", "hello", "fetch me a beer", "fetch it", "fetch my keys"] {
            let reading = Retrieval.read(sentence)
            XCTAssertFalse(reading.recognisedObject, "\"\(sentence)\"")
            XCTAssertEqual(reading.confidence, .notUnderstood, "\"\(sentence)\"")
        }
    }

    /// The plan is still built — the robot's envelope is a separate question and
    /// stays one — but the reading no longer claims the sentence was parsed.
    func testAnUnparsedSentenceStillPlansButNoLongerClaimsToBeUnderstood() {
        let (reading, plan) = Retrieval.plan(for: "fetch me a beer")
        XCTAssertEqual(reading.confidence, .notUnderstood)
        XCTAssertTrue(plan.isPossible, "isPossible is about the robot, not about the sentence")
        XCTAssertTrue(plan.refusals.isEmpty, "the sentence's legibility is not a Refusal")
    }

    /// GRAMS ALONE MUST NOT BUY THE GREEN SEAL. The thickness is what the bite
    /// test measures, and the invented 20 mm is EXACTLY the jaw height — which
    /// the test compares with a strict `<`, so an unnamed object lands on the
    /// permissive side of the one threshold that decides the grasp.
    func testGramsAloneDoNotCountAsUnderstanding() {
        let reading = Retrieval.read("fetch the 30 g thing")
        XCTAssertNil(reading.object)
        XCTAssertEqual(reading.stick.grams, 30, accuracy: 1e-9)
        XCTAssertEqual(reading.stick.thicknessMillimetres,
                       Retrieval.closedTipHeight * 1000, accuracy: 1e-9)
        XCTAssertEqual(reading.confidence, .notUnderstood)
    }

    /// A thickness given outright is checkable without a noun, so it counts.
    ///
    /// AND THIS IS THE CASE THE APP'S UNNAMED-TASK TITLE FALLBACK EXISTS FOR.
    /// `object == nil` and `confidence != .notUnderstood` CO-OCCUR, so a
    /// confidence guard in front of the export does not make an unnamed reading
    /// unreachable — RetrieveView's `reading.object.map { "Fetch the \($0)" }
    /// ?? "Fetch it"` still has to handle exactly this sentence. An earlier
    /// handoff note claimed the fallback became dead code; deleting it would
    /// fail to compile, and short-circuiting it would export an unnamed task.
    func testAThicknessGivenOutrightIsEnoughWithoutANoun() {
        let reading = Retrieval.read("fetch the thing 25 mm thick 2 m away")
        XCTAssertNil(reading.object)
        XCTAssertTrue(reading.recognisedObject)
        XCTAssertNotEqual(reading.confidence, .notUnderstood)
        XCTAssertEqual(reading.confidence, .understoodWithGuesses)
        XCTAssertEqual(reading.assumed, ["weight unknown — taken as 20 g"])
    }

    func testACatalogueWordWithEstimatesSaysTheyAreEstimates() {
        let reading = Retrieval.read("fetch the stick")
        XCTAssertEqual(reading.object, "stick")
        XCTAssertEqual(reading.confidence, .understoodWithGuesses)
    }

    /// Say every number and nothing is guessed at all.
    func testASentenceThatSaysEverythingIsUnderstoodOutright() {
        let reading = Retrieval.read("fetch the 30 g stick 25 mm thick 2 m away")
        XCTAssertTrue(reading.assumed.isEmpty, "\(reading.assumed)")
        XCTAssertEqual(reading.confidence, .understood)
    }

    /// A prop somebody described by hand is the strongest recognition there is.
    func testAPropInYourSceneIsUnderstoodOutright() {
        let (reading, _) = Retrieval.plan(for: "drag the broom over here",
                                          props: [DuckScene.broom()])
        XCTAssertTrue(reading.recognisedObject)
        XCTAssertEqual(reading.confidence, .understood)
    }

    /// THE SENTENCES ARE THE PRODUCT. Pinned string for string, because a view
    /// that paraphrased one would be the app going quiet about the one thing it
    /// exists to say. Four branches, not three: `.notUnderstood` says something
    /// different depending on whose weight is in the plan.
    func testEverySentenceOnAReadingIsPinned() {
        XCTAssertEqual(Retrieval.read("fetch the 30 g stick 25 mm thick 2 m away").sentence,
                       "Every number in this plan came out of your sentence.")
        XCTAssertEqual(Retrieval.read("fetch the stick").sentence,
                       "Some of these numbers are estimates of YOUR object, not measurements "
                     + "of the robot. Say the number and the guess goes away.")
        XCTAssertEqual(Retrieval.read("fetch me a beer").sentence,
                       "This sentence does not name anything to fetch, so the plan below is "
                     + "about an invented 20 g object 20 mm thick and answers a question you "
                     + "did not ask. Name the thing — pencil, pen, chopstick, twig, stick, "
                     + "dowel, crayon, cork, ball, carrot, broom, mop, rake or umbrella — or "
                     + "give a thickness outright, like \"25 mm thick\". The thickness is what "
                     + "decides whether the jaw can take hold of it at all.")
        XCTAssertEqual(Retrieval.read("fetch the 30 g thing").sentence,
                       "This sentence does not name anything to fetch. Your 30 g is in the "
                     + "plan below, but the 20 mm thickness beside it is this app's invention, "
                     + "not yours, so the plan still answers a question you did not ask. "
                     + "Name the thing — pencil, pen, chopstick, twig, stick, dowel, crayon, "
                     + "cork, ball, carrot, broom, mop, rake or umbrella — or give a thickness "
                     + "outright, like \"25 mm thick\". The thickness is what decides whether "
                     + "the jaw can take hold of it at all.")
    }

    /// THE REFUSAL MUST NOT CALL A PERSON'S OWN FIGURE MADE UP. "fetch the
    /// 30 g thing" is not understood — no noun, no thickness, so nothing was
    /// ever grasp-checked — but the 30 g came straight out of the sentence and
    /// the screen lists it two rows up under "Read as". The old sentence hung
    /// off `Confidence` alone and answered that with "an invented 20 g object",
    /// which is the app fabricating a fabrication.
    func testASentenceThatGaveAWeightIsNeverToldItsWeightWasInvented() {
        let reading = Retrieval.read("fetch the 30 g thing")
        XCTAssertEqual(reading.understood, ["30 g"])
        XCTAssertEqual(reading.confidence, .notUnderstood)
        XCTAssertFalse(reading.weightWasInvented)
        XCTAssertFalse(reading.sentence.contains("invented 20 g"), reading.sentence)
        XCTAssertTrue(reading.sentence.contains("Your 30 g is in the plan below"),
                      reading.sentence)
    }

    /// Every number the sentence quotes is a number out of the plan it sits
    /// above — by construction, not by two constants happening to agree.
    func testTheSentenceQuotesTheNumbersInThePlanItSitsAbove() {
        for text in ["fetch me a beer", "fetch the 30 g thing", "fetch the 0.4 kg thing",
                     "fetch it 2 m away", "asdfghjkl"] {
            let reading = Retrieval.read(text)
            XCTAssertEqual(reading.confidence, .notUnderstood, "\"\(text)\"")
            XCTAssertTrue(reading.sentence.contains(String(format: "%.0f g", reading.stick.grams)),
                          "\"\(text)\" → \(reading.sentence)")
            XCTAssertTrue(reading.sentence.contains(
                String(format: "%.0f mm thick", reading.stick.thicknessMillimetres))
                || reading.sentence.contains(
                    String(format: "%.0f mm thickness", reading.stick.thicknessMillimetres)),
                "\"\(text)\" → \(reading.sentence)")
        }
    }

    /// THE ONE INVARIANT THE SENTENCE LEANS ON, PROVED OVER A TABLE OF
    /// HAND-WRITTEN SENTENCES. Both `.notUnderstood` branches state flatly that
    /// the thickness is this app's, with no flag behind it — that is only
    /// honest because `recognisedObject` is false EXACTLY when no catalogue
    /// word matched and no thickness was given outright, and those are the only
    /// two ways a thickness can arrive. Weight, distance, grasp height, drag
    /// and "across the room" can all be supplied and none of them changes it.
    func testAnUnderstoodThicknessIsUnreachableWhileNotUnderstood() {
        for text in ["", "   ", "hello", "asdfghjkl", "fetch me a beer", "fetch my keys",
                     "fetch it", "fetch the 30 g thing", "fetch the 0.4 kg thing",
                     "fetch it 2 m away", "fetch it across the room",
                     "drag the 30 g thing 2 m away", "fetch the thing 150 mm up",
                     "fetch the 30 g thing 2 m away laid down",
                     "fetch the 25 g thing 60 cm away standing"] {
            let reading = Retrieval.read(text)
            XCTAssertEqual(reading.confidence, .notUnderstood, "\"\(text)\"")
            XCTAssertEqual(reading.stick.thicknessMillimetres,
                           Retrieval.assumedThicknessMillimetres, accuracy: 1e-9, "\"\(text)\"")
            XCTAssertTrue(reading.sentence.contains("20 mm"), "\"\(text)\" → \(reading.sentence)")
            for fact in reading.understood {
                XCTAssertFalse(fact.hasSuffix("mm thick"), "\"\(text)\" understood \(fact)")
            }
        }
    }

    /// A word added to the catalogue cannot go missing from the sentence that
    /// offers the vocabulary — in EITHER `.notUnderstood` branch.
    func testTheNotUnderstoodSentenceOffersTheWholeVocabulary() {
        for text in ["fetch me a beer", "fetch the 30 g thing"] {
            let sentence = Retrieval.read(text).sentence
            for object in Retrieval.everydayObjects {
                XCTAssertTrue(sentence.contains(object.word), "\"\(text)\" missing \(object.word)")
            }
        }
        XCTAssertTrue(Retrieval.vocabulary.hasSuffix("rake or umbrella"), Retrieval.vocabulary)
    }

    /// A prop somebody described by hand has no invented weight in it.
    func testAPropsWeightIsNeverTheAppsInvention() {
        let (reading, _) = Retrieval.plan(for: "drag the broom over here",
                                          props: [DuckScene.broom()])
        XCTAssertFalse(reading.weightWasInvented)
        XCTAssertEqual(reading.sentence, "Every number in this plan came out of your sentence.")
    }

    /// A CATALOGUE ESTIMATE IS THIS APP'S INVENTION TOO. `weightWasInvented`
    /// was computed as `grams == nil`, which is a different question — `grams`
    /// has already taken the catalogue's number by that line — so "fetch the
    /// pencil" answered `false` while the Guessed list on the same screen read
    /// "a pencil weighs about 6 g". Nothing on screen was wrong, because the
    /// one branch that reads this flag cannot reach a catalogue word; a public
    /// property that is false in a state nobody happens to look at is a wrong
    /// sentence waiting for its second reader, so it is pinned in the state
    /// that exposed it rather than only in the state that uses it.
    ///
    /// THE INVARIANT, BOTH WAYS: the flag is true exactly when the Guessed list
    /// carries a line about the weight. That is one fact with two consequences
    /// — the screen and the refusal cannot argue with each other — and it is
    /// swept rather than sampled, because three hand-picked rows are how the
    /// disagreement survived the last two passes.
    func testTheInventedWeightFlagIsTrueForACatalogueEstimate() {
        func mentionsTheWeight(_ assumed: [String]) -> Bool {
            assumed.contains { $0.contains("weighs about") || $0.hasPrefix("weight unknown") }
        }
        for word in Retrieval.everydayObjects.map(\.word) {
            let reading = Retrieval.read("fetch the \(word)")
            XCTAssertTrue(reading.weightWasInvented,
                          "nobody typed a weight for \"fetch the \(word)\" — the "
                        + "\(reading.stick.grams) g in the plan is the catalogue's")
            XCTAssertTrue(mentionsTheWeight(reading.assumed),
                          "\(word): \(reading.assumed)")
        }
        // Every shape that DOES supply a weight, including the one the plan
        // quotes back in different units from the ones it was typed in.
        for text in ["fetch the 30 g thing", "fetch the 400 g pencil", "fetch the 0.4 kg broom",
                     "drag the 1 kg umbrella over here", "fetch the 45 gram twig"] {
            let reading = Retrieval.read(text)
            XCTAssertFalse(reading.weightWasInvented, text)
            XCTAssertFalse(mentionsTheWeight(reading.assumed), "\(text): \(reading.assumed)")
        }
        // And the sweep, over every sentence shape `read` has a branch for.
        for head in ["fetch the", "get me a", "drag the", "pick up the", "bring the"] {
            for noun in Retrieval.everydayObjects.map(\.word) + ["thing", "20 g thing"] {
                for tail in ["", " across the room", " 2 m away", " laid down", " standing",
                             " 25 mm thick", " over here"] {
                    let reading = Retrieval.read("\(head) \(noun)\(tail)")
                    XCTAssertEqual(reading.weightWasInvented,
                                   mentionsTheWeight(reading.assumed),
                                   "\"\(head) \(noun)\(tail)\" — flag "
                                 + "\(reading.weightWasInvented), assumed \(reading.assumed)")
                }
            }
        }
    }

    /// The invented numbers the sentence quotes back are the ones `read`
    /// actually uses. A drift here is a screen describing an assumption nobody
    /// made.
    func testTheQuotedDefaultsAreTheOnesReadActuallyUses() {
        let reading = Retrieval.read("fetch it")
        XCTAssertEqual(reading.stick.grams, Retrieval.assumedGrams, accuracy: 1e-9)
        XCTAssertEqual(reading.stick.thicknessMillimetres,
                       Retrieval.assumedThicknessMillimetres, accuracy: 1e-9)
        XCTAssertEqual(reading.stick.metresAway, Retrieval.assumedMetresAway, accuracy: 1e-9)
        XCTAssertEqual(Retrieval.assumedThicknessMillimetres, Retrieval.closedTipHeight * 1000,
                       accuracy: 1e-9)
    }
}

