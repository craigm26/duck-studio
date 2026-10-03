import SwiftUI
import DuckKit
import StudioKit

/// Studio → Compare: be the judge. Quick duel, pick any two, a tournament,
/// or improve one of yours by choosing between variants.
struct CompareHubView: View {
    @ObservedObject var library: LibraryModel
    @ObservedObject var drafts: DraftStore
    @ObservedObject var benches: BenchStore
    @StateObject private var store = CompareStore()
    @StateObject private var sequences = SequenceStore()

    var body: some View {
        List {
            Section {
                Text(CompareWords.intro)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(CompareWords.tally(store.today, streak: store.streak),
                      systemImage: store.streak > 1 ? "flame.fill" : "hand.thumbsup")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(store.streak > 1 ? Theme.warning : Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                NavigationLink {
                    RolloutPreferenceView(onPick: { store.counted() })
                } label: {
                    row(CompareWords.quickDuel, CompareWords.quickDuelDetail, "bolt.fill")
                }
                NavigationLink {
                    ContenderPickView(mode: .two, library: library, drafts: drafts,
                                      sequences: sequences, benches: benches, store: store)
                } label: {
                    row(CompareWords.pickTwo, CompareWords.pickTwoDetail, "rectangle.split.1x2")
                }
                NavigationLink {
                    ContenderPickView(mode: .tournament, library: library, drafts: drafts,
                                      sequences: sequences, benches: benches, store: store)
                } label: {
                    row(CompareWords.tournament, CompareWords.tournamentDetail, "trophy.fill")
                }
                NavigationLink {
                    ImproveView(library: library, drafts: drafts, sequences: sequences,
                                benches: benches, store: store)
                } label: {
                    row(CompareWords.improve, CompareWords.improveDetail, "wand.and.rays")
                }
            } footer: {
                Text(CompareWords.sharing)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(CompareWords.title)
        .navigationBarTitleDisplayMode(.large)
    }

    private func row(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: Theme.spacing(.snug)) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.actionPrimary)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }
}

// MARK: - choosing what to compare

struct ContenderPickView: View {
    enum Mode { case two, tournament }
    let mode: Mode
    @ObservedObject var library: LibraryModel
    @ObservedObject var drafts: DraftStore
    @ObservedObject var sequences: SequenceStore
    @ObservedObject var benches: BenchStore
    @ObservedObject var store: CompareStore

    @State private var kind: Compare.Contender.Kind = .behaviour
    @State private var chosen: [Compare.Contender] = []
    @State private var command = 0
    @State private var going = false

    private var limit: Int { mode == .two ? 2 : Compare.Tournament.largest }
    private var ready: Bool {
        mode == .two ? chosen.count == 2 : chosen.count >= Compare.Tournament.smallest
    }

    private var candidates: [Compare.Contender] {
        var list = ContenderCatalog.all(kind, library: library, drafts: drafts, sequences: sequences)
        // Motions and your drafts compare with each other, so they share a list.
        if kind == .motion {
            list += ContenderCatalog.all(.draft, library: library, drafts: drafts, sequences: sequences)
        }
        return list
    }

    var body: some View {
        List {
            Section {
                Picker(CompareWords.chooseKind, selection: $kind) {
                    Text("Behaviours").tag(Compare.Contender.Kind.behaviour)
                    Text("Motions").tag(Compare.Contender.Kind.motion)
                    Text("Sequences").tag(Compare.Contender.Kind.sequence)
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, _ in chosen = [] }
                if kind.takesACommand {
                    Picker(CompareWords.command, selection: $command) {
                        ForEach(CompareWords.commands.indices, id: \.self) { i in
                            Text(CompareWords.commands[i].name).tag(i)
                        }
                    }
                }
            }
            .listRowBackground(Theme.surfacePrimary)

            let groups = Dictionary(grouping: candidates, by: \.source)
            ForEach([Compare.Contender.Source.pollen, .community, .yours, .device], id: \.self) { source in
                if let items = groups[source], !items.isEmpty {
                    Section {
                        ForEach(items) { item in pickRow(item) }
                    } header: {
                        SectionHeading(text: source.title)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
            }
            if candidates.count < 2 {
                Section {
                    Text("There are not two of these on \(DeviceWords.current.this) yet. Make one in Studio, or pick another kind.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(mode == .two ? CompareWords.pickTwo : CompareWords.tournament)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                going = true
            } label: {
                Text(ready ? CompareWords.start
                     : mode == .two ? CompareWords.chooseTwo : CompareWords.chooseSome(chosen.count))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .disabled(!ready)
            .padding(Theme.spacing(.snug))
            .background(.bar)
        }
        .navigationDestination(isPresented: $going) {
            if mode == .two, chosen.count == 2 {
                DuelView(left: chosen[0], right: chosen[1], command: command,
                         library: library, drafts: drafts, sequences: sequences,
                         benches: benches, store: store)
            } else if let t = try? Compare.Tournament(chosen) {
                TournamentView(tournament: t, command: command, library: library, drafts: drafts,
                               sequences: sequences, benches: benches, store: store,
                               onChampion: nil)
            }
        }
    }

    private func pickRow(_ item: Compare.Contender) -> some View {
        let on = chosen.contains(item)
        return Button {
            if on { chosen.removeAll { $0 == item } }
            else if chosen.count < limit { chosen.append(item) }
        } label: {
            HStack {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Theme.actionPrimary : Theme.textTertiary)
                Text(item.name).foregroundStyle(Theme.textPrimary)
                Spacer()
                if item.kind == .draft {
                    Text("yours").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - two on one screen

/// Two clips, one clock, and the four answers. Shared by a duel, a
/// tournament match and an improvement round.
struct DuelStage: View {
    let left: DuckIntentClip
    let right: DuckIntentClip
    let caption: String
    /// A ball on each side, one [x, y, z] per frame, when the thing judged
    /// moved one (Train a duck to shoot). Nil draws no ball.
    var balls: (left: [[Double]], right: [[Double]])? = nil
    /// A pitch to draw behind both.
    var pitch: Shoot.Pitch? = nil
    let answer: (DuckFeedback.Choice, [DuckFeedback.Reason]) -> Void

    @State private var playhead: TimeInterval = 0
    @State private var isRunning = true
    @State private var orbitLeft = OrbitState()
    @State private var orbitRight = OrbitState()
    @State private var reasons: Set<DuckFeedback.Reason> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                side(left, label: CompareWords.left, ball: balls?.left, orbit: $orbitLeft)
                side(right, label: CompareWords.right, ball: balls?.right, orbit: $orbitRight)
            }
            .frame(maxHeight: .infinity)
            TransportBar(duration: max(left.duration, right.duration),
                         playhead: $playhead, isRunning: $isRunning)
                .padding(.horizontal, Theme.spacing(.snug))
            VStack(spacing: Theme.spacing(.tight)) {
                Text(caption).font(.footnote).foregroundStyle(Theme.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.spacing(.tight)) {
                        ForEach(DuckFeedback.Reason.allCases, id: \.rawValue) { reason in
                            let on = reasons.contains(reason)
                            Button(RolloutPreferenceWords.reason(reason)) {
                                if on { reasons.remove(reason) } else { reasons.insert(reason) }
                            }
                            .buttonStyle(.bordered)
                            .tint(on ? Theme.actionPrimary : Theme.textSecondary)
                        }
                    }
                }
                HStack(spacing: Theme.spacing(.tight)) {
                    vote(CompareWords.left, .a, primary: true)
                    vote(CompareWords.right, .b, primary: true)
                }
                HStack(spacing: Theme.spacing(.tight)) {
                    vote(CompareWords.tie, .tie, primary: false)
                    vote(CompareWords.bothBad, .bothBad, primary: false)
                }
            }
            .padding(Theme.spacing(.snug))
        }
        .background(Theme.backgroundPrimary)
    }

    private func side(_ clip: DuckIntentClip, label: String, ball: [[Double]]?,
                      orbit: Binding<OrbitState>) -> some View {
        let t = min(playhead, clip.duration)
        let at = ball.flatMap { path -> SIMD2<Double>? in
            guard !path.isEmpty else { return nil }
            let i = min(Int(t * clip.hz), path.count - 1)
            return SIMD2(path[i][0], path[i][1])
        }
        return DuckStage(pose: .at(clip.pose(at: t)), environment: clip.environment,
                         props: at.map { [ShootBall.prop(at: $0)] } ?? [],
                         orbit: orbit, rolling: at, pitch: pitch)
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
            }
            .accessibilityLabel(Text(label))
    }

    @ViewBuilder private func vote(_ title: String, _ choice: DuckFeedback.Choice,
                                   primary: Bool) -> some View {
        let button = Button {
            answer(choice, DuckFeedback.Reason.allCases.filter { reasons.contains($0) })
            reasons = []
            playhead = 0
            isRunning = true
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        if primary { button.buttonStyle(.primaryAction) } else { button.buttonStyle(AuthoringActionStyle()) }
    }
}

/// Fetches both clips, then shows the duel.
struct DuelView: View {
    let left: Compare.Contender
    let right: Compare.Contender
    let command: Int
    @ObservedObject var library: LibraryModel
    @ObservedObject var drafts: DraftStore
    @ObservedObject var sequences: SequenceStore
    @ObservedObject var benches: BenchStore
    @ObservedObject var store: CompareStore

    @State private var clips: (DuckIntentClip, DuckIntentClip)?
    @State private var failure: String?
    @State private var done = false

    var body: some View {
        Group {
            if done {
                VStack(spacing: Theme.spacing(.snug)) {
                    Image(systemName: "checkmark.seal.fill").font(.largeTitle)
                        .foregroundStyle(Theme.measured)
                    Text(CompareWords.tally(store.today, streak: store.streak))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let clips {
                DuelStage(left: clips.0, right: clips.1, caption: caption) { choice, reasons in
                    store.pick(left: left, right: right, chose: choice, reasons: reasons,
                               context: "duel", command: commandVector, clips: clips)
                    done = true
                }
            } else {
                Loading(failure: failure)
            }
        }
        .navigationTitle("\(left.name) vs \(right.name)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var twist: DuckDrive.Twist { CompareWords.commands[command].twist }
    private var commandVector: [Double]? {
        left.kind.takesACommand ? [twist.vx, twist.vy, twist.vyaw] : nil
    }
    private var caption: String {
        left.kind.takesACommand ? "Both asked to: \(CompareWords.commands[command].name.lowercased())"
                                : "Both run in the same physics"
    }

    private func load() async {
        guard clips == nil else { return }
        do {
            let a = try await ContenderRunner.clip(for: left, command: twist, library: library,
                                                   drafts: drafts, sequences: sequences, benches: benches)
            let b = try await ContenderRunner.clip(for: right, command: twist, library: library,
                                                   drafts: drafts, sequences: sequences, benches: benches)
            clips = (a, b)
        } catch {
            failure = ContenderRunner.words(error)
        }
    }
}

private struct Loading: View {
    let failure: String?
    var body: some View {
        VStack(spacing: Theme.spacing(.snug)) {
            if let failure {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                Text(failure).font(.footnote).multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ProgressView()
                Text(CompareWords.running).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - a tournament

struct TournamentView: View {
    @State var tournament: Compare.Tournament
    let command: Int
    @ObservedObject var library: LibraryModel
    @ObservedObject var drafts: DraftStore
    @ObservedObject var sequences: SequenceStore
    @ObservedObject var benches: BenchStore
    @ObservedObject var store: CompareStore
    /// Improve by choosing keeps the champion; a plain tournament shows it.
    let onChampion: ((Compare.Contender) -> String?)?

    @State private var clips: [String: DuckIntentClip] = [:]
    @State private var pair: (a: Int, b: Int)?
    @State private var failure: String?
    @State private var keptLine: String?
    @State private var id = UUID().uuidString.lowercased()

    private var twist: DuckDrive.Twist { CompareWords.commands[command].twist }

    var body: some View {
        Group {
            if let champion = tournament.champion {
                championCard(champion)
            } else if let pair, let a = clips[tournament.contenders[pair.a].id],
                      let b = clips[tournament.contenders[pair.b].id] {
                DuelStage(left: a, right: b,
                          caption: CompareWords.progress(tournament.results.count,
                                                         of: tournament.length)) { choice, reasons in
                    store.pick(left: tournament.contenders[pair.a],
                               right: tournament.contenders[pair.b], chose: choice,
                               reasons: reasons, context: "tournament",
                               command: tournament.contenders[pair.a].kind.takesACommand
                                   ? [twist.vx, twist.vy, twist.vyaw] : nil,
                               tournament: id, clips: (a, b))
                    tournament.record(a: pair.a, b: pair.b, choice: choice)
                    self.pair = tournament.nextPair()
                    if tournament.isFinished { Haptic.finished() }
                }
                .id("\(pair.a)-\(pair.b)-\(tournament.results.count)")
            } else {
                Loading(failure: failure)
            }
        }
        .navigationTitle(CompareWords.tournament)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard clips.isEmpty else { return }
        do {
            for c in tournament.contenders {
                clips[c.id] = try await ContenderRunner.clip(for: c, command: twist, library: library,
                                                             drafts: drafts, sequences: sequences,
                                                             benches: benches)
            }
            pair = tournament.nextPair()
        } catch {
            failure = ContenderRunner.words(error)
        }
    }

    private func championCard(_ champion: Compare.Contender) -> some View {
        List {
            Section {
                VStack(spacing: Theme.spacing(.tight)) {
                    Image(systemName: "trophy.fill").font(.system(size: 48))
                        .foregroundStyle(Theme.warning)
                    Text(CompareWords.champion).font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(champion.name).font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    if let clip = clips[champion.id] {
                        ChampionReplay(clip: clip).frame(height: 220)
                    }
                    if let onChampion {
                        if let keptLine {
                            Text(keptLine).font(.footnote).foregroundStyle(Theme.measured)
                        } else {
                            Button(CompareWords.keepChampion) { keptLine = onChampion(champion) }
                                .buttonStyle(.primaryAction)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.spacing(.snug))
            }
            .listRowBackground(Theme.surfacePrimary)
            Section {
                ForEach(Array(tournament.ranking().enumerated()), id: \.element.contender.id) { i, row in
                    HStack {
                        Text("\(i + 1).").monospacedDigit().foregroundStyle(Theme.textSecondary)
                        Text(row.contender.name)
                        Spacer()
                        Text(String(format: "%.0f%%", row.share * 100))
                            .monospacedDigit().foregroundStyle(Theme.textSecondary)
                    }
                }
            } header: {
                SectionHeading(text: CompareWords.standings)
            } footer: {
                Text(CompareWords.tally(store.today, streak: store.streak))
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
    }
}

/// The champion, looping.
private struct ChampionReplay: View {
    let clip: DuckIntentClip
    @State private var orbit = OrbitState()
    var body: some View {
        TimelineView(.animation) { context in
            let t = clip.duration > 0
                ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: clip.duration)
                : 0
            DuckStage(pose: .at(clip.pose(at: t)), environment: clip.environment, orbit: $orbit)
        }
    }
}

// MARK: - improving one thing by choosing

struct ImproveView: View {
    @ObservedObject var library: LibraryModel
    @ObservedObject var drafts: DraftStore
    @ObservedObject var sequences: SequenceStore
    @ObservedObject var benches: BenchStore
    @ObservedObject var store: CompareStore

    @State private var searching: IntentDraft?

    var body: some View {
        List {
            Section {
                let yours = drafts.drafts.filter { !$0.keys.isEmpty }
                if yours.isEmpty {
                    Text("No motions of yours yet. Write one in Studio → Motions.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                ForEach(yours) { draft in
                    Button(draft.name) { searching = draft }
                }
            } header: {
                SectionHeading(text: "A motion")
            } footer: {
                Text("Pick between two versions at a time; each pick moves the search toward what you like, and the one you keep replaces the keyframes.")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                let runnable = sequences.sequences.filter { $0.benchPolicy != nil }
                if runnable.isEmpty {
                    Text("No sequences yet. Record one on Play with Record what I do.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                ForEach(runnable) { seq in
                    NavigationLink(seq.name) { variantsTournament(seq) }
                }
            } header: {
                SectionHeading(text: "A sequence")
            } footer: {
                Text("Five versions of the same drive: as driven, gentler, bolder, quicker, slower. A short tournament picks the best, and you can keep it.")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(CompareWords.improve)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $searching) { draft in
            NavigationStack {
                PreferenceSearchView(draft: draft, scene: nil) { chosen in
                    var kept = draft
                    kept.keys = chosen.keys
                    drafts.save(kept)
                    store.counted()
                }
            }
        }
    }

    @ViewBuilder private func variantsTournament(_ seq: DuckSequence) -> some View {
        let variants = Compare.variants(of: seq)
        let contenders = variants.map { v -> Compare.Contender in
            let key = "variant:\(v.sequence.id.uuidString)"
            ContenderRunner.transient[key] = v.sequence
            return Compare.Contender(kind: .sequence, name: v.label, digest: v.sequence.compareDigest,
                                     source: .yours, key: key)
        }
        if let t = try? Compare.Tournament(contenders) {
            TournamentView(tournament: t, command: 0, library: library, drafts: drafts,
                           sequences: sequences, benches: benches, store: store) { champion in
                guard let chosen = ContenderRunner.transient[champion.key] else { return nil }
                if champion.name == variants.first?.label { return "The original won. Nothing to change." }
                return sequences.save(chosen) ? CompareWords.kept(chosen.name)
                                              : "That version could not be kept."
            }
        }
    }
}


/// The ball a shot moves, as the stage's one kind of prop that can roll.
enum ShootBall {
    static let id = UUID(uuidString: "5B0C0000-0000-4000-8000-000000000001")!
    static func prop(at p: SIMD2<Double>) -> DuckScene.Prop {
        // A FIXED id and a fixed first position, so the stage builds the ball
        // once and `rolling` moves it; a prop whose fields change every frame
        // would be rebuilt every frame.
        DuckScene.Prop(id: id, name: "ball", shape: .ball, x: 0, y: 0, grams: 30,
                       thicknessMillimetres: 100, length: 0.10)
    }
}
