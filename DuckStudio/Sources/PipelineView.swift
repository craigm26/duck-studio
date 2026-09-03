import SwiftUI
import DuckKit
import StudioKit

/// Where a motion stands on its way from a sentence to a robot.
///
/// THE STAGES ALWAYS EXISTED; NOTHING SHOWED THEM. A motion could be written,
/// previewed on a phone that has no physics engine, run on a real one across
/// the room, and end up carrying no memory of any of it — somebody opening it a
/// week later saw keyframes and a name. Now the draft remembers, and this is
/// where it says so.
///
/// THE PREVIEW IS NOT A RUN, and the difference is the point of the screen. An
/// iPhone has no MuJoCo: what the stage draws is what you asked for. Only the
/// bench can tell you what happens, and the gap between the two is where the
/// surprises live — an authored bow keeps 8 of 8 rollouts upright and still
/// finishes 25 mm below standing height, which no preview would ever show.
///
/// EVERY STAGE SAYS ITS STANDING IN A WORD. It used to say it in a tinted
/// symbol and in nothing else — the words existed, in `Pipeline.State.spoken`,
/// and were handed to VoiceOver only. Roughly one man in twelve cannot separate
/// the green tick from the orange one, and "done" and "done, worth reading" are
/// the two states this screen exists to tell apart. The word is now on the
/// glass and the symbol is hidden from the screen reader, so the fact is
/// carried once and read the same way by everybody.
///
/// THE RESULT'S FIGURES ARE TELEMETRY ROWS. A rollout count, a finishing height
/// and a peak joint rate are numbers that change from run to run, which is what
/// earns tabular figures; the bench's name, the policy's name and the clock
/// reading are not, and stay in SF beside them.
struct PipelineView: View {
    let draftID: UUID
    @ObservedObject var drafts: DraftStore
    @ObservedObject var scenes: SceneStore
    /// Handed on to the bench screen, which hands it on to the player, which
    /// hands it to the editor. Nothing on this screen asks a model anything.
    @ObservedObject var models: EndpointStore

    /// WHICH SAVED BENCH. This read the one `@AppStorage` address every other
    /// bench screen used to read, so "has a bench" meant "a string is not
    /// empty" — true for an address that had never answered anything.
    @ObservedObject var benches: BenchStore
    @State private var busy = false
    @State private var failure: String?

    /// THE PICTURE OF THE RUN THAT JUST HAPPENED, AND IT IS NOT PERSISTED.
    /// A `/perform` answer is 50 × 24 numbers and a `/climb` clip is 211 × 24;
    /// writing either onto the draft on every run is unbounded growth on disk
    /// for a picture nobody asks for twice. A relaunch keeps the numbers and
    /// loses the picture — which `BenchOutcome.worldSentence` still describes
    /// in words, because the world was narrow enough to keep.
    @State private var lastRun: LastRun?

    /// THE CLIP CARRIES ITS OWN ROUTE AND THE WORLD IT WAS READ BACK IN, so
    /// the stage below can never pair a clip from one route with a world the
    /// other route persisted, and the player's caption is a fact carried with
    /// the clip rather than a claim assumed at the link.
    private enum LastRun {
        case performed(DuckIntentClip, laid: Pipeline.LaidWorld?)
        case climbed(DuckIntentClip, laid: Pipeline.LaidWorld?)

        var clip: DuckIntentClip {
            switch self {
            case .performed(let clip, _), .climbed(let clip, _): return clip
            }
        }
        /// What the player may say about the picture. A /climb clip comes out
        /// of the harness's own episode with the flight it ran on; a /perform
        /// clip is a readback only when a `stood` block came with it, and a
        /// bare floor otherwise, which claims nothing.
        var caption: StageCaption.RunWorld {
            switch self {
            case .climbed: return .readback
            case .performed(_, let laid): return laid == nil ? .bareFloor : .readback
            }
        }
    }
    /// The still picture's camera. One per screen, so a drag on the run card's
    /// stage does not move any other stage in the app.
    @State private var orbit = OrbitState()

    private var draft: IntentDraft? { drafts.drafts.first { $0.id == draftID } }

    /// The scene this draft was authored against, resolved BY IDENTITY out of
    /// the store this screen has held since day one and never read.
    private func scene(for draft: IntentDraft) -> DuckScene? {
        draft.sceneID.flatMap { id in scenes.scenes.first { $0.id == id } }
    }

    /// WHICH BENCH ROUTE THIS DRAFT GOES DOWN — ASKED, NEVER DECIDED HERE.
    ///
    /// Sending a stairs-challenge draft to `/perform` plays it on a bare bench
    /// and reports "8 of 8 stayed upright" over a picture of a staircase that
    /// was not in the physics. That decision is nine ordered rows in
    /// `BenchRoute`, where a test reads every one of them; this screen asks and
    /// draws the answer.
    ///
    /// NO GRASPABLES ARE PASSED, AND THAT IS A GAP AND NOT A CHOICE. The plan
    /// asks for `benches.graspables(for:)`; `BenchStore` has no such reader and
    /// is not this owner's file to grow one. `DriveView` gets its list from a
    /// `/health` probe it runs itself, which this screen does not do. The kit's
    /// default is the empty list, which plans the props by name without their
    /// measured masses.
    private func route(for draft: IntentDraft) -> BenchRoute {
        BenchRoute.of(draft: draft, scene: scene(for: draft))
    }

    private var pipeline: Pipeline? {
        draft.map {
            Pipeline.of($0, bench: $0.bench, hasBench: benches.selected != nil)
        }
    }

    var body: some View {
        List {
            if let draft, let pipeline {
                Section {
                    progress(pipeline)
                    Text(pipeline.next.map { "Next: \($0.name.lowercased())" }
                         ?? "Everything that can be done has been.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    SectionHeading(text: draft.name)
                }
                .listRowBackground(Theme.surfacePrimary)

                ForEach(pipeline.stages) { stage in
                    Section {
                        stageRow(stage)
                        if stage.name == "Run in physics" {
                            physicsControls(draft)
                        }
                        // NO SHARE LINK ON THE ATTESTED STAGE, DELIBERATELY.
                        // It passed `file: nil` and `message: draft.name`, so
                        // "Copy the message" copied the words "My bow" — under
                        // a footer promising "the fingerprint is the part a
                        // recipient can verify without trusting you", with no
                        // fingerprint, no file and no result in it. The obvious
                        // repair is worse: `CommunityShare.message(forDraft:)`
                        // embeds `IntentDraft.disclaimer` — "no physics ran" —
                        // on the one draft where physics did run. It comes back
                        // when the kit can compose a message that carries which
                        // bench, which policy, and the count.
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                if let bench = draft.bench {
                    Section {
                        LabeledContent("Ran", value: bench.when.formatted(date: .abbreviated,
                                                                          time: .shortened))
                        LabeledContent("Bench", value: bench.bench)
                        LabeledContent("Policy", value: bench.policy)
                        // THE THREE NUMBERS THE BENCH MEASURED, IN FIGURES THAT
                        // DO NOT MOVE. Each one is different on every run, and
                        // each one is read against the run before it — which is
                        // the whole argument for tabular digits, and for the
                        // label being in SF beside them rather than in the same
                        // mono face.
                        TelemetryRow(label: "Upright",
                                     value: "\(bench.achieves) of \(bench.rollouts)")
                        if let height = bench.medianHeight {
                            TelemetryRow(label: "Ends at",
                                         value: String(format: "%.3f", height), unit: "m")
                        }
                        if let rate = bench.peakJointRate {
                            TelemetryRow(label: "Peak joint rate",
                                         value: String(format: "%.1f", rate), unit: "rad/s")
                        }
                        // NOT A LABELLED ROW. "Plant: the bench's own plant"
                        // read like a fact with a value, and for every result
                        // stored before today there is no value at all — the
                        // honest answer there is a sentence, not a blank and
                        // not a placeholder. Composed in StudioKit, where a
                        // test asserts it.
                        //
                        // IN `measured` BECAUSE IT IS PROVENANCE. Teal is this
                        // app's claim that a machine produced what you are
                        // reading, and the sentence names the world these
                        // figures came out of — or says that nothing recorded
                        // it, which is the same claim failing honestly. It is
                        // on a `surfacePrimary` card, which is the ground
                        // `PaletteTests` proves the token at 4.5:1 against.
                        Text(bench.plantSentence)
                            .font(.caption).foregroundStyle(Theme.measured)
                            .fixedSize(horizontal: false, vertical: true)
                        // WHICH WORLD THIS RAN IN, IN ONE OF FOUR SENTENCES.
                        // Teal only when the bench read a world back out of
                        // its own joints; the other three are a run whose
                        // picture is the scene rather than the physics, and
                        // that is a warning and not a measurement.
                        Text(bench.worldSentence)
                            .font(.caption)
                            .foregroundStyle(worldTint(bench.worldStanding))
                            .fixedSize(horizontal: false, vertical: true)
                        if case .laid(let world) = bench.worldStanding {
                            laidRows(world)
                        }
                        // WHY THIS RUN IS NOT THE SCORE, WHEN IT IS NOT. The
                        // kit's sentence, set when the route was taken.
                        if let routeNote = bench.routeNote {
                            Text(routeNote)
                                .font(.caption).foregroundStyle(Theme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        SectionHeading(text: "The run")
                    } footer: {
                        // "Standing height on THIS plant" was a claim about
                        // whichever world the run above happened in, and until
                        // today no run recorded one. The number was measured on
                        // the canon plant and the sentence now says so — in
                        // StudioKit, where a test asserts it letter by letter.
                        Text(Pipeline.standingHeightSaid)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                // A SECOND ANSWER, BESIDE THE FIRST AND NEVER INSIDE IT. A
                // draft whose scene is the scored room goes to the harness's
                // own climb route, which answers one cell and no rollouts —
                // and `BenchOutcome.summary` would have fabricated "1 of 1"
                // out of it. Two answers, two types, two cards, and each says
                // which run it is.
                if let climbed = draft.climbed {
                    Section {
                        LabeledContent("Ran", value: climbed.when.formatted(
                            date: .abbreviated, time: .shortened))
                        cellRows(climbed)
                    } header: {
                        SectionHeading(text: "The cell")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                // ONE LINK FOR WHICHEVER ROUTE JUST RAN. Both answers can sit
                // on one draft, and two "See this run" links pointing at the
                // same clip would be two controls that do one thing.
                if let run = lastRun {
                    Section {
                        NavigationLink {
                            IntentPlayerView(clip: run.clip, store: scenes, drafts: drafts,
                                             models: models, run: run.caption)
                        } label: {
                            Label("See this run", systemImage: "play.rectangle")
                        }
                        .tint(Theme.actionSecondary)
                    } header: {
                        SectionHeading(text: "The picture")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
            } else {
                Section {
                    Text("That draft is gone.").foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S
        // GREY, and every row keeps a `surfacePrimary` card under it — which is
        // what lets the coloured sentences above be set at all. `Palette` is
        // explicit that `backgroundSecondary` carries the inks at 4.17:1 to
        // 4.27:1, short of the 4.5:1 body text owes, so the only words outside
        // a card here are the grey headers and footers.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Sim to real")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// How far along, as a bill and as a number.
    ///
    /// NEVER A BARE BAR. A filled shape on its own says "some" and a person
    /// reading it has to guess at the fraction; the figure beside it says which
    /// fraction, and is the only half of the pair a screen reader gets at all.
    /// The bill is the app's one pointing gesture — "this much, from here" — so
    /// progress wears it rather than the system's own bar, which arrives tinted
    /// by the platform and shaped like nothing else on the screen.
    private func progress(_ pipeline: Pipeline) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            TelemetryRow(label: "Done",
                         value: String(format: "%.0f", pipeline.fractionDone * 100),
                         unit: "%")
            // SILENT, BECAUSE THE ROW ABOVE ALREADY SAID IT. `BillIndicator`
            // takes a label only when it is the only thing making its point,
            // and here it is the picture of a number that has just been read
            // out.
            BillIndicator(fill: pipeline.fractionDone)
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }

    /// One stage: a symbol, the word for where it stands, and what that means.
    private func stageRow(_ stage: Pipeline.Stage) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing(.snug)) {
            // HIDDEN FROM VOICEOVER, NOT UNLABELLED. The state is now a word on
            // the glass three points to the right of this glyph; labelling the
            // glyph as well would read every stage twice.
            Image(systemName: symbol(for: stage.state))
                .foregroundStyle(colour(for: stage.state))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                // THE NAME AND THE STANDING, WRAPPING RATHER THAN TRUNCATING.
                // At an accessibility size "Run in physics" and "not done yet"
                // do not share a line on any phone, and the half that would
                // have been dropped is the half that says what happened.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline,
                           spacing: Theme.spacing(.tight)) {
                        stageName(stage)
                        stageStanding(stage)
                    }
                    VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                        stageName(stage)
                        stageStanding(stage)
                    }
                }
                Text(stage.detail)
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // ONE ELEMENT PER STAGE. Nothing in the row can be acted on, so its
        // three pieces — which stage, where it stands, what that means — are
        // one thing to hear rather than three to swipe past.
        .accessibilityElement(children: .combine)
    }

    private func stageName(_ stage: Pipeline.Stage) -> some View {
        Text(stage.name)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textPrimary)
    }

    /// The state as a WORD. StudioKit's, where a test asserts it — this places
    /// it and does not word it.
    private func stageStanding(_ stage: Pipeline.Stage) -> some View {
        Text(stage.state.spoken)
            .font(.caption)
            .foregroundStyle(colour(for: stage.state))
    }

    /// The world a run stood in, drawn and said.
    ///
    /// EVERY SENTENCE HERE IS THE KIT'S AND EVERY NUMBER IN THEM WAS READ OUT
    /// OF THE PHYSICS. This method places them and gates them on facts the kit
    /// computed — `aTreadFloats`, `wholeBankWasParked`, `noSpawnNote` — and
    /// composes none of them.
    @ViewBuilder
    private func laidRows(_ world: Pipeline.LaidWorld) -> some View {
        Text(DuckWorld.laidSaid(world))
            .font(.caption).foregroundStyle(Theme.measured)
            .fixedSize(horizontal: false, vertical: true)
        // THE READBACK, NEVER `scene.environment`. Drawing the scene here
        // would draw the staircase that was ASKED FOR over a run that may not
        // have had it — the whole falsehood this build exists to delete.
        // These steps are where the blocks were when the bench read its own
        // joints, and the duck is where the physics put it.
        //
        // GATED ON THE CLIP, BECAUSE A STAGE NEEDS A POSE. The pose is the
        // run's own first frame: where the duck was put down relative to the
        // flight, which is the fact the spawn exists to fix. `lastRun` is not
        // persisted, so a relaunch shows the sentences without the picture.
        //
        // `height:` AND NOT `maxHeight:`. A list row proposes no height, and a
        // maximum alone collapses a stage with no intrinsic size to nothing.
        // AND ONLY THE CLIP THAT WAS READ BACK IN THIS WORLD: a /climb clip
        // on this card, or a /perform clip from an earlier world, would put a
        // pose from one run inside the room of another.
        if case .performed(let clip, let laid)? = lastRun, laid == world {
            DuckStage(pose: .at(clip.pose(at: 0)),
                      environment: world.asEnvironment,
                      props: world.asProps,
                      orbit: $orbit)
                .frame(height: 220)
                .listRowInsets(EdgeInsets())
        }
        if let spawn = world.spawn, spawn.y != 0 {
            Text(DuckWorld.duckMovedToTheBank)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if world.aTreadFloats {
            Text(DuckWorld.blocksAreTwoHundredMillimetresTall)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if world.wholeBankWasParked {
            Text(DuckWorld.bankWasParkedForThisRun)
                .font(.caption).foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        if world.noSpawnNote != nil {
            Text(DuckWorld.noSpawnBesideAFlight)
                .font(.caption).foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        // WHAT THE BENCH COULD NOT DO WITH WHAT IT WAS ASKED FOR, grouped by
        // the kit so four identical notes are one line rather than four.
        if let header = DuckWorld.couldNotExpress(world.unexpressed) {
            Text(header)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(DuckWorld.groupedSayings(world.unexpressed), id: \.self) { saying in
                Text(saying)
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One scored cell, in the four rows the challenge screen prints.
    ///
    /// AN UNSCORED CELL PRINTS THE BENCH'S OWN REASON AND NOTHING ELSE. A
    /// verdict beside "not scored" would be a verdict about an episode the
    /// bench declined to run.
    @ViewBuilder
    private func cellRows(_ cell: Pipeline.CellOutcome) -> some View {
        if cell.invalid {
            Text(cell.why ?? StairsChallenge.oneCellSaid(cell))
                .font(.footnote).foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(StairsChallenge.scoredWhereItIsScored)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(StairsChallenge.oneCellSaid(cell))
                .font(.footnote).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(StairsChallenge.oneCellIsNotAScore)
                .font(.caption).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text(DuckBench.plantSaid(name: cell.plantName, digest: cell.plantDigest))
            .font(.caption).foregroundStyle(Theme.measured)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Teal for a world that was read back, and the warning ink for the three
    /// states where the picture is the scene rather than the physics. Both
    /// tokens are asserted at 4.5:1 on `surfacePrimary` by `PaletteTests`.
    private func worldTint(_ standing: Pipeline.BenchOutcome.WorldStanding) -> Color {
        if case .laid = standing { return Theme.measured }
        return Theme.warning
    }

    @ViewBuilder
    private func physicsControls(_ draft: IntentDraft) -> some View {
        if benches.selected == nil {
            NavigationLink {
                BenchSettingsView(store: benches)
            } label: {
                Label("Point it at a bench", systemImage: "network").font(.footnote)
            }
        } else {
            // THE ACTION COLOUR ON THE ONE CONTROL THAT DOES SOMETHING. Every
            // other row in this section navigates or explains; this is the one
            // that spends fifteen minutes of somebody else's CPU, and the
            // capsule is what says so before it is pressed.
            //
            // AT THE HIG'S FORTY-FOUR AND NOT AT SIXTY, because nothing moves
            // while you are looking at it. `primaryActionMoves` is for a
            // control held one-handed by somebody watching a duck; this one
            // starts eight rollouts and then there is nothing to watch until
            // they finish.
            Button {
                Task { await run(draft) }
            } label: {
                Label(draft.bench == nil ? "Run it in physics" : "Run it again",
                      systemImage: "play.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .disabled(busy || draft.keys.count < 2)
            // THE SPINNER SITS OUTSIDE THE CAPSULE. Inside it, it would be
            // drawn in the app's tint against Duck Orange — two accents on one
            // shape — and it would stretch the capsule as it appeared, moving
            // a control under a thumb that is already on it.
            //
            // AND IT IS A SPINNER AND NOT A SENTENCE, which is a gap and not a
            // choice: there is no string in StudioKit for "the bench is working
            // through your eight rollouts", and inventing one here would put a
            // claim about a machine in a view. The footer below says what the
            // eight rollouts are; nothing says how far through them this is.
            if busy {
                ProgressView().tint(Theme.brandPrimary)
            }
            if let failure {
                Text(failure).font(.caption).foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // WHAT PRESSING THIS ACTUALLY DOES, WHICH IS NOW ROUTE-DEPENDENT.
            // The literal that used to sit here promised eight rollouts on
            // every draft, including the ones that go to the harness's own
            // climb route and get one cell. The route says which it is, and
            // the kit says it in words a test reads.
            Text(route(for: draft).footnote)
                .font(.caption2).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // WHICH BENCH THIS IS ABOUT, AND A WAY TO CHANGE IT. This screen
            // offered a route to bench settings only while no bench existed,
            // so Studio → Motions contained no way to reach them at all once one
            // did — and no way to see which machine a result came off.
            if let chosen = benches.selected {
                Text("On \(chosen.name) — \(chosen.address)")
                    .font(.caption2.monospaced()).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NavigationLink { BenchSettingsView(store: benches) } label: {
                Label("Manage benches", systemImage: "slider.horizontal.3").font(.caption2)
            }
        }
    }

    @MainActor private func run(_ draft: IntentDraft) async {
        busy = true; failure = nil; lastRun = nil
        defer { busy = false }
        do {
            guard let chosen = benches.selected else {
                failure = "No bench is set up, so there is nothing to run this on."
                return
            }
            let armed = benches.armed(chosen)
            let address = try armed.resolved()

            switch route(for: draft) {
            case .climb(let rise, let cell, let intent, _):
                // THE SCORED ROOM GOES TO THE ROUTE THE SCORE IS SCORED ON.
                // Same flight, same north wall, same isolation, same tail —
                // and `clip: true`, so the picture comes out of the harness's
                // own episode instead of being drawn from the request.
                let call = try DuckBench.climb(address, intent: intent, rise: rise,
                                               cell: cell, clip: true)
                let data = try await ask(call, armed)
                var updated = draft
                updated.climbed = Pipeline.CellOutcome(try DuckBench.readClimbed(data),
                                                       when: Date())
                drafts.save(updated)
                // A /climb answer without a clip is an older bench: the
                // numbers stand and there is simply no picture.
                if let clip = try DuckBench.readClimbedClip(data, named: draft.name) {
                    lastRun = .climbed(clip, laid: updated.climbed?.laid)
                }

            case .perform(let standing, let because):
                let call = try DuckBench.perform(address, keys: draft.benchTrack,
                                                 seconds: draft.duration + 0.5, rollouts: 8,
                                                 world: standing?.plan,
                                                 spawn: standing?.spawn)
                let data = try await ask(call, armed)
                // THE PLANT IS READ, NEVER SUPPLIED. This used to hand
                // `readOutcome` a plant of its own — `readHealth` on a
                // /perform body, which cannot succeed because that body has no
                // `bench` key, falling back to the literal "the bench's own
                // plant". Every stored result in every install carries that
                // string, and the screen printed it in the same voice as the
                // measured numbers beside it. The bench now names its own
                // world in the answer; if it does not, the outcome says so
                // instead of borrowing a name from here.
                //
                // `askedForWorld` IS THE CALLER'S TO RECORD. A no-world
                // /perform answer is byte-identical to the one this route has
                // always given, deliberately, so there is no field on the wire
                // that tells "nothing was asked for" from "a bench too old to
                // answer". Only this line knows.
                var updated = draft
                updated.bench = try DuckBench.readOutcome(data, when: Date(),
                                                          askedForWorld: standing?.plan != nil)
                // THE CAVEAT IS STORED WITH THE NUMBERS IT QUALIFIES, not
                // held in a state that a relaunch forgets while the numbers
                // it was qualifying survive.
                updated.bench?.routeNote = because
                drafts.save(updated)
                if let clip = try? DuckBench.readPerformedClip(data, named: draft.name,
                                                               laid: updated.bench?.laid) {
                    lastRun = .performed(clip, laid: updated.bench?.laid)
                }

            case .notYet(let blocked):
                failure = blocked.message
            }
        } catch let refusal as DuckBench.Refusal {
            failure = refusal.message
        } catch let error as DuckBench.ReadError {
            failure = error.message
        } catch {
            failure = error.localizedDescription
        }
    }

    /// One request to the bench, with the deadline eight rollouts of physics
    /// on a small board actually need. Both routes take it, so neither can
    /// quietly get a shorter one.
    private func ask(_ call: DuckBench.Call, _ armed: BenchEndpoint) async throws -> Data {
        var request = DuckBench.urlRequest(for: call, token: armed.token)
        request.timeoutInterval = 900
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    private func symbol(for state: Pipeline.State) -> String {
        switch state {
        case .done: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .waiting: return "circle"
        case .blocked: return "lock.circle"
        }
    }

    /// The token a stage's standing is drawn in.
    ///
    /// `success` AND `warning`, NOT GREEN AND ORANGE. The two are chosen to sit
    /// in the same desaturated register as the palette's inks rather than to
    /// look like system colours dropped in, and both are asserted at 4.5:1
    /// against every ground this app sets words on — which matters here because
    /// the colour lands on the word beside the glyph as well as on the glyph.
    ///
    /// WAITING AND BLOCKED SHARE A GREY, and that is the honest pairing: one is
    /// a stage nobody has done yet and the other is a stage nobody can do, and
    /// neither is a state the eye should be pulled to. The words separate them,
    /// which is the whole argument for having the words.
    private func colour(for state: Pipeline.State) -> Color {
        switch state {
        case .done: return Theme.success
        case .attention: return Theme.warning
        case .waiting: return Theme.textTertiary
        case .blocked: return Theme.textTertiary
        }
    }
}
