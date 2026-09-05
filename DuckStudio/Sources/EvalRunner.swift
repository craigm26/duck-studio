import SwiftUI
import DuckKit
import StudioKit

/// The four whole plans this screen can run.
///
/// A PRESET IS A PLAN AND NOT A STARTING POINT. Picking one fills the task, the
/// scenes, the epoch axis, the reducer, the horizon and the scorers, so the
/// only thing left to choose is what is being evaluated. That is why there is
/// no reducer picker and no epoch count anywhere: `EvalTask`'s four factories
/// own those, each with a `said` a test reads, and a control that could
/// disagree with them would be a second opinion about what a preset means.
enum EvalPreset: String, CaseIterable, Identifiable {
    case walkThreeCommands
    case walkForwardOnly
    case stairsGrid
    case ballGrid

    var id: String { rawValue }

    var route: EvalTask.Route {
        switch self {
        case .walkThreeCommands, .walkForwardOnly: return .tune
        case .stairsGrid: return .climb
        case .ballGrid: return .chase
        }
    }

    /// Whether what is being evaluated is a network from the library. The two
    /// grids score a published challenge entrant, which is a move or a network
    /// under a schedule, and neither is picked out of the policy list.
    var evaluatesANetwork: Bool { route == .tune }
}

/// One entrant a grid preset can be run with: a published challenge row, and
/// the file behind it, already loaded.
///
/// LOADED ONCE AND UP FRONT, so a row that cannot be opened is never offered.
/// The alternative is a picker that lists nineteen rows and refuses four of
/// them after Start, which is the dead-end this whole screen is arranged to
/// avoid.
struct EvalEntrant: Identifiable {
    enum Body {
        case stairs(StairsChallenge.Move)
        case ball(BallChallenge.Entrant)
    }
    let file: String
    let title: String
    let body: Body
    var id: String { file }
}

/// One evaluation, run over the bench routes the app already speaks.
///
/// MODELLED ON `StairsRun`, WHICH IS THE SHAPE THAT WORKS. Probe first, and
/// draw no Start button while `probing` or before `hasProbed`, so a control is
/// never offered before the bench has said what it can do or while it is being
/// asked again; one request at a time and never in parallel, because the bench
/// serialises anyway and parallel answers arrive in an order that makes a
/// progress row a lie; a `notYet` carrying the bench's own words for a bench
/// that lacks the route, and a separate `unreachable` for a bench that did not
/// answer at all. Those two are different facts and reporting one as the other
/// tells somebody their bench is broken when it is merely older.
///
/// IT IS `EvalRunner` AND NOT `EvalRun`. `EvalRun` is the kit's finished value
/// type, the one every derived number is read off; this is the machine that
/// produces one. Two things with one name is how a screen ends up computing a
/// metric the kit already knows.
///
/// NOTHING HERE COMPUTES A RESULT. Every score is a number the bench sent,
/// filed under the scorer name the kit spelled; every reduction, mean, status
/// and count is `EvalRun`'s. The one judgement this file makes is which of the
/// bench's fields answers which scorer, and each of those is a line with the
/// scorer's own `said` quoted above it.
///
/// WHAT `EvalRunView` IS EXPECTED TO CALL, so the two halves of this feature
/// meet at a written-down contract rather than at a guess:
///
///     EvalRunView(runner: EvalRunner, evals: EvalStore)
///     runner.stop()                     the Stop button
///     runner.record(_ verdict:)         the verdict sheet's three answers
///     runner.skipJudging()              Skip this one, Stop watching
///     runner.judgeable                  the trial the sheet is about, or nil
///     runner.finishedFile               the log, once there is one
///     runner.somebodyIsWatching()       that screen appeared
///     runner.nobodyIsWatching()         that screen went away
///
/// The log is filed by the runner itself the moment there is nothing left to
/// judge, because `EvalLogFile.aLogIsFinished` says a log is finished when the
/// run is and a screen that had to remember to save one would eventually not.
///
/// AND THE RUNNER OUTLIVES BOTH SCREENS. It is a `@StateObject` on the app,
/// beside the shelf it files into, because it was one on the setup screen and a
/// run therefore died with a view somebody could pop: the bench went on working
/// with no Stop anywhere, and a run that was still asking for verdicts could
/// never file its log. The last two calls above are how it knows whether
/// anything can answer a verdict.
@MainActor
final class EvalRunner: ObservableObject {

    // MARK: - what is being set up

    @Published var preset: EvalPreset = .walkThreeCommands
    /// `PolicyLibrary.Entry.id`, for the two walk presets.
    @Published var policyID: String?
    /// A published challenge row's file, for the two grid presets.
    @Published var entrantFile: String?
    /// The rise the stairs grid is scored at. The published rows were measured
    /// at `StairsChallenge.defaultRise`.
    @Published var rise: Double = StairsChallenge.defaultRise
    /// Whether the one watchable trial of each scene gets a verdict offered.
    @Published var wantsVerdicts = false

    // MARK: - what the bench said

    @Published private(set) var probing = false
    /// True once the bench has answered at least one probe, so no Start button
    /// is drawn before we know whether this bench can run anything.
    @Published private(set) var hasProbed = false
    @Published private(set) var embodiment: EvalEmbodiment?
    /// The bench did not answer at all, in the transport's own words.
    @Published private(set) var unreachable: String?
    /// The bench answered and cannot run this task, in its own words or in the
    /// kit's sentence for the case.
    @Published private(set) var notYet: String?
    /// Why an embodiment could not be built at all: a bench that will not name
    /// the bytes its world was compiled from.
    @Published private(set) var embodimentRefusal: String?

    @Published private(set) var stairsCells: [DuckBench.Cell] = StairsChallenge.Grid.fallback
    @Published private(set) var stairsIsFallback = true
    @Published private(set) var ballCells: [DuckBench.ChaseCell] = BallChallenge.Grid.fallback
    @Published private(set) var ballIsFallback = true

    // MARK: - the task the preset built

    @Published private(set) var task: EvalTask?
    /// The other three, so a picker can name them in their own words.
    @Published private(set) var catalogue: [EvalPreset: EvalTask] = [:]
    /// Why the preset could not be turned into a task, in the kit's words.
    @Published private(set) var taskRefusal: String?

    // MARK: - the run

    @Published private(set) var running = false
    @Published private(set) var stopped = false
    /// Scenes finished and scenes to do, kept as two numbers so a progress bar
    /// is handed both and no share is computed here.
    @Published private(set) var scenesDone = 0
    @Published private(set) var scenesTotal = 0
    @Published private(set) var scenes: [EvalSceneResult] = []
    /// The scene being run, for the row that says where the run has got to.
    @Published private(set) var currentScene: EvalScene?
    /// Whatever stopped the whole run, in the refusal's own words.
    @Published private(set) var failure: String?
    /// The finished log, once there is one.
    @Published private(set) var finishedFile: EvalLogFile?

    /// The facts captured at Start and never read back, which is the fix
    /// `StairsRun.scoredBenchName` already documents: the bench is chosen on
    /// another tab, and a log assembled from `benches.selected` at the end
    /// would name whichever bench was selected then.
    @Published private(set) var ranOnBench: String?
    @Published private(set) var ranOnAddress: String?

    /// The bench's own sentence for what it scored, read off the wire and
    /// never authored here. Nil until an answer has carried one.
    private var criterion: String?
    /// True once the loop has stopped, whatever stopped it. The log is filed
    /// only after this, because a verdict answered while scenes are still
    /// arriving must not close the run early.
    private var loopEnded = false
    /// What stopped the whole run, kept here rather than passed around, so a
    /// halt that lands while somebody is still judging is not lost between the
    /// loop and the file.
    private var haltedBy: String?
    /// What this bench would not compute, by name and with its reason.
    private var refusedTerms: [(name: String, why: String)] = []
    /// The tail the first answered cell reported. A later cell with a
    /// different one is a different measurement, and L18 says so.
    private var declaredTail: Int?

    private var startedAt = Date()
    private var chosenPolicy: EvalPolicy?
    private var chosenEmbodiment: EvalEmbodiment?
    /// The task as it was at Start, captured for the same reason the policy and
    /// the embodiment are: the log has to be assembled from what the run
    /// actually used. `task` is rebuilt whenever a preset changes or a probe
    /// answers, and a rebuild that failed left the finished run with no task at
    /// all, which is a run that ended with neither a log nor a sentence.
    private var chosenTask: EvalTask?
    private var store: EvalStore?

    /// Whether a screen is on hand to put a verdict sheet in front of somebody.
    ///
    /// A QUEUE NOBODY CAN ANSWER IS A LOG NOBODY GETS. The log is filed when
    /// there is nothing left to judge, and the three things that empty the
    /// queue are all buttons on a sheet the run screen presents. With that
    /// screen gone the queue could only grow, so the run ended with its
    /// measurements in memory and nothing on the shelf. Trials queued while
    /// nobody is watching are simply not queued: a trial nobody judged carries
    /// no verdict, which is what `null` in their three parallel arrays already
    /// means.
    private var watching = false

    // MARK: - the verdict queue

    /// The traced trials still waiting for a verdict, oldest first. Empty
    /// unless verdicts were asked for.
    @Published private(set) var awaitingVerdict: [EvalTrialAddress] = []

    /// The trial the verdict sheet is about, with the scene it belongs to.
    var judgeable: (scene: EvalScene, trial: EvalTrial)? {
        guard let address = awaitingVerdict.first,
              let scene = scenes.first(where: { $0.scene.id == address.sceneID }),
              let trial = scene.trials.first(where: { $0.epoch == address.epoch })
        else { return nil }
        return (scene.scene, trial)
    }

    /// Which trial a verdict belongs to. A pair rather than an index, because
    /// an index into an array that is still growing is how a verdict lands
    /// against another trial's score.
    struct EvalTrialAddress: Equatable {
        let sceneID: String
        let epoch: Int
    }

    // MARK: - the preset

    /// Every entrant a grid preset can run, loaded from the bundle.
    @Published private(set) var stairsEntrants: [EvalEntrant] = []
    @Published private(set) var ballEntrants: [EvalEntrant] = []

    init() {
        rebuildTask()
    }

    /// The bundle reading this runner needs, done when a screen that can use it
    /// appears rather than at launch.
    ///
    /// IT IS OWNED AS HIGH AS THE SHELF NOW, WHICH IS WHY THIS IS NOT IN
    /// `init`. Decoding every published entrant of both challenges is thirty
    /// files, and doing it while the first tab is drawing would spend that on
    /// every launch for a screen most launches never open. Called from the
    /// setup screen's `.task`, and idempotent, because a `.task` runs again
    /// every time that screen comes back.
    func prepare() {
        guard stairsEntrants.isEmpty, ballEntrants.isEmpty else { return }
        loadEntrants()
        rebuildTask()
    }

    /// The published rows whose file this build actually carries.
    ///
    /// A ROW WHOSE MOVE WILL NOT LOAD IS NOT OFFERED. It is not a refusal worth
    /// a sentence: a leaderboard row this app has no copy of is a row about
    /// somebody else's file, and listing it would be offering to run something
    /// that is not here.
    private func loadEntrants() {
        stairsEntrants = StairsChallenge.leaderboard.compactMap { row in
            guard let move = try? StairsChallenge.move(for: row) else { return nil }
            return EvalEntrant(file: row.file, title: row.moveName, body: .stairs(move))
        }
        ballEntrants = BallChallenge.leaderboard.compactMap { row in
            guard let data = BallChallenge.Entrants.data(row.file),
                  let entrant = try? BallChallenge.Entrant.decode(data) else { return nil }
            return EvalEntrant(file: row.file, title: row.entrantName, body: .ball(entrant))
        }
    }

    var entrants: [EvalEntrant] {
        preset.evaluatesANetwork ? [] : (preset == .stairsGrid ? stairsEntrants : ballEntrants)
    }

    var entrant: EvalEntrant? {
        entrants.first { $0.file == entrantFile } ?? entrants.first
    }

    /// Every preset as the task it is, inside a `do`/`catch` because every
    /// factory in the kit throws and a `View` that called one in a property
    /// initialiser would be a screen that cannot be built.
    ///
    /// ALL FOUR, AND NOT ONLY THE CHOSEN ONE. A picker has to name the three
    /// it is not showing, and the only honest name for a preset is the `name`
    /// its own task carries: a title typed into the picker would be a fifth
    /// description of four things that already describe themselves.
    func rebuildTask() {
        var built: [EvalPreset: EvalTask] = [:]
        var refusal: String?
        for candidate in EvalPreset.allCases {
            do {
                built[candidate] = try make(candidate)
            } catch {
                if candidate == preset { refusal = EvalMessage.of(error) }
            }
        }
        catalogue = built
        task = built[preset]
        taskRefusal = refusal
    }

    private func make(_ preset: EvalPreset) throws -> EvalTask {
        switch preset {
        case .walkThreeCommands: return try EvalTask.walkThreeCommands()
        case .walkForwardOnly:   return try EvalTask.walkForwardOnly()
        case .stairsGrid:        return try EvalTask.stairsGrid(cells: stairsCells, rise: rise)
        case .ballGrid:          return try EvalTask.ballGrid(cells: ballCells)
        }
    }

    /// The synchronous half of picking a preset: everything a control has to
    /// see change on the frame it was tapped.
    ///
    /// THE ENTRANT MOVES WITH THE PRESET. The two grids have different lists,
    /// and a selection left pointing at the other one's file is a `Picker` with
    /// nothing selected while `entrant` quietly answers with the first row: the
    /// screen and the run would then disagree about what is being evaluated.
    func settle(on preset: EvalPreset) {
        self.preset = preset
        if !preset.evaluatesANetwork,
           !entrants.contains(where: { $0.file == entrantFile }) {
            entrantFile = entrants.first?.file
        }
        rebuildTask()
    }

    /// Called when the preset changes, which is also when the grid it needs
    /// has to be asked for.
    ///
    /// NOT WHILE A RUN IS GOING. Every picker on the setup screen disables
    /// itself during a run, so this cannot be reached by hand; the guard is
    /// here because `settle` reassigns the task the run is being filed against
    /// and a second way in would be a run that changed its own plan halfway.
    func choose(_ preset: EvalPreset, benches: BenchStore) async {
        guard !running else { return }
        settle(on: preset)
        await probe(benches: benches)
    }

    // MARK: - asking the bench what it can do

    /// `/health` first, then whatever the chosen preset's route needs.
    ///
    /// `/health` IS THE ONE THAT MUST HAPPEN, because it carries the plant name
    /// and the digest, and `EvalEmbodiment.checked` refuses a bench that will
    /// not name the bytes its world was built from. Refusing that in front of
    /// the Start button costs a sentence; refusing it at the writer costs the
    /// minutes the run already spent.
    ///
    /// NEVER WHILE A RUN IS GOING, which is what this file's own header
    /// promises the bench: one request at a time and never in parallel. The
    /// setup screen's `.task` re-runs whenever that screen reappears, which is
    /// what backing out of the run screen does, and a probe there sent a real
    /// one second episode at the address the scene loop was using, nulled the
    /// embodiment the run reports from, and rebuilt the task the log is filed
    /// against, while the measurement was still in flight.
    func probe(benches: BenchStore) async {
        guard !running else { return }
        probing = true
        defer { probing = false; hasProbed = true }
        unreachable = nil
        notYet = nil
        embodimentRefusal = nil
        embodiment = nil

        guard let bench = benches.selected else {
            unreachable = EvalMessage.of(DuckBench.Refusal.empty)
            return
        }
        let address: DuckBench.Address
        let token: String?
        let health: DuckBench.Health
        do {
            (address, token) = try Self.armed(benches)
            health = try DuckBench.readHealth(
                await Self.ask(DuckBench.health(address), token: token,
                               seconds: EvalRun.probeSeconds))
        } catch {
            // A BENCH THAT DID NOT ANSWER IS NOT A BENCH THAT CANNOT RUN THIS.
            // The phone's own listener comes up a moment after launch, and
            // reporting that as a bench which cannot score would be a claim
            // about a machine nobody has heard from.
            unreachable = bench.isThisPhone ? PhoneBenchReport.notListening
                                            : EvalMessage.of(error)
            return
        }

        let body: EvalEmbodiment.Body = bench.isThisPhone ? .thisPhoneBench : .networkBench
        let routes = await answeredRoutes(address: address, token: token,
                                          health: health, bench: bench.name)
        do {
            embodiment = try EvalEmbodiment.checked(body: body, health: health,
                                                    address: bench.address,
                                                    answeredRoutes: routes)
        } catch {
            embodimentRefusal = EvalMessage.of(error)
        }
        rebuildTask()
    }

    /// What this bench has actually been seen to answer.
    ///
    /// EMPTY MEANS UNASKED AND NOT UNABLE, which is the state
    /// `EvalEmbodiment.refusalBeforeStart` reads as "no route refusal to
    /// make". A grid route is asked with its own grid endpoint, which is cheap
    /// and also answers with the cells; `/tune` has no such endpoint, so it is
    /// asked the way `TuneView` asks it, with one real one-second episode of
    /// the network every bench in this family holds.
    private func answeredRoutes(address: DuckBench.Address, token: String?,
                                health: DuckBench.Health, bench: String) async -> Set<String> {
        switch preset {
        case .walkThreeCommands, .walkForwardOnly:
            do {
                let call = try DuckBench.tune(
                    address, policy: Self.probePolicy,
                    gain: DuckTuner.TuningVector.identity.gain,
                    offset: DuckTuner.TuningVector.identity.offset,
                    seconds: 1, drops: [0.1231], schedule: DuckBench.walkingCommand,
                    terms: DuckTuner.terms.map(\.key))
                _ = try DuckBench.readTuned(
                    await Self.ask(call, token: token,
                                   seconds: EvalRun.callTimeout(seconds: 1, episodes: 1)))
                return [EvalTask.Route.tune.path]
            } catch {
                // The phone bench answers `/tune` and cannot score one, and the
                // kit already has the sentence for that with the numbers in it.
                notYet = health.host?.kind == .phone ? DuckTuner.notYet : EvalMessage.of(error)
                return []
            }

        case .stairsGrid:
            do {
                let answered = try DuckBench.readClimbGrid(
                    await Self.ask(DuckBench.climbGrid(address), token: token,
                                   seconds: EvalRun.probeSeconds))
                stairsCells = answered.cells.isEmpty ? StairsChallenge.Grid.fallback
                                                     : answered.cells
                stairsIsFallback = answered.cells.isEmpty
                if !answered.climbable {
                    notYet = StairsChallenge.noClimbHere(bench: bench)
                    return []
                }
                return [EvalTask.Route.climb.path]
            } catch {
                notYet = StairsChallenge.noClimbHere(bench: bench)
                return []
            }

        case .ballGrid:
            do {
                let answered = try DuckBench.readChaseGrid(
                    await Self.ask(DuckBench.chaseGrid(address), token: token,
                                   seconds: EvalRun.probeSeconds))
                ballCells = answered.cells.isEmpty ? BallChallenge.Grid.fallback : answered.cells
                ballIsFallback = answered.cells.isEmpty
                if !answered.chaseable {
                    notYet = BallChallenge.noChaseHere(bench: bench)
                    return []
                }
                return [EvalTask.Route.chase.path]
            } catch {
                notYet = BallChallenge.noChaseHere(bench: bench)
                return []
            }
        }
    }

    /// The network the `/tune` probe runs, which is the one every bench in this
    /// family holds. A probe against a policy the bench has not got would fail
    /// for the wrong reason and report the wrong verdict.
    private static let probePolicy = "alpha_walking.onnx"

    // MARK: - before Start

    /// Everything that has to be true before a Start button is allowed to be
    /// tapped, as the sentence to draw under the control that is wrong.
    ///
    /// ONE FUNCTION, AND THE KIT ANSWERS MOST OF IT.
    /// `EvalEmbodiment.refusalBeforeStart` is where the bench's own rules live,
    /// so a screen cannot check four of five and offer the combination that
    /// dead-ends on the fifth three minutes later.
    func refusal(policy: EvalPolicy?, bundled: Set<String>) -> String? {
        if let unreachable { return unreachable }
        if let notYet { return notYet }
        if let embodimentRefusal { return embodimentRefusal }
        if let taskRefusal { return taskRefusal }
        guard let task else { return nil }
        guard let embodiment else { return nil }
        guard let policy else { return nil }
        return embodiment.refusalBeforeStart(
            route: task.route.path,
            // THE CANONICAL PARAMETER QUESTION BELONGS TO `/tune` AND TO
            // NOTHING ELSE. It asks whether the bench can hold the network's
            // parameters to fold a gain into the last layer. A grid route runs
            // an authored move or a published entrant and folds nothing, so the
            // question does not arise there and is answered the way an absent
            // question has to be answered through a Bool.
            policyIsNetworkIdentity: task.route == .tune ? policy.isNetworkIdentity : true,
            policyName: policy.benchPolicyName,
            bundledPolicyNames: bundled)
    }

    // MARK: - the run

    /// Run the whole task, one request at a time, into a log.
    func start(policy: EvalPolicy, library: LibraryModel, benches: BenchStore,
               evals: EvalStore) async {
        guard let task, let embodiment, !running else { return }
        running = true
        stopped = false
        loopEnded = false
        failure = nil
        finishedFile = nil
        haltedBy = nil
        scenes = []
        awaitingVerdict = []
        // START PUSHES THE RUN SCREEN, so somebody is watching from here until
        // that screen says otherwise. Waiting for its `onAppear` would leave a
        // scene that answered inside the first frame unqueued.
        watching = true
        criterion = nil
        refusedTerms = []
        declaredTail = nil
        scenesDone = 0
        scenesTotal = task.scenes.count
        startedAt = Date()
        chosenPolicy = policy
        chosenEmbodiment = embodiment
        chosenTask = task
        store = evals
        ranOnBench = benches.selected?.name
        ranOnAddress = benches.selected?.address

        do {
            let (address, token) = try Self.armed(benches)
            let wireName = try await wirePolicyName(policy, library: library,
                                                    embodiment: embodiment,
                                                    address: address, token: token)
            for scene in task.scenes {
                if stopped { break }
                currentScene = scene
                let outcome = try await runScene(scene, task: task, policyName: wireName,
                                                 embodiment: embodiment,
                                                 address: address, token: token)
                scenes.append(outcome)
                scenesDone += 1
                if let halt = pendingHalt { haltedBy = halt; pendingHalt = nil; break }
            }
        } catch {
            haltedBy = EvalMessage.of(error)
        }
        currentScene = nil
        running = false
        loopEnded = true
        if haltedBy != nil { Haptic.linkLost() } else if !stopped { Haptic.finished() }
        fileIfNothingLeftToJudge()
    }

    /// THE TAP IS ANSWERED THE MOMENT IT LANDS, even though the loop reads the
    /// flag at the end of a scene. `stopped` is published, so the button's own
    /// word changes with it; the haptic is here rather than in the view because
    /// both screens that draw a Stop should feel the same.
    func stop() {
        guard !stopped else { return }
        stopped = true
        Haptic.stopRequested()
    }

    /// Nobody is on a screen that could present the verdict sheet.
    ///
    /// Called when the run screen goes away. Everything queued goes unjudged
    /// and nothing more is queued, which is exactly what "Stop watching"
    /// already does, and the log is filed the moment the loop is over.
    func nobodyIsWatching() {
        watching = false
        awaitingVerdict = []
        fileIfNothingLeftToJudge()
    }

    /// A screen that can present the sheet is up.
    func somebodyIsWatching() { watching = true }

    /// A halt raised inside a scene, which stops the run after that scene
    /// rather than throwing through the request that found it: the scene that
    /// noticed still has trials worth keeping.
    private var pendingHalt: String?

    /// The name the bench knows this policy by.
    ///
    /// A BUNDLED NETWORK IS ALREADY THERE, and that is what the probe relies
    /// on: every bench in this family holds the nine the app ships. Anything
    /// else has to be put on the bench first, as whatever kind of bytes that
    /// bench takes: the phone runs canonical parameters and has no ONNX
    /// reader, a desk bench loads the file through onnxruntime and wants both,
    /// which is `TuneView.put`'s split, kept.
    private func wirePolicyName(_ policy: EvalPolicy, library: LibraryModel,
                                embodiment: EvalEmbodiment,
                                address: DuckBench.Address, token: String?) async throws -> String {
        guard policy.kind != .challengeEntrant, policy.kind != .authoredMotion else {
            return policy.benchPolicyName
        }
        guard let entry = library.library.entries.first(where: {
            $0.fileName == policy.benchPolicyName
        }) else { return policy.benchPolicyName }
        if entry.origin == .bundled { return entry.fileName }
        guard let file = PolicyStore.data(for: entry) else { return entry.fileName }
        let bytes = try DuckPolicy.load(from: file).canonicalParameterBytes
        if embodiment.body == .thisPhoneBench {
            return try DuckBench.readUploaded(
                await Self.ask(try DuckBench.uploadParameters(address, canonicalBytes: bytes),
                               token: token, seconds: EvalRun.probeSeconds))
        }
        return try DuckBench.readUploaded(
            await Self.ask(try DuckBench.upload(address, onnx: file, parameters: bytes),
                           token: token, seconds: EvalRun.probeSeconds))
    }

    private func runScene(_ scene: EvalScene, task: EvalTask, policyName: String,
                          embodiment: EvalEmbodiment,
                          address: DuckBench.Address, token: String?) async throws
        -> EvalSceneResult {
        switch task.route {
        case .tune:
            return try await runTuneScene(scene, task: task, policyName: policyName,
                                          embodiment: embodiment, address: address, token: token)
        case .climb:
            return try await runClimbScene(scene, task: task, embodiment: embodiment,
                                           address: address, token: token)
        case .chase:
            return try await runChaseScene(scene, task: task, embodiment: embodiment,
                                           address: address, token: token)
        }
    }

    // MARK: - one walk scene

    /// One `/tune` call answers every drop of a scene, so a scene is the unit
    /// of progress and of cancellation. That is the bench's own request shape
    /// and not a choice made here.
    private func runTuneScene(_ scene: EvalScene, task: EvalTask, policyName: String,
                              embodiment: EvalEmbodiment,
                              address: DuckBench.Address, token: String?) async throws
        -> EvalSceneResult {
        let drops = task.epochs.axis.dropValues ?? []
        let seconds = task.maxSeconds ?? EvalTask.walkSeconds
        let call = try DuckBench.tune(
            address, policy: policyName,
            gain: DuckTuner.TuningVector.identity.gain,
            offset: DuckTuner.TuningVector.identity.offset,
            seconds: seconds, drops: drops,
            schedule: scene.command ?? [],
            terms: DuckTuner.terms.map(\.key),
            trace: task.wantsTrace)
        let answer: DuckBench.Tuned
        do {
            answer = try DuckBench.readTuned(
                await Self.ask(call, token: token,
                               seconds: EvalRun.callTimeout(seconds: seconds,
                                                            episodes: drops.count)))
        } catch {
            // A SCENE THAT DID NOT ANSWER IS A SCENE WITH AN ERROR ON IT, and
            // the run goes on: eleven of twelve scenes answering is data, and
            // abandoning them to avoid printing one sentence throws away the
            // minutes that produced them.
            return EvalSceneResult(scene: scene, reducer: task.epochs.reducer, trials: [],
                                   error: EvalMessage.of(error))
        }
        if criterion == nil { criterion = DuckBench.statedCriterion(answer.criterion) }
        if refusedTerms.isEmpty { refusedTerms = answer.refused }
        if let halt = plantHalt(digest: answer.plantDigest, against: embodiment) {
            pendingHalt = halt
        }

        var trials: [EvalTrial] = []
        for (epoch, episode) in answer.perDrop.enumerated() {
            var metadata: [String: EvalLogJSON] = [
                EvalMeta.dropMetres: .number(episode.drop),
                EvalMeta.terms: .numbers(episode.terms),
                EvalMeta.diverged: .bool(episode.diverged),
            ]
            if episode.diverged {
                // THE BENCH'S OWN ACCOUNT OF DIVERGENCE, IN THE KIT'S WORDS.
                // `readTuned` does not carry the per-episode `divergedWhy` off
                // the wire, so the sentence here is the tested one this app
                // already prints beside a candidate an episode diverged on. The
                // trial is recorded and never scored either way.
                trials.append(EvalTrial.errored(sceneID: scene.id, epoch: epoch,
                                                why: DuckTuner.rejectedAsDiverged,
                                                metadata: metadata))
                continue
            }
            // THE TRACE IS THE FIRST DROP'S AND NO OTHER'S. `/tune` records one
            // episode per call, which is why `EvalTrace.dropHeight` exists at
            // all: a recording shown against the wrong trial is worse than no
            // recording.
            // THE CAPTION COMES OFF THE WIRE WITH THE TICKS. `traceWhy` is the
            // bench's own sentence about what it recorded and where the cap
            // falls; a caption this app wrote over somebody else's recording
            // would be this app describing a measurement it did not take.
            let trace: EvalTrace? = epoch == 0 ? answer.trace.map {
                EvalTrace(ticks: $0, dropHeight: episode.drop, why: answer.traceWhy)
            } : nil
            metadata[EvalMeta.ranToHorizon] = .bool(episode.standing)
            var scores: [String: Double] = [
                // `EvalScorer.successAtEnd.said`: 1 when the bench's own
                // criterion was met at the last tick, 0 when it was not.
                EvalScorer.successAtEnd.name: episode.standing ? 1 : 0,
                EvalScorer.travelled.name: episode.travelled,
                EvalScorer.netDisplacement.name: episode.netDisplacement,
            ]
            // A DIVERGED EPISODE SENDS NO HEIGHT AT ALL, and an absent height
            // written down as zero would be a duck lying on the floor.
            if let height = episode.endHeight { scores[EvalScorer.endHeight.name] = height }
            trials.append(EvalTrial.scored(
                sceneID: scene.id, epoch: epoch, scores: scores,
                terminationReason: episode.standing ? Self.endedAsAsked : Self.ranOutOfHorizon,
                ticks: trace?.ticks.count, metadata: metadata, trace: trace))
        }
        queueVerdicts(in: trials, sceneID: scene.id)
        return EvalSceneResult(scene: scene, reducer: task.epochs.reducer, trials: trials)
    }

    // MARK: - one stairs cell

    private func runClimbScene(_ scene: EvalScene, task: EvalTask, embodiment: EvalEmbodiment,
                               address: DuckBench.Address, token: String?) async throws
        -> EvalSceneResult {
        // NOTHING TO RUN IS NOT A REFUSAL WITH WORDS OF ITS OWN. Start is not
        // offered without an entrant, and a scene on the climb route always
        // carries its cell, so this is a scene with no error sentence rather
        // than an invented one.
        guard let entrant, case .stairs(let move) = entrant.body, let cell = scene.cell,
              let rise = scene.rise else {
            return EvalSceneResult(scene: scene, reducer: task.epochs.reducer, trials: [])
        }
        let climbed: DuckBench.Climbed
        do {
            let call = try DuckBench.climb(address, move: move, rise: rise, cell: cell)
            climbed = try DuckBench.readClimbed(
                await Self.ask(call, token: token, seconds: Self.cellSeconds))
        } catch {
            return EvalSceneResult(scene: scene, reducer: task.epochs.reducer, trials: [],
                                   error: EvalMessage.of(error))
        }
        if criterion == nil { criterion = DuckBench.statedCriterion(climbed.criterion) }
        if let halt = plantHalt(digest: climbed.plantDigest, against: embodiment) {
            pendingHalt = halt
        }
        if let halt = tailHalt(reported: climbed.tailTicks) { pendingHalt = halt }

        let metadata: [String: EvalLogJSON] = [
            EvalMeta.tailTicksDeclared: .integer(climbed.tailTicks),
            EvalMeta.cellInvalid: .bool(climbed.invalid),
        ]
        let trial: EvalTrial
        if climbed.invalid {
            // AN INVALID CELL IS NOT A FAILED CELL: it is a file that is not a
            // result, which is what the bench's own `invalid` means. It is
            // recorded with the bench's reason and never scored.
            trial = EvalTrial.errored(sceneID: scene.id, epoch: 0,
                                      why: EvalText.foreign(climbed.why)
                                        ?? EvalRun.erroredNotScoredSaid,
                                      metadata: metadata)
        } else {
            trial = EvalTrial.scored(
                sceneID: scene.id, epoch: 0,
                scores: [
                    EvalScorer.successAtEnd.name: climbed.stable ? 1 : 0,
                    EvalScorer.clearedHonestly.name: climbed.honest ? 1 : 0,
                    EvalScorer.peakAboveTread.name: climbed.peakAboveTreadMillimetres,
                    EvalScorer.maxTorque.name: climbed.maxTorque,
                ],
                terminationReason: climbed.stable ? Self.endedAsAsked : Self.ranOutOfHorizon,
                ticks: climbed.clipTicks, metadata: metadata)
        }
        return EvalSceneResult(scene: scene, reducer: task.epochs.reducer, trials: [trial])
    }

    // MARK: - one ball cell

    private func runChaseScene(_ scene: EvalScene, task: EvalTask, embodiment: EvalEmbodiment,
                               address: DuckBench.Address, token: String?) async throws
        -> EvalSceneResult {
        guard let entrant, case .ball(let runner) = entrant.body,
              let cell = scene.chaseCell else {
            return EvalSceneResult(scene: scene, reducer: task.epochs.reducer, trials: [])
        }
        let chased: DuckBench.Chased
        do {
            let call = try DuckBench.chase(address, entrant: runner, cell: cell)
            chased = try DuckBench.readChased(
                await Self.ask(call, token: token, seconds: Self.cellSeconds))
        } catch {
            return EvalSceneResult(scene: scene, reducer: task.epochs.reducer, trials: [],
                                   error: EvalMessage.of(error))
        }
        if criterion == nil { criterion = DuckBench.statedCriterion(chased.criterion) }
        if refusedTerms.isEmpty {
            refusedTerms = chased.refused.map { (name: $0.term, why: $0.reason) }
        }
        if let halt = plantHalt(digest: chased.plantDigest, against: embodiment) {
            pendingHalt = halt
        }
        if let halt = tailHalt(reported: chased.tailTicks) { pendingHalt = halt }

        let metadata: [String: EvalLogJSON] = [
            EvalMeta.tailTicksDeclared: .integer(chased.tailTicks),
            EvalMeta.cellInvalid: .bool(chased.invalid),
        ]
        let trial: EvalTrial
        if chased.invalid {
            trial = EvalTrial.errored(sceneID: scene.id, epoch: 0,
                                      why: EvalText.foreign(chased.why)
                                        ?? EvalRun.erroredNotScoredSaid,
                                      metadata: metadata)
        } else {
            trial = EvalTrial.scored(
                sceneID: scene.id, epoch: 0,
                scores: [
                    EvalScorer.successAtEnd.name: chased.stable ? 1 : 0,
                    EvalScorer.ballTravel.name: chased.ballTravelMillimetres,
                    EvalScorer.ballNet.name: chased.ballNetMillimetres,
                    EvalScorer.closestApproach.name: chased.closestMillimetres,
                ],
                terminationReason: chased.stable ? Self.endedAsAsked : Self.ranOutOfHorizon,
                ticks: nil, metadata: metadata)
        }
        return EvalSceneResult(scene: scene, reducer: task.epochs.reducer, trials: [trial])
    }

    // MARK: - the two halts

    /// L17. The first answer's world is the run's; a later answer with another
    /// one stops everything, because the scenes before the change and the
    /// scenes after it are not one measurement.
    private func plantHalt(digest: String?,
                           against embodiment: EvalEmbodiment) -> String? {
        guard let digest, let expected = embodiment.plantDigest, digest != expected else {
            return nil
        }
        return EvalRun.plantChangedMidRun(from: expected, to: digest)
    }

    /// L18. The tail is what standing at the end means, so a cell scored
    /// against a different one is a different question.
    ///
    /// THE DECLARED TAIL IS THE FIRST ANSWER'S AND NOT A NUMBER TYPED HERE. The
    /// harness owns its own tail; this app has never measured one, and writing
    /// a literal here would be the app asserting a number the bench decides.
    private func tailHalt(reported: Int) -> String? {
        guard let declared = declaredTail else {
            declaredTail = reported
            return nil
        }
        guard declared != reported else { return nil }
        return EvalRun.tailNotDeclared(declared: declared, reported: reported)
    }

    // MARK: - the two wire words for how a trial ended

    /// `termination_reasons[i]`, in upstream's own vocabulary.
    ///
    /// `success_at_end` READS THIS FIELD IN THEIR CODE, so the word a trial
    /// that met the criterion ends with has to be theirs or a log written here
    /// would score differently in their tools than it does on this screen.
    private static let endedAsAsked = "success"
    private static let ranOutOfHorizon = "horizon"

    // MARK: - verdicts

    private func queueVerdicts(in trials: [EvalTrial], sceneID: String) {
        guard wantsVerdicts, watching else { return }
        for trial in trials where trial.trace != nil {
            awaitingVerdict.append(EvalTrialAddress(sceneID: sceneID, epoch: trial.epoch))
        }
    }

    /// Write a person's answer beside the one trial they could watch.
    func record(_ verdict: EvalVerdict) {
        guard let address = awaitingVerdict.first else { return }
        replace(address) { trial in
            EvalTrial(sceneID: trial.sceneID, epoch: trial.epoch, status: trial.status,
                      scores: trial.scores, terminationReason: trial.terminationReason,
                      ticks: trial.ticks, error: trial.error, metadata: trial.metadata,
                      verdict: verdict, trace: trial.trace)
        }
        awaitingVerdict.removeFirst()
        fileIfNothingLeftToJudge()
    }

    /// Skip this one. A trial nobody judged carries no verdict, which is what
    /// `null` in their three parallel arrays already means.
    func skipOne() {
        guard !awaitingVerdict.isEmpty else { return }
        awaitingVerdict.removeFirst()
        fileIfNothingLeftToJudge()
    }

    /// Stop watching. Everything still queued goes unjudged.
    func skipJudging() {
        awaitingVerdict = []
        fileIfNothingLeftToJudge()
    }

    private func replace(_ address: EvalTrialAddress,
                         with change: (EvalTrial) -> EvalTrial) {
        guard let sceneIndex = scenes.firstIndex(where: { $0.scene.id == address.sceneID }),
              let trialIndex = scenes[sceneIndex].trials.firstIndex(where: {
                  $0.epoch == address.epoch
              }) else { return }
        var trials = scenes[sceneIndex].trials
        trials[trialIndex] = change(trials[trialIndex])
        scenes[sceneIndex] = EvalSceneResult(scene: scenes[sceneIndex].scene,
                                             reducer: scenes[sceneIndex].reducer,
                                             trials: trials,
                                             error: scenes[sceneIndex].error)
    }

    // MARK: - filing it

    /// The log is written the moment there is nothing left to judge.
    ///
    /// AND IT IS WRITTEN FOR A STOPPED RUN TOO. A run somebody stopped is real
    /// data about what happened up to the stop, which is what
    /// `EvalTask.stopIsNotAFailure` says under the Stop button; throwing it
    /// away would make the sentence false.
    ///
    /// THERE IS ONE RUN IT DOES NOT WRITE: one where no answer ever arrived.
    /// `criterion` has no default anywhere in this feature because it is the
    /// bench's own sentence about what ending standing means, and a log that
    /// carried an app-written criterion would say the bench said something it
    /// never said. So a run with no answer at all is a failure sentence and not
    /// a file.
    private func fileIfNothingLeftToJudge() {
        guard loopEnded, awaitingVerdict.isEmpty, finishedFile == nil else { return }
        guard let task = chosenTask, let policy = chosenPolicy,
              let embodiment = chosenEmbodiment, let store else { return }
        guard let criterion else {
            // NO ANSWER MEANS NO FILE AND A SENTENCE INSTEAD, and the sentence
            // is whichever refusal actually happened: the halt, or the first
            // scene's own words, before anything the probe said earlier.
            failure = haltedBy ?? scenes.compactMap(\.error).first ?? unreachable ?? notYet
            return
        }
        let run = EvalRun(task: task, policy: policy, embodiment: embodiment,
                          startedAt: startedAt, completedAt: Date(), scenes: scenes,
                          wasCancelled: stopped, haltedBy: haltedBy)
        let file = EvalLogFile.written(run, criterion: criterion, refusedTerms: refusedTerms,
                                       appVersion: Self.marketingVersion, build: Self.build)
        // "WHAT IT WROTE" IS A STATEMENT ABOUT THE DISK. `finishedFile` is what
        // the run screen draws its Open the log and Share section on, and
        // setting it before the write meant a failed save left that section on
        // screen, offering a file that was not on the shelf, with the refusal
        // waiting on another screen entirely.
        if store.save(file) {
            finishedFile = file
        } else {
            failure = store.failure
        }
    }

    /// READ FROM THE BUNDLE RATHER THAN WRITTEN DOWN, for the reason
    /// `AppVersion` already gives: both change on every upload, and a literal
    /// here would date-stamp every log with whatever was true the day this file
    /// was last edited.
    private static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
    private static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    // MARK: - the wire

    /// How long a client waits for one grid cell.
    ///
    /// THE KIT'S OWN FORMULA, WITH NO DECLARED PHYSICS IN IT. `/tune` is given
    /// a list of episodes and their seconds, so its deadline is the physics
    /// plus the transport; a grid cell is timed by the harness itself and
    /// names neither, so what is left is the formula's floor. Written this way
    /// rather than as a number, because a number here and a formula there is
    /// two answers to one question. It is generous for the reason
    /// `StairsRun.cellSeconds` gives: the floor is a phone running MuJoCo in
    /// WebAssembly, and a client timeout shorter than the bench's own deadline
    /// reports a working bench as a dead one.
    private static var cellSeconds: Int { EvalRun.callTimeout(seconds: 0, episodes: 0) }

    private static func armed(_ benches: BenchStore) throws -> (DuckBench.Address, String?) {
        guard let chosen = benches.selected else { throw DuckBench.Refusal.empty }
        let armed = benches.armed(chosen)
        return (try armed.resolved(), armed.token)
    }

    private static func ask(_ call: DuckBench.Call, token: String?,
                            seconds: Int) async throws -> Data {
        var request = DuckBench.urlRequest(for: call, token: token)
        request.timeoutInterval = TimeInterval(seconds)
        return try await URLSession.shared.data(for: request).0
    }
}
