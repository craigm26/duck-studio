import SwiftUI
import UIKit

/// The system share sheet.
///
/// WHY THIS AND NOT A DISCORD BUTTON. Discord, X, Messages, Mail, AirDrop and
/// Files are all already here, in the order this person actually uses them,
/// with no API key, no OAuth flow, no service that can change its terms, and
/// nothing about where a motion went passing through this app. One sheet
/// covers every destination anyone asked for and several nobody thought to.
///
/// IT MUST BE TOLD WHEN IT IS FINISHED, AND THAT IS NOT OPTIONAL. A
/// `UIActivityViewController` is built to be PRESENTED, not to be embedded, and
/// hosting one inside a SwiftUI `.sheet` puts it one layer down from the
/// presentation SwiftUI is tracking. When the person picks a destination or
/// taps Cancel, UIKit takes its own controller away — and SwiftUI, which was
/// never told, holds the sheet it is wrapped in open around the hole where the
/// controller used to be. What is left on screen is a blank card with no title,
/// no buttons and nothing to tap: the app looks broken at the exact moment it
/// just worked. So the completion handler is wired to the binding that
/// presented it, and every caller passes one.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// Called when UIKit dismisses the controller, however it ended. The caller
    /// uses this to put down the sheet it opened.
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items,
                                                  applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file on its way out, identified by where it is.
///
/// EXISTS SO THE EMPTY CASE CANNOT BE BUILT. The screens that hand over a file
/// used to keep a `Bool` and a `URL?` side by side and present on the Bool,
/// which leaves `.sheet` able to render its `if let` false branch — an
/// `EmptyView`, in a sheet, with no way out. Presenting on the value itself
/// means there is no state in which a sheet exists and the file does not.
///
/// It carries no message, unlike `Outgoing`. That is deliberate: a training
/// brief has no drafted share prose behind it, and inventing
/// one in a view is where the sentences this app is careful about would start
/// being written somewhere nothing tests them.
struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// A file written somewhere the share sheet can reach.
///
/// Temporary rather than in the container: a shared copy is a thing in flight,
/// not a thing this app keeps. Named by the intent so it arrives in a chat
/// looking like what it is.
enum ExportFile {

    /// What went wrong, in a sentence the person can act on.
    ///
    /// THROWS RATHER THAN RETURNING NIL, because nil is what every caller was
    /// quietly dropping. Four screens took the optional, wrote `guard let ...
    /// else { return }`, and left a button that a person could press all day
    /// while nothing happened and nothing was said — in the one app in this
    /// family whose whole value proposition is that it explains its refusals.
    enum Failure: Error {
        case unusableName(String)
        case couldNotWrite(String)

        var message: String {
            switch self {
            case .unusableName(let name):
                return "\"\(name)\" cannot be used as a file name. Rename it without a slash or "
                     + "a colon and try again."
            case .couldNotWrite(let reason):
                return "The file could not be written. \(reason)"
            }
        }
    }

    /// Everything a file name cannot contain and still be one path component.
    ///
    /// A NAME IS TYPED BY A PERSON, so it arrives with whatever they typed in
    /// it. `appendingPathComponent("up/down.duckmove")` does not make a file
    /// called "up/down" — it makes a *directory* called "up" that does not
    /// exist, and the write then fails for a reason that has nothing to do with
    /// anything the person can see.
    private static let forbidden = CharacterSet(charactersIn: "/\\:\u{0}")

    /// The name, made safe to be one component, or nil if nothing usable is
    /// left. The extension is preserved: it is what tells iOS, and the person
    /// receiving it, what the file is.
    static func safeName(_ name: String) -> String? {
        let cleaned = name
            .components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A leading dot makes a hidden file, and a name that is only dots is
        // not a name at all.
        guard !cleaned.isEmpty, cleaned.contains(where: { $0 != "." }) else { return nil }
        return cleaned.hasPrefix(".") ? String(cleaned.dropFirst()) : cleaned
    }

    static func write(_ data: Data, named name: String) throws -> URL {
        guard let safe = safeName(name) else { throw Failure.unusableName(name) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw Failure.couldNotWrite(error.localizedDescription)
        }
        return url
    }
}
