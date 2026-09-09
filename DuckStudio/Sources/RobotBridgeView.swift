import SwiftUI
import DuckKit
import DuckEvidence
import StudioKit

/// A bridge on the robot's own computer, and the one thing this app can put
/// through it today: a policy file, onto the robot's disk.
///
/// WHY THIS SCREEN EXISTS, AND WHAT CHANGED UNDER IT. `bridge/microduck-bridge.py`
/// has relayed robotd's socket to TCP since build 46. This screen was the first
/// door in the app that reached a real duck's disk, and it used to be the only
/// one that dialled the bridge at all — the Control tab's drive loop was typed
/// to a bench, so nothing else could. That is no longer true: the loop takes
/// `any DuckPeer`, and the link this screen opens is the link that tab drives.
///
/// SO THE CONNECTION IS NOT THIS SCREEN'S ANY MORE. It lives in `BridgeLink`,
/// owned by the app, and this screen opens and closes it on somebody's behalf
/// rather than owning it — which is why leaving this screen no longer hangs up
/// on a robot. What this screen still owns is the one thing only it does:
/// putting a file on the robot's disk. It says exactly what that does not do:
/// it does not run the network, it does not restart robotd, and it cannot
/// install anything on a bridge started without `--policy-dir`.
///
/// THE TOKEN IS THE BRIDGE'S, NOT HUGGING FACE'S. `BridgeTokenStore` keeps it
/// under its own Keychain name so the two credentials cannot overwrite each
/// other; `BridgeHandshake.tokenIsNotSecurity` says what it is for.
struct RobotBridgeView: View {
    @ObservedObject var library: LibraryModel
    /// The app's one link. NOT A `@State` HERE — see the file comment.
    @ObservedObject var robot: BridgeLink
    @AppStorage("bridge.host") private var host = ""
    @AppStorage("bridge.port") private var port = BridgeHandshake.defaultPort
    @State private var token = ""
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
                    .disabled(robot.isConnected)
                Stepper("Port \(port)", value: $port, in: 1...65535)
                    .disabled(robot.isConnected)
                SecureField("Token the bridge printed", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(robot.isConnected)
                if robot.isConnected {
                    // DISCONNECTING HERE HANGS UP ON THE CONTROL TAB TOO, which
                    // is the honest consequence of one link and is said rather
                    // than discovered: the button's own row names it.
                    Button("Disconnect") { robot.disconnect() }
                    Text(BridgeDrive.disconnectEndsDriving)
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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

            if let greeting = robot.greeting {
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
                    // THE DOOR TO THE THING THIS LINK IS NOW FOR. A person who
                    // has just connected a robot is one tap from driving it,
                    // and the alternative — finding the Control tab and
                    // switching its venue — is a route nobody would guess.
                    Label(BridgeDrive.driveOnControl, systemImage: "gamecontroller")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        // NO `onDisappear` CLOSE. It used to hang up on the way out, which was
        // right while this screen owned the socket and is wrong now that the
        // Control tab drives it: walking to the tab that uses the link must not
        // be what closes it. Disconnect is a button.

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
            try await robot.connect(host: host.trimmingCharacters(in: .whitespaces),
                                    port: port,
                                    token: token.trimmingCharacters(in: .whitespaces))
            BridgeTokenStore.save(token)
            Haptic.connected()
        } catch let refusal as BridgeHandshake.Refusal {
            failure = refusal.message
        } catch {
            failure = error.localizedDescription
        }
    }

    private func install() async {
        guard let peer = robot.peer, let chosen,
              let bytes = PolicyStore.data(for: chosen) else { return }
        busy = true; failure = nil; outcome = nil
        defer { busy = false }
        do {
            let request = DuckPolicyInstall(name: DuckPolicyInstall.fileName(for: chosen.title),
                                            bytes: bytes, slot: slot?.rawValue)
            let reply = try await peer.call(.installPolicy(request))
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
