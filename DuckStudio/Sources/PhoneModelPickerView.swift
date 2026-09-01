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
///
/// AND EVERY ONE OF THEM IS SET IN FIGURES THAT DO NOT MOVE. A size, a download
/// count and a rate are read against the rows above and below them, which is
/// the whole case for tabular digits; the model's name and its note are prose
/// and stay in SF.
///
/// NEVER A BARE BAR. The bill under a download is the app's one pointing
/// gesture — "this much, from here" — and the sentence beside it is
/// `DownloadRate.line`, which carries the percent, the megabytes, the speed and
/// the time left. A filled shape on its own says "some", and somebody watching
/// two gigabytes arrive over a hotel Wi-Fi needs the other four facts.
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
    /// Measured from successive progress samples, so the line can say how fast
    /// and how long — which a filling bar cannot.
    @State private var rate = DownloadRate()
    @State private var failure: String?
    /// State AND size. Holding only the size meant any directory with a file
    /// in it read as installed — which is how 14 MB of tokenizer JSON showed as
    /// "On this phone" with a Delete button and no way to finish the download.
    @State private var installed: [String: (state: PhoneModelInstall.InstallState, bytes: Int)] = [:]

    private var budget: Int { budgetSnapshot }

    var body: some View {
        Form {
            Section {
                Text(PhoneModel.preamble)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            if !PhoneModelRuntime.shared.isSupported {
                Section {
                    // A REFUSAL, NOT A WARNING. Nothing here can be made to
                    // work on this machine — there is no download to retry and
                    // no setting to change — so it takes the colour this app
                    // uses for "no", and the words say the same thing.
                    Label(PhoneModelInstall.simulatorRefusal, systemImage: "desktopcomputer")
                        .font(.footnote).foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            Section {
                ForEach(PhoneModel.catalogue) { model in
                    row(model)
                }
            } header: {
                Text("Tried on this app")
            } footer: {
                Text(PhoneModelInstall.staysOpenNote + " " + PhoneModelInstall.cellularWarning)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                HStack(spacing: Theme.spacing(.tight)) {
                    TextField("Search mlx-community", text: $search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { Task { await runSearch() } }
                    // THE PADDING IS INSIDE THE LABEL, WHICH IS THE ONLY PLACE
                    // IT ENLARGES ANYTHING. Applied after `.buttonStyle`, it
                    // grows the view the button is wrapped in and leaves the
                    // control's own hit region at the size of the word —
                    // "Find" at the body size is about thirty-four points by
                    // twenty-two, and a `.contentShape` out there is shaping a
                    // wrapper that was never doing the hit-testing. Inside the
                    // label the style measures the padded text, so the padding
                    // IS the target and the shape makes the transparent part of
                    // it pressable.
                    //
                    // AND THE FLOOR IS ASSERTED RATHER THAN ARRIVED AT. Twelve
                    // points above and below a body-size word is forty-four at
                    // the default text size and less than that at the smallest
                    // one, so the frame states the minimum instead of leaving
                    // it to be recomputed from a font metric.
                    //
                    // `.borderless` IS THE STOCK STYLE THIS ROW HAD. It takes
                    // the app's tint — `Theme.actionSecondary`, set once in
                    // `MicroduckTheme` — for its word, and greys that word when
                    // the button is disabled. The hand-rolled version set the
                    // action colour itself, so a `Find` disabled mid-search
                    // stayed orange and read as pressable.
                    Button {
                        Task { await runSearch() }
                    } label: {
                        Text("Find")
                            .padding(.vertical, Theme.spacing(.snug))
                            .padding(.leading, Theme.spacing(.snug))
                            .frame(minWidth: ConnectivityMetric.minimumTarget,
                                   minHeight: ConnectivityMetric.minimumTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(searching)
                }
                if searching {
                    ProgressView().tint(Theme.brandPrimary)
                }
                if let searchFailure {
                    Text(searchFailure).font(.footnote).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(hits) { hit in
                    hitRow(hit)
                }
            } header: {
                Text("Anything else")
            } footer: {
                Text(PhoneModelSearch.scopeNote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Text(PhoneModel.versusApple)
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            if let failure {
                Section {
                    Text(failure).font(.footnote).foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        // THE RECESSED GROUND UNDER THE CARDS. Every coloured word on this
        // screen sits on a `surfacePrimary` row, because `Palette` documents
        // this ground as carrying the inks short of what body text owes.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Download a model")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task {
            budgetSnapshot = Int(os_proc_available_memory())
            refreshInstalled()
            // WARMED BEFORE THE FIRST ARRIVAL, NOT AT IT. The taptic engine
            // spins up on demand, and the tap that says two gigabytes finished
            // is worth nothing if it lands after the row has already gone green.
            Haptic.prepare()
        }
        .onDisappear { job?.cancel() }
    }

    /// One model from the catalogue: what it is, what it costs, where it stands,
    /// and the one or two things that can be done about it.
    ///
    /// THE ACTIONS SIT UNDER THE ROW RATHER THAN BESIDE THE NAME. They were a
    /// pair of borderless words in the trailing corner — targets under the
    /// HIG's forty-four points, on the control that spends two gigabytes of
    /// somebody's data plan. Downloading is what this screen is for, so it
    /// takes the action colour and the room a real control needs; deleting
    /// keeps a word and the destructive colour beside it.
    @ViewBuilder private func row(_ model: PhoneModel) -> some View {
        let here = installed[model.repository]
        let fits = model.fits(budgetBytes: budget)

        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(model.name).font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // THE SIZE IS THE FIGURE PEOPLE COMPARE ROWS BY, so it is the
                // one part of this line in tabular digits.
                Text("\(model.parameters) · \(model.downloadDescription)")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }

            Text(model.note).font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // THE STATE LINE, AND EVERY VERSION OF IT IS A TESTED SENTENCE.
            if busyWith == model.repository, let progress {
                downloading(progress)
            } else if let here, here.state == .complete {
                Text(PhoneModelInstall.installed(bytes: here.bytes))
                    .font(.caption).foregroundStyle(Theme.success)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let here {
                Text(PhoneModelInstall.partlyDownloaded(bytes: here.bytes))
                    .font(.caption).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !fits {
                // IT WILL NOT FIT IS A REFUSAL AND NOT A CAUTION. iOS would
                // kill the app part-way through, which is not something the
                // person can push past by being careful.
                Text(PhoneModel.tooBig(model, budgetBytes: budget))
                    .font(.caption).foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(PhoneModelInstall.notDownloaded(model))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions(model, here: here)
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }

    /// The bill, and the sentence that says what it means.
    ///
    /// THE FIGURE IS IN THE SENTENCE, WHICH IS WHERE IT ALREADY LIVES.
    /// `DownloadRate.line` composes the percent, the megabytes so far, the
    /// speed and the time remaining in one tested string; printing a second
    /// percent beside the bar would be a second source of truth for the same
    /// quantity, rounded in a different place.
    private func downloading(_ progress: (fraction: Double, total: Int)) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            BillIndicator(fill: progress.fraction)
            Text(rate.line(fraction: progress.fraction, totalBytes: progress.total))
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // THE PAIR IS ONE THING TO HEAR. The bill draws a number the sentence
        // states, and `BillIndicator` is silent unless it is given a label
        // precisely so it does not become an unnamed graphic in the rotor.
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actions(_ model: PhoneModel,
                         here: (state: PhoneModelInstall.InstallState, bytes: Int)?) -> some View {
        if busyWith == model.repository {
            ProgressView().tint(Theme.brandPrimary)
        } else if here?.state == .complete {
            deleteButton(model)
        } else {
            // A PARTIAL GETS BOTH. Downloading again is the resume —
            // files that finished are skipped — and deleting is the way
            // out of a download that will not finish.
            //
            // WIDEST FIRST. Two controls at their real sizes do not share a
            // line on the narrowest phone still supported, and the alternative
            // to stacking them is truncating the verb on the button that
            // spends two gigabytes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.spacing(.tight)) {
                    downloadButton(model, here: here)
                    if here != nil { deleteButton(model) }
                }
                VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                    downloadButton(model, here: here)
                    if here != nil { deleteButton(model) }
                }
            }
        }
    }

    private func downloadButton(_ model: PhoneModel,
                                here: (state: PhoneModelInstall.InstallState, bytes: Int)?)
        -> some View {
        Button(here == nil ? "Download" : "Resume") { download(model) }
            .buttonStyle(.primaryAction)
            .disabled(!PhoneModelRuntime.shared.isSupported || busyWith != nil)
            .accessibilityLabel(Text(here == nil ? "Download" : "Resume"))
            .accessibilityValue(Text(model.name))
    }

    /// Deleting keeps a word and the app's own red, and it is not a capsule:
    /// the design system's filled shape is for the thing you are meant to
    /// press, and this is the thing you are meant to find when you need it.
    private func deleteButton(_ model: PhoneModel) -> some View {
        Button(role: .destructive) { remove(model) } label: {
            Text("Delete")
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.critical)
                .padding(.horizontal, Theme.spacing(.loose))
                .padding(.vertical, Theme.spacing(.snug))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Delete"))
        .accessibilityValue(Text(model.name))
    }

    /// One search result: a repository nobody has tried on this app, and how
    /// many people have pulled it.
    private func hitRow(_ hit: PhoneModelSearch.Hit) -> some View {
        HStack(spacing: Theme.spacing(.tight)) {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text(hit.name).font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // A COUNT THAT DIFFERS BY ORDERS OF MAGNITUDE BETWEEN ROWS, and
                // the only thing on this row a person ranks the results by — so
                // it is in tabular digits and the word beside it is not.
                HStack(spacing: Theme.spacing(.hairline)) {
                    Text("\(hit.downloads)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Text("downloads")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: Theme.spacing(.tight))
            // THE SAME TARGET THE SEARCH BUTTON GETS, AND FOR THE SAME REASON:
            // the padding lives inside the label so the control is what grew,
            // the frame states the forty-four rather than hoping the type size
            // supplies it, and `.borderless` is the stock style, which greys
            // its own word while a download holds this row disabled.
            Button {
                Task { await vetThenAdd(hit) }
            } label: {
                Text("Add")
                    .padding(.vertical, Theme.spacing(.snug))
                    .padding(.leading, Theme.spacing(.snug))
                    .frame(minWidth: ConnectivityMetric.minimumTarget,
                           minHeight: ConnectivityMetric.minimumTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(busyWith != nil)
            .accessibilityLabel(Text("Add"))
            .accessibilityValue(Text(hit.name))
        }
    }

    // MARK: - doing it

    /// BOTH LISTS. This walked `catalogue` only, so an untried model could
    /// never show as installed however much of it was on the phone.
    private func refreshInstalled() {
        var found: [String: (PhoneModelInstall.InstallState, Int)] = [:]
        for model in PhoneModel.all {
            let contents = PhoneModelFiles.contents(model.repository)
            let state = PhoneModelInstall.state(paths: contents.paths,
                                                indexJSON: contents.index,
                                                bytes: contents.bytes)
            if state != .absent { found[model.repository] = (state, contents.bytes) }
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
                rate = DownloadRate()
                try await PhoneModelRuntime.shared.load(model.repository) { made in
                    // READ THE NUMBERS HERE, NOT INSIDE THE TASK, or the rate is
                    // computed from a moment other than the one reported.
                    //
                    // AND COMPLETED COMES FROM THE FRACTION. The parent Progress
                    // aggregates its children through `fractionCompleted`; its
                    // own completedUnitCount does not advance, so a rate fed
                    // from that sees a delta of zero every time.
                    let fraction = made.fractionCompleted
                    let total = Int(made.totalUnitCount)
                    let done = Int(fraction * Double(total))
                    let at = Date().timeIntervalSince1970
                    Task { @MainActor in
                        rate.observe(completedBytes: done, totalBytes: total, at: at)
                        progress = (fraction, total)
                    }
                }
                add(repository: model.repository, named: model.name)
                // TWO GIGABYTES ARRIVING IS THE PLAINEST WORLD EVENT THIS APP
                // HAS. It takes long enough that nobody watches the whole of
                // it, the note above says the screen has to stay open, and the
                // taptic engine is the only channel left to somebody whose
                // phone is face down on a desk. `finished` is the design
                // system's feeling for "the thing you asked for ran to the end".
                Haptic.finished()
                // LET GO UNLESS IT IS THE CHOSEN ONE. Loading is what proves
                // the repository actually opens — which is the whole reason
                // `downloadedButWouldNotOpen` exists — but holding two
                // gigabytes resident afterwards flips every other row to "too
                // big" while the sheet is still open.
                if store.selected.model != model.repository {
                    PhoneModelRuntime.shared.unload(ifHolding: model.repository)
                }
            } catch is CancellationError {
                // SAID, NOT SWALLOWED. Silence here is indistinguishable from
                // success: the row simply stops moving, and with a partial on
                // disk it used to go green. Whatever stopped it, the person
                // needs to know it stopped.
                failure = PhoneModelInstall.stopped
            } catch let error as URLError where error.code == .cancelled {
                failure = PhoneModelInstall.stopped
            } catch let error as PhoneModelRuntime.Failure {
                failure = PhoneModelInstall.failed(error.message)
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
