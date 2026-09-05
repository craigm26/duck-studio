import XCTest
@testable import StudioKit

/// The writer: the file's name, its timestamps, and every field of the log a
/// finished run turns into.
final class EvalLogWriterTests: XCTestCase {

    // MARK: - the slug, character for character

    /// `json_log._slug` is `_SLUG_RE.sub("-", name.lower()).strip("-")[:200].strip("-") or "eval"`,
    /// and every row below was run through that regex in the venv this session
    /// rather than reasoned about.
    func testTheSlugIsTheirSlug() {
        XCTAssertEqual(EvalLogWriter.slug("Walk under a forward command"),
                       "walk-under-a-forward-command")
        XCTAssertEqual(EvalLogWriter.slug("Stairs challenge grid"), "stairs-challenge-grid")
        XCTAssertEqual(EvalLogWriter.slug("  "), "eval", "nothing left means eval")
        XCTAssertEqual(EvalLogWriter.slug(""), "eval")
        XCTAssertEqual(EvalLogWriter.slug("!!!"), "eval")
        XCTAssertEqual(EvalLogWriter.slug("A  B"), "a-b", "a run of anything is one hyphen")
        XCTAssertEqual(EvalLogWriter.slug("--lead and trail--"), "lead-and-trail")
        XCTAssertEqual(EvalLogWriter.slug("v1.2/3"), "v1-2-3")
        // Measured in the venv: "Ünder the Bridge!!" is 'nder-the-bridge', because
        // the accented letter is outside [a-z0-9] after lowering and the leading
        // separator is stripped.
        XCTAssertEqual(EvalLogWriter.slug("\u{DC}nder the Bridge!!"), "nder-the-bridge")
    }

    func testTheSlugIsCappedAtTwoHundredAndStrippedAfterwards() {
        XCTAssertEqual(EvalLogWriter.slugCap, 200)
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(EvalLogWriter.slug(long).count, 200)
        // A cap that landed on a hyphen would leave a trailing one, which their
        // second strip removes and so does this.
        let ending = String(repeating: "ab ", count: 100)
        let slug = EvalLogWriter.slug(ending)
        XCTAssertLessThanOrEqual(slug.count, 200)
        XCTAssertFalse(slug.hasSuffix("-"))
    }

    // MARK: - the filename

    func testTheFilenameIsTheirsAndTheReportSharesItsStem() {
        let name = EvalLogWriter.filename(task: "Walk under a forward command",
                                          runID: "4b1e77a2")
        XCTAssertEqual(name, "walk-under-a-forward-command_4b1e77a2.json")
        XCTAssertEqual(EvalLogWriter.htmlFilename(task: "Walk under a forward command",
                                                  runID: "4b1e77a2"),
                       "walk-under-a-forward-command_4b1e77a2.html")
    }

    func testARunIDIsEightLowerCaseHex() {
        let id = EvalLogWriter.runID()
        XCTAssertEqual(id.count, 8)
        XCTAssertTrue(id.allSatisfy { "0123456789abcdef".contains($0) }, id)
        XCTAssertNotEqual(EvalLogWriter.runID(), EvalLogWriter.runID(),
                          "two runs in one afternoon must not overwrite each other")
    }

    // MARK: - the timestamp

    /// `datetime.now(UTC).isoformat()`, checked against values printed by the
    /// venv this session.
    func testTheTimestampIsPythonsIsoformat() {
        XCTAssertEqual(EvalLogWriter.timestamp(Date(timeIntervalSince1970: 1_788_642_847.482911)),
                       "2026-09-05T21:14:07.482911+00:00")
        XCTAssertEqual(EvalLogWriter.timestamp(Date(timeIntervalSince1970: 0)),
                       "1970-01-01T00:00:00+00:00",
                       "Python omits the fraction when the microseconds are zero")
        XCTAssertEqual(EvalLogWriter.timestamp(Date(timeIntervalSince1970: 1)),
                       "1970-01-01T00:00:01+00:00")
    }

    /// A fraction that rounds to a whole million must carry the second rather
    /// than write `.1000000`, which is not a timestamp anybody's parser reads.
    func testAFractionThatRoundsUpCarriesTheSecond() {
        let stamp = EvalLogWriter.timestamp(Date(timeIntervalSince1970: 0.9999999))
        XCTAssertEqual(stamp, "1970-01-01T00:00:01+00:00")
    }

    // MARK: - the log a run becomes

    func testEveryTopLevelFieldComesOffTheRun() throws {
        let file = try EvalFixtures.workedExample()
        let log = file.log
        XCTAssertEqual(log.version, 1)
        XCTAssertEqual(log.status, .success)
        XCTAssertEqual(log.eval.task, "Walk under a forward command")
        XCTAssertEqual(log.eval.policy, "alpha_walking.onnx@27b1f53d1f26")
        XCTAssertEqual(log.eval.embodiment, "network-bench/duck-bench-5/scene.mjb@3f8c9ab9b409")
        XCTAssertEqual(log.eval.created, log.stats.startedAt,
                       "their own writer's created is the run's start")
        XCTAssertEqual(log.results.totalScenes, 1)
        XCTAssertEqual(log.results.totalTrials, 3)
        XCTAssertEqual(log.results.erroredTrials, 0)
        XCTAssertEqual(log.samples.count, 1)
    }

    /// L4, L10 and no `git_commit`: four fields this app writes as null on
    /// purpose, and a test that would go red the day one of them acquires a
    /// value nobody measured.
    func testTheFourFieldsThisAppRefusesToFillIn() throws {
        let log = try EvalFixtures.workedExample().log
        XCTAssertNil(log.eval.seed)
        XCTAssertNil(log.eval.gitCommit)
        XCTAssertNil(log.stats.meanInferenceLatencySeconds)
        XCTAssertNil(log.stats.framesDir)
    }

    /// L9. `total_steps` is the traced episode and nothing else: three trials
    /// ran and one reported ticks.
    func testTotalStepsCountsOnlyReportedTicks() throws {
        let log = try EvalFixtures.workedExample().log
        XCTAssertEqual(log.stats.totalSteps, 300)
        XCTAssertEqual(log.results.totalTrials, 3, "and it is not trials times a rate")
        let reported = log.samples[0].trialMetadata
            .compactMap { $0[EvalMeta.ticksReported]?.integerValue }
        XCTAssertEqual(reported, [300])
    }

    /// L11. Their own report prints this field verbatim in its footer, so it
    /// has to be a sentence rather than a version number.
    func testTheProducerFieldNamesUsAndDeniesThem() throws {
        let log = try EvalFixtures.workedExample().log
        XCTAssertTrue(log.eval.inspectRobotsVersion.contains("Microduck Studio 1.1 (58)"))
        XCTAssertTrue(log.eval.inspectRobotsVersion.contains("No inspect-robots ran"))
    }

    /// L2. The digest is INSIDE the identity, so two runs against two worlds
    /// cannot read as one on anybody's report.
    func testThePlantDigestIsInsideTheEmbodimentIdentity() throws {
        let log = try EvalFixtures.workedExample().log
        XCTAssertTrue(log.eval.embodiment.contains("3f8c9ab9b409"))
        XCTAssertEqual(log.eval.embodimentInfo[EvalMeta.plantDigest]?.stringValue,
                       EvalFixtures.plantDigest, "and the whole digest is beside it")
    }

    /// V11 and L4: five of their six capability words, and never `seedable`.
    func testCapabilitiesAreTheirWordsAndNeverSeedable() throws {
        let log = try EvalFixtures.workedExample().log
        let words = (log.eval.embodimentInfo["capabilities"]?.arrayValue ?? [])
            .compactMap(\.stringValue)
        XCTAssertEqual(words, ["auto_reset", "privileged_success", "renderable",
                               "resettable", "self_paced"])
        XCTAssertFalse(words.contains("seedable"))
    }

    /// `renderable` is a fact about the run, not about the bench: a run that
    /// got no trajectory has nothing to render.
    func testRenderableIsOnlyClaimedWhenATraceCameBack() throws {
        let grid = try EvalFixtures.stairsMixed().log
        let words = (grid.eval.embodimentInfo["capabilities"]?.arrayValue ?? [])
            .compactMap(\.stringValue)
        XCTAssertFalse(words.contains("renderable"), "no /climb trial has a trajectory")
        XCTAssertTrue(words.contains("auto_reset"))
    }

    /// The criterion is the bench's, carried through unrounded and unreworded,
    /// which is why an evaluation log can hold characters this repository's own
    /// copy rules forbid.
    func testTheCriterionIsCarriedVerbatim() throws {
        let log = try EvalFixtures.workedExample().log
        XCTAssertEqual(log.eval.policyConfig[EvalMeta.criterion]?.stringValue,
                       EvalFixtures.criterion)
        XCTAssertTrue(EvalFixtures.criterion.contains("\u{2014}"))
        XCTAssertTrue(EvalFixtures.criterion.contains("\u{2212}"))
    }

    /// V6: `policy_config` is what their viewer renders, so it holds every
    /// sentence a stranger must read, and the three of their own fields that
    /// give it their reference log's shape.
    func testThePolicyConfigCarriesTheirThreeFieldsAndOurEight() throws {
        let log = try EvalFixtures.workedExample().log
        XCTAssertEqual(Set(log.eval.policyConfig.keys),
                       ["action_horizon", "bench_host", "bench_world", EvalMeta.criterion,
                        EvalMeta.epochAxis, "replan_interval", "residual", "seed_note",
                        "step_counts", "temperature", "trace_note"])
        XCTAssertEqual(log.eval.policyConfig["action_horizon"]?.integerValue, 1)
        XCTAssertTrue(log.eval.policyConfig["replan_interval"]?.isNull ?? false)
        XCTAssertTrue(log.eval.policyConfig["temperature"]?.isNull ?? false)
    }

    /// E6: the axis is written as numbers as well as prose, so an archived log
    /// goes on meaning what it meant if the tuner's held-out list ever changes.
    func testTheEpochAxisIsWrittenAsNumbersAndNotOnlyAsProse() throws {
        let log = try EvalFixtures.workedExample().log
        let drops = EvalReport.drops(log.samples[0])
        XCTAssertEqual(drops, Array(EvalTask.walkDrops.prefix(3)))
        XCTAssertEqual(drops.count, 3)
    }

    // MARK: - the eight parallel arrays

    /// L19. Ragged arrays would file one trial's verdict against another
    /// trial's score, and their reader would not notice.
    func testTheEightParallelArraysAreAllTheSameLength() throws {
        for entry in try EvalFixtures.corpus() {
            for sample in entry.file.log.samples {
                let lengths = sample.parallelLengths
                XCTAssertEqual(Set(lengths.values).count, 1,
                               "\(entry.name)/\(sample.sceneID): \(lengths)")
                XCTAssertEqual(lengths[EvalLog.Key.epochs], sample.epochs.count)
            }
        }
    }

    /// The shape the winning design got wrong: an errored trial is `{}` in
    /// `epochs`, never a missing entry.
    func testAnErroredTrialIsAnEmptyEpochRatherThanAnAbsentOne() throws {
        let log = try EvalFixtures.stairsMixed().log
        let invalid = try XCTUnwrap(log.samples.first { $0.status == .error })
        XCTAssertEqual(invalid.epochs, [[:]])
        XCTAssertEqual(invalid.terminationReasons, [nil])
        XCTAssertEqual(invalid.operatorMessages, [[]])
        XCTAssertNotNil(invalid.error)
    }

    /// Each trial's own reason survives, because their schema has one error per
    /// scene and a walk scene can have two failures with different causes.
    func testEveryDivergedTrialKeepsItsOwnReason() throws {
        let log = try EvalFixtures.walkDiverged().log
        let sample = log.samples[0]
        let reasons = sample.trialMetadata.compactMap { $0[EvalMeta.why]?.stringValue }
        XCTAssertEqual(reasons.count, 2)
        XCTAssertTrue(reasons.allSatisfy { $0.contains("diverged") })
        XCTAssertEqual(sample.error, reasons.first,
                       "and the first is promoted so the scene row is not blank")
        XCTAssertEqual(log.status, .success,
                       "two failures out of eight is data about the policy")
    }

    /// L21 and the shape of a watched trial: a verdict on the traced trial and
    /// null everywhere else, in three arrays at once.
    func testAVerdictSitsOnlyOnTheTrialSomebodyCouldWatch() throws {
        let log = try EvalFixtures.walkVerdict().log
        for sample in log.samples {
            XCTAssertEqual(sample.operatorJudgements.filter { $0 != nil }.count, 1)
            XCTAssertEqual(sample.judgementSources.compactMap { $0 }, ["prompt"])
            XCTAssertEqual(sample.operatorNotes.filter { $0 != nil }.count, 1)
            XCTAssertNotNil(sample.operatorJudgements.first ?? nil,
                            "and it is the first trial, which is the traced one")
        }
    }

    // MARK: - the statuses

    func testACancelledRunKeepsWhatRanAndSaysItWasStopped() throws {
        let log = try EvalFixtures.cancelled().log
        XCTAssertEqual(log.status, .cancelled)
        XCTAssertEqual(log.samples.count, 1, "the scenes that never started are absent")
        XCTAssertEqual(log.results.totalTrials, 8)
        XCTAssertNil(log.error, "stopping is not a fault")
    }

    /// L7, in upstream's own wording.
    func testARunWhereEveryTrialErroredIsAnErrorInTheirWords() throws {
        let log = try EvalFixtures.allErrored().log
        XCTAssertEqual(log.status, .error)
        XCTAssertEqual(log.results.metrics, [:])
        XCTAssertEqual(log.results.erroredTrials, log.results.totalTrials)
        XCTAssertEqual(log.error, "all 8 trial(s) errored; nothing was scored")
    }

    // MARK: - the bytes

    /// The gate that needs nothing: every fixture re-encodes to itself.
    func testEveryFixtureReEncodesToItsOwnBytes() throws {
        for entry in try EvalFixtures.corpus() {
            let tree = try EvalLogJSON.parse(entry.file.bytes)
            XCTAssertEqual(tree.encoded(), entry.file.bytes, entry.name)
            XCTAssertNotEqual(entry.file.bytes.last, UInt8(ascii: "\n"),
                              "\(entry.name) has a trailing newline theirs does not")
        }
    }

    /// L5 on the writing side: a metric that is not a number becomes null,
    /// exactly as `json_log._sanitize` makes it, and the scorer's name comes
    /// back out of the run so a screen can say which one.
    func testANonFiniteMetricIsNulledAndItsNameIsKept() throws {
        let file = try EvalFixtures.hostileStrings()
        let text = String(data: file.bytes, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"end_height_m\": null"), text.prefix(400).description)
        // The two tokens `json.dump` would have written with `allow_nan` left
        // on, and which no RFC 8259 parser accepts. Matched with the colon and
        // the space in front so `mean_inference_latency_s` does not count as an
        // infinity, which is exactly the kind of substring hit this repository
        // has already shipped once.
        XCTAssertFalse(text.contains(": Infinity"))
        XCTAssertFalse(text.contains(": -Infinity"))
        XCTAssertFalse(text.contains(": NaN"))
        XCTAssertEqual(file.log.results.metrics[EvalScorer.endHeight.name]?.isFinite, false,
                       "the run still knows which scorer produced it")
    }

    func testAFileIsNamedFromTheTaskAndItsReportSharesTheStem() throws {
        let file = try EvalFixtures.workedExample()
        XCTAssertEqual(file.name, "walk-under-a-forward-command_4b1e77a2.json")
        XCTAssertEqual(file.htmlName, "walk-under-a-forward-command_4b1e77a2.html")
        XCTAssertEqual(file.origin, .written)
        XCTAssertEqual(file.wroteIt, "Microduck Studio 1.1 (58)")
    }
}
