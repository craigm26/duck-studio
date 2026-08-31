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
                    ProgressView(value: pipeline.fractionDone)
                    Text(pipeline.next.map { "Next: \($0.name.lowercased())" }
                         ?? "Everything that can be done has been.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text(draft.name)
                }

                ForEach(pipeline.stages) { stage in
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbol(for: stage.state))
                                .foregroundStyle(colour(for: stage.state))
                                // THE STATE IS SAID IN COLOUR AND IN NOTHING
                                // ELSE. A tinted symbol beside a stage name is
                                // the only thing on this row that says whether
                                // the stage has happened, and colour is exactly
                                // what a screen reader does not get. The words
                                // come from StudioKit, where a test asserts
                                // them.
                                .accessibilityLabel(Text(stage.state.spoken))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stage.name).font(.subheadline.weight(.medium))
                                Text(stage.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if stage.name == "Run in physics" {
                            physicsControls(draft)
                        }
                        if stage.name == "Attested", draft.bench != nil {
                            NavigationLink {
                                ShareDestinationsView(title: draft.name,
                                                      file: nil, message: draft.name)
                            } label: {
                                Label("Share it with its result", systemImage: "square.and.arrow.up")
                                    .font(.footnote)
                            }
                        }
                    }
                }

                if let bench = draft.bench {
                    Section {
                        LabeledContent("Ran", value: bench.when.formatted(date: .abbreviated,
                                                                          time: .shortened))
                        LabeledContent("Bench", value: bench.bench)
                        LabeledContent("Policy", value: bench.policy)
                        LabeledContent("Upright", value: "\(bench.achieves) of \(bench.rollouts)")
                        if let height = bench.medianHeight {
                            LabeledContent("Ends at",
                                           value: String(format: "%.3f m", height))
                        }
                        if let rate = bench.peakJointRate {
                            LabeledContent("Peak joint rate",
                                           value: String(format: "%.1f rad/s", rate))
                        }
                        // NOT A LABELLED ROW. "Plant: the bench's own plant"
                        // read like a fact with a value, and for every result
                        // stored before today there is no value at all — the
                        // honest answer there is a sentence, not a blank and
                        // not a placeholder. Composed in StudioKit, where a
                        // test asserts it.
                        Text(bench.plantSentence)
                            .font(.caption).foregroundStyle(.secondary)
                    } header: {
                        Text("The run")
                    } footer: {
                        // "Standing height on THIS plant" was a claim about
                        // whichever world the run above happened in, and until
                        // today no run recorded one. The number was measured on
                        // the canon plant and the sentence now says so — in
                        // StudioKit, where a test asserts it letter by letter.
                        Text(Pipeline.standingHeightSaid)
                    }
                }
            } else {
                Text("That draft is gone.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sim to real")
        .navigationBarTitleDisplayMode(.inline)
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
            Button {
                Task { await run(draft) }
            } label: {
                HStack {
                    Label(draft.bench == nil ? "Run it in physics" : "Run it again",
                          systemImage: "play.circle")
                    if busy { Spacer(); ProgressView() }
                }
                .font(.footnote)
            }
            .disabled(busy || draft.keys.count < 2)
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.orange)
            }
            Text("Eight rollouts at different drop heights, because one that stays up proves very little — the four authored stair motions in this app get up their flight 0 times in 16.")
                .font(.caption2).foregroundStyle(.secondary)
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

    private func colour(for state: Pipeline.State) -> Color {
        switch state {
        case .done: return .green
        case .attention: return .orange
        case .waiting: return .secondary
        case .blocked: return .secondary
        }
    }
}
