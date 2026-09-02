import SwiftUI
import DuckKit
import StudioKit

/// Run a policy on a machine that has physics, because this one does not.
///
/// THE HOLE THIS FILLS. You can import a policy here — Pollen's, or one
/// somebody published on Hugging Face — and then there is nothing to press. An
/// iPhone has no MuJoCo: every clip in this app was recorded on a bigger
/// machine and baked in when the app was built. Point this at a bench on your
/// network and an imported policy becomes something you can actually run.
///
/// EVERYTHING ORANGE TALKS TO THE BENCH, and nothing else on the screen is
/// orange. That is the whole colour rule here and it is the same rule the Drive
/// screen states about the duck: Duck Orange is the action colour, so Connect,
/// Record it and Measure wear it and the pickers, the steppers, the twist
/// fields and the notes do not. Keeping a recording is not orange either — it
/// writes to this phone's own Motions and reaches nothing across the room.
///
/// TEAL IS WHAT THE BENCH MEASURED. The plant sentence and the success
/// criterion are the two claims on this screen that came off another machine,
/// and they are set in `Theme.measured` so that a person reading the figures
/// beside them can see at a glance which words are the bench's and which are
/// the app's. The figures themselves are `TelemetryRow`s: a core count, a tick
/// rate, a rollout ratio and a tick count all change from bench to bench and
/// run to run, which is what earns tabular digits.
///
/// THE LENS IS THE LINK, AND IT BELONGS WHERE NOTHING SCROLLS. The iris opens
/// when the bench answers `/health`, which is the moment this screen becomes
/// able to do anything at all — the same picture, in the same place, as the
/// Drive screen.
struct RemoteRunView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var scenes: SceneStore
    @ObservedObject var drafts: DraftStore
    /// For the player that shows what the bench just recorded: remixing that
    /// clip opens the editor, and the editor's Ask panel needs the app's one
    /// model store or it arrives disabled with advice that cannot be followed
    /// from here.
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore

    /// WHICH SAVED BENCH, not a typed address. This was an
    /// `@AppStorage("duckbench.address")` string, so the app held exactly one
    /// bench, could not say which, and forgot the last one whenever somebody
    /// moved between machines. `BenchStore` is the Models tab's shape applied
    /// to the same problem.
    private var bench: BenchEndpoint? { benches.selected }
    /// The token comes off the chosen bench, out of the Keychain, at the
    /// moment of use. It is not a field on this screen any more: a credential
    /// belongs to a bench, not to whichever screen last asked for it.
    private var token: String? { bench.flatMap { benches.armed($0).token } }
    @State private var health: DuckBench.Health?
    @State private var chosen = ""
    @State private var seconds = 6.0
    @State private var start = DuckBench.Step(at: 0)
    @State private var then = DuckBench.Step(at: 1)
    @State private var clip: DuckIntentClip?
    @State private var success: DuckBench.Success?
    @State private var busy = false
    @State private var failure: String?
    /// The name a recording was kept under, so the button can say so.
    ///
    /// CLEARED WHENEVER THE RECORDING CHANGES, and it was not. `clip.name` is
    /// the bench's POLICY name, so recording `alpha_walking` twice yields two
    /// clips with one name: keep the first, record a second, and `kept ==
    /// clip.name` was still true — the button read "Kept — it is in your
    /// Intents" and sat disabled over a recording nobody had saved.
    @State private var kept: String?
    /// The name THIS recording would be kept under, minted when it arrived.
    ///
    /// IT CANNOT BE COMPUTED IN THE LABEL. The button compares against it on
    /// every body pass, so anything that distinguishes two otherwise identical
    /// recordings — and the twist fields exist precisely to make two runs of
    /// one policy at one duration different — has to be captured once, when
    /// the clip lands. Named from the policy, the duration and the tick count
    /// alone, two runs that differ only in their twists share a name, and
    /// `acceptIntent` writes `intents/<name>.duckintent` keyed by name: the
    /// second keep destroys the first while reporting "Added the motion …".
    @State private var recordedName: String?

    /// Whether this recording has already been kept, which is the one thing the
    /// Keep button's word, symbol and enabled state all turn on. Written once
    /// rather than three times, because three copies of a comparison drift.
    private var alreadyKept: Bool { kept != nil && kept == recordedName }

    var body: some View {
        List {
            // THE FACT, NOT THE MODES' SENTENCE. This screen has two entrances
            // — Studio > Measure on a bench, and the bench row under Studio >
            // Modes — and the honesty line lived only on the container that
            // held the modes. `LabCatalogue.modesPreamble` cannot be reused
            // here: it asserts "Nothing in these modes is talking to a robot",
            // which names a place the reader may not be in.
            Section {
                Text(LabCatalogue.noRobotYet)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                // THE LIST IS THE CONTROL. Picking between saved benches is a
                // different act from typing one in, and conflating them is
                // what made the old screen forget the machine you were on
                // five minutes ago.
                if benches.benches.isEmpty {
                    NavigationLink { BenchSettingsView(store: benches) } label: {
                        Label("Set up a bench", systemImage: "plus.circle")
                    }
                } else {
                    Picker("Bench", selection: Binding(
                        get: { benches.selectedID },
                        set: { benches.selectedID = $0 })) {
                        ForEach(benches.benches) { one in
                            Text(one.name).tag(UUID?.some(one.id))
                        }
                    }
                    if let bench {
                        // MONO BECAUSE IT IS TRANSCRIBED, NOT BECAUSE IT MOVES.
                        // A host and port is copied off another machine's
                        // terminal character by character, which is the same
                        // argument the setup screen's command makes.
                        Text(bench.address)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    NavigationLink { BenchSettingsView(store: benches) } label: {
                        Label("Manage benches", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        Task { await connect() }
                    } label: {
                        Text("Connect").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(bench == nil || busy)
                }
            } header: {
                Text("Where the physics is")
            } footer: {
                Text("A machine on your own network running duckbench.mjs. Plain http, because a Pi on a desk has no certificate — so only a private address or a tailnet one is accepted.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            if let health {
                Section {
                    // A NAME IS NOT TELEMETRY. The bench's own name for itself
                    // never changes while you are looking at it, and tabular
                    // figures on it would tell the reader to watch something
                    // that is not going to move.
                    LabeledContent("Bench", value: health.bench)
                    TelemetryRow(label: "Cores", value: "\(health.cores)")
                    TelemetryRow(label: "Rate",
                                 value: "\(Int(health.tickHz))", unit: "Hz")
                    Text(health.plant)
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // WHETHER A RESULT FROM HERE COULD EVER BE ATTRIBUTED. The
                    // line above is the bench's own prose about its world; this
                    // one says whether it identified that world well enough for
                    // a stored result to be matched against anyone else's.
                    // Composed in StudioKit, where a test asserts it.
                    //
                    // IN `measured`, WHICH IS THE PROVENANCE CLAIM ITSELF. Teal
                    // is what a machine said; the sentence is about whether the
                    // machine said enough. It is on a card, which is the ground
                    // `PaletteTests` proves the token against at 4.5:1.
                    Text(health.plantSentence)
                        .font(.caption2).foregroundStyle(Theme.measured)
                        .fixedSize(horizontal: false, vertical: true)
                    if !health.graspables.isEmpty {
                        Text("Things in that world: "
                             + health.graspables.map {
                                 String(format: "%@ (%.0f g)", $0.name, $0.grams)
                               }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !health.trains, let why = health.trainsWhy {
                        Label(why, systemImage: "info.circle")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("What answered")
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    Picker("Policy", selection: $chosen) {
                        ForEach(health.policies, id: \.self) { Text($0).tag($0) }
                    }
                    Stepper("For \(String(format: "%.0f", seconds)) s",
                            value: $seconds, in: 1...20, step: 1)
                } header: {
                    Text("What to run")
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    twist("From 0 s", step: $start)
                    twist("From \(String(format: "%.1f", then.at)) s", step: $then)
                } header: {
                    Text("What to command it")
                } footer: {
                    Text("Three numbers, and what they mean is the policy's business: for alpha_walking they are forward, sideways and turn; for flamingo-cycle the first is a flag and the second picks the foot. The policy's own card says which.")
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    Button {
                        Task { await record() }
                    } label: {
                        Label("Record it", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(chosen.isEmpty || busy)
                    Button {
                        Task { await measure() }
                    } label: {
                        Label("Measure how often it works", systemImage: "chart.bar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(chosen.isEmpty || busy)
                    // THE SPINNER SITS OUTSIDE THE CAPSULES, not inside one of
                    // them. Inside, it would be drawn in the app's tint against
                    // Duck Orange — two accents on one shape — and it would
                    // stretch a control as it appeared, moving a button under a
                    // thumb that is already on it.
                    if busy {
                        ProgressView()
                            .tint(Theme.brandPrimary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            if let failure {
                Section {
                    Text(failure).font(.footnote).foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            if let success {
                Section {
                    // THE RATIO IS THE MEASUREMENT, so it is the one figure on
                    // this screen most owed tabular digits: it is read against
                    // the last run and against the run before that, and
                    // proportional numerals make 8 of 8 and 3 of 8 different
                    // widths.
                    TelemetryRow(label: "Worked",
                                 value: "\(success.achieves) of \(success.rollouts)")
                    // WHAT "WORKED" MEANT, IN THE BENCH'S OWN WORDS. The ratio
                    // above is meaningless without it — eight of eight WHAT —
                    // and it is the bench's claim rather than the app's, which
                    // is what the teal says.
                    Text(success.criterion)
                        .font(.caption).foregroundStyle(Theme.measured)
                        .fixedSize(horizontal: false, vertical: true)
                    if let randomised = success.randomised {
                        Text(randomised)
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Measured on the bench")
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            if let clip {
                Section {
                    NavigationLink {
                        IntentPlayerView(clip: clip, store: scenes, drafts: drafts,
                                         models: models)
                    } label: {
                        Label("Watch what it did", systemImage: "play.circle")
                    }
                    // HOW LONG THE RECORDING IS, AS A ROW RATHER THAN AS A TAIL
                    // ON THE LINK'S LABEL. It was "Watch what it did — 412
                    // ticks", which put a number that changes on every recording
                    // inside a navigation label that never does, and truncated
                    // the number first at an accessibility text size.
                    TelemetryRow(label: "Recorded", value: "\(clip.frames.count)",
                                 unit: "ticks")
                    // KEEPING IT IS THE WHOLE POINT OF HAVING RECORDED IT.
                    // Until this button existed the footer below was simply
                    // true: a recording lasted as long as the screen, so a
                    // policy that did not ship with the app — an imported one,
                    // or a blend made on this phone — could be watched once on
                    // the bench and never played again. Kept, it becomes a
                    // motion under Studio > Motions like any other, playable
                    // with no bench and no network.
                    //
                    // NOT ORANGE, BECAUSE IT REACHES NOTHING. Everything in the
                    // action colour on this screen sends a request to another
                    // machine; this one writes a file on the phone.
                    Button {
                        keepRecording(clip)
                    } label: {
                        Label(alreadyKept ? "Kept — it is in your Motions"
                                          : "Keep this recording",
                              systemImage: alreadyKept ? "checkmark.circle"
                                                       : "tray.and.arrow.down")
                    }
                    .disabled(alreadyKept)
                } header: {
                    Text("Recorded")
                } footer: {
                    Text("Made on the bench just now, not shipped with the app. Keep it and it "
                       + "becomes a motion in your Motions — playable afterwards with no bench "
                       + "and no network, because the frames are the recording rather than a "
                       + "live run.")
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S
        // GREY. `backgroundSecondary` is the token `Theme` documents as a
        // ground for surfaces rather than for words, and every row above keeps
        // a real `surfacePrimary` card under it — which is what makes the
        // provenance colours legible claims rather than hopeful ones.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Run on your network")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LensIndicator(state: linkState)
            }
        }
        .task {
            // WARMED BEFORE THE FIRST ANSWER, NOT AT IT. The taptic engine
            // spins up on demand and the first tap of a session arrives after
            // the thing it is about — which teaches the person that the buzz
            // and the bench are unrelated.
            Haptic.prepare()
        }
    }

    /// What the lens in the toolbar is doing. The bench has answered, is being
    /// asked, or has not been reached.
    private var linkState: LensIndicator.Connection {
        if health != nil { return .connected }
        return busy ? .connecting : .asleep
    }

    /// One command in the schedule: three numbers whose meaning is the
    /// policy's, which is why they are numbered rather than named.
    @ViewBuilder
    private func twist(_ label: String, step: Binding<DuckBench.Step>) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.spacing(.tight)) {
                ForEach(["1", "2", "3"], id: \.self) { slot in
                    let value = Binding<Double>(
                        get: {
                            switch slot {
                            case "1": return step.wrappedValue.vx
                            case "2": return step.wrappedValue.vy
                            default: return step.wrappedValue.vyaw
                            }
                        },
                        set: { new in
                            let s = step.wrappedValue
                            step.wrappedValue = DuckBench.Step(
                                at: s.at,
                                vx: slot == "1" ? new : s.vx,
                                vy: slot == "2" ? new : s.vy,
                                vyaw: slot == "3" ? new : s.vyaw)
                        })
                    VStack(spacing: 0) {
                        Text(slot)
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                            // THE FIELD BELOW CARRIES THIS AS ITS LABEL. Read
                            // out separately it is a lone digit in the rotor
                            // between two things that mean something.
                            .accessibilityHidden(true)
                        TextField("0", value: value, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.center)
                            // MONO, BECAUSE THESE ARE THE NUMBERS THAT CHANGE.
                            // Three fields side by side with proportional
                            // figures put 0.5, 0.05 and -0.5 at three different
                            // widths, and the row jogs as each is typed.
                            .font(.body.monospacedDigit())
                            // A NUMBERED FIELD WITH NO LABEL IS THREE IDENTICAL
                            // "text field" ELEMENTS IN A ROW. Which schedule
                            // step and which of its three slots is the whole of
                            // what distinguishes them.
                            .accessibilityLabel(Text("\(label), \(slot)"))
                    }
                }
            }
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }

    // MARK: - the network

    /// The chosen bench, or a refusal that says what to do. EVERY CALL GOES
    /// THROUGH THIS: a screen that builds a request from no bench at all is how
    /// a button does nothing and says nothing.
    private func requireBench() throws -> BenchEndpoint {
        guard let bench else { throw DuckBench.Refusal.empty }
        return bench
    }

    /// Put a bench recording into the app's own Intents.
    ///
    /// THROUGH `acceptIntent`, NOT AROUND IT. That is the same door a
    /// `.duckintent` arriving from Files or AirDrop goes through — it decodes,
    /// writes, reloads and reports — so a recording made here gets exactly the
    /// checks an imported one gets, and lands in exactly the same place.
    ///
    /// THE FINGERPRINT IS THE BENCH'S POLICY NAME AND NOTHING MORE. A policy
    /// running on a bench has no digest this phone has computed, and inventing
    /// one would put a number on a card that nothing verified.
    @MainActor private func keepRecording(_ clip: DuckIntentClip) {
        failure = nil
        // THE CLIP'S OWN CREDIT FIRST. `DuckBench.readClip` already built one
        // from the /record answer — the world that recording actually ran in —
        // and composing a fresh one from a later /health answers a different
        // question: it downgrades to "nothing recorded which world this ran in"
        // when /health is silent about the plant although the recording named
        // one, and names a different plant outright if the bench reloaded
        // between Connect and Record.
        let note = clip.credit
            ?? DuckBench.recordedCredit(plantName: health?.plantName,
                                        plantDigest: health?.plantDigest)
        // THE NAME MINTED WHEN THE RECORDING ARRIVED, not one composed now:
        // recomposing here would put a second clock reading on it.
        let title = recordedName ?? Self.keepName(clip, at: Date())
        do {
            let export = IntentExport(clip: clip, policyFingerprint: nil,
                                      note: note, named: title)
            guard model.acceptIntent(try export.encoded(), named: title) else {
                // ITS MESSAGE, NOT A NEW ONE. `acceptIntent` says exactly what
                // went wrong — a decode refusal names the field — and it says it
                // under Behaviours, which is not this screen.
                failure = model.lastImport ?? "That recording could not be kept."
                return
            }
            kept = title
        } catch {
            failure = "That recording could not be kept: \(error.localizedDescription)"
        }
    }

    /// A name no other recording of the same policy will take.
    ///
    /// THE POLICY NAME IS NOT ENOUGH, and it is also a name bundled clips
    /// already hold. `roulade` and `headspin` are both a bundled clip AND the
    /// stem of the policy they came from, and both have entries in
    /// `intent-success.json` — so a fresh recording made on somebody's own
    /// bench came up carrying a measured success rate that had been measured
    /// about something else.
    private static func keepName(_ clip: DuckIntentClip, at when: Date) -> String {
        let seconds = clip.hz > 0 ? Double(clip.frames.count) / clip.hz : 0
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss"
        return String(format: "%@ — bench %@, %.1f s, %d ticks",
                      clip.name, clock.string(from: when), seconds, clip.frames.count)
    }

    @MainActor private func run<T>(_ work: () async throws -> T) async -> T? {
        busy = true; failure = nil
        defer { busy = false }
        do { return try await work() }
        catch let refusal as DuckBench.Refusal { failure = refusal.message }
        catch let error as DuckBench.ReadError { failure = error.message }
        catch { failure = error.localizedDescription }
        return nil
    }

    @MainActor private func connect() async {
        health = nil; clip = nil; success = nil; kept = nil; recordedName = nil
        health = await run {
            let address = try requireBench().resolved()
            let request = DuckBench.urlRequest(for: DuckBench.health(address), token: token)
            let (data, _) = try await URLSession.shared.data(for: request)
            return try DuckBench.readHealth(data)
        }
        if let health, chosen.isEmpty { chosen = health.policies.first ?? "" }
        // A BENCH ANSWERING IS AN EVENT ACROSS THE ROOM, which is the only kind
        // this app spends the taptic engine on. It arrives seconds after the
        // finger left the button — on a slow link, long enough that the person
        // has looked away — so the tap is about the answer and never about the
        // press. `Haptic`'s own preamble makes the argument at length.
        if health != nil { Haptic.connected() }
    }

    @MainActor private func record() async {
        success = nil; kept = nil; recordedName = nil
        clip = await run {
            let address = try requireBench().resolved()
            let call = try DuckBench.record(address, policy: chosen, seconds: seconds,
                                            schedule: [start, then])
            let (data, _) = try await URLSession.shared.data(
                for: DuckBench.urlRequest(for: call, token: token))
            return try DuckBench.readClip(data, named: chosen)
        }
        // MINTED ONCE, HERE. See `recordedName`.
        if let clip {
            recordedName = Self.keepName(clip, at: Date())
            // SOMETHING THE PERSON ASKED FOR RAN TO THE END. Six seconds of
            // physics on a small board is long enough to put the phone down for.
            Haptic.finished()
        }
    }

    @MainActor private func measure() async {
        clip = nil; kept = nil; recordedName = nil
        success = await run {
            let address = try requireBench().resolved()
            let call = try DuckBench.measure(address, policy: chosen, seconds: seconds,
                                             rollouts: 8, schedule: [start, then])
            let (data, _) = try await URLSession.shared.data(
                for: DuckBench.urlRequest(for: call, token: token))
            return try DuckBench.readSuccess(data)
        }
        // EIGHT ROLLOUTS IS A MINUTE OR MORE OF SOMEBODY ELSE'S CPU, and the
        // tap is what says it is over to a person who stopped watching.
        if success != nil { Haptic.finished() }
    }
}
