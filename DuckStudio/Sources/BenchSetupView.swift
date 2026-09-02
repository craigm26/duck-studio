import SwiftUI
import StudioKit

/// The screen that gets a phone talking to a machine with physics.
///
/// IT EXISTS BECAUSE THE ADDRESS FIELD WAS THE WHOLE ONBOARDING. A text box
/// labelled "192.168.1.20:8770" assumes somebody already knows there is a
/// program to install, on which machine, what it is called, and what to type
/// when it does not work. That is the one setup in this app that happens on a
/// DIFFERENT DEVICE, so it is the one that cannot be discovered by tapping
/// around.
///
/// IT IS THE STEPS AND NOTHING ELSE. It used to carry its own address field and
/// Test button, which was right when there was one bench and became a second
/// place to type an address the moment `BenchSettingsView` existed — two boxes
/// for the same setting, disagreeing. Entering and checking an address belongs
/// to the bench being edited; this screen answers "what do I do on the other
/// computer", which no editor can.
///
/// THE ONLY MONOSPACE ON IT IS THE PART YOU TYPE SOMEWHERE ELSE. Everything on
/// this screen is prose that never changes, and the design system reads tabular
/// figures as a claim that something is going to move — so the steps are SF and
/// the command is mono, because the command is code and has to be transcribable
/// character by character.
struct BenchSetupView: View {
    var body: some View {
        List {
            Section {
                Text("Microduck Studio can read a policy and blend one. It cannot RUN one — an "
                   + "iPhone has no physics engine. The bench is a small program on a computer "
                   + "you already own that does, and these are the steps to start it.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section("On the other computer") {
                ForEach(BenchSetup.steps) { step in
                    stepRow(step)
                }
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Text("The bench window has to stay open while you use it. Closing it stops the "
                   + "bench, and the app will say nothing answered.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        // THE RECESSED GROUND UNDER THE CARDS, which is what this token is for.
        // Every word on this screen sits on a `surfacePrimary` row; `Palette`
        // is explicit that `backgroundSecondary` carries the inks short of the
        // 4.5:1 body text owes, and is a ground for surfaces rather than words.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Setting up a bench")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One numbered step, and — where there is something to type — the thing to
    /// type, as a button that puts it on the pasteboard.
    @ViewBuilder private func stepRow(_ step: BenchSetup.Step) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Text("\(step.number). \(step.title)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.detail)
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let copyable = step.copyable {
                Button {
                    UIPasteboard.general.string = copyable
                } label: {
                    Label(copyable, systemImage: "doc.on.doc")
                        .font(.caption.monospaced())
                        // A COMMAND IS NOT A ONE-LINER ON EVERY PHONE. Left to
                        // truncate, the middle of a path disappears behind an
                        // ellipsis and the thing this button exists to show
                        // becomes unreadable — on the screen whose entire job
                        // is telling somebody what to type on another machine.
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        // THE HIG'S FLOOR, STATED — BECAUSE THE ARITHMETIC DID
                        // NOT REACH IT. This claimed that a caption with
                        // `.snug` above and below was already past forty-four
                        // points; it is not. A caption is thirteen points and
                        // its line box about sixteen, so twelve either side
                        // makes forty on a one-line command, and less again at
                        // the smaller text sizes — a shortfall nobody was going
                        // to notice, on the one control on this screen that
                        // does anything.
                        //
                        // The frame names `DesignMetric.minimumTarget`, which
                        // is the app's one 44, rather than writing the number
                        // again or hoping a font metric supplies it. The
                        // padding stays: it is what keeps the command clear of
                        // the step's prose, which is a spacing decision and
                        // belongs on the spacing scale.
                        .padding(.vertical, Theme.spacing(.snug))
                        .frame(maxWidth: .infinity,
                               minHeight: DesignMetric.minimumTarget,
                               alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.actionSecondary)
                // THE WORD FOR WHAT IT DOES, THEN THE THING ITSELF. Unlabelled
                // this announces the command and the trait "button", and what
                // the button does with the command is left to be guessed.
                .accessibilityLabel(Text("Copy"))
                .accessibilityValue(Text(copyable))
            }
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }
}
