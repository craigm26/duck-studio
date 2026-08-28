import SwiftUI
import UIKit

/// The system share sheet.
///
/// WHY THIS AND NOT A DISCORD BUTTON. Discord, X, Messages, Mail, AirDrop and
/// Files are all already here, in the order this person actually uses them,
/// with no API key, no OAuth flow, no service that can change its terms, and
/// nothing about where a motion went passing through this app. One sheet
/// covers every destination anyone asked for and several nobody thought to.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file written somewhere the share sheet can reach.
///
/// Temporary rather than in the container: a shared copy is a thing in flight,
/// not a thing this app keeps. Named by the intent so it arrives in a chat
/// looking like what it is.
enum ExportFile {
    static func write(_ data: Data, named name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
