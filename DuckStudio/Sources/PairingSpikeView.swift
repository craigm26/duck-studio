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
            }

            if let radio = scanner.radio {
                Section {
                    Label(radio, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }

            setupSection
            ducksSection
            if started { stepsSection }
            if readResolved { promptSection }
            if scanner.spikeFinished { reportSection }
        }
        .navigationTitle("Pairing spike")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { scanner.stopSpike() }
        .onChange(of: scanner.spikeFinished) { _, _ in refreshRun() }
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
    /// raises the prompt. A segmented control asking about a pairing sheet while
    /// the phone is still scanning would invite an answer about nothing.
    private var readResolved: Bool { scanner.spikeOutcomes[.readVersion] != nil }

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
            TextField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .font(.body.monospaced())
                .disabled(scanner.spikeStep != nil)
            Toggle("btd started with --require-pairing", isOn: $requirePairing)
                .disabled(scanner.spikeStep != nil)
        } header: {
            Text("Before you start")
        } footer: {
            // Why the flag is the question, in the kit's words: it is what the
            // read step is even for.
            Text(PairingSpike.Step.readVersion.establishes)
        }
    }

    // MARK: - starting, and picking one

    private var ducksSection: some View {
        Section {
            if scanner.found.isEmpty {
                HStack(spacing: 10) {
                    if scanner.scanning { ProgressView() }
                    Text(scanner.scanning ? "Listening for a duck…" : "Nothing found yet.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
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
            }

            Button {
                run = nil
                scanner.beginSpike()
            } label: {
                Label(started ? "Start again" : "Start the spike", systemImage: "stopwatch")
            }
            .disabled(scanner.spikeStep != nil)
        } header: {
            Text("Ducks in range")
        } footer: {
            Text(PairingSpike.Step.scan.establishes)
        }
    }

    private func row(_ duck: DuckLink.Sighting) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(duck.name).font(.body)
                Text(address(duck.address))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if let rssi = duck.rssi {
                Text("\(rssi) dBm")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
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
        }
    }

    private func stepRow(_ step: PairingSpike.Step) -> some View {
        let running = scanner.spikeStep == step
        let outcome = scanner.spikeOutcomes[step] ?? .notReached
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: running ? "circle.dotted" : symbol(outcome))
                    .foregroundStyle(running ? Color.accentColor : tint(outcome))
                Text(step.title).font(.subheadline)
                Spacer()
                if running { ProgressView() }
            }
            if running {
                Text(step.establishes).font(.caption2).foregroundStyle(.secondary)
                // SAYING THE DEADLINE OUT LOUD IS THE POINT. A spinner with no
                // number beside it is indistinguishable from the hang being
                // hunted; a spinner that says how long it will wait tells the
                // person holding the duck when an answer is coming either way.
                Text("Waiting up to \(PairingSpike.seconds(step.timeoutSeconds))")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                // The kit's line, which is where a refusal and a silence are
                // kept apart in words.
                Text(outcome.line)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(tint(outcome))
                if needsExplaining(outcome) {
                    Text(step.failureMeans).font(.caption2).foregroundStyle(.secondary)
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

    private func tint(_ outcome: PairingSpike.Outcome) -> Color {
        switch outcome {
        case .ok: return .green
        case .refused: return .orange
        case .timedOut: return .red
        case .notReached: return .secondary
        }
    }

    /// A step that was never attempted gets no explanation — it has nothing to
    /// explain, and a paragraph under it reads as an accusation. Same rule the
    /// report follows.
    private func needsExplaining(_ outcome: PairingSpike.Outcome) -> Bool {
        switch outcome {
        case .refused, .timedOut: return true
        case .ok, .notReached: return false
        }
    }

    // MARK: - the one answer only a person has

    private var promptSection: some View {
        Section {
            Picker("iOS asked to pair", selection: Binding(
                get: { Answer(scanner.pairingPrompt) },
                set: { scanner.answerPairingPrompt($0.value) })) {
                    ForEach(Answer.allCases, id: \.self) { answer in
                        Text(answer.label).tag(answer)
                    }
                }
                .pickerStyle(.segmented)
                // STILL EDITABLE AFTER THE ALERT, and after the run has ended.
                // Somebody who tapped the wrong button, or who was looking at
                // the duck rather than the phone and only worked out afterwards
                // what they saw, must be able to correct the report instead of
                // shipping a wrong observation because a dialog had gone.
        } header: {
            Text("The pairing prompt")
        } footer: {
            Text(Self.promptQuestion)
        }
    }

    /// The three states the report can carry, as something a segmented control
    /// can hold. "Not sure" and "never answered" are the same `nil`: a person
    /// who is unsure has not observed anything, and `Run.pairingPromptShown`
    /// exists to keep that apart from a `false`.
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
                Text(run.report())
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                Button {
                    hand(over: run)
                } label: {
                    Label("Share the report", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("The report")
        } footer: {
            Text("Plain text, and it says what it does not establish as plainly as what it does. "
                 + "A step that timed out is a result worth sending, not a run worth repeating "
                 + "until it goes green.")
        }
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
