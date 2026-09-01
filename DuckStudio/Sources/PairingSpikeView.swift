import SwiftUI
import UIKit
import StudioKit

/// The phone spike Pollen's roadmap says their app is blocked on.
///
/// THIS SCREEN EXISTS TO BRING BACK AN ANSWER, NOT A VERDICT. §5.5 of their
/// app-path design records the encrypted read HANGING on macOS — "no prompt, no
/// error, no retry" — and the flag that would turn encryption on ships off
/// because of it, which is why "every robot running this has wifi credentials
/// and a PIN readable by a bystander". Nobody has yet watched a real iPhone try
/// it, and iOS raises a pairing sheet in places macOS does not. Either answer
/// moves them forward.
///
/// EVERY ROW HERE IS DRAWN, NOT DECIDED. What a step is called, what reaching it
/// proves, what failing it would mean, how long it is allowed and why, what an
/// outcome reads as and what a finished run means all come out of
/// `PairingSpike`, where `swift test` asserts them. This file chooses icons,
/// colours and where things sit.
///
/// THE TWO THINGS IT DOES THAT NO API COULD. It asks whether iOS showed the
/// pairing prompt, and it asks whether `btd` was started with
/// `--require-pairing` on. Neither is observable from inside a client — the
/// pairing sheet belongs to the system and nothing tells an app it appeared,
/// and nothing in an advertisement, a GATT table or an RPC answer says how the
/// daemon was launched. Both are recorded as what a person said, and the report
/// says so in those words.
///
/// FOUR ENDINGS, AND NOW FOUR WORDS FOR THEM. The whole contribution turns on
/// nobody mistaking a silence for a refusal, and until this restyle that
/// distinction was carried by a green tick against an orange cross against a red
/// clock — which is to say, by colour, to the roughly one man in twelve who
/// cannot separate those (SC 1.4.1). Every step now wears a `StateBadge`: a dot
/// AND the word beside it. The kit's own `Outcome.line` still sits underneath
/// wherever it says something the badge cannot, because that line is where a
/// refusal and a silence are kept apart in Pollen's terms rather than this
/// app's, and it is the text somebody pastes into an issue.
struct PairingSpikeView: View {

    /// Its own scanner, not the one `FindDuckView` holds. The everyday screen's
    /// state machine stops at the first failure; this one must not, and two
    /// screens sharing one radio would have had to agree about that.
    @StateObject private var scanner = DuckLinkScanner()

    /// The PIN `system.authenticate` will be given. Editable because a
    /// provisioned duck has stopped answering to the factory one, and a spike
    /// that could only ever try `000000` would bring back a refusal that says
    /// nothing about pairing.
    @State private var pin = PairingSpike.factoryPIN

    /// A PERSON'S ANSWER, AND THE EASIEST WAY TO PRODUCE A FALSE GREEN.
    ///
    /// Nothing reachable from this phone reveals how `btd` was launched, so this
    /// is asked. It defaults OFF because that is the state §5.5 says ships — "the
    /// flag is `--require-pairing` and it is **off**" — and because off is the
    /// answer that makes the kit's reading refuse to be encouraging: a read that
    /// sails through an unencrypted characteristic proves the pipe works and
    /// nothing whatsoever about pairing. Defaulting it on would let a tester who
    /// never touched the flag file a report claiming the blocker was cleared.
    @State private var requirePairing = false

    /// Rebuilt when the run ends and whenever the person changes an answer,
    /// rather than on every redraw — a report whose numbers moved while somebody
    /// read it would be a small lie in a document whose only value is that it
    /// can be trusted.
    @State private var run: PairingSpike.Run?

    @State private var outgoing: ExportedFile?
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                // THE KIT'S SENTENCE, NOT ONE WRITTEN HERE. What this spike is
                // for is a claim about Pollen's blocker and their protocol, and
                // a claim like that written in a view is a claim nothing tests.
                Text(PairingSpike.whatThisIsFor)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            if let radio = scanner.radio {
                Section {
                    // A WARNING AND NOT A REFUSAL. Nothing said no; the radio is
                    // off, or this app has not been allowed to use it, and both
                    // of those are things the person can go and fix.
                    Label(radio, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            setupSection
            ducksSection
            if started { stepsSection }
            if readResolved { promptSection }
            if scanner.spikeFinished { reportSection }
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S GREY,
        // and every row keeps a real `surfacePrimary` card under it — so no word
        // on this screen is set on `backgroundSecondary`, which the palette
        // documents as short of 4.5:1 for the four inks.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Pairing spike")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // THE EYE IS OPEN ONLY IF THE CONNECT STEP SAID SO, which is the
                // one claim about the link this screen can actually make. It
                // does not open when the run ends: a run that ends is not a run
                // that succeeded, and that confusion is the exact thing this
                // whole screen is built to prevent.
                LensIndicator(state: linkState)
            }
        }
        // WARMED BEFORE THE FIRST EVENT, NOT AT IT. The taptic engine spins up
        // on demand and the first tap of a session lands after the thing it is
        // about, which teaches the person that the buzz and the run are
        // unrelated.
        .task { Haptic.prepare() }
        .onDisappear { scanner.stopSpike() }
        .onChange(of: scanner.spikeFinished) { _, finished in
            refreshRun()
            // SOMETHING THE PERSON ASKED FOR RAN TO THE END — which is what
            // `Haptic.finished` means, and is not a claim that it went well. A
            // run that ends in eight timeouts is still a run that ended, and the
            // person is looking at the duck rather than at the phone.
            if finished { Haptic.finished() }
        }
        .onChange(of: scanner.pairingPrompt) { _, _ in refreshRun() }
        .onChange(of: requirePairing) { _, _ in refreshRun() }
        // ASKED ONCE, THE MOMENT THE READ RESOLVES, because that is while the
        // person still remembers. There is no CoreBluetooth API that reports
        // this: the pairing sheet is raised by the system, outside the app, and
        // an app is not told that it appeared, that it was accepted or that it
        // was dismissed. So the question is asked out loud and the answer is
        // recorded as an answer.
        .alert("Did iOS ask you to pair?", isPresented: $scanner.askingAboutPairingPrompt) {
            Button("Yes, it asked") { scanner.answerPairingPrompt(true) }
            Button("No, nothing appeared") { scanner.answerPairingPrompt(false) }
            Button("I'm not sure", role: .cancel) { scanner.answerPairingPrompt(nil) }
        } message: {
            Text(Self.promptQuestion)
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

    /// Whether a run has begun, so the step list only appears once there is
    /// something to say.
    private var started: Bool { scanner.spikeStep != nil || !scanner.spikeOutcomes.isEmpty }

    /// Whether the read step has ended, however it ended.
    ///
    /// THE QUESTION APPEARS ONLY AFTER THE READ, because before it there is
    /// nothing to have seen: the read is what requires a bond and therefore what
    /// raises the prompt. A control asking about a pairing sheet while the phone
    /// is still scanning would invite an answer about nothing.
    private var readResolved: Bool { scanner.spikeOutcomes[.readVersion] != nil }

    /// What the lens in the toolbar is doing.
    ///
    /// `isOK` IS THE KIT'S OWN PREDICATE, so the eye and the report agree about
    /// what counts as a link. Anything else — refused, timed out, never
    /// reached — leaves the eye closed, which is the honest picture.
    private var linkState: LensIndicator.Connection {
        if scanner.spikeStep != nil { return .connecting }
        return (scanner.spikeOutcomes[.connect]?.isOK ?? false) ? .connected : .asleep
    }

    /// Why the app has to ask rather than measure. It is a fact about iOS, which
    /// is this target's own subject — the robot and the protocol are the kit's.
    private static let promptQuestion =
        "iOS raises the pairing sheet itself and tells the app nothing about it — not that it "
      + "appeared, not that it was accepted, not that it was dismissed. Only you saw it, so only "
      + "you can record it. \"I'm not sure\" is recorded as nobody having watched, which is a "
      + "different thing from no prompt appearing, and the report keeps them apart."

    // MARK: - what the run needs told

    private var setupSection: some View {
        Section {
            // MONO BECAUSE IT IS SIX DIGITS THAT ARE READ BACK ONE AT A TIME.
            // A PIN is the kind of value where a 1 and an l being the same shape
            // costs somebody a refusal they then have to explain.
            TextField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .font(.body.monospaced())
                .foregroundStyle(Theme.textPrimary)
                .disabled(scanner.spikeStep != nil)
                .accessibilityLabel(Text("PIN"))
            Toggle("btd started with --require-pairing", isOn: $requirePairing)
                .disabled(scanner.spikeStep != nil)
                .accessibilityHint(Text(
                    "Only you know how the daemon was launched. This is recorded as your answer."))
        } header: {
            Text("Before you start")
        } footer: {
            // Why the flag is the question, in the kit's words: it is what the
            // read step is even for.
            Text(PairingSpike.Step.readVersion.establishes)
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - starting, and picking one

    private var ducksSection: some View {
        Section {
            if scanner.found.isEmpty { listeningRow }
            ForEach(scanner.found) { duck in
                Button {
                    scanner.runSpike(with: duck, pin: pin)
                } label: {
                    row(duck.sighting)
                }
                .buttonStyle(.plain)
                // ONE RUN AT A TIME. Picking a second duck mid-run would leave
                // half a report attributed to the wrong robot.
                .disabled(scanner.spikeStep != nil || scanner.spikeFinished)
                .accessibilityLabel(Text(duck.sighting.name))
                .accessibilityHint(Text("Runs the whole spike against this duck."))
            }

            // THE THING SOMEBODY CAME HERE TO DO, so it is the one capsule in
            // the action colour on this screen until a report exists. It is
            // `.primaryAction` and not `.primaryActionMoves`: a spike reads and
            // writes RPC, and nothing on the robot moves when it is pressed.
            Button {
                run = nil
                scanner.beginSpike()
            } label: {
                Label(started ? "Start again" : "Start the spike", systemImage: "stopwatch")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .listRowSeparator(.hidden)
            .disabled(scanner.spikeStep != nil)
        } header: {
            Text("Ducks in range")
        } footer: {
            Text(PairingSpike.Step.scan.establishes)
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// Nothing found yet.
    ///
    /// AN EYE RATHER THAN A SPINNER, for the reason `LensIndicator` is written
    /// down at length: a spinner says this phone is busy, and what is happening
    /// is that the room is being listened to. The iris is hidden from VoiceOver
    /// because its own word is "Connecting" and nothing is being connected to —
    /// the sentence beside it is the accurate one.
    private var listeningRow: some View {
        HStack(spacing: Theme.spacing(.tight)) {
            LensIndicator(state: scanner.scanning ? .connecting : .asleep)
                .accessibilityHidden(true)
            Text(scanner.scanning ? "Listening for a duck…" : "Nothing found yet.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One duck.
    ///
    /// STACKED RATHER THAN THREE COLUMNS, the same as `FindDuckView`'s. Name,
    /// address and signal sharing one row's width is a fight for that width at
    /// an accessibility text size, and the part that loses is always the number
    /// on the right — which hides the signal strength from the people who most
    /// enlarged the type in order to read it.
    private func row(_ duck: DuckLink.Sighting) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack(spacing: Theme.spacing(.tight)) {
                Text(duck.name)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.spacing(.tight))
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            // MONO BECAUSE IT IS AN ADDRESS — the one thing on the row somebody
            // retypes into a terminal character by character.
            Text(address(duck.address))
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // RSSI IS TELEMETRY IN THE STRICT SENSE: different on every
            // advertisement, which is the claim monospace makes, and tabular
            // figures are what stop the row twitching as it updates.
            if let rssi = duck.rssi {
                TelemetryRow(label: "Signal", value: "\(rssi)", unit: "dBm")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The three cases `adv.rs` insists are different, kept different.
    private func address(_ address: DuckLink.Address) -> String {
        switch address {
        case .at(let ip): return ip
        case .none: return "no address — the duck has no wifi"
        case .notBroadcast: return "no address broadcast — an older release"
        }
    }

    // MARK: - the steps, live

    /// ALL EIGHT STEPS, ALWAYS, IN ORDER — the same list the report prints, so
    /// what somebody read on the screen and what they hand over cannot differ.
    /// A step nobody reached says so rather than being missing, because "we
    /// never got there" and "it failed" are the distinction the whole run turns
    /// on.
    private var stepsSection: some View {
        Section {
            ForEach(PairingSpike.Step.allCases, id: \.self) { step in
                stepRow(step)
            }
        } header: {
            Text("What happened")
        } footer: {
            Text(PairingSpike.Step.readVersion.timeoutRationale)
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func stepRow(_ step: PairingSpike.Step) -> some View {
        let running = scanner.spikeStep == step
        let outcome = scanner.spikeOutcomes[step] ?? .notReached
        let state = running ? RobotState.scanning : badge(outcome)
        return VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack(spacing: Theme.spacing(.tight)) {
                // THE GLYPH AND THE BADGE SAY THE SAME THING IN TWO CHANNELS,
                // shape and word, and neither of them is the colour. Four
                // endings still get four different icons, for the reason they
                // always did.
                Image(systemName: running ? "circle.dotted" : symbol(outcome))
                    .foregroundStyle(state.color)
                Text(step.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.spacing(.tight))
                StateBadge(text: running ? "running" : word(outcome), state: state)
            }

            if running {
                Text(step.establishes)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // SAYING THE DEADLINE OUT LOUD IS THE POINT. A spinner with no
                // number beside it is indistinguishable from the hang being
                // hunted; a spinner that says how long it will wait tells the
                // person holding the duck when an answer is coming either way.
                //
                // IT IS SET IN THE SAME COLUMN AS `Elapsed` BELOW ON PURPOSE.
                // The budget does not change and telemetry normally does — but
                // the whole reading of this screen is one of these two numbers
                // against the other, and a pair only compares if it is set the
                // same way.
                TelemetryRow(label: "Waiting up to",
                             value: PairingSpike.seconds(step.timeoutSeconds))
            } else {
                if let took = elapsed(outcome) {
                    TelemetryRow(label: "Elapsed", value: took)
                }
                if needsExplaining(outcome) {
                    // THE KIT'S LINE, WHICH IS WHERE A REFUSAL AND A SILENCE ARE
                    // KEPT APART IN WORDS — "REFUSED after 2.10 s — <why>"
                    // against "TIMED OUT after 60.00 s — no answer and no
                    // error". The badge has the word and the row above has the
                    // number; this has the part neither can carry, and it is the
                    // text somebody pastes into an issue. Not monospaced: it is
                    // a sentence, and tabular figures on a sentence tell the
                    // reader to watch something that is not going to move.
                    Text(outcome.line)
                        .font(.caption)
                        .foregroundStyle(state.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.failureMeans)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Four endings, four different icons, on purpose — the entire contribution
    /// turns on nobody mistaking silence for a refusal, or a step that was never
    /// tried for one that failed.
    private func symbol(_ outcome: PairingSpike.Outcome) -> String {
        switch outcome {
        case .ok: return "checkmark.circle.fill"
        case .refused: return "xmark.octagon.fill"
        case .timedOut: return "clock.badge.exclamationmark.fill"
        case .notReached: return "circle"
        }
    }

    /// The outcome in ONE WORD, for the badge.
    ///
    /// THIS BELONGS IN `PairingSpike.Outcome` AND IS NOT THERE. The kit carries
    /// `line`, which is the report's sentence, and a badge cannot take a
    /// sentence — so these four words are derived here, the way `DriveView`
    /// derives "Driving" and "On its side" from a pose. They are the same four
    /// the report's own vocabulary uses, and the moment `Outcome` grows a `word`
    /// this should call it instead.
    private func word(_ outcome: PairingSpike.Outcome) -> String {
        switch outcome {
        case .ok: return "ok"
        case .refused: return "refused"
        case .timedOut: return "timed out"
        case .notReached: return "not reached"
        }
    }

    /// Which of `RobotState`'s four colours an ending is drawn in.
    ///
    /// THE WORD IS THE STATE AND THE COLOUR IS A HINT, which is what makes this
    /// mapping safe to argue about. `StateBadge` takes a `RobotState`, so the
    /// palette's proof that each of its four values clears 4.5:1 on every ground
    /// the app sets words on comes with it — and `Theme.refused`, the critical
    /// red, is deliberately not reachable through it. That is the right way
    /// round here: a refusal is an ANSWER, and the ending this spike exists to
    /// find is the one where nothing came back at all, so the loudest of the
    /// four goes to the hang and the yellow warning register goes to the refusal.
    private func badge(_ outcome: PairingSpike.Outcome) -> RobotState {
        switch outcome {
        // Teal is what a machine measured. A step that answered is a measurement.
        case .ok: return .idle
        // Yellow is the app's warning register: the platform or the robot said
        // no, in words somebody can be shown.
        case .refused: return .scanning
        // The loudest of the four, for the §5.5 symptom itself.
        case .timedOut: return .active
        // Grey. Nothing happened here and nothing is being claimed about it.
        case .notReached: return .offline
        }
    }

    /// How long the step took, formatted BY THE KIT so the screen and the report
    /// cannot disagree about a number. `nil` for a step nobody reached, which
    /// has no duration to report and must not be given a zero.
    private func elapsed(_ outcome: PairingSpike.Outcome) -> String? {
        switch outcome {
        case .ok(let seconds): return PairingSpike.seconds(seconds)
        case .refused(let seconds, _): return PairingSpike.seconds(seconds)
        case .timedOut(let after): return PairingSpike.seconds(after)
        case .notReached: return nil
        }
    }

    /// A step that was never attempted gets no explanation — it has nothing to
    /// explain, and a paragraph under it reads as an accusation. Same rule the
    /// report follows. A step that simply worked gets none either: the badge and
    /// the elapsed row already say everything `line` would.
    private func needsExplaining(_ outcome: PairingSpike.Outcome) -> Bool {
        switch outcome {
        case .refused, .timedOut: return true
        case .ok, .notReached: return false
        }
    }

    // MARK: - the one answer only a person has

    /// THREE EQUAL BUTTONS RATHER THAN A SEGMENTED CONTROL, and the reason is
    /// the height. A segmented control is about 32 points tall, which is under
    /// the HIG's 44pt floor, on the one question in this app whose answer is a
    /// piece of evidence — asked of somebody holding a robot in one hand. These
    /// are 44pt each, they share the width equally, and the chosen one carries
    /// the bill as well as the wash, because `surfaceInteractive` differs from
    /// its ground by 1.02:1 in light and the palette says in as many words that
    /// this is a hint and not information.
    ///
    /// STILL EDITABLE AFTER THE ALERT, and after the run has ended. Somebody who
    /// tapped the wrong button, or who was looking at the duck rather than the
    /// phone and only worked out afterwards what they saw, must be able to
    /// correct the report instead of shipping a wrong observation because a
    /// dialog had gone.
    private var promptSection: some View {
        Section {
            HStack(spacing: Theme.spacing(.tight)) {
                ForEach(Answer.allCases, id: \.self) { answer in
                    answerButton(answer)
                }
            }
            // Room for the bill to hang below the chosen capsule without the row
            // jogging four points taller the moment an answer is given.
            .padding(.bottom, Theme.spacing(.snug))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("iOS asked to pair"))
        } header: {
            Text("The pairing prompt")
        } footer: {
            Text(Self.promptQuestion)
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// One answer. The bill is the selection, not the tint — the same
    /// construction `DriveView`'s layer chips use, for the same reason.
    private func answerButton(_ answer: Answer) -> some View {
        let chosen = Answer(scanner.pairingPrompt) == answer
        return Button {
            scanner.answerPairingPrompt(answer.value)
        } label: {
            Text(answer.label)
                .font(.footnote.weight(chosen ? .semibold : .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(chosen ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.spacing(.tight))
                .frame(maxWidth: .infinity,
                       minHeight: ConnectivityMetric.minimumTarget)
                .background { if chosen { Capsule().fill(Theme.surfaceInteractive) } }
                .overlay(Capsule().strokeBorder(Theme.separator,
                                                lineWidth: ConnectivityMetric.hairlineStroke))
                .overlay(alignment: .bottom) {
                    if chosen { BillIndicator().offset(y: Theme.spacing(.tight)) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(answer.label))
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    /// The three states the report can carry, as something three buttons can
    /// hold. "Not sure" and "never answered" are the same `nil`: a person who is
    /// unsure has not observed anything, and `Run.pairingPromptShown` exists to
    /// keep that apart from a `false`.
    private enum Answer: CaseIterable, Hashable {
        case yes, no, unsaid

        init(_ value: Bool?) {
            switch value {
            case .some(true): self = .yes
            case .some(false): self = .no
            case .none: self = .unsaid
            }
        }

        var value: Bool? {
            switch self {
            case .yes: return true
            case .no: return false
            case .unsaid: return nil
            }
        }

        var label: String {
            switch self {
            case .yes: return "It asked"
            case .no: return "No prompt"
            case .unsaid: return "Not sure"
            }
        }
    }

    // MARK: - handing it over

    private var reportSection: some View {
        Section {
            if let run {
                Text(run.reading.headline)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // MONO BECAUSE IT IS A DOCUMENT, NOT A VALUE. This is the exact
                // plain text that leaves the phone, column alignment and all,
                // and somebody reading it here is proof-reading what they are
                // about to hand over.
                Text(run.report())
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                // THE POINT OF THE SCREEN, so it is the capsule in the action
                // colour. Everything above it is a reading; this is the only
                // thing here that leaves the phone.
                Button {
                    hand(over: run)
                } label: {
                    Label("Share the report", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .listRowSeparator(.hidden)
                .accessibilityHint(Text(
                    "Writes the report as a text file and opens the system share sheet."))
            }
        } header: {
            Text("The report")
        } footer: {
            Text("Plain text, and it says what it does not establish as plainly as what it does. "
                 + "A step that timed out is a result worth sending, not a run worth repeating "
                 + "until it goes green.")
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private func refreshRun() {
        guard scanner.spikeFinished else {
            run = nil
            return
        }
        run = scanner.spikeRun(requirePairing: requirePairing,
                               deviceModel: Self.deviceModel,
                               iOSVersion: UIDevice.current.systemVersion)
    }

    private func hand(over run: PairingSpike.Run) {
        do {
            outgoing = ExportedFile(url: try ExportFile.write(Data(run.report().utf8),
                                                              named: "microduck-pairing-spike.txt"))
        } catch let error as ExportFile.Failure {
            failure = error.message
        } catch {
            failure = "\(error)"
        }
    }

    /// The machine this ran on.
    ///
    /// THE HARDWARE IDENTIFIER, NOT THE MARKETING NAME, because that is what
    /// iOS will actually give: `UIDevice.model` says "iPhone" for every iPhone
    /// ever made. A hang on one radio generation is not a hang on all of them,
    /// and the person reading the issue is holding different hardware.
    private static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
