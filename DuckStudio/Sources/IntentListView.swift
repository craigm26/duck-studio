import SwiftUI
import DuckKit
import DuckEvidence
import StudioKit

// MARK: - the pieces this screen shares with the Behaviours tab

/// One point — the thinnest rule iOS draws crisply.
///
/// THIS IS THE FOURTH PLACE IN THE APP TO WRITE THIS NUMBER DOWN, AND
/// `PolicyListView` SAID WHAT THAT MEANS. Its own copy carries the sentence
/// "two files knowing that a hairline is one point is tolerable; a third would
/// mean the number belongs in `Palette`" — and the count was already past that
/// before this line: `DesignComponents.Metric.hairlineStroke`,
/// `DriveView.DriveMetric.hairlineStroke` and `PolicyListView`'s own. So by
/// that file's own rule the stroke has earned a place in the design system
/// beside the radii and the focus ring's geometry, and this declaration is the
/// evidence rather than the argument. It is written here rather than moved
/// there because this change owns the root and Studio → Motions and nothing
/// else; the move is a one-line addition to `Palette` and a four-place
/// deletion, and it should be made by whoever owns the tokens next.
private let hairlineStroke = DesignMetric.hairlineStroke

/// A section heading, in the one heading style this design system has.
///
/// A DELIBERATE SECOND COPY, NOT A DIVERGENCE. `PolicyListView` declares the
/// same three helpers `private` at file scope, which in Swift means file-local,
/// so there is nothing to import and nothing that can collide. Two screens
/// drawing the same heading from two identical declarations is drift waiting to
/// happen and it is written down here so the next person sees it: these two —
/// `sectionFootnote`, `cardSegment` — still belong in `DesignComponents`,
/// beside `StateBadge` and `TelemetryRow`, for exactly the reason that file
/// already gives ("drawn twice, they drift within a release"). `SectionHeading`
/// has made that move and the private copy this file carried is gone.

/// The explanatory line under a section, and the long sentences this screen
/// leads with.
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

private extension View {
    /// A row that is part of a card: the right corner treatment for where it
    /// sits in the run, and the palette's own rule between it and the next one.
    ///
    /// The separator is 1.42:1 on the surface and that is deliberate — the
    /// palette calls a separator decoration in SC 1.4.11's sense, because the
    /// rows are already separated by space and by type, and a rule dark enough
    /// to clear 3:1 on cream would read as a table border.
    func cardRow(first: Bool, last: Bool) -> some View {
        listRowBackground(cardSegment(first: first, last: last))
            .listRowSeparatorTint(Theme.separator)
    }
}

/// The recordings. A separate place from the policies, because they are a
/// separate kind of thing.
///
/// A POLICY IS A NETWORK; AN INTENT IS A MOTION. A policy has no time axis at
/// all — you hand it an observation and it answers with fourteen numbers, and
/// that is the whole of it. An intent has nothing BUT a time axis: it is what
/// happened over four seconds when a policy drove a robot in a physics engine.
/// One is probed, the other is watched.
///
/// The first cut of this app put them on one screen, and the seam showed
/// immediately: opening `roulade.onnx` and tapping through to its bench offered
/// a list of clips that had nothing to do with roulade, under a heading about
/// standard deviations that described the observation rather than any of them.
/// They are two lists now, and the real relationship between them — every clip
/// names the policy it was recorded from — is shown as a link rather than as an
/// accident of layout.
///
/// AND THE COLOUR SAYS WHAT THE HEADING SAYS. This screen is sorted by
/// provenance, so it uses the palette as a claim about provenance and nothing
/// else: teal is Pollen's own network driven in physics, yellow is a motion
/// somebody WROTE, lavender is somebody else's training, and grey is a file
/// that came off this person's own bench. Nothing here is distinguished by
/// colour alone — every pill says its word as well as wearing its colour, and
/// every worrying number is a number before it is a hue.
struct IntentListView: View {
    /// Which model answers a plain-language tweak inside the editor. Threaded
    /// through rather than made here, so Studio → Draft and the editor share one
    /// choice — two stores would mean picking Claude in one place and getting
    /// Apple's model in the other.
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore
    @ObservedObject var plans: PlanStore

    @ObservedObject var store: SceneStore
    @ObservedObject var model: LibraryModel
    @ObservedObject var drafts: DraftStore
    /// PRESENTED ON AN ID, NOT ON A COPY. Holding the draft itself meant the
    /// sheet carried a stale value that went out of date on the first
    /// keystroke, and — because the editor writes to DraftStore as you type —
    /// the list re-rendered continuously underneath it, re-running the sheet's
    /// content closure on every change.
    @State private var editing: DraftID?
    /// The brand-new motion that nobody has written into yet, and which is
    /// therefore NOT in the store. See the "Write a new motion" button for why
    /// it waits here instead.
    ///
    /// LOAD-BEARING FOR THE SHEET'S LOOKUP. Until the editor's first change
    /// reaches `onSave`, this is the only place that draft exists, and the
    /// sheet below has no `else` — lose it while the sheet is up and the
    /// person gets an empty, toolbar-less NavigationStack they cannot leave.
    /// So it is cleared in `onDismiss`, after the sheet is gone, and nowhere
    /// else.
    @State private var unwritten: IntentDraft?
    @State private var clips: [String: DuckIntentClip] = [:]
    @State private var picking = false
    /// Rolled-out rates, loaded once. The list is the place these matter most:
    /// scanning fourteen motions for the ones that actually work is the whole
    /// reason to have measured them.
    @State private var odds: DuckIntentSuccess?

    private var fromPollen: [DuckIntentClip] {
        sorted(clips.values.filter { !$0.authored && $0.credit == nil })
    }
    private var authored: [DuckIntentClip] {
        sorted(clips.values.filter { $0.authored })
    }
    private var shared: [DuckIntentClip] {
        sorted(clips.values.filter { $0.credit != nil })
    }

    private func sorted(_ c: [DuckIntentClip]) -> [DuckIntentClip] {
        c.sorted { $0.name < $1.name }
    }

    /// The not-yet-written new motion, but only if it is the one this sheet was
    /// opened for. Matched by id rather than handed over on trust, so a stale
    /// one can never stand in for a row that means something else.
    private func standIn(for id: UUID) -> IntentDraft? {
        unwritten?.id == id ? unwritten : nil
    }

    /// What a saved plan says in one line.
    ///
    /// STUDIOKIT'S SENTENCE, NOT THIS FILE'S. It asserts what the robot can do
    /// with somebody's object, which is the one class of claim that is not a
    /// view's to compose — see `Retrieval.Plan.oneLine`, and the tests that
    /// pin it.
    private func planSummary(_ file: DuckPlanFile) -> String { file.plan.oneLine }

    var body: some View {
        List {
            Section {
                sectionFootnote("Motions recorded in MuJoCo from the trained policies, because the policy cannot run live on a phone. Playing one shows what the robot did; it does not re-run the network.")
                    .cardRow(first: true, last: true)
            }

            writtenHere

            // PLANS ARE KEPT NOW, NOT JUST EXPORTED. A fetch used to leave as a
            // quackd task file this app could not read back, so the only record
            // of a plan was a file in Files that returned "nothing was added".
            if !plans.plans.isEmpty { savedPlans }

            if !drafts.drafts.isEmpty { simToReal }

            // WHERE THE IMPORTER SAYS WHAT HAPPENED. `model.lastImport` was
            // drawn on the Behaviours tab and nowhere else, so a `.duckmove`, a
            // `.duck` or an unrecognised file picked from THIS screen's own
            // import button was refused into a void: the sheet closed, the list
            // did not change, and the sentence explaining why was on a tab the
            // person was not looking at.
            if let message = model.lastImport {
                Section {
                    sectionFootnote(message)
                        .cardRow(first: true, last: true)
                }
            }
            if !fromPollen.isEmpty {
                Section {
                    clipRows(fromPollen, whose: .pollen)
                } header: {
                    SectionHeading(text: "From Pollen's policies")
                } footer: {
                    sectionFootnote("The policy's own output, driven in physics and recorded.")
                }
            }
            if !authored.isEmpty {
                Section {
                    clipRows(authored, whose: .authored)
                } header: {
                    SectionHeading(text: "Authored moves")
                } footer: {
                    sectionFootnote("A keyframe track riding on a standing policy as offsets — searched against a prop rather than trained. These are the ones most likely to fail, and the posture each ends in says whether it did.")
                }
            }
            if !model.importedClips.isEmpty {
                Section {
                    // THEIRS TO THROW AWAY, AND UNTIL NOW THEY COULD NOT.
                    // Everything in this section arrived by AirDrop, by
                    // Files, or off the person's own bench; none of it is
                    // the app's, and there was no delete anywhere on the
                    // screen that listed it. The bundled clips are a
                    // different array and keep no swipe.
                    clipRows(model.importedClips, whose: .yours) { offsets in
                        offsets.map { model.importedClips[$0] }
                               .forEach { model.removeIntent($0) }
                    }
                } header: {
                    // NOT "Sent to you". Recordings kept from your own bench
                    // land in exactly this array — nobody sent those, and the
                    // footer's promise about digests is false for them on
                    // purpose: `RemoteRunView.keepRecording` passes
                    // `policyFingerprint: nil` because a policy running on a
                    // bench has no digest this phone computed, and inventing one
                    // would put an unverified number on a card.
                    SectionHeading(text: "Brought in")
                } footer: {
                    sectionFootnote("Motions from a .duckintent file — sent to you, or kept from your own bench. One that carries a digest names the policy it was recorded from, so you can check whether you hold the same network; a bench recording carries none, and its card says so.")
                }
            }
            if !shared.isEmpty {
                Section {
                    clipRows(shared, whose: .community)
                } header: {
                    SectionHeading(text: "Shared by other owners")
                } footer: {
                    sectionFootnote("Recorded the same way, from a policy this app did not ship.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        // THE RECESSED GROUND, WHICH IS WHAT THIS TOKEN IS FOR. Grouped content
        // sits on it and the words sit on the cards, the way
        // `systemGroupedBackground` works on iOS — see `sectionFootnote` for
        // the numbers that make that a rule rather than a preference.
        .background(Theme.backgroundSecondary)
        .navigationTitle("Motions")
        // SAID OUT LOUD RATHER THAN INHERITED. A `NavigationStack` root already
        // gets a large title by default, so this line changes nothing today —
        // it pins the design system's choice against a future default, and it
        // is the only place the choice can be made without reaching into a
        // screen this change does not own. See `DuckStudioApp` for why the root
        // does not impose it on the other four tabs.
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // NO GEAR HERE ANY MORE. ONE PER TAB ROOT, AND THIS IS NO LONGER
            // ONE. Motions is a row inside Studio, whose own root carries the
            // gear — so a gear here put two of them one tap apart, in the same
            // corner, leading to the same screen, which reads as two different
            // Settings until somebody opens both to find out.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // WARMED HERE BECAUSE THIS IS THE TAP BEFORE THE EVENT.
                    // The taptic engine spins up on demand and the delay is
                    // long enough that the first tap of a session lands after
                    // the thing it is about — which teaches a person that the
                    // buzz and the event are unrelated. Opening the picker is
                    // the moment an import becomes possible, and it is several
                    // seconds ahead of the file actually arriving.
                    Haptic.prepare()
                    picking = true
                } label: { Image(systemName: "square.and.arrow.down") }
                    // The door every shared motion and every policy file comes
                    // in through, and an icon-only one. What it accepts is said
                    // by the picker it opens and by `model.lastImport`
                    // afterwards; the button only has to be findable.
                    .accessibilityLabel(Text("Import a file"))
            }
        }
        .fileImporter(isPresented: $picking,
                      allowedContentTypes: [.json, .data],
                      allowsMultipleSelection: false) { result in
            // The same door as onOpenURL, so a motion picked from Files and one
            // AirDropped end up in the same place having had the same checks —
            // including the tap, which is why both go through `Imports.open`
            // rather than calling `model.open` directly.
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Imports.open(url, model: model, drafts: drafts, plans: plans)
                }
            case .failure(let error):
                // THE PICKER CAN FAIL AND USED TO DO IT IN SILENCE. `if case
                // .success` dropped the other half on the floor, so a file the
                // system would not hand over — a permission the user backed out
                // of, an iCloud item that never downloaded — looked exactly like
                // a tap that did nothing.
                model.lastImport = "That file could not be opened. \(error.localizedDescription)"
            }
        }
        .onAppear {
            clips = (try? DuckIntentClip.bundled()) ?? [:]
            odds = try? DuckIntentSuccess.bundled()
        }
        // ONLY AFTER THE SHEET IS GONE. `onDismiss` runs on every way out —
        // Done, Cancel, the confirmation dialog, and the swipe — which is
        // exactly why nothing that decides a draft's fate lives here: it cannot
        // tell those four apart. It does one safe thing, which is to stop
        // holding a motion the editor has finished with.
        // CLEARED ONLY IF NOTHING IS WAITING TO OPEN. `onDismiss` is a
        // trailing event: if it lands after a second "Write a new motion" tap
        // has already set `unwritten` and `editing`, an unconditional clear
        // takes the new draft out from under the sheet that is opening, and the
        // lookup then resolves to neither the store nor the stand-in — which is
        // the empty, toolbar-less editor this file has been bitten by before.
        .sheet(item: $editing, onDismiss: { if editing == nil { unwritten = nil } }) { wrapper in
            NavigationStack {
                // Looked up fresh, so the editor opens on what is actually
                // stored rather than on whatever was in hand when the row was
                // tapped. A brand-new motion is not stored yet — see
                // `unwritten` — so it stands in until the editor's first change
                // lands in the store, after which the store's copy is the newer
                // one and wins. Order matters for that reason.
                if let current = drafts.drafts.first(where: { $0.id == wrapper.id })
                                 ?? standIn(for: wrapper.id) {
                    IntentAuthorView(
                        draft: current, scenes: store, models: models,
                        isNew: wrapper.isNew,
                        onSave: { drafts.save($0) },
                        // ORDER MATTERS. This lookup has no `else`, so if the
                        // draft leaves the store while `editing` is still set,
                        // the sheet presents an empty NavigationStack — no
                        // title, no Cancel, no Done. That is a real permanent
                        // trap, manufactured while fixing one. Clear the
                        // binding first; the store only changes afterwards.
                        //
                        // Deleting a motion that was never written into is a
                        // no-op on both halves of `DraftStore.delete` — no such
                        // row, no such file — so Cancel on an untouched new one
                        // still does exactly what it says, and says it once.
                        onDiscard: { doomed in
                            editing = nil
                            drafts.delete(doomed)
                        })
                        // Leaving the editor is the moment the file is
                        // definitely current, whether they tapped Done or
                        // swiped the sheet away.
                        .onDisappear { drafts.flush() }
                } else {
                    // THE `else` THIS FILE'S OWN COMMENT ASKED FOR, AND IT IS
                    // HERE BECAUSE THE TRAP IT DESCRIBES WAS REPORTED FROM A
                    // DEVICE. The comment eight lines up has said for two
                    // versions that a failed lookup "presents an empty
                    // NavigationStack — no title, no Cancel, no Done… a real
                    // permanent trap", and then left the `if let` without an
                    // else, so the trap stayed one tap away the whole time.
                    //
                    // A sheet a person cannot leave is the worst state this app
                    // can reach: every other refusal here still has a way out.
                    // So whatever went wrong upstream — a draft deleted while
                    // its editor was opening, a stand-in cleared by a trailing
                    // onDismiss — it ends in a sentence and a button rather
                    // than a blank rectangle.
                    ContentUnavailableView {
                        Label("That motion is not here", systemImage: "questionmark.square.dashed")
                    } description: {
                        Text("It was being opened and is no longer in your drafts. Nothing has been lost that was saved — a motion you had already written into is in the list behind this. If this keeps happening, it is a bug in this build and not something you did.")
                    } actions: {
                        Button("Close") { editing = nil }
                            .buttonStyle(.primaryAction)
                    }
                }
            }
        }
    }

    // MARK: - the sections

    /// The person's own motions, the door to a new one, and the door to a plan.
    ///
    /// ONE CARD ACROSS THREE KINDS OF ROW, which is what the `first`/`last`
    /// bookkeeping is for: the drafts, the "write" button and the "fetch" link
    /// are one run of rows in one rounded surface, so the corners are drawn at
    /// the two ends of the run and nowhere in between.
    @ViewBuilder private var writtenHere: some View {
        Section {
            ForEach(Array(drafts.drafts.enumerated()), id: \.element.id) { index, draft in
                Button { editing = DraftID(id: draft.id) } label: { draftRow(draft) }
                    .buttonStyle(.plain)
                    .cardRow(first: index == 0, last: false)
            }
            .onDelete { offsets in
                for index in offsets { drafts.delete(drafts.drafts[index]) }
            }
            Button {
                // NOT SAVED HERE, AND THAT IS THE WHOLE FIX. This line used
                // to be `drafts.save(fresh)`, because the sheet looks a
                // draft up by id and cannot present one the store has never
                // heard of. The cost was that the row — and, 0.4 s later,
                // the file — existed before the person had written a single
                // thing into it, so every way OUT of the editor then needed
                // its own agreement to un-create it. Cancel got one
                // (`IntentAuthorView.discard()`), the confirmation dialog
                // got one (`reallyDiscard()`), and the fourth exit — a
                // swipe down, which is the one most people reach for — got
                // nothing, ran neither, and left a motion called "New
                // motion" that its owner never asked for and could not
                // explain. Twice fixed, twice by adding a guard to one more
                // exit.
                //
                // A FOURTH GUARD WOULD HAVE BEEN THE THIRD PATCH ON THE
                // SAME DANCE, and it could not have worked anyway: from out
                // here Done and a swipe are the same event — both just set
                // `editing` to nil — so no rule applied on dismissal can
                // keep one and throw away the other. Whatever such a rule
                // did to the swipe, it would also do to Done, and a Done
                // that quietly produces nothing is worse than a leftover
                // row.
                //
                // So the state that needed guarding is gone instead. A
                // blank motion is a motion nobody has written; it waits in
                // `unwritten` and becomes a row and a file at the moment
                // the editor's first change is saved. All four exits now
                // do the same thing to an untouched one — nothing — and
                // they cannot drift apart again, because none of them has
                // anything left to do.
                let fresh = IntentDraft.blank()
                unwritten = fresh
                editing = DraftID(id: fresh.id, isNew: true)
            } label: {
                Label("Write a new motion", systemImage: "plus")
            }
            // THE ACTION COLOUR THAT CAN SET A WORD, WHICH IS NOT THE ONE THE
            // APP IS TINTED IN. A `Button` in a list paints its label from the
            // tint, and the app's tint is Duck Orange — 2.30:1 on Warm Cream,
            // which is unreadable as text and is exactly why `Palette` carries
            // an ink for it. `actionSecondary` is that ink in light (4.52:1)
            // and stays Duck Orange in dark, where the brand value clears
            // 6.76:1 on the dark ground on its own. The rule the palette states
            // is the whole of it: a brand colour fills a shape, an ink colour
            // sets a word, and this is a word.
            //
            // `.tint` RATHER THAN `.foregroundStyle`, because the automatic
            // button style reads the tint explicitly and an inherited
            // foreground style never reaches the label.
            .tint(Theme.actionSecondary)
            .cardRow(first: drafts.drafts.isEmpty, last: false)
            NavigationLink {
                RetrieveView(plans: plans)
            } label: {
                Label("Fetch something", systemImage: "arrow.down.to.line")
            }
            .foregroundStyle(Theme.textPrimary)
            .cardRow(first: false, last: true)
        } header: {
            SectionHeading(text: "Written here")
        } footer: {
            sectionFootnote("Poses and times, interpolated. A phone has no physics engine, so this is what you asked the robot for — not what it would do. Every authored move already in this app was written the same way, and all four stair ones get up their flight 0 times in 16.\n\nFetch something is different: it writes no poses at all. Retrieval composes policies the robot already has — walk, ground pick, and the one servo no network drives — so a sentence there becomes a plan, not a keyframe track.")
        }
    }

    @ViewBuilder private var savedPlans: some View {
        Section {
            ForEach(Array(plans.plans.enumerated()), id: \.element.name) { index, plan in
                NavigationLink {
                    RetrieveView(plans: plans, opening: plan)
                } label: {
                    VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                        Text(plan.name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(planSummary(plan))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .cardRow(first: index == 0, last: index == plans.plans.count - 1)
            }
            .onDelete { indexes in
                indexes.map { plans.plans[$0] }.forEach(plans.delete)
            }
        } header: {
            SectionHeading(text: "Plans")
        } footer: {
            sectionFootnote("A fetch, kept on this phone in this app's own format. The steps are "
                          + "worked out again each time it is opened, against the measurements "
                          + "this app holds — so a plan cannot go stale and argue with the app "
                          + "that opened it.")
        }
    }

    @ViewBuilder private var simToReal: some View {
        Section {
            ForEach(Array(drafts.drafts.enumerated()), id: \.element.id) { index, draft in
                NavigationLink {
                    PipelineView(draftID: draft.id, drafts: drafts, scenes: store,
                                 models: models, benches: benches)
                } label: {
                    let pipeline = Pipeline.of(draft, bench: draft.bench)
                    VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                        Text(draft.name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                        ProgressView(value: pipeline.fractionDone)
                            // TEAL RATHER THAN THE APP'S ORANGE TINT, FOR TWO
                            // REASONS THAT AGREE. The first is measured: Duck
                            // Orange is 2.30:1 on Warm Cream, below even the
                            // 3:1 SC 1.4.11 asks of a control's boundary, and a
                            // native `ProgressView` has nowhere to hang the
                            // hairline rim `BillIndicator` and the action
                            // capsule use to fix that. The second is what the
                            // bar means: how far a motion has come through sim
                            // to real is something this app WORKED OUT from
                            // what has actually happened to the draft, and teal
                            // is what a machine measured. Orange is the colour
                            // of the thing you press, and nobody presses this.
                            .tint(Theme.brandPrimary)
                            // A BARE BAR ANNOUNCES A PERCENTAGE AND
                            // NOTHING ELSE — "sixty percent" of what is
                            // the whole question.
                            //
                            // THE LABEL NAMES WHAT THE BAR MEASURES,
                            // NOT WHAT COMES NEXT. Labelling it with
                            // `pipeline.next` made the two halves answer
                            // different questions: the value is how far
                            // this motion has come, and `next` is the
                            // first stage it has NOT reached, so a bar
                            // reading sixty percent announced itself as
                            // the name of the thing that has not
                            // happened. What is still to come belongs in
                            // the value, where it reads as a position.
                            .accessibilityLabel(Text("Sim to real"))
                            .accessibilityValue(Text(pipeline.next.map {
                                "next: \($0.name)" } ?? "every stage done"))
                        Text(draft.bench.map { "Run in physics: \($0.summary)" }
                             ?? "Never run in physics.")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .cardRow(first: index == 0, last: index == drafts.drafts.count - 1)
            }
        } header: {
            SectionHeading(text: "Sim to real")
        } footer: {
            sectionFootnote("What has actually happened to each motion. A preview on this phone is NOT a run — an iPhone has no physics engine, so what it draws is what you asked for. Point the app at a bench and this becomes a real result the draft keeps.")
        }
    }

    // MARK: - where a motion came from

    /// Whose motion this is — which is a different question from which section
    /// it happens to be filed under today.
    ///
    /// THE PILL TRAVELS AND THE HEADING DOES NOT. A heading is true of a run of
    /// rows until you scroll past it; a clip's provenance is true of the clip,
    /// and this is the one screen in the app where a clip changes hands. A
    /// recording shared out of "From Pollen's policies" arrives on somebody
    /// else's phone under "Brought in", and the pill is what carries the answer
    /// across that move. It is also the only thing that can disambiguate
    /// "Brought in", which is genuinely mixed: a stranger's contribution and a
    /// recording off your own bench land in the same array.
    ///
    /// The colours are the app's provenance claim and nothing else — teal for
    /// what Pollen's network produced, yellow for what a person WROTE, lavender
    /// for somebody else's training, grey for a file that came off this
    /// person's own bench. Lavender is the palette's least-used hue on its
    /// least-frequent claim, which is what the design system asks of it. Every
    /// one of them clears 4.5:1 on the card it sits on, because each sets a
    /// word rather than filling a shape.
    private enum Provenance {
        case pollen
        case authored
        case community
        case yours

        var title: String {
            switch self {
            case .pollen: return "Pollen Robotics"
            case .authored: return "Authored"
            case .community: return "Community"
            case .yours: return "Yours"
            }
        }

        var colour: Color {
            switch self {
            case .pollen: return Theme.measured
            case .authored: return Theme.asked
            case .community: return Theme.training
            case .yours: return Theme.textSecondary
            }
        }
    }

    /// What the clip itself can say, and the section's answer for what it
    /// cannot.
    ///
    /// THE KIT DECIDES WHETHER A CREDIT IS YOURS, NOT THIS VIEW.
    /// `DuckBench.wasRecordedHere` is the one place that knows the prefix this
    /// app writes onto a recording made on your own bench, and reproducing that
    /// test here is exactly the kind of second opinion the app is built to
    /// avoid. A clip with no credit and no authorship has nothing to say about
    /// itself, and then — and only then — the section it is filed under
    /// answers: bundled motions are Pollen's, imported ones are yours.
    private func provenance(of clip: DuckIntentClip, in section: Provenance) -> Provenance {
        if let credit = clip.credit {
            return DuckBench.wasRecordedHere(credit) ? .yours : .community
        }
        if clip.authored { return .authored }
        return section
    }

    private func provenancePill(_ whose: Provenance) -> some View {
        Text(whose.title)
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

    // MARK: - the rows

    /// Every clip in one section, each knowing whether it is an end of the
    /// card, and each carrying its own provenance rather than the section's.
    private func clipRows(_ list: [DuckIntentClip],
                          whose section: Provenance,
                          onDelete: ((IndexSet) -> Void)? = nil) -> some View {
        ForEach(Array(list.enumerated()), id: \.element.name) { index, clip in
            row(clip, whose: section)
                .cardRow(first: index == 0, last: index == list.count - 1)
        }
        .onDelete(perform: onDelete)
    }

    private func row(_ clip: DuckIntentClip, whose section: Provenance) -> some View {
        NavigationLink {
            IntentPlayerView(clip: clip, store: store, drafts: drafts, models: models)
        } label: {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                // WHAT IT IS AND WHOSE IT IS, ON ONE LINE. The pill sits beside
                // the name it qualifies, the way the Behaviours tab draws the
                // same claim, and the measured numbers move down to the second
                // line with the other measured numbers.
                HStack(spacing: Theme.spacing(.tight)) {
                    Text(clip.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    if clip.environment.hasProps {
                        Image(systemName: "square.3.layers.3d")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                            // The screen this row opens says WHICH props, and
                            // offers to hide them; the row only says there were
                            // some — in the same words that screen's toggle
                            // uses, "recorded against".
                            .accessibilityLabel(Text("Recorded against props"))
                    }
                    Spacer(minLength: Theme.spacing(.tight))
                    provenancePill(provenance(of: clip, in: section))
                }
                // The measured start and end posture. It is the single most
                // useful line in the row: step_up reads "standing → toppled",
                // which is the move failing, stated plainly.
                HStack(spacing: Theme.spacing(.hairline)) {
                    // THE ARROW IS THE VERB, AND AN ARROW IS NOT A WORD.
                    // "standing, toppled" read out in a row is two postures
                    // with no idea which is which; the two words that fix it
                    // are the ones the detail screen already labels these
                    // exact fields with. The postures themselves stay the
                    // kit's — this view names the field, never the finding.
                    Text(clip.startsFrom.rawValue)
                        .accessibilityLabel(Text("Starts \(clip.startsFrom.rawValue)"))
                    Image(systemName: "arrow.right").font(.caption2)
                        .accessibilityHidden(true)
                    Text(clip.endsIn.rawValue)
                        .foregroundStyle(worrying(clip.endsIn) ? Theme.warning
                                                              : Theme.textSecondary)
                        .accessibilityLabel(Text("Ends \(clip.endsIn.rawValue)"))
                    if let outcome = odds?[clip.name] {
                        Text("·").accessibilityHidden(true)
                        // THE WORD IS SF AND THE FIGURE IS MONO, WHICH IS THE
                        // WHOLE OF THE TYPOGRAPHIC RULE APPLIED TO FOUR
                        // CHARACTERS. "works" is the same on every row; the
                        // fraction is the number somebody is scanning this list
                        // for, it varies row to row, and tabular figures are
                        // what let 0/16 and 12/16 line up down the column
                        // instead of drifting. If it never changes, it is not
                        // telemetry — so only half of this is set as if it
                        // were.
                        (Text("works ")
                            + Text("\(outcome.achieves)/\(outcome.rollouts)")
                                .font(.caption.monospaced().monospacedDigit()))
                            .foregroundStyle(outcome.achieves == 0 ? Theme.warning
                                                                   : Theme.textSecondary)
                    }
                    Spacer(minLength: Theme.spacing(.tight))
                    Text(String(format: "%.1fs", clip.duration))
                        .font(.caption.monospaced().monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func draftRow(_ draft: IntentDraft) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack(spacing: Theme.spacing(.tight)) {
                Text(draft.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                if !draft.isPlayable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        // THE REFUSAL COLOUR, NOT THE WARNING ONE, AND THE TWO
                        // ARE KEPT APART ON THIS SCREEN ON PURPOSE. A motion
                        // that ends toppled, or that achieves its goal none of
                        // sixteen times, is a measured disappointment and takes
                        // `warning`. This is different in kind: the app has
                        // checked the motion and will not play it. `refused` is
                        // the token the palette gives that — "a refusal, or a
                        // limit being approached" — and using it here keeps the
                        // strongest colour in the app for the one thing on the
                        // row that is not going to happen at all.
                        .foregroundStyle(Theme.refused)
                        // WHY it will not play, in the checker's own words.
                        // `isPlayable` is false exactly when a broken problem
                        // exists, so this reads the first of them rather than
                        // announcing a triangle — and rather than this view
                        // writing a second, vaguer sentence about a motion it
                        // did not check.
                        .accessibilityLabel(Text(
                            draft.problems.first { $0.severity == .broken }?.text ?? ""))
                }
                Spacer(minLength: Theme.spacing(.tight))
                Text(String(format: "%.1fs", draft.duration))
                    .font(.caption.monospaced().monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            // PROSE, AND SO NOT SET AS TELEMETRY. The keyframe count varies from
            // row to row like the duration does, but it is a clause in a
            // sentence with a middot in it rather than a readout in a column,
            // and monospacing one word of a sentence is how a list starts to
            // look like a log file.
            Text("\(draft.keys.count) keyframes · no physics")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .contentShape(Rectangle())
    }

    /// Ending on the floor is worth colouring. Not an error — a roll passes
    /// through it deliberately — but it is what someone scanning the list is
    /// looking for.
    private func worrying(_ posture: DuckIntentClip.Posture) -> Bool {
        posture == .fallen || posture == .toppled
    }
}

/// One recording, played.
struct IntentPlayerView: View {
    let clip: DuckIntentClip
    /// Scenes this phone holds, so a motion can be played somewhere other than
    /// where it was recorded.
    ///
    /// OBSERVED, AND NOT OPTIONAL. The old comment said "optional because the
    /// bench opens this view too" and that was simply false — `grep` finds no
    /// `IntentPlayerView(` in BenchView, and all five construction sites pass a
    /// real store. Meanwhile the optionality had already cost this file one
    /// documented bug, where a nil store quietly gave the remix editor a
    /// different set of scenes from the rest of the app. Without the wrapper
    /// the id resolution below is correct but its redraw is unspecified.
    @ObservedObject var store: SceneStore
    var drafts: DraftStore?
    /// Passed through to the editor a remix opens, so a tweak asked for there
    /// reaches the same model as everywhere else.
    ///
    /// IT WAS OPTIONAL AND DEFAULTED, "so none of the four screens that present
    /// this player has to change to gain a feature they do not use" — and three
    /// of the four then took the default. A remix opened from a policy's
    /// recordings, from a rule's "Watch what it would play", or from a remote
    /// run got an editor whose Ask panel was dead, telling the user to choose a
    /// model on a screen with no model picker in its view tree. A default that
    /// silently removes a feature is a default that will be taken; all four
    /// screens pass the one store the app owns, and a fifth cannot compile
    /// without doing the same.
    @ObservedObject var models: EndpointStore

    @State private var remixed: DraftID?
    @State private var playhead: TimeInterval = 0
    @State private var isRunning = true
    @State private var orbit = OrbitState()
    @State private var showProps = true
    /// The scene this clip is being replayed in, BY IDENTITY. Holding the
    /// `DuckScene` value froze it: rename or move a prop while this was set and
    /// the banner went on naming the old name and the stage went on drawing the
    /// old props, silently. See the same note in `BenchView`.
    @State private var elsewhereID: UUID?

    private var elsewhere: DuckScene? {
        guard let elsewhereID else { return nil }
        return store.scenes.first { $0.id == elsewhereID }
    }
    @State private var outgoing: Outgoing?
    @State private var shareFailure: String?
    @State private var panel: Panel = .story

    enum Panel: String, CaseIterable, Identifiable {
        case story = "What happened", numbers = "Numbers"
        case curves = "Over time", reward = "Reward", odds = "How often"
        var id: String { rawValue }
    }

    private var pose: DuckIntentClip.Pose { clip.pose(at: playhead) }

    /// What the robot is standing in. The recording's own world unless somebody
    /// has deliberately moved the motion somewhere else — and when they have,
    /// the screen says so, because a clip replayed against a different
    /// staircase is no longer evidence about the one it was recorded on.
    private var world: DuckIntentClip.Environment {
        if let elsewhere { return elsewhere.environment }
        return showProps ? clip.environment : .bareFloor
    }

    /// Computed once. The first version recomputed this — including a JSON
    /// decode of the success corpus — on every body evaluation, which with the
    /// playhead advancing at 50 Hz meant fifty decodes a second while the
    /// Numbers tab was open.
    @State private var cachedMetrics: RunMetrics?
    @State private var cachedSeries: RunSeries?

    private var metrics: RunMetrics {
        if let cachedMetrics { return cachedMetrics }
        return RunMetrics(clip: clip, success: try? DuckIntentSuccess.bundled())
    }

    /// Package the motion, draft what to say about it, and offer somewhere to
    /// send it. The message carries how often the motion actually works — a
    /// clip measured at 0 of 16 is a useful negative result, and sending it
    /// without that number is not.
    private func share() {
        let export = IntentExport(clip: clip, policyFingerprint: nil)
        do {
            let data = try export.encoded()
            let url = try ExportFile.write(data, named: export.suggestedFilename)
            outgoing = Outgoing(
                url: url,
                message: CommunityShare.message(
                    forIntent: export,
                    outcome: (try? DuckIntentSuccess.bundled())?[clip.name]))
        } catch let error as ExportFile.Failure {
            shareFailure = error.message
        } catch {
            shareFailure = "\(error)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                // A SCENE'S PROPS COME ALONGSIDE ITS ENVIRONMENT, never inside
                // it: `DuckIntentClip.Environment` is the recorded world and a
                // Studio prop is not part of one. Empty when the clip is
                // playing where it was recorded, which is the honest answer —
                // a recording carries no Studio props.
                DuckStage(pose: .at(pose), variant: clip.variant,
                          environment: world,
                          props: elsewhere?.props ?? [],
                          trail: clip.roots,
                          progress: playhead / max(clip.duration, 1e-9),
                          orbit: $orbit)
                StageLegend(pose: .at(pose),
                            environment: world, props: elsewhere?.props ?? [],
                            orbit: $orbit)
            }
            .frame(maxHeight: 340)

            TransportBar(duration: clip.duration, playhead: $playhead, isRunning: $isRunning)
                .padding(.horizontal, Theme.spacing(.standard))
                .padding(.vertical, Theme.spacing(.tight))

            Picker("Panel", selection: $panel) {
                ForEach(Panel.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.spacing(.standard))
            .padding(.bottom, Theme.spacing(.tight))

            List {
                if let elsewhere {
                    Section {
                        Label("Playing in \(elsewhere.name), not where it was recorded.",
                              systemImage: "arrow.triangle.branch")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                        Button("Back to the recorded world") { elsewhereID = nil }
                            .tint(Theme.actionSecondary)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                } else if elsewhereID != nil {
                    // DELETED WHILE IT WAS BEING PLAYED IN. The banner above is
                    // gated on resolving the scene, so without this branch the
                    // whole notice disappeared along with the scene and the
                    // motion quietly went back to its recorded world with
                    // nothing said. Note the fallback is NOT a bare floor here,
                    // which is why the sentence is per-use.
                    Section {
                        Label(StageCaption.sceneDeleted(.playedIn),
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                        Button("Fine, keep the recorded world") { elsewhereID = nil }
                            .tint(Theme.actionSecondary)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                switch panel {
                case .numbers:  numbers
                case .curves:   curves
                case .reward:   reward
                case .odds:     odds
                case .story:    story
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
        }
        // The page ground behind the stage, the transport and the panel picker.
        // The list paints its own recessed ground over the rest.
        .background(Theme.backgroundPrimary)
        .navigationTitle(clip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { share() } label: {
                        Label("Share this motion", systemImage: "square.and.arrow.up")
                    }
                    if !store.scenes.isEmpty {
                        Menu("Play somewhere else") {
                            ForEach(store.scenes) { scene in
                                Button(scene.name) { elsewhereID = scene.id; playhead = 0 }
                            }
                        }
                    }
                    if let drafts {
                        Button {
                            // A REMIX KEEPS THE SHAPES AND LOSES THE PHYSICS.
                            // Eight smoothstepped keyframes are not a recording
                            // at fifty hertz, and the draft's provenance line
                            // says so — a remix of a clip that works is not a
                            // motion that works.
                            //
                            // SAVED IMMEDIATELY, UNLIKE "Write a new motion",
                            // which now waits for its first edit. The two are
                            // not the same thing: a blank motion holds nothing
                            // anybody wrote, so an untouched one is worth
                            // nothing and is never created; a remix holds this
                            // clip's poses and carries its name into the list,
                            // so an untouched one is a real starting point and
                            // an explicable row. Deferring it would mean
                            // remixing a clip, tapping Done, and getting no
                            // motion — a menu item that did nothing, which is
                            // the failure this app minds most.
                            let draft = IntentDraft.remix(clip)
                            drafts.save(draft)
                            remixed = DraftID(id: draft.id, isNew: true)
                        } label: {
                            Label("Remix into a new motion", systemImage: "wand.and.stars")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        // Share, play it somewhere else, remix it — three
                        // things that exist only behind this one icon.
                        .accessibilityLabel(Text("More"))
                }
            }
        }
        .sheet(item: $outgoing) { out in
            NavigationStack {
                ShareDestinationsView(title: clip.name, file: out.url, message: out.message)
            }
        }
        .alert("Could not share", isPresented: Binding(
            get: { shareFailure != nil }, set: { if !$0 { shareFailure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(shareFailure ?? "") }
        .sheet(item: $remixed) { wrapper in
            NavigationStack {
                // `store` and `drafts` are both required to get here — the menu
                // item that sets `remixed` only exists when they are present —
                // so this asks for them rather than manufacturing a throwaway
                // SceneStore on every render, which is what the first version
                // did and which quietly gave the remix editor a different set
                // of scenes from the rest of the app.
                if let drafts,
                   let current = drafts.drafts.first(where: { $0.id == wrapper.id }) {
                    IntentAuthorView(
                        draft: current, scenes: store, models: models,
                        isNew: wrapper.isNew,
                        onSave: { drafts.save($0) },
                        onDiscard: { doomed in
                            remixed = nil
                            drafts.delete(doomed)
                        })
                        .onDisappear { drafts.flush() }
                }
            }
        }
        .onAppear {
            if cachedMetrics == nil {
                cachedMetrics = RunMetrics(clip: clip, success: try? DuckIntentSuccess.bundled())
                cachedSeries = RunSeries(clip: clip)
            }
        }
        .onReceive(Timer.publish(every: 1.0 / DuckModel.tickHz, on: .main, in: .common).autoconnect()) { _ in
            guard isRunning else { return }
            playhead += 1.0 / DuckModel.tickHz
            // `hold` LOOPS AND HAS NO END, so `hasFinished` is never true for
            // it and the old `!clip.loops` guard excluded it from the only
            // reset. Its playhead grew without bound: after a minute the
            // transport read 60.00 s against a two-second slider. `pose(at:)`
            // wraps correctly forever, so this was cosmetic — and the readout
            // is the thing anybody scrubbing is looking at.
            if clip.loops {
                playhead = playhead.truncatingRemainder(dividingBy: max(clip.duration, 1e-9))
            } else if pose.hasFinished {
                playhead = 0
            }
        }
    }

    // MARK: - what happened

    @ViewBuilder private var story: some View {
        Section {
            posture("Starts", clip.startsFrom.rawValue)
            posture("Ends", clip.endsIn.rawValue)
            // A NUMBER THAT CHANGES, IN THE COMPONENT THE APP ALREADY HAS FOR
            // ONE. `TelemetryRow` is a label that does not change beside a
            // value that does, in tabular figures, reflowing to stacked at
            // accessibility sizes instead of letting the value be truncated off
            // the right-hand edge — which is exactly what these two rows are.
            // Drawing a lookalike here is the drift `DesignComponents` exists
            // to prevent.
            TelemetryRow(label: "Turns",
                         value: String(format: "%+.2f", clip.netYaw),
                         unit: "rad")
            TelemetryRow(label: "Length",
                         value: String(format: "%.1f s · %d ticks",
                                       clip.duration, clip.frames.count))
        } header: {
            SectionHeading(text: "What happened")
        }
        .listRowBackground(Theme.surfacePrimary)

        Section {
            posture("Policy", clip.policy)
            if clip.authored {
                Text("A keyframe track riding on that policy as offsets, not the policy's own output. It was searched against a prop, and searching found what worked in that one situation — not a motion that generalises.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            if let note = ClipNote.provenance(for: clip) {
                Text(note).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            if ClipNote.needsPlantCaveat(clip) {
                Text(ClipNote.plantCaveat)
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        } header: {
            SectionHeading(text: "Recorded from")
        }
        .listRowBackground(Theme.surfacePrimary)

        Section {
            Button { share() } label: {
                Label("Share this motion", systemImage: "square.and.arrow.up")
            }
            .tint(Theme.actionSecondary)
        } footer: {
            sectionFootnote("Sends a .duckintent file — the frames, the postures, and the digest of the policy it was recorded from. The digest lets whoever receives it check they hold the same network; it does not say who made the motion, because a signature nobody can anchor would not tell them that either.")
        }
        .listRowBackground(Theme.surfacePrimary)

        if clip.environment.hasProps {
            Section {
                Toggle("Show what it was recorded against", isOn: $showProps)
                    .foregroundStyle(Theme.textPrimary)
            } footer: {
                sectionFootnote("Hiding the props is how you see the motion alone; showing them is how you see whether it worked. \(clip.name) was performed against \(clip.environment.steps.isEmpty ? "a wall" : "a four-step flight"), and without it on screen a duck that falls over looks like it fell over for no reason.")
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    /// A word beside a word.
    ///
    /// NOT `TelemetryRow`, BECAUSE A POSTURE IS NOT A MEASUREMENT. "standing"
    /// set in tabular figures would be the app claiming a word is a number that
    /// is about to change — the one thing the typographic rule here forbids. It
    /// keeps `TelemetryRow`'s hierarchy, though: the label is the quiet half
    /// and the value is the loud one, so a column of these and a column of
    /// those read as one table.
    private func posture(_ label: String, _ value: String) -> some View {
        LabeledContent {
            Text(value).foregroundStyle(Theme.textPrimary)
        } label: {
            Text(label).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - the numbers

    /// EVERY MEASURABLE THING ABOUT THE RUN. A three-line summary is enough to
    /// browse a list and not enough to judge a motion: "ends toppled" says a
    /// move failed and not how close it came, and the difference between a
    /// climb that stalls 4 mm short and one that never left the floor is the
    /// whole of whether it is worth another attempt.
    @ViewBuilder private var numbers: some View {
        let m = metrics
        Section {
            ForEach(m.travel) { ReadingRow(reading: $0) }
        } header: {
            SectionHeading(text: "Where it went")
        }
        .listRowBackground(Theme.surfacePrimary)

        Section {
            ForEach(m.attitude) { ReadingRow(reading: $0) }
        } header: {
            SectionHeading(text: "How it held itself")
        }
        .listRowBackground(Theme.surfacePrimary)

        Section {
            ForEach(m.joints) { ReadingRow(reading: $0) }
        } header: {
            SectionHeading(text: "What the joints did")
        }
        .listRowBackground(Theme.surfacePrimary)

        Section {
            // LIVE, AT THE PLAYHEAD. The aggregate rows below say what each
            // joint did over the whole run; these say what it is doing NOW,
            // which is the question a scrubber asks — a headspin that falls
            // backwards is diagnosed by seeing which servos are pushing, and
            // which way, at the moment it goes.
            ForEach(RunSeries.joints(of: clip, at: playhead)) { moment in
                JointMomentRow(moment: moment)
            }
        } header: {
            SectionHeading(text: String(format: "Right now — %.2f s", playhead))
        } footer: {
            sectionFootnote("Scrub the transport and these follow. The sign is the direction: positive is toward the joint's positive travel, and the achieved motion is shown, not the command — a clamped servo is doing something different from what it was told.")
        }
        .listRowBackground(Theme.surfacePrimary)

        Section {
            ForEach(m.perJoint) { JointRow(reading: $0) }
        } header: {
            SectionHeading(text: "Over the whole run")
        } footer: {
            sectionFootnote("Travel is how far the joint moved in total; deviation is how far from the home pose it got. They answer different questions — a gait travels a long way without ever going far — and the bar is the deviation against the room that joint actually has.")
        }
        .listRowBackground(Theme.surfacePrimary)

        Section {
            ForEach(m.control) { ReadingRow(reading: $0) }
        } header: {
            SectionHeading(text: "What the policy emitted")
        } footer: {
            sectionFootnote(m.telemetryMissing
                 ? "This recording stored the robot's joint angles only. The network's own output was not kept, so nothing here can be derived from it."
                 : "The network's raw output, before the gait scales it and before the travel stops clamp it.")
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - how often it works

    /// A RATE CANNOT COME FROM A RECORDING, and this panel exists because
    /// somebody will read "ends standing" and hear "works". A clip is one run;
    /// the number here comes from running the motion again, many times, with
    /// the drop height, the footpad friction, the shove and the trunk's centre
    /// of mass all varied over the ranges Pollen train against.
    @ViewBuilder private var odds: some View {
        let m = metrics
        if m.success.isEmpty {
            Section {
                sectionFootnote("Nobody has rolled this motion out. A rate needs repeated runs under varied conditions, and this clip has only ever been recorded once — which is one run, not a measurement.")
            }
            .listRowBackground(Theme.surfacePrimary)
        } else {
            Section {
                ForEach(m.success) { ReadingRow(reading: $0) }
            } header: {
                SectionHeading(text: "Measured by rolling it out again")
            } footer: {
                sectionFootnote("Two rates rather than one, because they are different questions and they come apart on exactly the motions that matter. A stair move that reliably ends upright on the floor repeats perfectly and achieves nothing.")
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }

    // MARK: - over time

    /// A summary says how far; a curve says when. Roulade is supposed to go
    /// past 90° and step_up is not, and in a table of peaks the two are
    /// indistinguishable.
    @ViewBuilder private var curves: some View {
        // Cached for the same reason as the metrics: the playhead rule moves
        // fifty times a second, and rebuilding twelve hundred points per frame
        // to draw a line that has not changed is how a chart tab stutters.
        let series = cachedSeries ?? RunSeries(clip: clip)
        Section {
            sectionFootnote("Sampled once per tick at \(Int(clip.hz)) Hz, unsmoothed. The interesting features here are the sharp ones — the instant a foot lands, the tick a joint hits its stop — and a filter would remove exactly those. The orange line is the playhead.")
        }
        .listRowBackground(Theme.surfacePrimary)
        ForEach(series.tracks) { track in
            Section { RunChart(track: track, playhead: playhead) }
                .listRowBackground(Theme.surfacePrimary)
        }
    }

    // MARK: - the reward

    @ViewBuilder private var reward: some View {
        let m = metrics
        Section {
            sectionFootnote(m.provenance)
        }
        .listRowBackground(Theme.surfacePrimary)

        if !m.rewards.isEmpty {
            Section {
                ForEach(m.rewards) { RewardRow(term: $0) }
            } header: {
                SectionHeading(text: "Scored on this recording")
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        if !m.unevaluated.isEmpty {
            Section {
                ForEach(m.unevaluated) { ReadingRow(reading: $0) }
            } header: {
                SectionHeading(text: "Terms a recording cannot answer")
            } footer: {
                sectionFootnote("These are real terms in the training config and they are not scored here, because each reads a sensor a clip does not carry. Listing them is the honest alternative to a shorter panel that looks complete.")
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        if m.rewards.isEmpty && m.unevaluated.isEmpty {
            Section {
                sectionFootnote("No reward is scored for this motion. Weights belong to a training config, and attaching the wrong one would give every number on this screen an authority it has not earned.")
            }
            .listRowBackground(Theme.surfacePrimary)
        }
    }
}

/// One measured number.
private struct ReadingRow: View {
    let reading: RunMetrics.Reading

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack {
                Text(reading.label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(reading.value)
                    .font(.subheadline.monospaced().monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            if let detail = reading.detail {
                Text(detail).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        // A name, a number and the sentence about them are one reading. Three
        // separate stops to hear one measurement is how a person loses which
        // number went with which name.
        .accessibilityElement(children: .combine)
    }
}

/// One joint at the playhead: where it is, and which way it is moving.
///
/// THREE THINGS SHARED ONE ROW'S WIDTH AND THE LAST OF THEM WAS PINNED TO 74
/// POINTS. A joint's name, its rate and its angle in one line is already the
/// arrangement `TelemetryRow` refuses to keep at accessibility sizes, and this
/// row was worse than the two-column case it was written against: at AX5 the
/// name takes the width, the rate takes what is left, and the angle — the one
/// number the section header promises ("Right now") — is squeezed into a fixed
/// column sized for the default text size and truncates inside it. So the app
/// hid the reading from the people who had most enlarged the type in order to
/// read it, which is the exact failure `TelemetryRow` is written down to avoid.
///
/// SO IT REFLOWS ON THE SAME SIGNAL, AND THE COLUMN IS A FLOOR RATHER THAN A
/// WIDTH. Stacked at `isAccessibilitySize`, each of the three gets the whole
/// width and nothing is dropped. Below that the row stays one line, and the
/// angle asks for a `@ScaledMetric` 74 as a MINIMUM: it still lines the column
/// up down the section at any one text size, and a reading that outgrows it
/// pushes the column wider instead of losing digits. Tabular figures are what
/// make the alignment hold — every digit is the same width, so only the number
/// of characters can vary.
private struct JointMomentRow: View {
    let moment: RunSeries.JointMoment

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The angle column's floor. Seventy-four points is what the widest reading
    /// this format can produce measures at the default text size — a sign, two
    /// digits, a point, two more and the unit — and `@ScaledMetric` is what
    /// keeps that true at the other sizes rather than only at the one it was
    /// measured on. A bare 74 is a column that fits at Large and clips at xxL.
    @ScaledMetric(relativeTo: .caption) private var angleColumn: CGFloat = 74

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    name
                    rate
                    angle
                }
            } else {
                HStack(spacing: Theme.spacing(.tight)) {
                    name
                    Spacer(minLength: Theme.spacing(.tight))
                    rate
                    angle
                        .frame(minWidth: angleColumn, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One joint at one instant is one thing to hear: which joint, how fast,
        // and where it is.
        .accessibilityElement(children: .combine)
    }

    private var name: some View {
        Text(moment.name)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// How fast, and which way.
    ///
    /// THE ARROW AND ITS NUMBER ARE ONE THING, so they travel together into
    /// either layout and sit a hairline apart rather than at the row's own
    /// spacing — a glyph that is the sign of the number beside it has to read as
    /// attached to it, and at an accessibility size a stack that split them
    /// across two lines would leave a lone arrow meaning nothing.
    @ViewBuilder private var rate: some View {
        if moment.isMoving {
            HStack(spacing: Theme.spacing(.hairline)) {
                // THE ARROW CARRIES THE DIRECTION AND THE COLOUR NO LONGER
                // TRIES TO. This drew a positive rate in the accent colour and
                // a negative one in orange, which is a hue standing in for a
                // sign — and in an app where a hue is a claim about provenance,
                // that claim is false: both directions are the same
                // measurement, off the same recording, and colouring one of
                // them says the two came from different places. Two glyphs that
                // point opposite ways are the stronger cue anyway, they survive
                // every form of colour blindness (SC 1.4.1), and the signed
                // number is printed immediately beside them.
                Image(systemName: moment.velocity > 0
                      ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    // SILENT ON PURPOSE. The arrow is the sign of the number
                    // printed immediately beside it, drawn again for a reader
                    // scanning at a glance. Spoken, it would be the same fact
                    // twice — and a paraphrase of it, since the direction has
                    // no words here that the signed value does not carry.
                    .accessibilityHidden(true)
                Text(String(format: "%+.1f rad/s", moment.velocity))
                    .font(.caption.monospaced().monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("holding")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var angle: some View {
        Text(String(format: "%+.2f rad", moment.angle))
            .font(.caption.monospaced().monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One joint's share of the work.
private struct JointRow: View {
    let reading: RunMetrics.JointReading

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack {
                Text(reading.name)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if reading.atStopFraction > 0 {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.caption2).foregroundStyle(Theme.warning)
                        // The text next to it says this in words already.
                        .accessibilityHidden(true)
                    Text("\(Int((reading.atStopFraction * 100).rounded()))% at its stop")
                        .font(.caption2).foregroundStyle(Theme.warning)
                }
                Spacer()
                Text(String(format: "%.2f rad · %.0f rad/s", reading.travel, reading.peakRate))
                    .font(.caption2.monospaced().monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // THE TRACK IS FURNITURE AND THE FILL IS THE FINDING. The
                    // track used to be the system grey at 15% opacity, which is
                    // an invented colour on an invented ground; `separator` is
                    // the token the palette already keeps for a line that is
                    // there to be seen past rather than read. The fill is teal
                    // because a deviation is something this app MEASURED, and
                    // it turns to the warning colour on the one condition worth
                    // interrupting a scan for — a joint spending part of the
                    // run against its stop, which the words beside it say too.
                    Capsule().fill(Theme.separator)
                    Capsule()
                        .fill(reading.atStopFraction > 0 ? Theme.warning : Theme.brandPrimary)
                        .frame(width: geo.size.width * CGFloat(reading.usedFraction))
                }
            }
            .frame(height: Theme.spacing(.hairline))
            Text(String(format: "furthest from home: %.2f rad at %.2f s",
                        reading.peakDeviation, reading.peakDeviationAt))
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        // Four fragments about one joint, heard as one. The bar is the
        // deviation drawn, and the deviation is already in the last line.
        .accessibilityElement(children: .combine)
    }
}

/// One of Pollen's reward terms, and what this recording could say about it.
private struct RewardRow: View {
    let term: RunMetrics.RewardTerm

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack {
                // MONO ON A NAME THAT NEVER CHANGES, WHICH IS THE ONE EXEMPTION
                // THE RULE HAS. A reward term is an identifier out of a training
                // config, not a sentence, and the app already sets the other
                // identifier it shows — a policy's digest — the same way.
                Text(term.name)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                switch term.standing {
                case .evaluated(let mean, let weighted):
                    Text(String(format: "%.3f × %+.3f = %+.3f", mean, term.weight, weighted))
                        .font(.caption.monospaced().monospacedDigit())
                        .foregroundStyle(weighted < 0 ? Theme.warning : Theme.textSecondary)
                case .missing:
                    Text("not scored").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Text(term.purpose).font(.caption).foregroundStyle(Theme.textSecondary)
            if case .missing(let why) = term.standing {
                Text("Not scored: \(why).").font(.caption).foregroundStyle(Theme.warning)
            }
        }
        // The term, its arithmetic, what it is for and why it went unscored are
        // one answer about one reward term.
        .accessibilityElement(children: .combine)
    }
}

/// Play, pause, restart, scrub.
struct TransportBar: View {
    let duration: TimeInterval
    @Binding var playhead: TimeInterval
    @Binding var isRunning: Bool

    /// The clock, written once and read twice: by the readout on the right and
    /// by the slider that speaks it. A transport that showed 1.25 s and said
    /// "forty-one percent" would be answering a different question from the one
    /// asked, and the number in seconds is the one the rest of the screen is
    /// keyed to — "Right now — 1.25 s" over the live joint rows.
    private var printedTime: String { String(format: "%.2fs", playhead) }

    var body: some View {
        HStack(spacing: Theme.spacing(.snug)) {
            Button { isRunning.toggle() } label: {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    // 44pt, the floor. These were roughly 20pt glyphs with no
                    // frame — under half the minimum, on the two controls a
                    // person taps most while watching a recording.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            // The name follows the symbol, because this one button is both
            // controls and announcing "play" while it is playing sends people
            // hunting for a pause that is under their finger.
            .accessibilityLabel(Text(isRunning ? "Pause" : "Play"))
            Button { playhead = 0; isRunning = true } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Restart"))
            Slider(value: $playhead, in: 0...max(duration, 0.01)) { editing in
                // Scrubbing pauses, or the playhead fights the thumb and the
                // duck twitches between where you dragged and where the timer
                // has got to.
                if editing { isRunning = false }
            }
            // LABELLED RATHER THAN COMBINED INTO THE BAR, for the same reason
            // as the bench's inputs: a Slider is its own element and combining
            // it away would take the .adjustable trait with it. Scrubbing by
            // swipe is how this recording gets watched without a drag gesture.
            .accessibilityLabel(Text("Scrub"))
            .accessibilityValue(Text(printedTime))
            Text(printedTime)
                .font(.caption2.monospaced().monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 46, alignment: .trailing)
                // Said by the slider, one element to the left.
                .accessibilityHidden(true)
        }
        .buttonStyle(.borderless)
        // THE TRANSPORT IS THE ACTION ON THIS SCREEN, AND IT SETS WORDS RATHER
        // THAN FILLING THEM. Play, pause and restart are glyphs on the page
        // ground, not fills, so they take the ink that clears 4.5:1 on cream
        // rather than Duck Orange, which is 2.30:1 there. In dark this IS Duck
        // Orange — the token is the same colour in both schemes on the one
        // ground where the brand value works.
        .tint(Theme.actionSecondary)
    }
}

/// A draft's identity, so a sheet can be presented on something stable.
struct DraftID: Identifiable, Hashable {
    let id: UUID
    /// Whether the editor CREATED this motion, rather than opening one that
    /// already existed.
    ///
    /// THIS NO LONGER MEANS "ALREADY IN THE STORE", AND THE HISTORY IS THE
    /// REASON THE DISTINCTION SURVIVES. A brand-new draft used to be committed
    /// before its editor appeared, purely so the sheet's lookup could resolve
    /// it — which made Cancel responsible for un-creating it, and left a row
    /// called "New motion" behind every exit that did not run Cancel. There
    /// were three such exits before the swipe was counted, and each was fixed
    /// separately. A new draft is now held in `unwritten` and becomes a row at
    /// its first change, so no exit has to clean anything up. `isNew` is still
    /// what tells the editor it is looking at something nobody has saved.
    var isNew = false
}

/// A file and the message that goes with it, made identifiable so it can drive
/// a sheet.
struct Outgoing: Identifiable {
    let url: URL
    let message: String
    var id: String { url.absoluteString }
}
