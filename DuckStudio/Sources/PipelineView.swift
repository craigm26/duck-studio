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

    private var draft: IntentDraft? { drafts.drafts.first { $0.id == draftID } }

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
            Text("Eight rollouts at different drop heights, because one that stays up proves very little — the four authored stair motions in this app get up their flight 0 times in 16.")
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
        busy = true; failure = nil
        defer { busy = false }
        do {
            guard let chosen = benches.selected else {
                failure = "No bench is set up, so there is nothing to run this on."
                return
            }
            let armed = benches.armed(chosen)
            let address = try armed.resolved()
            let track = draft.benchTrack
            guard track.count >= 2 else {
                failure = "A motion needs at least two keyframes to run."
                return
            }
            let call = try DuckBench.perform(address, keys: track,
                                             seconds: draft.duration + 0.5, rollouts: 8)
            var request = DuckBench.urlRequest(for: call, token: armed.token)
            // Eight rollouts of physics on a small board is not quick.
            request.timeoutInterval = 900
            let (data, _) = try await URLSession.shared.data(for: request)
            // THE PLANT IS READ, NEVER SUPPLIED. This used to hand
            // `readOutcome` a plant of its own — `readHealth` on a /perform
            // body, which cannot succeed because that body has no `bench` key,
            // falling back to the literal "the bench's own plant". Every stored
            // result in every install carries that string, and the screen
            // printed it in the same voice as the measured numbers beside it.
            // The bench now names its own world in the answer; if it does not,
            // the outcome says so instead of borrowing a name from here.
            let outcome = try DuckBench.readOutcome(data, when: Date())
            var updated = draft
            updated.bench = outcome
            drafts.save(updated)
        } catch let refusal as DuckBench.Refusal {
            failure = refusal.message
        } catch let error as DuckBench.ReadError {
            failure = error.message
        } catch {
            failure = error.localizedDescription
        }
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
