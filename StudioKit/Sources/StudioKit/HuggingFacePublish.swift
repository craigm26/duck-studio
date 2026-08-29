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
        public let namespace: String
        public let name: String
        public var id: String { "\(namespace)/\(name)" }
        public var webURL: String { "https://\(host)/\(id)" }
    }

    public enum Refusal: Error, Equatable {
        case emptyName
        case badName(String)
        case tooLong(String)
        case noNamespace
        case nothingToPublish

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
            }
        }
    }

    /// Hugging Face's own rules for a repository name, checked here so a
    /// refusal arrives before a token is spent rather than as a 400.
    public static func repository(namespace: String, name: String) throws -> Repository {
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
        return Repository(namespace: space, name: trimmed)
    }

    /// Who the token belongs to. Asked BEFORE anything is created, so the
    /// screen can say "publishing as …" rather than discovering the account
    /// from the address of a repository that now exists.
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
    public static func create(_ repository: Repository, license: String = "apache-2.0",
                              isPrivate: Bool = true) -> Call {
        var body: [String: Any] = ["name": repository.name, "type": "model",
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
        let path = "https://\(host)/api/models/\(repository.id)/commit/\(revision)"
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
