import SwiftUI
import StudioKit

/// The class pack's settings: its name, how it is scored, and which printed cards are in play.
///
/// THE ID IS SHOWN, NEVER EDITED. It was minted once for this install so another phone keeps this
/// class's pack apart from another class's; changing it would make a shared copy a different pack.
///
/// NEW SETTINGS ARE HELD TO EVERY CHALLENGE FIRST. Saving goes through `DuckPacksStore.apply`, which
/// has the kit recheck each challenge (`ClassPack.rechecked`): par is worked out again for the new
/// score and cards, and a challenge that cannot be solved with the cards chosen refuses the change
/// in a sentence, with nothing changed.
struct DuckPackClassSettingsView: View {
    @ObservedObject private var store = DuckPacksStore.shared
    @State private var name = ""
    @State private var score = DuckPacks.Score.steps
    @State private var chosen: Set<String> = []
    @State private var loaded = false
    @State private var said: String?
    @State private var refusal: String?

    private var deck: DuckCards.Deck? { DuckCardsStore.shared.deck }

    var body: some View {
        List {
            Section {
                TextField(DuckPacks.Words.settingsNamePlaceholder, text: $name)
                    .frame(minHeight: DesignMetric.minimumTarget)
            } header: {
                SectionHeading(text: DuckPacks.Words.settingsNameHeading)
            } footer: {
                Text(DuckPacks.Words.settingsID(store.settings.id)).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Picker(DuckPacks.Words.settingsScoreHeading, selection: $score) {
                    ForEach(DuckPacks.Score.allCases, id: \.self) { s in
                        Text(DuckPacks.Words.scoreName(s)).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: DesignMetric.minimumTarget)
                Text(DuckPacks.Words.scoredBy(score))
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SectionHeading(text: DuckPacks.Words.settingsScoreHeading)
            }
            .listRowBackground(Theme.surfacePrimary)

            if let deck {
                Section {
                    ForEach(DuckPacks.ClassPack.cards(deck), id: \.self) { code in
                        let always = DuckPacks.ClassPack.always.contains(code)
                        Toggle(deck.card(code: code)?.name ?? code,
                               isOn: Binding(get: { always || chosen.contains(code) },
                                             set: { on in
                                                 if on { chosen.insert(code) } else { chosen.remove(code) }
                                             }))
                            .disabled(always)
                            .frame(minHeight: DesignMetric.minimumTarget)
                    }
                } header: {
                    SectionHeading(text: DuckPacks.Words.settingsCardsHeading)
                } footer: {
                    Text(DuckPacks.Words.settingsCardsFooter).foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            Section {
                Button(DuckPacks.Words.applySettings) { apply() }
                    .buttonStyle(.primaryAction)
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
        .navigationTitle(DuckPacks.Words.settings)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: name) { _, _ in said = nil; refusal = nil }
        .onChange(of: score) { _, _ in said = nil; refusal = nil }
        .onChange(of: chosen) { _, _ in said = nil; refusal = nil }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let s = store.settings
        name = s.name == DuckPacks.ClassPack.name ? "" : s.name
        score = s.score
        chosen = Set(deck.map(s.inPlay) ?? [])
    }

    private func apply() {
        refusal = nil
        let printed = deck.map(DuckPacks.ClassPack.cards) ?? []
        let cards = printed.filter { DuckPacks.ClassPack.always.contains($0) || chosen.contains($0) }
        var next = store.settings
        next.name = name
        next.score = score
        next.cards = cards == printed ? nil : cards
        do {
            try store.apply(next)
            said = DuckPacks.Words.settingsSaved(store.settings.shownName)
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
