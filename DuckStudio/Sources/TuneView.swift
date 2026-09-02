import SwiftUI
import DuckKit
import StudioKit

/// Tune it on this phone — a search over a per-joint gain and trim, and a
/// refusal to run one that cannot be scored honestly.
///
/// WHAT THE SCREEN IS FOR. Every other screen in this app either inspects a
/// network somebody else trained or measures one. This is the only one that
/// tries to make a network BETTER, and the only honest way to do that on a
/// phone is to search a residual small enough to fold into the last layer —
/// twenty-eight numbers, which `DuckPolicyWriter.folding` turns into a file
/// robotd would load. Nothing here is training and `DuckTuner.notTraining` is
/// the sentence that says so, in the kit, where `swift test` reads it.
///
/// AND TODAY IT DOES NOT RUN, WHICH IS THE MOST IMPORTANT THING ON IT. The
/// phone bench answers `/state` and `/intent` with a position, a quaternion and
/// fourteen joint angles — no velocity, no action — so four of the six reward
/// terms cannot be computed from what it says, and the two that survive are
/// both terms a duck standing still maximises. Measured through this app's own
/// bench build: the standing policy scores 2.9812 on those two where the
/// walking policy scores 2.5287, having travelled 1 mm against 1231. So the
/// Start button is not drawn, `DuckTuner.notYet` says exactly that with the
/// numbers, and it names the one endpoint that would unblock it. A blocked
/// surface ships as a stated not-yet, never as a control that does nothing.
///
/// THE RUN PANEL IS REAL CODE AND NOT A MOCK-UP. `run()` below drives a whole
/// (1+λ)-ES against `/tune` — baseline, generations, inert rejection, held-out
/// check, export — and the only thing between it and a person is the bench
/// answering that endpoint. Writing the panel as a placeholder would have meant
/// discovering on the day `/tune` ships that the client was never written.
///
/// NOTHING ON THIS SCREEN COMPUTES ANYTHING. The reward is `DuckTuner.reward`,
/// the mutation is `DuckTuner.mutate`, the inert guard is `PolicyBlend`'s by
/// way of `DuckTuner.wentInert`, and every sentence is a `static let` in the
/// kit. This file arranges them.
struct TuneView: View {
    @ObservedObject var library: LibraryModel
    @ObservedObject var benches: BenchStore

    /// Which network the residual is folded into. Only policies that load: a
    /// fold into a file this app refused would be a fold into nothing.
    @State private var basePolicyID: String?
    // @StateObject AND NOT @State. `TuneRun` is a reference type that
    // publishes; `@State` would hold it without subscribing, so a generation
    // finishing would change the object and redraw nothing — the run panel
    // would sit at generation one for fifteen minutes and look like a hang.
    @StateObject private var run = TuneRun()
    @State private var orbit = OrbitState()
    @State private var outgoing: ExportedFile?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The viewport the duck gets when text is at a normal size. The same
    /// number `DriveView` uses, restated here rather than reached for across
    /// screens, because a shared metric between two unrelated stages is a
    /// coupling neither of them asked for.
    private let stageHeight: CGFloat = 300

    private var candidates: [PolicyLibrary.Entry] {
        library.library.entries.filter(\.isRunnable)
    }

    private var base: PolicyLibrary.Entry? {
        basePolicyID.flatMap { wanted in candidates.first { $0.id == wanted } }
    }

    var body: some View {
        Form {
            beforeYouRunIt
            whatItIsScoredOn
            whatIsRefused
            thisBench
            howLong
            if run.isRunning || !run.generations.isEmpty { runPanel }
            if let result = run.result { resultRow(result) }
            if let failure = run.failure { failureRow(failure) }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Tune it on this phone")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if basePolicyID == nil { basePolicyID = candidates.first?.id }
            // ASK THE BENCH WHETHER IT CAN SCORE, rather than deciding from the
            // address. Both benches answer the same ten endpoints; the only
            // honest way to know whether this one has grown `/tune` is to send
            // it one and read what comes back.
            await run.probe(benches: benches)
            Haptic.prepare()
        }
        .sheet(item: $outgoing) { file in
            ShareSheet(items: [file.url]) { outgoing = nil }
        }
    }

    // MARK: - before

    private var beforeYouRunIt: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing(.snug)) {
                Text(DuckTuner.notTraining)
                Text(DuckTuner.Schedule.onAPhone.described)
                Text(DuckTuner.Schedule.headIsNotSearched)
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Picker("Fold into", selection: $basePolicyID) {
                Text("None").tag(String?.none)
                ForEach(candidates) { entry in
                    Text(entry.displayName).tag(String?.some(entry.id))
                }
            }
            .disabled(run.isRunning)
        } header: {
            SectionHeading(text: "What this does")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the reward

    private var whatItIsScoredOn: some View {
        Section {
            ForEach(DuckTuner.terms) { term in
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    TelemetryRow(label: term.key, value: weight(term))
                    Text(term.purpose)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.spacing(.hairline))
            }
        } header: {
            SectionHeading(text: "Scored on")
        } footer: {
            Text("Every weight is \(DuckTuner.configFile)'s own, read from the same place the "
               + "app grades a recorded clip by.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// THE WEIGHT IS PRINTED WITH ITS SIGN, ALWAYS. Two of the six are
    /// penalties, and a bare "0.05" beside `body_ang_vel` would read as a
    /// reward for turning.
    private func weight(_ term: DuckTuner.Term) -> String {
        (term.weight < 0 ? "−" : "+") + String(format: "%.2f", abs(term.weight))
    }

    private var whatIsRefused: some View {
        Section {
            ForEach(run.refusals) { refused in
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    Text(refused.key)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(Theme.textPrimary)
                    Text(refused.why)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.spacing(.hairline))
            }
        } header: {
            SectionHeading(text: "Not scored · \(run.refusals.count)")
        } footer: {
            Text("Named rather than dropped. A shorter list is not a better one — it is the "
               + "same list with the inconvenient half taken out.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the bench, and whether it can score

    @ViewBuilder private var thisBench: some View {
        Section {
            if let bench = benches.selected {
                TelemetryRow(label: "Bench", value: bench.name)
            }
            if let host = run.host {
                Text(PhoneBenchReport.ranOn(host))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if run.probing {
                Text("Asking this bench whether it can score a search…")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else if let unreachable = run.unreachable {
                // NOT THE NOT-YET. "This bench cannot score a search" and "this
                // bench did not answer" are different facts, and showing the
                // first for the second would tell somebody a permanent thing
                // about a temporary one.
                Text(unreachable)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let readiness = run.readiness {
                Text(readiness.sentence)
                    // YELLOW AND NOT RED. Nothing is broken: a bench that
                    // cannot weigh a trace is a bench that has not grown an
                    // endpoint, which is a caution about what can be done here
                    // and not an error anybody has to fix on this phone.
                    .foregroundStyle(readiness.canSearch ? Theme.textSecondary : Theme.warning)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                if !readiness.canSearch {
                    Text(DuckTuner.whatStillWorksWithoutTune)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // THE BUTTON IS ABSENT, NOT DISABLED. A greyed Start over a
                // reward that rewards standing still is a control that says the
                // feature exists and this phone is not good enough; the
                // sentence above says the true thing instead.
                if readiness.canSearch, let base, !run.isRunning {
                    Button {
                        start(base)
                    } label: {
                        Text("Start the search").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                }
                if run.isRunning {
                    Button(role: .destructive) {
                        run.stop()
                    } label: {
                        Text("Stop").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                    .accessibilityHint(Text("Ends the search after the current episode."))
                }
            }
        } header: {
            SectionHeading(text: "This bench")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var howLong: some View {
        Section {
            Text(run.duration)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: "How long")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the run

    private var runPanel: some View {
        Section {
            // THE DUCK DOING THE CURRENT BEST. Between generations the run
            // puts the best candidate on the live lane and drives it, so what
            // is on the stage is the network the numbers below describe rather
            // than whatever the world happened to be holding.
            DuckStage(pose: run.stance ?? .home, environment: .bareFloor, orbit: $orbit)
                // NOT CAPPED AT ACCESSIBILITY SIZES, the same rule `DriveView`
                // documents: the duck shrinks to make room and the numbers
                // under it do not disappear.
                .frame(maxHeight: typeSize.isAccessibilitySize ? nil : stageHeight)
                .listRowInsets(EdgeInsets())
            if let best = run.best {
                TelemetryRow(label: "Best reward", value: String(format: "%.4f", best.reward))
                // NEVER THE REWARD ALONE. A reward that climbed while the walk
                // stopped is the failure this screen is arranged against.
                TelemetryRow(label: "Travelled", value: metres(best.travelled))
                TelemetryRow(label: "Stayed up", value: "\(best.standing) of \(best.episodes)")
            }
            ForEach(run.generations.reversed()) { generation in
                Text(DuckTuner.generationLine(generation))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(generation.rejectedAsInert > 0
                                        ? Theme.warning : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: run.isRunning ? "Running" : "What it did")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func resultRow(_ result: TuneRun.Result) -> some View {
        Section {
            Text(result.verdict)
                .font(.footnote)
                .foregroundStyle(Theme.measured)
                .fixedSize(horizontal: false, vertical: true)
            Text(result.residual)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(result.provenance)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let caveat = PolicyLibrary.Origin.tuned(base: result.basePolicy).caveat {
                Text(caveat)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                export(result)
            } label: {
                secondaryAction("Save the tuned policy", symbol: "square.and.arrow.up")
            }
        } header: {
            SectionHeading(text: "Result")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func failureRow(_ text: String) -> some View {
        Section {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.refused)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func secondaryAction(_ title: String, symbol: String) -> some View {
        Label {
            Text(title).foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.actionSecondary)
        }
    }

    /// Metres, or millimetres where a walk that stopped lives.
    private func metres(_ value: Double) -> String {
        value < 0.01 ? "\(Int((value * 1000).rounded())) mm" : String(format: "%.2f m", value)
    }

    private func start(_ entry: PolicyLibrary.Entry) {
        guard let bytes = PolicyStore.data(for: entry) else {
            run.failure = "That file is not on this phone any more."
            return
        }
        Haptic.behaviourStarted()
        Task { await run.search(baseFile: bytes, named: entry.displayName,
                                declaredScale: library.declaredScale(for: entry),
                                benches: benches) }
    }

    private func export(_ result: TuneRun.Result) {
        do {
            outgoing = ExportedFile(url: try ExportFile.write(result.onnx, named: result.filename))
        } catch let refusal as ExportFile.Failure {
            run.failure = refusal.message
        } catch {
            run.failure = error.localizedDescription
        }
    }
}

/// The search, as a thing that runs rather than a thing that is drawn.
///
/// EVERY DECISION IN HERE IS THE KIT'S. Which candidate wins is
/// `DuckTuner.reward`; which is thrown away is `DuckTuner.wentInert`, which is
/// `PolicyBlend`'s measured check; what the next candidate is comes from
/// `DuckTuner.mutate` and a seed. This type owns the HTTP, the ordering and the
/// stopping, and nothing else — the app target draws and does not compute, and
/// a search that invented its own arithmetic would be the largest violation of
/// that rule the app could contain.
@MainActor
final class TuneRun: ObservableObject {

    @Published var probing = true
    @Published var readiness: DuckTuner.Readiness?
    /// Set when the bench did not answer at all, which is a different state
    /// from a bench that answered and cannot score.
    @Published var unreachable: String?
    @Published var host: DuckBench.Health.Host?
    @Published var isRunning = false
    @Published var generations: [DuckTuner.Generation] = []
    @Published var best: DuckTuner.Score?
    @Published var stance: DuckStance?
    @Published var result: Result?
    @Published var failure: String?
    @Published var duration = DuckTuner.durationNotMeasuredYet

    private var stopped = false
    private var episodesDone = 0
    private var startedAt = Date()

    struct Result {
        let verdict: String
        let residual: String
        let provenance: String
        let basePolicy: String
        let onnx: Data
        let filename: String
    }

    /// What is NOT scored, which depends on the bench and is therefore only
    /// answerable after asking it.
    var refusals: [DuckTuner.Refused] {
        DuckTuner.refusedByThePlant + (readiness?.missing ?? [])
    }

    // MARK: - asking the bench what it can do

    func probe(benches: BenchStore) async {
        probing = true
        defer { probing = false }
        readiness = nil; unreachable = nil
        let address: DuckBench.Address, token: String?
        do {
            (address, token) = try armed(benches)
            host = try DuckBench.readHealth(
                await ask(DuckBench.health(address), token: token)).host
        } catch {
            // A BENCH THAT DID NOT ANSWER AT ALL IS NOT A BENCH THAT CANNOT
            // SCORE, and reporting the second for the first would tell somebody
            // their phone is not good enough when the truth is that the
            // listener has not come up. Two states, two sentences.
            unreachable = PhoneBenchReport.notListening
            return
        }
        do {
            // ONE `/tune` CALL WITH THE IDENTITY RESIDUAL. It is a real
            // episode, which is the point: a bench that answers it can score,
            // and one that has no such path answers with the same error shape
            // every shell in this family uses for an unknown route.
            let call = try DuckBench.tune(
                address, policy: probePolicy, gain: DuckTuner.TuningVector.identity.gain,
                offset: DuckTuner.TuningVector.identity.offset,
                seconds: 1, drops: [0.1231], schedule: DuckBench.walkingCommand,
                terms: DuckTuner.terms.map(\.key))
            let tuned = try DuckBench.readTuned(await ask(call, token: token))
            // AND IT HAS TO ANSWER WITH EVERY TERM. A bench with a `/tune` that
            // returns four of six is not a bench that can score this search,
            // and finding that out at generation nine would be worse.
            _ = try DuckTuner.reward(tuned.terms)
            readiness = DuckTuner.readiness(for: .benchComputesThem)
        } catch {
            readiness = DuckTuner.readiness(for: .aLoopOverStates)
        }
    }

    /// The network the probe runs, which is the one every bench in this family
    /// has. A probe against a policy the bench does not hold would fail for the
    /// wrong reason and report the wrong verdict.
    private let probePolicy = "alpha_walking.onnx"

    func stop() { stopped = true }

    // MARK: - the search

    func search(baseFile: Data, named name: String, declaredScale: Double?,
                benches: BenchStore) async {
        guard readiness?.canSearch == true else {
            failure = DuckTuner.notYet
            return
        }
        isRunning = true; stopped = false; failure = nil; result = nil
        generations = []; episodesDone = 0; startedAt = Date()
        defer { isRunning = false }

        let schedule = DuckTuner.Schedule.onAPhone
        let seed = UInt64.random(in: 1...UInt64(Int32.max))
        var rng = DuckTuner.Seeded(seed: seed)

        do {
            let (address, token) = try armed(benches)
            // THE BASE GOES ON THE BENCH AS PARAMETERS, NOT AS A FILE. The
            // phone bench has no ONNX reader on purpose; it runs the canonical
            // bytes the fingerprint is taken over, which is the same
            // arrangement the nine bundled networks already use.
            let policy = try await put(baseFile, address: address, token: token)

            func score(_ vector: DuckTuner.TuningVector, drops: [Double]) async throws
                -> DuckTuner.Score {
                let answer = try DuckBench.readTuned(await ask(try DuckBench.tune(
                    address, policy: policy, gain: vector.gain, offset: vector.offset,
                    seconds: schedule.seconds, drops: drops,
                    schedule: DuckBench.walkingCommand,
                    terms: DuckTuner.terms.map(\.key)), token: token))
                episodesDone += answer.episodes
                duration = DuckTuner.durationSoFar(episodesDone: episodesDone,
                                                   elapsed: Date().timeIntervalSince(startedAt),
                                                   schedule: schedule)
                return DuckTuner.Score(reward: try DuckTuner.reward(answer.terms),
                                       travelled: answer.travelled,
                                       standing: answer.standing, episodes: answer.episodes,
                                       terms: answer.terms,
                                       perDrop: answer.perDrop.map(\.terms))
            }

            // THE YARDSTICK FIRST. Every number after this is a difference from
            // it, and `DuckTuner.Refusal.noBaselineYet` exists because a
            // difference from nothing is not one.
            let baseline = try await score(.identity, drops: schedule.searchDrops)
            let baselineHeld = try await score(.identity, drops: schedule.heldOutDrops)
            // THE NOISE FLOOR, MEASURED RATHER THAN ASSUMED: the spread of the
            // UNCHANGED network's own reward across the very drops the winner
            // will be checked on. It comes out of the per-episode rewards and
            // is nil when the bench reported only an aggregate — in which case
            // the verdict is withheld rather than computed against a number
            // nobody measured.
            let floor = DuckTuner.noiseFloor(
                try baselineHeld.perDrop.map { try DuckTuner.reward($0) })

            var parent = DuckTuner.TuningVector.identity
            var parentScore = baseline
            best = baseline

            for index in 1...schedule.generations {
                if stopped { break }
                var bestChild: DuckTuner.TuningVector?
                var bestChildScore: DuckTuner.Score?
                var inert = 0
                for _ in 0..<schedule.lambda {
                    if stopped { break }
                    let child = DuckTuner.mutate(parent, with: schedule, using: &rng)
                    let seen = try await score(child, drops: schedule.searchDrops)
                    // REJECTED, NOT RANKED. Five of the six terms pay for
                    // standing still, so a candidate that has quietly stopped
                    // would otherwise pull the whole search toward it.
                    if DuckTuner.wentInert(travelled: seen.travelled,
                                           baselineTravelled: baseline.travelled,
                                           standing: seen.standing, of: seen.episodes) {
                        inert += 1
                        continue
                    }
                    if bestChildScore.map({ seen.reward > $0.reward }) ?? true {
                        bestChild = child; bestChildScore = seen
                    }
                }
                if let bestChild, let bestChildScore, bestChildScore.reward > parentScore.reward {
                    parent = bestChild; parentScore = bestChildScore
                }
                best = parentScore
                generations.append(.init(index: index, best: parentScore,
                                         rejectedAsInert: inert))
                // SHOW THE DUCK DOING THE CURRENT BEST, on the live lane, so
                // what is on screen is the network the numbers describe.
                await showOnStage(parent, base: baseFile, address: address, token: token)
            }

            // THE ONLY QUESTION THAT MATTERS: did it survive drops the search
            // never saw?
            let held = try await score(parent, drops: schedule.heldOutDrops)
            let export = try DuckTuner.export(
                baseFile: baseFile, basePolicy: name, declaredActionScale: declaredScale,
                vector: parent, schedule: schedule, seed: seed,
                bench: benches.selected?.name ?? "a bench", measuredTerms: held.terms,
                travelled: held.travelled,
                elapsed: Date().timeIntervalSince(startedAt))

            duration = DuckTuner.durationMeasured(episodes: episodesDone,
                                                  elapsed: Date().timeIntervalSince(startedAt))
            result = Result(
                verdict: floor.map {
                    DuckTuner.heldOutVerdict(gain: held.reward - baselineHeld.reward,
                                             noiseFloor: $0)
                } ?? DuckTuner.noNoiseFloor,
                residual: parent.described,
                provenance: DuckTuner.provenance(
                    episodes: episodesDone, seconds: schedule.seconds,
                    bench: benches.selected?.name ?? "a bench", basePolicy: name,
                    baseFingerprint: export.baseFingerprint, seed: seed),
                basePolicy: name, onnx: export.onnx, filename: export.filename)
            Haptic.finished()
        } catch let refusal as DuckTuner.Refusal {
            failure = refusal.message
        } catch let refusal as DuckTuner.TuningVector.Refusal {
            failure = refusal.message
        } catch let refusal as DuckBench.Refusal {
            failure = refusal.message
        } catch let refusal as BenchEndpoint.Refusal {
            failure = refusal.message
        } catch let error as DuckBench.ReadError {
            failure = error.message
        } catch {
            failure = error.localizedDescription
        }
    }

    // MARK: - the bench

    private func armed(_ benches: BenchStore) throws -> (DuckBench.Address, String?) {
        guard let chosen = benches.selected else { throw DuckBench.Refusal.empty }
        let armed = benches.armed(chosen)
        return (try armed.resolved(), armed.token)
    }

    private func ask(_ call: DuckBench.Call, token: String?) async throws -> Data {
        try await URLSession.shared.data(
            for: DuckBench.urlRequest(for: call, token: token)).0
    }

    /// Put a network on the bench, as whatever kind of bytes that bench takes.
    ///
    /// THE PHONE BENCH AND A DESK BENCH WANT DIFFERENT THINGS, and `host.kind`
    /// is the field a caller is allowed to branch on. The phone runs the
    /// canonical parameter bytes and has no ONNX reader; a desk bench loads
    /// through onnxruntime and wants the file. Sending the wrong one is refused
    /// by the bench with its own sentence rather than failing quietly, which is
    /// how this was found in the first place.
    private func put(_ file: Data, address: DuckBench.Address,
                     token: String?) async throws -> String {
        if host?.kind == .phone {
            let bytes = try DuckPolicy.load(from: file).canonicalParameterBytes
            return try DuckBench.readUploaded(
                await ask(try DuckBench.uploadParameters(address, canonicalBytes: bytes),
                          token: token))
        }
        return try DuckBench.readUploaded(
            await ask(try DuckBench.upload(address, onnx: file), token: token))
    }

    /// Drive the current best for a moment so it can be watched.
    ///
    /// FOLDED AND UPLOADED RATHER THAN DESCRIBED. What goes on the live lane is
    /// the candidate itself, so the duck on the stage is the network the
    /// generation line above it is about. A failure here is swallowed on
    /// purpose: not being able to WATCH a run is not a reason to abandon it,
    /// and the numbers are the result either way.
    private func showOnStage(_ vector: DuckTuner.TuningVector, base: Data,
                             address: DuckBench.Address, token: String?) async {
        do {
            let folded = try vector.folded(into: try DuckPolicy.load(from: base))
            let name = try await put(try DuckPolicyWriter.encoded(
                mean: folded.parameters.mean, std: folded.parameters.std,
                layers: folded.parameters.layers), address: address, token: token)
            _ = try await ask(try DuckDrive.reset(address), token: token)
            _ = try await ask(try DuckDrive.load(address, policy: name), token: token)
            for _ in 0..<20 {
                if stopped { return }
                let live = try DuckDrive.readLive(await ask(
                    try DuckDrive.intent(address, .init(vx: 0.5, vy: 0, vyaw: 0), hold: 0.1),
                    token: token))
                stance = live.stance
            }
        } catch {
            // Nothing. See above.
        }
    }
}
