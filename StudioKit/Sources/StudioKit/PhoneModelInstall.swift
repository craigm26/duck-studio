import Foundation

/// Everything about downloading a model that is arithmetic or a sentence.
///
/// THE APP DRAWS AND DOES NOT COMPUTE, so the byte sums and every line a person
/// reads about a multi-gigabyte download live here, where `swift test` on a
/// Raspberry Pi can hold them. The app enumerates a directory and hands the
/// sizes over; it does not add them up.
///
/// AND THE SIZE ON SCREEN IS A MEASUREMENT OF THE DIRECTORY, never a re-print
/// of the catalogue number. Those two disagree whenever a download is partial,
/// resumed, or shared between two entries, and the one that matters to somebody
/// deciding whether to delete it is what is actually on the disk.
public enum PhoneModelInstall {

    /// Where the hub puts a repository's snapshot, relative to its cache root.
    ///
    /// `namespace/repo` becomes `models--namespace--repo`, which is the layout
    /// the Hugging Face hub client uses on every platform. Needed for two
    /// things the loader does not offer: asking whether a model is already here
    /// without starting a download, and deleting it afterwards.
    public static func cacheSubpath(for repository: String) -> String {
        "models--" + repository.replacingOccurrences(of: "/", with: "--")
    }

    /// Sum of the file sizes the app enumerated.
    public static func totalBytes(_ sizes: [Int]) -> Int { sizes.reduce(0, +) }

    // MARK: - what the screen says

    public static func notDownloaded(_ model: PhoneModel) -> String {
        "Not on this phone. \(model.downloadDescription) to download."
    }

    /// Mid-download, driven by the FRACTION rather than a unit count.
    ///
    /// THE UNIT COUNT ONLY MOVES IN WHOLE FILES, and these repositories are one
    /// enormous `model.safetensors` beside a dozen small JSONs. Counting units
    /// meant the line read "Downloading — 1%, 14 MB of 2.3 GB" and then sat
    /// frozen for twenty minutes while the only file that matters came down.
    /// `fractionCompleted` is the one field a composed `Progress` advances
    /// continuously.
    ///
    /// THE CLAMP IS LOAD-BEARING. The parent's total is a sum of tree-entry
    /// sizes while each child's is later overwritten by the HTTP content
    /// length, so an unclamped fraction prints 103%.
    public static func downloading(fraction: Double, totalBytes: Int) -> String {
        let f = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        let percent = Int((f * 100).rounded())
        // The hub reports a placeholder count of 1 when the snapshot was
        // already cached: there are no bytes to name, so do not invent
        // "0 MB of 0 MB".
        guard totalBytes > 1 else { return "Downloading — \(percent)%." }
        return "Downloading — \(percent)%, "
             + "\(PhoneModel.megabytes(Int(f * Double(totalBytes)))) of "
             + "\(PhoneModel.megabytes(totalBytes))."
    }

    /// How much of a model is actually here.
    ///
    /// THERE ARE THREE STATES AND THE CODE KNEW TWO. A directory with any file
    /// in it read as installed, so a download torn off half way showed the
    /// green "On this phone, taking 1.4 GB" with a Delete button and no way
    /// back to Download.
    public enum InstallState: Equatable, Sendable { case absent, partial, complete }

    /// Complete means a config, a tokenizer, and — when the repository is
    /// sharded — every distinct file the weight map names.
    public static func state(paths: [String], indexJSON: Data?, bytes: Int) -> InstallState {
        guard bytes > 0, !paths.isEmpty else { return .absent }
        let names = Set(paths.map { $0.split(separator: "/").last.map(String.init) ?? $0 })
        guard names.contains("config.json"),
              names.contains(where: { $0.hasPrefix("tokenizer") }) else { return .partial }

        guard let indexJSON,
              let index = try? JSONSerialization.jsonObject(with: indexJSON) as? [String: Any],
              let map = index["weight_map"] as? [String: String] else {
            // Not sharded: one weights file is the whole of it.
            return names.contains(where: { $0.hasSuffix(".safetensors") }) ? .complete : .partial
        }
        return Set(map.values).isSubset(of: names) ? .complete : .partial
    }

    public static func partlyDownloaded(bytes: Int) -> String {
        "Partly downloaded — \(PhoneModel.megabytes(bytes)) on this phone. Downloading again "
      + "keeps the files that finished and starts the one in progress over."
    }

    /// Installed, with the size MEASURED on disk.
    public static func installed(bytes: Int) -> String {
        "On this phone, taking \(PhoneModel.megabytes(bytes))."
    }

    public static func failed(_ reason: String) -> String {
        "That did not finish. \(reason)"
    }

    /// THE DOWNLOAD STOPS IF YOU LEAVE, and saying so is not optional: a
    /// two-gigabyte fetch that silently dies when somebody switches apps is a
    /// wasted evening they will blame on their network.
    ///
    /// AND IT DOES NOT RESUME MID-FILE, WHICH THE OLD WORDING PROMISED. The
    /// hub writes its partial-blob marker only on the success path and then
    /// moves it away; the in-flight temporary file is discarded on cancel. So
    /// files that finished are kept and the one in progress starts over — which
    /// is a materially different promise on a 2.3 GB single-file download.
    public static let staysOpenNote =
        "Keep this screen open while it downloads. Leaving stops it. Files that already finished "
      + "are kept, and the one in progress starts over."

    public static let cellularWarning =
        "This is a large download. On cellular it will use that much of your data allowance."

    /// Said when the weights cannot be reached because MLX is not there.
    public static let simulatorRefusal =
        "This model runs on the phone's GPU, which the Simulator does not have. Try it on a "
      + "device."

    public static let notLoaded =
        "That model is not loaded. It may have been deleted while this screen was open."

    /// The delete confirmation, naming the MEASURED bytes it frees.
    ///
    /// TAKES A NAME, NOT A `PhoneModel`. The swipe-to-delete path holds a
    /// `ModelEndpoint` whose repository may be one somebody searched for, which
    /// is in no catalogue — and the bytes may be unknown if the directory has
    /// already gone.
    public static func deleteConfirmation(named name: String, bytes: Int?) -> String {
        guard let bytes else {
            return "Delete \(name)? Its weights come off this phone and can be downloaded "
                 + "again, at the same cost."
        }
        return "Delete \(name) and free \(PhoneModel.megabytes(bytes))? It can be downloaded "
             + "again, at the same cost."
    }

    /// Turns a chat template's thinking block off, where the template reads it.
    ///
    /// TWO OF THE FIVE CATALOGUE MODELS THINK BY DEFAULT. Qwen3's template
    /// suppresses it only through `enable_thinking`, and nothing set it — so
    /// both spent a 1200-token ceiling reasoning at temperature 0, which
    /// Qwen's own card warns against by name: greedy decoding with thinking on
    /// gives "endless repetitions". Greedy decoding is right here *because*
    /// this is set; shipping one without the other is the documented failure.
    public static let templateThinkingOff: [String: any Sendable] = ["enable_thinking": false]

    /// Said when a repository downloaded and then would not open.
    ///
    /// THE DISTINCTION IS THE WHOLE SENTENCE. The loader fetches only
    /// `*.safetensors`, `*.json` and `*.jinja`, so a repository whose tokenizer
    /// needs a `.model` or `.txt` file downloads IN FULL and then fails at the
    /// tokenizer. Somebody told only "failed" retries the download and spends
    /// the bytes again.
    public static let downloadedButWouldNotOpen =
        "The download finished and the model would not open — its tokenizer needs a file the "
      + "loader does not fetch. Downloading it again will not help; try one from the list above."
}
