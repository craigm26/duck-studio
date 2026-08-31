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

    /// What a repository's tree says about whether it can be used at all.
    ///
    /// TWO MEASURED TRAPS IN THE LIVE INDEX, both of which end in the failure
    /// this file exists to prevent — several gigabytes fetched and then
    /// useless — and one of which ends in it after fetching 1,519 bytes.
    public struct Shape: Equatable, Sendable {
        public let bytes: Int
        public let hasWeights: Bool

        public init(bytes: Int, hasWeights: Bool) {
            self.bytes = bytes; self.hasWeights = hasWeights
        }
    }

    /// TRAP ONE: A REPOSITORY WITH NO WEIGHTS IN IT. Four Gemma 4 repositories
    /// in mlx-community contain nothing but a 1,519-byte `.gitattributes` —
    /// `gemma-4-E2B-it-qat-mxfp4`, `-nvfp4`, `gemma-4-e4b-mxfp4`, `-nvfp4`. A
    /// picker that sorts by size surfaces those at the top as tiny, perfect
    /// phone models.
    public static func readTreeShape(_ data: Data) throws -> Shape {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ReadError.notJSON
        }
        let files = array.filter { ($0["type"] as? String) == "file" }
        return Shape(bytes: files.compactMap { $0["size"] as? Int }.reduce(0, +),
                     hasWeights: files.contains {
                         ($0["path"] as? String)?.hasSuffix(".safetensors") == true
                     })
    }

    public static let noWeights =
        "That repository has no weights in it — only a placeholder file. Some conversions are "
      + "published empty; there is nothing to download."

    /// Where a repository's config lives, for trap two.
    public static func configURL(for repository: String) -> URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/main/config.json")!
    }

    /// TRAP TWO: A QUANTISATION THIS LOADER CANNOT READ. mlx-swift-lm decodes
    /// quantisation from the top-level `"quantization"` key alone
    /// (`BaseConfiguration.CodingKeys.quantizationContainer`), skips quantising
    /// entirely when it is absent, and then verifies with `verify: [.all]` — so
    /// Google's own `quantization_config` / `quant_method: "gemma"` repositories
    /// download in full and fail on a shape mismatch.
    /// `gemma-4-E2B-it-qat-mobile` is the smallest-looking Gemma 4 in the
    /// organisation, has five figures of monthly downloads, and is exactly this.
    public static func canLoadQuantisation(_ configData: Data) -> Bool {
        guard let config = try? JSONSerialization.jsonObject(with: configData)
                as? [String: Any] else { return false }
        return config["quantization"] != nil
    }

    public static let unreadableQuantisation =
        "That repository is quantised in a scheme this app's loader cannot read — it would "
      + "download in full and then fail to open. The models in the list above use the scheme it "
      + "can."

    /// Whether a searched repository is worth starting, and what to say if not.
    ///
    /// THE ARITHMETIC LIVES HERE, NOT IN THE VIEW. The picker had
    /// `shape.bytes + 350_000_000` in it — the app computing, which
    /// `check_no_studio_math.sh` exists to stop — and reached for
    /// `PhoneModel.megabytes`, which is internal. A sentence about whether
    /// three gigabytes will fit belongs where a test can hold it either way.
    ///
    /// The headroom is the same rule of thumb `PhoneModel.estimatedPeakBytes`
    /// uses, and it is a rule of thumb: nothing here has been measured on a
    /// phone, and the sentence says so.
    public static func doesNotFit(_ name: String, bytes: Int, budgetBytes: Int) -> String? {
        let peak = bytes + 350_000_000
        guard peak > budgetBytes else { return nil }
        return "\(name) needs roughly \(PhoneModel.megabytes(peak)) resident and iOS is offering "
             + "this app about \(PhoneModel.megabytes(budgetBytes)). It would be killed part-way "
             + "through an answer. That estimate is a rule of thumb, not a measurement on this "
             + "phone."
    }

    /// AN HTTP FAULT IS NOT A VERDICT ABOUT A REPOSITORY. `vetThenAdd` checked
    /// no status: Hugging Face answers a missing config with plain-text "Entry
    /// not found" and a rate limit with a JSON body, neither of which has a
    /// `quantization` key — so the app stated, definitively, that a perfectly
    /// good repository was "quantised in a scheme this app's loader cannot
    /// read". Only a 200 whose body parses may keep that sentence.
    public static func huggingFaceAnswered(_ status: Int) -> String {
        "huggingface.co answered \(status), so nothing was learned about that repository. That "
      + "is the index, not the model — try again in a moment."
    }

    public static let noConfigJSON =
        "That repository has no config.json in it. The loader reads that file to know what the "
      + "weights are, so there is nothing for it to open."

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
      + "motion. The first list above is the one that has been tried."
}

/// Without this a bare `catch` prints "The operation couldn't be completed.
/// (StudioKit.PhoneModelSearch.ReadError error 1.)" — the enum's own index, in
/// front of somebody who asked a question about a model.
extension PhoneModelSearch.ReadError: LocalizedError {
    public var errorDescription: String? { message }
}
