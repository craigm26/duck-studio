import SwiftUI
import StudioKit

/// What the camera card opens: cards held still, for the plan editor or to save as a Your card, the
/// class deck the cards are read with, or the Duck Card packs.
struct DuckCardsOpening: Identifiable {
    enum Kind { case plan, save, deck, packs }
    let id = UUID()
    let kind: Kind
    /// The reading held still when the button was pressed; nil for the class deck and the packs.
    let held: DuckCards.Reading?
}

/// Cards held still from the camera, on their way into the plan editor or the class deck.
///
/// HELD, NOT LIVE. The camera reads four times a second and a hand moves; what goes on from here
/// is the reading as it was when the button was pressed, said again at the top so the person sees
/// what was held.
///
/// A REPEAT IS ASKED ABOUT FIRST. Studio does not read the number written on a Repeat card, so it
/// asks for each one and nothing goes on until the person says the numbers are right — a stepper
/// that starts at 2 is a question, not an answer. Then the row is read again with the answers.
///
/// THE EDITOR STILL DECIDES. A row read off cards arrives in `PlanEditorView` as a proposal, every
/// step shown, and nothing moves until Run is pressed there.
struct DuckCardsSheet: View {
    let opening: DuckCardsOpening
    var robot: BridgeLink? = nil
    var models: EndpointStore? = nil
    var stopDriving: (() async -> Void)? = nil
    /// The camera card's feed, so a pack's challenge can take the row the camera reads now.
    var camera: DuckCameraFeed? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DuckCardsStore.shared
    /// The numbers on the steppers, by the positions `Program.asks` gives.
    @State private var given: [Int: Int] = [:]
    /// The numbers the person said are right; nil until they do.
    @State private var counts: [Int: Int]?

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(DuckCards.Words.close) { dismiss() }
                    }
                }
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
#endif
    }

    @ViewBuilder private var content: some View {
        if opening.kind == .deck {
            DuckCardsDeckView()
        } else if opening.kind == .packs {
            DuckPacksView(camera: camera, robot: robot, models: models, stopDriving: stopDriving)
        } else if let held = opening.held, let deck = store.deck {
            if let reading = answered(held, deck) {
                if opening.kind == .plan {
                    editor(reading, deck)
                } else {
                    DuckCardSaveForm(reading: reading, counts: counts ?? [:])
                }
            } else {
                questions(held)
            }
        }
    }

    /// The held reading with its Repeat numbers given, or nil while one is still asked about.
    private func answered(_ held: DuckCards.Reading, _ deck: DuckCards.Deck) -> DuckCards.Reading? {
        if held.program.asks.isEmpty { return held }
        guard let counts else { return nil }
        return DuckCards.answered(held, deck: deck, counts: counts)
    }

    /// What a Repeat's stepper shows: the number given, or where the question starts.
    private func shown(_ ask: Int) -> Int {
        DuckCards.answers([ask], given: given)[ask] ?? DuckCards.repeatOffered
    }

    // MARK: - how many times

    private func questions(_ held: DuckCards.Reading) -> some View {
        List {
            Section {
                Text(DuckCards.Words.sees(held))
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SectionHeading(text: DuckCards.Words.heldHeading)
            } footer: {
                Text(DuckCards.Words.heldFooter).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                ForEach(Array(held.program.asks.enumerated()), id: \.element) { index, ask in
                    Stepper(DuckCards.Words.repeatTimes(index, of: held.program.asks.count, times: shown(ask)),
                            value: Binding(get: { shown(ask) }, set: { given[ask] = $0 }),
                            in: DuckCards.repeatRange)
                        .font(.callout)
                        .frame(minHeight: DesignMetric.minimumTarget)
                }
                Button(DuckCards.Words.useTheseNumbers) {
                    counts = DuckCards.answers(held.program.asks, given: given)
                }
                .buttonStyle(.primaryAction)
            } header: {
                SectionHeading(text: DuckCards.Words.howManyTimes)
            } footer: {
                Text(DuckCards.Words.repeatAsked).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(DuckCards.Words.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - into the plan editor

    /// The format's own plan, read back through `DuckIntentPlan.read`, proposed by the cards and the
    /// deck they were read with. On a duck that is connected it runs on the duck; otherwise it can
    /// be kept as a sequence, as a plan opened from Studio can.
    @ViewBuilder private func editor(_ reading: DuckCards.Reading, _ deck: DuckCards.Deck) -> some View {
        switch Result(catching: { try DuckCards.handed(reading, deck: deck) }) {
        case .success(let handed):
            PlanEditorView(desk: nil, venue: robot?.isConnected == true ? .real : .sim, engage: {},
                           models: models, robot: robot, stopDriving: stopDriving, handed: handed)
        case .failure(let error):
            List {
                Label((error as? DuckIntentPlan.ReadError)?.message ?? error.localizedDescription,
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Theme.surfacePrimary)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
            .navigationTitle(DuckCards.Words.title)
        }
    }
}

/// Save a row of cards as a Your card: a number, a name, and what it does.
///
/// THE NUMBER IS THE PRINTED CARD. The picker offers the free numbers first, the printed blanks
/// before the rest, then the numbers that already mean something; saving over one of those is asked
/// about first, naming the cards it changes. Once saved, the screen says which blank to write the
/// name on, because the deck knows the card now and the card does not know its name yet.
///
/// EVERY CHECK IS THE KIT'S. Which numbers are free, whether a row can be saved, what a loop or a
/// fifth Your card deep is called: `DuckCards.ClassDeck` decides and says, and this draws it.
struct DuckCardSaveForm: View {
    let reading: DuckCards.Reading
    /// The Repeat numbers the person gave, by the positions `Program.asks` gave.
    let counts: [Int: Int]

    @ObservedObject private var store = DuckCardsStore.shared
    @State private var number: Int?
    @State private var name = ""
    @State private var does = ""
    @State private var said: String?
    @State private var refusal: String?
    /// The card a save would replace, while the person is asked about it.
    @State private var replacing: DuckCards.Card?

    var body: some View {
        List {
            Section {
                Text(DuckCards.Words.sees(reading))
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !reading.program.onFall.isEmpty {
                    Label(DuckCards.Words.fallNotInCard, systemImage: "info.circle")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                SectionHeading(text: DuckCards.Words.heldHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Picker(DuckCards.Words.numberLabel, selection: $number) {
                    ForEach(store.classDeck?.numbers ?? [], id: \.self) { tag in
                        Text(choice(tag)).tag(Optional(tag))
                    }
                }
                .pickerStyle(.menu)
                .frame(minHeight: DesignMetric.minimumTarget)
            } header: {
                SectionHeading(text: DuckCards.Words.numberHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                TextField(DuckCards.Words.namePlaceholder, text: $name)
                    .frame(minHeight: DesignMetric.minimumTarget)
            } header: {
                SectionHeading(text: DuckCards.Words.nameHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                TextField(DuckCards.Words.doesPlaceholder, text: $does, axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                SectionHeading(text: DuckCards.Words.doesHeading)
            } footer: {
                Text(DuckCards.Words.doesFooter).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Button(DuckCards.Words.save) { save(replacing: false) }
                    .buttonStyle(.primaryAction)
                    .disabled(number == nil || said != nil)
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
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(DuckCards.Words.saveTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if number == nil { number = store.classDeck?.suggested } }
        .onChange(of: number) { _, _ in said = nil; refusal = nil }
        .onChange(of: name) { _, _ in said = nil; refusal = nil }
        .onChange(of: does) { _, _ in said = nil; refusal = nil }
        .confirmationDialog(replacing.map(DuckCards.Words.replaceTitle) ?? DuckCards.Words.saveTitle,
                            isPresented: Binding(get: { replacing != nil },
                                                 set: { if !$0 { replacing = nil } }),
                            titleVisibility: .visible) {
            Button(DuckCards.Words.replace, role: .destructive) { save(replacing: true) }
            Button(DuckCards.Words.keepIt, role: .cancel) {}
        } message: {
            if let replacing {
                Text(DuckCards.Words.replaceQuestion(replacing,
                                                     heldBy: store.classDeck?.heldBy(replacing.tag) ?? []))
            }
        }
    }

    /// A number in the picker, as the kit words it.
    private func choice(_ tag: Int) -> String {
        DuckCards.Words.number(tag, meaning: store.classDeck?.means(tag),
                               printed: store.classDeck?.isPrinted(tag) ?? false)
    }

    /// Save. The kit checks everything else first and says last when the number already means
    /// something; that one is asked about, and Replace it saves again with `replacing`.
    private func save(replacing confirmed: Bool) {
        guard let number, let deck = store.deck else { return }
        refusal = nil
        do {
            let row = try DuckCards.savedRow(reading, deck: deck, counts: counts)
            let card = try store.save(row: row, asCard: number, name: name, does: does, replacing: confirmed)
            said = DuckCards.Words.saved(card)
        } catch DuckCards.Refusal.wouldReplace(let held) {
            replacing = held
        } catch let refused as DuckCards.Refusal {
            refusal = refused.message
        } catch {
            refusal = error.localizedDescription
        }
    }
}

/// The class deck: every Your card that means something, a way to forget one, and the deck file to
/// share.
///
/// SHARING SENDS THE FILE, NOT A SUMMARY OF IT. What another phone opens, and what the duck reads
/// with `--deck`, is the deck file itself, byte for byte, written where the share sheet can reach
/// it as `class.duckcards`. A file someone shared comes back in through the app's one import door.
struct DuckCardsDeckView: View {
    @ObservedObject private var store = DuckCardsStore.shared
    @State private var outgoing: ExportedFile?
    @State private var said: String?
    /// The card a Forget is asking about.
    @State private var forgetting: DuckCards.Card?

    var body: some View {
        List {
            Section {
                if let classDeck = store.classDeck, !classDeck.saved.isEmpty {
                    ForEach(classDeck.saved, id: \.tag) { card in row(card, classDeck) }
                } else {
                    Text(DuckCards.Words.noYourCards)
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                SectionHeading(text: DuckCards.Words.yourCardsHeading)
            } footer: {
                Text(DuckCards.Words.deckFooter).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Button { share() } label: {
                    Label(DuckCards.Words.shareDeck, systemImage: "square.and.arrow.up")
                }
                .tint(Theme.actionSecondary)
                .frame(minHeight: DesignMetric.minimumTarget)
            } footer: {
                Text(DuckCards.Words.shareFooter).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            if let line = said ?? store.lastOpened {
                Section {
                    Text(line)
                        .font(.footnote).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
            if let problem = store.classDeck?.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(DuckCards.Words.deckTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $outgoing) { file in
            ShareSheet(items: [file.url]) { outgoing = nil }
        }
        .confirmationDialog(forgetting.map(DuckCards.Words.forgetTitle) ?? DuckCards.Words.forget,
                            isPresented: Binding(get: { forgetting != nil },
                                                 set: { if !$0 { forgetting = nil } }),
                            titleVisibility: .visible) {
            if let card = forgetting {
                Button(DuckCards.Words.forget, role: .destructive) { forget(card) }
            }
            Button(DuckCards.Words.keepIt, role: .cancel) {}
        } message: {
            if let card = forgetting {
                Text(DuckCards.Words.forgetQuestion(card, heldBy: store.classDeck?.heldBy(card.tag) ?? []))
            }
        }
    }

    /// One saved card: its number and name, what it runs in the reader's words, what the class
    /// wrote it does, and Forget.
    private func row(_ card: DuckCards.Card, _ classDeck: DuckCards.ClassDeck) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Text(DuckCards.Words.yourCard(card))
                .font(.body.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(DuckCards.Words.runs(classDeck.reads(card.tag)))
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let does = card.does {
                Text(does)
                    .font(.footnote.italic()).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(DuckCards.Words.forget, role: .destructive) { forgetting = card }
                .buttonStyle(.borderless)
                .font(.footnote)
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }

    private func share() {
        guard let classDeck = store.classDeck else { return }
        do {
            outgoing = ExportedFile(url: try ExportFile.write(classDeck.exported, named: DuckCards.ClassDeck.fileName))
        } catch let failure as ExportFile.Failure {
            said = failure.message
        } catch {
            said = error.localizedDescription
        }
    }

    private func forget(_ card: DuckCards.Card) {
        do {
            try store.forget(card.tag)
            said = DuckCards.Words.forgot(card.tag)
        } catch let refused as DuckCards.Refusal {
            said = refused.message
        } catch {
            said = error.localizedDescription
        }
    }
}
