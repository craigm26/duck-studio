import SwiftUI
import StudioKit

/// Give a policy a name you will recognise.
///
/// THIS SHEET DRAWS AND NOTHING ELSE. The rule about what a name may be, the
/// refusal sentences, the explainer under the field and the recomputation that
/// happens when a name is cleared all live in `PolicyTitleRule` and
/// `PolicyLibrary`, where `swift test` reads them letter by letter. What is
/// left here is a field, a button, and where the refusal goes.
///
/// THE REFUSAL IS UNDER THE FIELD AND THE BUTTON IS DISABLED, not the other way
/// round. A Save that does nothing is the failure this app spends most of its
/// copy avoiding; a Save that is out while a sentence says why is a control
/// whose state has a reason on screen beside it.
///
/// CLEAR IS DRAWN ONLY WHERE IT WOULD DO SOMETHING. With no typed title,
/// clearing recomputes the same name from the same ladder and changes nothing —
/// an inert control, and one that would imply the current name was yours.
struct PolicyRenameSheet: View {

    let entry: PolicyLibrary.Entry
    /// `nil` clears back to the recomputed ladder. Returns the kit's refusal
    /// when there is one, which is the only thing this sheet shows in red.
    let commit: (String?) -> PolicyTitleRule.Refusal?

    @Environment(\.dismiss) private var dismiss
    @State private var typed: String = ""
    @State private var refusal: PolicyTitleRule.Refusal?
    /// So the field arrives selected: one tap replaces the whole name, which is
    /// what somebody opening a rename sheet is nearly always about to do.
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $typed)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: DesignMetric.minimumTarget)
                        .onChange(of: typed) { _, _ in refusal = nil }
                    if let refusal {
                        Label(refusal.message(keeping: entry.title),
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    SectionHeading(text: "Name")
                } footer: {
                    Text(PolicyTitleRule.explainer)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)

                if entry.titleSource == .typed {
                    Section {
                        Button("Clear", role: .destructive) {
                            _ = commit(nil)
                            dismiss()
                        }
                        .frame(minHeight: DesignMetric.minimumTarget)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(refusal != nil)
                }
            }
        }
        .onAppear {
            // PREFILLED WITH WHAT IT IS CALLED NOW, whichever rung that came
            // from. Somebody renaming a `.digest` entry gets "Unnamed policy
            // 4f2a1c3b" in the field and clears it, which is one gesture more
            // than an empty field would be — and an empty field beside a row
            // that says "Name" is a screen that has lost the thing it is about.
            if typed.isEmpty { typed = entry.title }
            focused = true
        }
    }

    private func save() {
        if let refused = commit(typed) {
            refusal = refused
            return
        }
        dismiss()
    }
}
