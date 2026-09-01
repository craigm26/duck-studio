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
private let hairlineStroke: CGFloat = 1

/// A section heading, in the one heading style this design system has.
///
/// THIRTEEN POINTS, BOLD, SIX PER CENT OF TRACKING, TERTIARY. That is the brand
/// sheet's heading, and the only interesting decision here is that the size is
/// `@ScaledMetric` rather than the literal 13. A heading pinned to a point size
/// is a heading that does not grow when somebody enlarges type, so at AX5 the
/// section headings are the smallest text on a screen where everything else has
/// doubled — and the tracking has to be derived from whatever size that lands
/// on, because six per cent of 13 is not six per cent of 30.
///
/// `.textCase(nil)` because SwiftUI upper-cases grouped section headers by
/// default, and "RELEASED BY POLLEN ROBOTICS" is a different, louder app.
private struct SectionHeading: View {
    let text: String

    /// The `.footnote` point size at the person's current setting; 13 is what
    /// that style measures at the default content size.
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 13

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .tracking(size * 0.06)
            .textCase(nil)
            .foregroundStyle(Theme.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

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

/// The library: every policy this app holds, and where each one came from.
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
    /// same editor as one remixed from the Motions tab, and the Ask panel there
    /// was dead for want of this one argument. No screen in this app puts a
    /// store in the environment; every one is passed by hand, so a feature that
    /// needs one three screens down has to be threaded through the two between.
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore

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
            if !released.isEmpty {
                Section {
                    rows(released)
                } header: {
                    SectionHeading(text: "Released by Pollen Robotics")
                } footer: {
                    sectionFootnote("Matched by fingerprint — a digest of the trained weights, not of the file. A re-export under a newer opset still matches; one changed weight does not.")
                }
            }
            if !elsewhere.isEmpty {
                Section {
                    rows(elsewhere)
                } header: {
                    SectionHeading(text: "From elsewhere")
                } footer: {
                    sectionFootnote("Trained by someone else, or newer than this app knows about. This only says the weights are unfamiliar — not that they are bad.")
                }
            }
            if model.library.entries.isEmpty {
                Section { emptyLibrary }
            }
        }
        .scrollContentBackground(.hidden)
        // THE RECESSED GROUND, WHICH IS WHAT THIS TOKEN IS FOR. Grouped
        // content sits on it and the words sit on the cards, the way
        // `systemGroupedBackground` works on iOS — see `sectionFootnote` for
        // the numbers that make that a rule rather than a preference.
        .background(Theme.backgroundSecondary)
        .navigationTitle("Policies")
        .confirmationDialog("Remove this policy?",
                            isPresented: Binding(get: { removing != nil },
                                                 set: { if !$0 { removing = nil } }),
                            presenting: removing) { entry in
            Button("Remove \(entry.displayName)", role: .destructive) {
                model.removePolicy(entry)
                removing = nil
            }
            Button("Keep it", role: .cancel) { removing = nil }
        } message: { entry in
            Text(entry.removalWarning)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // A COUNT THAT CHANGES, SO IT IS SET IN FIGURES THAT DO NOT
                // MOVE. Tabular digits are the design system's claim that a
                // number is live; this one goes up and down as policies are
                // added and removed, which is exactly what earns them.
                Text("\(model.library.runnableCount) of \(model.library.entries.count) run")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            // ONE MENU OF WORDS, NOT FOUR BARE GLYPHS. This carried four
            // icon-only links, one of which appeared only once the library had
            // two runnable policies — so the row shifted under the thumb as
            // policies were added, and "antenna radiowaves left and right" was
            // the only name three of them had. A menu of text rows is the
            // pattern `IntentAuthorView` already uses.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink { DriveView(model: model, benches: benches,
                                               scenes: scenes) } label: {
                        Label("Drive one live", systemImage: "gamecontroller")
                    }
                    // THE ONLY DOOR IN THIS APP THAT OPENS ONTO HARDWARE, and
                    // for now the only person it is useful to is somebody
                    // holding a Microduck. It sits here rather than behind a
                    // setting because the first of those people to open the app
                    // should not have to be told where it is.
                    NavigationLink { FindDuckView() } label: {
                        Label("Find a real duck", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    NavigationLink { RemoteRunView(model: model, scenes: scenes, drafts: drafts,
                                                   models: models, benches: benches) } label: {
                        Label("Run on your network", systemImage: "wifi")
                    }
                    // ONLY WORTH OFFERING WITH TWO THINGS TO MIX. A blend of
                    // one policy is that policy, which `PolicyBlend` refuses
                    // anyway; showing the door to a refusal is not an
                    // affordance. In a menu this no longer moves anything.
                    if model.library.runnableCount >= 2 {
                        NavigationLink { PolicyBlendView(library: model.library,
                                                         benches: benches) } label: {
                            Label("Blend two policies", systemImage: "arrow.triangle.merge")
                        }
                    }
                    NavigationLink { CatalogueView(model: model) } label: {
                        Label("Pollen Robotics",
                              systemImage: "antenna.radiowaves.left.and.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(Text("More"))
                }
            }
            // The Benches link is gone from here: it is Settings → Benches now,
            // and still two taps from the four screens that actually run things.
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
                    .accessibilityLabel(Text(entry.report.headline))
                Text(entry.displayName)
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

        var title: String {
            switch self {
            case .pollen: return "Pollen Robotics"
            case .community: return "Community"
            case .brought: return "Yours"
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
            }
        }
    }

    private func provenance(of entry: PolicyLibrary.Entry) -> Provenance {
        if isReleased(model.standing(for: entry)) { return .pollen }
        switch entry.origin {
        case .fetched: return .community
        case .bundled, .imported: return .brought
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
    /// a remix from it opens the same editor, as the Motions tab. Without this
    /// the Ask panel in that editor was disabled with a message pointing at a
    /// screen this view tree does not contain.
    @ObservedObject var models: EndpointStore
    @State private var clips: [String: DuckIntentClip] = [:]
    @State private var outgoing: Outgoing?
    @State private var failure: String?

    /// Clips whose recorded-from policy is this file. Matched on the filename
    /// the recorder wrote, which is the only link the clip carries.
    private var madeFromThisPolicy: [DuckIntentClip] {
        clips.values.filter { $0.policy == entry.displayName }.sorted { $0.name < $1.name }
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
            .sheet(item: $outgoing) { out in
                NavigationStack {
                    ShareDestinationsView(title: entry.displayName,
                                          file: out.url, message: out.message)
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
        guard let data = PolicyStore.data(for: entry) else {
            failure = "The policy file could not be re-read."
            return
        }
        do {
            let url = try ExportFile.write(data, named: entry.displayName)
            outgoing = Outgoing(url: url,
                                message: CommunityShare.message(forPolicy: entry, standing: standing))
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
                    NavigationLink { DriveView(model: model, benches: benches,
                                               scenes: scenes) } label: {
                        secondaryAction("Drive it live", symbol: "gamecontroller")
                    }
                } footer: {
                    // TWO DIFFERENT SCREENS, AND THE ADVICE DIFFERS. With a
                    // recording in hand the bench is optional; without one — a
                    // remix, a policy somebody sent you — it is the only way to
                    // see the thing move at all, and saying "run it on a bench"
                    // to somebody who already has the recording is what sent
                    // people away from the answer.
                    if madeFromThisPolicy.isEmpty {
                        sectionFootnote("Nothing has been recorded from this network yet, so there is nothing to play. A phone has no physics engine: watching a policy move means running it somewhere that does. Send it to a bench, record it, and keep the recording — it comes back to the Motions tab under \"Brought in\".\n\nProbe hands it one observation and shows the fourteen numbers it answers with, and the robot they command. That works with no bench at all, but a network has no time axis, so nothing plays there either.")
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
        .navigationTitle(entry.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { clips = (try? DuckIntentClip.bundled()) ?? [:] }
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
