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

    /// Mid-download. THE PERCENTAGE AND THE BYTES TOGETHER: a percentage alone
    /// hides how much of somebody's data allowance is going, and a byte count
    /// alone hides how far along it is.
    public static func downloading(completed: Int, total: Int) -> String {
        guard total > 0 else { return "Downloading…" }
        let percent = Int((Double(completed) / Double(total) * 100).rounded())
        return "Downloading — \(percent)%, \(PhoneModel.megabytes(completed)) of "
             + "\(PhoneModel.megabytes(total))."
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
    public static let staysOpenNote =
        "Keep this screen open while it downloads. Leaving stops it, and it starts again from "
      + "where it got to."

    public static let cellularWarning =
        "This is a large download. On cellular it will use that much of your data allowance."

    /// Said when the weights cannot be reached because MLX is not there.
    public static let simulatorRefusal =
        "This model runs on the phone's GPU, which the Simulator does not have. Try it on a "
      + "device."

    public static let notLoaded =
        "That model is not loaded. It may have been deleted while this screen was open."

    /// The delete confirmation, naming the MEASURED bytes it frees.
    public static func deleteConfirmation(_ model: PhoneModel, bytes: Int) -> String {
        "Delete \(model.name) and free \(PhoneModel.megabytes(bytes))? It can be downloaded "
      + "again, at the same cost."
    }

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
