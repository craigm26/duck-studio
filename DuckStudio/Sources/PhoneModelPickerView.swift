import SwiftUI
import StudioKit

/// Choosing a model to download onto the phone, and getting rid of it again.
///
/// THIS IS NOT A PRESET, AND IT COULD NOT BE ONE. `ModelSettingsView.Preset`
/// returns a finished endpoint and opens a form — right for an address, wrong
/// for something that has to check what fits, fetch two gigabytes with a
/// progress bar, and be deletable afterwards. So it sits above the presets as
/// its own row.
///
/// EVERY NUMBER ON SCREEN IS MEASURED. The catalogue sizes came from the
/// Hugging Face tree API; the "taking N" beside an installed model is a walk of
/// the directory, not a re-print of the catalogue — those disagree whenever a
/// download was partial or resumed, and the one that matters to somebody about
/// to free space is what is actually on the disk.
struct PhoneModelPickerView: View {
    @ObservedObject var store: EndpointStore
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var hits: [PhoneModelSearch.Hit] = []
    @State private var searching = false
    @State private var searchFailure: String?

    @State private var busyWith: String?
    /// FRACTION, NOT UNITS. The parent Progress advances in whole files and
    /// these repositories are one enormous weights file beside a dozen tiny
    /// JSONs, so a unit count sits frozen at 1% for twenty minutes.
    @State private var progress: (fraction: Double, total: Int)?
    /// So leaving can actually stop it, and so cancelling does not print
    /// "That did not finish. cancelled."
    @State private var job: Task<Void, Never>?
    /// Read once per appearance. As a computed property it drifted between
    /// rows within a single body evaluation.
    @State private var budgetSnapshot = 0
    @State private var failure: String?
    @State private var installed: [String: Int] = [:]

    private var budget: Int { budgetSnapshot }

    var body: some View {
        Form {
            Section {
                Text(PhoneModel.preamble)
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if !PhoneModelRuntime.shared.isSupported {
                Section {
                    Label(PhoneModelInstall.simulatorRefusal, systemImage: "desktopcomputer")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }

            Section {
                ForEach(PhoneModel.catalogue) { model in
                    row(model)
                }
            } header: {
                Text("Tried on this app")
            } footer: {
                Text(PhoneModelInstall.staysOpenNote + " " + PhoneModelInstall.cellularWarning)
            }

            Section {
                HStack {
                    TextField("Search mlx-community", text: $search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { Task { await runSearch() } }
                    Button("Find") { Task { await runSearch() } }
                        .disabled(searching)
                }
                if let searchFailure {
                    Text(searchFailure).font(.footnote).foregroundStyle(.orange)
                }
                ForEach(hits) { hit in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.name).font(.subheadline)
                            Text("\(hit.downloads) downloads")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add") { Task { await vetThenAdd(hit) } }
                            .buttonStyle(.borderless)
                            .disabled(busyWith != nil)
                    }
                }
            } header: {
                Text("Anything else")
            } footer: {
                Text(PhoneModelSearch.scopeNote)
            }

            Section {
                Text(PhoneModel.versusApple)
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let failure {
                Section { Text(failure).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Download a model")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task {
            budgetSnapshot = Int(os_proc_available_memory())
            refreshInstalled()
        }
        .onDisappear { job?.cancel() }
    }

    @ViewBuilder private func row(_ model: PhoneModel) -> some View {
        let bytes = installed[model.repository]
        let fits = model.fits(budgetBytes: budget)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(.subheadline.weight(.medium))
                    Text("\(model.parameters) · \(model.downloadDescription)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                if busyWith == model.repository {
                    ProgressView()
                } else if bytes != nil {
                    Button(role: .destructive) { remove(model) } label: { Text("Delete") }
                        .buttonStyle(.borderless)
                } else {
                    Button("Download") { download(model) }
                        .buttonStyle(.borderless)
                        .disabled(!fits || !PhoneModelRuntime.shared.isSupported
                                  || busyWith != nil)
                }
            }

            Text(model.note).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // THE STATE LINE, AND EVERY VERSION OF IT IS A TESTED SENTENCE.
            if busyWith == model.repository, let progress {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: min(max(progress.fraction, 0), 1))
                    Text(PhoneModelInstall.downloading(fraction: progress.fraction,
                                                       totalBytes: progress.total))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let bytes {
                Text(PhoneModelInstall.installed(bytes: bytes))
                    .font(.caption).foregroundStyle(.green)
            } else if !fits {
                Text(PhoneModel.tooBig(model, budgetBytes: budget))
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(PhoneModelInstall.notDownloaded(model))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - doing it

    private func refreshInstalled() {
        var found: [String: Int] = [:]
        for model in PhoneModel.catalogue {
            if let bytes = PhoneModelFiles.bytesOnDisk(model.repository) { found[model.repository] = bytes }
        }
        installed = found
    }

    private func download(_ model: PhoneModel) {
        busyWith = model.repository
        failure = nil
        progress = nil
        job = Task { @MainActor in
            defer { busyWith = nil; progress = nil; refreshInstalled() }
            do {
                try await PhoneModelRuntime.shared.load(model.repository) { made in
                    Task { @MainActor in
                                progress = (made.fractionCompleted, Int(made.totalUnitCount))
                    }
                }
                add(repository: model.repository, named: model.name)
                // LET GO UNLESS IT IS THE CHOSEN ONE. Loading is what proves
                // the repository actually opens — which is the whole reason
                // `downloadedButWouldNotOpen` exists — but holding two
                // gigabytes resident afterwards flips every other row to "too
                // big" while the sheet is still open.
                if store.selected.model != model.repository {
                    PhoneModelRuntime.shared.unload(ifHolding: model.repository)
                }
            } catch is CancellationError {
                // Leaving the screen is not a failure to report back to it.
            } catch let error as PhoneModelRuntime.Failure {
                failure = PhoneModelInstall.failed(error.message)
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                failure = PhoneModelInstall.failed(error.localizedDescription)
            }
        }
    }

    /// ONE DELETE, NOT TWO. This called `PhoneModelFiles.delete` and then
    /// `store.delete`, which deletes the weights again — harmless only by
    /// accident, and exactly the kind of duplication that becomes a bug when
    /// one of the two grows a side effect.
    private func remove(_ model: PhoneModel) {
        let rows = store.endpoints.filter {
            $0.kind == .downloadedMLX && $0.model == model.repository
        }
        if rows.isEmpty {
            PhoneModelRuntime.shared.unload(ifHolding: model.repository)
            PhoneModelFiles.delete(model.repository)
        } else {
            // `EndpointStore.delete` frees the weights for this kind.
            rows.forEach(store.delete)
        }
        refreshInstalled()
    }

    /// Save it as an endpoint so it appears beside every other model.
    private func add(repository: String, named name: String) {
        guard !store.endpoints.contains(where: {
            $0.kind == .downloadedMLX && $0.model == repository
        }) else { return }
        var endpoint = ModelEndpoint(name: name, kind: .downloadedMLX,
                                     baseURL: "", model: repository)
        endpoint.relay = false
        do {
            try endpoint.validate()
            store.save(endpoint)
        } catch let refusal as ModelEndpoint.Refusal {
            failure = refusal.message
        } catch {
            failure = error.localizedDescription
        }
    }

    /// TWO REQUESTS BEFORE ANY BYTES ARE SPENT, both cheap, both guarding a
    /// measured trap: a repository holding no weights at all, and one quantised
    /// in a scheme this loader cannot read. Either otherwise ends in a full
    /// download that will not open.
    @MainActor private func vetThenAdd(_ hit: PhoneModelSearch.Hit) async {
        busyWith = hit.repository
        failure = nil
        defer { busyWith = nil }
        do {
            let (tree, _) = try await URLSession.shared.data(
                from: PhoneModelSearch.treeURL(for: hit.repository))
            let shape = try PhoneModelSearch.readTreeShape(tree)
            guard shape.hasWeights else {
                failure = PhoneModelSearch.noWeights
                return
            }
            let (config, _) = try await URLSession.shared.data(
                from: PhoneModelSearch.configURL(for: hit.repository))
            guard PhoneModelSearch.canLoadQuantisation(config) else {
                failure = PhoneModelSearch.unreadableQuantisation
                return
            }
            // The size is known now, so the fit is judged before starting.
            if let refusal = PhoneModelSearch.doesNotFit(hit.name, bytes: shape.bytes,
                                                         budgetBytes: budget) {
                failure = refusal
                return
            }
            add(repository: hit.repository, named: hit.name)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func runSearch() async {
        searching = true; searchFailure = nil
        defer { searching = false }
        do {
            let (data, _) = try await URLSession.shared.data(
                from: PhoneModelSearch.url(matching: search))
            hits = try PhoneModelSearch.read(data, matching: search)
        } catch let error as PhoneModelSearch.ReadError {
            hits = []
            searchFailure = error.message
        } catch {
            hits = []
            searchFailure = error.localizedDescription
        }
    }
}
