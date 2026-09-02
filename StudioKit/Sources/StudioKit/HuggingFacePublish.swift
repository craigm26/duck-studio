import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLRequest lives here on Linux, where these tests run
#endif

/// Putting something on Hugging Face, as a set of requests somebody else sends.
///
/// THE TOKEN NEVER ENTERS A CALL. Everything here builds a `Call` — a method,
/// an address, a body — with no credential anywhere in it, and the token is
/// attached at the last moment by `urlRequest(for:token:)` as an
/// `Authorization` header. That is not ceremony: a write token in a URL ends up
/// in logs, in a screenshot of a failure message, and in the `displayURL` this
/// app prints on screen before it asks permission. A test pins that no Call's
/// description can contain one.
///
/// PUBLISHING IS PUBLIC AND IT IS NOT REALLY UNDOABLE. A repository can be
/// deleted, but anything already fetched or indexed is out. So this type
/// constructs; it never sends. The screen that sends shows the account, the
/// address and every byte of every file first.
public enum HuggingFacePublish {

    // MARK: - what a screen holding the token may say about it

    /// THE TOKEN HAD NO OWNING SCREEN UNTIL NOW. It was pasted four taps deep
    /// inside one motion's publish sheet, and `TokenStore.clear()` had no
    /// caller anywhere in the app — so a write token that can create and delete
    /// repositories under somebody's name could be saved and never removed.
    /// These are the sentences the screen that owns it is allowed to say.
    public static let tokenHeldNote =
        "A Hugging Face write token is saved in this device's Keychain. It is attached to one "
      + "kind of request only — publishing a motion — and to no other host."

    public static let tokenAbsentNote =
        "No token is saved. Publishing a motion asks for one; nothing else in this app uses it."

    /// REMOVING IS NOT REVOKING, and a Remove button that does not say so
    /// teaches a false safety: the credential still works everywhere it worked
    /// a minute ago, on every other device it was ever pasted into.
    public static let tokenRemovedNote =
        "Removed from this device. That does not revoke it — revoke it at "
      + "huggingface.co/settings/tokens."

    public static let host = "huggingface.co"

    /// One request, credential-free.
    public struct Call: Equatable, Sendable {
        public let method: String
        public let url: URL
        public let contentType: String?
        public let body: Data?

        public var displayURL: String { url.absoluteString }
    }

    public struct Repository: Equatable, Sendable {

        /// A model repository or a dataset repository. Hugging Face has both,
        /// and a trajectory belongs in the second one.
        ///
        /// THE PROOF THIS IS NOT A TASTE QUESTION: on the live Hub,
        /// `/api/datasets?filter=reachy_mini_community_moves` answers with 30+
        /// repositories and `/api/models?filter=reachy_mini_community_moves`
        /// answers with none. Pollen never put a move in a model repo. A move
        /// published as one is a move nobody's loader goes looking for, in a
        /// place their search does not reach.
        public enum Kind: String, Equatable, Sendable {
            case model
            case dataset

            /// The segment the COMMIT endpoint wants. This is the half that
            /// genuinely differs: creation is one address for both kinds and
            /// only the body's `type` changes, but a commit goes to
            /// `api/models/…` or `api/datasets/…`, and a commit posted to the
            /// wrong one addresses a repository that does not exist.
            var apiSegment: String {
                switch self {
                case .model: return "models"
                case .dataset: return "datasets"
                }
            }

            /// The website needs `datasets/` in front of a dataset, and the
            /// failure that prefix prevents is SILENT. `huggingface.co/<ns>/<name>`
            /// for a dataset does not 404 when a model of the same name
            /// exists — it quietly resolves to the MODEL. So an address printed
            /// without the prefix can open a real page, look right, and be a
            /// different artifact from the one just published.
            var webPrefix: String {
                switch self {
                case .model: return ""
                case .dataset: return "datasets/"
                }
            }
        }

        public let namespace: String
        public let name: String
        public let kind: Kind
        public var id: String { "\(namespace)/\(name)" }
        public var webURL: String { "https://\(host)/\(kind.webPrefix)\(id)" }
    }

    public enum Refusal: Error, Equatable {
        case emptyName
        case badName(String)
        case tooLong(String)
        case noNamespace
        case nothingToPublish
        case noWhenToUse

        public var message: String {
            switch self {
            case .emptyName:
                return "Give the repository a name."
            case .badName(let name):
                return "\"\(name)\" cannot be a repository name — letters, digits, dots, "
                     + "dashes and underscores only, and it cannot start or end with a dot or dash."
            case .tooLong(let name):
                return "\"\(name)\" is longer than Hugging Face allows (96 characters)."
            case .noNamespace:
                return "Sign in first: the account decides where this is published."
            case .nothingToPublish:
                return "There are no files to publish."
            case .noWhenToUse:
                return "Say when this move should be played, in one sentence. A library of "
                     + "moves with no descriptions is a list of filenames — that sentence is "
                     + "what somebody browsing reads, and it is all a model choosing a move "
                     + "has to go on."
            }
        }
    }

    /// Hugging Face's own rules for a repository name, checked here so a
    /// refusal arrives before a token is spent rather than as a 400.
    ///
    /// `kind` HAS NO DEFAULT ON PURPOSE. A default is exactly how this app
    /// came to publish motions as model repositories: nobody chose it, the
    /// parameter simply already said so. Every call site now has to state
    /// which kind of thing it is making, out loud.
    public static func repository(namespace: String, name: String,
                                  kind: Repository.Kind) throws -> Repository {
        let space = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !space.isEmpty else { throw Refusal.noNamespace }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Refusal.emptyName }
        guard trimmed.count <= 96 else { throw Refusal.tooLong(trimmed) }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw Refusal.badName(trimmed)
        }
        guard let first = trimmed.first, let last = trimmed.last,
              !".-".contains(first), !".-".contains(last) else {
            throw Refusal.badName(trimmed)
        }
        return Repository(namespace: space, name: trimmed, kind: kind)
    }

    /// Who the token belongs to. Asked BEFORE anything is created, so the
    /// screen can say "publishing as …" rather than discovering the account
    /// from the address of a repository that now exists.
    /// THE WARNING EVERY PUBLIC PUBLISH DRAWS, in one place. It used to be a
    /// byte-copy in two views, one of them untested.
    public static let publicWarning =
        "PUBLIC: anyone can find and download it, and anything already fetched stays fetched "
      + "even if you delete it later."
    /// The failure ladder a publish sheet climbs, as sentences rather than
    /// string literals in a view.
    public static let tokenRefused = "Hugging Face did not accept that token."
    public static func answered(_ status: Int) -> String { "huggingface.co answered \(status)." }
    public static let noAccountNamed = "That answer did not name an account."
    public static func creating(_ status: Int) -> String {
        "Creating the repository answered \(status)."
    }

    public static func whoami() -> Call {
        Call(method: "GET", url: URL(string: "https://\(host)/api/whoami-v2")!,
             contentType: nil, body: nil)
    }

    public static func parseWhoami(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return root["name"] as? String
    }

    /// Create the repository. `private` defaults TRUE: the safe default for a
    /// button that publishes is the one you can still change your mind about.
    ///
    /// ONE ADDRESS CREATES BOTH KINDS. There is no `/api/datasets/create` —
    /// the URL below is the whole of it, and the only thing deciding which
    /// kind you get is `type` in the body. This note is here so the next
    /// person stops hunting for the endpoint that does not exist.
    public static func create(_ repository: Repository, license: String = "apache-2.0",
                              isPrivate: Bool = true) -> Call {
        var body: [String: Any] = ["name": repository.name,
                                   "type": repository.kind.rawValue,
                                   "private": isPrivate, "license": license]
        // The namespace is only sent when it is an organisation; for a personal
        // account Hugging Face infers it from the token.
        body["organization"] = NSNull()
        let json = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return Call(method: "POST", url: URL(string: "https://\(host)/api/repos/create")!,
                    contentType: "application/json", body: json)
    }

    /// One file in a commit.
    public struct File: Equatable, Sendable {
        public let path: String
        public let contents: Data
        /// Text is committed as utf-8 so it is readable in the web diff;
        /// anything else goes base64.
        public let isText: Bool

        public init(path: String, contents: Data, isText: Bool) {
            self.path = path; self.contents = contents; self.isText = isText
        }

        public var bytes: Int { contents.count }
    }

    /// The commit. JSON rather than the ndjson form — both are supported, and
    /// one object is easier to show somebody before they send it.
    ///
    /// NO LFS PATH HERE ON PURPOSE. Everything this app publishes is a motion:
    /// keyframes and a card, kilobytes. A trained network would need the
    /// preupload/LFS dance, and this app does not train networks, so writing
    /// that path would be writing code for a case that cannot arise.
    public static func commit(_ repository: Repository, revision: String = "main",
                              summary: String, description: String = "",
                              files: [File]) throws -> Call {
        guard !files.isEmpty else { throw Refusal.nothingToPublish }
        let encoded: [[String: Any]] = files.map { file in
            [
                "path": file.path,
                "encoding": file.isText ? "utf-8" : "base64",
                "content": file.isText
                    ? (String(data: file.contents, encoding: .utf8) ?? "")
                    : file.contents.base64EncodedString(),
            ]
        }
        let body: [String: Any] = ["summary": summary, "description": description,
                                   "files": encoded]
        let json = try JSONSerialization.data(withJSONObject: body)
        // The one address here that is NOT shared between the two kinds.
        let path = "https://\(host)/api/\(repository.kind.apiSegment)/\(repository.id)"
                 + "/commit/\(revision)"
        return Call(method: "POST", url: URL(string: path)!,
                    contentType: "application/json", body: json)
    }

    /// The only place a token and a request meet.
    public static func urlRequest(for call: Call, token: String) -> URLRequest {
        var request = URLRequest(url: call.url)
        request.httpMethod = call.method
        request.httpBody = call.body
        if let contentType = call.contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))",
                         forHTTPHeaderField: "Authorization")
        return request
    }
}
