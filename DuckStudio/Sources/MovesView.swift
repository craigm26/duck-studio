import SwiftUI
import StudioKit
import DuckKit

/// Tab 2: Moves, the toy box (docs/plans/native-first-redesign.md, build 91).
///
/// A TAP ON A SKILL OR A SOUND RUNS ON THE CURRENT DUCK, the one Play is on, with the floating
/// Stop pill shown while it runs. Every run goes through `DuckRuns`, so through `DuckOrderRunner`
/// and `StopPath`: the robot's rules (one move at a time, init and enable first) are the kit's.
///
/// Games never move the real duck and never switch the venue: each opens its own practice screen.
struct MovesView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drafts: DraftStore
    @ObservedObject var benches: BenchStore
    @ObservedObject var models: EndpointStore
    let robot: BridgeLink
    @ObservedObject private var runs = DuckRuns.shared
    @EnvironmentObject private var router: AppRouter

    /// The sequences kept on this phone, read here for the list; playing one is Play's stick
    /// loop, so a tap sends Play the sequence.
    @StateObject private var shelf = PadDesk()

    var body: some View {
        List {
            if let added = router.added {
                Section {
                    Label(added, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.measured)
                        .accessibilityLabel(Text(added))
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            MoveTileSections()

            Section {
                if shelf.sequences.isEmpty {
                    Text(MoveTileSections.noSequences)
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(shelf.sequences) { sequence in
                    Button {
                        router.go(to: .play(.sequence(sequence.id)))
                    } label: {
                        Label(sequence.name, systemImage: "list.bullet.rectangle")
                            .frame(minHeight: DesignMetric.minimumTarget)
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
            } header: {
                SectionHeading(text: MoveTileSections.mySequences)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                NavigationLink {
                    PlanEditorView(desk: nil, venue: .sim, engage: {}, models: models, robot: robot)
                } label: {
                    HubRow(PlanEditorWords.studioRow, StudioHubWords.plan, PlanEditorWords.studioRowSymbol)
                }
                NavigationLink {
                    DuckPacksView(robot: robot, models: models)
                } label: {
                    HubRow(DuckPacks.Words.packs, "Cards a camera can read, in packs for a class.",
                           "square.grid.3x3")
                }
            } header: {
                SectionHeading(text: "My plans, cards and packs")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                NavigationLink {
                    DuckSoccerView(library: model, drafts: drafts, benches: benches)
                } label: {
                    HubRow("Duck soccer", "Practice duck only. Score on a pitch.", "soccerball")
                }
                NavigationLink {
                    GhostDuckView()
                } label: {
                    HubRow("Golf, fetch and more", "Practice duck only. Games on the ghost duck.",
                           "figure.golf")
                }
            } header: {
                SectionHeading(text: "Games")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                ForEach(AutoGoal.allCases) { goal in
                    Button {
                        router.go(to: .play(.auto))
                    } label: {
                        HubRow(goal.title,
                               goal.subtitle(on: runs.duck, driverInstalled: PhoneDrivers.installed),
                               goal.symbol)
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
            } header: {
                SectionHeading(text: "Goals")
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Moves")
        .onAppear { shelf.reloadShelf() }
        // THE "ADDED" CHIP IS SHOWN ONCE: it goes when the person leaves Moves.
        .onDisappear { router.added = nil }
        .safeAreaInset(edge: .bottom) {
            if let caption = runs.caption {
                Text(caption)
                    .font(.footnote)
                    .padding(Theme.spacing(.tight))
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .padding(.bottom, runs.isRunning ? StopMetric.pillHeight + Theme.spacing(.loose) : 0)
            }
        }
    }
}

/// Phone drivers installed in this app. None yet: the phone driver's app half is a later build,
/// and the Auto card says so rather than pretending.
enum PhoneDrivers {
    static var installed: Bool { false }
}

/// Skills and sounds as tiles, on the Moves tab and in Play's pull-up Moves sheet: the same
/// tiles in both places. A tap runs on the duck Play is on, through `DuckRuns`, with the Stop pill
/// showing while it runs.
struct MoveTileSections: View {
    @ObservedObject private var runs = DuckRuns.shared

    static let mySequences = "My sequences"
    static let noSequences = "Nothing kept yet. Record one from Play, More."

    /// The robot's one-shot skills, by the names robotd uses. Sit and stand are one skill on the
    /// robot and live on Play's buttons, so the toggle is not offered here.
    private var skills: [String] {
        RobotPlan.skillSeconds.keys.filter { $0 != DuckOrder.sitToggle }.sorted()
    }

    var body: some View {
        Section {
            if runs.duck == nil {
                Text(ControllerWords.tellNoDuck)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(skills, id: \.self) { name in
                tile(name.replacingOccurrences(of: "_", with: " ").capitalized,
                     symbol: "figure.run", order: .skill(name))
            }
        } header: {
            SectionHeading(text: "Skills")
        } footer: {
            if runs.duck == .sim {
                Text("The practice duck has no skills of its own; a real duck does.")
            }
        }
        .listRowBackground(Theme.surfacePrimary)

        Section {
            ForEach(DuckSound.allCases, id: \.self) { sound in
                tile(sound.rawValue.capitalized, symbol: "speaker.wave.2", order: .sound(sound))
            }
        } header: {
            SectionHeading(text: "Sounds")
        } footer: {
            if runs.duck == .sim {
                Text(DuckOrder.PracticeWords.noVoice)
            }
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func tile(_ title: String, symbol: String, order: DuckOrder) -> some View {
        Button {
            Task { _ = await runs.run(order) }
        } label: {
            Label(title, systemImage: symbol)
        }
        // THE PRACTICE DUCK HAS NO SKILLS AND NO VOICE (build 92): these tiles were enabled there
        // and failed with a Swift case name nobody saw. Now they are dimmed, and the footer says why.
        .disabled(runs.duck == nil || runs.isRunning || runs.duck.flatMap(order.notOn) != nil)
        .frame(minHeight: DesignMetric.minimumTarget)
    }
}
