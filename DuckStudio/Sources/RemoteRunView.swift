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
    @ObservedObject var scenes: SceneStore
    @ObservedObject var drafts: DraftStore

    @AppStorage("duckbench.address") private var addressText = ""
    @State private var token = ""
    @State private var health: DuckBench.Health?
    @State private var chosen = ""
    @State private var seconds = 6.0
    @State private var start = DuckBench.Step(at: 0)
    @State private var then = DuckBench.Step(at: 1)
    @State private var clip: DuckIntentClip?
    @State private var success: DuckBench.Success?
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                TextField("192.168.1.20:8770", text: $addressText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Token, if the bench wants one", text: $token)
                Button("Connect") { Task { await connect() } }
                    .disabled(addressText.isEmpty || busy)
            } header: {
                Text("Where the physics is")
            } footer: {
                Text("A machine on your own network running duckbench.mjs from the duck-sounds repository. Plain http, because a Pi on a desk has no certificate — so only a private address or a .local name is accepted.")
            }

            if let health {
                Section {
                    LabeledContent("Bench", value: health.bench)
                    LabeledContent("Cores", value: "\(health.cores)")
                    LabeledContent("Rate", value: "\(Int(health.tickHz)) Hz")
                    Text(health.plant).font(.caption).foregroundStyle(.secondary)
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
                        IntentPlayerView(clip: clip, store: scenes, drafts: drafts)
                    } label: {
                        Label("Watch what it did — \(clip.frames.count) ticks",
                              systemImage: "play.circle")
                    }
                } header: {
                    Text("Recorded")
                } footer: {
                    Text("This recording lives for as long as this screen does. It was made on the bench just now, not shipped with the app.")
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

    private func run<T>(_ work: () async throws -> T) async -> T? {
        busy = true; failure = nil
        defer { busy = false }
        do { return try await work() }
        catch let refusal as DuckBench.Refusal { failure = refusal.message }
        catch let error as DuckBench.ReadError { failure = error.message }
        catch { failure = error.localizedDescription }
        return nil
    }

    private func connect() async {
        health = nil; clip = nil; success = nil
        health = await run {
            let address = try DuckBench.address(addressText)
            let request = DuckBench.urlRequest(for: DuckBench.health(address), token: token)
            let (data, _) = try await URLSession.shared.data(for: request)
            return try DuckBench.readHealth(data)
        }
        if let health, chosen.isEmpty { chosen = health.policies.first ?? "" }
    }

    private func record() async {
        success = nil
        clip = await run {
            let address = try DuckBench.address(addressText)
            let call = try DuckBench.record(address, policy: chosen, seconds: seconds,
                                            schedule: [start, then])
            let (data, _) = try await URLSession.shared.data(
                for: DuckBench.urlRequest(for: call, token: token))
            return try DuckBench.readClip(data, named: chosen)
        }
    }

    private func measure() async {
        clip = nil
        success = await run {
            let address = try DuckBench.address(addressText)
            let call = try DuckBench.measure(address, policy: chosen, seconds: seconds,
                                             rollouts: 8, schedule: [start, then])
            let (data, _) = try await URLSession.shared.data(
                for: DuckBench.urlRequest(for: call, token: token))
            return try DuckBench.readSuccess(data)
        }
    }
}
