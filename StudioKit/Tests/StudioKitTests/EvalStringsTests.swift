import XCTest
@testable import StudioKit

/// Every sentence the evaluation feature puts in front of a person or into a
/// log, checked as copy rather than as code.
///
/// WHY ONE FILE FOR ALL OF THEM. `scripts/check_stage_sentences.sh` proves that
/// a screen draws no literal of its own; it cannot prove that the constants the
/// screen draws instead are any good. So the constants are collected here and
/// walked: none empty, none with an em dash, none with a doubled space, none
/// saying the word this app does not say, and the ones bound for
/// `policy_config` held to two sentences, because their viewer renders that
/// block as a definition list and a paragraph in a definition list is a
/// paragraph nobody finishes.
final class EvalStringsTests: XCTestCase {

    /// Sentences, counted the way a reader counts them: a full stop, question
    /// mark or exclamation mark followed by a space or by the end. A decimal
    /// point is followed by a digit and does not count.
    static func sentences(in text: String) -> Int {
        var count = 0
        let characters = Array(text)
        for (index, character) in characters.enumerated() where ".?!".contains(character) {
            if index == characters.count - 1 || characters[index + 1] == " " { count += 1 }
        }
        return count
    }

    /// Every constant this feature ships so far, by name so a failure says
    /// which one.
    static let everyString: [(String, String)] = [
        ("EvalScorer.notEmittedHere", EvalScorer.notEmittedHere),
        ("EvalScorer.termsAreNotScoresSaid", EvalScorer.termsAreNotScoresSaid),
        ("EvalScorerSet.Refusal.empty", EvalScorerSet.Refusal.empty.message),
        ("EvalScorerSet.Refusal.duplicateName",
         EvalScorerSet.Refusal.duplicateName("travelled_m").message),
        ("EvalScorerSet.Refusal.reservedName",
         EvalScorerSet.Refusal.reservedName("vlm").message),
        ("EvalScorerSet.Refusal.successWithoutMotionEvidence",
         EvalScorerSet.Refusal.successWithoutMotionEvidence("success_at_end").message),
        ("EvalEpochs.noSeedSaid", EvalEpochs.noSeedSaid),
        ("EvalEpochs.noPassAtK", EvalEpochs.noPassAtK),
        ("EvalEpochs.Refusal.noDrops", EvalEpochs.Refusal.noDrops.message),
        ("EvalEpochs.Refusal.outOfRange", EvalEpochs.Refusal.outOfRange.message),
        ("EvalEpochs.Refusal.tooMany", EvalEpochs.Refusal.tooMany(33).message),
        ("EvalEpochs.Refusal.duplicateDrop", EvalEpochs.Refusal.duplicateDrop.message),
        ("EvalEmbodiment.digestIsIdentitySaid", EvalEmbodiment.digestIsIdentitySaid),
        ("EvalEmbodiment.noDigestRefusal", EvalEmbodiment.noDigestRefusal),
        ("EvalEmbodiment.notSeedable", EvalEmbodiment.notSeedable),
        ("EvalEmbodiment.realMicroduckRefusal", EvalEmbodiment.realMicroduckRefusal),
        ("EvalEmbodiment.phoneBenchOnlyBundled", EvalEmbodiment.phoneBenchOnlyBundled),
        ("EvalPolicy.identityResidualSaid", EvalPolicy.identityResidualSaid),
        ("EvalPolicy.foldedResidualSaid", EvalPolicy.foldedResidualSaid),
        ("EvalPolicy.canonicalParametersSaid", EvalPolicy.canonicalParametersSaid),
        ("EvalPolicy.fileOnlySaid", EvalPolicy.fileOnlySaid),
        ("EvalTask.rowTitle", EvalTask.rowTitle),
        ("EvalTask.whatAnEvaluationIs", EvalTask.whatAnEvaluationIs),
        ("EvalTask.nothingRunYet", EvalTask.nothingRunYet),
        ("EvalTask.stopIsNotAFailure", EvalTask.stopIsNotAFailure),
        ("EvalTask.maxStepsSaid", EvalTask.maxStepsSaid),
        ("EvalTask.whyNotMeasure", EvalTask.whyNotMeasure),
        ("EvalTask.whyNotPerform", EvalTask.whyNotPerform),
        ("EvalTask.Refusal.noScenes", EvalTask.Refusal.noScenes.message),
        ("EvalTask.Refusal.duplicateSceneID",
         EvalTask.Refusal.duplicateSceneID("cmd-forward").message),
        ("EvalTask.Refusal.sceneIDNotFilesystemSafe",
         EvalTask.Refusal.sceneIDNotFilesystemSafe("a/b").message),
        ("EvalTask.Refusal.secondsOutOfRange",
         EvalTask.Refusal.secondsOutOfRange(30).message),
        ("EvalTask.Refusal.epochsOnARouteThatDoesNotVary",
         EvalTask.Refusal.epochsOnARouteThatDoesNotVary("/climb").message),
        ("EvalTrace.firstDropOnlySaid", EvalTrace.firstDropOnlySaid),
        ("EvalVerdict.watchBeforeYouJudge", EvalVerdict.watchBeforeYouJudge),
        ("EvalVerdict.recordedNotScoredSaid", EvalVerdict.recordedNotScoredSaid),
        ("EvalVerdict.vocabularySaid", EvalVerdict.vocabularySaid),
        ("EvalRun.erroredNotScoredSaid", EvalRun.erroredNotScoredSaid),
        ("EvalRun.stepCountsSaid", EvalRun.stepCountsSaid),
        ("EvalRun.noLatencySaid", EvalRun.noLatencySaid),
        ("EvalRun.noFramesSaid", EvalRun.noFramesSaid),
        ("EvalRun.allTrialsErrored", EvalRun.allTrialsErrored(24)),
        ("EvalRun.plantChangedMidRun",
         EvalRun.plantChangedMidRun(from: "3f8c9ab9b409ba74", to: "aa11bb22cc33dd44")),
        ("EvalRun.tailNotDeclared", EvalRun.tailNotDeclared(declared: 50, reported: 30)),
        ("EvalRun.producerSaid", EvalRun.producerSaid(version: "1.1", build: "58")),
        ("EvalText.notTheirRender", EvalText.notTheirRender),
        ("EvalLogRefusal.notAnObject", EvalLogRefusal.notAnObject("eval").message),
        ("EvalLogRefusal.unsupportedVersion", EvalLogRefusal.unsupportedVersion("2").message),
        ("EvalLogRefusal.unknownKey", EvalLogRefusal.unknownKey("extra", in: "eval").message),
        ("EvalLogRefusal.missing", EvalLogRefusal.missing("status", in: "the log").message),
        ("EvalLogRefusal.wrongType",
         EvalLogRefusal.wrongType("version", in: "the log", wanted: "a whole number").message),
    ]

    func testEveryStringSaysSomething() {
        for (name, text) in Self.everyString {
            XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, name)
        }
        XCTAssertGreaterThan(Self.everyString.count, 45)
    }

    /// No em dash anywhere in copy under Craig's name. The bench's own
    /// `criterion` has two of them and is carried verbatim, which is a
    /// measurement quoted rather than prose written, and it is not in this
    /// list.
    func testNoStringHasAnEmDash() {
        for (name, text) in Self.everyString {
            XCTAssertFalse(text.contains("\u{2014}"), "\(name) has an em dash")
            XCTAssertFalse(text.contains("\u{2013}"), "\(name) has an en dash")
        }
    }

    func testNoStringHasADoubledSpace() {
        for (name, text) in Self.everyString {
            XCTAssertFalse(text.contains("  "), "\(name) has a doubled space")
        }
    }

    func testNoStringTrailsOrLeadsWithSpace() {
        for (name, text) in Self.everyString {
            XCTAssertEqual(text, text.trimmingCharacters(in: .whitespaces), name)
        }
    }

    /// E4, in the suite as well as in the shell guard: the word this app does
    /// not say, and the phrase it only ever says while denying it.
    func testNoStringSaysTheWordThisAppDoesNotSay() {
        for (name, text) in Self.everyString {
            XCTAssertFalse(text.uppercased().contains("RLHF"), name)
            let lower = text.lowercased()
            if lower.contains("reward model") {
                XCTAssertTrue(lower.contains("no reward model")
                              || lower.contains("not a reward model"), name)
            }
        }
    }

    /// Their viewer renders `policy_config` as a definition list, so anything
    /// bound for it is two sentences at most.
    func testEveryRenderedNoteIsAtMostTwoSentences() throws {
        let epochs = try EvalEpochs.drops(EvalTask.walkDrops, reducer: .median)
        let notes: [(String, String)] = [
            ("EvalEpochs.noSeedSaid", EvalEpochs.noSeedSaid),
            ("EvalEpochs.said (drops)", epochs.said),
            ("EvalEpochs.said (single)", EvalEpochs.single(reducer: .mean).said),
            ("EvalRun.stepCountsSaid", EvalRun.stepCountsSaid),
            ("EvalTrace.firstDropOnlySaid", EvalTrace.firstDropOnlySaid),
            ("EvalPolicy.identityResidualSaid", EvalPolicy.identityResidualSaid),
            ("EvalPolicy.foldedResidualSaid", EvalPolicy.foldedResidualSaid),
            ("EvalPolicy.fileOnlySaid", EvalPolicy.fileOnlySaid),
            ("EvalRun.producerSaid", EvalRun.producerSaid(version: "1.1", build: "58")),
        ]
        for (name, note) in notes {
            XCTAssertLessThanOrEqual(Self.sentences(in: note), 2, "\(name): \(note)")
        }
    }

    /// The counter itself, because a sentence counter that counted nothing
    /// would make the test above pass on a page of prose.
    func testTheSentenceCounterCounts() {
        XCTAssertEqual(Self.sentences(in: "One."), 1)
        XCTAssertEqual(Self.sentences(in: "One. Two."), 2)
        XCTAssertEqual(Self.sentences(in: "One. Two. Three."), 3)
        XCTAssertEqual(Self.sentences(in: "A drop of 0.12 m. Two."), 2)
        XCTAssertEqual(Self.sentences(in: "Nothing here"), 0)
    }

    // MARK: - foreign text, C1 to C6

    func testForeignTextIsCappedWithASingleTrailingMarker() {
        let long = String(repeating: "a", count: 1000)
        let capped = EvalText.foreign(long)
        XCTAssertEqual(capped.count, EvalText.cap)
        XCTAssertEqual(EvalText.cap, 240)
        XCTAssertTrue(capped.hasSuffix(EvalText.marker))
        XCTAssertEqual(EvalText.marker, "\u{2026}")
        XCTAssertEqual(capped.filter { String($0) == EvalText.marker }.count, 1)
    }

    func testTextThatFitsIsNotTouched() {
        XCTAssertEqual(EvalText.foreign("the bench said no"), "the bench said no")
        let exact = String(repeating: "b", count: EvalText.cap)
        XCTAssertEqual(EvalText.foreign(exact), exact)
        XCTAssertFalse(EvalText.foreign(exact).hasSuffix(EvalText.marker))
    }

    /// A tab, a newline and a U+2028 in a row title are a layout nobody can
    /// predict, and a JavaScript authored `why` has no length bound at all.
    func testControlCharactersAreStripped() {
        XCTAssertEqual(EvalText.foreign("a\tb\nc\u{2028}d\u{0}e"), "abcde")
        XCTAssertEqual(EvalText.foreign("  padded  "), "padded")
    }

    func testNonAsciiThatIsNotAControlCharacterSurvives() {
        // The bench's own criterion carries an em dash and a minus sign, and
        // quoting a measurement exactly is not the same thing as writing one.
        XCTAssertEqual(EvalText.foreign("gravity past \u{2212}0.5 \u{2014} upright"),
                       "gravity past \u{2212}0.5 \u{2014} upright")
    }

    func testAnAbsentForeignStringStaysAbsent() {
        XCTAssertNil(EvalText.foreign(nil as String?))
        XCTAssertNil(EvalText.foreign("\t\n" as String?), "a string of nothing is nothing")
        XCTAssertEqual(EvalText.foreign("x" as String?), "x")
    }

    /// The bench's real refusal, which is the longest foreign string this
    /// feature actually meets.
    func testTheBenchsOwnCriterionIsDrawnWholeBecauseItFits() {
        let criterion = "ends standing: at the last tick the trunk's own up is still up "
                      + "\u{2014} gravity projects past \u{2212}0.5 into the body's \u{2212}z, "
                      + "the same test /measure and /perform use \u{2014} and the trunk is at "
                      + "least 100 mm above the floor."
        XCTAssertLessThanOrEqual(criterion.count, EvalText.cap)
        XCTAssertEqual(EvalText.foreign(criterion), criterion)
    }
}
