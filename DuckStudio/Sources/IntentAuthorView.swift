import SwiftUI
import DuckKit
import StudioKit

/// Write a motion from scratch: pose the robot, mark the moment, repeat.
///
/// WHAT THIS IS NOT. It is not a recording, and the screen says so on every
/// visit. A recorded intent is a trained policy driving the robot through
/// physics with the trunk going wherever physics put it. This is a list of
/// poses and the times they happen at, interpolated. It is the same shape as
/// the authored moves already in the corpus — `step_up` and `wall_flip` are
/// exactly this — and those are also the ones measured at 0 of 16, which is the
/// most useful thing anybody can know before writing another one.
struct IntentAuthorView: View {
    @State var draft: IntentDraft
    @ObservedObject var scenes: SceneStore
    /// Which model answers "make the bow deeper".
    ///
    /// NOT OPTIONAL, AND THE COMPILER IS THE POINT. It used to be, with the
    /// player that opens this editor defaulting it to nil "so a screen that has
    /// no store still opens the editor". Three of the four screens that present
    /// that player then quietly took the default, and the Ask panel arrived
    /// dead on all three — telling the user to "choose one under Draft →
    /// Models", which is advice that cannot work from a view tree holding no
    /// model picker. A feature that can be lost by omitting an argument will
    /// be. Every caller now hands over the one store the app owns, and a new
    /// screen cannot compile without doing the same.
    @ObservedObject var models: EndpointStore
    /// True when this editor created the motion. A draft must be in the store
    /// before the sheet can look it up, so a new one exists before its editor
    /// appears — and Cancel has to be able to un-create it.
    let isNew: Bool
    let onSave: (IntentDraft) -> Void
    /// Take it out of the store. Must clear the presentation binding BEFORE
    /// touching the store, or the sheet's lookup stops resolving while it is
    /// still on screen and presents an empty, toolbar-less NavigationStack.
    let onDiscard: (IntentDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var playhead: TimeInterval = 0
    @State private var isRunning = false
    @State private var orbit = OrbitState()
    /// THE SELECTED KEYFRAME BY IDENTITY, NOT BY INDEX. `ordered` is sorted by
    /// time and the times are editable, so an index means a different keyframe
    /// the moment somebody drags one past its neighbour — and means NO keyframe
    /// at all once one is deleted, which left the Pose tab silently blank.
    @State private var selectedKey: UUID?
    /// What the draft looked like on the way in, so Cancel has something to go
    /// back to.
    @State private var original: IntentDraft?
    @State private var panel: Panel = .joints
    @State private var outgoing: Outgoing?
    @State private var failure: String?
    /// Why the last attempt to move a keyframe was turned away. The Keyframes
    /// panel had no refusal surface at all, and the only banner in the file
    /// lives inside the Ask panel — so a stepper that stopped stopped silently.
    @State private var blockedRetime: String?
    @State private var confirmingDiscard = false
    @State private var confirmingDelete = false
    @State private var publishing = false
    /// The two-ducks screen. A sheet rather than a fifth panel: the comparison
    /// needs the whole width twice over, and the editor's own stage is already
    /// using the top third.
    @State private var preferring = false

    enum Panel: String, CaseIterable, Identifiable {
        case joints = "Pose", timeline = "Keyframes", ask = "Ask", checks = "Checks"
        var id: String { rawValue }
    }

    private var ordered: [IntentDraft.Key] { draft.keys.sorted { $0.time < $1.time } }

    @State private var asked = ""
    @State private var thinking = false
    @State private var tweakNotes: [String] = []
    /// The instructions the kit could NOT apply. Kept apart from the notes
    /// because they are drawn apart: StudioKit stopped handing back one
    /// combined list precisely so this screen could not put "wing is not a
    /// joint this robot has" under a green tick, which is what it used to do.
    @State private var tweakRefusals: [String] = []
    @State private var tweakFailure: String?
    /// Where the last tweak actually put something new, or nil when it put
    /// nothing anywhere — a rename, or a keyframe removed. It decides both
    /// where the playhead goes and what the panel is allowed to claim.
    @State private var tweakMoment: TimeInterval?
    /// The motion as it was before the last tweak, so a sentence that made it
    /// worse can be taken back. ONE STEP IS ENOUGH: the alternative is an undo
    /// stack nobody asked for, and Cancel already puts back the whole session.
    @State private var beforeTweak: IntentDraft?

    /// The keyframe being edited, falling back to the first. A selection can go
    /// stale — the keyframe it named was deleted — and the right answer then is
    /// to edit something rather than to show an empty panel.
    private var editingKey: IntentDraft.Key? {
        ordered.first { $0.id == selectedKey } ?? ordered.first
    }

    private var hasUnsavedChanges: Bool {
        guard let original else { return false }
        return original != draft
    }
    private var scene: DuckScene? { scenes.scenes.first { $0.id == draft.sceneID } }

    /// What to draw. Scrubbing shows the interpolated motion; standing on a
    /// keyframe shows that keyframe exactly, which is what makes editing one
    /// feel like editing rather than like nudging an average.
    private var shown: [Double] {
        draft.pose(at: playhead)
    }

    /// Where the trunk goes so this pose stands on the floor.
    ///
    /// The rule and its caveats live in `StageFloor`; the mesh probe is the one
    /// `StageLegend` already loads once per process, so this costs nothing
    /// beyond the sampling that screen was doing anyway.
    private func restingRoot(for angles: [Double]) -> DuckIntentClip.Root {
        let pinned = StagePose.home.root
        guard let probe = StageLegend.clearance else { return pinned }
        return StageFloor.resting(pinned,
                                  clearanceMetres: probe.clearance(jointAngles: angles,
                                                                   root: pinned))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                // PROPS ARE HALF OF WHAT A SCENE IS. Passing only
                // `environment` dropped every one of them, because
                // `DuckScene.environment` is DuckKit's RECORDED-world type and
                // has no room for a Studio prop — so "Author against → Broom in
                // the corner", the one starter scene that exists for the fetch
                // and drag work, was a complete visual no-op. The scene editor
                // one tap away drew all three objects, which is how somebody
                // learns the app is inconsistent rather than that the feature
                // is missing.
                // DRAWN STANDING ON THE FLOOR, NOT HANGING AT 116 mm. A draft
                // carries joints and no root, so this stage chose the height —
                // and pinning it at standing drew `sit` with its feet 54.9 mm
                // in the air, measured against the real meshes. That looks
                // exactly like the published data being wrong, and it is not:
                // every clip sits on the floor at the root physics recorded.
                // So the body is dropped by the pose's own clearance.
                DuckStage(pose: StagePose(jointAngles: shown, root: restingRoot(for: shown)),
                          environment: scene?.environment ?? .bareFloor,
                          props: scene?.props ?? [],
                          orbit: $orbit)
                // `rootIsPinned` because it is: the root here is a constant, by
                // the design `IntentDraft`'s header states in capitals. The
                // legend was built for recorded clips and reads that pin as if
                // physics had produced it.
                // THE LEGEND IS HANDED THE STANDING-HEIGHT POSE ON PURPOSE.
                // Its clearance reading against that pose IS the drop, and it
                // is the same measurement that used to be printed as a float.
                // Measuring the rested pose instead would read zero by
                // construction and blind the check that caught the build where
                // every clip floated.
                StageLegend(pose: StagePose(jointAngles: shown, root: StagePose.home.root),
                            environment: scene?.environment ?? .bareFloor,
                            props: scene?.props ?? [],
                            rootIsPinned: true,
                            restedOnFloor: true,
                            orbit: $orbit)
            }
            .frame(maxHeight: 300)

            // ABOVE THE TAB PICKER, BECAUSE THE THING IT IS ABOUT IS ABOVE THE
            // TAB PICKER. A warning about the floor that only appears on one
            // tab vanishes while the misleading floor stays on screen.
            if draft.sceneID != nil, scene == nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(StageCaption.sceneDeleted(.authoredAgainst), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                    Spacer(minLength: 8)
                    Button("Bare floor") { draft.sceneID = nil }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.horizontal).padding(.top, 6)
            }

            TransportBar(duration: max(draft.duration, 0.01),
                         playhead: $playhead, isRunning: $isRunning)
                .padding(.horizontal).padding(.vertical, 6)

            Picker("Panel", selection: $panel) {
                ForEach(Panel.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.bottom, 6)

            List {
                switch panel {
                case .joints:   joints
                case .timeline: timeline
                case .ask:      ask
                case .checks:   checks
                }
            }
        }
        .navigationTitle(draft.name)
        .navigationBarTitleDisplayMode(.inline)
        // TWO WAYS OUT, BOTH ALWAYS PRESENT. The first version had one — a
        // "Save" button that both wrote to the store and dismissed in the same
        // tick — and a person who did not want to keep what they had made had
        // nowhere to go. Done only dismisses, because the work is already
        // saved; Cancel puts back what was there on the way in.
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { discard() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // TWO DUCKS AND A CHOICE. It sits above Export because it
                    // is a way of WRITING the motion, not a way of sending it —
                    // the same class of thing as the Ask panel, and the only
                    // one in the app that changes a motion from what somebody
                    // preferred rather than from what they typed.
                    Button { preferring = true } label: {
                        Label("Tune by preference", systemImage: "arrow.left.arrow.right")
                    }
                    Button { share() } label: {
                        Label("Export the motion", systemImage: "square.and.arrow.up")
                    }
                    Button { publishing = true } label: {
                        Label("Publish to Hugging Face", systemImage: "arrow.up.circle")
                    }
                    // A PICKER, NOT BUTTONS, SO THE CURRENT CHOICE IS VISIBLE.
                    // Plain buttons carried no selection state anywhere on the
                    // screen, which is what made a draft pointing at a DELETED
                    // scene impossible to discover: the preview fell back to
                    // bare floor and the menu looked exactly as it does for a
                    // draft that never had one. A dangling id matches no tag,
                    // so nothing is ticked — and the row under the stage says
                    // why.
                    Picker("Author against", selection: $draft.sceneID) {
                        Text("Bare floor").tag(UUID?.none)
                        ForEach(scenes.scenes) { s in
                            Text(s.name).tag(UUID?.some(s.id))
                        }
                    }
                    Divider()
                    // The only other way to remove a motion is swiping its row
                    // in the list, which nothing signposts.
                    Button("Delete this motion", role: .destructive) {
                        confirmingDelete = true
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    // AN ICON WITH NO TEXT IS ANNOUNCED BY GUESSING AT THE
                    // SYMBOL NAME. This one is the only way to export, publish,
                    // change the scene or delete the motion, so "ellipsis
                    // circle" is the difference between having those and not.
                    .accessibilityLabel(Text("More"))
            }
        }
        .confirmationDialog("Throw away this motion?", isPresented: $confirmingDiscard,
                            titleVisibility: .visible) {
            Button("Throw it away", role: .destructive) { reallyDiscard() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            // THE OLD COPY WAS FALSE AT EXACTLY THE MOMENT IT MATTERED. It
            // chose on `keys.count < 3`, and a blank motion has two, so every
            // brand-new one was told "It has not been saved anywhere else" —
            // while sitting in the list, saved.
            Text(isNew
                 ? "This motion will be deleted. It is not saved anywhere else."
                 : "Everything since you opened it will go back to how it was.")
        }
        .confirmationDialog("Delete this motion?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { dismiss(); onDiscard(draft) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It goes from the list and from this iPhone. This cannot be undone.")
        }
        .onAppear { if original == nil { original = draft } }
        .sheet(isPresented: $preferring) {
            NavigationStack {
                PreferenceSearchView(draft: draft, scene: scene) { chosen in
                    // THE SEARCH RETURNS A MOTION, NOT A SETTING. Keeping the
                    // knob values would leave the draft's keyframes untouched
                    // and the preference living somewhere only this screen
                    // understands; writing the poses back means what was
                    // chosen IS the motion, and every other screen — export,
                    // the bench, the checks — sees it.
                    draft.keys = chosen.keys
                }
            }
        }
        .sheet(item: $outgoing) { out in
            NavigationStack {
                ShareDestinationsView(title: draft.name, file: out.url, message: out.message)
            }
        }
        .sheet(isPresented: $publishing) {
            PublishMotionView(draft: draft)
        }
        .alert("Could not export", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failure ?? "") }
        .onReceive(Timer.publish(every: 1.0 / DuckModel.tickHz, on: .main, in: .common).autoconnect()) { _ in
            guard isRunning, draft.duration > 0 else { return }
            playhead += 1.0 / DuckModel.tickHz
            if playhead >= draft.duration { playhead = 0 }
        }
        // THE COLLISION WARNING DIES WITH THE MOTION THAT CAUSED IT, and this
        // is the only place that rule needs to live. `blockedRetime` names two
        // specific keyframes that were too close to swap; delete either one,
        // add a third between them, or let a tweak rewrite the timeline, and
        // the warning is about a conflict that no longer exists. Hanging the
        // clear here rather than on each of the six edits that could invalidate
        // it is what makes it total — and a REFUSED retime is exactly the case
        // that must not clear it, which this gets right for free: a refusal
        // leaves `draft` untouched, so this never fires.
        .onChange(of: draft) { _, new in
            blockedRetime = nil
            onSave(new)
        }
    }

    // MARK: - posing

    @ViewBuilder private var joints: some View {
        Section {
            TextField("Name", text: $draft.name)
            // WHICH PLACE THIS IS BEING JUDGED IN, in words. The stage draws
            // it and the legend counts what is standing in it, but neither
            // names it, and the name is the only thing that ties what is on
            // screen to the menu item somebody tapped.
            LabeledContent("Posed against") {
                Text(scene?.name ?? (draft.sceneID == nil ? "Bare floor" : "A deleted scene"))
            }
            .font(.footnote)
            Text(IntentDraft.disclaimer).font(.caption).foregroundStyle(.secondary)
        }

        Section {
            Picker("Editing", selection: Binding(
                get: { editingKey?.id },
                set: { picked in
                    selectedKey = picked
                    // Jump the playhead to whatever was picked, so the robot on
                    // screen is always the pose the sliders move. Editing one
                    // keyframe while looking at another is how somebody drags a
                    // joint for a minute and wonders why nothing happens.
                    if let picked, let key = ordered.first(where: { $0.id == picked }) {
                        playhead = key.time
                    }
                    isRunning = false
                })) {
                ForEach(ordered) { key in
                    Text(String(format: "%.2f s", key.time)).tag(UUID?.some(key.id))
                }
            }
            .pickerStyle(.segmented)
            // The picker shows what exists; this makes one. Without it the only
            // way to add a keyframe was the Keyframes tab, which somebody
            // working on a pose has no reason to open.
            Button {
                let time = nudged(playhead)
                let key = IntentDraft.Key(time: time, pose: draft.pose(at: playhead))
                draft.keys.append(key)
                selectedKey = key.id
                playhead = time
            } label: {
                Label(String(format: "Add a keyframe here (%.2f s)", playhead),
                      systemImage: "plus")
                    .font(.footnote)
            }
        } header: {
            Text("Keyframe")
        } footer: {
            Text("Pick a moment, then move the joints. The robot above shows the keyframe you are editing. A new one holds whatever the motion was already doing at that instant — every pose stays pinned, though the curve between them re-eases, because each span is smoothed on its own.")
        }

        if let key = editingKey {
            ForEach(JointGroup.all) { group in
                Section {
                    ForEach(group.joints, id: \.self) { joint in
                        JointSlider(control: JointControl(index: joint),
                                    value: binding(joint: joint, of: key.id))
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    group.note.map { Text($0) }
                }
            }
        }
    }

    /// A slider drives ONE joint of ONE keyframe, found by id — sorting by time
    /// means an index names a different keyframe the moment somebody drags one
    /// past its neighbour, and names nothing once one is deleted.
    private func binding(joint: Int, of id: UUID) -> Binding<Double> {
        Binding(
            get: {
                draft.keys.first { $0.id == id }?.pose[joint]
                    ?? JointControl(index: joint).home
            },
            set: { value in
                guard let index = draft.keys.firstIndex(where: { $0.id == id }),
                      draft.keys[index].pose.indices.contains(joint) else { return }
                draft.keys[index].pose[joint] = value
            })
    }

    // MARK: - asking for a change

    /// Describe a change and watch it happen.
    ///
    /// IT EDITS; IT DOES NOT REDRAFT. The model is shown the motion that exists
    /// — every keyframe, every joint that has moved — and asked for a list of
    /// changes. Everything it does not mention is left alone, which is the only
    /// behaviour that makes a second sentence safe to send. Asking for a whole
    /// new motion would throw away every slider already nudged.
    @ViewBuilder private var ask: some View {
        Section {
            TextField("Make the bow deeper. Hold it longer. Look left at the end.",
                      text: $asked, axis: .vertical)
                .lineLimit(1...4)
            Button {
                Task { await applyTweak() }
            } label: {
                HStack {
                    Label("Change it", systemImage: "wand.and.stars")
                    if thinking { Spacer(); ProgressView() }
                }
            }
            .disabled(thinking || asked.trimmingCharacters(in: .whitespaces).isEmpty
                      || models.selected.kind != .openAICompatible)
        } header: {
            Text("Describe a change")
        } footer: {
            // THE REFUSAL HAS TO NAME A STEP THAT WORKS. The old one said
            // "Choose one under Draft → Models" to everybody, including the
            // person on the out-of-the-box choice — who then went to Models,
            // selected the Apple row that cannot be deleted, and came back to
            // exactly the same dead button and the same sentence. What is
            // needed is a DIFFERENT KIND of model, not a different selection,
            // and the sentence now says which kind and why.
            // A DOWNLOADED MODEL CAN DO THIS TOO. It returns JSON in prose
            // exactly as a server does; it is Apple's typed-value path that
            // cannot express a list of edits.
            if models.selected.kind != .appleOnDevice {
                Text("\(models.selected.name) is asked for a list of changes to THIS motion, not for a new one. Anything it does not mention is left exactly as it is. \(models.selected.privacyNote)")
            } else {
                // A DOOR, NOT DIRECTIONS. This told people to walk to another
                // tab; `ModelSettingsView` is reachable from here because all
                // three presenters of this view wrap it in a NavigationStack.
                NavigationLink { ModelSettingsView(store: models) } label: {
                    Label("Models", systemImage: "brain")
                }
                Text("\(models.selected.name) hands back a whole motion as a typed value, which is the shape it guarantees and the reason drafting works on it. There is no typed shape here for a list of edits, so this app does not ask it for one. Add a server here rather than picking a different model: any OpenAI-compatible address will do, and a small local one is plenty, because every angle it asks for is checked and clamped here afterwards.")
            }
        }

        if let failure = tweakFailure {
            Section {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }

        // ABOVE THE NOTES, NOT AFTER THEM. What was refused is the thing the
        // person has to act on; what worked they can see on the robot.
        if !tweakRefusals.isEmpty {
            Section {
                ForEach(tweakRefusals, id: \.self) {
                    Label($0, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            } header: {
                Text("Not applied")
            } footer: {
                // "EVERYTHING ELSE WAS APPLIED" IS FALSE WHEN NOTHING WAS.
                // `MotionTweak.outcome` throws only when a refusal carries a
                // `Failure` behind it; a list whose sole instruction is refused
                // by SENTENCE — an empty rename is the shipped example — comes
                // back with no notes and no throw, and this footer used to
                // announce a success that had not happened beside the refusal
                // saying it had not.
                Text(tweakNotes.isEmpty
                     ? "Nothing else was asked for, so the motion is exactly as it was. Say it again in other words, or change it by hand in Pose."
                     : "Everything else in the same sentence was applied. Say these again in other words, or change them by hand in Pose.")
            }
        }

        if !tweakNotes.isEmpty {
            Section {
                ForEach(tweakNotes, id: \.self) {
                    Label($0, systemImage: "checkmark").font(.footnote)
                }
                if beforeTweak != nil {
                    Button(role: .destructive) {
                        if let before = beforeTweak {
                            draft = before
                            beforeTweak = nil
                            tweakNotes = []
                            tweakRefusals = []
                            tweakMoment = nil
                        }
                    } label: {
                        Label("Put it back", systemImage: "arrow.uturn.backward")
                    }
                }
            } header: {
                Text("What changed")
            } footer: {
                // THE CLAIM NOW MATCHES WHAT THE PLAYHEAD DID. It used to say
                // the robot was already showing the change while the playhead
                // had been sent to the motion's FIRST keyframe — which is the
                // standing pose on every draft that starts blank or comes from
                // a proposal, i.e. the one moment where a deeper bow is
                // invisible. When there is nowhere new to point (a rename, a
                // keyframe removed) the playhead stays put and this says so
                // rather than claiming a pose that did not move.
                Text(tweakMoment == nil
                     ? "Nothing new was added at a moment to jump to, so the robot above is where you left it. The keyframe list and the name are where to look."
                     : "The robot above is standing at the moment the change landed. Scrub the timeline to watch it through.")
            }
        }
    }

    private func applyTweak() async {
        let sentence = asked.trimmingCharacters(in: .whitespaces)
        thinking = true; tweakFailure = nil; tweakRefusals = []
        defer { thinking = false }
        let endpoint = models.armed(models.selected)
        do {
            let answer = try await DraftEngine.ask(
                endpoint, kind: .tweak, prompt: sentence, knownIntents: [],
                instructions: ChatDraft.tweakInstructions(for: draft))
            let tweak = try ChatDraft.tweak(fromJSON: answer.json)
            let outcome = try tweak.outcome(applyingTo: draft)
            let was = draft
            // NOTHING TO PUT BACK WHEN NOTHING MOVED. `outcome` returns without
            // throwing when every instruction was refused by sentence, and
            // offering "Put it back" against an identical motion is a control
            // that cannot do anything.
            //
            // COMPARED THROUGH SORTED KEYS, BECAUSE THE KIT SORTS AND
            // `IntentDraft` IS EQUATABLE ON ARRAY ORDER. A draft whose keys
            // happen to be stored out of time order comes back from a
            // no-op tweak reordered but unchanged, and a plain `==` reads that
            // as an edit — which offers an undo for something that did not
            // happen, on exactly the all-refused path this guard exists for.
            let unchanged = outcome.draft.keys.sorted { $0.time < $1.time }
                         == was.keys.sorted { $0.time < $1.time }
            beforeTweak = unchanged ? nil : was
            draft = outcome.draft
            // THE MODEL'S SUMMARY IS NOT A SUBSTITUTE FOR A NOTE. This used to
            // read `notes.isEmpty ? [tweak.summary] : notes`, which meant that
            // when every instruction was refused the screen showed the model's
            // own description of what it INTENDED — "made the bow deeper" —
            // under a checkmark, beside a motion nothing had happened to. An
            // empty notes list is now simply an empty section, and the refusals
            // beside it say why.
            tweakNotes = outcome.notes
            tweakRefusals = outcome.refusals
            // THE SENTENCE STAYS IN THE BOX WHEN NOTHING LANDED. Clearing it
            // was fine while every path here changed something; it is not fine
            // on the path where every instruction came back refused, because
            // the obvious next move is to reword what you typed and it has
            // gone.
            if !outcome.notes.isEmpty { asked = "" }
            // Show the moment the edit landed on, which is a question only the
            // resulting motion can answer — a stated time is snapped to the
            // nearest keyframe, clamped, or refused on the way in. This used to
            // take the motion's FIRST keyframe, which is the standing pose by
            // construction and is where nothing an edit did is visible.
            // The editor autosaves on every change of `draft`, so there is
            // nothing to call here — the onChange above has already run.
            tweakMoment = outcome.draft.firstNewMoment(comparedTo: was)
            if let moment = tweakMoment { playhead = moment }
            isRunning = false
        } catch let failure as MotionTweak.Failure {
            tweakFailure = failure.message
        } catch let wire as ChatWire.WireError {
            tweakFailure = wire.message
        } catch let draftError as ChatDraft.DraftError {
            tweakFailure = draftError.message
        } catch {
            tweakFailure = error.localizedDescription
        }
    }

    // MARK: - the timeline

    @ViewBuilder private var timeline: some View {
        if let blockedRetime {
            Section {
                Label(blockedRetime, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        Section {
            ForEach(ordered) { key in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(moment(key.time))
                            .font(.subheadline.monospacedDigit())
                        Spacer()
                        Button("Show") {
                            playhead = key.time; isRunning = false
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    // RETIMING WAS THE MISSING ONE. A keyframe could be added,
                    // shown and deleted, and the only way to change WHEN it
                    // happened was to delete it and build it again — so every
                    // "hold it a bit longer" meant redoing the pose.
                    Stepper(value: Binding(
                        get: { key.time },
                        set: { retime(key, to: $0) }),
                            in: 0...30, step: 0.05) {
                        Text("Move it").font(.caption).foregroundStyle(.secondary)
                    }
                    // WHAT IT MOVED TO, WHICH ONLY THE ROW ABOVE SAID. A
                    // stepper announcing "Move it" and nothing else gives no
                    // feedback at all on the one control here that can be
                    // REFUSED: a collision leaves the time exactly where it
                    // was, and a person who hears no number cannot tell that
                    // from a tap that did not register. Same expression as the
                    // heading, so the two cannot round apart.
                    .accessibilityValue(Text(moment(key.time)))
                }
            }
            .onDelete { offsets in
                let doomed = offsets.map { ordered[$0].id }
                draft.keys.removeAll { doomed.contains($0.id) }
                // The moment that was in the way may have just been the one
                // deleted, and a refusal naming a keyframe that no longer
                // exists is worse than no refusal at all.
                blockedRetime = nil
            }
        } header: {
            Text("Keyframes")
        } footer: {
            Text("Between keyframes the robot is interpolated with smoothstep — it arrives and leaves at rest. A linear blend would change speed instantly at every keyframe, and a servo asked to do that answers with a jolt the balance controller then has to absorb.")
        }

        Section {
            Button {
                // The pose currently on screen, at the moment currently on
                // screen. Capturing the interpolated pose rather than a copy of
                // a neighbour keeps every pose that was pinned pinned — but it
                // is NOT a no-op, and this comment used to claim it was. Each
                // span is smoothstepped separately, so splitting one in two
                // makes the duck ease through the middle where it used to sail
                // past: about two degrees at the half-second on a simple bow.
                // The least surprising choice available, not a free one.
                let time = nudged(playhead)
                let key = IntentDraft.Key(time: time, pose: draft.pose(at: playhead))
                draft.keys.append(key)
                selectedKey = key.id
                playhead = time
                panel = .joints
            } label: {
                Label(String(format: "Add a keyframe at %.2f s", playhead), systemImage: "plus")
            }
            Button {
                let last = ordered.last
                draft.keys.append(.init(time: (last?.time ?? 0) + 0.5,
                                        pose: last?.pose ?? DuckStance.home.jointAngles))
            } label: {
                Label("Add half a second on the end", systemImage: "arrow.right.to.line")
            }
        }
    }

    /// Move a keyframe to another moment, refusing a collision rather than
    /// creating one.
    private func retime(_ key: IntentDraft.Key, to time: TimeInterval) {
        guard let index = draft.keys.firstIndex(where: { $0.id == key.id }) else { return }
        // THE REFUSAL IS SAID OUT LOUD NOW. Both the collision window and the
        // sentence live in StudioKit, because the window is the same one
        // `MotionTweak` moves keyframes by and a second copy of it here is how
        // the two start disagreeing. Refusing is right — two keyframes at one
        // instant is a broken motion — but this used to refuse by returning,
        // and since the stepper walks in 0.05 s straight onto a neighbour, a
        // brand-new motion's two keyframes half a second apart stall on the
        // tenth tap with nothing on screen changing at all.
        if let refusal = IntentDraft.retimeRefusal(draft.keys, moving: key.id, to: time) {
            blockedRetime = refusal
            return
        }
        blockedRetime = nil
        draft.keys[index].time = max(time, 0)
        playhead = draft.keys[index].time
        isRunning = false
    }

    /// A keyframe's moment as words, printed and spoken from one expression.
    private func moment(_ time: TimeInterval) -> String {
        String(format: "%.2f s", time)
    }

    /// A time not already taken. Two keyframes at the same instant is a broken
    /// motion, and the button that creates it should not be able to.
    private func nudged(_ time: TimeInterval) -> TimeInterval {
        var candidate = max(time, 0)
        while draft.keys.contains(where: { abs($0.time - candidate) < 0.005 }) {
            candidate += 0.02
        }
        return candidate
    }

    // MARK: - checks

    @ViewBuilder private var checks: some View {
        let problems = draft.problems
        Section {
            Text(draft.provenance).font(.footnote).foregroundStyle(.secondary)
        }
        if problems.isEmpty {
            Section {
                Label("Nothing to flag. Every pose is inside its travel and nothing moves faster than the recorded corpus does.",
                      systemImage: "checkmark.circle")
                    .font(.footnote)
            }
        } else {
            Section {
                ForEach(problems) { problem in
                    Label {
                        Text(problem.text).font(.footnote)
                    } icon: {
                        Image(systemName: icon(problem.severity))
                            .foregroundStyle(problem.severity == .caution ? Color.secondary : .orange)
                    }
                }
            } header: {
                Text("Checks")
            } footer: {
                Text("These are the things a phone can check: travel, ordering, and how fast a joint is asked to move against what the recorded corpus actually does. What it cannot check is whether the robot stays up, because that needs physics.")
            }
        }
        Section {
            Text("Every authored move in this app — step_up, lever_up, riser_up, climb — was written this way and searched against a real step, and all four get up their flight 0 times in 16. Authoring is the easy half.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Before you run it")
        }
    }

    private func icon(_ severity: IntentDraft.Problem.Severity) -> String {
        switch severity {
        case .broken:     return "exclamationmark.triangle.fill"
        case .impossible: return "gauge.with.dots.needle.100percent"
        case .caution:    return "info.circle"
        }
    }

    /// Leave without keeping the changes. Asks first only when there is
    /// something to lose — a confirmation on an untouched draft is a dialog
    /// that teaches people to tap through dialogs.
    private func discard() {
        // An untouched NEW motion still has something to lose — itself. It was
        // committed to the store before this sheet opened, so dismissing
        // silently leaves a row called "New motion" that the person never
        // wanted and cannot explain.
        guard hasUnsavedChanges else {
            dismiss()
            if isNew { onDiscard(draft) }
            return
        }
        confirmingDiscard = true
    }

    private func reallyDiscard() {
        if isNew {
            // NOTHING TO GO BACK TO: this motion did not exist before the sheet
            // opened. And do NOT restore `original` first — assigning `draft`
            // fires the .onChange that saves, which would re-create the row
            // being deleted. That is what the first version did, so the red
            // "Throw it away" button put the motion straight back.
            dismiss()
            onDiscard(draft)
            return
        }
        if let original {
            draft = original
            onSave(original)
        }
        dismiss()
    }

    private func share() {
        do {
            let data = try draft.exported()
            let url = try ExportFile.write(data, named: draft.suggestedFilename)
            outgoing = Outgoing(url: url, message: CommunityShare.message(forDraft: draft))
        } catch let error as DuckMove.Invalid {
            failure = error.message
        } catch let error as ExportFile.Failure {
            failure = error.message
        } catch {
            failure = "\(error)"
        }
    }
}

/// One joint, with its real travel as the slider's ends.
private struct JointSlider: View {
    let control: JointControl
    @Binding var value: Double

    /// What the slider says when it is spoken instead of seen.
    ///
    /// THE TRAVEL STOPS ARE PART OF THE VALUE, NOT DECORATION. The ends of this
    /// slider are the joint's real travel, so a thumb that will not go further
    /// has hit the joint's limit rather than a bug — and the two numbers under
    /// the track are the only thing on screen that says which. Drop them and
    /// the spoken control is strictly worse than the printed one: fifteen of
    /// these per keyframe, each stopping somewhere different, with no way to
    /// tell a stop from a stall. Every part comes from `JointControl`, the same
    /// expressions the three visible rows use, so the spoken and printed
    /// angles cannot round apart.
    private var spoken: String {
        "\(control.degrees(value)), travel \(control.travelLabel.lower) to \(control.travelLabel.upper)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Hidden because the slider below now carries the name, the angle
            // and both stops. A Slider is its own element with the adjustable
            // trait and never reads a sibling HStack, so these rows would
            // otherwise be spoken beside a control still announcing itself as a
            // bare percentage.
            HStack {
                Text(control.name).font(.caption)
                Spacer()
                Text(control.degrees(value))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            // The ends ARE the travel stops, so the slider cannot ask for an
            // angle the joint does not have. A slider with generous ends and a
            // warning underneath is a slider that teaches people to ignore
            // warnings.
            Slider(value: $value, in: control.lower...control.upper)
                .accessibilityLabel(Text(control.name))
                .accessibilityValue(Text(spoken))
            HStack {
                Text(control.travelLabel.lower)
                Spacer()
                Text(control.travelLabel.upper)
            }
            .font(.caption2).foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
    }
}


