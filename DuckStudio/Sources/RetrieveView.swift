import SwiftUI
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
///
/// SO THE REFUSALS ARE DRAWN AS THE LESSON. A fatal refusal takes
/// `Theme.refused` and an octagon; a caveat takes `Theme.warning` and a
/// triangle; a sentence the reader could not make sense of takes the same
/// warning with a question mark, because nothing was refused — the reading
/// failed, not the duck. The three used to be orange, orange and the system's
/// secondary grey, which said that a caveat is furniture and that a robot
/// refusing a job is the same event as a parser shrugging.
///
/// THE CONSTANTS ARE NOT MONOSPACED AND THE SCHEDULE IS. "Where the numbers
/// come from" is a table of things about this robot that will be the same next
/// year — the mouth's lowest point, the trained payload, the pull before the
/// feet slide — and monospace is the app's claim that a number is going to
/// move. The schedule above it genuinely moves: change one word of the sentence
/// and every start time in it changes. That is the whole distinction
/// `TelemetryRow` is built around, applied here without the component, because
/// these rows are a reference table rather than a readout.
struct RetrieveView: View {
    /// Where a plan is kept on this phone.
    @ObservedObject var plans: PlanStore
    /// A plan being reopened from the Intents list, if this screen was pushed
    /// from one. The sentence it was written from comes back with it.
    var opening: DuckPlanFile?

    @State private var sentence = "fetch the stick 1 m away"
    /// Why the file could not be written. This screen refused things for a
    /// living and then had nothing to say when it was the one that failed.
    @State private var failure: String?
    /// Named after it is kept, so the screen can say so rather than going quiet.
    ///
    /// READ IN THE BODY, which is the whole point of it. It was written here
    /// and rendered nowhere for one revision: "Keep this plan" wrote a file,
    /// set this, and changed nothing on screen, so the only way to learn
    /// whether the headline button had worked was to leave for the Intents
    /// tab. A save that reports nothing is indistinguishable from a save that
    /// failed.
    @State private var kept: String?

    /// The measurement a REOPENED plan was kept with, until the sentence is
    /// edited.
    ///
    /// WITHOUT IT, REOPENING A PLAN SHOWS A DIFFERENT PLAN. `DuckPlanFile`
    /// stores the stick precisely so a kept plan cannot go stale, and this
    /// screen used to throw that away and re-derive everything from
    /// `Retrieval.read(asked)` — the sentence-only reader, with no `props:`.
    /// A plan drafted against a scene prop, or by a model that resolved the
    /// object itself, reopened as a DIFFERENT object: different grams,
    /// different thickness, sometimes `.notUnderstood`, whose own text calls
    /// the numbers below it invented. The words are still what somebody wants
    /// to edit, so they come back too — and the moment they are edited this
    /// clears and the sentence is in charge again.
    @State private var restored: Retrieval.Stick?

    /// The header over the unread verdict, named because the Save footer points
    /// the reader at it BY NAME. Two literals would be one rename away from a
    /// footer citing a heading that is not on the screen.
    private static let unreadHeader = "It did not find a thing to fetch"

    private var reading: Retrieval.Reading { Retrieval.read(sentence) }
    /// The measurement everything on this screen is about: the one the plan was
    /// kept with if this screen was opened from one, otherwise the sentence's.
    private var stick: Retrieval.Stick { restored ?? reading.stick }
    private var plan: Retrieval.Plan { Retrieval.plan(for: stick) }
    /// A reopened plan HAS a pinned-down object — it was measured when it was
    /// kept — so the unread state cannot apply to it, and neither can the
    /// caveats about guesses. Re-reading the sentence would decide otherwise.
    private var confidence: Retrieval.Reading.Confidence {
        restored != nil ? .understood : reading.confidence
    }

    /// Keep the plan in this app, in this app's own format.
    private func keep() {
        failure = nil
        // THE SECOND LOCK, WHICH THE DELETED EXPORT DOCUMENTED AS LOAD-BEARING.
        // `.disabled` is a statement about a control; this is a statement about
        // the file. Writing a plan whose object nobody read means writing this
        // app's invented 20 g / 20 mm dowel down as somebody's measurement.
        guard confidence != .notUnderstood else { return }
        let reading = Retrieval.plan(for: sentence)
        let noun = reading.reading.object ?? "it"
        // THE MEASUREMENT IS IN THE NAME, because `PlanStore.save` is keyed by
        // name and justifies that on "two plans with the same name are the same
        // plan re-measured". That holds only if a person chose the name, and
        // nobody does here. On the object word alone, "fetch the pencil" and
        // "fetch the pencil 4 m away, 30 mm thick" were both "Fetch the pencil"
        // and the second silently destroyed the first — everything that made
        // them different plans lived in the numbers this now prints.
        let composed = "Fetch the \(noun) · " + Self.measured(stick)
        // A REOPENED, UNEDITED PLAN IS THE SAME PLAN. `AutomationChatView`
        // titles a plan with the person's own sentence and this screen composes
        // noun plus measurement, so recomposing on the way back in files a
        // SECOND copy of a plan already in the list, under a name nobody chose.
        let title = restored != nil ? (opening?.name ?? composed) : composed
        // KEPT EVEN WHEN THE DUCK CANNOT DO IT. A refusal is a result — it is
        // the measured reason a fetch will not work — and somebody who wants to
        // come back and change the object should not have to retype it.
        let file = DuckPlanFile(name: title,
                                stick: stick,
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
        guard let opening else { return }
        // THE MEASUREMENT FIRST, and unconditionally: a plan kept without a
        // sentence still has one, and it is the half that cannot be re-derived.
        restored = opening.stick
        guard let asked = opening.asked, !asked.isEmpty else { return }
        sentence = asked
    }

    /// A stored measurement as rows, one number per line.
    private static func lines(_ stick: Retrieval.Stick) -> [String] {
        var rows = [String(format: "%.0f g", stick.grams),
                    String(format: "%.0f mm thick where the jaw closes", stick.thicknessMillimetres),
                    String(format: "%.2f m away", stick.metresAway),
                    String(format: "floor friction %.2f", stick.floorFriction)]
        if let height = stick.graspHeightMillimetres {
            rows.append(String(format: "held %.0f mm off the floor", height))
        } else {
            rows.append("lying on the floor")
        }
        return rows
    }

    /// A plan's measurement in one line, short enough for a row title.
    private static func measured(_ stick: Retrieval.Stick) -> String {
        var parts = [String(format: "%.0f g", stick.grams),
                     String(format: "%.0f mm", stick.thicknessMillimetres),
                     String(format: "%.1f m", stick.metresAway)]
        if let height = stick.graspHeightMillimetres {
            parts.append(String(format: "up %.0f mm", height))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        List {
            Section {
                TextField("What should it fetch?", text: $sentence, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
            } header: {
                SectionHeading(text: "Say it plainly")
            } footer: {
                Text("Try \"fetch the pencil\", \"drag the broom standing in the corner\", \"pick up the dowel 2 m away\". Weights, thicknesses and grip heights can be given outright — \"a 30 g stick 25 mm thick\", \"held 120 mm up\".")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            if let restored {
                Section {
                    // TEAL, BECAUSE SOMEBODY MEASURED THESE. `Theme.measured` is
                    // the palette's claim that a number came off a bench or out
                    // of the kinematics rather than out of a sentence, and a
                    // stored measurement is the one place on this screen where
                    // that is unambiguously true — the whole reason the file
                    // keeps the stick instead of re-reading the words.
                    ForEach(Self.lines(restored), id: \.self) {
                        Label($0, systemImage: "tray.and.arrow.down")
                            .font(.footnote)
                            .foregroundStyle(Theme.measured)
                    }
                } header: {
                    SectionHeading(text: "The measurement this plan was kept with")
                } footer: {
                    // NOT `reading.sentence`. That paragraph says which numbers
                    // came out of THESE words, and none of these did — they came
                    // out of the file. Printing it here is how a plan drafted
                    // against a scene prop came back reading "this app invented
                    // the thickness" about a thickness somebody measured.
                    Text("These are the numbers the plan was written with, not a re-reading of the words above. Edit the sentence and the app reads it again from scratch.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            if restored == nil, !reading.understood.isEmpty {
                Section {
                    ForEach(reading.understood, id: \.self) {
                        Text($0).font(.footnote).foregroundStyle(Theme.textPrimary)
                    }
                } header: {
                    SectionHeading(text: "Read as")
                }
                .listRowBackground(Theme.surfacePrimary)
            }
            if restored == nil, !reading.assumed.isEmpty {
                Section {
                    // A GUESS IS THE APP ASKING, NOT THE APP MEASURING, and
                    // `Theme.asked` is the token for exactly that. It sits one
                    // section above the numbers it produced, so the colour is
                    // the reader's warning that everything below inherits it.
                    ForEach(reading.assumed, id: \.self) {
                        Label($0, systemImage: "questionmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.asked)
                    }
                } header: {
                    SectionHeading(text: "Guessed")
                }
                .listRowBackground(Theme.surfacePrimary)
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
                switch confidence {
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
                    //
                    // A CAVEAT AND NOT A REFUSAL, WHICH IS WHY IT IS THE
                    // WARNING TOKEN RATHER THAN THE REFUSED ONE. Nothing said
                    // no here: the duck was never asked about anything, because
                    // no object came out of the sentence. `Theme.refused` would
                    // put a robot's verdict on a parser's shrug.
                    Label(reading.sentence, systemImage: "questionmark.circle")
                        .font(.footnote).foregroundStyle(Theme.warning)
                case .understood, .understoodWithGuesses:
                    if plan.refusals.isEmpty {
                        Label("Inside every envelope.", systemImage: "checkmark.seal")
                            .font(.footnote).foregroundStyle(Theme.success)
                    }
                }
                // THE REFUSALS STAY IN ALL THREE STATES. `.notUnderstood` and a
                // real refusal co-occur — "fetch the 0.4 kg thing" names no thing
                // AND is over the trained payload — and that refusal is about the
                // person's own 400 g, so it is true and theirs. Dropping it to
                // keep the state tidy would be a second lie pointing the other
                // way.
                //
                // FATAL IS REFUSED; THE REST ARE CAVEATS. Both already carried
                // their own glyph, which is what made the old colouring so
                // strange: the octagon was orange and the triangle was the
                // system's secondary grey, so a caveat about a robot's limit was
                // drawn in the same ink as a footnote about where a file goes.
                ForEach(plan.refusals, id: \.message) { refusal in
                    Label(refusal.message,
                          systemImage: refusal.isFatal ? "xmark.octagon" : "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(refusal.isFatal ? Theme.refused : Theme.warning)
                }
            } header: {
                // NOT "It cannot do this" IN THE UNREAD STATE. That is a verdict
                // on the robot's envelope, and `plan.isPossible` is genuinely
                // true for the invented 20 g / 20 mm object — flipping it would
                // trade one false statement for another. The honest header says
                // what actually happened: the reading failed, not the duck.
                if confidence == .notUnderstood {
                    SectionHeading(text: Self.unreadHeader)
                } else {
                    SectionHeading(text: plan.isPossible ? "It can do this" : "It cannot do this")
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
                if confidence != .notUnderstood {
                    Text(reading.sentence).foregroundStyle(Theme.textSecondary)
                }
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                ForEach(Array(plan.schedule.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
                        // MONO, AND HERE IT IS EARNED. Every start time in this
                        // schedule is recomputed from the sentence, so they
                        // change while somebody types — which is the claim
                        // tabular figures make, and the alignment is what lets a
                        // reader see that two steps are the same ground pick
                        // split at the moment the mouth is lowest.
                        Text(String(format: "%5.2f s", entry.start))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                        VStack(alignment: .leading, spacing: Theme.spacing(.hairline) / 4) {
                            Text(entry.step.label)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            // A POLICY'S FILENAME IS AN IDENTIFIER, which is the
                            // one exemption the monospace rule has and the same
                            // one the recordings list takes for a reward term.
                            Text(entry.step.policy ?? "servo 9 — no policy drives the mouth")
                                .font(.caption2.monospaced())
                                .foregroundStyle(Theme.textSecondary)
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
                if confidence == .notUnderstood {
                    SectionHeading(text: "The plan for the guessed object · \(String(format: "%.1f s", plan.seconds))")
                } else {
                    SectionHeading(text: "The plan · \(String(format: "%.1f s", plan.seconds))")
                }
            } footer: {
                Text("Two of these steps are the same ground pick, split at the moment the mouth is lowest.")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

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
                if let height = stick.graspHeightMillimetres,
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
                SectionHeading(text: "Where the numbers come from")
            } footer: {
                Text("The two pull figures are CEILINGS, not demonstrations: the duck's 0.737 kg out of Pollen's MJCF, the ±0.6405 N⋅m training runs its joints at, the 0.084 m from the neck joint to the beak, and the 0.7–1.3 foot friction training randomises over. Nobody has measured this duck dragging anything, and a ceiling says what is impossible rather than what works.\n\nThe payload and the 4 s cycle are upstream's — sample_mouth_payload and GP_PERIOD in microduck_ground_pick_env_cfg.py, and GROUND_PICK_END_PHASE in robotd's control.rs. The mouth heights and the grasp window are measured here, through this app's kinematics over the recorded policy. They DISAGREE with the config's nominal hold of 1.50–1.70 s: the plant bottoms out at 1.16 s and is already climbing by 1.50. Closing the jaw on the config's window closes it on the way up.")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                // THERE IS ONE BUTTON NOW. This screen used to offer only an
                // export — a quackd task file this app could not read back — so
                // a plan worked out here could not be returned to, and
                // re-importing one was answered with "nothing was added". A plan
                // is a thing the app holds; the export is gone with quackd.
                Button {
                    keep()
                } label: {
                    Label("Keep this plan", systemImage: "tray.and.arrow.down")
                }
                // DISABLED RATHER THAN ENABLED AND REFUSING, because a control
                // that cannot work says so before it is pressed. The reason is in
                // the footer below it; the full explanation is the paragraph
                // further up, and repeating it here would be the third copy of a
                // 400-character sentence on one screen.
                .disabled(confidence == .notUnderstood)
                if let kept {
                    // A FILE THAT IS ON THE PHONE IS A RESULT, so it takes the
                    // success token — the only one on this screen, beside a
                    // verdict that is only ever a claim about an envelope.
                    Label("Kept as \"\(kept)\" — it is in your Motions, under Plans.",
                          systemImage: "checkmark.circle")
                        .font(.footnote).foregroundStyle(Theme.success)
                }
            } footer: {
                if confidence == .notUnderstood {
                    // NO PHYSICAL CLAIM IN HERE ON PURPOSE. Which numbers are
                    // whose is StudioKit's sentence to make — it is on the
                    // screen already, and it differs between a sentence that
                    // gave a weight and one that gave nothing. This footer only
                    // says why the button is off and where to read the rest.
                    Text("Nothing to write down: no thing to fetch was read out of your sentence. See \"\(Self.unreadHeader)\" above.")
                        .foregroundStyle(Theme.warning)
                } else {
                    // WHAT THE BUTTON ACTUALLY DOES. This sentence outlived the
                    // control it described: it promised a task file that travels
                    // and gets "run somewhere this app is not", one line under a
                    // confirmation saying the plan is in your Motions. The only
                    // control here writes a `.duckplan` into Application Support.
                    // Nothing leaves the phone.
                    Text("This plan is kept on this phone, in this app's own format, and it appears in your Motions under Plans. The file holds the MEASUREMENT, not the steps — the schedule above is worked out again from those numbers every time the plan is opened, so a kept plan cannot go stale and start disagreeing with the app that opens it.")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        // EVERY ROW ON A CARD, AND THE CARDS ON THE RECESSED GROUND — the
        // arrangement `Theme` asks for in as many words, because the four inks
        // land short of 4.5:1 against `backgroundSecondary` and clear it against
        // `surfacePrimary`.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Fetch something")
        .navigationBarTitleDisplayMode(.inline)
        .task { restoreIfOpening() }
        // A CONFIRMATION IS ABOUT WHAT WAS ON SCREEN WHEN IT WAS PRESSED. Leave
        // "Kept as …" standing over an edited sentence and it claims a plan
        // nobody wrote.
        .onChange(of: sentence) { _, now in
            kept = nil
            // NOT ON THE RESTORE ITSELF, and the reason is subtle enough that
            // the decision lives in StudioKit under test rather than here:
            // `restoreIfOpening` runs from `.task`, so putting the stored
            // sentence back IS a change to this hook, and clearing `restored`
            // unconditionally threw the measurement away one update after
            // putting it there — leaving the screen re-deriving from the
            // sentence exactly as before, with the section that shows the
            // stored measurement unreachable.
            if !Retrieval.shouldKeepStoredMeasurement(sentence: now,
                                                      asked: opening?.asked) {
                restored = nil
            }
        }
        .alert("That did not save",
               isPresented: .constant(failure != nil),
               presenting: failure) { _ in
            Button("OK") { failure = nil }
        } message: { Text($0) }
    }

    /// One row of the reference table: what the robot is, beside the number.
    ///
    /// NOT MONOSPACED, AND THAT IS THE POINT OF THE ROW. `TelemetryRow` states
    /// the rule these numbers fail: monospace is a claim, and the claim is
    /// "this will change". The mouth's lowest point, the trained payload and
    /// the pull before the feet slide are constants of a robot — set them in
    /// tabular figures and the app is telling the reader to watch a thing that
    /// is never going to move, which is exactly the habit that makes the
    /// schedule's timings above stop meaning anything.
    ///
    /// AT AN ACCESSIBILITY SIZE IT STACKS, for the reason the component gives:
    /// two columns of text at AX5 is a fight for the width that the right-hand
    /// one always loses, so the app would hide the number from the person who
    /// enlarged it in order to read it. The pair is one element to VoiceOver
    /// because it is one fact.
    private func measurement(_ name: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
                Text(name).font(.footnote).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.spacing(.tight))
                Text(value).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(name).font(.footnote).foregroundStyle(Theme.textPrimary)
                Text(value).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

}
