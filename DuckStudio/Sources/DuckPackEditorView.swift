import SwiftUI
import StudioKit

/// Design a challenge: tap squares for the start and the way it faces, the goal, walls and gates;
/// give it a name and a hint; save it into the class pack.
///
/// EVERY TAP IS THE KIT'S. Which side of a square a tap means, whether a gate may sit there, what
/// happens to a wall when the board shrinks: `DuckPacks.Draft` decides, and this draws it.
///
/// PAR IS WORKED OUT, NEVER TYPED. It is the board rule's own search (`Draft.par`), shown as the board
/// changes (a finishing card counted), and a goal that cannot be reached is said in the kit's
/// sentence before anyone presses Save. Saving checks again (`Draft.checked`) and writes the search's
/// shortest row as the solution. In a class pack scored by cards, par is the plain row's card count,
/// and the author may lower it only by laying a shorter row that the board plays to the goal
/// (`Draft.shorterVerdict`).
///
/// VOICEOVER DRAWS TOO. Each square is an element saying what is on it, with the tool's taps as its
/// actions, so walls and gates can be placed without seeing the board.
struct DuckPackEditorView: View {
    @State var draft: DuckPacks.Draft

    @ObservedObject private var store = DuckPacksStore.shared
    @State private var tool: DuckPacks.Words.Tool = .start
    @State private var said: String?
    @State private var refusal: String?

    /// The cards in play in the class pack, as the teacher set them.
    private var cards: [String] { store.classCards }
    private var score: DuckPacks.Score { store.settings.score }
    private var deck: DuckCards.Deck? { DuckCardsStore.shared.deck }
    private var packName: String { store.settings.shownName }

    /// The cards a shorter row is laid from: the cards in play that sit in a row on their own.
    private func layable(_ deck: DuckCards.Deck) -> [DuckCards.Card] {
        cards.filter { !["start", "end", "when_falls"].contains($0) }
            .compactMap { deck.card(code: $0) }
            .filter { $0.kind != "modifier" && $0.kind != "yours" }
    }

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
                Text(DuckPacks.Words.draftPar(draft.par(cards: cards), score, finishing: draft.finishWith != nil))
                    .font(.callout).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SectionHeading(text: DuckPacks.Words.parHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            if let deck { finishSection(deck) }
            if score == .cards, let deck { shorterSection(deck) }

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
                TextField(DuckPacks.Words.notePlaceholder, text: $draft.note)
                    .frame(minHeight: DesignMetric.minimumTarget)
            } header: {
                SectionHeading(text: DuckPacks.Words.noteHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Button(DuckPacks.Words.save(to: packName)) { save() }
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
                Text(DuckPacks.Words.designFooter(packName)).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(DuckPacks.Words.design)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft) { _, _ in said = nil; refusal = nil }
    }

    /// A card the row must end with, among the cards in play the duck does standing still, or None.
    private func finishSection(_ deck: DuckCards.Deck) -> some View {
        Section {
            Picker(DuckPacks.Words.finishHeading, selection: $draft.finishWith) {
                Text(DuckPacks.Words.finishNone).tag(String?.none)
                ForEach(DuckPacks.Draft.finishes(cards, deck: deck), id: \.self) { code in
                    Text(deck.card(code: code)?.name ?? code).tag(String?.some(code))
                }
            }
            .frame(minHeight: DesignMetric.minimumTarget)
        } header: {
            SectionHeading(text: DuckPacks.Words.finishHeading)
        } footer: {
            Text(DuckPacks.Words.finishFooter).foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// Scored by cards: a row the author lays to beat the plain row, played on the board as it is
    /// laid, and said whether it lowers par.
    private func shorterSection(_ deck: DuckCards.Deck) -> some View {
        Section {
            ForEach(Array(draft.shorter.enumerated()), id: \.offset) { index, entry in
                HStack(alignment: .firstTextBaseline) {
                    Text(DuckPacks.Words.laidCard(index, entry, deck: deck))
                        .font(.body).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if entry.card == "repeat" {
                        Stepper(DuckCards.Words.repeatTimes(0, of: 1, times: entry.times ?? DuckCards.repeatOffered),
                                value: Binding(get: { entry.times ?? DuckCards.repeatOffered },
                                               set: { draft.shorter[index] = DuckCards.Entry(card: entry.card, times: $0) }),
                                in: DuckCards.repeatRange)
                            .labelsHidden()
                            .accessibilityLabel(Text(DuckCards.Words.repeatTimes(0, of: 1, times: entry.times ?? DuckCards.repeatOffered)))
                    }
                    Button(role: .destructive) {
                        draft.shorter.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: DesignMetric.minimumTarget, minHeight: DesignMetric.minimumTarget)
                    .accessibilityLabel(Text(DuckPacks.Words.removeCardLabel(entry, at: index, deck: deck)))
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Theme.spacing(.tight))],
                      alignment: .leading, spacing: Theme.spacing(.tight)) {
                ForEach(layable(deck), id: \.code) { card in
                    Button {
                        draft.shorter.append(DuckCards.Entry(card: card.code,
                                                             times: card.code == "repeat" ? DuckCards.repeatOffered : nil))
                    } label: {
                        Text(card.name)
                            .font(.callout)
                            .frame(maxWidth: .infinity, minHeight: DesignMetric.minimumTarget, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.actionSecondary)
                }
            }
            .padding(.vertical, Theme.spacing(.hairline))
            Text(DuckPacks.Words.shorter(draft.shorterVerdict(cards: cards, deck: deck)))
                .font(.callout).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !draft.shorter.isEmpty {
                Button(DuckPacks.Words.clearRow, role: .destructive) { draft.shorter = [] }
                    .buttonStyle(.borderless)
                    .font(.footnote)
                    .frame(minHeight: DesignMetric.minimumTarget)
            }
        } header: {
            SectionHeading(text: DuckPacks.Words.shorterHeading)
        } footer: {
            Text(DuckPacks.Words.shorterFooter).foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
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
            said = DuckPacks.Words.saved(try store.save(draft), in: packName)
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
