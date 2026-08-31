import SwiftUI
import StudioKit

/// The benches this app knows about — named, saved, and one of them chosen.
///
/// THIS IS THE MODELS SCREEN FOR BENCHES, on purpose. The Models tab already
/// solved "several saved connections, one selected, each checkable on its own",
/// and the bench had a single unnamed address box instead — so the app could
/// hold one bench, could not say which, and forgot the last one every time you
/// moved between machines. Copying that screen's shape is worth more than a
/// fresh design: somebody who has set up a model already knows how this works.
///
/// A NEW ENTRY CAN BE CHECKED BEFORE IT IS FINISHED. "Check this address" asks
/// for `/health`, which a bench answers without running anything, so it works
/// on an entry with no name and before any policy has been chosen — which is
/// the only moment anybody presses it.
struct BenchSettingsView: View {
    @ObservedObject var store: BenchStore
    @State private var editing: BenchEndpoint?

    var body: some View {
        Form {
            if let note = store.unreadableNote {
                Section {
                    Text(note).font(.footnote)
                    Button("Got it") { store.dismissUnreadableNote() }
                }
            }

            Section("Run things on") {
                if store.benches.isEmpty {
                    Text("No bench yet. Without one this app can read a policy and blend one, "
                       + "but not run it — an iPhone has no physics engine.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(store.benches) { bench in
                        row(bench)
                    }
                    .onDelete { indexes in
                        indexes.map { store.benches[$0] }.forEach(store.delete)
                    }
                }
            }

            Section {
                ForEach(BenchSetup.presets) { preset in
                    Button {
                        editing = BenchEndpoint(name: preset.suggestedName,
                                                address: preset.address)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(preset.name, systemImage: preset.symbol)
                            Text(preset.detail)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } header: {
                Text("Add one")
            } footer: {
                Text(BenchSetup.preambleForAdding)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Setting one up, once") {
                NavigationLink { BenchSetupView() } label: {
                    Label("The steps", systemImage: "list.number")
                }
            }
        }
        .navigationTitle("Benches")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { bench in
            NavigationStack {
                BenchEditorView(bench: store.armed(bench), store: store)
            }
        }
    }

    private func row(_ bench: BenchEndpoint) -> some View {
        HStack {
            Button {
                store.selectedID = bench.id
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bench.name)
                        Text(bench.address)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        // SAID WHILE IT IS STILL WORKING. A Wi-Fi bench fails
                        // on the bus in a way that looks like it going down.
                        if !bench.isTailnet {
                            Text("Wi-Fi only")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if bench.id == store.selectedID {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
            .foregroundStyle(.primary)

            Button {
                editing = bench
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Edit \(bench.name)"))
        }
    }
}

/// One bench, being edited — with the two questions a person actually has:
/// does this address answer, and what is on it.
struct BenchEditorView: View {
    @State var bench: BenchEndpoint
    @ObservedObject var store: BenchStore

    @Environment(\.dismiss) private var dismiss
    @State private var diagnosis: BenchSetup.Diagnosis?
    @State private var policies: [String] = []
    @State private var busy = false
    @State private var refusal: String?

    var body: some View {
        Form {
            Section("Name") {
                TextField("My bench", text: $bench.name)
            }

            Section {
                TextField("100.122.199.6:8770", text: $bench.address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .onSubmit { bench.address = BenchSetup.tidy(bench.address) }
                SecureField("Token, only if you set one", text: Binding(
                    get: { bench.token ?? "" },
                    set: { bench.token = $0 }))
            } header: {
                Text("Address")
            } footer: {
                Text("Host and port, as the start script prints it. No http://, no trailing "
                   + "slash — this is not a web address.")
            }

            Section {
                Button(busy ? "Asking…" : "Check this address") {
                    Task { await check() }
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

                if !policies.isEmpty {
                    DisclosureGroup("What it can run (\(policies.count))") {
                        ForEach(policies, id: \.self) { name in
                            Text(name).font(.caption.monospaced())
                        }
                    }
                }
            } header: {
                Text("Check")
            } footer: {
                Text("Asks the bench for its health — the one thing it answers without running "
                   + "any physics, so this works before anything else is set. It says which of "
                   + "the several very different reasons an address can fail it hit: nothing "
                   + "listening, something else on the port, a token wanted, an address this app "
                   + "will not dial, or connected.")
            }

            if !bench.isTailnet, !bench.address.isEmpty {
                Section {
                    Text(BenchSetup.lanWarning)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let refusal {
                Section { Text(refusal).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle(bench.name.isEmpty ? "New bench" : bench.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
    }

    private func save() {
        do {
            try bench.validate()
            store.save(bench)
            dismiss()
        } catch let error as BenchEndpoint.Refusal {
            refusal = error.message
        } catch {
            refusal = error.localizedDescription
        }
    }

    @MainActor private func check() async {
        busy = true; refusal = nil; diagnosis = nil; policies = []
        defer { busy = false }
        bench.address = BenchSetup.tidy(bench.address)

        var status: Int?
        var body: Data?
        var failed = false
        // ONLY DIAL WHAT THE PARSER ACCEPTS. Building a request out of
        // something `DuckBench.address` would refuse is how an app that says it
        // never contacts a public host contacts one.
        if let address = try? bench.resolved() {
            do {
                let token = bench.token?.isEmpty == false ? bench.token : nil
                let request = DuckBench.urlRequest(for: DuckBench.health(address), token: token)
                let (data, response) = try await URLSession.shared.data(for: request)
                status = (response as? HTTPURLResponse)?.statusCode
                body = data
                if let health = try? DuckBench.readHealth(data) { policies = health.policies }
            } catch {
                failed = true
            }
        }
        diagnosis = BenchSetup.diagnose(address: bench.address, status: status,
                                        body: body, transportFailed: failed)
    }
}
