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
///
/// THE WHOLE SCREEN IS `Theme.asked`, WHICH IS WHY THE HEADLINE FOOTER WEARS
/// IT. The palette's provenance rule is that teal is what a machine measured
/// and yellow is what somebody asked for; a training request is the largest
/// piece of "asked for" the app produces, and the one sentence that says so has
/// spent its life as small grey footer text under a green seal. It keeps its
/// place in the footer and gains the colour and the glyph, because a claim
/// about provenance that only reads as furniture is a claim nobody reads.
///
/// A GLYPH BESIDE EVERY VERDICT. The seal, the refusals and the open questions
/// each carry their own symbol, so none of them is a colour on its own — the
/// same rule `StateBadge` makes structurally true for a robot's state.
struct TrainingRequestView: View {
    let request: TrainingRequest
    /// The file itself drives the sheet — see `ExportedFile`. A flag beside an
    /// optional is what leaves a share sheet open and empty.
    @State private var outgoing: ExportedFile?
    @State private var failure: String?
    @State private var showingConfig = false

    var body: some View {
        List {
            Section {
                // WORTH TRAINING IS A RESULT; NOT WORTH TRAINING IS A REFUSAL.
                // The two used to be green and orange, which are the two colours
                // this palette does not have: `success` is the token for a thing
                // that came out right and `refused` is the token for a no, and
                // both are asserted at 4.5:1 on every ground the app sets words
                // on. The seal and the octagon are what carry it for anybody who
                // cannot separate the two hues.
                Label(request.isTrainable ? "Worth handing to a machine"
                                          : "Not worth handing to a machine",
                      systemImage: request.isTrainable ? "checkmark.seal" : "xmark.octagon")
                    .foregroundStyle(request.isTrainable ? Theme.success : Theme.refused)
                Text(request.summary).font(.footnote).foregroundStyle(Theme.textPrimary)
            } footer: {
                Label("Nothing here has been trained. A phone has no Python, no mjlab and no GPU — this is a specification for a machine that has all three.",
                      systemImage: "pencil.and.list.clipboard")
                    .foregroundStyle(Theme.asked)
            }
            .listRowBackground(Theme.surfacePrimary)

            if !request.refusals.isEmpty {
                Section {
                    // FATAL IS A REFUSAL AND THE REST ARE CAVEATS, drawn apart
                    // rather than drawn in one colour and a grey. The kit
                    // already separates them — `isFatal` is the whole
                    // distinction — and the screen used to answer it with
                    // orange for one and the system's secondary grey for the
                    // other, so a caveat looked like furniture.
                    ForEach(request.refusals, id: \.message) { refusal in
                        Label(refusal.message,
                              systemImage: refusal.isFatal ? "xmark.octagon" : "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(refusal.isFatal ? Theme.refused : Theme.warning)
                    }
                } header: {
                    SectionHeading(text: "What was checked")
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            Section {
                // NOT `TelemetryRow`, AND THE RULE IS THE COMPONENT'S OWN.
                // Monospace is a claim that a number will change; a fork's name,
                // its command block and its episode length are a specification
                // that sits still for the life of the request. `LabeledContent`
                // is the right shape for a fact that is not going anywhere.
                LabeledContent("Forks", value: request.base.rawValue)
                Text(request.base.summary).font(.caption).foregroundStyle(Theme.textSecondary)
                LabeledContent("Command", value: request.base.command)
                LabeledContent("Episode", value: String(format: "%g s", request.episodeSeconds))
            } header: {
                SectionHeading(text: "Starting point")
            } footer: {
                Text("A fork that feeds a phase-clock task a velocity is the classic way one of these fails, so the command block is written down rather than assumed.")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                ForEach(request.rewards) { reward in
                    VStack(alignment: .leading, spacing: Theme.spacing(.hairline) / 2) {
                        HStack {
                            // MONO ON A NAME THAT NEVER CHANGES, WHICH IS THE
                            // ONE EXEMPTION THE RULE HAS — the same one
                            // `RewardRow` takes in the recordings list, for the
                            // same reason and about the same content. A reward
                            // term is an identifier out of a training config,
                            // not a sentence, and its weight is read as part of
                            // the identifier rather than as a reading.
                            Text(reward.function)
                                .font(.footnote.monospaced())
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(String(format: "×%g", reward.weight))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(reward.reason).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            } header: {
                SectionHeading(text: "Rewards")
            } footer: {
                Text("Every one of these exists in mjlab_microduck/tasks/mdp.py. A config naming a function nobody wrote will not import, and a training machine is a slow place to find a typo.")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            if let prop = request.prop {
                Section {
                    LabeledContent("Object", value: prop.name)
                    LabeledContent("Weight", value: String(format: "%.0f g", prop.grams))
                    LabeledContent("Across", value: String(format: "%.0f mm",
                                                           prop.thicknessMillimetres))
                } header: {
                    SectionHeading(text: "What it is for")
                } footer: {
                    // NOT IN THE SCENE YET IS A CAVEAT ABOUT THE REQUEST, so it
                    // takes the caveat colour and a triangle rather than sitting
                    // in the same grey as the paragraphs that are merely
                    // explaining things.
                    Label("It is not in the training scene yet. The scene has a ball, blocks and cones; whoever runs this has to add the object first, and that is the first job rather than an afterthought.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warning)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            Section {
                Text(request.successCriterion).font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
            } header: {
                SectionHeading(text: "Success")
            }
            .listRowBackground(Theme.surfacePrimary)

            if !request.openQuestions.isEmpty {
                Section {
                    // AN OPEN QUESTION IS THE PUREST "ASKED, NOT MEASURED"
                    // THING ON THE SCREEN: nobody knows the answer, and the
                    // request is being handed over anyway. Yellow and a question
                    // mark, so it reads as an unknown rather than as a bullet.
                    ForEach(request.openQuestions, id: \.self) {
                        Label($0, systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.asked)
                    }
                } header: {
                    SectionHeading(text: "Open questions")
                } footer: {
                    Text("Carried into the file. A request that hides its assumptions gets run by somebody who does not share them.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)
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
                SectionHeading(text: "Hand it over")
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S GREY,
        // and every row keeps a real `surfacePrimary` card under it — which is
        // what `Theme` asks for in as many words: `backgroundSecondary` carries
        // the four inks between 4.17:1 and 4.27:1, short of the 4.5:1 body text
        // owes, so words go on a card and the card goes on the ground.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(request.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingConfig) {
            NavigationStack {
                ScrollView {
                    // MONO BECAUSE IT IS CODE. A config file is read as source
                    // — alignment and indentation carry meaning in it — which is
                    // the other half of the monospace rule: the claim is not
                    // only "this will change", it is also "this is literal
                    // text".
                    Text(request.envConfig())
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.spacing(.standard))
                }
                .background(Theme.backgroundPrimary)
                .navigationTitle(request.fileName)
                .navigationBarTitleDisplayMode(.inline)
                // The only read-only text sheet in the app without a way out.
                // A drag-down still works, but a sheet whose only exit is an
                // undiscoverable gesture is one people get stuck in.
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingConfig = false }
                    }
                }
            }
        }
        .sheet(item: $outgoing) { out in
            ShareSheet(items: [out.url]) { outgoing = nil }
        }
        .alert("That did not save",
               isPresented: .constant(failure != nil),
               presenting: failure) { _ in
            Button("OK") { failure = nil }
        } message: { Text($0) }
    }

    private func hand(over text: String, named name: String) {
        do {
            outgoing = ExportedFile(url: try ExportFile.write(Data(text.utf8), named: name))
        } catch let error as ExportFile.Failure {
            failure = error.message
        } catch {
            failure = "\(error)"
        }
    }
}
