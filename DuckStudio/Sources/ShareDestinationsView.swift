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
    /// The person may be watching a real robot while this sheet is up, and
    /// somebody who has turned this on has said what they want. See the copy
    /// button.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sharing = false
    @State private var copied = false

    var body: some View {
        List {
            Section {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } header: {
                SectionHeading(text: "What to say")
            } footer: {
                Text("Written from what this app can actually check. The fingerprint is the part a recipient can verify without trusting you.")
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                // THE WORD CHANGES, NOT ONLY THE TICK. "Copied" replaces "Copy
                // the message" and the symbol follows it, so the state is
                // readable without seeing the glyph — which matters here
                // because the glyph is the whole of the feedback: nothing else
                // on screen moves when the pasteboard is written.
                //
                // `Theme.settle`, AND THE REDUCED-MOTION CURVE WHEN ASKED FOR.
                // Settle rather than the spring because a label swapping under a
                // finger that is still on it should arrive and stop: a bouncing
                // checkmark reads as the app being pleased with itself. The
                // first restyle routed this through `Theme.motion(reduced:)` to
                // honour Reduce Motion, which was right, and thereby handed
                // everyone else the overshoot this comment had argued against,
                // which was not. Both values are `Theme`'s own; choosing between
                // them here invents nothing.
                Button {
                    UIPasteboard.general.string = message
                    withAnimation(reduceMotion ? Theme.reducedMotion : Theme.settle) { copied = true }
                } label: {
                    Label(copied ? "Copied" : "Copy the message",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityLabel(Text("Copy the message"))
                .accessibilityValue(Text(copied ? "Copied" : ""))
                if file != nil {
                    Button { sharing = true } label: {
                        Label("Send the file", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("Send the file"))
                    .accessibilityHint(Text(
                        "Opens the system share sheet with the file and the message."))
                }
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                // ONE ROW PER DESTINATION, EACH WITH ITS OWN SYMBOL AND ITS OWN
                // SENTENCE. The name says where, the purpose says what that
                // place is for, and both come from `CommunityShare` — a list of
                // somewhere to post is exactly the kind of claim that goes stale
                // silently, and there it is a value `swift test` can read.
                ForEach(CommunityShare.destinations) { destination in
                    Button {
                        openURL(destination.url)
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                            Label(destination.name, systemImage: destination.symbol)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Text(destination.purpose)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    // THE NAME IS THE LABEL AND THE PURPOSE IS THE HINT, rather
                    // than both being read as one run-on utterance. A row that
                    // announces "Discord, where people building on this robot
                    // actually talk" is a row nobody can skim past in a rotor.
                    // The label is set on the BUTTON rather than by making the
                    // stack its own element: a button is already one element,
                    // and re-declaring it is how a control loses the trait that
                    // says it can be pressed.
                    .accessibilityLabel(Text(destination.name))
                    .accessibilityHint(Text(destination.purpose))
                }
            } header: {
                SectionHeading(text: "Where")
            } footer: {
                Text(CommunityShare.cannotPostNote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        // THE LIST SITS ON THE PALETTE'S RECESSED GROUND, NOT THE SYSTEM'S GREY.
        // Every row keeps a real `surfacePrimary` card under it, so nothing is
        // ever set on the ground the palette says is short of 4.5:1 for words.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
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
