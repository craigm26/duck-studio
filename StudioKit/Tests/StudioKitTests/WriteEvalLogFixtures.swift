import XCTest
import Crypto
import DuckKit
@testable import StudioKit

/// The runs the rest of the evaluation tests are written against, and the
/// corpus the cross-language gate reads.
///
/// WHY THE FIXTURES ARE BUILT BY THE PRODUCTION WRITER RATHER THAN TYPED OUT.
/// A hand-typed JSON fixture proves that somebody can type JSON. These are
/// produced by `EvalLogFile.written`, which is exactly the path a run on a
/// phone takes, so when `read_eval_log` opens one it has opened the app's own
/// output. The plan's worked example is the first of them for the same reason:
/// its arithmetic was checked by hand, so a fixture that reproduces it is a
/// fixture whose numbers somebody has already verified.
///
/// NOTHING HERE INVENTS A BENCH SENTENCE. `criterion` and `traceWhy` are the
/// strings the Pi answered with on 2026-09-05, copied out of
/// `Fixtures/bench/tune-trace-probe.json`, which is why they carry an em dash
/// and a minus sign this repository's own copy rules forbid: a measurement
/// quoted exactly is not prose written.
enum EvalFixtures {

    static let appVersion = "1.1"
    static let build = "58"

    /// The bench's own criterion, verbatim from the captured `/tune` answer.
    /// U+2014 and U+2212 are in it, and they are the best real escaping
    /// fixture this feature has.
    static let criterion =
        "ends standing: at the last tick the trunk's own up is still up \u{2014} gravity "
      + "projects past \u{2212}0.5 into the body's \u{2212}z, the same test /measure and "
      + "/perform use \u{2014} and the trunk is at least 100 mm above the floor. A duck that "
      + "stood still passes it perfectly, which is why `travelled` is beside it."

    static let traceWhy =
        "the first drop's 100 control ticks, unrounded, asked for with `\"trace\": true`"

    static let plantDigest =
        "3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec78d80dca242547be"

    /// Pollen's six reward terms as the Pi reported them for one episode.
    /// Recorded per trial and never scored.
    static let terms: [String: Double] = [
        "upright": 0.9668626396354579,
        "track_linear_velocity": 0.5627831092346859,
        "track_angular_velocity": 0.443426179896686,
        "pose": 0.7299846029845863,
        "body_ang_vel": 0.5133092643991006,
        "action_rate_l2": 0.15872753057741817,
    ]

    // MARK: - the two ends of a run

    static func health(host: Bool = true) throws -> DuckBench.Health {
        let hostBlock = host
            ? #", "host": {"kind": "desk", "device": "Raspberry Pi 5", "#
              + #""engine": "mujoco 3.1.16, 4 cores", "tickMillis": 3.12}"#
            : ""
        let json = #"{"bench": "duck-bench/5", "plant": "a floor", "plantName": "scene.mjb", "#
                 + #""plantDigest": "\#(plantDigest)", "tickHz": 50, "cores": 4, "#
                 + #""policies": [], "trains": false\#(hostBlock)}"#
        return try DuckBench.readHealth(Data(json.utf8))
    }

    static func embodiment(body: EvalEmbodiment.Body = .networkBench,
                           host: Bool = true) throws -> EvalEmbodiment {
        try EvalEmbodiment.checked(body: body, health: try health(host: host),
                                   address: "100.122.199.6:8770",
                                   answeredRoutes: ["/health", "/reset", "/tune",
                                                    "/climb", "/chase"])
    }

    static let walkingPolicy = EvalPolicy(
        kind: .libraryNetwork, title: "Pollen's walking network",
        identity: .parameters("27b1f53d1f26aa9c4b7e0d1a5f83c2e6d4907b1c3e8f5a2d6b0c9e7f4a1d8b35"),
        benchPolicyName: "alpha_walking.onnx", residualIsIdentity: true)

    static func moment(_ offset: Double) -> Date {
        // 2026-09-05T21:14:07.482911Z, so every fixture's timestamps read as
        // one afternoon rather than as 1970.
        Date(timeIntervalSince1970: 1_788_642_847.482911 + offset)
    }

    // MARK: - a walk task at any axis

    static func walkTask(id: String, name: String, sceneIDs: [String],
                         drops: [Double], reducer: EvalEpochs.Reducer = .median,
                         seconds: Double = EvalTask.walkSeconds) throws -> EvalTask {
        let commands: [String: [DuckBench.Step]] = [
            "cmd-forward": DuckBench.walkingCommand,
            "cmd-sideways": DuckBench.sidewaysCommand,
            "cmd-turning": DuckBench.turningCommand,
        ]
        return try EvalTask.checked(
            id: id, name: name,
            said: "A walk measured from drop heights the network was never tuned on.",
            route: .tune,
            scenes: sceneIDs.map {
                EvalTask.walkScene(id: $0, command: commands[$0] ?? DuckBench.walkingCommand,
                                   seconds: seconds)
            },
            scorers: .walk,
            epochs: try EvalEpochs.drops(drops, reducer: reducer),
            maxSeconds: seconds)
    }

    /// One episode of a walk scene, scored the way `/tune`'s `perDrop` entry
    /// scores it.
    static func walkTrial(sceneID: String, epoch: Int, drop: Double, travelled: Double,
                          net: Double, endHeight: Double, standing: Bool = true,
                          ticks: Int? = nil, traced: Bool = false,
                          verdict: EvalVerdict? = nil) -> EvalTrial {
        var metadata: [String: EvalLogJSON] = [
            EvalMeta.dropMetres: .number(drop),
            EvalMeta.diverged: .bool(false),
            EvalMeta.ranToHorizon: .bool(true),
            EvalMeta.terms: .numbers(terms),
        ]
        if !standing { metadata[EvalMeta.ranToHorizon] = .bool(true) }
        return .scored(sceneID: sceneID, epoch: epoch,
                       scores: [EvalScorer.successAtEnd.name: standing ? 1.0 : 0.0,
                                EvalScorer.travelled.name: travelled,
                                EvalScorer.netDisplacement.name: net,
                                EvalScorer.endHeight.name: endHeight],
                       // Their `success_at_end` reads the termination reason, so
                       // the two can never disagree here: an episode that did
                       // not end standing did not end with their success word.
                       terminationReason: standing ? "success" : "max_steps",
                       ticks: ticks, metadata: metadata,
                       verdict: verdict,
                       trace: traced ? trace(drop: drop, ticks: ticks ?? 300) : nil)
    }

    /// A trajectory of the shape the bench sends. The values move so a stage
    /// drawing it draws a duck going somewhere.
    static func trace(drop: Double, ticks: Int) -> EvalTrace {
        var made: [DuckBench.Tuned.Tick] = []
        made.reserveCapacity(ticks)
        for index in 0..<ticks {
            let time = Double(index) / DuckModel.tickHz
            made.append(DuckBench.Tuned.Tick(
                root: [0.5 * time, 0.01 * time, DuckStance.standingHeight, 1, 0, 0, 0],
                qvel: [0.5, 0.01, 0, 0, 0, 0],
                twist: [0.5, 0.01, 0, 0, 0, 0],
                joints: (0..<DuckModel.policyJointCount).map { 0.01 * Double($0) },
                action: (0..<DuckModel.policyJointCount).map { 0.02 * Double($0) },
                command: [0.5, 0, 0]))
        }
        return EvalTrace(ticks: made, dropHeight: drop, why: traceWhy)
    }

    static func divergedTrial(sceneID: String, epoch: Int, drop: Double) -> EvalTrial {
        .errored(sceneID: sceneID, epoch: epoch,
                 why: "the bench said: it diverged at tick 143, |qvel| went past 200",
                 metadata: [EvalMeta.dropMetres: .number(drop),
                            EvalMeta.diverged: .bool(true),
                            EvalMeta.ranToHorizon: .bool(false)])
    }

    /// A whole walk scene: one trial per drop, the first of them traced,
    /// because the bench answers with a trajectory for the first drop only.
    static func walkScene(_ id: String, task: EvalTask, travelled: [Double],
                          standing: [Bool]? = nil, divergedFrom: Int? = nil,
                          verdict: EvalVerdict? = nil) -> EvalSceneResult {
        let drops = task.epochs.axis.dropValues ?? [0.12]
        var trials: [EvalTrial] = []
        for (index, drop) in drops.enumerated() {
            if let divergedFrom, index >= divergedFrom {
                trials.append(divergedTrial(sceneID: id, epoch: index, drop: drop))
                continue
            }
            let metres = index < travelled.count ? travelled[index] : travelled.last ?? 0
            let upright = standing.map { index < $0.count ? $0[index] : true } ?? true
            trials.append(walkTrial(sceneID: id, epoch: index, drop: drop,
                                    travelled: metres,
                                    net: metres * 1.005,
                                    endHeight: 0.1163 + 0.0002 * Double(index),
                                    standing: upright,
                                    ticks: index == 0 ? 300 : nil,
                                    traced: index == 0,
                                    verdict: index == 0 ? verdict : nil))
        }
        let scene = task.scenes.first { $0.id == id } ?? task.scenes[0]
        return EvalSceneResult(scene: scene, reducer: task.epochs.reducer, trials: trials)
    }

    static func run(task: EvalTask, scenes: [EvalSceneResult], cancelled: Bool = false,
                    haltedBy: String? = nil, seconds: Double = 23.884177) throws -> EvalRun {
        EvalRun(task: task, policy: walkingPolicy, embodiment: try embodiment(),
                startedAt: moment(0), completedAt: moment(seconds),
                scenes: scenes, wasCancelled: cancelled, haltedBy: haltedBy)
    }

    static func file(_ run: EvalRun, runID: String) -> EvalLogFile {
        .written(run, criterion: criterion, appVersion: appVersion, build: build, runID: runID)
    }

    // MARK: - the eleven

    /// §2.2's worked example: one scene, the first three held-out drops,
    /// median, six seconds, one traced trial carrying an operator verdict.
    static func workedExample() throws -> EvalLogFile {
        let task = try walkTask(id: "walk-forward", name: "Walk under a forward command",
                                sceneIDs: ["cmd-forward"],
                                drops: Array(EvalTask.walkDrops.prefix(3)))
        let verdict = EvalVerdict(answer: .yes,
                                  note: "It walks and it drifts a little to the left.")
        let scene = walkScene("cmd-forward", task: task,
                              travelled: [1.1932, 1.2213, 1.1867], verdict: verdict)
        return file(try run(task: task, scenes: [scene]), runID: "4b1e77a2")
    }

    static func walkClean() throws -> EvalLogFile {
        let task = try EvalTask.walkThreeCommands()
        let scenes = [
            walkScene("cmd-forward", task: task, travelled: [1.1932, 1.2213, 1.1867, 1.2044,
                                                             1.1789, 1.1955, 1.2101, 1.1876]),
            walkScene("cmd-sideways", task: task, travelled: [0.0214, 0.0198, 0.0233, 0.0207,
                                                              0.0189, 0.0221, 0.0202, 0.0216]),
            walkScene("cmd-turning", task: task, travelled: [0.2441, 0.2388, 0.2502, 0.2417,
                                                             0.2365, 0.2478, 0.2433, 0.2399]),
        ]
        return file(try run(task: task, scenes: scenes, seconds: 154.201), runID: "0a1b2c3d")
    }

    /// L1 in the corpus: a perfect success rate beside two millimetres of
    /// travel. If the tiles ever stop telling the truth, this is the file that
    /// shows it.
    static func walkInert() throws -> EvalLogFile {
        let task = try EvalTask.walkForwardOnly()
        let scene = walkScene("cmd-forward", task: task,
                              travelled: [0.002, 0.0019, 0.0021, 0.002,
                                          0.0018, 0.0022, 0.002, 0.0021])
        return file(try run(task: task, scenes: [scene], seconds: 51.02), runID: "11aa22bb")
    }

    static func walkDiverged() throws -> EvalLogFile {
        let task = try EvalTask.walkForwardOnly()
        let scene = walkScene("cmd-forward", task: task,
                              travelled: [1.1932, 1.2213, 1.1867, 1.2044, 1.1789, 1.1955],
                              divergedFrom: 6)
        return file(try run(task: task, scenes: [scene], seconds: 44.5), runID: "33cc44dd")
    }

    static func walkVerdict() throws -> EvalLogFile {
        let task = try EvalTask.walkThreeCommands()
        let scenes = [
            walkScene("cmd-forward", task: task,
                      travelled: [1.1932, 1.2213, 1.1867, 1.2044, 1.1789, 1.1955, 1.2101, 1.1876],
                      verdict: EvalVerdict(answer: .yes, note: "Straight and steady.")),
            walkScene("cmd-sideways", task: task,
                      travelled: [0.0214, 0.0198, 0.0233, 0.0207, 0.0189, 0.0221, 0.0202, 0.0216],
                      verdict: EvalVerdict(answer: .no,
                                           note: "It leans and stays where it was dropped.")),
            walkScene("cmd-turning", task: task,
                      travelled: [0.2441, 0.2388, 0.2502, 0.2417, 0.2365, 0.2478, 0.2433, 0.2399],
                      verdict: EvalVerdict(answer: .partial, note: "Turns, then drifts forward.")),
        ]
        return file(try run(task: task, scenes: scenes, seconds: 156.9), runID: "55ee66ff")
    }

    /// The stairs grid: fourteen cells, one epoch each, three of them invalid
    /// and recorded with `epochs: [{}]` rather than `[]`, because a ragged
    /// parallel array is the failure the whole schema half of this feature is
    /// organised around.
    static func stairsMixed() throws -> EvalLogFile {
        let rise = 0.060
        let cells = StairsChallenge.Grid.fallback
        let task = try EvalTask.stairsGrid(cells: cells, rise: rise)
        var scenes: [EvalSceneResult] = []
        for (index, scene) in task.scenes.enumerated() {
            let trial: EvalTrial
            if index % 5 == 4 {
                trial = .errored(sceneID: scene.id, epoch: 0,
                                 why: "the bench said: rise 0.070 is outside this intent's "
                                    + "declared search bounds",
                                 metadata: [EvalMeta.cellInvalid: .bool(true)])
            } else {
                let cleared = index % 3 == 0
                trial = .scored(
                    sceneID: scene.id, epoch: 0,
                    scores: [EvalScorer.successAtEnd.name: cleared ? 1.0 : 0.0,
                             EvalScorer.clearedHonestly.name: cleared ? 1.0 : 0.0,
                             EvalScorer.peakAboveTread.name: 12.4 + Double(index),
                             EvalScorer.maxTorque.name: 0.6405],
                    terminationReason: cleared ? "success" : "max_steps",
                    ticks: nil,
                    metadata: [EvalMeta.tailTicksDeclared: .integer(50)])
            }
            scenes.append(EvalSceneResult(scene: scene, reducer: .mean, trials: [trial]))
        }
        return file(try run(task: task, scenes: scenes, seconds: 61.4), runID: "77aa88bb")
    }

    static func ballGrid() throws -> EvalLogFile {
        let cells = BallChallenge.Grid.fallback
        let task = try EvalTask.ballGrid(cells: cells)
        let scenes = task.scenes.enumerated().map { index, scene -> EvalSceneResult in
            let chased = index % 4 == 0
            let trial = EvalTrial.scored(
                sceneID: scene.id, epoch: 0,
                scores: [EvalScorer.successAtEnd.name: chased ? 1.0 : 0.0,
                         EvalScorer.ballTravel.name: chased ? 412.0 + Double(index) : 0.0,
                         EvalScorer.ballNet.name: chased ? 388.0 + Double(index) : 0.0,
                         EvalScorer.closestApproach.name: chased ? 41.2 : 620.5],
                terminationReason: chased ? "success" : "max_steps",
                ticks: nil, metadata: [:])
            return EvalSceneResult(scene: scene, reducer: .mean, trials: [trial])
        }
        return file(try run(task: task, scenes: scenes, seconds: 96.8), runID: "99cc00dd")
    }

    /// A stopped run: the scene that finished is here, the two that never
    /// started are absent, and the file says cancelled.
    static func cancelled() throws -> EvalLogFile {
        let task = try EvalTask.walkThreeCommands()
        let scenes = [
            walkScene("cmd-forward", task: task,
                      travelled: [1.1932, 1.2213, 1.1867, 1.2044, 1.1789, 1.1955, 1.2101, 1.1876]),
        ]
        return file(try run(task: task, scenes: scenes, cancelled: true, seconds: 52.7),
                    runID: "aabbccdd")
    }

    /// L7: every trial errored, so the run is an error and the file carries
    /// upstream's own wording for it.
    static func allErrored() throws -> EvalLogFile {
        let task = try EvalTask.walkForwardOnly()
        let scene = walkScene("cmd-forward", task: task, travelled: [], divergedFrom: 0)
        return file(try run(task: task, scenes: [scene], seconds: 12.9), runID: "eeff0011")
    }

    /// The file that would catch a writer built on the other JSON type: the
    /// bench's em dash and minus sign, a task name past the slug cap, an
    /// accented letter, an emoji above the BMP, a DEL and a tab, a negative
    /// zero, a tiny exponent and one metric that is not a number at all.
    static func hostileStrings() throws -> EvalLogFile {
        let longName = String(repeating: "long walk ", count: 26)
        let task = try EvalTask.checked(
            id: "hostile",
            name: longName,
            said: "Every escaping case this writer has to get right, in one file.",
            route: .tune,
            scenes: [EvalScene(id: "scene-hostile",
                               instruction: "Caf\u{e9} \u{1F986} tab:\u{9} del:\u{7F} "
                                          + "quote:\" backslash:\\ slash:/ less:<",
                               command: DuckBench.walkingCommand)],
            scorers: .walk,
            epochs: try EvalEpochs.drops([0.12, 0.1215], reducer: .mean),
            maxSeconds: 6.0)
        let trials = [
            EvalTrial.scored(sceneID: "scene-hostile", epoch: 0,
                             scores: [EvalScorer.successAtEnd.name: 1.0,
                                      EvalScorer.travelled.name: -0.0,
                                      EvalScorer.netDisplacement.name: 1e-07,
                                      EvalScorer.endHeight.name: .infinity],
                             terminationReason: "success", ticks: 300,
                             metadata: [EvalMeta.dropMetres: .number(0.12)],
                             trace: trace(drop: 0.12, ticks: 300)),
            EvalTrial.scored(sceneID: "scene-hostile", epoch: 1,
                             scores: [EvalScorer.successAtEnd.name: 1.0,
                                      EvalScorer.travelled.name: -0.0,
                                      EvalScorer.netDisplacement.name: 1e-07,
                                      EvalScorer.endHeight.name: .infinity],
                             terminationReason: "success", ticks: nil,
                             metadata: [EvalMeta.dropMetres: .number(0.1215)]),
        ]
        let scene = EvalSceneResult(scene: task.scenes[0], reducer: .mean, trials: trials)
        return file(try run(task: task, scenes: [scene], seconds: 13.5), runID: "beefcafe")
    }

    /// A log this app did not write, read in through the same door an import
    /// uses. It carries a seed, because a run somewhere else may have had one,
    /// and it names a Python version, because one ran.
    static func importedForeign() throws -> EvalLogFile {
        let spec = EvalLog.Spec(
            task: "cubepick reach",
            policy: "scripted-reach",
            embodiment: "mock/cubepick-v0",
            created: "2026-09-05T18:02:11.104882+00:00",
            inspectRobotsVersion: "0.58.0",
            gitCommit: "9f2c1ab",
            policyConfig: ["action_horizon": .integer(1)],
            embodimentInfo: ["control_hz": .number(30.0)],
            seed: 7, maxSteps: 120, maxSeconds: nil)
        let sample = EvalLog.Sample(
            sceneID: "cube-0",
            status: .success,
            reduced: ["success_at_end": 1.0, "episode_length": 44.0],
            epochs: [["success_at_end": 1.0, "episode_length": 44.0]],
            error: nil,
            instruction: "Reach the cube.",
            sceneMetadata: [:],
            operatorJudgements: [nil], judgementSources: [nil], operatorNotes: [nil],
            operatorMessages: [[]], trialMetadata: [[:]],
            terminationReasons: ["success"], policyTranscripts: [.null])
        let log = EvalLog(status: .success, eval: spec,
                          results: EvalLog.Results(totalScenes: 1, totalTrials: 1,
                                                   metrics: ["success_at_end": 1.0,
                                                             "episode_length": 44.0],
                                                   erroredTrials: 0),
                          stats: EvalLog.Stats(startedAt: "2026-09-05T18:02:11.104882+00:00",
                                               completedAt: "2026-09-05T18:02:13.902114+00:00",
                                               durationSeconds: 2.797232,
                                               totalSteps: 44),
                          samples: [sample], error: nil)
        return try EvalLogFile.imported(log.encoded(), named: "cubepick-reach_1f2e3d4c.json",
                                        runID: "1f2e3d4c")
    }

    /// The whole corpus, in the order it is written, each with the one thing it
    /// proves. The generator writes this list and the manifest names it, so a
    /// fixture added here appears in both without a second edit.
    static func corpus() throws -> [(name: String, proves: String, file: EvalLogFile)] {
        [
            ("walk_worked_example", "the plan's own worked example, produced by the writer",
             try workedExample()),
            ("walk_clean", "three scenes, eight drops each, one traced trial per scene",
             try walkClean()),
            ("walk_inert", "a perfect success rate beside two millimetres of travel",
             try walkInert()),
            ("walk_diverged", "two diverged episodes recorded with the bench's own reason",
             try walkDiverged()),
            ("walk_verdict", "one watched verdict per scene and null for every unwatched trial",
             try walkVerdict()),
            ("stairs_mixed", "fourteen cells, three invalid, epochs [{}] rather than []",
             try stairsMixed()),
            ("ball_grid", "the ball grid through the same shape as the stairs grid",
             try ballGrid()),
            ("cancelled", "a stopped run keeps the scenes that finished",
             try cancelled()),
            ("all_errored", "every trial errored, so the run is an error in their own words",
             try allErrored()),
            ("hostile_strings", "every escaping case, a negative zero and a nulled metric",
             try hostileStrings()),
            ("imported_foreign", "a log written elsewhere, with a seed and a Python version",
             try importedForeign()),
        ]
    }
}

/// Writes the corpus to a directory, for the cross-language gate.
///
/// IT IS A TEST BECAUSE THE TEST TARGET IS THE ONLY THING IN THIS PACKAGE THAT
/// RUNS. There is no executable here and there is not going to be one, so the
/// fixture writer is a test that skips itself unless somebody asks for it by
/// setting `EVALLOG_FIXTURE_DIR`. Skipping loudly rather than writing into a
/// temporary directory is deliberate: a gate that produced files nobody could
/// find would report success and prove nothing.
final class WriteEvalLogFixtures: XCTestCase {

    static let directoryVariable = "EVALLOG_FIXTURE_DIR"

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func testItWritesTheCorpusWhenAskedTo() throws {
        guard let path = ProcessInfo.processInfo.environment[Self.directoryVariable],
              !path.isEmpty else {
            throw XCTSkip("set \(Self.directoryVariable) to a directory to write the evaluation "
                        + "log corpus; it is read by scripts/check_evallog_parity.sh and by "
                        + "inspect-robots itself, and nothing writes it by accident")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var manifest: [String] = [
            "# Evaluation log fixtures, written by WriteEvalLogFixtures.",
            "# Every one of these is the output of EvalLogFile.written or",
            "# EvalLogFile.imported, which is the same path a run on a phone takes.",
            "# name\tbytes\tsha256\twhat it proves",
        ]
        for entry in try EvalFixtures.corpus() {
            let json = entry.file.bytes
            let jsonName = "\(entry.name).json"
            try json.write(to: directory.appendingPathComponent(jsonName))
            let html = Data(EvalReport.html(entry.file).utf8)
            try html.write(to: directory.appendingPathComponent("\(entry.name).html"))
            let card = Data(entry.file.card().utf8)
            try card.write(to: directory.appendingPathComponent("\(entry.name).md"))
            manifest.append("\(jsonName)\t\(json.count)\t\(Self.digest(json))\t\(entry.proves)")
            manifest.append("\(entry.name).html\t\(html.count)\t\(Self.digest(html))\t"
                          + "this app's own report of \(jsonName)")
            manifest.append("\(entry.name).md\t\(card.count)\t\(Self.digest(card))\t"
                          + "the dataset card for \(jsonName)")
        }
        let text = manifest.joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: directory.appendingPathComponent("manifest.txt"))
        XCTAssertEqual(try EvalFixtures.corpus().count, 11)
    }

    /// The corpus builds, every file in it re-encodes to its own bytes through
    /// the value tree, and every one of them opens through this app's own
    /// reader. Runs on every commit, with no directory and no Python, because a
    /// corpus that only compiles when somebody asks for it is a corpus that
    /// rots.
    ///
    /// THE BYTE CLAIM IS MADE OVER THE VALUE TREE AND NOT OVER THE TYPED LOG,
    /// and `hostile_strings` is why. It carries a metric that is not a number,
    /// which the writer nulls the way `json_log._sanitize` does; the typed
    /// reader cannot hold that null in a `[String: Double]`, so the key is
    /// absent from the log it reads back. The file is right and the round trip
    /// through the strong type is lossy in exactly that one place, which
    /// `EvalLogReaderTests` states out loud rather than leaving here.
    func testTheCorpusBuildsAndReadsBackHere() throws {
        for entry in try EvalFixtures.corpus() {
            let tree = try EvalLogJSON.parse(entry.file.bytes)
            XCTAssertEqual(tree.encoded(), entry.file.bytes,
                           "\(entry.name) does not re-encode to its own bytes")
            let read = try EvalLogReader.read(entry.file.bytes)
            XCTAssertEqual(read.status, entry.file.log.status, entry.name)
            XCTAssertEqual(read.samples.count, entry.file.log.samples.count, entry.name)
            if entry.file.log.results.metrics.values.allSatisfy({ $0.isFinite }) {
                XCTAssertEqual(read, entry.file.log, entry.name)
            }
            XCTAssertFalse(EvalReport.html(entry.file).isEmpty, entry.name)
            XCTAssertFalse(entry.file.card().isEmpty, entry.name)
        }
    }

    /// The names are the filenames, so a duplicate would silently overwrite a
    /// fixture and the gate would go on passing over one file fewer.
    func testEveryFixtureHasItsOwnName() throws {
        let names = try EvalFixtures.corpus().map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }
}
