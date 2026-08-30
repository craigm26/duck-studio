import SwiftUI
import DuckKit
import StudioKit

/// Send it somewhere: the file, a message worth pasting, and a link that opens
/// the right place.
///
/// NOTHING IS POSTED FOR YOU, and the sheet says so above the buttons rather
/// than in a footnote. iOS hands the file to whichever app is picked; this app
/// has no account anywhere.
struct ShareDestinationsView: View {
    let title: String
    /// The file to hand over, already written to a temporary URL.
    let file: URL?
    /// The message drafted by StudioKit, where every claim is one the app can
    /// actually support.
    let message: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var sharing = false
    @State private var copied = false

    var body: some View {
        List {
            Section {
                Text(message)
                    .font(.footnote)
                    .textSelection(.enabled)
            } header: {
                Text("What to say")
            } footer: {
                Text("Written from what this app can actually check. The fingerprint is the part a recipient can verify without trusting you.")
            }

            Section {
                Button {
                    UIPasteboard.general.string = message
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy the message", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                if file != nil {
                    Button { sharing = true } label: {
                        Label("Send the file", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                ForEach(CommunityShare.destinations) { destination in
                    Button {
                        openURL(destination.url)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(destination.name, systemImage: destination.symbol)
                                .font(.subheadline)
                            Text(destination.purpose)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Where")
            } footer: {
                Text(CommunityShare.cannotPostNote)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        // `file` is a `let` handed in by the caller, so it cannot become nil
        // under the sheet. What it still needs is the completion handler: a
        // share that ends leaves this sheet up and empty without it.
        .sheet(isPresented: $sharing) {
            if let file { ShareSheet(items: [file, message]) { sharing = false } }
        }
    }
}
