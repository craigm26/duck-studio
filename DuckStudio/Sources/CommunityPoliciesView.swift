import SwiftUI
import DuckKit
import StudioKit

/// What other people have trained for this robot.
///
/// A POLICY WITHOUT ITS MANIFEST IS A NETWORK NOBODY CAN DRIVE. The `.onnx`
/// states its input and output widths and nothing else; it does not say that
/// command slot 0 is a flag rather than a forward velocity, which is exactly
/// the difference between `flamingo-cycle` standing on one foot and it trying
/// to walk. So this screen leads with the manifest: what the slots mean, what
/// the author measured, and what the author says breaks it.
///
/// NOTHING LEAVES THE DEVICE UNTIL ASKED, the same as the Pollen catalogue —
/// the address is printed first and the scan is a button.
///
/// EVERY REPOSITORY HERE WEARS THE LAVENDER PILL, and that is the point of it.
/// This screen and the Pollen catalogue look alike on purpose — same rows, same
/// buttons, same manifests — so the one thing that must never blur is who
/// published the file. `CatalogueOriginPill` says it in a word, in the colour
/// the palette keeps for the least-frequent thing the app reports, on every row.
/// It is not a warning. A community policy is not worse; it is differently
/// sourced, and the sourcing is what a person needs to be able to see.
///
/// THE SEAL NO LONGER STANDS ALONE. The `microduck-policy` tag used to be a bare
/// checkmark glyph in a section header — which said "this repository claims to
/// hold a policy" to sighted people and nothing to anybody else. It is now a
/// glyph with the word beside it, in the body of the row, under the sentence
/// that says a tag is a courtesy rather than a proof.
struct CommunityPoliciesView: View {
    @ObservedObject var model: LibraryModel

    @State private var entries: [PolicyCatalogue.CommunityEntry] = []
    @State private var manifests: [String: PolicyManifest] = [:]
    /// The manifest bytes as fetched, so an install can store the file itself
    /// rather than a re-encoding of this app's understanding of it.
    @State private var manifestBytes: [String: Data] = [:]
    @State private var noManifest: Set<String> = []
    @State private var busy = false
    @State private var working: String?
    @State private var failure: String?
    @State private var pastedText = ""
    /// References that arrived by paste, keyed by repository — they can name a
    /// revision or a file the browse path never would.
    @State private var pasted: [String: PolicyCatalogue.CommunityReference] = [:]
    @FocusState private var typing: Bool

    private var listing: PolicySource.Request { PolicyCatalogue.communityListing() }

    var body: some View {
        List {
            Section {
                Text("Anyone can train a Microduck policy and publish it. These are the ones on Hugging Face tagged for this robot.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // MONO BECAUSE IT IS AN ADDRESS, printed before anything is
                // fetched and selectable, so somebody can read exactly where the
                // request is about to go.
                Text(listing.displayURL)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SectionHeading(text: "Where to look")
            }
            .listRowBackground(Theme.surfacePrimary)

            pasteSection

            Section {
                // THE THING SOMEBODY CAME HERE TO DO, so it is the capsule in
                // the action colour and every other control on the screen is
                // quieter than it.
                Button {
                    Task { await scan() }
                } label: {
                    Label(busy ? "Scanning…" : "Scan for shared policies",
                          systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .disabled(busy)
                .listRowSeparator(.hidden)
                .accessibilityLabel(Text("Scan for shared policies"))
                .accessibilityValue(Text(busy ? "Scanning" : ""))
            }
            .listRowBackground(Theme.surfacePrimary)

            if let failure {
                Section {
                    // SOMEBODY SAID NO, IN THEIR OWN WORDS. `Theme.refused` is
                    // the provenance colour for exactly that.
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            ForEach(entries) { entry in
                Section {
                    entryHeadline(entry)
                    if let manifest = manifests[entry.id] {
                        card(manifest, entry: entry)
                    } else if noManifest.contains(entry.id) {
                        // The honest version of "we could not import this".
                        // SECONDARY AND NOT REFUSED: nothing refused anything,
                        // and the sentence itself says the policy may be fine.
                        Label("No Microduck manifest in this repository, so what its command "
                              + "block means is not written down anywhere. It may still be a "
                              + "fine policy — it cannot be driven correctly from here.",
                              systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Link("Open it on Hugging Face", destination: URL(string: entry.webURL)!)
                            .font(.caption)
                            .foregroundStyle(Theme.actionSecondary)
                    }
                } header: {
                    HStack(spacing: Theme.spacing(.tight)) {
                        // MONO BECAUSE `owner/name` IS BOTH THE ADDRESS AND THE
                        // IDENTITY, and it is the string somebody compares
                        // against a link they were sent.
                        Text(entry.id)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: Theme.spacing(.tight))
                        CatalogueOriginPill(origin: .community)
                    }
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            Section {
                Text("The tag is a courtesy, not a proof. What decides whether a shared network can be driven here is its manifest — Pollen's sharing format, the same one their own policies carry.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S GREY,
        // and every row keeps a real `surfacePrimary` card under it — so no word
        // on this screen is set on `backgroundSecondary`, which the palette
        // documents as short of 4.5:1 for the four inks.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Community policies")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - pasting one in

    /// STACKED RATHER THAN A FIELD AND A BUTTON SHARING A LINE. An address field
    /// and a 44pt capsule cannot both have the width at an accessibility text
    /// size, and what loses is the button — which is to say the app takes the
    /// paste and then hides the way to open it.
    private var pasteSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                // MONO BECAUSE IT IS AN ADDRESS BEING RETYPED, character by
                // character, off somebody else's screen.
                TextField("huggingface.co/owner/name", text: $pastedText)
                    .textFieldStyle(.plain)
                    .font(.callout.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .onSubmit { Task { await open(pastedText) } }
                    .padding(.horizontal, Theme.spacing(.snug))
                    .frame(maxWidth: .infinity,
                           minHeight: ConnectivityMetric.minimumTarget,
                           alignment: .leading)
                    .background(field.fill(Theme.surfaceInteractive))
                    .overlay(field.strokeBorder(Theme.separator,
                                                lineWidth: ConnectivityMetric.hairlineStroke))
                    .accessibilityLabel(Text("Repository address"))
                Button("Open") { Task { await open(pastedText) } }
                    .buttonStyle(.connectivityAction)
                    .disabled(pastedText.trimmingCharacters(in: .whitespaces).isEmpty
                              || working != nil)
                    .accessibilityHint(Text("Reads the manifest at this address."))
            }
        } header: {
            SectionHeading(text: "Paste a link")
        } footer: {
            Text("The repository page, an owner/name, or a link straight to the file — blob or resolve, either works. Anything that is not a policy file is taken to mean the repository it sits in.")
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// A field is a control, so it takes the control radius — one step down from
    /// the card it sits inside, which is the concentric rule the whole app
    /// follows rather than a corner picked to look right.
    private var field: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radius(.control), style: .continuous)
    }

    // MARK: - one repository

    /// The name, who wrote it, whether it wears the tag, and the one button.
    private func entryHeadline(_ entry: PolicyCatalogue.CommunityEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Text(entry.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("by \(entry.author)\(entry.updated.map { " · \($0)" } ?? "")")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if entry.declaresPolicyTag {
                // THE SEAL WITH ITS WORD BESIDE IT. The tag is the only thing
                // separating a repository that says it holds a Microduck policy
                // from one that merely turned up in the search; drawn as a bare
                // symbol it said that to sighted people only.
                Label("Tagged microduck-policy", systemImage: "checkmark.seal")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if working == entry.id {
                // THE WORD, NOT A SPINNER — and the two jobs this spot can be
                // doing are different enough to name apart.
                Text(manifests[entry.id] == nil ? "Reading…" : "Adding…")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else if manifests[entry.id] == nil && !noManifest.contains(entry.id) {
                Button("Read") { Task { await readManifest(entry) } }
                    .buttonStyle(.connectivityAction)
                    .accessibilityLabel(Text("Read the manifest for \(entry.name)"))
                    .accessibilityHint(Text(
                        "Fetches the manifest that says what this policy's command block means."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func card(_ manifest: PolicyManifest, entry: PolicyCatalogue.CommunityEntry) -> some View {
        if let summary = manifest.summary {
            Text(summary)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let command = manifest.command, !command.twist.isEmpty {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                Text("What you send it")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(Array(command.twist.enumerated()), id: \.offset) { index, meaning in
                    Text("twist[\(index)] — \(meaning)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // THE THREE NUMBERS THAT DECIDE WHETHER IT CAN BE DRIVEN, each as a
        // `TelemetryRow`. They were a single `caption2` line of three chips,
        // which at an accessibility size wrapped into a paragraph and reached
        // VoiceOver as one utterance nobody could skip through. Every one of
        // them is different for every policy, which is the claim monospace
        // makes — and stacked, the label and the value each get the whole width.
        TelemetryRow(label: "Observation → action",
                     value: "\(manifest.observationLength) → \(manifest.actionLength)")
        if let hz = manifest.controlHz {
            TelemetryRow(label: "Control rate", value: "\(Int(hz))", unit: "Hz")
        }
        if let kind = manifest.kind {
            // NOT A `TelemetryRow`: a kind is a name, it sits still for the life
            // of the policy, and tabular figures on it would tell the reader to
            // watch something that is never going to move.
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
                Text("Kind")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: Theme.spacing(.tight))
                Text(kind)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }

        if manifest.isRunnableHere {
            Button {
                Task { await install(entry, manifest: manifest) }
            } label: {
                Label("Add to my policies", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .disabled(working == entry.id)
            .listRowSeparator(.hidden)
            .accessibilityHint(Text(
                "Downloads the weights and keeps the manifest beside them."))
        } else {
            // IT CANNOT BE DRIVEN HERE, WHICH IS A REFUSAL — the app saying no,
            // in the kit's words, for a reason the kit can name. `Theme.refused`
            // is the colour that claim is made in everywhere else in the app.
            ForEach(manifest.incompatibilities, id: \.self) { problem in
                Label(problem.message, systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // THE AUTHOR'S OWN CAUTIONS, IN THE WARNING REGISTER. Nothing here said
        // no — somebody who trained this network wrote down what breaks it, and
        // a triangle in grey reads as a footnote rather than as the thing they
        // took the trouble to say.
        ForEach(manifest.cautions, id: \.self) { caution in
            Label(caution, systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let training = manifest.training, let task = training.taskID {
            Text("Trained as \(task)\(training.run.map { " · run \($0)" } ?? "")")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - the network

    private func scan() async {
        busy = true; failure = nil; entries = []
        defer { busy = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: listing.url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = "\(listing.host) answered \(http.statusCode)."
                return
            }
            entries = try PolicyCatalogue.parseCommunity(data)
            if entries.isEmpty { failure = "Nobody has published one yet." }
        } catch {
            failure = "\(error.localizedDescription)"
        }
    }

    /// Open whatever was pasted: resolve it, read its manifest, and put it at
    /// the top of the list so it reads exactly like a browsed one.
    private func open(_ text: String) async {
        failure = nil
        let reference: PolicyCatalogue.CommunityReference
        do {
            reference = try PolicyCatalogue.communityReference(from: text)
        } catch let error as PolicyCatalogue.ReferenceError {
            failure = error.message
            return
        } catch {
            failure = "\(error.localizedDescription)"
            return
        }
        typing = false
        pasted[reference.repository] = reference
        let owner = String(reference.repository.split(separator: "/").first ?? "")
        let entry = PolicyCatalogue.CommunityEntry(
            id: reference.repository, author: owner, updated: nil,
            downloads: 0, likes: 0, declaresPolicyTag: false)
        if !entries.contains(where: { $0.id == entry.id }) {
            entries.insert(entry, at: 0)
        }
        pastedText = ""
        await readManifest(entry)
    }

    private func readManifest(_ entry: PolicyCatalogue.CommunityEntry) async {
        working = entry.id; failure = nil
        defer { working = nil }
        do {
            let request = try (pasted[entry.id]?.manifestRequest()
                               ?? PolicySource.huggingFaceManifest(repository: entry.id))
            let (data, response) = try await URLSession.shared.data(from: request.url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                noManifest.insert(entry.id)
                return
            }
            manifests[entry.id] = try PolicyManifest.decode(data)
            manifestBytes[entry.id] = data
        } catch let error as PolicyManifest.ReadError {
            if case .unsupportedSchema(let version) = error {
                failure = "\(entry.name) is written in sharing format \(version), which this "
                        + "version of the app has not been taught to read."
            } else {
                noManifest.insert(entry.id)
            }
        } catch {
            failure = "\(error.localizedDescription)"
        }
    }

    private func install(_ entry: PolicyCatalogue.CommunityEntry, manifest: PolicyManifest) async {
        working = entry.id; failure = nil
        defer { working = nil }
        do {
            let request = try (pasted[entry.id]?.policyRequest()
                               ?? PolicySource.huggingFace(repository: entry.id, file: "policy.onnx"))
            let (data, response) = try await URLSession.shared.data(from: request.url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = "\(request.host) answered \(http.statusCode)."
                return
            }
            guard data.count <= PolicySource.byteCap else {
                failure = "That file is larger than this app will load."
                return
            }
            // THE REAL DOWNLOADED FILE NAME, NOT A FABRICATED ONE. This used to
            // hand over `"\(manifest.name).onnx"` — a string this screen made
            // up — as if it were the name of the file it had just fetched, and
            // then look the entry back up by that same invention to attach the
            // manifest. The lookup missed on every already-held policy, the
            // manifest was silently dropped, and the bench fell back to
            // guessing the action scale from a name that matched nothing.
            //
            // ONE CALL NOW CARRIES ALL THREE: the file's own name, the author's
            // word for the policy, and the manifest bytes this screen already
            // has in hand.
            model.accept(data, named: request.url.lastPathComponent,
                         origin: "huggingface.co/\(entry.id)",
                         title: manifest.name, manifest: manifestBytes[entry.id])
        } catch {
            failure = "\(error)"
        }
    }
}
