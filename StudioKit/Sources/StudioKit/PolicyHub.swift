import Foundation
import DuckKit

/// Finding policies other people have published.
///
/// THERE IS A COMMUNITY AND THIS APP COULD NOT SEE IT. People publish trained
/// Microduck policies to the Hugging Face Hub as model repositories tagged
/// `microduck-policy` — Pollen's own co-founder among them — each with
/// `policy.onnx`, a `manifest.json`, and usually a preview video. This app
/// could import a `.onnx` somebody AirDropped it and had no way to discover a
/// single one of those repositories. Its only Hub search is scoped to
/// `mlx-community` text-generation models, which is the language-model picker
/// and finds no policies at all.
///
/// THE TAG IS THE WHOLE MECHANISM, and it is not this project's to define.
/// `filter=microduck-policy` is what the published repositories already carry,
/// so this searches for what exists rather than proposing a convention nobody
/// else follows.
public enum PolicyHub {

    /// One published policy, as a listing shows it before anything is fetched.
    public struct Listing: Equatable, Sendable, Identifiable {
        /// `owner/name`.
        public let repository: String
        public var id: String { repository }
        public let author: String
        public let downloads: Int
        public let likes: Int
        /// When the repository last changed, ISO-8601 as the Hub gives it.
        public let updated: String?
        /// Whether the Hub says the weights are gated behind an agreement.
        public let gated: Bool

        public init(repository: String, author: String, downloads: Int, likes: Int,
                    updated: String?, gated: Bool) {
            self.repository = repository; self.author = author
            self.downloads = downloads; self.likes = likes
            self.updated = updated; self.gated = gated
        }

        /// The last path component, which is what people call it.
        public var name: String {
            repository.split(separator: "/").last.map(String.init) ?? repository
        }
    }

    /// The listing query.
    ///
    /// SORTED BY WHAT CHANGED LAST, not by downloads. The language-model picker
    /// sorts by downloads because it is choosing among thousands of well-known
    /// files; this is a handful of repositories in a community measured in
    /// people rather than thousands, where every download count is near zero
    /// and the interesting one is whatever somebody just trained.
    public static func searchURL(matching text: String = "", limit: Int = 25) -> URL {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        var items = [
            URLQueryItem(name: "filter", value: DuckPolicyManifest.hubTag),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 50)))),
            URLQueryItem(name: "sort", value: "lastModified"),
            URLQueryItem(name: "direction", value: "-1"),
        ]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "search", value: trimmed)) }
        components.queryItems = items
        return components.url!
    }

    /// Where a file inside a published policy lives.
    ///
    /// `resolve/main` rather than `blob/main`: the former is the bytes, the
    /// latter is an HTML page about the bytes, and fetching the second and
    /// parsing it as ONNX is a mistake with a very confusing error.
    public static func fileURL(repository: String, path: String) -> URL? {
        var escaped = URLComponents(string: "https://huggingface.co")
        escaped?.path = "/\(repository)/resolve/main/\(path)"
        return escaped?.url
    }

    /// The two files a policy repository is expected to carry.
    public static let policyPath = "policy.onnx"
    public static var manifestPath: String { DuckPolicyManifest.path }

    public enum ReadError: Error, Equatable {
        case notJSON
        case empty(String)

        public var message: String {
            switch self {
            case .notJSON:
                return "Hugging Face did not answer with a list of models."
            case .empty(let text):
                return text.isEmpty
                    ? "Nothing on the Hub is tagged \(DuckPolicyManifest.hubTag) right now, which "
                    + "probably means the search did not reach it — this is a small community, "
                    + "but it is not empty."
                    : "Nothing tagged \(DuckPolicyManifest.hubTag) matches \"\(text)\"."
            }
        }
    }

    public static func read(_ data: Data, matching text: String = "") throws -> [Listing] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ReadError.notJSON
        }
        let listings = rows.compactMap { row -> Listing? in
            guard let id = row["id"] as? String ?? row["modelId"] as? String else { return nil }
            return Listing(
                repository: id,
                author: row["author"] as? String
                    ?? id.split(separator: "/").first.map(String.init) ?? "",
                downloads: row["downloads"] as? Int ?? 0,
                likes: row["likes"] as? Int ?? 0,
                updated: row["lastModified"] as? String,
                gated: (row["gated"] as? Bool) ?? false)
        }
        if listings.isEmpty { throw ReadError.empty(text) }
        return listings
    }

    /// What the browser has to say about where these come from.
    ///
    /// NOT POLLEN'S, AND THE LIST CANNOT TELL YOU IF THEY WORK. A published
    /// policy is somebody's training run. The manifest carries their own status
    /// and known limits, this app checks the weights it actually downloads, and
    /// a bench is the only thing that can say whether it does anything.
    public static let provenanceNote =
        "These are policies people have published themselves, not releases from Pollen Robotics. "
      + "Anyone can publish one; a listing says who and when, and nothing about whether it works.\n\n"
      + "Opening one reads its manifest — the author's own status, what they say they did not "
      + "test, and the action scale the runtime should use — and checks the weights against the "
      + "architecture this robot runs. Whether it does anything is a question only a bench answers."
}
