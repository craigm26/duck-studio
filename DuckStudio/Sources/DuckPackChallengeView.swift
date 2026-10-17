import SwiftUI
import StudioKit

/// One challenge: the board, a row laid from the pack's cards, the row played on the board step by
/// step, and the same row sent to the duck as a plan.
///
/// ONLY THE PACK'S CARDS ARE OFFERED. A pack narrows what is printed and offered, not what a duck may
/// do, so a row the camera read may hold a card the pack does not play; it is taken as it lies, and
/// the kit's sentence says which cards are not in the game (`Pack.notInPlay`).
///
/// THE BOARD PLAYS BY THE BOARD RULE AND SAYS SO. Solved, the score and par are the kit's
/// (`DuckPacks.play`), word for word; nothing here works out where a duck is.
///
/// "RUN ON THE DUCK" IS THE PATH A ROW READ OFF CARDS ALREADY TAKES. The row is handed to
/// `PlanEditorView` as a proposal (`DuckPacks.handed`, the board's twin of `DuckCards.handed`), every
/// step shown, and nothing moves until Run is pressed there. The deck is the one the board played
/// with, so the duck runs the steps the board showed.
///
/// ONE DECK, THE CLASS'S. Board play and Run on the duck use the class deck, with the pack's Your
/// cards lent only where the class has none (`DuckPacksStore.playDeck`): on a clash the class's own
/// meaning plays, as the camera reads it and the duck's card reader runs it, and this screen says so.
struct DuckPackChallengeView: View {
    let pack: DuckPacks.Pack
    let challenge: DuckPacks.Challenge
    /// The camera card's feed, for the row it reads; nil where Packs was opened without one.
    var camera: DuckCameraFeed? = nil
    var robot: BridgeLink? = nil
    var models: EndpointStore? = nil
    var stopDriving: (() async -> Void)? = nil

    @ObservedObject private var store = DuckPacksStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var row: [DuckCards.Entry] = []
    /// What the kit's reader said about a row taken from the camera.
    @State private var notes: [String] = []
    @State private var play: DuckPacks.Play?
    /// How many places of the play's path are on the board so far.
    @State private var shown = 1
    @State private var finished = false
    @State private var playing: Task<Void, Never>?

    private var deck: DuckCards.Deck? { store.playDeck(pack) }
    private var par: Int { DuckPacks.par(challenge, in: pack) ?? challenge.par }

    /// The cards a row is laid from, and the cards that go under one, in the pack's order.
    private func laid(_ deck: DuckCards.Deck) -> (cards: [DuckCards.Card], under: [DuckCards.Card]) {
        let cards = pack.cards.filter { !["start", "end", "when_falls"].contains($0) }.compactMap { deck.card(code: $0) }
        return (cards.filter { $0.kind != "modifier" }, cards.filter { $0.kind == "modifier" })
    }

    var body: some View {
        List {
            boardSection
            if let deck {
                rowSection(deck)
                cardsSection(deck)
                startingSection
                playSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(challenge.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: row) { _, _ in reset() }
        .onDisappear { playing?.cancel() }
    }

    // MARK: - the board

    private var boardSection: some View {
        Section {
            Text(DuckPacks.Words.hint(challenge))
                .font(.callout).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let note = challenge.note {
                Text(DuckPacks.Words.note(note))
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(DuckPacks.Words.par(par, pack.score))
                .font(.footnote.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            if let finish = challenge.finishWith, let deck {
                Text(DuckPacks.Words.finishWith(finish, deck: deck))
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            if !challenge.gates.isEmpty {
                Text(DuckPacks.Words.gatesToPass(challenge.gates.count))
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DuckPackBoardView(contents: DuckPackBoardContents(challenge),
                              duck: play.map { $0.path[min(shown, $0.path.count) - 1] },
                              trail: play.map { Array($0.path.prefix(shown)) } ?? [],
                              passed: finished ? Set(play?.gatesPassed ?? []) : [],
                              step: shown,
                              label: DuckPacks.Words.board(challenge))
                .padding(.vertical, Theme.spacing(.tight))
            if let play, finished { result(play) }
        } header: {
            SectionHeading(text: DuckPacks.Words.boardHeading)
        } footer: {
            Text(DuckPacks.Words.boardRule).foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func result(_ play: DuckPacks.Play) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Label(play.solved ? DuckPacks.Words.solved : DuckPacks.Words.notSolved,
                  systemImage: play.solved ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                .font(.headline)
                .foregroundStyle(play.solved ? Theme.success : Theme.textPrimary)
            Text(play.said)
                .font(.callout).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(DuckPacks.Words.score(play, pack.score))
                .font(.footnote.monospacedDigit()).foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - the row

    private func rowSection(_ deck: DuckCards.Deck) -> some View {
        Section {
            if row.isEmpty {
                Text(DuckPacks.Words.emptyRow)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(row.enumerated()), id: \.offset) { index, entry in
                entryRow(index, entry, deck)
            }
            if !row.isEmpty {
                Button(DuckPacks.Words.clearRow, role: .destructive) { row = []; notes = [] }
                    .buttonStyle(.borderless)
                    .font(.footnote)
                    .frame(minHeight: DesignMetric.minimumTarget)
            }
            ForEach(notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let clashes = store.clashes(pack)
            if !clashes.isEmpty {
                Label(DuckPacks.Words.classMeaningWins(pack, clashes), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: DuckPacks.Words.rowHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func entryRow(_ index: Int, _ entry: DuckCards.Entry, _ deck: DuckCards.Deck) -> some View {
        let under = laid(deck).under
        return VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack(alignment: .firstTextBaseline) {
                Text(DuckPacks.Words.rowCard(index, entry, deck: deck))
                    .font(.body).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(role: .destructive) {
                    row.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .frame(minWidth: DesignMetric.minimumTarget, minHeight: DesignMetric.minimumTarget)
                .accessibilityLabel(Text(DuckPacks.Words.removeCardLabel(entry, at: index, deck: deck)))
            }
            if entry.card == "repeat" {
                Stepper(DuckCards.Words.repeatTimes(0, of: 1, times: entry.times ?? DuckCards.repeatOffered),
                        value: Binding(get: { entry.times ?? DuckCards.repeatOffered },
                                       set: { row[index] = DuckCards.Entry(card: entry.card, under: entry.under, times: $0) }),
                        in: DuckCards.repeatRange)
                    .font(.callout)
                    .frame(minHeight: DesignMetric.minimumTarget)
            }
            if !under.isEmpty, deck.card(code: entry.card)?.kind == "action" || deck.card(code: entry.card)?.kind == "yours" {
                Menu {
                    ForEach(under, id: \.code) { card in
                        let on = entry.under.contains(card.code)
                        Button(DuckPacks.Words.underIt(card.name, on: on)) {
                            let next = on ? entry.under.filter { $0 != card.code } : entry.under + [card.code]
                            row[index] = DuckCards.Entry(card: entry.card, under: next, times: entry.times)
                        }
                    }
                } label: {
                    Label(DuckPacks.Words.under, systemImage: "square.stack.3d.down.right")
                        .font(.footnote)
                }
                .tint(Theme.actionSecondary)
                .frame(minHeight: DesignMetric.minimumTarget)
            }
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }

    private func cardsSection(_ deck: DuckCards.Deck) -> some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: Theme.spacing(.tight))],
                      alignment: .leading, spacing: Theme.spacing(.tight)) {
                ForEach(laid(deck).cards, id: \.code) { card in
                    Button {
                        row.append(DuckCards.Entry(card: card.code, times: card.code == "repeat" ? DuckCards.repeatOffered : nil))
                    } label: {
                        Text(card.name)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: DesignMetric.minimumTarget, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.actionSecondary)
                }
            }
            .padding(.vertical, Theme.spacing(.hairline))
        } header: {
            SectionHeading(text: DuckPacks.Words.laidHeading)
        } footer: {
            Text(DuckPacks.Words.laidFooter).foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - a row to start from

    @ViewBuilder private var startingSection: some View {
        if camera != nil || challenge.buggy != nil {
            Section {
                if let camera {
                    DuckPackCameraRow(feed: camera) { take($0) }
                }
                if let buggy = challenge.buggy {
                    Button {
                        row = buggy
                        notes = []
                    } label: {
                        Label(DuckPacks.Words.useBuggy, systemImage: "ladybug")
                    }
                    .tint(Theme.actionSecondary)
                    .frame(minHeight: DesignMetric.minimumTarget)
                    Text(DuckPacks.Words.buggyFooter)
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    /// The row the camera reads, as a Your card would hold it (`DuckCards.savedRow`). A Repeat's
    /// number is not read, so each one starts where the camera card's question starts and the
    /// stepper in the row is where it is set.
    private func take(_ reading: DuckCards.Reading) {
        guard let readDeck = DuckCardsStore.shared.deck, let deck else { return }
        do {
            let taken = try DuckCards.savedRow(reading, deck: readDeck,
                                               counts: DuckCards.answers(reading.program.asks, given: [:]))
            row = taken
            notes = pack.notInPlay(taken.flatMap { [$0.card] + $0.under }, deck: deck)
                + (reading.program.asks.isEmpty ? [] : [DuckPacks.Words.cameraRepeats])
        } catch let refusal as DuckCards.Refusal {
            notes = [refusal.message]
        } catch {
            notes = [error.localizedDescription]
        }
    }

    // MARK: - play it, run it

    private var playSection: some View {
        Section {
            if playing != nil && !finished, let play {
                Text(DuckPacks.Words.playing(min(shown, play.path.count) - 1, of: max(play.path.count - 1, 0)))
                    .font(.footnote.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }
            Button(DuckPacks.Words.play) { start() }
                .buttonStyle(.primaryAction)
                .disabled(row.isEmpty)
            NavigationLink {
                planEditor
            } label: {
                Label(DuckPacks.Words.run, systemImage: PlanEditorWords.studioRowSymbol)
            }
            .disabled(row.isEmpty)
            .frame(minHeight: DesignMetric.minimumTarget)
        } footer: {
            Text(DuckPacks.Words.runFooter).foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func reset() {
        playing?.cancel()
        playing = nil
        play = nil
        shown = 1
        finished = false
    }

    /// Play the row, one step on the board at a time. The result is the kit's; this only shows its
    /// path a place at a time, and says solved, the score and par once the last place is shown.
    private func start() {
        guard let deck else { return }
        reset()
        let result = DuckPacks.play(challenge, row: row, score: pack.score, deck: deck)
        play = result
        playing = Task { @MainActor in
            for k in 1..<max(result.path.count, 1) {
                try? await Task.sleep(nanoseconds: 450_000_000)
                if Task.isCancelled { return }
                withAnimation(Theme.motion(reduced: reduceMotion)) { shown = k + 1 }
            }
            if Task.isCancelled { return }
            withAnimation(Theme.motion(reduced: reduceMotion)) { finished = true }
        }
    }

    /// The row as a plan, handed to the editor the way a row read off cards is.
    @ViewBuilder private var planEditor: some View {
        if let deck {
            switch Result(catching: { try DuckPacks.handed(row, deck: deck) }) {
            case .success(let handed):
                PlanEditorView(desk: nil, venue: robot?.isConnected == true ? .real : .sim, engage: {},
                               models: models, robot: robot, stopDriving: stopDriving, handed: handed)
            case .failure(let error):
                List {
                    Label(Self.message(error), systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Theme.surfacePrimary)
                }
                .scrollContentBackground(.hidden)
                .background(Theme.backgroundSecondary)
                .navigationTitle(DuckPacks.Words.run)
            }
        }
    }

    static func message(_ error: Error) -> String {
        if let e = error as? DuckIntentPlan.ReadError { return e.message }
        if let e = error as? DuckCards.Refusal { return e.message }
        return error.localizedDescription
    }
}

/// "Use the row the camera read", watching the camera card's feed so it is offered the moment a row
/// from Start to End is on the table (`DuckCards.savable`), and says why not until then.
struct DuckPackCameraRow: View {
    @ObservedObject var feed: DuckCameraFeed
    let use: (DuckCards.Reading) -> Void

    var body: some View {
        let ready = feed.running && feed.readCards && (feed.reading.map(DuckCards.savable) ?? false)
        Button {
            if let reading = feed.reading { use(reading) }
        } label: {
            Label(DuckPacks.Words.useCamera, systemImage: "camera.viewfinder")
        }
        .tint(Theme.actionSecondary)
        .disabled(!ready)
        .frame(minHeight: DesignMetric.minimumTarget)
        if !ready {
            Text(feed.running && feed.readCards ? DuckPacks.Words.cameraNoRow : DuckPacks.Words.cameraOff)
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
