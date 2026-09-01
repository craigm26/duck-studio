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

    var body: some View {
        List {
            // THE FACT, NOT THE LAB'S SENTENCE. This screen has two entrances
            // now — the Lab's bench row and the Policies menu — and the honesty
            // line lived only on the Lab container. `LabCatalogue.preamble`
            // cannot be reused here: it asserts "Nothing in the Lab is talking
            // to a robot", which names a place the reader may not be in.
            Section {
                Text(LabCatalogue.noRobotYet)
                    .font(.footnote).foregroundStyle(.secondary)
            }

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
                        Text(bench.address)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    NavigationLink { BenchSettingsView(store: benches) } label: {
                        Label("Manage benches", systemImage: "slider.horizontal.3")
                    }
                    Button("Connect") { Task { await connect() } }
                        .disabled(bench == nil || busy)
                }
            } header: {
                Text("Where the physics is")
            } footer: {
                Text("A machine on your own network running duckbench.mjs. Plain http, because a Pi on a desk has no certificate — so only a private address or a tailnet one is accepted.")
            }

            if let health {
                Section {
                    LabeledContent("Bench", value: health.bench)
                    LabeledContent("Cores", value: "\(health.cores)")
                    LabeledContent("Rate", value: "\(Int(health.tickHz)) Hz")
                    Text(health.plant).font(.caption).foregroundStyle(.secondary)
                    // WHETHER A RESULT FROM HERE COULD EVER BE ATTRIBUTED. The
                    // line above is the bench's own prose about its world; this
                    // one says whether it identified that world well enough for
                    // a stored result to be matched against anyone else's.
                    // Composed in StudioKit, where a test asserts it.
                    Text(health.plantSentence).font(.caption2).foregroundStyle(.secondary)
                    if !health.graspables.isEmpty {
                        Text("Things in that world: "
                             + health.graspables.map {
                                 String(format: "%@ (%.0f g)", $0.name, $0.grams)
                               }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !health.trains, let why = health.trainsWhy {
                        Label(why, systemImage: "info.circle")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("What answered")
                }

                Section {
                    Picker("Policy", selection: $chosen) {
                        ForEach(health.policies, id: \.self) { Text($0).tag($0) }
                    }
                    Stepper("For \(String(format: "%.0f", seconds)) s",
                            value: $seconds, in: 1...20, step: 1)
                } header: {
                    Text("What to run")
                }

                Section {
                    twist("From 0 s", step: $start)
                    twist("From \(String(format: "%.1f", then.at)) s", step: $then)
                } header: {
                    Text("What to command it")
                } footer: {
                    Text("Three numbers, and what they mean is the policy's business: for alpha_walking they are forward, sideways and turn; for flamingo-cycle the first is a flag and the second picks the foot. The policy's own card says which.")
                }

                Section {
                    Button {
                        Task { await record() }
                    } label: {
                        HStack {
                            Label("Record it", systemImage: "record.circle")
                            if busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(chosen.isEmpty || busy)
                    Button {
                        Task { await measure() }
                    } label: {
                        Label("Measure how often it works", systemImage: "chart.bar")
                    }
                    .disabled(chosen.isEmpty || busy)
                }
            }

            if let failure {
                Section { Text(failure).font(.footnote).foregroundStyle(.orange) }
            }

            if let success {
                Section {
                    LabeledContent("Worked", value: "\(success.achieves) of \(success.rollouts)")
                    Text(success.criterion).font(.caption).foregroundStyle(.secondary)
                    if let randomised = success.randomised {
                        Text(randomised).font(.caption2).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Measured on the bench")
                }
            }

            if let clip {
                Section {
                    NavigationLink {
                        IntentPlayerView(clip: clip, store: scenes, drafts: drafts,
                                         models: models)
                    } label: {
                        Label("Watch what it did — \(clip.frames.count) ticks",
                              systemImage: "play.circle")
                    }
                    // KEEPING IT IS THE WHOLE POINT OF HAVING RECORDED IT.
                    // Until this button existed the footer below was simply
                    // true: a recording lasted as long as the screen, so a
                    // policy that did not ship with the app — an imported one,
                    // or a blend made on this phone — could be watched once on
                    // the bench and never played again. Kept, it becomes a
                    // motion in the Intents tab like any other, playable with
                    // no bench and no network.
                    Button {
                        keepRecording(clip)
                    } label: {
                        Label(kept == Self.keepName(clip) ? "Kept — it is in your Intents"
                                                : "Keep this recording",
                              systemImage: kept == Self.keepName(clip) ? "checkmark.circle" : "tray.and.arrow.down")
                    }
                    .disabled(kept == Self.keepName(clip))
                } header: {
                    Text("Recorded")
                } footer: {
                    Text("Made on the bench just now, not shipped with the app. Keep it and it "
                       + "becomes a motion in your Intents — playable afterwards with no bench "
                       + "and no network, because the frames are the recording rather than a "
                       + "live run.")
                }
            }
        }
        .navigationTitle("Run on your network")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func twist(_ label: String, step: Binding<DuckBench.Step>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
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
                        Text(slot).font(.caption2).foregroundStyle(.tertiary)
                        TextField("0", value: value, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
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
        let title = Self.keepName(clip)
        do {
            let export = IntentExport(clip: clip, policyFingerprint: nil,
                                      note: note, named: title)
            guard model.acceptIntent(try export.encoded(), named: title) else {
                // ITS MESSAGE, NOT A NEW ONE. `acceptIntent` says exactly what
                // went wrong — a decode refusal names the field — and it says it
                // on the Policies tab, which is not this screen.
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
    private static func keepName(_ clip: DuckIntentClip) -> String {
        let seconds = clip.hz > 0 ? Double(clip.frames.count) / clip.hz : 0
        return String(format: "%@ — bench, %.1f s, %d ticks",
                      clip.name, seconds, clip.frames.count)
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
        health = nil; clip = nil; success = nil; kept = nil
        health = await run {
            let address = try requireBench().resolved()
            let request = DuckBench.urlRequest(for: DuckBench.health(address), token: token)
            let (data, _) = try await URLSession.shared.data(for: request)
            return try DuckBench.readHealth(data)
        }
        if let health, chosen.isEmpty { chosen = health.policies.first ?? "" }
    }

    @MainActor private func record() async {
        success = nil; kept = nil
        clip = await run {
            let address = try requireBench().resolved()
            let call = try DuckBench.record(address, policy: chosen, seconds: seconds,
                                            schedule: [start, then])
            let (data, _) = try await URLSession.shared.data(
                for: DuckBench.urlRequest(for: call, token: token))
            return try DuckBench.readClip(data, named: chosen)
        }
    }

    @MainActor private func measure() async {
        clip = nil; kept = nil
        success = await run {
            let address = try requireBench().resolved()
            let call = try DuckBench.measure(address, policy: chosen, seconds: seconds,
                                             rollouts: 8, schedule: [start, then])
            let (data, _) = try await URLSession.shared.data(
                for: DuckBench.urlRequest(for: call, token: token))
            return try DuckBench.readSuccess(data)
        }
    }
}
