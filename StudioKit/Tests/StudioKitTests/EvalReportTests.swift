import XCTest
import DuckKit
@testable import StudioKit

/// The page this app draws, the paragraph it offers to share, and the one
/// function that turns a recorded episode into something the stage can draw.
final class EvalReportTests: XCTestCase {

    // MARK: - numbers

    func testANumberReadsAsAMeasurementAndNeverAsACount() {
        XCTAssertEqual(EvalReport.number(1.0), "1.0", "a success rate is not the number one")
        XCTAssertEqual(EvalReport.number(1.1932), "1.1932")
        XCTAssertEqual(EvalReport.number(0.021), "0.021")
        XCTAssertEqual(EvalReport.number(0.12345678), "0.1235")
        XCTAssertEqual(EvalReport.number(0), "0.0")
        XCTAssertEqual(EvalReport.number(.infinity), EvalReport.notFinite)
        XCTAssertEqual(EvalReport.number(.nan), EvalReport.notFinite)
    }

    // MARK: - the escaper

    /// C1 to C6 on the page: every interpolated string, once.
    func testTheEscaperCoversTheFiveAndBothLineSeparators() {
        XCTAssertEqual(EvalReport.escaped("a<b"), "a&lt;b")
        XCTAssertEqual(EvalReport.escaped("a>b"), "a&gt;b")
        XCTAssertEqual(EvalReport.escaped("a&b"), "a&amp;b")
        XCTAssertEqual(EvalReport.escaped("a\"b"), "a&quot;b")
        XCTAssertEqual(EvalReport.escaped("a'b"), "a&#39;b")
        XCTAssertEqual(EvalReport.escaped("a\u{2028}b"), "a&#8232;b")
        XCTAssertEqual(EvalReport.escaped("a\u{2029}b"), "a&#8233;b")
        XCTAssertEqual(EvalReport.escaped("&<>"), "&amp;&lt;&gt;",
                       "and the ampersand is escaped first or it eats the others")
        XCTAssertEqual(EvalReport.escaped("caf\u{e9} \u{1F986}"), "caf\u{e9} \u{1F986}",
                       "a letter is a letter")
    }

    /// The bench's own criterion carries an em dash and a minus sign, and both
    /// survive the page as themselves: neither is a character HTML needs
    /// escaped, and turning a measurement's punctuation into an entity would be
    /// this app editing what the bench said. Its apostrophes DO become
    /// entities, which is the escaper doing its job and is invisible in a
    /// browser.
    func testTheBenchsOwnPunctuationSurvivesTheEscaper() {
        let escaped = EvalReport.escaped(EvalFixtures.criterion)
        XCTAssertTrue(escaped.contains("\u{2014}"), "the em dash is not an HTML character")
        XCTAssertTrue(escaped.contains("\u{2212}0.5"), "and neither is the minus sign")
        XCTAssertTrue(escaped.contains("trunk&#39;s"))
        XCTAssertFalse(escaped.contains("trunk's"))
        XCTAssertEqual(escaped.replacingOccurrences(of: "&#39;", with: "'"),
                       EvalFixtures.criterion,
                       "and nothing else about it changed")
    }

    func testAScriptTagInASceneNameComesOutAsText() throws {
        let task = try EvalTask.checked(
            id: "hostile", name: "<script>alert(1)</script>",
            said: "a task named after an attack",
            route: .tune,
            scenes: [EvalScene(id: "s", instruction: "<script>alert(2)</script>",
                               command: DuckBench.walkingCommand)],
            scorers: .walk,
            epochs: try EvalEpochs.drops([0.12], reducer: .mean),
            maxSeconds: 6.0)
        let trial = EvalTrial.scored(sceneID: "s", epoch: 0,
                                     scores: [EvalScorer.successAtEnd.name: 1.0,
                                              EvalScorer.travelled.name: 1.0],
                                     terminationReason: "success", ticks: nil, metadata: [:])
        let run = try EvalFixtures.run(
            task: task,
            scenes: [EvalSceneResult(scene: task.scenes[0], reducer: .mean, trials: [trial])])
        let html = EvalReport.html(EvalFixtures.file(run, runID: "0badc0de"))
        XCTAssertFalse(html.contains("<script"), "a page with a script in it is not a report")
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(2)&lt;/script&gt;"))
    }

    // MARK: - the page

    func testThePageIsSelfContained() throws {
        let html = EvalReport.html(try EvalFixtures.workedExample())
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("</html>"))
        XCTAssertFalse(html.contains("http://"), "no network")
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("<img"), "no images to fetch")
        XCTAssertFalse(html.contains("<script"))
        XCTAssertEqual(html.components(separatedBy: "<style>").count - 1, 1,
                       "one stylesheet, inline")
    }

    /// The colours come from `Palette`, whose contrast `PaletteTests` already
    /// holds to WCAG, in both schemes.
    func testThePageTakesItsColoursFromThePalette() throws {
        let html = EvalReport.html(try EvalFixtures.workedExample())
        XCTAssertTrue(html.contains(Palette.color(.textPrimary, in: .light).hexString))
        XCTAssertTrue(html.contains(Palette.color(.textPrimary, in: .dark).hexString))
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"))
    }

    /// The sentences that must reach the page, each one an honesty claim this
    /// build is organised around.
    func testEveryHonestySentenceReachesThePage() throws {
        let file = try EvalFixtures.workedExample()
        let html = EvalReport.html(file)
        let required: [(String, String)] = [
            ("noSeedSaid", EvalEpochs.noSeedSaid),
            ("stepCountsSaid", EvalRun.stepCountsSaid),
            ("firstDropOnlySaid", EvalTrace.firstDropOnlySaid),
            ("recordedNotScoredSaid", EvalVerdict.recordedNotScoredSaid),
            ("termsAreNotScoresSaid", EvalScorer.termsAreNotScoresSaid),
            ("erroredNotScoredSaid", EvalRun.erroredNotScoredSaid),
            ("noLatencySaid", EvalRun.noLatencySaid),
            ("noFramesSaid", EvalRun.noFramesSaid),
            ("notEmittedHere", EvalScorer.notEmittedHere),
            ("digestIsIdentitySaid", EvalEmbodiment.digestIsIdentitySaid),
            ("meanOverScenesSaid", EvalReport.meanOverScenesSaid),
            ("howToRead", EvalLogFile.howToRead),
            ("independenceShort", Provenance.independenceShort),
            ("reproduceSaid", EvalReport.reproduceSaid(file.log)),
        ]
        for (name, sentence) in required {
            XCTAssertTrue(html.contains(EvalReport.escaped(sentence)), name)
        }
    }

    /// L12: the last thing on the page says whose page it is.
    func testTheLastLineIsTheDenial() throws {
        let html = EvalReport.html(try EvalFixtures.workedExample())
        let tail = html.suffix(600)
        XCTAssertTrue(tail.contains(EvalReport.escaped(EvalReport.notTheirRender)))
        XCTAssertEqual(EvalReport.notTheirRender, EvalText.notTheirRender,
                       "one denial, one wording")
    }

    /// A7: a grid log says on its own page that a leaderboard is somewhere
    /// else, and a walk log does not, because there is no leaderboard for it to
    /// be confused with.
    func testOnlyAGridLogNamesTheLeaderboard() throws {
        let grid = EvalReport.html(try EvalFixtures.stairsMixed())
        XCTAssertTrue(grid.contains(EvalReport.escaped(
            EvalReport.leaderboardIsTheChallengeScreen)))
        let walk = EvalReport.html(try EvalFixtures.workedExample())
        XCTAssertFalse(walk.contains(EvalReport.escaped(
            EvalReport.leaderboardIsTheChallengeScreen)))
    }

    /// L1 on the page: success and the evidence that keeps it honest are
    /// adjacent, and there is no arrangement of the tiles where one appears
    /// without the other.
    func testSuccessAndMotionEvidenceAreAdjacentInEveryOrdering() {
        let names = EvalReport.ordered([EvalScorer.maxTorque.name, EvalScorer.endHeight.name,
                                        EvalScorer.travelled.name, EvalScorer.successAtEnd.name])
        XCTAssertEqual(names, ["success_at_end", "travelled_m", "end_height_m", "max_torque_nm"])
        for set in EvalScorerSet.all {
            let ordered = EvalReport.ordered(set.names)
            let successIndex = try? XCTUnwrap(ordered.firstIndex {
                EvalReport.scorer(named: $0)?.role == .success
            })
            let evidenceIndex = try? XCTUnwrap(ordered.firstIndex {
                EvalReport.scorer(named: $0)?.role == .motionEvidence
            })
            XCTAssertNotNil(successIndex)
            XCTAssertNotNil(evidenceIndex)
        }
    }

    /// A name from somebody else's task is drawn under its own name and is
    /// never given a meaning this app made up.
    func testAScorerThisAppDoesNotKnowIsStillDrawn() throws {
        let file = try EvalFixtures.importedForeign()
        let html = EvalReport.html(file)
        XCTAssertTrue(html.contains("episode_length"))
        XCTAssertNil(EvalReport.scorer(named: "episode_length"))
    }

    func testAnImportedLogSaysSoOnItsOwnPage() throws {
        let html = EvalReport.html(try EvalFixtures.importedForeign())
        XCTAssertTrue(html.contains(EvalReport.escaped(EvalLogFile.importedSaid)))
        XCTAssertTrue(html.contains(EvalReport.escaped(EvalLogFile.foreignSeedSaid)),
                      "a foreign log that had a seed is shown as the file has it")
    }

    // MARK: - spread

    func testSpreadSaysWhatVariedOrThatNothingDid() {
        let flat = EvalReport.spreadSaid([1.0, 1.0, 1.0])
        XCTAssertTrue(flat.contains("deterministic"))
        XCTAssertFalse(flat.lowercased().contains("confidence interval is"),
                       "it denies one rather than reporting one")
        XCTAssertTrue(flat.contains("1.0"))
        let spread = EvalReport.spreadSaid([1.1802, 1.2213, 1.1932])
        XCTAssertTrue(spread.contains("1.1802"))
        XCTAssertTrue(spread.contains("1.2213"))
        XCTAssertTrue(spread.contains("three epochs"))
        XCTAssertFalse(EvalReport.spreadSaid([]).isEmpty)
    }

    // MARK: - the share paragraph

    func testTheShareParagraphKeepsItsFiveRules() throws {
        let file = try EvalFixtures.walkClean()
        let text = EvalReport.shareSentence(file)
        XCTAssertTrue(text.contains("3f8c9ab9b409"), "it always names the plant digest")
        XCTAssertTrue(text.contains("cmd-forward"))
        XCTAssertTrue(text.contains("cmd-sideways"),
                      "the scene a mean would have hidden is a row of its own")
        XCTAssertTrue(text.contains("8 of 8 ended standing"))
        XCTAssertTrue(text.contains("Nothing errored."))
        XCTAssertTrue(text.contains("Microduck Studio 1.1 (58)"))
        XCTAssertFalse(text.contains("\u{2014}"), "no em dash in copy under his name")
        for word in ["trained", "learned", "improved", "training"] {
            XCTAssertFalse(text.lowercased().contains(word), word)
        }
    }

    /// A fourteen cell grid pasted into a chat window has to be a paragraph
    /// rather than a list, and the count it collapses to is still a count of
    /// what the bench said rather than a rank.
    func testAGridSharesAsOneLineRatherThanFourteen() throws {
        let text = EvalReport.shareSentence(try EvalFixtures.stairsMixed())
        XCTAssertTrue(text.contains("14 scenes,"), text)
        XCTAssertTrue(text.contains("met the bench's own criterion"), text)
        XCTAssertFalse(text.contains("cell-050mm"), "no cell gets a line of its own")
        XCTAssertLessThan(text.count, 700, text)
        XCTAssertEqual(EvalReport.sceneListCap, 4,
                       "the three walk commands fit under it and a grid does not")
    }

    /// And under the cap every scene keeps its own line, because that is what
    /// stops a mean hiding the one command the policy cannot do.
    func testThreeCommandsEachKeepTheirOwnLine() throws {
        let text = EvalReport.shareSentence(try EvalFixtures.walkClean())
        for scene in ["cmd-forward", "cmd-sideways", "cmd-turning"] {
            XCTAssertTrue(text.contains(scene), scene)
        }
    }

    func testACancelledRunLeadsWithTheWordCancelled() throws {
        let text = EvalReport.shareSentence(try EvalFixtures.cancelled())
        XCTAssertTrue(text.hasPrefix("Cancelled"), text)
    }

    func testErroredTrialsAreNamedInTheShare() throws {
        let text = EvalReport.shareSentence(try EvalFixtures.walkDiverged())
        XCTAssertTrue(text.contains("2 of 8 trials errored"), text)
        XCTAssertFalse(text.contains("Nothing errored."))
    }

    func testAnImportedLogIsSharedAsSomebodyElsesWork() throws {
        let text = EvalReport.shareSentence(try EvalFixtures.importedForeign())
        XCTAssertTrue(text.contains(EvalReport.passedOnSaid))
        XCTAssertFalse(text.contains("Microduck Studio 1.1"))
    }

    /// L1 in a paragraph: a duck that did nothing scores perfectly, so the
    /// travel is in the same sentence as the success rate rather than further
    /// down the page.
    func testTheShareOfAnInertRunShowsTheTravelBesideTheSuccess() throws {
        let text = EvalReport.shareSentence(try EvalFixtures.walkInert())
        XCTAssertTrue(text.contains("8 of 8 ended standing"))
        XCTAssertTrue(text.contains("0.002 m travelled"), text)
    }

    // MARK: - reproduce

    /// A3: enough to run it again, out of fields the log already carries.
    func testReproduceNamesThePresetThePolicyAndTheWorld() throws {
        let log = try EvalFixtures.workedExample().log
        let said = EvalReport.reproduceSaid(log)
        XCTAssertTrue(said.contains("Walk under a forward command"))
        XCTAssertTrue(said.contains("alpha_walking.onnx@27b1f53d1f26"))
        XCTAssertTrue(said.contains("scene.mjb 3f8c9ab9b409"))
        XCTAssertFalse(said.contains("\u{2014}"))
    }

    /// A log with no plant block still says something true rather than
    /// inventing a world.
    func testReproduceFallsBackToTheIdentityWhenThereIsNoPlantBlock() throws {
        let log = try EvalFixtures.importedForeign().log
        XCTAssertNil(EvalReport.world(log))
        XCTAssertTrue(EvalReport.reproduceSaid(log).contains("mock/cubepick-v0"))
    }

    // MARK: - F3, the stage

    /// The recorded episode, turned into what `DuckStage` already draws, in the
    /// kit, so the app target does no arithmetic.
    func testATraceBecomesAPosePerTickAndATrail() throws {
        let trace = EvalFixtures.trace(drop: 0.12, ticks: 120)
        let clip = EvalStageClip.of(trace)
        XCTAssertEqual(clip.ticks, 120)
        XCTAssertEqual(clip.trail.count, 120)
        XCTAssertEqual(clip.poses.count, 120)
        XCTAssertEqual(clip.dropHeight, 0.12)
        XCTAssertEqual(clip.duration, 119.0 / DuckModel.tickHz, accuracy: 1e-12)
        XCTAssertFalse(clip.wasCapped)
    }

    /// The fourteen policy joints scatter over the fifteen model joints around
    /// the mouth, which is the same map every other reader in this project
    /// uses, and the mouth gets home rather than zero.
    func testTheFourteenPolicyJointsScatterAroundTheMouth() {
        let joints = (0..<DuckModel.policyJointCount).map { 0.01 * Double($0) }
        let tick = DuckBench.Tuned.Tick(root: [1, 2, 3, 1, 0, 0, 0], qvel: [], twist: [],
                                        joints: joints, action: [], command: [])
        let clip = EvalStageClip.of(EvalTrace(ticks: [tick], dropHeight: 0.12, why: nil))
        let angles = clip.pose(at: 0).jointAngles
        XCTAssertEqual(angles.count, DuckModel.jointCount)
        XCTAssertEqual(angles[DuckModel.mouthIndex],
                       DuckModel.homePose[DuckModel.mouthIndex])
        for slot in 0..<DuckModel.policyJointCount {
            XCTAssertEqual(angles[DuckModel.jointOfPolicySlot(slot)], joints[slot], accuracy: 1e-12)
        }
        XCTAssertEqual(clip.pose(at: 0).root.x, 1)
        XCTAssertEqual(clip.pose(at: 0).root.z, 3)
    }

    /// F3's second half. `/tune` answers with a plant name and a digest and no
    /// scene geometry, so drawing the world the app happens to have selected
    /// would put a staircase under an episode that never had one.
    func testTheStageEnvironmentIsBareFloorAndNeverTheSelectedWorld() {
        let clip = EvalStageClip.of(EvalFixtures.trace(drop: 0.12, ticks: 3))
        XCTAssertEqual(clip.environment, DuckIntentClip.Environment.bareFloor)
        XCTAssertTrue(clip.environment.ground)
        XCTAssertFalse(clip.environment.hasProps)
    }

    /// A trace is somebody else's JSON and a playhead is a render loop, so a
    /// short root array and an index past the end both have to be survivable.
    func testAShortRootAndAnIndexPastTheEndAreSurvivable() {
        let tick = DuckBench.Tuned.Tick(root: [1], qvel: [], twist: [],
                                        joints: [], action: [], command: [])
        let clip = EvalStageClip.of(EvalTrace(ticks: [tick], dropHeight: 0.12, why: nil))
        XCTAssertEqual(clip.pose(at: 0).root.x, 1)
        XCTAssertEqual(clip.pose(at: 0).root.z, DuckStance.standingHeight)
        XCTAssertEqual(clip.pose(at: 9_999).root.x, 1)
        XCTAssertEqual(clip.pose(at: -5).root.x, 1)
        let empty = EvalStageClip.of(EvalTrace(ticks: [], dropHeight: 0.12, why: nil))
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.pose(at: 0), DuckStance.home)
    }

    /// A recording that ran into the bench's cap says so, because a clip that
    /// quietly stops before the episode does is a clip somebody would judge on.
    func testACappedRecordingSaysSo() {
        let clip = EvalStageClip.of(EvalFixtures.trace(drop: 0.12, ticks: EvalTrace.cap))
        XCTAssertTrue(clip.wasCapped)
        XCTAssertEqual(EvalTrace.cap, 500)
    }

    /// The real captured `/tune` answer, read through the production reader and
    /// put on the stage, so this path is proved against bytes the Pi sent
    /// rather than against a trace this test made up.
    func testTheCapturedBenchAnswerDrawsOnTheStage() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tune-trace-probe",
                                                  withExtension: "json",
                                                  subdirectory: "Fixtures/bench"))
        let tuned = try DuckBench.readTuned(try Data(contentsOf: url))
        let ticks = try XCTUnwrap(tuned.trace)
        let first = try XCTUnwrap(tuned.perDrop.first)
        let clip = EvalStageClip.of(EvalTrace(ticks: ticks, dropHeight: first.drop,
                                              why: tuned.traceWhy))
        XCTAssertEqual(clip.ticks, ticks.count)
        XCTAssertEqual(clip.poses.first?.jointAngles.count, DuckModel.jointCount)
        XCTAssertEqual(clip.environment, DuckIntentClip.Environment.bareFloor)
        XCTAssertNotEqual(clip.trail.first?.x, clip.trail.last?.x,
                          "a duck that walked went somewhere")

        // THE CAPTION IS THE BENCH'S AND IT REACHES THE SCREEN CAPPED. The
        // sentence the Pi actually sent is longer than a row can hold, which is
        // what `EvalText.foreign` is for; what must never happen is this app
        // writing its own caption over somebody else's recording.
        let why = try XCTUnwrap(clip.why)
        XCTAssertEqual(why, tuned.traceWhy)
        XCTAssertGreaterThan(why.count, EvalText.cap)
        XCTAssertEqual(EvalText.foreign(clip.why)?.count, EvalText.cap)
    }
}
