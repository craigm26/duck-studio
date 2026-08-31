import Foundation

/// Finding a model to run on the phone that is not in the curated list.
///
/// THE LIST IS SHORT ON PURPOSE AND THIS IS THE ESCAPE HATCH. Six measured
/// entries cover the sizes that matter; somebody who wants a particular model —
/// one they already trust, or one published after this build — should not have
/// to wait for an app update.
///
/// IT SEARCHES ONE ORGANISATION, AND THAT IS A REAL RESTRICTION RATHER THAN A
/// PREFERENCE. The loader on the phone reads MLX-format weights. A repository
/// of GGUF or safetensors in any other layout will download several gigabytes
/// and then fail to open, which is the worst possible failure: slow, expensive,
/// and at the end. `mlx-community` is the organisation that publishes converted
/// MLX weights, so restricting to it is what makes a result trustworthy enough
/// to offer.
///
/// NO TOKEN IS SENT. This reads a public index, exactly as `PolicyCatalogue`
/// does for policies, and `GATES.md` pre-registers that the write token travels
/// on one path only.
public enum PhoneModelSearch {

    /// A result, before anything has been downloaded.
    ///
    /// IT CARRIES NO SIZE, AND THAT IS THE API'S DOING RATHER THAN A CHOICE.
    /// The models index returns neither `usedStorage` (the expand list rejects
    /// it outright) nor sibling file sizes — checked against the live endpoint
    /// on 2026-08-31, where every `siblings` entry came back sizeless. The tree
    /// API does give real bytes, so the size is fetched for the one model
    /// somebody actually taps: one extra request at the only moment it matters.
    /// A `bytes` field here would be a field that is always nil.
    public struct Hit: Equatable, Sendable, Identifiable {
        public var id: String { repository }
        public let repository: String
        public let downloads: Int
        public let likes: Int

        public init(repository: String, downloads: Int, likes: Int) {
            self.repository = repository; self.downloads = downloads; self.likes = likes
        }

        public var name: String {
            repository.split(separator: "/").last.map(String.init) ?? repository
        }
    }


    /// The query. Empty text lists the most-downloaded of the organisation,
    /// which is a reasonable place to start looking.
    public static func url(matching text: String, limit: Int = 25) -> URL {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        var items = [
            URLQueryItem(name: "author", value: "mlx-community"),
            // TEXT GENERATION ONLY. Without it the top hit for "qwen3-1.7b" on
            // the live index is `Qwen3-TTS-12Hz-1.7B-Base-bf16` — text to
            // speech, in bf16, which downloads and is useless. This removes
            // most of that. It does not remove all of it; `scopeNote` says so.
            URLQueryItem(name: "pipeline_tag", value: "text-generation"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 50)))),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
        ]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "search", value: trimmed)) }
        components.queryItems = items
        return components.url!
    }

    public enum ReadError: Error, Equatable {
        case notJSON
        case none(String)

        public var message: String {
            switch self {
            case .notJSON:
                return "Hugging Face did not answer with a list of models."
            case .none(let text):
                return text.isEmpty
                    ? "mlx-community has nothing to show, which probably means the search did not "
                    + "reach it."
                    : "Nothing in mlx-community matches \"\(text)\". That organisation publishes "
                    + "the MLX-format weights this phone can open — a model published anywhere "
                    + "else will download and then fail to load."
            }
        }
    }

    public static func read(_ data: Data, matching text: String = "") throws -> [Hit] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ReadError.notJSON
        }
        let hits = array.compactMap { row -> Hit? in
            guard let id = row["id"] as? String ?? row["modelId"] as? String else { return nil }
            return Hit(repository: id,
                       downloads: row["downloads"] as? Int ?? 0,
                       likes: row["likes"] as? Int ?? 0)
        }
        guard !hits.isEmpty else { throw ReadError.none(text) }
        return hits
    }


    /// The URL of a repository's file tree, for asking a size the index did not
    /// give — worth one extra request before a download of this size.
    public static func treeURL(for repository: String) -> URL {
        URL(string: "https://huggingface.co/api/models/\(repository)/tree/main?recursive=true")!
    }

    public static func readTreeBytes(_ data: Data) throws -> Int {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ReadError.notJSON
        }
        return array.filter { ($0["type"] as? String) == "file" }
                    .compactMap { $0["size"] as? Int }
                    .reduce(0, +)
    }

    /// Said under the search field.
    /// IT ADMITS THE FILTER IS NOT A GUARANTEE. Restricting to mlx-community
    /// and text-generation removes the obvious mistakes, but not all of them:
    /// `Qwen3-Embedding-0.6B-4bit-DWQ` is tagged text-generation and is an
    /// embedding model. No field reliably says "this is an instruction-
    /// following chat model", so the curated list is the one that has been
    /// checked and this is the one that has not.
    public static let scopeNote =
        "Searches mlx-community, the organisation that publishes weights in the format this phone "
      + "can open — a model from anywhere else will download in full and then fail to load, which "
      + "is a slow way to find out. These results are not checked beyond that: an embedding or "
      + "speech model can appear here and will download without being any use for writing a "
      + "motion. The list above is the one that has been tried."
}
