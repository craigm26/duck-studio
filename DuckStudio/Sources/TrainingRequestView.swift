import SwiftUI
import StudioKit

/// A request to train a new policy: what to fork, what to reward, what nobody
/// knows yet.
///
/// NOTHING ON THIS SCREEN TRAINS ANYTHING, and the screen says so before it
/// says anything else. Training is a rollout loop against a physics engine with
/// thousands of parallel environments; this phone has no Python, no mjlab and
/// no GPU. What it can do is write the request and check it — so "lift two
/// kilos" is refused in a second by arithmetic rather than after a day of
/// training that was never going to converge.
struct TrainingRequestView: View {
    let request: TrainingRequest
    @State private var sharing = false
    @State private var file: URL?
    @State private var showingConfig = false

    var body: some View {
        List {
            Section {
                Label(request.isTrainable ? "Worth handing to a machine"
                                          : "Not worth handing to a machine",
                      systemImage: request.isTrainable ? "checkmark.seal" : "xmark.octagon")
                    .foregroundStyle(request.isTrainable ? Color.green : Color.orange)
                Text(request.summary).font(.footnote)
            } footer: {
                Text("Nothing here has been trained. A phone has no Python, no mjlab and no GPU — this is a specification for a machine that has all three.")
            }

            if !request.refusals.isEmpty {
                Section("What was checked") {
                    ForEach(request.refusals, id: \.message) { refusal in
                        Label(refusal.message,
                              systemImage: refusal.isFatal ? "xmark.octagon" : "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(refusal.isFatal ? Color.orange : Color.secondary)
                    }
                }
            }

            Section {
                LabeledContent("Forks", value: request.base.rawValue)
                Text(request.base.summary).font(.caption).foregroundStyle(.secondary)
                LabeledContent("Command", value: request.base.command)
                LabeledContent("Episode", value: String(format: "%g s", request.episodeSeconds))
            } header: {
                Text("Starting point")
            } footer: {
                Text("A fork that feeds a phase-clock task a velocity is the classic way one of these fails, so the command block is written down rather than assumed.")
            }

            Section {
                ForEach(request.rewards) { reward in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(reward.function).font(.footnote.monospaced())
                            Spacer()
                            Text(String(format: "×%g", reward.weight))
                                .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(reward.reason).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Rewards")
            } footer: {
                Text("Every one of these exists in mjlab_microduck/tasks/mdp.py. A config naming a function nobody wrote will not import, and a training machine is a slow place to find a typo.")
            }

            if let prop = request.prop {
                Section {
                    LabeledContent("Object", value: prop.name)
                    LabeledContent("Weight", value: String(format: "%.0f g", prop.grams))
                    LabeledContent("Across", value: String(format: "%.0f mm",
                                                           prop.thicknessMillimetres))
                } header: {
                    Text("What it is for")
                } footer: {
                    Text("It is not in the training scene yet. The scene has a ball, blocks and cones; whoever runs this has to add the object first, and that is the first job rather than an afterthought.")
                }
            }

            Section("Success") {
                Text(request.successCriterion).font(.footnote)
            }

            if !request.openQuestions.isEmpty {
                Section {
                    ForEach(request.openQuestions, id: \.self) {
                        Label($0, systemImage: "questionmark.circle").font(.caption)
                    }
                } header: {
                    Text("Open questions")
                } footer: {
                    Text("Carried into the file. A request that hides its assumptions gets run by somebody who does not share them.")
                }
            }

            Section {
                Button {
                    showingConfig = true
                } label: {
                    Label("Read the config it would write", systemImage: "doc.plaintext")
                }
                Button {
                    hand(over: request.envConfig(), named: request.fileName)
                } label: {
                    Label("Send the config", systemImage: "square.and.arrow.up")
                }
                Button {
                    hand(over: request.brief(), named: "\(request.slug).md")
                } label: {
                    Label("Send the brief", systemImage: "doc.richtext")
                }
            } header: {
                Text("Hand it over")
            }
        }
        .navigationTitle(request.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingConfig) {
            NavigationStack {
                ScrollView {
                    Text(request.envConfig())
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(request.fileName)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $sharing) {
            if let file { ShareSheet(items: [file]) }
        }
    }

    private func hand(over text: String, named name: String) {
        file = ExportFile.write(Data(text.utf8), named: name)
        sharing = file != nil
    }
}
