import SwiftUI
import DuckKit
import DuckEvidence
import StudioKit

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
struct IntentListView: View {
    /// Which model answers a plain-language tweak inside the editor. Threaded
    /// through rather than made here, so the Draft tab and the editor share one
    /// choice — two stores would mean picking Claude in one place and getting
    /// Apple's model in the other.
    @ObservedObject var models: EndpointStore

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

    var body: some View {
        List {
            Section {
                Text("Motions recorded in MuJoCo from the trained policies, because the policy cannot run live on a phone. Playing one shows what the robot did; it does not re-run the network.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                ForEach(drafts.drafts) { draft in
                    Button { editing = DraftID(id: draft.id) } label: { draftRow(draft) }
                        .buttonStyle(.plain)
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
                } label: { Label("Write a new motion", systemImage: "plus") }
                NavigationLink {
                    RetrieveView()
                } label: {
                    Label("Fetch something", systemImage: "arrow.down.to.line")
                }
            } header: {
                Text("Written here")
            } footer: {
                Text("Poses and times, interpolated. A phone has no physics engine, so this is what you asked the robot for — not what it would do. Every authored move already in this app was written the same way, and all four stair ones get up their flight 0 times in 16.\n\nFetch something is different: it writes no poses at all. Retrieval composes policies the robot already has — walk, ground pick, and the one servo no network drives — so a sentence there becomes a plan, not a keyframe track.")
            }

            if !drafts.drafts.isEmpty {
                Section {
                    ForEach(drafts.drafts) { draft in
                        NavigationLink {
                            PipelineView(draftID: draft.id, drafts: drafts, scenes: store,
                                         models: models)
                        } label: {
                            let pipeline = Pipeline.of(draft, bench: draft.bench)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(draft.name).font(.subheadline)
                                ProgressView(value: pipeline.fractionDone)
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
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                } header: {
                    Text("Sim to real")
                } footer: {
                    Text("What has actually happened to each motion. A preview on this phone is NOT a run — an iPhone has no physics engine, so what it draws is what you asked for. Point the app at a bench and this becomes a real result the draft keeps.")
                }
            }

            // WHERE THE IMPORTER SAYS WHAT HAPPENED. `model.lastImport` was
            // drawn on the Policies tab and nowhere else, so a `.duckmove`, a
            // `.duck` or an unrecognised file picked from THIS screen's own
            // import button was refused into a void: the sheet closed, the list
            // did not change, and the sentence explaining why was on a tab the
            // person was not looking at.
            if let message = model.lastImport {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            if !fromPollen.isEmpty {
                Section {
                    ForEach(fromPollen, id: \.name) { row($0) }
                } header: {
                    Text("From Pollen's policies")
                } footer: {
                    Text("The policy's own output, driven in physics and recorded.")
                }
            }
            if !authored.isEmpty {
                Section {
                    ForEach(authored, id: \.name) { row($0) }
                } header: {
                    Text("Authored moves")
                } footer: {
                    Text("A keyframe track riding on a standing policy as offsets — searched against a prop rather than trained. These are the ones most likely to fail, and the posture each ends in says whether it did.")
                }
            }
            if !model.importedClips.isEmpty {
                Section {
                    ForEach(model.importedClips, id: \.name) { row($0) }
                } header: {
                    Text("Sent to you")
                } footer: {
                    Text("Motions imported from a .duckintent file. Each names the policy it was recorded from by digest, so you can check whether you hold the same network.")
                }
            }
            if !shared.isEmpty {
                Section {
                    ForEach(shared, id: \.name) { row($0) }
                } header: {
                    Text("Shared by other owners")
                } footer: {
                    Text("Recorded the same way, from a policy this app did not ship.")
                }
            }
        }
        .navigationTitle("Intents")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { picking = true } label: { Image(systemName: "square.and.arrow.down") }
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
            // AirDropped end up in the same place having had the same checks.
            switch result {
            case .success(let urls):
                if let url = urls.first { model.open(url, into: drafts) }
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
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func row(_ clip: DuckIntentClip) -> some View {
        NavigationLink {
            IntentPlayerView(clip: clip, store: store, drafts: drafts, models: models)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(clip.name).font(.subheadline.weight(.medium))
                    if clip.environment.hasProps {
                        Image(systemName: "square.3.layers.3d")
                            .font(.caption2).foregroundStyle(.secondary)
                            // The screen this row opens says WHICH props, and
                            // offers to hide them; the row only says there were
                            // some — in the same words that screen's toggle
                            // uses, "recorded against".
                            .accessibilityLabel(Text("Recorded against props"))
                    }
                    Spacer()
                    Text(String(format: "%.1fs", clip.duration))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                // The measured start and end posture. It is the single most
                // useful line in the row: step_up reads "standing → toppled",
                // which is the move failing, stated plainly.
                HStack(spacing: 4) {
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
                        .foregroundStyle(worrying(clip.endsIn) ? .orange : .secondary)
                        .accessibilityLabel(Text("Ends \(clip.endsIn.rawValue)"))
                    if let outcome = odds?[clip.name] {
                        Text("·").accessibilityHidden(true)
                        // The measured rate, not the posture. `climb` ends
                        // standing every time and gets up the flight none of
                        // them, and the posture alone cannot say that.
                        Text("works \(outcome.achieves)/\(outcome.rollouts)")
                            .foregroundStyle(outcome.achieves == 0 ? .orange : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func draftRow(_ draft: IntentDraft) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(draft.name).font(.subheadline.weight(.medium))
                Spacer()
                if !draft.isPlayable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                        // WHY it will not play, in the checker's own words.
                        // `isPlayable` is false exactly when a broken problem
                        // exists, so this reads the first of them rather than
                        // announcing a triangle — and rather than this view
                        // writing a second, vaguer sentence about a motion it
                        // did not check.
                        .accessibilityLabel(Text(
                            draft.problems.first { $0.severity == .broken }?.text ?? ""))
                }
                Text(String(format: "%.1fs", draft.duration))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("\(draft.keys.count) keyframes · no physics")
                .font(.caption).foregroundStyle(.secondary)
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
                .padding(.horizontal).padding(.vertical, 8)

            Picker("Panel", selection: $panel) {
                ForEach(Panel.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.bottom, 6)

            List {
                if let elsewhere {
                    Section {
                        Label("Playing in \(elsewhere.name), not where it was recorded.",
                              systemImage: "arrow.triangle.branch")
                            .font(.footnote).foregroundStyle(.orange)
                        Button("Back to the recorded world") { elsewhereID = nil }
                    }
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
                            .font(.footnote).foregroundStyle(.orange)
                        Button("Fine, keep the recorded world") { elsewhereID = nil }
                    }
                }

                switch panel {
                case .numbers:  numbers
                case .curves:   curves
                case .reward:   reward
                case .odds:     odds
                case .story:    story
                }
            }
        }
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
        Section("What happened") {
            LabeledContent("Starts", value: clip.startsFrom.rawValue)
                    LabeledContent("Ends", value: clip.endsIn.rawValue)
                    LabeledContent("Turns") {
                        Text(String(format: "%+.2f rad", clip.netYaw)).monospacedDigit()
                    }
                    LabeledContent("Length") {
                        Text(String(format: "%.1f s · %d ticks", clip.duration, clip.frames.count))
                            .monospacedDigit()
                    }
                }

                Section("Recorded from") {
                    LabeledContent("Policy", value: clip.policy)
                    if clip.authored {
                        Text("A keyframe track riding on that policy as offsets, not the policy's own output. It was searched against a prop, and searching found what worked in that one situation — not a motion that generalises.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let note = ClipNote.provenance(for: clip) {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                    if ClipNote.needsPlantCaveat(clip) {
                        Text(ClipNote.plantCaveat)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button { share() } label: {
                        Label("Share this motion", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text("Sends a .duckintent file — the frames, the postures, and the digest of the policy it was recorded from. The digest lets whoever receives it check they hold the same network; it does not say who made the motion, because a signature nobody can anchor would not tell them that either.")
                }

        if clip.environment.hasProps {
            Section {
                Toggle("Show what it was recorded against", isOn: $showProps)
            } footer: {
                Text("Hiding the props is how you see the motion alone; showing them is how you see whether it worked. \(clip.name) was performed against \(clip.environment.steps.isEmpty ? "a wall" : "a four-step flight"), and without it on screen a duck that falls over looks like it fell over for no reason.")
            }
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
        Section("Where it went") { ForEach(m.travel) { ReadingRow(reading: $0) } }
        Section("How it held itself") { ForEach(m.attitude) { ReadingRow(reading: $0) } }
        Section("What the joints did") { ForEach(m.joints) { ReadingRow(reading: $0) } }
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
            Text(String(format: "Right now — %.2f s", playhead))
        } footer: {
            Text("Scrub the transport and these follow. The sign is the direction: positive is toward the joint's positive travel, and the achieved motion is shown, not the command — a clamped servo is doing something different from what it was told.")
        }

        Section {
            ForEach(m.perJoint) { JointRow(reading: $0) }
        } header: {
            Text("Over the whole run")
        } footer: {
            Text("Travel is how far the joint moved in total; deviation is how far from the home pose it got. They answer different questions — a gait travels a long way without ever going far — and the bar is the deviation against the room that joint actually has.")
        }
        Section {
            ForEach(m.control) { ReadingRow(reading: $0) }
        } header: {
            Text("What the policy emitted")
        } footer: {
            Text(m.telemetryMissing
                 ? "This recording stored the robot's joint angles only. The network's own output was not kept, so nothing here can be derived from it."
                 : "The network's raw output, before the gait scales it and before the travel stops clamp it.")
        }
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
                Text("Nobody has rolled this motion out. A rate needs repeated runs under varied conditions, and this clip has only ever been recorded once — which is one run, not a measurement.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(m.success) { ReadingRow(reading: $0) }
            } header: {
                Text("Measured by rolling it out again")
            } footer: {
                Text("Two rates rather than one, because they are different questions and they come apart on exactly the motions that matter. A stair move that reliably ends upright on the floor repeats perfectly and achieves nothing.")
            }
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
            Text("Sampled once per tick at \(Int(clip.hz)) Hz, unsmoothed. The interesting features here are the sharp ones — the instant a foot lands, the tick a joint hits its stop — and a filter would remove exactly those. The orange line is the playhead.")
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(series.tracks) { track in
            Section { RunChart(track: track, playhead: playhead) }
        }
    }

    // MARK: - the reward

    @ViewBuilder private var reward: some View {
        let m = metrics
        Section { Text(m.provenance).font(.footnote).foregroundStyle(.secondary) }

        if !m.rewards.isEmpty {
            Section("Scored on this recording") {
                ForEach(m.rewards) { RewardRow(term: $0) }
            }
        }
        if !m.unevaluated.isEmpty {
            Section {
                ForEach(m.unevaluated) { ReadingRow(reading: $0) }
            } header: {
                Text("Terms a recording cannot answer")
            } footer: {
                Text("These are real terms in the training config and they are not scored here, because each reads a sensor a clip does not carry. Listing them is the honest alternative to a shorter panel that looks complete.")
            }
        }
        if m.rewards.isEmpty && m.unevaluated.isEmpty {
            Section {
                Text("No reward is scored for this motion. Weights belong to a training config, and attaching the wrong one would give every number on this screen an authority it has not earned.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// One measured number.
private struct ReadingRow: View {
    let reading: RunMetrics.Reading

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(reading.label).font(.subheadline)
                Spacer()
                Text(reading.value).font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let detail = reading.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        // A name, a number and the sentence about them are one reading. Three
        // separate stops to hear one measurement is how a person loses which
        // number went with which name.
        .accessibilityElement(children: .combine)
    }
}

/// One joint at the playhead: where it is, and which way it is moving.
private struct JointMomentRow: View {
    let moment: RunSeries.JointMoment

    var body: some View {
        HStack(spacing: 8) {
            Text(moment.name).font(.caption)
            Spacer()
            if moment.isMoving {
                Image(systemName: moment.velocity > 0
                      ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                    .font(.caption)
                    .foregroundStyle(moment.velocity > 0 ? Color.accentColor : Color.orange)
                    // SILENT ON PURPOSE. The arrow is the sign of the number
                    // printed immediately beside it, drawn again for a reader
                    // scanning at a glance. Spoken, it would be the same fact
                    // twice — and a paraphrase of it, since the direction has
                    // no words here that the signed value does not carry.
                    .accessibilityHidden(true)
                Text(String(format: "%+.1f rad/s", moment.velocity))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(moment.velocity > 0 ? Color.accentColor : Color.orange)
            } else {
                Text("holding").font(.caption2).foregroundStyle(.tertiary)
            }
            Text(String(format: "%+.2f rad", moment.angle))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 74, alignment: .trailing)
        }
        // One joint at one instant is one thing to hear: which joint, how fast,
        // and where it is.
        .accessibilityElement(children: .combine)
    }
}

/// One joint's share of the work.
private struct JointRow: View {
    let reading: RunMetrics.JointReading

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(reading.name).font(.caption)
                if reading.atStopFraction > 0 {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.caption2).foregroundStyle(.orange)
                        // The text next to it says this in words already.
                        .accessibilityHidden(true)
                    Text("\(Int((reading.atStopFraction * 100).rounded()))% at its stop")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Spacer()
                Text(String(format: "%.2f rad · %.0f rad/s", reading.travel, reading.peakRate))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(reading.atStopFraction > 0 ? Color.orange : Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(reading.usedFraction))
                }
            }
            .frame(height: 5)
            Text(String(format: "furthest from home: %.2f rad at %.2f s",
                        reading.peakDeviation, reading.peakDeviationAt))
                .font(.caption2).foregroundStyle(.tertiary)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(term.name).font(.subheadline.monospaced())
                Spacer()
                switch term.standing {
                case .evaluated(let mean, let weighted):
                    Text(String(format: "%.3f × %+.3f = %+.3f", mean, term.weight, weighted))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(weighted < 0 ? .orange : .secondary)
                case .missing:
                    Text("not scored").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(term.purpose).font(.caption).foregroundStyle(.secondary)
            if case .missing(let why) = term.standing {
                Text("Not scored: \(why).").font(.caption).foregroundStyle(.orange)
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
        HStack(spacing: 14) {
            Button { isRunning.toggle() } label: {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
            }
            // The name follows the symbol, because this one button is both
            // controls and announcing "play" while it is playing sends people
            // hunting for a pause that is under their finger.
            .accessibilityLabel(Text(isRunning ? "Pause" : "Play"))
            Button { playhead = 0; isRunning = true } label: {
                Image(systemName: "arrow.counterclockwise")
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
                .font(.caption2.monospacedDigit())
                .frame(width: 46, alignment: .trailing)
                // Said by the slider, one element to the left.
                .accessibilityHidden(true)
        }
        .buttonStyle(.borderless)
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
