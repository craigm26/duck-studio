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
    /// Where a plan is kept when it is saved into the app rather than exported.
    @ObservedObject var plans: PlanStore
    /// A plan being reopened from the Intents list, if this screen was pushed
    /// from one. The sentence it was written from comes back with it.
    var opening: DuckPlanFile?

    @State private var sentence = "fetch the stick 1 m away"
    /// PRESENTED ON THE FILE ITSELF, NOT ON A FLAG BESIDE IT. The pair this
    /// replaced — a `Bool` and a `URL?` — let `.sheet` reach a state where it
    /// was open and the file was not there, which renders as a blank card with
    /// nothing on it and no way out. `ExportedFile` makes that state
    /// unrepresentable.
    @State private var outgoing: ExportedFile?
    /// Why the file could not be written. This screen refused things for a
    /// living and then had nothing to say when it was the one that failed.
    @State private var failure: String?
    /// Named after it is kept, so the screen can say so rather than going quiet.
    @State private var kept: String?

    /// The header over the unread verdict, named because the Save footer points
    /// the reader at it BY NAME. Two literals would be one rename away from a
    /// footer citing a heading that is not on the screen.
    private static let unreadHeader = "It did not find a thing to fetch"

    private var reading: Retrieval.Reading { Retrieval.read(sentence) }
    private var plan: Retrieval.Plan { Retrieval.plan(for: reading.stick) }

    /// Keep the plan in this app, in this app's own format.
    private func keep() {
        failure = nil
        let reading = Retrieval.plan(for: sentence)
        // THE SAME NAME THE EXPORT USES, so a plan kept here and a plan
        // exported are recognisably the same thing.
        let title = reading.reading.object.map { "Fetch the \($0)" } ?? "Fetch it"
        // KEPT EVEN WHEN THE DUCK CANNOT DO IT. A refusal is a result — it is
        // the measured reason a fetch will not work — and somebody who wants to
        // come back and change the object should not have to retype it.
        let file = DuckPlanFile(name: title,
                                stick: reading.plan.stick,
                                asked: sentence,
                                provenance: "Written here")
        guard plans.save(file) else {
            failure = "That plan could not be written to this phone."
            return
        }
        kept = file.name
    }

    /// Restore the sentence a reopened plan was written from, once.
    ///
    /// THE SENTENCE, NOT THE PLAN. `DuckPlanFile` stores the measurement and
    /// derives the plan; this screen derives it from a sentence. Putting the
    /// words back is what makes the two agree, and it is also the thing
    /// somebody wants to edit.
    private func restoreIfOpening() {
        guard let opening, let asked = opening.asked, !asked.isEmpty else { return }
        sentence = asked
    }

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
                }
                // THE FOOTER THAT USED TO SIT HERE IS NOW `reading.sentence`, ONE
                // SECTION DOWN. It read "Estimates of YOUR object, not
                // measurements of the robot" — almost word for word what
                // StudioKit now composes, and a lie in the one state that matters
                // most: when the sentence named nothing, these are not estimates
                // of YOUR object, they are an object this app made up. Two copies
                // of a claim drift; this one had already drifted into being false.
                // It moves rather than doubles because the same paragraph printed
                // twice on one screen is its own kind of noise.
            }

            Section {
                switch reading.confidence {
                case .notUnderstood:
                    // WHERE THE GREEN SEAL USED TO GO UNCONDITIONALLY, AND THE
                    // LINE IN THE BUG REPORT. "Inside every envelope." is a claim
                    // about an object, and in this state there is no object — the
                    // thickness the grasp was checked against is
                    // `assumedThicknessMillimetres`, which is exactly
                    // `closedTipHeight * 1000` against a strict `<`, so nothing
                    // was ever tested and a seal would be a measurement of the
                    // app's own default. The words are StudioKit's, pinned by
                    // test; this file only decides that they go here, above the
                    // schedule they call "below".
                    Label(reading.sentence, systemImage: "questionmark.circle")
                        .font(.footnote).foregroundStyle(.orange)
                case .understood, .understoodWithGuesses:
                    if plan.refusals.isEmpty {
                        Label("Inside every envelope.", systemImage: "checkmark.seal")
                            .font(.footnote).foregroundStyle(.green)
                    }
                }
                // THE REFUSALS STAY IN ALL THREE STATES. `.notUnderstood` and a
                // real refusal co-occur — "fetch the 0.4 kg thing" names no thing
                // AND is over the trained payload — and that refusal is about the
                // person's own 400 g, so it is true and theirs. Dropping it to
                // keep the state tidy would be a second lie pointing the other
                // way.
                ForEach(plan.refusals, id: \.message) { refusal in
                    Label(refusal.message,
                          systemImage: refusal.isFatal ? "xmark.octagon" : "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(refusal.isFatal ? Color.orange : Color.secondary)
                }
            } header: {
                // NOT "It cannot do this" IN THE UNREAD STATE. That is a verdict
                // on the robot's envelope, and `plan.isPossible` is genuinely
                // true for the invented 20 g / 20 mm object — flipping it would
                // trade one false statement for another. The honest header says
                // what actually happened: the reading failed, not the duck.
                if reading.confidence == .notUnderstood {
                    Text(Self.unreadHeader)
                } else {
                    Text(plan.isPossible ? "It can do this" : "It cannot do this")
                }
            } footer: {
                // THE VERDICT AND THE CAVEAT SHARE A SECTION IN THE TWO STATES
                // THAT HAVE A VERDICT, so the seal cannot be read on its own.
                // With guesses this is the line that stops a green checkmark
                // above an estimated weight from reading as a measurement; when
                // everything came out of the sentence it says so. In
                // `.notUnderstood` there is no footer, because the same sentence
                // is already the row above — it is rendered EXACTLY ONCE per
                // state, and it is a paragraph, not a line.
                if reading.confidence != .notUnderstood {
                    Text(reading.sentence)
                }
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
                // THE SCHEDULE IS SHOWN IN ALL THREE STATES, AND IN THE UNREAD
                // ONE IT IS LABELLED. Hiding it would leave `reading.sentence`
                // pointing at nothing — it says "the plan below is about an
                // invented 20 g object" by name — and the timings are real
                // kinematics either way. What is not real is who they are about,
                // so the header says whose object it is rather than letting a
                // 22.8 s schedule pass for an answer. "Guessed" is the word the
                // section two rows up uses, and it is true in both halves of this
                // state: the weight may be the person's, the thickness never is.
                if reading.confidence == .notUnderstood {
                    Text("The plan for the guessed object · \(String(format: "%.1f s", plan.seconds))")
                } else {
                    Text("The plan · \(String(format: "%.1f s", plan.seconds))")
                }
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
                // KEEPING IT COMES FIRST, EXPORTING SECOND. This screen used to
                // offer only the export — a quackd task file this app cannot
                // read back — so a plan somebody worked out here could not be
                // returned to, and re-importing one was answered with "nothing
                // was added". A plan is now a thing the app holds.
                Button {
                    keep()
                } label: {
                    Label("Keep this plan", systemImage: "tray.and.arrow.down")
                }
                Button {
                    save()
                } label: {
                    Label("Export as a .duck task", systemImage: "square.and.arrow.up")
                }
                // DISABLED RATHER THAN ENABLED AND REFUSING, because a control
                // that cannot work says so before it is pressed. The reason is in
                // the footer below it; the full explanation is the paragraph
                // further up, and repeating it here would be the third copy of a
                // 400-character sentence on one screen.
                .disabled(reading.confidence == .notUnderstood)
            } footer: {
                if reading.confidence == .notUnderstood {
                    // NO PHYSICAL CLAIM IN HERE ON PURPOSE. Which numbers are
                    // whose is StudioKit's sentence to make — it is on the
                    // screen already, and it differs between a sentence that
                    // gave a weight and one that gave nothing. This footer only
                    // says why the button is off and where to read the rest.
                    Text("Nothing to write down: no thing to fetch was read out of your sentence. See \"\(Self.unreadHeader)\" above.")
                } else {
                    Text("A task file carries the constraints in its own body, so it can be read and run somewhere this app is not — a task that travels without them is one somebody runs against a carrot.")
                }
            }
        }
        .navigationTitle("Fetch something")
        .navigationBarTitleDisplayMode(.inline)
        // The house pattern, which the three export screens that always worked
        // were already using: present on the value, and put the sheet down
        // again when UIKit says the share is over.
        .sheet(item: $outgoing) { out in
            ShareSheet(items: [out.url]) { outgoing = nil }
        }
        .alert("That did not save",
               isPresented: .constant(failure != nil),
               presenting: failure) { _ in
            Button("OK") { failure = nil }
        } message: { Text($0) }
    }

    private func measurement(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).font(.footnote)
            Spacer()
            Text(value).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    /// EVERY EXIT SAYS SOMETHING. The first version had two that did not: a
    /// `try?` that dropped a `DuckTask.ReadError` carrying a written-out
    /// message, and a `nil` from the writer that left the button looking
    /// pressed and inert. Both are the failure this app exists to explain.
    private func save() {
        // REFUSE THE EXPORT RATHER THAN LABEL THE FILE, and the choice is
        // forced by what the file is. A `.duck` is not a screenshot: the
        // frontmatter a runner acts on carries this plan's verbs and budgets,
        // and the body asserts "20 g, 20 mm thick, 1.00 m away" as facts about
        // the object under "## This object". Those numbers came out of
        // `assumedGrams`/`assumedThicknessMillimetres`, not out of anybody's
        // sentence, so the file would state a measurement nobody took — and the
        // footer directly above this button promises the file carries its
        // constraints in its own body. A warning line in the body does not fix
        // it either: quackd's executor reads the body, but the machine half
        // would still say fetch, and the constraint text would still be about
        // an invented object. There is nothing here to write a true file about.
        //
        // The button is `.disabled` in this state, so this is a second lock
        // rather than the visible refusal — it is the one that holds if a caller
        // ever reaches `save()` some other way. `failure` raises the alert, so
        // it is not a silent exit; the words are the same StudioKit sentence the
        // screen is already showing.
        guard reading.confidence != .notUnderstood else {
            failure = reading.sentence
            return
        }
        // THE `?? "Fetch it"` FALLBACK IS LIVE, NOT DEAD, and the guard above
        // does not cover it: "fetch the thing 25 mm thick 2 m away" gives a
        // thickness outright, so it is understood, and still names no object.
        let title = reading.object.map { "Fetch the \($0)" } ?? "Fetch it"
        do {
            let task = try plan.duckTask(named: title)
            outgoing = ExportedFile(url: try ExportFile.write(task.encode(),
                                                              named: "\(task.name).duck"))
        } catch let error as DuckTask.ReadError {
            failure = error.message
        } catch let error as ExportFile.Failure {
            failure = error.message
        } catch {
            failure = "\(error)"
        }
    }
}
