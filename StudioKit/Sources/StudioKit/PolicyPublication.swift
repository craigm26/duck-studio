import Foundation
import DuckKit

/// A policy on Hugging Face, in the shape the Behaviours tab's own Community
/// list reads back.
///
/// THE LOOP THIS CLOSES. The Community list is `PolicyCatalogue.communityListing`:
/// every model on the Hub tagged `microduck`, with its `manifest.json` read
/// for the card and `policy.onnx` fetched on a tap. Until now the only way onto
/// that list was a laptop and the `huggingface_hub` CLI, while a network made
/// on this phone left through the share sheet as bytes with no manifest. This
/// writes the three files that list expects — the network, its manifest and a
/// card carrying the tag — so a policy published from here appears on every
/// other phone's Community list, with the same card this app draws.
///
/// SAME RULES AS `MotionPublication`: it constructs and never sends; every
/// call is credential-free; publishing is public and not really undoable, and
/// the screen shows every byte first. What differs is the repository kind — a
/// network is a MODEL on the Hub, a move is a dataset — and the honesty the
/// card owes: a network made here was searched or tuned in a simulator, never
/// trained, never run on hardware, and the card says so before the tag does.
public struct PolicyPublication: Equatable, Sendable {

    /// THE BROAD TAG AND THE NARROW ONE. `microduck` is what the Community
    /// listing filters on; `microduck-policy` is what Pollen's own published
    /// policy carries and what `CommunityEntry.declaresPolicyTag` reads.
    public static let hubTags = ["microduck", "microduck-policy"]
    public static let repositoryKind = HuggingFacePublish.Repository.Kind.model
    /// `CommunityReference.policyFile`'s default, and `huggingFaceManifest`'s
    /// path: the two names the reader already knows.
    public static let policyPath = "policy.onnx"
    public static let manifestPath = "manifest.json"
    /// Repository names start with this so `CommunityEntry.name` shows the
    /// bare name, the way it does for Pollen's `microduck-flamingo-cycle`.
    public static let namePrefix = "microduck-"

    public let name: String
    public let slug: String
    public let whatItDoes: String
    public let files: [HuggingFacePublish.File]
    public let summary: String
    /// The parameter fingerprint, the one thing a recipient can check.
    public let fingerprint: String

    public var totalBytes: Int { files.reduce(0) { $0 + $1.bytes } }

    /// The repository name proposed for a policy.
    public static func slug(for title: String) -> String {
        let bare = MotionPublication.slug(for: title)
        let stem = bare == "microduck-motion" ? "policy" : bare
        return stem.hasPrefix(namePrefix) ? stem : namePrefix + stem
    }

    /// - Parameters:
    ///   - entry: the library entry, for its title, origin and fingerprint.
    ///   - onnx: the file's bytes, exactly as the library holds them.
    ///   - manifest: the manifest sidecar when the library has one — a kept
    ///     network's `made_here` record travels with it — or nil, in which
    ///     case one is written from what the entry knows.
    ///   - whatItDoes: the one sentence. Refused empty.
    public init(entry: PolicyLibrary.Entry, onnx: Data, manifest: Data?,
                whatItDoes: String, note: String? = nil) throws {
        let sentence = whatItDoes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { throw HuggingFacePublish.Refusal.noWhatItDoes }
        guard !onnx.isEmpty else { throw HuggingFacePublish.Refusal.nothingToPublish }
        name = entry.title
        self.whatItDoes = sentence
        slug = Self.slug(for: entry.title)
        fingerprint = entry.identity.value
        let manifestBytes = try Self.manifest(for: entry, held: manifest, whatItDoes: sentence)
        let decoded = try PolicyManifest.decode(manifestBytes)
        let card = Self.card(for: entry, manifest: decoded, whatItDoes: sentence, note: note)
        files = [
            .init(path: Self.policyPath, contents: onnx, isText: false),
            .init(path: Self.manifestPath, contents: manifestBytes, isText: true),
            .init(path: "README.md", contents: Data(card.utf8), isText: true),
        ]
        summary = "Add \(entry.title) — a Microduck policy published from Microduck Studio"
    }

    // MARK: - the manifest

    /// The library's own sidecar when it has one, with the sentence added
    /// under an additive key; otherwise a fresh one from what the entry knows.
    ///
    /// A HELD MANIFEST IS NOT REWRITTEN. A kept network's `made_here` is the
    /// record of how it was made and the reason it can be trusted as far as it
    /// can; a fetched policy's manifest is its author's. Adding `when_to_use`
    /// beside them is additive by the same rule `PolicyManifest.encode` gives
    /// for `extra` — an older reader ignores what it does not know.
    static func manifest(for entry: PolicyLibrary.Entry, held: Data?,
                         whatItDoes: String) throws -> Data {
        if let held,
           var top = try? JSONSerialization.jsonObject(with: held) as? [String: Any],
           (try? PolicyManifest.decode(held)) != nil {
            top["when_to_use"] = whatItDoes
            if (top["description"] as? String)?.isEmpty ?? true { top["description"] = whatItDoes }
            return try JSONSerialization.data(withJSONObject: top,
                                              options: [.prettyPrinted, .sortedKeys])
        }
        let kind = PolicyNaming.kind(forFileName: entry.fileName)?.rawValue
        return try PolicyManifest.encode(PolicyManifest.Written(
            name: entry.title, summary: whatItDoes, actionScale: nil, kind: kind,
            durationSeconds: nil, entryPose: nil, twist: [], idle: [],
            cautions: cautions(for: entry), extra: ["when_to_use": whatItDoes]))
    }

    /// What the card has to admit about where the weights came from.
    static func cautions(for entry: PolicyLibrary.Entry) -> [String] {
        var out: [String] = []
        if let caveat = entry.origin.caveat { out.append(caveat) }
        switch entry.origin {
        case .bundled:
            out.append("These are the weights the app bundles, republished. The original release "
                     + "is pollen-robotics/microduck; this copy adds nothing to it.")
        case .imported:
            out.append("These weights were brought into the app as a file. Who trained them, "
                     + "and on what, is not something this app can say.")
        case .fetched(let host):
            out.append("These weights were fetched from \(host) and republished unchanged.")
        case .tuned, .searched:
            out.append(MotionPublication.trainsNothing)
        }
        return out
    }

    // MARK: - the card

    static func card(for entry: PolicyLibrary.Entry, manifest: PolicyManifest,
                     whatItDoes: String, note: String?) -> String {
        let cautionLines = (manifest.authorCautions + cautions(for: entry))
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .map { "- \($0)" }.joined(separator: "\n")
        let tags = Self.hubTags.joined(separator: ", ")
        // FRONT MATTER IN A MODEL CARD'S SHAPE: license, tags, pipeline_tag,
        // pretty_name. `library_name: onnx` is what the Hub's own file viewer
        // keys its "how to load" panel on, and it is true.
        return """
        ---
        license: apache-2.0
        library_name: onnx
        pipeline_tag: reinforcement-learning
        tags: [\(tags), onnx]
        pretty_name: \(MotionPublication.yamlQuoted("\(entry.title) • Microduck policy"))
        ---
        # \(entry.title)
        A policy for the Pollen Robotics [Microduck](https://github.com/pollen-robotics/microduck), \
        published from Microduck Studio. \(note ?? "")
        ## What it does
        \(whatItDoes)
        ## Where the weights came from
        \(entry.origin.label). \(entry.origin.caveat ?? "")
        ## What a reader can check
        | | |
        |---|---|
        | Parameter fingerprint (sha256) | `\(entry.identity.value)` |
        | Observation | \(manifest.observationLength) floats |
        | Action | \(manifest.actionLength) joints |
        | Control rate | \(Int(manifest.controlHz ?? DuckModel.tickHz)) Hz |
        | Kind | \(manifest.kind ?? "not declared") |
        The fingerprint is taken over the canonical parameter bytes, the same layout DuckKit \
        fingerprints every policy by. Load `policy.onnx` in Microduck Studio and compare.
        ## Before you run it
        \(cautionLines)
        ## Files
        - `\(Self.policyPath)` — the network, exactly as the library held it.
        - `\(Self.manifestPath)` — the manifest, in the documented sharing format Microduck \
        Studio reads; a network made in the app carries how it was made under `made_here`.
        - `README.md` — this card
        """
    }
}
