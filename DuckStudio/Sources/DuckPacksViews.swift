import SwiftUI
import StudioKit

/// The Duck Card packs: the starter packs by grade band, youngest first, any `.duckpack` opened,
/// and the class's own pack.
///
/// REACHED FROM THE CAMERA CARD, WHERE DUCK CARDS LIVE. The camera card on the Play tab and the
/// one on My Microduck open this beside the class deck, and hand it their feed, so a challenge can
/// take the row the camera reads.
///
/// A PACK'S YOUR CARDS ARE ASKED ABOUT HERE. A pack opened through the import door lends its Your
/// cards to the class deck and keeps the class's own where they clash; the question waits in
/// `DuckPacksStore.asking` and is asked when this screen is in front.
///
/// SO IS A PACK WITH AN ID ALREADY OPEN. Two classes' packs have two ids and sit side by side; one
/// whose id matches a pack already here replaces it only after the person picks, with both named
/// (`DuckPacksStore.replacing`).
struct DuckPacksView: View {
    var camera: DuckCameraFeed? = nil
    var robot: BridgeLink? = nil
    var models: EndpointStore? = nil
    var stopDriving: (() async -> Void)? = nil

    @ObservedObject private var store = DuckPacksStore.shared
    /// In front, so the import door's question is asked here and not under a pushed screen.
    @State private var inFront = false

    /// The starter packs, grouped by grade band in the order `DuckPacks.bundled` gives, youngest first.
    private var bands: [[DuckPacks.Pack]] {
        var out: [[DuckPacks.Pack]] = []
        for pack in DuckPacks.bundled {
            if let last = out.last?.first, last.gradeFrom == pack.gradeFrom, last.gradeTo == pack.gradeTo {
                out[out.count - 1].append(pack)
            } else {
                out.append([pack])
            }
        }
        return out
    }

    var body: some View {
        List {
            if let line = store.lastOpened {
                Section {
                    Text(line)
                        .font(.footnote).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            ForEach(bands, id: \.first!.id) { band in
                Section {
                    ForEach(band, id: \.id) { pack in link(pack, isClass: false) }
                } header: {
                    SectionHeading(text: DuckPacks.Words.band(band[0]))
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            if !store.opened.isEmpty {
                Section {
                    ForEach(store.opened, id: \.id) { pack in link(pack, isClass: false) }
                } header: {
                    SectionHeading(text: DuckPacks.Words.openedHeading)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            Section {
                if let mine = store.classPack {
                    link(mine, isClass: true)
                } else {
                    Text(DuckPacks.Words.noClassPack)
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                NavigationLink {
                    DuckPackEditorView(draft: DuckPacks.Draft(columns: DuckPacks.ClassPack.columns,
                                                              rows: DuckPacks.ClassPack.rows))
                } label: {
                    Label(DuckPacks.Words.design, systemImage: "square.grid.3x3.square")
                }
                .frame(minHeight: DesignMetric.minimumTarget)
                NavigationLink {
                    DuckPackClassSettingsView()
                } label: {
                    Label(DuckPacks.Words.settings, systemImage: "slider.horizontal.3")
                }
                .frame(minHeight: DesignMetric.minimumTarget)
            } header: {
                SectionHeading(text: DuckPacks.Words.classHeading)
            } footer: {
                Text(DuckPacks.Words.packsFooter).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(DuckPacks.Words.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { inFront = true }
        .onDisappear { inFront = false }
        .modifier(DuckPacksAsking(when: { _ in inFront }))
        .confirmationDialog(DuckPacks.Words.sameIDTitle,
                            isPresented: Binding(get: { inFront && store.replacing != nil },
                                                 set: { if !$0, let q = store.replacing { store.answer(q, replace: false) } }),
                            titleVisibility: .visible,
                            presenting: store.replacing) { question in
            Button(DuckPacks.Words.replaceOpened, role: .destructive) { store.answer(question, replace: true) }
            Button(DuckPacks.Words.keepOpened, role: .cancel) { store.answer(question, replace: false) }
        } message: { question in
            Text(DuckPacks.Words.sameIDQuestion(question.incoming, question.existing))
        }
    }

    private func link(_ pack: DuckPacks.Pack, isClass: Bool) -> some View {
        NavigationLink {
            DuckPackView(pack: pack, isClass: isClass, camera: camera, robot: robot, models: models,
                         stopDriving: stopDriving)
        } label: {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(pack.name)
                    .font(.body).foregroundStyle(Theme.textPrimary)
                Text(DuckPacks.Words.packLine(pack))
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, Theme.spacing(.hairline))
        }
    }
}

/// One pack: what it is, the cards in play, its challenges in order, its lessons, the Your cards it
/// lends, a challenge of your own, and the pack file to share.
///
/// SHARING SENDS THE FILE, NOT A SUMMARY OF IT. What another phone opens, and what the duck reads
/// with `--pack`, is `Pack.source`, the bytes the pack was read from, written where the share sheet
/// can reach it as `<id>.duckpack`.
struct DuckPackView: View {
    let pack: DuckPacks.Pack
    /// The class's own pack, whose challenges can be taken out.
    var isClass = false
    var camera: DuckCameraFeed? = nil
    var robot: BridgeLink? = nil
    var models: EndpointStore? = nil
    var stopDriving: (() async -> Void)? = nil

    @ObservedObject private var store = DuckPacksStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var outgoing: URL?
    @State private var said: String?
    @State private var removing = false

    /// The class pack as it is now, so a challenge taken out leaves the list at once.
    private var shown: DuckPacks.Pack { isClass ? (store.classPack ?? pack) : pack }

    var body: some View {
        List {
            aboutSection
            challengesSection
            if !shown.lessons.isEmpty { lessonsSection }
            if !shown.yours.isEmpty { yoursSection }
            designSection
            shareSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(shown.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: shown.source) { writeShared() }
        .modifier(DuckPacksAsking(when: { $0.pack.id == pack.id }))
        .confirmationDialog(DuckPacks.Words.remove, isPresented: $removing, titleVisibility: .visible) {
            Button(DuckPacks.Words.remove, role: .destructive) {
                store.remove(pack)
                dismiss()
            }
            Button(DuckCards.Words.keepIt, role: .cancel) {}
        } message: {
            Text(DuckPacks.Words.removeQuestion(pack))
        }
    }

    private var deck: DuckCards.Deck? { store.playDeck(shown) }

    private var aboutSection: some View {
        Section {
            Text(shown.about)
                .font(.callout).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(DuckPacks.Words.scoredBy(shown.score))
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let deck {
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    Text(DuckPacks.Words.cardsHeading)
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(DuckPacks.Words.cardsInPlay(shown, deck: deck))
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Text(shown.credit)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: DuckPacks.Words.aboutHeading)
        } footer: {
            Text(DuckPacks.Words.boardRule).foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var challengesSection: some View {
        Section {
            ForEach(Array(shown.challenges.enumerated()), id: \.element.id) { index, ch in
                NavigationLink {
                    DuckPackChallengeView(pack: shown, challenge: ch, camera: camera, robot: robot, models: models,
                                          stopDriving: stopDriving)
                } label: {
                    VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                        Text(DuckPacks.Words.challengeLine(index, ch))
                            .font(.body).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Theme.spacing(.tight)) {
                            Text(DuckPacks.Words.par(DuckPacks.par(ch, in: shown) ?? ch.par, shown.score))
                                .font(.footnote.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                            if ch.buggy != nil {
                                Label(DuckPacks.Words.findTheBug, systemImage: "ladybug")
                                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if let note = ch.note {
                            Text(DuckPacks.Words.note(note))
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, Theme.spacing(.hairline))
                }
            }
            .onDelete(perform: isClass ? { (offsets: IndexSet) in remove(offsets) } : nil)
            if let said {
                Text(said)
                    .font(.footnote).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: DuckPacks.Words.challengesHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var lessonsSection: some View {
        Section {
            ForEach(Array(shown.lessons.enumerated()), id: \.offset) { _, lesson in
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    Text(lesson.title)
                        .font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(DuckPacks.Words.skill(lesson))
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                    Text(lesson.body)
                        .font(.callout).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(DuckPacks.Words.ask(lesson))
                        .font(.callout.italic()).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.spacing(.hairline))
            }
        } header: {
            SectionHeading(text: DuckPacks.Words.lessonsHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var yoursSection: some View {
        Section {
            ForEach(shown.yours, id: \.tag) { card in
                Text(DuckPacks.Words.lends(card))
                    .font(.footnote).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let clashes = store.clashes(shown)
            if !clashes.isEmpty {
                Label(DuckPacks.Words.classMeaningWins(shown, clashes), systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                store.lend(shown, replacing: false)
            } label: {
                Label(DuckPacks.Words.lend, systemImage: "rectangle.stack.badge.plus")
            }
            .tint(Theme.actionSecondary)
            .frame(minHeight: DesignMetric.minimumTarget)
            if let line = store.lastOpened {
                Text(line)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: DuckPacks.Words.yoursHeading)
        } footer: {
            Text(DuckPacks.Words.lendFooter).foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var designSection: some View {
        Section {
            NavigationLink {
                DuckPackEditorView(draft: DuckPacks.Draft(columns: shown.board.columns, rows: shown.board.rows))
            } label: {
                Label(DuckPacks.Words.design, systemImage: "square.grid.3x3.square")
            }
            .frame(minHeight: DesignMetric.minimumTarget)
        } footer: {
            Text(DuckPacks.Words.designFooter(store.settings.shownName)).foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var shareSection: some View {
        Section {
            if let outgoing {
                ShareLink(item: outgoing) {
                    Label(DuckPacks.Words.share, systemImage: "square.and.arrow.up")
                }
                .tint(Theme.actionSecondary)
                .frame(minHeight: DesignMetric.minimumTarget)
            }
            if store.isOpened(pack) && !isClass {
                Button(DuckPacks.Words.remove, role: .destructive) { removing = true }
                    .buttonStyle(.borderless)
                    .frame(minHeight: DesignMetric.minimumTarget)
            }
        } header: {
            SectionHeading(text: DuckPacks.Words.shareHeading)
        } footer: {
            Text(DuckPacks.Words.shareFooter(shown)).foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// The pack file, written where the share sheet can reach it, before Share is offered.
    private func writeShared() {
        do {
            outgoing = try ExportFile.write(shown.source, named: "\(shown.id).\(DuckPacks.fileExtension)")
        } catch let failure as ExportFile.Failure {
            outgoing = nil
            said = failure.message
        } catch {
            outgoing = nil
            said = error.localizedDescription
        }
    }

    private func remove(_ offsets: IndexSet) {
        for index in offsets where shown.challenges.indices.contains(index) {
            do {
                try store.remove(shown.challenges[index])
            } catch let refusal as DuckPacks.Refusal {
                said = refusal.message
            } catch {
                said = error.localizedDescription
            }
        }
    }
}

/// The question a pack's Your cards raise when they clash with the class deck: replace the class's
/// own with the pack's, or keep them. Asked by whichever screen `when` says is the one to ask.
private struct DuckPacksAsking: ViewModifier {
    let when: (DuckPacksStore.Asking) -> Bool
    @ObservedObject private var store = DuckPacksStore.shared

    @ViewBuilder func body(content: Content) -> some View {
        let asking = store.asking.flatMap { when($0) ? $0 : nil }
        content.confirmationDialog(asking.map { DuckPacks.Words.clashTitle($0.clashes) } ?? DuckPacks.Words.lend,
                                   isPresented: Binding(get: { asking != nil },
                                                        set: { if !$0 { store.asking = nil } }),
                                   titleVisibility: .visible) {
            if let asking {
                Button(DuckPacks.Words.replaceThem, role: .destructive) { store.lend(asking.pack, replacing: true) }
            }
            Button(DuckPacks.Words.keepOurs, role: .cancel) { store.asking = nil }
        } message: {
            if let asking { Text(DuckPacks.Words.clashQuestion(asking.pack, asking.clashes)) }
        }
    }
}
