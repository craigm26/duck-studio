import SwiftUI
import DuckKit
import StudioKit

/// Say what you want fetched; find out whether the duck can fetch it.
///
/// THIS IS THE HONEST SHAPE OF "TRAIN A NEW INTENT FROM A SENTENCE". A phone
/// cannot train a network — training is a rollout loop against a physics
/// engine, not a gradient anything here could take. But retrieval does not need
/// a new network: walking is `alpha_walking`, reaching down is
/// `alpha_ground_pick`, and the grasp is the fifteenth servo, which no policy
/// drives. The sentence composes skills the robot already has, and this screen
/// shows the composition rather than a progress bar over a lie.
///
/// THE REFUSALS ARE THE LESSON. Ask for a pencil and it says no, because the
/// jaw closes 20 mm above the floor and a 7 mm pencil passes underneath. Ask
/// for a carrot and it says no, because the lift was trained against 10–40 g.
/// Somebody who reads two refusals knows more about this robot than somebody
/// who watched a demo work.
struct RetrieveView: View {
    @State private var sentence = "fetch the stick 1 m away"
    @State private var sharing = false
    @State private var file: URL?

    private var reading: Retrieval.Reading { Retrieval.read(sentence) }
    private var plan: Retrieval.Plan { Retrieval.plan(for: reading.stick) }

    var body: some View {
        List {
            Section {
                TextField("What should it fetch?", text: $sentence, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Say it plainly")
            } footer: {
                Text("Try \"fetch the pencil\", \"drag the broom standing in the corner\", \"pick up the dowel 2 m away\". Weights, thicknesses and grip heights can be given outright — \"a 30 g stick 25 mm thick\", \"held 120 mm up\".")
            }

            if !reading.understood.isEmpty {
                Section("Read as") {
                    ForEach(reading.understood, id: \.self) { Text($0).font(.footnote) }
                }
            }
            if !reading.assumed.isEmpty {
                Section {
                    ForEach(reading.assumed, id: \.self) {
                        Label($0, systemImage: "questionmark.circle").font(.footnote)
                    }
                } header: {
                    Text("Guessed")
                } footer: {
                    Text("Estimates of YOUR object, not measurements of the robot. Say the number and the guess goes away.")
                }
            }

            Section {
                if plan.refusals.isEmpty {
                    Label("Inside every envelope.", systemImage: "checkmark.seal")
                        .font(.footnote).foregroundStyle(.green)
                }
                ForEach(plan.refusals, id: \.message) { refusal in
                    Label(refusal.message,
                          systemImage: refusal.isFatal ? "xmark.octagon" : "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(refusal.isFatal ? Color.orange : Color.secondary)
                }
            } header: {
                Text(plan.isPossible ? "It can do this" : "It cannot do this")
            }

            Section {
                ForEach(Array(plan.schedule.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%5.2f s", entry.start))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.step.label).font(.subheadline)
                            Text(entry.step.policy ?? "servo 9 — no policy drives the mouth")
                                .font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("The plan · \(String(format: "%.1f s", plan.seconds))")
            } footer: {
                Text("Two of these steps are the same ground pick, split at the moment the mouth is lowest.")
            }

            Section {
                measurement("Mouth at its lowest, open",
                            String(format: "%.1f mm", Retrieval.openTipHeight * 1000))
                measurement("With the jaw shut",
                            String(format: "%.1f mm", Retrieval.closedTipHeight * 1000))
                measurement("Grasp window",
                            String(format: "%.2f–%.2f s",
                                   Retrieval.graspWindow.lowerBound, Retrieval.graspWindow.upperBound))
                measurement("Lowest at", String(format: "%.2f s", Retrieval.graspInstant))
                measurement("Trained payload", "10–40 g")
                measurement("Mouth sweeps", String(format: "%.0f–%.0f mm through the arc",
                                                   Retrieval.Reach.lowestDuringPick * 1000,
                                                   Retrieval.Reach.highestDuringPick * 1000))
                if let height = reading.stick.graspHeightMillimetres,
                   let at = Retrieval.Reach.graspTime(forHeight: height / 1000) {
                    measurement(String(format: "Bite at %.0f mm", height),
                                String(format: "%.2f s into the pick", at))
                }
                measurement("Pull before its feet slide",
                            String(format: "%.1f N", Retrieval.Drag.pullBeforeSlipping(
                                footFriction: Retrieval.Drag.footFriction.lowerBound)))
                measurement("Pull before its neck stalls",
                            String(format: "%.1f N", Retrieval.Drag.pullBeforeNeckStalls))
                measurement("Pick runs for", String(format: "%.1f s of a %.0f s cycle",
                                                    Retrieval.pickDuration, Retrieval.phasePeriod))
            } header: {
                Text("Where the numbers come from")
            } footer: {
                Text("The two pull figures are CEILINGS, not demonstrations: the duck's 0.737 kg out of Pollen's MJCF, the ±0.6405 N⋅m training runs its joints at, the 0.084 m from the neck joint to the beak, and the 0.7–1.3 foot friction training randomises over. Nobody has measured this duck dragging anything, and a ceiling says what is impossible rather than what works.\n\nThe payload and the 4 s cycle are upstream's — sample_mouth_payload and GP_PERIOD in microduck_ground_pick_env_cfg.py, and GROUND_PICK_END_PHASE in robotd's control.rs. The mouth heights and the grasp window are measured here, through this app's kinematics over the recorded policy. They DISAGREE with the config's nominal hold of 1.50–1.70 s: the plant bottoms out at 1.16 s and is already climbing by 1.50. Closing the jaw on the config's window closes it on the way up.")
            }

            Section {
                Button {
                    save()
                } label: {
                    Label("Save as a .duck task", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("A task file carries the constraints in its own body, so it can be read and run somewhere this app is not — a task that travels without them is one somebody runs against a carrot.")
            }
        }
        .navigationTitle("Fetch something")
        .navigationBarTitleDisplayMode(.inline)
        // The house pattern: a flag and a file, rather than a retroactive
        // Identifiable on URL that every other module would then inherit.
        .sheet(isPresented: $sharing) {
            if let file { ShareSheet(items: [file]) }
        }
    }

    private func measurement(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).font(.footnote)
            Spacer()
            Text(value).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let title = reading.object.map { "Fetch the \($0)" } ?? "Fetch it"
        guard let task = try? plan.duckTask(named: title) else { return }
        file = ExportFile.write(task.encode(), named: "\(task.name).duck")
        sharing = file != nil
    }
}
