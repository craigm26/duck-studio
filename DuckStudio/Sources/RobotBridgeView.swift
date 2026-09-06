import SwiftUI
import DuckKit
import DuckEvidence
import StudioKit

/// A bridge on the robot's own computer, and the one thing this app can put
/// through it today: a policy file, onto the robot's disk.
///
/// WHY THIS SCREEN EXISTS. `bridge/microduck-bridge.py` has relayed robotd's
/// socket to TCP since build 46, and nothing in the app ever dialled it: the
/// Control tab's loop is typed to a bench, and that refactor is its own job.
/// Installing a policy needs none of that — one request, one answer — so
/// this is the first door in the app that reaches a real duck's disk, and it
/// says exactly what it does not do: it does not run the network, it does not
/// restart robotd, and it cannot install anything on a bridge started without
/// `--policy-dir`.
///
/// THE TOKEN IS THE BRIDGE'S, NOT HUGGING FACE'S. `BridgeTokenStore` keeps it
/// under its own Keychain name so the two credentials cannot overwrite each
/// other; `BridgeHandshake.tokenIsNotSecurity` says what it is for.
struct RobotBridgeView: View {
    @ObservedObject var library: LibraryModel
    @AppStorage("bridge.host") private var host = ""
    @AppStorage("bridge.port") private var port = BridgeHandshake.defaultPort
    @State private var token = ""
    @State private var client: BridgeClient?
    @State private var greeting: BridgeHandshake.Greeting?
    @State private var busy = false
    @State private var failure: String?
    @State private var chosenID: String?
    @State private var slot: DuckOfficialPolicies.Slot?
    @State private var confirming = false
    @State private var outcome: String?

    private var candidates: [PolicyLibrary.Entry] {
        library.library.entries.filter(\.isRunnable)
    }
    private var chosen: PolicyLibrary.Entry? {
        chosenID.flatMap { id in candidates.first { $0.id == id } }
    }

    var body: some View {
        List {
            Section {
                Text(BridgeHandshake.whatABridgeIs)
                    .font(.footnote).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("robot.local or 192.168.1.20", text: $host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
                    .disabled(client != nil)
                Stepper("Port \(port)", value: $port, in: 1...65535)
                    .disabled(client != nil)
                SecureField("Token the bridge printed", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(client != nil)
                if let client {
                    Button("Disconnect") { client.close(); self.client = nil; greeting = nil }
                } else {
                    Button { Task { await connect() } } label: {
                        HStack(spacing: Theme.spacing(.tight)) {
                            Text("Connect").frame(maxWidth: .infinity)
                            if busy { ProgressView() }
                        }
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(busy || host.trimmingCharacters(in: .whitespaces).isEmpty
                              || token.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                SectionHeading(text: "The bridge")
            } footer: {
                Text(BridgeHandshake.tokenIsNotSecurity)
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            if let greeting {
                Section {
                    TelemetryRow(label: "Bridge", value: greeting.bridge, unit: "")
                    Text(BridgeHandshake.deadmanSaid(greeting.deadmanMilliseconds))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if greeting.installsPolicies {
                        Label("This bridge can install policies", systemImage: "checkmark.circle")
                            .font(.footnote).foregroundStyle(Theme.success)
                    } else {
                        Label(DuckPolicyInstall.bridgeCannotInstall, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    SectionHeading(text: "Connected")
                }
                .listRowBackground(Theme.surfacePrimary)

                if greeting.installsPolicies { installSection }
            }

            if let failure {
                Section {
                    Label(failure, systemImage: "xmark.octagon")
                        .font(.footnote).foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Bridge to a robot")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            token = BridgeTokenStore.load() ?? ""
            if chosenID == nil { chosenID = candidates.first?.id }
        }
        .onDisappear { client?.close(); client = nil }
        .confirmationDialog("Install on the robot?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Install \(chosen?.title ?? "")", role: .destructive) { Task { await install() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(installMessage)
        }
    }

    private var installSection: some View {
        Section {
            let labels = PolicyLibrary.pickerLabels(candidates)
            Picker("Policy", selection: $chosenID) {
                ForEach(candidates) { entry in
                    Text(labels[entry.id] ?? entry.title).tag(String?.some(entry.id))
                }
            }
            Picker("Point a slot at it", selection: $slot) {
                Text("No slot — just the file").tag(DuckOfficialPolicies.Slot?.none)
                ForEach(DuckOfficialPolicies.Slot.allCases, id: \.rawValue) { one in
                    Text("\(one.title) (\(one.rawValue))").tag(DuckOfficialPolicies.Slot?.some(one))
                }
            }
            if let chosen {
                TelemetryRow(label: "Lands as", value: DuckPolicyInstall.fileName(for: chosen.title) + ".onnx", unit: "")
                if let caveat = chosen.origin.caveat {
                    Text(caveat).font(.caption).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button { confirming = true } label: {
                HStack(spacing: Theme.spacing(.tight)) {
                    Text("Install it on the robot").frame(maxWidth: .infinity)
                    if busy { ProgressView() }
                }
            }
            .buttonStyle(.primaryActionMoves)
            .disabled(busy || chosen == nil)
            if let outcome {
                Text(outcome).font(.footnote).foregroundStyle(Theme.measured)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        } header: {
            SectionHeading(text: "Install a policy")
        } footer: {
            Text(DuckPolicyInstall.whatInstallDoes)
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var installMessage: String {
        var lines = [DuckPolicyInstall.whatInstallDoes]
        if let chosen, chosen.origin.caveat != nil { lines.append(DuckPolicyInstall.neverRunOnHardware) }
        return lines.joined(separator: "\n\n")
    }

    private func connect() async {
        busy = true; failure = nil; outcome = nil
        defer { busy = false }
        do {
            let made = try await BridgeClient.connect(
                host: host.trimmingCharacters(in: .whitespaces), port: port,
                token: token.trimmingCharacters(in: .whitespaces), named: host)
            client = made
            greeting = made.greeting
            BridgeTokenStore.save(token)
            Haptic.connected()
        } catch let refusal as BridgeHandshake.Refusal {
            failure = refusal.message
        } catch {
            failure = error.localizedDescription
        }
    }

    private func install() async {
        guard let client, let chosen, let bytes = PolicyStore.data(for: chosen) else { return }
        busy = true; failure = nil; outcome = nil
        defer { busy = false }
        do {
            let request = DuckPolicyInstall(name: DuckPolicyInstall.fileName(for: chosen.title),
                                            bytes: bytes, slot: slot?.rawValue)
            let reply = try await client.peer.call(.installPolicy(request))
            outcome = try DuckPolicyInstall.read(reply).said
            Haptic.finished()
        } catch let refusal as DuckPolicyInstall.ReadError {
            failure = refusal.message
        } catch let misuse as DuckCall.Misuse {
            failure = misuse.message
        } catch {
            failure = error.localizedDescription
        }
    }
}
