import SwiftUI
import Foundation
import DuckKit
import DuckEvidence
import StudioKit

/// One point — the thinnest rule iOS draws crisply.
///
/// `DesignComponents` keeps the app's other hairline in a private `Metric`, so
/// this restates the width rather than sharing it. Two files knowing that a
/// hairline is one point is tolerable; a third would mean the number belongs in
/// `Palette` beside the radii, next to the focus ring's geometry, which is the
/// other layout constant the design system already carries.
private let hairlineStroke = DesignMetric.hairlineStroke


/// The explanatory line under a section.
///
/// SET IN `textSecondary`, WHICH IS A CONTRAST DECISION AND NOT A TASTE ONE.
/// Footers sit on the list's recessed ground, and `Palette` is explicit that
/// `backgroundSecondary` is a ground for surfaces rather than for words: the
/// four ink variants land between 4.17:1 and 4.27:1 on it, short of the 4.5:1
/// body text owes. The two greys clear it — secondary 6.24:1, tertiary 4.59:1
/// in light — so the only text allowed outside a card on this screen is grey
/// text, and every coloured word in the design lives on a card.
private func sectionFootnote(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
}

/// One row's share of its section's card.
///
/// A CARD DRAWN AS SEGMENTS, BECAUSE A `Section` HAS NO BACKGROUND OF ITS OWN.
/// The design system asks for a `surfacePrimary` card at the card radius with
/// rows inside it; a SwiftUI list gives you rows and a group shape it draws
/// itself, at the platform's radius. Painting the first and last rows with
/// their outer corners rounded and the rest square produces the card the brief
/// asks for, at the radius the brief asks for, without hand-rolling a list —
/// and the corners are the ones we set, because a 14pt corner is strictly
/// inside the 10pt one the platform would clip to.
private func cardSegment(first: Bool, last: Bool) -> some View {
    UnevenRoundedRectangle(
        topLeadingRadius: first ? Theme.radius(.card) : 0,
        bottomLeadingRadius: last ? Theme.radius(.card) : 0,
        bottomTrailingRadius: last ? Theme.radius(.card) : 0,
        topTrailingRadius: first ? Theme.radius(.card) : 0,
        style: .continuous)
        .fill(Theme.surfacePrimary)
}

/// Behaviours: what this robot knows how to do, where more of it comes from,
/// and how a new one would be asked for.
///
/// IT IS A TAB ROOT NOW, AND A TAB ROOT MAY NOT KEEP ITS DOORS IN A MENU. This
/// screen used to be "Policies" with an ellipsis carrying five destinations,
/// three of which — driving, finding a real duck, running on a bench — are not
/// about the policy library at all. Each of those three now has a tab or a home
/// of its own (Control, My Microduck → Connection, Studio → Measure on a
/// bench), so they are gone from here rather than duplicated: two doors to one
/// room is how an app teaches somebody that neither of them is the way.
///
/// THE ORDER IS THE QUESTION ORDER. What is installed, how a new one is asked
/// for, and where other people's are — in that order, because the person who
/// opens this tab already has policies far more often than not, and a discovery
/// shelf above the shelf you own is a shop pretending to be a library.
///
/// ORGANISED BY PROVENANCE, NOT BY FOLDER. The sections are "Released by Pollen
/// Robotics" and "From elsewhere", and which section a policy lands in is
/// decided by its parameter fingerprint — not by whether it shipped in the
/// bundle. Those two answers diverge the moment anyone downloads a policy from
/// Pollen's own repository, and a heading that said "Bundled" would be telling
/// the reader where a file came from while looking like it was telling them
/// what it is.
///
/// AND THE COLOUR SAYS THE SAME THING THE HEADING DOES. This app is strict
/// about provenance, so the palette is used as a claim about it and nothing
/// else: the teal seal is what this app MEASURED when it read the file, the
/// critical mark is a REFUSAL, and the yellow is what somebody WROTE DOWN — the
/// author's own caveats out of the manifest, in the colour reserved for things
/// that were asked for rather than observed. Nothing on this screen is
/// distinguished by colour alone: every seal carries the report's own headline
/// as its label, every caveat carries the warning glyph, and the provenance
/// pill says its word as well as wearing its colour.
struct PolicyListView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var scenes: SceneStore
    @ObservedObject var drafts: DraftStore
    /// Not used on this screen — carried through to the clip player and the
    /// bench, because a motion remixed from a policy's own recordings opens the
    /// same editor as one remixed from Studio → Motions, and the Ask panel there
    /// was dead for want of this one argument. No screen in this app puts a
    /// store in the environment; every one is passed by hand, so a feature that
    /// needs one three screens down has to be threaded through the two between.
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore

    /// Which tab is in front.
    ///
    /// THE ONE SANCTIONED WAY OUT OF THIS TAB. Two rows on this screen and its
    /// detail screen end somewhere that is not a policy — driving is Control,
    /// writing a training request is Studio — and before `AppRouter` existed the
    /// honest options were a duplicate copy of another tab's screen pushed onto
    /// this stack, or a sentence telling somebody to go and tap a tab. Both are
    /// the app declining to do a thing it can obviously do.
    @EnvironmentObject private var router: AppRouter

    private var released: [PolicyLibrary.Entry] {
        model.library.entries.filter { isReleased(model.standing(for: $0)) }
    }
    private var elsewhere: [PolicyLibrary.Entry] {
        model.library.entries.filter { !isReleased(model.standing(for: $0)) }
    }

    var body: some View {
        List {
            if let message = model.lastImport {
                Section {
                    sectionFootnote(message)
                        .listRowBackground(cardSegment(first: true, last: true))
                }
            }
            installed
            if model.library.entries.isEmpty {
                Section { emptyLibrary }
            }
            retrain
            discover
            independence
        }
        .scrollContentBackground(.hidden)
        // THE RECESSED GROUND, WHICH IS WHAT THIS TOKEN IS FOR. Grouped
        // content sits on it and the words sit on the cards, the way
        // `systemGroupedBackground` works on iOS — see `sectionFootnote` for
        // the numbers that make that a rule rather than a preference.
        .background(Theme.backgroundSecondary)
        // THE TAB'S OWN WORD, NOT THE FILE FORMAT'S. "Policies" is what is on
        // disk; "Behaviours" is what somebody came to look at, and it is the
        // word the tab bar says two points below the title. A root whose title
        // disagrees with its tab is a root somebody has to read twice.
        .navigationTitle("Behaviours")
        .confirmationDialog("Remove this policy?",
                            isPresented: Binding(get: { removing != nil },
                                                 set: { if !$0 { removing = nil } }),
                            presenting: removing) { entry in
            Button("Remove \(entry.title)", role: .destructive) {
                model.removePolicy(entry)
                removing = nil
            }
            Button("Keep it", role: .cancel) { removing = nil }
        } message: { entry in
            Text(entry.removalWarning)
        }
        .toolbar {
            // WHAT IS LEFT OF THE MENU IS THE ONE THING THAT IS ABOUT THIS
            // LIBRARY AND BELONGS TO NO SINGLE POLICY IN IT.
            //
            // Drive, "find a real duck" and "run on your network" are gone,
            // and not to another menu: driving is the Control tab, finding a
            // duck is My Microduck → Connection, and a bench run is Studio →
            // Measure on a bench. Pollen's catalogue is gone too — it is a row
            // in Discover at the foot of this screen, where the community one
            // sits beside it and the two can be read as the pair they are.
            //
            // AND THE BUTTON ITSELF IS CONDITIONAL, NOT ITS CONTENTS. A blend
            // of one policy is that policy, which `PolicyBlend` refuses anyway;
            // with the other four doors gone, a library holding fewer than two
            // runnable policies would leave an ellipsis that opens an empty
            // menu, which is worse than no ellipsis. So the glyph appears with
            // the second runnable policy and takes its one door with it.
            ToolbarItem(placement: .topBarTrailing) {
                if model.library.runnableCount >= 2 {
                    Menu {
                        NavigationLink { PolicyBlendView(library: model.library,
                                                         benches: benches) } label: {
                            Label("Blend two policies", systemImage: "arrow.triangle.merge")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel(Text("More"))
                    }
                }
            }
            // ONE GEAR, ONCE, ON THE TAB ROOT. The Benches link is gone from
            // here: it is Settings → Benches now, and still two taps from the
            // screens that actually run things.
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView(models: models, benches: benches) } label: {
                    Image(systemName: "gear").accessibilityLabel(Text("Settings"))
                }
            }
        }
        .onAppear { readManifests() }
        .onChange(of: model.library.entries) { _, _ in readManifests() }
    }

    /// The policy a removal is being confirmed for.
    ///
    /// CONFIRMED RATHER THAN SWIPED AWAY, because for an imported policy this
    /// is not recoverable: the weights may exist nowhere else, and this app is
    /// not a backup. `Entry.removalWarning` says which of the two cases it is —
    /// a download that can be fetched again, or a file that cannot.
    @State private var removing: PolicyLibrary.Entry?

    /// The manifest each policy came with, keyed by identity.
    ///
    /// READ ONCE PER APPEARANCE, NOT ONCE PER ROW PER FRAME. A manifest lives
    /// beside the weights on disk, so asking for one inside a row's body is a
    /// file read every time SwiftUI rebuilds that row — which, in a list, is
    /// every scroll. Reading them all when the screen appears and again when
    /// the library changes costs one pass over a directory of small JSON files
    /// and makes the rows pure.
    @State private var manifests: [String: PolicyManifest] = [:]

    /// The action scale each policy DECLARED, keyed the same way.
    ///
    /// KEPT SEPARATELY FROM THE MANIFEST ON PURPOSE. `LibraryModel` exposes it
    /// as a named accessor precisely so a view never reaches into the manifest
    /// for the number itself — it is a fact about how far the robot moves, and
    /// a view holding it is a view one edit away from doing arithmetic with it.
    /// Carrying the value in its own dictionary keeps that boundary where the
    /// kit put it.
    @State private var declaredScales: [String: Double] = [:]

    private func readManifests() {
        var found: [String: PolicyManifest] = [:]
        var scales: [String: Double] = [:]
        for entry in model.library.entries {
            if let manifest = model.manifest(for: entry) { found[entry.id] = manifest }
            if let scale = model.declaredScale(for: entry) { scales[entry.id] = scale }
        }
        manifests = found
        declaredScales = scales
    }

    private func isReleased(_ standing: DuckOfficialPolicies.Standing) -> Bool {
        if case .released = standing { return true }
        return false
    }

    // MARK: - what is installed

    /// One provenance group, with the sentence that explains what landing in it
    /// means.
    ///
    /// NOT NAMED `Group`, WHICH IS THE OBVIOUS NAME AND A TRAP. A nested type
    /// called `Group` shadows SwiftUI's inside every `body` in this file, so the
    /// day somebody wraps two rows in a `Group` they get this struct and an
    /// error that says nothing about why.
    private struct Shelf: Identifiable {
        let id: String
        let title: String
        let entries: [PolicyLibrary.Entry]
        let footnote: String
    }

    /// The groups that have anything in them, in the order they are read.
    ///
    /// EMPTY GROUPS ARE ABSENT RATHER THAN EMPTY, which is what makes the
    /// "Installed" heading attachable at all: it goes on the first group that
    /// exists, so a library of nothing but imported files still gets counted
    /// under one heading instead of the count vanishing with the section that
    /// happened to be listed first.
    private var shelves: [Shelf] {
        var found: [Shelf] = []
        if !released.isEmpty {
            found.append(Shelf(
                id: "released", title: "Released by Pollen Robotics", entries: released,
                footnote: "Matched by fingerprint — a digest of the trained weights, not of the file. A re-export under a newer opset still matches; one changed weight does not."))
        }
        if !elsewhere.isEmpty {
            found.append(Shelf(
                id: "elsewhere", title: "From elsewhere", entries: elsewhere,
                footnote: "Trained by someone else, or newer than this app knows about. This only says the weights are unfamiliar — not that they are bad."))
        }
        return found
    }

    /// Everything this phone holds, under one heading that counts it.
    ///
    /// TWO HEADINGS STACKED ON THE FIRST SECTION, WHICH IS THE HONEST SHAPE OF
    /// WHAT IS BEING SAID. "Installed · 7" is a fact about the library; "Released
    /// by Pollen Robotics" is a fact about the seven rows under it. A list has
    /// no nested sections, so the outer claim is drawn once, above the first
    /// group, in the same `SectionHeading` the inner one uses — the alternative
    /// was inventing a second heading style for a distinction that does not need
    /// one, or repeating the count on both groups, where it would be wrong on
    /// both.
    @ViewBuilder
    private var installed: some View {
        ForEach(Array(shelves.enumerated()), id: \.element.id) { index, shelf in
            Section {
                rows(shelf.entries)
            } header: {
                if index == 0 {
                    VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                        SectionHeading(text: "Installed · \(model.library.entries.count)")
                        SectionHeading(text: shelf.title)
                    }
                } else {
                    SectionHeading(text: shelf.title)
                }
            } footer: {
                if index == 0 {
                    VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                        runnableFraction
                        sectionFootnote(shelf.footnote)
                    }
                } else {
                    sectionFootnote(shelf.footnote)
                }
            }
        }
    }

    /// How many of them this app will actually load.
    ///
    /// A COUNT THAT CHANGES, SO IT IS SET IN FIGURES THAT DO NOT MOVE. Tabular
    /// digits are the design system's claim that a number is live; this one goes
    /// up and down as policies are added and removed, which is exactly what
    /// earns them.
    ///
    /// AND IT IS A FOOTER NOW RATHER THAN A TOOLBAR ITEM. It spent its life at
    /// `.topBarLeading`, where a large-title root shows it beside nothing and a
    /// person reads it before they have been told what is being counted. Under
    /// the "Installed" heading it is the sentence that heading owes: seven
    /// installed, six of which run. It counts the WHOLE library rather than the
    /// group it sits under, which is why it is set apart from that group's own
    /// footnote instead of running into it.
    private var runnableFraction: some View {
        Text("\(model.library.runnableCount) of \(model.library.entries.count) run")
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
    }

    // MARK: - asking for a new one

    /// Where a request to train something new is written.
    ///
    /// NOTHING ON THIS PHONE KEEPS A TRAINING REQUEST, AND THIS ROW IS WHAT
    /// THAT LOOKS LIKE HONESTLY. The stores were read before this section was
    /// drawn: `DraftStore` holds `IntentDraft`s, `PlanStore` holds
    /// `DuckPlanFile`s, and the only `TrainingRequest` values that exist
    /// anywhere in the app are the ones hanging off a chat card in
    /// `AutomationChatView`, whose transcript is `@State` — it dies with the
    /// screen. So there is no list of saved requests to draw, and drawing an
    /// empty one would be this screen implying a store it does not have.
    ///
    /// IT GOES SOMEWHERE, WHICH IS WHY IT IS NOT A "NOT YET". The house rule is
    /// that a blocked surface says so in a tested kit sentence and never ships
    /// as an inert control — and the counterpart of that rule is that a surface
    /// which is not blocked must not be dressed as one. Retraining is not
    /// blocked: it is written in Studio → Draft, one tap from here now that
    /// `AppRouter` exists. A row that named that screen and opened nothing
    /// would be the inert control the rule forbids, wearing an apology it has
    /// not earned.
    ///
    /// THE ROW LANDS ON DRAFT, NOT ON THE STUDIO ROOT. It used to make only the
    /// first of the two hops — `AppRouter` selected a tab and could not push a
    /// screen inside one — so the label named both halves and left the second to
    /// the person, who arrived at a list of four rows with nothing marking the
    /// one they had just asked for. `go(to:then:)` carries the second hop; the
    /// label still names the route because a person who lands two screens deep
    /// should be able to see how they got there.
    private var retrain: some View {
        Section {
            Button {
                router.go(to: .studio, then: .draft)
            } label: {
                Label {
                    Text("Write one in Studio → Draft")
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "text.bubble").foregroundStyle(Theme.actionSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens Draft, in the Studio tab, where a sentence becomes a checked training request."))
            .listRowBackground(cardSegment(first: true, last: true))
        } header: {
            SectionHeading(text: "Retrain")
        } footer: {
            sectionFootnote("Describe what you want the duck to learn and Draft turns it into a fork of a training config, a set of reward functions that exist, and an episode — then refuses the ones the robot's own physics rule out, in a second rather than after a day of training. Nothing here keeps a request: it lives on the card that wrote it, and travels as a file you send to a machine that has Python, mjlab and a GPU.")
        }
    }

    // MARK: - where more of them come from

    /// The two catalogues, as rows rather than as menu items.
    ///
    /// LAST, AND INLINE. These were two entries in an ellipsis menu — one of
    /// them nested inside the other's screen — which is the arrangement that
    /// makes a person believe an app has nothing to offer them. They are the
    /// end of the list because owning something comes before shopping for more
    /// of it, and they are rows because a door drawn as a row is a door.
    ///
    /// TWO SIBLINGS, NOT A PARENT AND A CHILD. Pollen's releases and the
    /// community's are different claims about provenance and neither contains
    /// the other, which is the whole posture of this app's palette. Reaching the
    /// community through Pollen's screen said the opposite.
    ///
    /// AND A THIRD ROW THAT IS NOT A CATALOGUE OF NETWORKS. The challenges are
    /// published corpora with an audit behind them — the stairs a corpus of
    /// authored MOVES, the ball a corpus that also holds trained policies under
    /// a command schedule — which is a different kind of thing from a shelf of
    /// networks. But it is the same question a person asks here, "what have
    /// other people published", and burying the only published things in this
    /// app that can be scored against their own leaderboards inside another tab
    /// is how a shelf goes unread. It is the one row in this section that
    /// leaves the tab, so it is a `Button` on the router rather than a
    /// `NavigationLink`: pushing Studio's screen onto the Behaviours stack
    /// would be a second copy of it, on a stack where its own Back button lies
    /// about where you came from.
    ///
    /// ITS TWO LINES ARE THE KIT'S, ONE PER CHALLENGE. `Challenge.oneSentence`
    /// is the same sentence the list screen draws, so this door cannot describe
    /// a challenge differently from the screen it opens.
    private var discover: some View {
        Section {
            NavigationLink { CatalogueView(model: model) } label: {
                door("Pollen Robotics",
                     detail: "The releases that ship with the robot — and anything they have published since this app was built.",
                     symbol: "antenna.radiowaves.left.and.right")
            }
            .listRowBackground(cardSegment(first: true, last: false))
            NavigationLink { CommunityPoliciesView(model: model) } label: {
                door("Community",
                     detail: "Networks other people trained and published on Hugging Face, each with the manifest that says what its command block means.",
                     symbol: "person.2")
            }
            .listRowBackground(cardSegment(first: false, last: false))
            Button {
                router.go(to: .studio, then: .challenges)
            } label: {
                // A BUTTON IN A LIST DRAWS NO CHEVRON, so it is put back by
                // hand. The row leads out of this tab entirely, which is more
                // of a journey than the two above it and not less — and a row
                // that looks inert beside two that look tappable reads as a
                // heading rather than as a door.
                HStack(alignment: .center, spacing: Theme.spacing(.tight)) {
                    VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                        Label {
                            Text(Challenge.listTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                        } icon: {
                            Image(systemName: "trophy")
                                .foregroundStyle(Theme.actionSecondary)
                        }
                        ForEach(Challenge.allCases) { challenge in
                            Text("\(challenge.name) — \(challenge.oneSentence)")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, Theme.spacing(.hairline))
                    Spacer(minLength: Theme.spacing(.tight))
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        // The row already says where it goes; a screen reader
                        // announcing "chevron" adds nothing.
                        .accessibilityHidden(true)
                }
            }
            .listRowBackground(cardSegment(first: false, last: true))
        } header: {
            SectionHeading(text: "Discover behaviours people have published")
        } footer: {
            sectionFootnote("Neither catalogue fetches anything until you ask: the address is printed first and the scan is a button. What decides whether a downloaded network can be driven here is its manifest, not whose repository it sat in. The challenges are in Studio, and nothing in them has been run on hardware.")
        }
        .listRowSeparatorTint(Theme.separator)
    }

    /// Whose robot this is, and whose app this is not.
    ///
    /// IT GOES UNDER BEHAVIOURS BECAUSE THIS IS THE SCREEN THAT NAMES POLLEN.
    /// Discover's first row is "Pollen Robotics" and the one under it is the
    /// community's; a person reading a list of releases that ship with the
    /// robot, on a screen inside an app about that robot, is a person who could
    /// reasonably conclude they are in Pollen's app. That conclusion is the one
    /// this sentence exists to prevent, and it belongs where it can be drawn
    /// rather than in a store listing nobody reads twice.
    ///
    /// THE SENTENCE IS THE KIT'S. `Provenance.independenceShort` is asserted by
    /// `swift test`, which is the house rule for every user-visible sentence and
    /// matters most for this one: a disclaimer edited into a hedge — "not
    /// officially affiliated" — is worse than none, and a literal here is a
    /// literal nothing can stop somebody softening.
    ///
    /// A ROW STYLED AS A FOOTER, NOT A `footer:` SLOT, and the reason is that
    /// the slot is on a section with nothing in it. A `Section { } footer: { … }`
    /// holding no rows is not reliably drawn by a `List`, and there is no
    /// Simulator on the machine this was written on to settle it — see the
    /// repo's own note about that. A claim about provenance that renders on some
    /// builds and not others is the worst of the three outcomes, so this is a
    /// row, which always draws, wearing the footnote type and a clear ground so
    /// it reads as the foot of the screen rather than as a card.
    private var independence: some View {
        Section {
            // `StudioKit.` SPELLED OUT: this file has a private `Provenance` of its
            // own, and the bare name resolves to it — Theme.swift said so in advance.
            sectionFootnote(StudioKit.Provenance.independence)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// One row that opens a catalogue: what it is, and one line on what is
    /// behind it.
    ///
    /// THE GLYPH CARRIES THE ACTION COLOUR AND THE WORD DOES NOT — the same
    /// arrangement `PolicyDetailView` makes for the doors that are not the
    /// primary one, so that a screen with several of them still reads as a
    /// screen rather than as a row of buttons.
    private func door(_ title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Label {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
            } icon: {
                Image(systemName: symbol).foregroundStyle(Theme.actionSecondary)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }

    // MARK: - the rows

    /// Every row in one section, each knowing whether it is an end of the card.
    private func rows(_ entries: [PolicyLibrary.Entry]) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            row(entry, first: index == 0, last: index == entries.count - 1)
        }
    }

    private func row(_ entry: PolicyLibrary.Entry, first: Bool, last: Bool) -> some View {
        NavigationLink {
            PolicyDetailView(entry: entry, model: model,
                             library: model.library, benches: benches,
                             standing: model.standing(for: entry),
                             scenes: scenes, drafts: drafts, models: models)
        } label: {
            rowContent(entry)
        }
        .listRowBackground(cardSegment(first: first, last: last))
        // The rule between two rows of the same card, in the palette's own
        // separator rather than the system's grey. It is 1.42:1 on the surface
        // and that is deliberate: `Palette` calls a separator decoration in SC
        // 1.4.11's sense, because the rows are already separated by space and
        // by type, and a rule dark enough to clear 3:1 on cream would read as a
        // table border.
        .listRowSeparatorTint(Theme.separator)
        // ONLY WHERE IT CAN WORK. The nine that ship inside the app bundle
        // cannot be deleted from a read-only bundle, so they get no swipe
        // at all rather than one that appears and does nothing.
        .swipeActions(edge: .trailing) {
            if entry.isRemovable {
                Button(role: .destructive) { removing = entry } label: {
                    Label("Remove", systemImage: "trash")
                }
                // THE DESTRUCTIVE ROLE, IN THIS APP'S RED. The role is what
                // makes it destructive — the confirmation, the ordering, and
                // what VoiceOver says all come from it — and the tint is what
                // makes it look like the rest of the app rather than like the
                // system's default red. `critical` is 6.64:1 on cream and
                // 6.70:1 on the dark ground, so the white "Remove" on it is
                // legible in both.
                .tint(Theme.critical)
            }
        }
    }

    /// The row itself: what this file is, where it came from, what it declares,
    /// and what its author admits to.
    private func rowContent(_ entry: PolicyLibrary.Entry) -> some View {
        let manifest = manifests[entry.id]
        return VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.snug)) {
                // WHETHER THIS FILE RUNS IS THE ONE THING THE ROW SAYS IN
                // A SEAL AND A COLOUR AND NOWHERE ELSE. The verdict is
                // StudioKit's sentence, written for exactly this — "One
                // short line, suitable for a row in a list" — so the icon
                // reads it out rather than this view inventing a second
                // wording of the same judgement.
                //
                // A SEAL AND ITS OPPOSITE, RATHER THAN A SEAL AND A TRIANGLE.
                // The two glyphs are now a pair, which leaves the triangle free
                // to mean one thing on this screen: the author's caveat. A row
                // can carry both — a policy whose manifest fits this robot and
                // whose weights this app will not read — and two triangles in
                // two colours would be the app saying "careful" twice about
                // different things.
                Image(systemName: entry.isRunnable ? "checkmark.seal" : "xmark.seal")
                    .foregroundStyle(entry.isRunnable ? Theme.measured : Theme.refused)
                    // THE POLICY, NOT THE FILE. `report.headline` names the
                    // FILE, and for every digest-named entry in the list that
                    // sentence is "This file is a Microduck policy" — an
                    // accessibility label that identifies nothing, on the one
                    // control whose job is to say which row you are on.
                    .accessibilityLabel(Text(entry.runnabilityLabel))
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.spacing(.tight))
                provenancePill(entry)
            }
            HStack(spacing: Theme.spacing(.tight)) {
                // Sixteen characters is what a person compares at a
                // glance; the full digest is on the detail screen,
                // because a truncated hash is a weaker claim and the
                // place it is VERIFIED should show the whole thing.
                Text(entry.shortIdentity).font(.caption2.monospaced())
                Text(entry.origin.label).font(.caption2)
            }
            .foregroundStyle(Theme.textTertiary)

            // THE ONE ORIGIN THAT COMES WITH A WARNING, AND IT IS ON THE ROW
            // RATHER THAN ONE SCREEN IN. A tuned policy looks exactly like
            // every other runnable entry — it loads, it has a digest, it has a
            // shape — and the thing that is different about it is invisible:
            // its weights were changed by a search on this phone and nothing
            // has ever run it on hardware. Amber, because it works; a person
            // who has to open a detail screen to find out is a person who will
            // send it to a robot first.
            if let caveat = entry.origin.caveat {
                Text(caveat)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let manifest {
                // THE TWO NUMBERS THAT DECIDE WHETHER A POLICY CAN DRIVE THIS
                // ROBOT AT ALL, in the component the app already has for a
                // label beside a value that changes. They vary from row to row
                // — that is the whole reason they are worth showing here rather
                // than on the detail screen — so they earn the tabular figures
                // `TelemetryRow` sets them in, and they reflow to stacked at
                // accessibility sizes instead of the value being truncated off
                // the right-hand edge. Drawing a smaller lookalike here is
                // exactly the drift `DesignComponents` exists to prevent.
                //
                // ONLY A POLICY THAT CAME WITH A MANIFEST HAS THEM. Everything
                // else shows nothing, rather than this app printing its own
                // architecture in the space reserved for a policy's claim about
                // itself.
                TelemetryRow(label: "Shape",
                             value: "\(manifest.observationLength) → \(manifest.actionLength)")
                if let scale = declaredScales[entry.id] {
                    TelemetryRow(label: "Action scale", value: scaleText(scale))
                }
                caveats(manifest)
            }
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }

    /// Two decimals, because the interesting difference between two policies is
    /// often the second one — a network declaring 1.00 driven at 0.90 is the
    /// 10% shortfall `BenchView` already documents.
    private func scaleText(_ scale: Double) -> String {
        String(format: "%.2f", scale)
    }

    /// What the author says is wrong with their own policy.
    ///
    /// THE YELLOW IS A CLAIM ABOUT WHERE THE WORDS CAME FROM. Teal is what a
    /// machine measured and yellow is what somebody asked for or wrote down,
    /// and every sentence here is a field an author filled in: the known
    /// limits, the stress trials, a training branch they say is not merged, a
    /// policy that has no end of its own. None of it is this app's judgement,
    /// and it is not set in the colour this app refuses things in.
    ///
    /// GLYPH AND COLOUR, NEVER COLOUR ALONE — and one glyph for the block
    /// rather than one per line, because three triangles down the left of a row
    /// reads as three separate alarms when it is one author being candid.
    @ViewBuilder
    private func caveats(_ manifest: PolicyManifest) -> some View {
        if !manifest.cautions.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityLabel(Text("The author's caveats"))
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    ForEach(manifest.cautions, id: \.self) { caution in
                        Text(caution)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.sensorActive)
            .padding(Theme.spacing(.snug))
            .frame(maxWidth: .infinity, alignment: .leading)
            // A CARD INSIDE A CARD TAKES THE NEXT RADIUS DOWN. The section is
            // drawn at the card radius, so the one container that sits inside a
            // row is drawn at the control radius, and the corners are
            // concentric rather than stacked. It is an outline and not a fill
            // because the palette's grounds are all within about 1.1:1 of each
            // other by design — a block inside a card cannot announce itself
            // with a surface here, only with a shape.
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius(.control), style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: hairlineStroke))
        }
    }

    // MARK: - where a policy came from

    /// Whose weights these are — which is a different question from how the
    /// file got here, and the two are answered separately on purpose.
    ///
    /// THE PILL IS THE PROVENANCE AND THE LINE BELOW IT IS THE TRANSPORT. A
    /// Pollen release downloaded from their repository is Pollen's; so is the
    /// bundled copy of the same weights. `origin.label` — "Bundled",
    /// "Imported", "From huggingface.co/…" — says how it arrived, and it stays
    /// where it was, beside the digest. What the pill adds is the answer the
    /// fingerprint gives, in a word short enough to sit at the end of a row.
    private enum Provenance {
        case pollen
        case community
        case brought
        /// Made here, by folding a searched residual into somebody else's
        /// network. A separate word because "Yours" would take the credit for
        /// the walk, which is not this app's to take.
        case tuned

        var title: String {
            switch self {
            case .pollen: return "Pollen Robotics"
            case .community: return "Community"
            case .brought: return "Yours"
            case .tuned: return "Tuned here"
            }
        }

        /// Teal for Pollen, lavender for everybody else's training, grey for a
        /// file somebody carried in themselves. Lavender is the palette's least
        /// used hue on its least frequent claim, which is what the design
        /// system asks of it.
        var colour: Color {
            switch self {
            case .pollen: return Theme.brandPrimary
            case .community: return Theme.training
            case .brought: return Theme.textSecondary
            // AMBER, WHICH IS THIS APP'S COLOUR FOR A THING THAT WORKS AND HAS
            // NOT BEEN CHECKED. It is not red: the file loads and runs. What is
            // true of it is that nobody has ever run it anywhere but a
            // simulator on a phone, which is a caution and not an error.
            case .tuned: return Theme.warning
            }
        }
    }

    private func provenance(of entry: PolicyLibrary.Entry) -> Provenance {
        if isReleased(model.standing(for: entry)) { return .pollen }
        switch entry.origin {
        case .fetched: return .community
        case .bundled, .imported: return .brought
        case .tuned: return .tuned
        }
    }

    private func provenancePill(_ entry: PolicyLibrary.Entry) -> some View {
        let whose = provenance(of: entry)
        return Text(whose.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(whose.colour)
            .padding(.horizontal, Theme.spacing(.tight))
            .padding(.vertical, Theme.spacing(.hairline))
            // A CAPSULE, WHICH THE SHAPE SCALE OTHERWISE RESERVES FOR THINGS
            // YOU PRESS — and it is here because `StateBadge` already sets the
            // precedent for a badge that is a capsule and is not pressable. Two
            // shapes for the same job would be a worse inconsistency than this
            // one. The outline is the separator: the word carries the colour,
            // and the pill only says the word belongs together.
            .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: hairlineStroke))
            .fixedSize()
    }

    // MARK: - nothing yet

    /// THE PERSON WHO MOST NEEDS THIS ROUTE. The sentence below offers Files,
    /// Mail and AirDrop and no way to reach the policies Pollen publishes —
    /// which is where somebody with an empty library actually has to go. It was
    /// drawn in secondary grey under the sentence, which is the wrong way round
    /// for the only thing there is to do on this screen: on an empty library it
    /// is THE action, so it is set as one.
    ///
    /// IT STAYS EVEN THOUGH DISCOVER IS NOW TWO SECTIONS DOWN. That looks like
    /// the duplicate door this redesign spent its afternoon deleting and it is
    /// the opposite case: Discover is a permanent shelf, phrased for somebody
    /// choosing between two catalogues, and this is the one state where there
    /// is nothing else on the screen at all. An empty state whose only
    /// affordance is further down the list is an empty state people leave.
    private var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.standard)) {
            Text("No policies yet. Send one to Microduck Studio from Files, Mail or AirDrop.")
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            NavigationLink { CatalogueView(model: model) } label: {
                Label("Get more from Pollen Robotics",
                      systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
        }
        .padding(.vertical, Theme.spacing(.tight))
        .listRowBackground(cardSegment(first: true, last: true))
    }
}

/// One policy: what it is, where it came from, and what is inside it.
struct PolicyDetailView: View {
    let entry: PolicyLibrary.Entry
    /// For the "Run it on a bench" link. THE COMMENT BELOW PROMISED TWO THINGS
    /// AND ONE WAS BUILT: remix reached this screen and run did not, so the
    /// only route to a bench stayed the menu two taps back that cannot know
    /// which policy you have open — the exact complaint the comment makes.
    @ObservedObject var model: LibraryModel
    /// So this policy can be remixed and run from its own screen, rather than
    /// only from a menu two taps away that does not know which one you are
    /// looking at.
    let library: PolicyLibrary
    @ObservedObject var benches: BenchStore
    let standing: DuckOfficialPolicies.Standing
    @ObservedObject var scenes: SceneStore
    @ObservedObject var drafts: DraftStore
    /// For the player below: a recording listed here opens the same viewer, and
    /// a remix from it opens the same editor, as Studio → Motions. Without this
    /// the Ask panel in that editor was disabled with a message pointing at a
    /// screen this view tree does not contain.
    @ObservedObject var models: EndpointStore
    /// See `PolicyListView.router`. Driving is a tab, not a screen this stack
    /// owns a second copy of.
    @EnvironmentObject private var router: AppRouter
    @State private var clips: [String: DuckIntentClip] = [:]
    @State private var failure: String?

    /// The one sheet this screen can have up, and which one it is.
    ///
    /// ONE OPTIONAL, BECAUSE TWO CANNOT BOTH BE NIL BY ACCIDENT. `IntentListView`
    /// already paid for this lesson and wrote it down: two `.sheet` modifiers on
    /// one view are not two slots — the second wins, and which one that is
    /// depends on modifier order rather than on anything a reader can see. This
    /// screen grew its second sheet in build 47, so it takes the same shape
    /// rather than rediscovering the same silent failure.
    private enum Presented: Identifiable {
        /// A packaged policy file and the message that goes with it.
        case share(Outgoing)
        /// Giving this policy a name. ONE DOOR, ON THIS SCREEN — the list
        /// behind it has none, because a rename affordance on every row is a
        /// screen full of controls for the one thing nobody does twice.
        case rename

        var id: String {
            switch self {
            case .share(let out): return "share:\(out.id)"
            case .rename:         return "rename"
            }
        }
    }

    @State private var presented: Presented?

    /// The entry as the library holds it NOW.
    ///
    /// A NAVIGATION DESTINATION IS BUILT FROM A VALUE AND KEEPS IT. `entry` was
    /// copied when the row was tapped, so after a rename it still carries the
    /// old title — the sheet would close onto a navigation bar that had not
    /// changed. The library is observed, so looking the entry back up by
    /// identity is what makes this screen agree with itself.
    private var shown: PolicyLibrary.Entry {
        model.library.entries.first { $0.id == entry.id } ?? entry
    }

    /// Clips whose recorded-from policy is this file. Matched on the FILE name
    /// the recorder wrote, which is the only link the clip carries — and a
    /// rename must never break it.
    private var madeFromThisPolicy: [DuckIntentClip] {
        clips.values.filter { $0.policy == entry.fileName }.sorted { $0.name < $1.name }
    }

    var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { share() } label: { Image(systemName: "square.and.arrow.up") }
                        // The button people go hunting for, and the one an
                        // unlabelled square-and-arrow-up hides best.
                        .accessibilityLabel(Text("Share this policy"))
                        .disabled(!entry.isRunnable && !entry.identity.isNetworkIdentity)
                }
            }
            .sheet(item: $presented) { what in
                switch what {
                case .share(let out):
                    NavigationStack {
                        ShareDestinationsView(title: shown.title,
                                              file: out.url, message: out.message)
                    }
                case .rename:
                    PolicyRenameSheet(entry: shown) { typed in
                        model.rename(shown, to: typed)
                    }
                }
            }
            .alert("Could not share", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(failure ?? "") }
    }

    /// Hand over the policy FILE, with a message that leads with the digest.
    /// The person pasting this is about to ask strangers to run it on a robot,
    /// so an unrecognised policy is described as unrecognised.
    private func share() {
        // THE LIVE ENTRY, SHADOWED ON PURPOSE. A rename changes what a
        // digest-named policy exports as, and the copy this destination was
        // built with does not know about it.
        let entry = shown
        guard let data = PolicyStore.data(for: entry) else {
            failure = "The policy file could not be re-read."
            return
        }
        do {
            // THE FILE LEAVES UNDER ITS OWN NAME, never under a nickname. A
            // title means something on this phone and nothing in somebody
            // else's downloads folder — `exportFileName` reaches for it only
            // when there is no file name to use, and the drafted message then
            // says whose word it is.
            let url = try ExportFile.write(data, named: entry.exportFileName)
            presented = .share(Outgoing(
                url: url,
                message: CommunityShare.message(forPolicy: entry, standing: standing)))
        } catch let error as ExportFile.Failure {
            failure = error.message
        } catch {
            failure = "\(error)"
        }
    }

    /// THE SECTIONS HERE TAKE A FLAT SURFACE, NOT THE SEGMENTED CARD. The list
    /// screen's two policy sections are the ones the design system names, and
    /// their rows come out of a `ForEach` where the first and last are known.
    /// Half the sections below are built from optionals — a reason that may be
    /// empty, a remedy that may be nil — so "which row is last" is a question
    /// this file would have to answer twice and could get wrong once. A flat
    /// `surfacePrimary` on the platform's group shape is the same surface at a
    /// radius somebody else maintains, which is the right trade for a screen
    /// the brief does not draw.
    private var content: some View {
        List {
            Section {
                Text(DuckOfficialPolicies.summary(for: standing))
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                nameRow
                fileNameRow
                // STACKED, NOT A `TelemetryRow`. A digest is 64 characters
                // wide: set beside its label it either truncates or wraps to
                // three lines of body-sized monospace, and it has to stay
                // selectable so somebody can compare it against a repository.
                // This is the shape `TelemetryRow` itself takes at
                // accessibility sizes, at every size.
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    Text(entry.identity.isNetworkIdentity ? "Weights" : "File digest")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text(entry.identity.value)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                }
                if !entry.identity.isNetworkIdentity {
                    Text("This file does not load, so it has no weights to fingerprint. It is identified by the bytes of the file instead — which is a weaker kind of identity, and the reason it says so.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                arrived
                // WHERE A POLICY CAME FROM CANNOT BE RECOVERED AFTER THE FACT.
                // Anything imported before this build was persisted with no
                // record of its host, and the app will not guess one out of a
                // manifest's training repository — so the pill stays the honest
                // grey and this says why it is grey.
                if !shown.arrivalWasRecorded {
                    Text(PolicyNaming.arrivalNotRecorded)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                SectionHeading(text: "Provenance")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Text(entry.report.headline)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                if !entry.report.reason.isEmpty {
                    Text(entry.report.reason)
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                }
                if let remedy = entry.report.remedy {
                    Text(remedy).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                // WHERE THE REFUSAL STOPS. This app reads one exact
                // architecture and the robot's runtime reads far less, so a
                // refusal here is not the robot's answer — and a person looking
                // at "will not load" is exactly the person about to conclude
                // their file is broken.
                if entry.report.outcome == .refused {
                    Text(PolicyReport.refusalIsAboutThisApp)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            } header: {
                SectionHeading(text: entry.isRunnable ? "Verdict" : "Why it will not load here")
            }
            .listRowBackground(Theme.surfacePrimary)

            if entry.isRunnable {
                Section {
                    // THE PREVIEW GOES FIRST, AND IT ALREADY EXISTED. This
                    // screen led with "Probe this network" — one observation in,
                    // fourteen numbers out, nothing moving — and then told you
                    // in its footer to go and find a bench, while a playable
                    // recording of this exact policy sat two sections further
                    // down under a heading nobody reads as "press here to watch
                    // it". Somebody arriving to see what a policy DOES was sent
                    // to another machine to obtain something they already had.
                    //
                    // AND IT IS THE ONE ACTION DRAWN AS AN ACTION. Five
                    // navigation rows of equal weight is a menu, not a screen
                    // with a point of view; this is the thing somebody came
                    // here to do, so it is a capsule in the action colour and
                    // the other four stay rows. `PrimaryActionStyle` is what
                    // makes it one — including the part where it darkens under
                    // the thumb instead of shrinking away from it.
                    // THE ONE CASE WHERE NAMING IT IS THE POINT OF THE SCREEN.
                    // A `.digest` title says the app does not know what this
                    // file was called; offering the fix as a row among five
                    // would bury the answer to the question the title asks.
                    if shown.titleSource == .digest {
                        Button { presented = .rename } label: {
                            Label("Name this policy", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.primaryAction)
                        .listRowSeparator(.hidden)
                    }
                    if let preview = madeFromThisPolicy.first {
                        NavigationLink { IntentPlayerView(clip: preview, store: scenes,
                                                          drafts: drafts, models: models) } label: {
                            Label("Watch it move", systemImage: "play.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.primaryAction)
                        .listRowSeparator(.hidden)
                    }
                    NavigationLink { BenchView(entry: entry, model: model,
                                               store: scenes) } label: {
                        secondaryAction("Probe this network",
                                        symbol: "slider.horizontal.below.square.filled.and.square")
                    }
                    // REMIX AND RUN, FROM THE POLICY YOU ARE LOOKING AT.
                    // Both existed and neither was reachable from here: blending
                    // was a menu item on the list behind this screen, which
                    // cannot know which policy you had open, and running one
                    // meant going to the bench and picking it out of a list by
                    // name. A policy's own screen is where somebody asks "what
                    // can I do with this one".
                    if library.runnableCount >= 2 {
                        NavigationLink { PolicyBlendView(library: library,
                                                         benches: benches,
                                                         starting: entry) } label: {
                            secondaryAction("Remix it with another",
                                            symbol: "arrow.triangle.merge")
                        }
                    }
                    NavigationLink { RemoteRunView(model: model, scenes: scenes,
                                                   drafts: drafts, models: models,
                                                   benches: benches) } label: {
                        secondaryAction("Run it on a bench", symbol: "wifi")
                    }
                    // THE PRESENT TENSE, UNDER THE TWO PAST ONES. Watch is what
                    // it did, Run records what it does under a schedule written
                    // in advance; this is the one where you decide what happens
                    // next while it is happening.
                    //
                    // AND IT IS THE CONTROL TAB, NOT A SECOND COPY OF IT. This
                    // pushed its own `DriveView` onto the Behaviours stack,
                    // which meant two live instances of the one screen that
                    // moves a robot could exist at once, each with its own
                    // connection state, and the tab bar would go on saying
                    // Behaviours while a duck walked. Selecting the tab is the
                    // whole action: it does not preselect this policy, because
                    // it never did — the old push carried no entry either, and
                    // pretending otherwise would be a claim about loading that
                    // nothing here performs.
                    Button {
                        router.go(to: .control)
                    } label: {
                        secondaryAction("Drive it live", symbol: "gamecontroller")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens the Control tab."))
                } footer: {
                    // TWO DIFFERENT SCREENS, AND THE ADVICE DIFFERS. With a
                    // recording in hand the bench is optional; without one — a
                    // remix, a policy somebody sent you — it is the only way to
                    // see the thing move at all, and saying "run it on a bench"
                    // to somebody who already has the recording is what sent
                    // people away from the answer.
                    if PolicyNaming.isDigestName(entry.fileName) {
                        // A NOT-YET, BESIDE CONTROLS THAT STILL WORK. Probe and
                        // the bench are unaffected; it is only the clip link
                        // that has nothing to match on, and matching by
                        // fingerprint is not built.
                        sectionFootnote(PolicyNaming.recordingsNeedAFileName)
                    } else if madeFromThisPolicy.isEmpty {
                        sectionFootnote("Nothing has been recorded from this network yet, so there is nothing to play. A preview cannot play a policy: watching one move means running it on a bench, and this iPhone is one. Run it on a bench, record it, and keep the recording — it comes back under Studio → Motions, in \"Brought in\".\n\nProbe hands it one observation and shows the fourteen numbers it answers with, and the robot they command. That works with no bench at all, but a network has no time axis, so nothing plays there either.")
                    } else {
                        sectionFootnote("Watch it move plays a recording made when this network drove a robot in physics — what it did, not what somebody asked for. Probe is the other half: hand it one observation and see the fourteen numbers it answers with. A network has no time axis, so nothing plays in Probe.\n\nRun it on a bench to record it again under your own commands, on your own floor.")
                    }
                }
                .listRowBackground(Theme.surfacePrimary)

                // The real link between the two halves of this app: a clip
                // names the policy it was recorded from, so a policy can list
                // its own recordings. Shown only when there ARE any, rather
                // than as an empty section implying something is missing.
                let recordings = madeFromThisPolicy
                if !recordings.isEmpty {
                    Section {
                        ForEach(recordings, id: \.name) { clip in
                            NavigationLink { IntentPlayerView(clip: clip, store: scenes, drafts: drafts,
                                                              models: models) } label: {
                                HStack {
                                    Text(clip.name)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(clip.startsFrom.rawValue) → \(clip.endsIn.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                    } header: {
                        SectionHeading(text: "Recorded from this policy")
                    } footer: {
                        sectionFootnote("Motions this network produced when it drove a robot in physics. These play; the network itself does not.")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                    .listRowSeparatorTint(Theme.separator)
                }
            }

            Section {
                // THE STRUCTURE TABLE IS TELEMETRY IN THE STRICT SENSE THE
                // DESIGN SYSTEM MEANS: a label that is the same on every policy
                // beside a value that is different on every policy. It was set
                // in caption monospace, trailing-aligned, which at
                // accessibility sizes is a fight for the width that the value
                // always loses — the app hiding the number from the person who
                // enlarged the type in order to read it. `TelemetryRow` stacks
                // instead of truncating.
                ForEach(entry.report.facts, id: \.label) { fact in
                    TelemetryRow(label: fact.label, value: fact.value)
                }
            } header: {
                SectionHeading(text: "Structure")
            }
            .listRowBackground(Theme.surfacePrimary)
            .listRowSeparatorTint(Theme.separator)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(shown.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { clips = (try? DuckIntentClip.bundled()) ?? [:] }
    }

    /// What this policy is CALLED, and the door to changing it.
    ///
    /// THE WHOLE ROW IS THE BUTTON, and the pencil is a hint rather than the
    /// target. A 44 pt glyph at the end of a row somebody has to aim at is the
    /// affordance this app keeps failing to make findable; a row that responds
    /// anywhere is one nobody has to aim at.
    ///
    /// AND THE CAPTION UNDER IT IS THE POINT OF THE WHOLE SECTION. Every rung
    /// of the ladder is a different KIND of claim — a person's word, a checked
    /// fact about the weights, a stranger's claim about them — and a screen
    /// that showed the name without saying where it came from would be setting
    /// all three in the same typeface.
    private var nameRow: some View {
        Button { presented = .rename } label: {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
                    Text("Name")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: Theme.spacing(.tight))
                    Text(shown.title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "pencil")
                        .foregroundStyle(Theme.actionSecondary)
                }
                if let explanation = shown.titleExplanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Name, \(shown.title)"))
        .accessibilityHint(Text("Renames this policy on this phone."))
    }

    /// What the file is called, under the name a person reads.
    ///
    /// IT IS DRAWN EVEN WHEN THERE IS NOTHING TO SHOW, because "not kept" is
    /// the honest answer and an absent row would read as a screen that had not
    /// finished loading. What it does NOT do is print the digest a second time
    /// under a label saying "file name" — the digest is above, called what it
    /// is.
    private var fileNameRow: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Text("File name")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            if PolicyNaming.isDigestName(shown.fileName) {
                Text(PolicyNaming.fileNameUnknown)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Text(PolicyNaming.fileNameNotKept)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(shown.fileName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// How the file got onto this phone, as opposed to whose weights they are.
    private var arrived: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
            Text("Arrived")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: Theme.spacing(.tight))
            // NOT MONOSPACE, AND THE RULE IS THE REASON. Tabular figures are
            // this app's claim that a value changes; "Bundled" never will, for
            // this policy or any other, so setting it in the face reserved for
            // things that move would be telling the reader to watch it.
            Text(entry.origin.label)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// One of the four doors that is not the primary one.
    ///
    /// THE SYMBOL CARRIES THE ACTION COLOUR AND THE WORD DOES NOT. Orange ink
    /// on the surface is 4.92:1 and would be perfectly legible as a label, but
    /// a row of four orange sentences reads as four buttons, which is the thing
    /// the primary action above them is supposed to be alone in being. The glyph
    /// in `actionSecondary` says "this does something" quietly; the word stays
    /// the colour every other word on the screen is.
    private func secondaryAction(_ title: String, symbol: String) -> some View {
        Label {
            Text(title).foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.actionSecondary)
        }
    }
}
