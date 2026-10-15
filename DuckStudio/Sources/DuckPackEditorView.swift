import SwiftUI
import StudioKit

/// Design a challenge: tap squares for the start and the way it faces, the goal, walls and gates;
/// give it a name and a hint; save it into the class pack.
///
/// EVERY TAP IS THE KIT'S. Which side of a square a tap means, whether a gate may sit there, what
/// happens to a wall when the board shrinks: `DuckPacks.Draft` decides, and this draws it.
///
/// PAR IS WORKED OUT, NEVER TYPED. It is the board rule's own search (`Draft.par`), shown as the board
/// changes, and a goal that cannot be reached is said in the kit's sentence before anyone presses
/// Save. Saving checks again (`Draft.checked`) and writes the search's shortest row as the solution.
///
/// VOICEOVER DRAWS TOO. Each square is an element saying what is on it, with the tool's taps as its
/// actions, so walls and gates can be placed without seeing the board.
struct DuckPackEditorView: View {
    @State var draft: DuckPacks.Draft

    @ObservedObject private var store = DuckPacksStore.shared
    @State private var tool: DuckPacks.Words.Tool = .start
    @State private var said: String?
    @State private var refusal: String?

    private var cards: [String] { DuckCardsStore.shared.deck.map(DuckPacks.ClassPack.cards) ?? [] }

    var body: some View {
        List {
            Section {
                Picker(DuckPacks.Words.toolHeading, selection: $tool) {
                    ForEach(DuckPacks.Words.Tool.allCases, id: \.self) { t in
                        Text(t.name).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: DesignMetric.minimumTarget)
                Text(tool.help)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                DuckPackBoardView(contents: DuckPackBoardContents(draft), editing: editing)
                    .padding(.vertical, Theme.spacing(.tight))
            } header: {
                SectionHeading(text: DuckPacks.Words.toolHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Text(DuckPacks.Words.draftPar(draft.par(cards: cards)))
                    .font(.callout).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SectionHeading(text: DuckPacks.Words.parHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Stepper(DuckPacks.Words.columns(draft.columns),
                        value: Binding(get: { draft.columns }, set: { draft.resize(columns: $0, rows: draft.rows) }),
                        in: DuckPacks.Draft.smallest...DuckPacks.largestBoard)
                    .frame(minHeight: DesignMetric.minimumTarget)
                Stepper(DuckPacks.Words.rows(draft.rows),
                        value: Binding(get: { draft.rows }, set: { draft.resize(columns: draft.columns, rows: $0) }),
                        in: DuckPacks.Draft.smallest...DuckPacks.largestBoard)
                    .frame(minHeight: DesignMetric.minimumTarget)
            } header: {
                SectionHeading(text: DuckPacks.Words.sizeHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                TextField(DuckPacks.Words.namePlaceholder, text: $draft.name)
                    .frame(minHeight: DesignMetric.minimumTarget)
            } header: {
                SectionHeading(text: DuckPacks.Words.nameHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                TextField(DuckPacks.Words.hintPlaceholder, text: $draft.hint, axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                SectionHeading(text: DuckPacks.Words.hintHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Button(DuckPacks.Words.save) { save() }
                    .buttonStyle(.primaryAction)
                    .disabled(said != nil)
                if let refusal {
                    Label(refusal, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let said {
                    Label(said, systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text(DuckPacks.Words.designFooter).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(DuckPacks.Words.design)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft) { _, _ in said = nil; refusal = nil }
    }

    /// The board's taps and VoiceOver actions, for the tool in hand.
    private var editing: DuckPackBoardEditing {
        DuckPackBoardEditing(
            tap: { square, across, down in
                switch tool {
                case .start: draft.placeStart(square)
                case .goal: draft.placeGoal(square)
                case .gates: draft.cycleGate(square)
                case .walls:
                    if let other = draft.neighbour(square, DuckPacks.Draft.side(across: across, down: down)) {
                        draft.toggleWall(square, other)
                    }
                }
            },
            label: { DuckPacks.Words.square($0, in: draft) },
            actions: { square in
                switch tool {
                case .start: return [DuckPackBoardEditing.Action(name: DuckPacks.Words.placeStart) { draft.placeStart(square) }]
                case .goal: return [DuckPackBoardEditing.Action(name: DuckPacks.Words.placeGoal) { draft.placeGoal(square) }]
                case .gates: return [DuckPackBoardEditing.Action(name: DuckPacks.Words.cycleGate) { draft.cycleGate(square) }]
                case .walls:
                    return DuckPacks.Facing.allCases.compactMap { side -> DuckPackBoardEditing.Action? in
                        guard let other = draft.neighbour(square, side) else { return nil }
                        return DuckPackBoardEditing.Action(name: DuckPacks.Words.wall(side, on: draft.hasWall(square, other))) {
                            draft.toggleWall(square, other)
                        }
                    }
                }
            })
    }

    private func save() {
        refusal = nil
        do {
            said = DuckPacks.Words.saved(try store.save(draft))
        } catch let refused as DuckPacks.DraftRefusal {
            refusal = refused.message
        } catch let refused as DuckPacks.Refusal {
            refusal = refused.message
        } catch let refused as DuckCards.Refusal {
            refusal = refused.message
        } catch {
            refusal = error.localizedDescription
        }
    }
}
