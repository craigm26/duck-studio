import SwiftUI
import StudioKit

/// The screen that gets a phone talking to a machine with physics.
///
/// IT EXISTS BECAUSE THE ADDRESS FIELD WAS THE WHOLE ONBOARDING. A text box
/// labelled "192.168.1.20:8770" assumes somebody already knows there is a
/// program to install, on which machine, what it is called, and what to type
/// when it does not work. That is the one setup in this app that happens on a
/// DIFFERENT DEVICE, so it is the one that cannot be discovered by tapping
/// around.
///
/// THE TEST BUTTON IS THE SCREEN. Everything above it is instructions somebody
/// may or may not read; the useful moment is pressing Test and being told the
/// one thing to do next. `BenchSetup.diagnose` decides that, with tests on
/// every sentence, because a diagnosis that names the wrong action sends a
/// person to check a firewall they never needed to touch.
struct BenchSetupView: View {
    @AppStorage("duckbench.address") private var addressText = ""
    @AppStorage("duckbench.token") private var token = ""
    @State private var diagnosis: BenchSetup.Diagnosis?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Text("Duck Studio can read a policy and blend one. It cannot RUN one — an "
                   + "iPhone has no physics engine. The bench is a small program on a computer "
                   + "you already own that does, and this connects the two.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("The address") {
                TextField("100.95.79.116:8770", text: $addressText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .onSubmit { addressText = BenchSetup.tidy(addressText) }
                SecureField("Token, only if you set one", text: $token)

                Button(busy ? "Testing…" : "Test this address") {
                    Task { await test() }
                }
                .disabled(busy)

                if let diagnosis {
                    Label {
                        Text(diagnosis.message).font(.footnote)
                    } icon: {
                        Image(systemName: diagnosis.isConnected
                                          ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(diagnosis.isConnected ? .green : .orange)
                    }
                }

                // SAID WHEN IT IS STILL WORKING, not when it breaks. A Wi-Fi
                // address connects perfectly here and fails on the bus, and by
                // then nothing on screen connects the two events.
                if !addressText.isEmpty, !BenchSetup.isTailnet(addressText) {
                    Text(BenchSetup.lanWarning)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Setting it up, once") {
                ForEach(BenchSetup.steps) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(step.number). \(step.title)")
                            .font(.subheadline.weight(.semibold))
                        Text(step.detail)
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let copyable = step.copyable {
                            Button {
                                UIPasteboard.general.string = copyable
                            } label: {
                                Label(copyable, systemImage: "doc.on.doc")
                                    .font(.caption.monospaced())
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Text("The bench window has to stay open while you use it. Closing it stops the "
                   + "bench, and the app will say nothing answered.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Set up a bench")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func test() async {
        busy = true; diagnosis = nil
        defer { busy = false }
        addressText = BenchSetup.tidy(addressText)

        var status: Int?
        var body: Data?
        var failed = false
        // ONLY DIAL IF THE ADDRESS PARSES. Building a request from something
        // `DuckBench.address` would refuse is how a public host gets contacted
        // by an app that says it never does.
        if let address = try? DuckBench.address(addressText) {
            do {
                let request = DuckBench.urlRequest(
                    for: DuckBench.health(address), token: token.isEmpty ? nil : token)
                let (data, response) = try await URLSession.shared.data(for: request)
                status = (response as? HTTPURLResponse)?.statusCode
                body = data
            } catch {
                failed = true
            }
        }
        diagnosis = BenchSetup.diagnose(address: addressText, status: status,
                                        body: body, transportFailed: failed)
    }
}
