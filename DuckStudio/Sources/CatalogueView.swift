import SwiftUI
import DuckKit
import DuckEvidence
import StudioKit

/// Go and see what Pollen currently publish.
///
/// THE APP'S OWN LIST IS FROZEN AT BUILD TIME and Pollen keep training, so a
/// release newer than this build shows up in the library as "unrecognised" —
/// honest, and unhelpful. This is the difference between "I have not heard of
/// this" and "here is what exists".
///
/// NOTHING IS FETCHED UNTIL SOMEBODY ASKS. The address is printed first, whole,
/// and the scan button sits under it: a request leaving the device because a
/// screen appeared is the shape of an accident.
///
/// WHOSE FILE THIS IS, IN A PILL. Everything on this screen came out of a
/// repository Pollen own, and everything one tap away came out of a repository
/// somebody else owns — and the app's whole posture is that those two are
/// different claims. `CatalogueOriginPill` says which, in a word, in the two
/// colours the palette keeps for exactly that pair: brand teal for the robot's
/// own publisher, training lavender for everybody else.
///
/// SPINNERS ARE WORDS HERE. Every `ProgressView` on this screen has been
/// replaced by the word for what is happening — "Scanning…", "Opening…" — for
/// the same reason `LensIndicator` exists on the connectivity screens: a
/// spinner is a claim that this phone is busy, and what is actually happening is
/// that somebody else's server is being asked a question. The word is also the
/// only version of it a screen reader can read.
struct CatalogueView: View {
    @ObservedObject var model: LibraryModel

    /// So the two rows that put a provenance pill beside something else can
    /// stack instead of fighting for the width. See `provenance(origin:content:)`.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var source = PolicyCatalogue.officialPolicies
    @State private var entries: [PolicyCatalogue.Entry] = []
    @State private var headline: String?
    @State private var failure: String?
    @State private var busy = false
    @State private var fetching: String?

    var body: some View {
        List {
            Section {
                Picker("Repository", selection: $source) {
                    ForEach(PolicyCatalogue.sources) { s in
                        Text(s.name).tag(s)
                    }
                }
                .pickerStyle(.menu)
                Text(source.holds)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // MONO BECAUSE IT IS AN ADDRESS. This is printed before anything
                // is fetched and it is selectable, so somebody can read exactly
                // where the request is about to go and take it somewhere else.
                Text(source.webURL)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Where to look")
            } footer: {
                Text(PolicyCatalogue.tokenNote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                // THE THING SOMEBODY CAME HERE TO DO, so it is the one capsule
                // in the action colour and every other row on the screen stays a
                // row. `.primaryAction` rather than `.primaryActionMoves`: this
                // asks GitHub a question, and nothing on the robot moves.
                Button {
                    Task { await scan() }
                } label: {
                    Label(busy ? "Scanning…" : "Scan for what is published",
                          systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .disabled(busy)
                .listRowSeparator(.hidden)
                .accessibilityLabel(Text("Scan for what is published"))
                .accessibilityValue(Text(busy ? "Scanning" : ""))
            }
            .listRowBackground(Theme.surfacePrimary)

            if let failure {
                Section {
                    // A HOST SAID NO, IN ITS OWN WORDS. `Theme.refused` is the
                    // provenance colour for exactly that, and the sentence is
                    // whatever came back rather than a friendlier version of it.
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            if let headline {
                Section {
                    Text(headline)
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("What is there")
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                } footer: {
                    Text(isPolicySource
                         ? "Opening one downloads it and fingerprints its weights. That is the only thing that decides whether a file is a policy you already hold — upstream ships two of these under names this app carries differently."
                         : "These are the training environments. Every reward weight and tolerance in an intent's Reward panel is read out of these files.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            // A SENTENCE, NOT A SECOND DOOR. This carried a `NavigationLink` to
            // the community catalogue, which made Behaviours → Discover →
            // Pollen Robotics → Community a real path to a screen that is
            // Pollen's sibling and not its child — and pushing it here left
            // somebody two backs deep in the wrong provenance. Both catalogues
            // are rows in Discover now, side by side, one back from this screen.
            // The claim the section was making is worth keeping; the extra door
            // was teaching the wrong shape.
            Section {
                Text("Pollen are not the only people training this robot any more. Other authors publish policies on Hugging Face, each with a manifest saying what its command block means — they are under Discover, beside this catalogue.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("And everyone else")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Text(PolicyCatalogue.intentsNote)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("And motions?")
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S GREY,
        // and every row keeps a real `surfacePrimary` card under it — so no word
        // on this screen is set on `backgroundSecondary`, which the palette
        // documents as short of 4.5:1 for the four inks.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Pollen Robotics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isPolicySource: Bool { source.id == PolicyCatalogue.officialPolicies.id }

    /// One file the repository is offering.
    ///
    /// STACKED RATHER THAN A FILENAME AND A BUTTON SHARING A LINE. At an
    /// accessibility text size a monospaced filename and a 44pt capsule cannot
    /// both have the width, and the one that loses is whichever is on the right —
    /// so the action disappears for the people who most enlarged the type.
    private func row(_ entry: PolicyCatalogue.Entry) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            provenance(origin: .pollen) {
                // MONO BECAUSE IT IS A FILENAME — a machine identifier somebody
                // matches against another one character by character.
                //
                // AND IT IS THE ONE ON THIS LINE THAT IS ALLOWED TO TRUNCATE,
                // which is a decision about which of the two a person can
                // recover. A filename cut in the middle still shows both ends,
                // and the whole of it is one tap away; a provenance word cut to
                // "Comm…" leaves the claim being made by the colour alone.
                Text(entry.filename)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(isPolicySource
                 ? PolicyCatalogue.summary(of: entry)
                 // A NUMBER BORN IN A VIEW, AND IT IS LEFT ALONE ON PURPOSE.
                 // `PolicyCatalogue.summary(of:)` formats a size for the policy
                 // branch and the kit's `byteCount` is internal to StudioKit, so
                 // there is nothing public to call here. It is reported rather
                 // than fixed, because fixing it means editing the kit.
                 : "\(entry.bytes / 1024) KB")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if fetching == entry.path {
                // THE WORD, NOT A SPINNER. It is also the only version of this a
                // screen reader has ever been able to read.
                Text("Opening…")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else if isPolicySource {
                Button("Open") { Task { await fetch(entry) } }
                    .buttonStyle(.connectivityAction)
                    .accessibilityLabel(Text("Open \(entry.filename)"))
                    .accessibilityHint(Text(
                        "Downloads this policy and fingerprints its weights."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Something, with the pill that says whose repository it came out of.
    ///
    /// AT ACCESSIBILITY SIZES IT STACKS RATHER THAN SQUEEZES, which is the
    /// argument `TelemetryRow` already makes about a label beside a value: two
    /// runs of text on one line at AX5 is a fight for the width that one of them
    /// has to lose, and here the loser is always the pill — it is the trailing
    /// item, and the leading one is a whole filename or a whole row title. What
    /// gets lost is the word "Pollen" or "Community", after which the provenance
    /// is being carried by a coloured capsule and nothing else. That is SC 1.4.1
    /// (Use of Colour) failing on the one claim this app is strictest about, and
    /// failing hardest for the people who enlarged the type in order to read it.
    ///
    /// STACKED, EACH GETS THE WHOLE WIDTH and neither has to give anything up.
    @ViewBuilder
    private func provenance<Content: View>(
        origin: CatalogueOriginPill.Origin,
        @ViewBuilder content: () -> Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                content()
                CatalogueOriginPill(origin: origin)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: Theme.spacing(.tight)) {
                content()
                Spacer(minLength: Theme.spacing(.tight))
                CatalogueOriginPill(origin: origin)
            }
        }
    }

    // MARK: - the network

    private func scan() async {
        busy = true; failure = nil; headline = nil; entries = []
        defer { busy = false }
        let request = PolicyCatalogue.listing(source)
        do {
            var urlRequest = URLRequest(url: request.url)
            // GitHub answers HTML to a request with no Accept header often
            // enough that asking explicitly is worth one line.
            urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = "\(request.host) answered \(http.statusCode)."
                return
            }
            let found = try PolicyCatalogue.parse(
                data, source: source,
                extensions: isPolicySource ? ["onnx"] : ["py"])
            entries = found
            headline = isPolicySource
                ? PolicyCatalogue.headline(found)
                : "\(found.count) training environments."
        } catch let error as PolicyCatalogue.ScanError {
            failure = {
                switch error {
                case .refused(let message): return "\(request.host) said: \(message)"
                case .notJSON: return "That address did not answer with JSON."
                case .noTree: return "The answer had no file list in it."
                }
            }()
        } catch {
            failure = "\(error.localizedDescription)"
        }
    }

    /// Download one policy and hand it to the library, which fingerprints it.
    private func fetch(_ entry: PolicyCatalogue.Entry) async {
        fetching = entry.path; failure = nil
        defer { fetching = nil }
        do {
            let request = try PolicyCatalogue.download(entry, from: source)
            let (data, response) = try await URLSession.shared.data(from: request.url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = "\(request.host) answered \(http.statusCode)."
                return
            }
            guard data.count <= PolicySource.byteCap else {
                failure = "That file is larger than this app will load."
                return
            }
            model.accept(data, named: request.suggestedName,
                         origin: "github.com/\(source.owner)/\(source.repository)")
        } catch {
            failure = "\(error)"
        }
    }
}

// MARK: - who published it

/// Whose repository a policy came out of, as a word in a pill.
///
/// PROVENANCE IS THE ONE THING THIS APP IS CONSISTENTLY STRICT ABOUT, and it is
/// already a colour scheme: teal is what a machine measured, yellow is what
/// somebody asked for, the critical colour is a refusal. This adds the pair the
/// catalogue needs — the robot's own publisher against everybody else — using
/// `brandPrimary` for Pollen, because their policies are what the robot ships
/// with, and `training`, the lavender the palette keeps for the least-frequent
/// thing the app reports, for the community. Neither is a judgement. A community
/// policy is not worse; it is differently sourced, and the difference is the
/// thing a person needs to be able to see.
///
/// THE WORD IS THE INFORMATION AND THE COLOUR IS A HINT, which is why this is a
/// pill with a word in it rather than a coloured dot or a tinted filename. It is
/// built the way `StateBadge` is built and for the same reason: the two hues sit
/// about two steps apart in the palette, and roughly one man in twelve cannot
/// reliably separate them.
///
/// THE FILL IS THE SURFACE, NOT THE HUE. `brandPrimary` and `training` are text
/// tokens — the palette proves them at 4.5:1 as words on the four grounds, and
/// proves nothing at all about words drawn ON them. So the hue sets the word and
/// the hairline, and the capsule keeps the surface it is sitting on.
struct CatalogueOriginPill: View {

    enum Origin {
        /// The trained networks that ship with the robot.
        case pollen
        /// Somebody else's, published on Hugging Face.
        case community

        /// One word, because it is a label and not a sentence.
        var word: String {
            switch self {
            case .pollen: return "Pollen"
            case .community: return "Community"
            }
        }

        /// Said in full for anybody being read to. "Pollen" alone in a rotor is
        /// a word with no claim attached to it.
        var spoken: String {
            switch self {
            case .pollen: return "Published by Pollen Robotics"
            case .community: return "Published by somebody in the community"
            }
        }

        var color: Color {
            switch self {
            case .pollen: return Theme.brandPrimary
            case .community: return Theme.training
            }
        }
    }

    let origin: Origin

    var body: some View {
        Text(origin.word)
            .font(.caption2.weight(.medium))
            .foregroundStyle(origin.color)
            // THE WORD IS NOT ALLOWED TO BE THE THING THAT GIVES WAY. One line,
            // and `fixedSize` so that line is measured at the width the word
            // actually needs rather than at whatever a row has left over. A
            // `lineLimit(1)` on its own is a promise to truncate: squeezed, this
            // pill said "Comm…" and the provenance fell back to a colour, which
            // is the one thing a pill built for SC 1.4.1 must never do. Wrapping
            // would not have saved it either — these are single words, and a
            // single word too wide for its line is truncated, not wrapped.
            //
            // A FIXED-WIDTH ITEM IN AN HSTACK IS SERVED FIRST, so the flexible
            // thing beside it — a filename, which is built to truncate in the
            // middle and is one tap from being read in full — is what shrinks.
            // At accessibility sizes `CatalogueView.provenance(origin:content:)`
            // stops asking them to share a line at all.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, Theme.spacing(.tight))
            .padding(.vertical, Theme.spacing(.hairline))
            .background(Capsule().fill(Theme.surfacePrimary))
            .overlay(Capsule().strokeBorder(origin.color,
                                            lineWidth: ConnectivityMetric.hairlineStroke))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(origin.spoken))
    }
}
