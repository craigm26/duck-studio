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

    @AppStorage("duckbench.address") private var addressText = ""
    @State private var busy = false
    @State private var failure: String?

    private var draft: IntentDraft? { drafts.drafts.first { $0.id == draftID } }

    private var pipeline: Pipeline? {
        draft.map {
            Pipeline.of($0, bench: $0.bench, hasBench: !addressText.isEmpty)
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
                        LabeledContent("Plant", value: bench.plant)
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
                    } header: {
                        Text("The run")
                    } footer: {
                        Text("Standing height on this plant is \(String(format: "%.3f", Pipeline.standingHeight)) m — what the standing policy holds when it is simply left alone. A motion that ends much below that stayed up without standing up.")
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
        if addressText.isEmpty {
            NavigationLink {
                RemoteRunView(scenes: scenes, drafts: drafts)
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

    private func run(_ draft: IntentDraft) async {
        busy = true; failure = nil
        defer { busy = false }
        do {
            let address = try DuckBench.address(addressText)
            let track = draft.benchTrack
            guard track.count >= 2 else {
                failure = "A motion needs at least two keyframes to run."
                return
            }
            let call = try DuckBench.perform(address, keys: track,
                                             seconds: draft.duration + 0.5, rollouts: 8)
            var request = DuckBench.urlRequest(for: call)
            // Eight rollouts of physics on a small board is not quick.
            request.timeoutInterval = 900
            let (data, _) = try await URLSession.shared.data(for: request)
            let health = try? DuckBench.readHealth(data)
            let outcome = try DuckBench.readOutcome(
                data, when: Date(), plant: health?.plant ?? "the bench's own plant")
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
