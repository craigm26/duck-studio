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
struct BenchSetupView: View {
    var body: some View {
        List {
            Section {
                Text("Duck Studio can read a policy and blend one. It cannot RUN one — an "
                   + "iPhone has no physics engine. The bench is a small program on a computer "
                   + "you already own that does, and these are the steps to start it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("On the other computer") {
                ForEach(BenchSetup.steps) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(step.number). \(step.title)")
                            .font(.subheadline.weight(.semibold))
                        Text(step.detail)
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let copyable = step.copyable {
                            Button {
                                UIPasteboard.general.string = copyable
                            } label: {
                                Label(copyable, systemImage: "doc.on.doc")
                                    .font(.caption.monospaced())
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Text("The bench window has to stay open while you use it. Closing it stops the "
                   + "bench, and the app will say nothing answered.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Setting up a bench")
        .navigationBarTitleDisplayMode(.inline)
    }
}
