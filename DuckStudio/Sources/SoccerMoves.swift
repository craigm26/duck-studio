import SwiftUI
import DuckKit
import StudioKit

/// Your moves in Duck Soccer: the loadout, kept on this phone, and the clips
/// it resolves to before kick-off.
@MainActor final class SoccerMovesStore: ObservableObject {
    @Published var loadout: SoccerLoadout {
        didSet { UserDefaults.standard.set(loadout.encoded(), forKey: Self.key); clips = [:] }
    }
    /// The resolved clips, by slot. Empty until `prepare` runs.
    @Published private(set) var clips: [SoccerLoadout.Slot: DuckIntentClip] = [:]
    @Published private(set) var preparing: String?
    @Published private(set) var problems: [SoccerLoadout.Slot: String] = [:]

    private static let key = "duckstudio.soccerLoadout"

    init() {
        loadout = SoccerLoadout.decoded(UserDefaults.standard.string(forKey: Self.key) ?? "")
    }

    var moves: DuckSoccer.Moves { SoccerLoadout.moves(from: clips) }

    /// Turn every chosen skill into a clip. Motions are instant; behaviours,
    /// drafts, sequences and your shooter are recorded once on the bench.
    func prepare(library: LibraryModel, drafts: DraftStore, benches: BenchStore) async {
        problems = [:]
        let sequences = SequenceStore()
        for slot in SoccerLoadout.Slot.allCases {
            guard clips[slot] == nil, let skill = loadout[slot] else { continue }
            preparing = "Getting \(skill.name) ready…"
            do {
                if skill.kind == Compare.Contender.Kind.shooter.rawValue {
                    clips[slot] = try await Self.shooterKick(benches: benches)
                } else if let contender = skill.contender {
                    clips[slot] = try await ContenderRunner.clip(
                        for: contender, command: CompareWords.commands[0].twist,
                        library: library, drafts: drafts, sequences: sequences, benches: benches)
                }
            } catch {
                problems[slot] = ContenderRunner.words(error)
            }
        }
        preparing = nil
    }

    /// Your trained shooter's kick: one shot from the middle spot, cut to the
    /// kick itself (from the swap to the kick network, 1.5 s on).
    private static func shooterKick(benches: BenchStore) async throws -> DuckIntentClip {
        let saved = UserDefaults.standard.string(forKey: "duckstudio.shooter") ?? ""
        guard let o = try? JSONSerialization.jsonObject(with: Data(saved.utf8)) as? [String: Any]
        else { throw ContenderRunner.Failure.said("Keep a shooter in Train a duck to shoot first.") }
        var values: [String: Double] = [:]
        for (k, v) in o { if let d = v as? Double { values[k] = d } }
        let params = Shoot.Params(values: values, foot: o["foot"] as? String ?? "auto").clamped
        guard let bench = benches.selected else { throw ContenderRunner.Failure.said(ShootWords.noBench) }
        let call = try Shoot.call(try bench.resolved(), cell: Shoot.coreCells[4], params: params)
        let data = try await URLSession.shared.data(
            for: DuckBench.urlRequest(for: call, token: benches.armed(bench).token)).0
        let shot = try Shoot.read(data, cell: Shoot.coreCells[4], named: "Your shooter")
        guard let kick = shot.phases.first(where: { $0.phase == "kick" }) else {
            throw ContenderRunner.Failure.said("Your shooter did not kick from the middle spot.")
        }
        let c = shot.clip
        let from = Int(kick.at * c.hz), to = min(from + Int(1.5 * c.hz), c.frames.count)
        guard to > from else { throw ContenderRunner.Failure.said("Your shooter's kick was too short to use.") }
        return DuckIntentClip(name: "Your shooter", hz: c.hz, frames: Array(c.frames[from..<to]),
                              roots: c.roots.isEmpty ? [] : Array(c.roots[from..<min(to, c.roots.count)]),
                              netYaw: 0, loops: false, startsFrom: .standing, endsIn: c.endsIn,
                              policy: c.policy, authored: false, environment: .bareFloor)
    }

    /// Everything that could go in a slot, grouped for the picker.
    func candidates(library: LibraryModel, drafts: DraftStore) -> [(title: String, items: [Compare.Contender])] {
        let sequences = SequenceStore()
        var groups: [(String, [Compare.Contender])] = [
            ("Motions", ContenderCatalog.all(.motion, library: library, drafts: drafts, sequences: sequences)),
            ("Your motions", ContenderCatalog.all(.draft, library: library, drafts: drafts, sequences: sequences)),
            ("Sequences", ContenderCatalog.all(.sequence, library: library, drafts: drafts, sequences: sequences)),
            ("Behaviours", ContenderCatalog.all(.behaviour, library: library, drafts: drafts, sequences: sequences)),
        ]
        if UserDefaults.standard.string(forKey: "duckstudio.shooter")?.isEmpty == false {
            groups.insert(("Your shooter", [Compare.Contender(kind: .shooter, name: "Your trained shooter",
                                                              digest: "sha256:shooter", source: .yours,
                                                              key: "shooter")]), at: 0)
        }
        return groups.filter { !$0.1.isEmpty }
    }
}

/// The loadout editor: four slots, each yours or the standard move.
struct SoccerMovesView: View {
    @ObservedObject var store: SoccerMovesStore
    @ObservedObject var library: LibraryModel
    @ObservedObject var drafts: DraftStore

    var body: some View {
        List {
            Section {
                ForEach(SoccerLoadout.Slot.allCases) { slot in
                    NavigationLink {
                        SoccerSkillPicker(slot: slot, store: store, library: library, drafts: drafts)
                    } label: {
                        HStack(spacing: Theme.spacing(.snug)) {
                            Image(systemName: slot.symbol).frame(width: 28)
                                .foregroundStyle(Theme.actionPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot.title).font(.headline)
                                Text(store.loadout[slot]?.name ?? slot.standard)
                                    .font(.subheadline)
                                    .foregroundStyle(store.loadout[slot] == nil
                                                     ? Theme.textSecondary : Theme.textPrimary)
                                if let problem = store.problems[slot] {
                                    Text(problem).font(.caption).foregroundStyle(Theme.warning)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } footer: {
                Text("Your whole team plays your moves. Skills recorded on a bench decide the effect "
                   + "too; the ball's speed off a kick stays the game's own.")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)
            if !store.loadout.isStandard {
                Section {
                    Button("Back to the standard moves", role: .destructive) {
                        store.loadout = SoccerLoadout()
                    }
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Your moves")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SoccerSkillPicker: View {
    let slot: SoccerLoadout.Slot
    @ObservedObject var store: SoccerMovesStore
    @ObservedObject var library: LibraryModel
    @ObservedObject var drafts: DraftStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                row(name: slot.standard, chosen: store.loadout[slot] == nil) {
                    store.loadout[slot] = nil
                }
            } header: {
                SectionHeading(text: "Standard")
            } footer: {
                Text(slot.effect).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)
            ForEach(store.candidates(library: library, drafts: drafts), id: \.title) { group in
                Section {
                    ForEach(group.items) { c in
                        row(name: c.name, chosen: store.loadout[slot]?.digest == c.digest) {
                            store.loadout[slot] = SoccerLoadout.Skill(c)
                        }
                    }
                } header: {
                    SectionHeading(text: group.title)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(slot.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(name: String, chosen: Bool, pick: @escaping () -> Void) -> some View {
        Button {
            pick(); dismiss()
        } label: {
            HStack {
                Text(name).foregroundStyle(Theme.textPrimary)
                Spacer()
                if chosen { Image(systemName: "checkmark").foregroundStyle(Theme.actionPrimary) }
            }
        }
    }
}
