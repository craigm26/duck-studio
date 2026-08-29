import Foundation
import DuckKit
import DuckEvidence

/// What Pollen Robotics currently publish, and how to go and look.
///
/// WHY A SCAN AND NOT A BUNDLED LIST. This app ships nine policies and a
/// fingerprint table describing them, and both are frozen at build time. Pollen
/// keep training: a release newer than this build shows up in the library as
/// "unrecognised", which is honest and unhelpful — the person is being told the
/// app has not heard of a file that has been public for a month. Asking the
/// repository is the difference between "I do not know this" and "here is what
/// exists".
///
/// THE LISTING IS A HINT; ONLY THE FILE DECIDES. A scan can see paths, sizes
/// and git blob hashes, and NONE of those is the identity this app uses. Two of
/// the nine upstream files are not even named the way the bundled copies are —
/// upstream ships `alpha_stand.onnx` and `roller.onnx` where this app carries
/// `BEST_alpha_stand.onnx` and `BEST_roller.onnx`. So a listing entry can say
/// "a name you do not hold" and never "a network you do not hold": that
/// question is answered by `DuckPolicy.fingerprint` after the bytes arrive, and
/// this type is careful never to phrase it otherwise.
///
/// NO NETWORK LIVES HERE. This builds URLs and parses responses, both pure, so
/// every rule is asserted by `swift test` on Linux. The app performs the
/// request and shows what comes back.
public enum PolicyCatalogue {

    /// A place Pollen publish from.
    public struct Source: Hashable, Sendable, Identifiable {
        public let id: String
        /// What to call it on screen.
        public let name: String
        /// One line about what is actually kept there.
        public let holds: String
        public let owner: String
        public let repository: String
        public let branch: String
        /// The directory inside the repository worth listing.
        public let directory: String

        public var webURL: String {
            "https://github.com/\(owner)/\(repository)/tree/\(branch)/\(directory)"
        }
    }

    /// The trained networks that ship with the robot.
    ///
    /// THIS COMMENT USED TO SAY THERE WAS NOTHING ON HUGGING FACE, and on the
    /// day it was written that was true. It stopped being true on 2026-08-29,
    /// when Pollen's own Rémi Fabre published `RemiFabre/microduck-flamingo-cycle`
    /// there under the `microduck-policy` tag with a `manifest.json` in the
    /// documented sharing format. Community policies are a second source now —
    /// see `communityPolicies` below — and this one remains what the ROBOT
    /// ships with, which is a different claim and still true.
    public static let officialPolicies = Source(
        id: "pollen-policies",
        name: "Pollen Robotics · microduck",
        holds: "The trained policies that ship with the robot.",
        owner: "pollen-robotics", repository: "microduck",
        branch: "main", directory: "policies")

    /// The training environments — reward terms, terminations, curricula.
    /// Listed because it is where the numbers in the reward panel come from,
    /// and because a new task config appearing here is the earliest sign that a
    /// new policy is coming.
    public static let trainingConfigs = Source(
        id: "pollen-rl",
        name: "Pollen Robotics · microduck_rl",
        holds: "The training environments the reward terms are read from.",
        owner: "pollen-robotics", repository: "microduck_rl",
        branch: "main", directory: "src/mjlab_microduck/tasks")

    public static let sources: [Source] = [officialPolicies, trainingConfigs]

    // MARK: - what the community publishes

    /// One Microduck policy somebody has shared on Hugging Face.
    public struct CommunityEntry: Equatable, Sendable, Identifiable {
        /// `owner/name`, which is both the address and the identity.
        public let id: String
        public let author: String
        public let updated: String?
        public let downloads: Int
        public let likes: Int
        /// Tagged the way Pollen's sharing doc asks. Untagged repositories
        /// still list — the tag is a courtesy, not a gate — but this says
        /// which ones followed it.
        public let declaresPolicyTag: Bool

        public init(id: String, author: String, updated: String?,
                    downloads: Int, likes: Int, declaresPolicyTag: Bool) {
            self.id = id; self.author = author; self.updated = updated
            self.downloads = downloads; self.likes = likes
            self.declaresPolicyTag = declaresPolicyTag
        }

        public var webURL: String { "https://huggingface.co/\(id)" }
        public var name: String {
            let bare = id.split(separator: "/").last.map(String.init) ?? id
            return bare.hasPrefix("microduck-") ? String(bare.dropFirst("microduck-".count)) : bare
        }
    }

    /// Everything on Hugging Face tagged `microduck`.
    ///
    /// THE BROAD TAG, NOT THE NARROW ONE. `microduck-policy` is what Pollen's
    /// sharing format asks authors to use, and on 2026-08-29 exactly one
    /// repository used it while three carried plain `microduck`. Listing the
    /// narrow tag would have hidden two thirds of what exists. What separates
    /// a policy this app can drive from a folder of files is not a tag but a
    /// readable `manifest.json`, and that is checked per entry.
    public static func communityListing(limit: Int = 50) -> PolicySource.Request {
        let string = "https://huggingface.co/api/models?filter=microduck&limit=\(limit)"
        let url = URL(string: string)!
        return PolicySource.Request(url: url, displayURL: string,
                                    host: "huggingface.co",
                                    suggestedName: "microduck policies")
    }

    /// A Hugging Face address somebody pasted, reduced to what to fetch.
    ///
    /// EVERY SHAPE A LINK ARRIVES IN. People copy the address bar (the repo
    /// page), the "copy path" button (`owner/name`), or a link to the file
    /// itself — and the file link is as likely to be `blob/` (the HTML page
    /// wrapped around the file) as `resolve/` (the file). Asking someone to
    /// hand-edit blob into resolve is asking them to know a Hugging Face
    /// implementation detail, so this does it.
    public struct CommunityReference: Equatable, Sendable {
        public let repository: String
        public let revision: String
        /// The file named in the link, when one was. A bare repository link
        /// means "the policy", which by the sharing format is policy.onnx.
        public let file: String?

        public var policyFile: String { file ?? "policy.onnx" }
        public var webURL: String { "https://huggingface.co/\(repository)" }

        public func policyRequest() throws -> PolicySource.Request {
            try PolicySource.huggingFace(repository: repository, file: policyFile,
                                         revision: revision)
        }
        public func manifestRequest() throws -> PolicySource.Request {
            try PolicySource.huggingFaceManifest(repository: repository, revision: revision)
        }
    }

    public enum ReferenceError: Error, Equatable {
        case empty
        case notHuggingFace(String)
        case insecure(String)
        case malformed(String)

        public var message: String {
            switch self {
            case .empty:
                return "Paste a Hugging Face address, or an owner/name like RemiFabre/microduck-flamingo-cycle."
            case .notHuggingFace(let host):
                return "That address is on \(host). This imports from huggingface.co; a file "
                     + "anywhere else can still be opened with the file picker."
            case .insecure(let scheme):
                return "That address is \(scheme), not https."
            case .malformed(let text):
                return "\"\(text)\" is not a Hugging Face repository — it should look like "
                     + "owner/name."
            }
        }
    }

    /// Turn whatever was pasted into something fetchable.
    public static func communityReference(from text: String) throws -> CommunityReference {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReferenceError.empty }

        if trimmed.contains("://") {
            guard let url = URL(string: trimmed), let host = url.host else {
                throw ReferenceError.malformed(trimmed)
            }
            guard url.scheme?.lowercased() == "https" else {
                throw ReferenceError.insecure(url.scheme ?? "an unknown scheme")
            }
            guard host == "huggingface.co" || host == "www.huggingface.co" else {
                throw ReferenceError.notHuggingFace(host)
            }
            trimmed = url.path
        }
        // Strip a query or fragment somebody copied along with the address.
        for cut in ["?", "#"] {
            if let index = trimmed.firstIndex(of: Character(cut)) {
                trimmed = String(trimmed[..<index])
            }
        }
        var parts = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        // "api/models/" prefixes the API form of the same address — people
        // paste that too, having found the repository through a search.
        if parts.first == "api" { parts.removeFirst() }
        if parts.first == "models" { parts.removeFirst() }
        guard parts.count >= 2 else { throw ReferenceError.malformed(trimmed) }
        let repository = "\(parts[0])/\(parts[1])"
        var revision = "main"
        var file: String?
        if parts.count > 2 {
            // blob and resolve both carry <revision>/<path>; tree carries a
            // revision and no file.
            let marker = parts[2]
            if ["blob", "resolve", "tree"].contains(marker), parts.count > 3 {
                revision = parts[3]
                let rest = parts.dropFirst(4).joined(separator: "/")
                if !rest.isEmpty, marker != "tree" { file = rest }
            }
        }
        if let name = file, !name.lowercased().hasSuffix(".onnx") {
            // A link to the manifest, the video, the README — the repository
            // is what was meant, and the policy is what is wanted.
            file = nil
        }
        return CommunityReference(repository: repository, revision: revision, file: file)
    }

    public static func parseCommunity(_ data: Data) throws -> [CommunityEntry] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ScanError.notJSON
        }
        return rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let tags = row["tags"] as? [String] ?? []
            return CommunityEntry(
                id: id,
                author: row["author"] as? String
                    ?? String(id.split(separator: "/").first ?? ""),
                updated: (row["lastModified"] as? String).map { String($0.prefix(10)) },
                downloads: row["downloads"] as? Int ?? 0,
                likes: row["likes"] as? Int ?? 0,
                declaresPolicyTag: tags.contains("microduck-policy"))
        }.sorted { ($0.updated ?? "") > ($1.updated ?? "") }
    }

    /// WHY THERE IS NO INTENT SOURCE. Pollen publish policies and training
    /// configs; they do not publish recorded motions, because a motion is
    /// something you get by running a policy in physics rather than something
    /// the robot ships with. Every clip in this app was recorded here. Listing
    /// an upstream intent feed would mean inventing an address, and the scan
    /// would report "nothing new" forever from a URL that does not exist.
    public static let intentsNote =
        "Pollen publish policies, not motions — every intent in this app was recorded here by "
      + "running one of their policies in MuJoCo. Motions arrive from other owners as "
      + ".duckintent files, not from a repository."

    // MARK: - asking

    /// The listing request for a source. GitHub's recursive tree endpoint,
    /// which answers with every blob in the repository in one response — one
    /// request rather than a walk, and no token, because these repositories are
    /// public and this app has no account.
    public static func listing(_ source: Source) -> PolicySource.Request {
        let string = "https://api.github.com/repos/\(source.owner)/\(source.repository)"
                   + "/git/trees/\(source.branch)?recursive=1"
        let url = URL(string: string)!
        return PolicySource.Request(url: url, displayURL: string,
                                    host: "api.github.com",
                                    suggestedName: source.repository)
    }

    /// One file the repository is offering.
    public struct Entry: Equatable, Sendable, Identifiable {
        public let path: String
        public let bytes: Int
        /// Git's own hash of the blob. NOT this app's identity for a policy —
        /// it changes when the file is re-exported and the network is
        /// unchanged, and it says nothing about the weights. Carried so a
        /// second scan can tell that a file has been replaced.
        public let blob: String
        public var id: String { path }

        public var filename: String {
            String(path.split(separator: "/").last ?? "")
        }
    }

    public enum ScanError: Error, Equatable {
        case notJSON
        /// GitHub answered, and not with a tree — a wrong branch name gives
        /// `Not Found` here, which is worth showing verbatim.
        case refused(String)
        case noTree
    }

    /// Everything under the source's directory, from a tree response.
    public static func parse(_ data: Data, source: Source,
                             extensions: Set<String>) throws -> [Entry] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScanError.notJSON
        }
        if let message = object["message"] as? String, object["tree"] == nil {
            throw ScanError.refused(message)
        }
        guard let tree = object["tree"] as? [[String: Any]] else { throw ScanError.noTree }
        let prefix = source.directory.isEmpty ? "" : source.directory + "/"
        return tree.compactMap { node -> Entry? in
            guard node["type"] as? String == "blob",
                  let path = node["path"] as? String,
                  path.hasPrefix(prefix) else { return nil }
            // Only the named directory, not everything below it: the policies
            // folder is flat, and a recursive listing would otherwise sweep in
            // an assets tree of several hundred STLs.
            let rest = path.dropFirst(prefix.count)
            guard !rest.contains("/") else { return nil }
            guard let dot = rest.lastIndex(of: "."),
                  extensions.contains(String(rest[rest.index(after: dot)...]).lowercased())
            else { return nil }
            return Entry(path: path,
                         bytes: node["size"] as? Int ?? 0,
                         blob: node["sha"] as? String ?? "")
        }
        .sorted { $0.path < $1.path }
    }

    /// The raw-file URL for an entry, through the same checks any other fetch
    /// gets — https only, `.onnx` only, and under the size cap.
    public static func download(_ entry: Entry, from source: Source) throws -> PolicySource.Request {
        guard entry.bytes <= PolicySource.byteCap else {
            throw PolicySource.Refusal.tooLarge(bytes: entry.bytes)
        }
        guard entry.filename.lowercased().hasSuffix(".onnx") else {
            throw PolicySource.Refusal.notAPolicyFile(entry.filename)
        }
        let string = "https://raw.githubusercontent.com/\(source.owner)/\(source.repository)"
                   + "/\(source.branch)/\(entry.path)"
        guard let url = URL(string: string) else { throw PolicySource.Refusal.notAURL(string) }
        return PolicySource.Request(url: url, displayURL: string,
                                    host: "raw.githubusercontent.com",
                                    suggestedName: entry.filename)
    }

    // MARK: - what to say about it

    /// What can be said about a listed file before it is fetched.
    public enum Familiarity: Equatable, Sendable {
        /// A filename one of the recorded releases also uses.
        case knownName(String)
        /// A name this build has not seen. NOT "a new policy" — upstream
        /// renames, and two of the nine already differ from the bundled copies.
        case unfamiliarName
    }

    public static func familiarity(of entry: Entry) -> Familiarity {
        if let match = DuckOfficialPolicies.releases.first(where: { $0.filename == entry.filename }) {
            return .knownName(match.purpose)
        }
        return .unfamiliarName
    }

    /// The sentence under a listed file.
    public static func summary(of entry: Entry) -> String {
        let size = "\(entry.bytes / 1024) KB"
        switch familiarity(of: entry) {
        case .knownName(let purpose):
            return "\(size). A name this app already knows: \(purpose)"
        case .unfamiliarName:
            return "\(size). A filename this build has not seen. That may be a policy that is "
                 + "new, or one of Pollen's own under a name this app carries differently — "
                 + "only the weights decide, and they are only known once it is opened."
        }
    }

    /// The line at the top of a completed scan.
    ///
    /// COUNTS NAMES, AND SAYS SO. "Two new policies" would be a claim about
    /// networks, made from a directory listing that cannot support it.
    public static func headline(_ entries: [Entry]) -> String {
        let unfamiliar = entries.filter { familiarity(of: $0) == .unfamiliarName }.count
        guard !entries.isEmpty else { return "The repository listed nothing in that folder." }
        let files = "\(entries.count) file\(entries.count == 1 ? "" : "s")"
        guard unfamiliar > 0 else {
            return "\(files), all under names this app already knows."
        }
        return "\(files), \(unfamiliar) under \(unfamiliar == 1 ? "a name" : "names") this build "
             + "has not seen. Open one to find out whether the network is new."
    }
}
