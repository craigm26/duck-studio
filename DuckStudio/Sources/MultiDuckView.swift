import SwiftUI
import DuckKit
import StudioKit

/// Two ducks in one bench world, one command, two walkers — crossed.
///
/// STAGE 2 OF `docs/MULTI-DUCK.md`, AND DELIBERATELY THE SAME SCREEN THE
/// HARDWARE WILL GET. Everything that decides — the cross, the schedule, the
/// record — is `MultiDuck` in the kit, tested against a live two-duck bench.
/// This view uploads, drives, records and plays back, and only that.
///
/// DRIVEN FIRST, SHOWN SECOND. A run is sent to the end and every tick's
/// stance kept for both ducks, then played on one clock with the two stages
/// stacked, `RolloutPreferenceView`'s layout. The person watches something
/// that happened on their bench a moment ago, and it cannot stutter.
///
/// STOP BOTH IS ALWAYS ON SCREEN. In a simulator it only ends the run early;
/// the habit is the point, because the next stage is two robots.
struct MultiDuckView: View {

    @ObservedObject var model: LibraryModel
    @ObservedObject var benches: BenchStore

    @StateObject private var feedback = FeedbackStore()
    @State private var ducks: [String] = []
    @State private var host: DuckBench.Health.Host?
    @State private var walkerA: String?
    @State private var walkerB: String?
    @State private var commandIndex = 0
    @State private var pair: MultiDuck.Pair?
    @State private var run = 1
    @State private var recording: MultiDuck.Recording?
    @State private var running = false
    @State private var stopRequested = false
    @State private var playhead: TimeInterval = 0
    @State private var isPlaying = true
    @State private var orbit = OrbitState()
    @State private var firstPick: RolloutPairs.Pick?
    @State private var consistentCount = 0
    @State private var crossedCount = 0
    @State private var refusal: String?

    private var candidates: [PolicyLibrary.Entry] {
        model.library.entries.filter { MultiDuck.identity(of: $0) != nil }
    }
    private var bench: BenchEndpoint? { benches.selected.map { benches.armed($0) } }
    private var address: DuckBench.Address? { try? bench?.resolved() }

    var body: some View {
        VStack(spacing: 0) {
            if let recording, pair != nil {
                stages(recording)
                TransportBar(duration: max(recording.duration, 0.01), playhead: $playhead,
                             isRunning: $isPlaying)
                    .padding(.horizontal, Theme.spacing(.snug))
                answers
            } else {
                setup
            }
        }
        .background(Theme.backgroundPrimary)
        .navigationTitle(MultiDuck.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(MultiDuck.stopBoth, role: .destructive) { stopBoth() }
            }
        }
        .task(id: benches.selectedID) { await readBench() }
    }

    // MARK: - setting up

    private var setup: some View {
        List {
            Section {
                Text(MultiDuck.intro).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if ducks.count < 2 {
                    Text(ducks.isEmpty ? MultiDuck.noBench : MultiDuck.Refusal.needTwoDucks(ducks.count).message)
                        .font(.caption).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if candidates.count < 2 {
                    Text(MultiDuck.needWalkers).font(.caption).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker(MultiDuck.walkerA, selection: $walkerA) {
                    ForEach(candidates) { Text($0.title).tag(Optional($0.id)) }
                }
                Picker(MultiDuck.walkerB, selection: $walkerB) {
                    ForEach(candidates) { Text($0.title).tag(Optional($0.id)) }
                }
                Picker(MultiDuck.command, selection: $commandIndex) {
                    ForEach(Array(MultiDuck.commands.enumerated()), id: \.offset) { i, c in
                        Text(c.name).tag(i)
                    }
                }
                Button(running ? MultiDuck.running : MultiDuck.start) { Task { await startPair() } }
                    .buttonStyle(.primaryAction)
                    .disabled(running || ducks.count < 2 || walkerA == nil || walkerB == nil)
                if let refusal {
                    Label(refusal, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if crossedCount > 0 {
                    Text(MultiDuck.consistency(consistentCount, of: crossedCount))
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.measured)
                }
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
    }

    // MARK: - watching and answering

    private func stages(_ recording: MultiDuck.Recording) -> some View {
        let now = recording.stances(at: playhead)
        return VStack(spacing: 0) {
            DuckStage(pose: now.first, environment: .bareFloor, props: [], orbit: $orbit)
                .frame(maxHeight: .infinity)
                .accessibilityLabel(Text(MultiDuck.top))
            Rectangle().fill(Theme.separator).frame(height: AuthoringMetric.hairlineStroke)
            DuckStage(pose: now.second, environment: .bareFloor, props: [], orbit: $orbit)
                .frame(maxHeight: .infinity)
                .accessibilityLabel(Text(MultiDuck.bottom))
        }
    }

    private var answers: some View {
        VStack(spacing: Theme.spacing(.tight)) {
            Text(MultiDuck.runOf(run)).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.spacing(.tight)) {
                Button { answer(.left) } label: { Text(MultiDuck.top).frame(maxWidth: .infinity) }
                    .buttonStyle(.primaryAction)
                Button { answer(.right) } label: { Text(MultiDuck.bottom).frame(maxWidth: .infinity) }
                    .buttonStyle(.primaryAction)
            }
            HStack(spacing: Theme.spacing(.tight)) {
                Button { answer(.tie) } label: {
                    Text(RolloutPreferenceWords.tie).frame(maxWidth: .infinity)
                }
                .buttonStyle(AuthoringActionStyle())
                Button { answer(.bothBad) } label: {
                    Text(RolloutPreferenceWords.bothBad).frame(maxWidth: .infinity)
                }
                .buttonStyle(AuthoringActionStyle())
            }
        }
        .padding(Theme.spacing(.snug))
        .disabled(running)
    }

    private func answer(_ pick: RolloutPairs.Pick) {
        guard let pair else { return }
        if let record = try? MultiDuck.record(pick, reasons: [], pair: pair, run: run,
                                              share: feedback.share, client: FeedbackStore.client) {
            feedback.append([record])
        }
        if run == 1 {
            firstPick = pick
            run = 2
            Task { await drive(pair, run: 2) }
        } else {
            if let first = firstPick, let same = MultiDuck.consistent(run1: first, run2: pick) {
                crossedCount += 1
                if same { consistentCount += 1 }
            }
            self.pair = nil
            recording = nil
            run = 1
            firstPick = nil
        }
    }

    // MARK: - the bench

    private func send(_ call: DuckBench.Call) async throws -> Data {
        try await URLSession.shared.data(for: DuckBench.urlRequest(for: call, token: bench?.token)).0
    }

    private func readBench() async {
        guard let address, let data = try? await send(DuckBench.health(address)),
              let health = try? DuckBench.readHealth(data) else { ducks = []; return }
        ducks = health.ducks
        host = health.host
    }

    private func startPair() async {
        refusal = nil
        guard let address,
              let entryA = candidates.first(where: { $0.id == walkerA }),
              let entryB = candidates.first(where: { $0.id == walkerB }),
              let idA = MultiDuck.identity(of: entryA), let idB = MultiDuck.identity(of: entryB) else { return }
        running = true
        defer { running = false }
        do {
            let nameA = try await BenchUploads.put(entryA, address: address, token: bench?.token, host: host)
            let nameB = try await BenchUploads.put(entryB, address: address, token: bench?.token, host: host)
            let made = try MultiDuck.Pair(
                ducks: ducks,
                a: .init(benchName: nameA, title: entryA.title, identity: idA),
                b: .init(benchName: nameB, title: entryB.title, identity: idB),
                command: MultiDuck.commands[commandIndex])
            pair = made
            run = 1
            await drive(made, run: 1)
        } catch let error as MultiDuck.Refusal {
            refusal = error.message
        } catch {
            refusal = error.localizedDescription
        }
    }

    private func drive(_ pair: MultiDuck.Pair, run: Int) async {
        guard let address else { return }
        running = true
        stopRequested = false
        defer { running = false }
        do {
            for call in try MultiDuck.setUp(pair, run: run, at: address) { _ = try await send(call) }
            var fresh = MultiDuck.Recording()
            for _ in 0..<MultiDuck.ticks(for: pair.command) where !stopRequested {
                let calls = try MultiDuck.tick(pair, at: address)
                let first = try DuckDrive.readLive(try await send(calls[0]))
                let second = try DuckDrive.readLive(try await send(calls[1]))
                fresh.append(first: first.stance, second: second.stance)
            }
            recording = fresh
            playhead = 0
            isPlaying = true
        } catch {
            refusal = error.localizedDescription
            self.pair = nil
        }
    }

    private func stopBoth() {
        stopRequested = true
        guard let address else { return }
        let names = ducks.prefix(2)
        Task {
            for duck in names {
                if let call = try? DuckDrive.stop(address, duck: duck) { _ = try? await send(call) }
            }
        }
    }
}
