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
    ///
    /// The screens' own chrome is swept with them, off `EvalScreen.everyWord`,
    /// so a heading cannot pick up an em dash or a second wording just because
    /// it is one word long. `EvalScreenTests` is what pins each of those to its
    /// exact text; this is the sweep they join.
    static let everyString: [(String, String)] =
        authoredSentences + EvalScreen.everyWord.map { ("EvalScreen \"\($0)\"", $0) }

    static let authoredSentences: [(String, String)] = [
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
        ("EvalEpochs.wholeSceneAtOnceSaid", EvalEpochs.wholeSceneAtOnceSaid),
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
        ("EvalTask.noHorizonSaid", EvalTask.noHorizonSaid),
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
        // the writer, the file and the shelf
        ("EvalLogWriter.runIDSaid", EvalLogWriter.runIDSaid),
        ("EvalLogWriter.wroteIt", EvalLogWriter.wroteIt(version: "1.1", build: "58")),
        ("EvalLogReader.asStrictAsTheirs", EvalLogReader.asStrictAsTheirs),
        ("EvalLogFile.fromTheFile", EvalLogFile.fromTheFile),
        ("EvalLogFile.importedBadge", EvalLogFile.importedBadge),
        ("EvalLogFile.importedSaid", EvalLogFile.importedSaid),
        ("EvalLogFile.cannotPublishImported", EvalLogFile.cannotPublishImported),
        ("EvalLogFile.foreignSeedSaid", EvalLogFile.foreignSeedSaid),
        ("EvalLogFile.whatAnImportedLogMustBe", EvalLogFile.whatAnImportedLogMustBe),
        ("EvalLogFile.aLogIsFinished", EvalLogFile.aLogIsFinished),
        ("EvalLogFile.howToRead", EvalLogFile.howToRead),
        ("EvalLogFile.oneLogAtATimeSaid", EvalLogFile.oneLogAtATimeSaid),
        ("EvalLogFile.criterionLabel", EvalLogFile.criterionLabel),
        ("EvalLogFile.plantDigestLabel", EvalLogFile.plantDigestLabel),
        ("EvalLogFile.Refusal.imported", EvalLogFile.Refusal.imported.message),
        // the report
        ("EvalReport.notFinite", EvalReport.notFinite),
        ("EvalReport.leaderboardIsTheChallengeScreen",
         EvalReport.leaderboardIsTheChallengeScreen),
        ("EvalReport.whatIsShared", EvalReport.whatIsShared),
        ("EvalReport.meanOverScenesSaid", EvalReport.meanOverScenesSaid),
        ("EvalReport.cancelledLead", EvalReport.cancelledLead),
        ("EvalReport.passedOnSaid", EvalReport.passedOnSaid),
        ("EvalReport.wroteItSaid", EvalReport.wroteItSaid("Microduck Studio 1.1 (58)")),
        ("EvalReport.horizonSaid", EvalReport.horizonSaid(seconds: 6.0, steps: 300)),
        ("EvalReport.spreadSaid (flat)", EvalReport.spreadSaid([1.0, 1.0, 1.0])),
        ("EvalReport.spreadSaid (spread)", EvalReport.spreadSaid([1.18, 1.22])),
        ("EvalReport.spreadSaid (none)", EvalReport.spreadSaid([])),
        ("EvalReport.statusShown", EvalReport.statusShown(.cancelled)),
        // comparing two
        ("EvalCompare.neverCombinedSaid", EvalCompare.neverCombinedSaid),
        ("EvalCompare.differenceIsNotAScoreSaid", EvalCompare.differenceIsNotAScoreSaid),
        ("EvalCompare.oneSidedSaid", EvalCompare.oneSidedSaid),
        ("EvalCompare.whatCanBeComparedSaid", EvalCompare.whatCanBeComparedSaid),
        ("EvalCompare.Refusal.sameLog", EvalCompare.Refusal.sameLog("walk_4b1e77a2.json").message),
        ("EvalCompare.Refusal.differentEmbodiment",
         EvalCompare.Refusal.differentEmbodiment("a/one.mjb@aa", "a/two.mjb@bb").message),
        ("EvalCompare.Refusal.differentTask",
         EvalCompare.Refusal.differentTask("Walk forward", "Stairs grid").message),
        ("EvalCompare.Refusal.nothingInCommon", EvalCompare.Refusal.nothingInCommon.message),
    ]

    func testEveryStringSaysSomething() {
        for (name, text) in Self.everyString {
            XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, name)
        }
        XCTAssertGreaterThan(Self.everyString.count, 80)
    }

    /// Two constants with the same words are two places a wording can be
    /// changed in one of them, which is the "second wording" failure this whole
    /// feature is organised against.
    ///
    /// THE EXCEPTIONS ARE FORWARDS AND NOT COPIES. A `Refusal.message` that
    /// returns a named constant is one sentence reachable by two names, which
    /// is the opposite of the problem: change the constant and both move. Each
    /// one is listed here so a real duplicate cannot hide behind the rule.
    static let sameWordsOnPurpose: Set<String> = [
        // A door that described itself differently from the screen it opens
        // would be two descriptions of one thing.
        "EvalTask.whatAnEvaluationIs",
        // Refusals that forward to the sentence they are the refusal for.
        "EvalLogFile.Refusal.imported", "EvalLogFile.cannotPublishImported",
        "EvalText.notTheirRender", "EvalReport.notTheirRender",
    ]

    func testNoTwoConstantsSayTheSameThing() {
        var seen: [String: String] = [:]
        for (name, text) in Self.everyString {
            if let first = seen[text] {
                XCTAssertTrue(Self.sameWordsOnPurpose.contains(name)
                              || Self.sameWordsOnPurpose.contains(first),
                              "\(name) and \(first) are the same sentence")
            }
            seen[text] = name
        }
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
            ("EvalTask.noHorizonSaid", EvalTask.noHorizonSaid),
        ]
        for (name, note) in notes {
            XCTAssertLessThanOrEqual(Self.sentences(in: note), 2, "\(name): \(note)")
        }
    }

    /// The cap, over the log a run actually writes rather than over a list
    /// somebody remembered to keep up to date. Their viewer renders
    /// `policy_config` as a definition list, and a paragraph in a definition
    /// list is a paragraph nobody finishes.
    ///
    /// The bench's own `criterion` is exempt and is the only exemption: it is a
    /// measurement quoted exactly, this app did not write it, and truncating it
    /// would put a sentence in the record the bench never said.
    func testEveryNoteInAWrittenLogIsAtMostTwoSentences() throws {
        for entry in try EvalFixtures.corpus() where entry.file.origin == .written {
            for (key, value) in entry.file.log.eval.policyConfig {
                guard key != EvalMeta.criterion, let text = value.stringValue else { continue }
                XCTAssertLessThanOrEqual(Self.sentences(in: text), 2,
                                         "\(entry.name)/\(key): \(text)")
            }
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
