import SwiftUI
import StudioKit

/// Studio > Settings > Models > Hosted planners: paste or forget an Anthropic or OpenAI key.
///
/// KEYS ONLY. No planner card appears on Play or Auto: the offer rule hides both until a
/// measured row exists, and this screen says so. Nothing here makes a network call. A key is
/// checked for shape by the kit and saved to this device's Keychain. Every sentence is a kit
/// string (`HostedPlannerWords`).
struct HostedKeysView: View {
    var body: some View {
        List {
            Section {
                Text(HostedPlannerWords.notOfferedYet)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
            ForEach(HostedVendor.allCases, id: \.self) { vendor in
                HostedKeySection(vendor: vendor)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(HostedPlannerWords.heading)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One vendor's key: the field, Save, Forget, and the card's disclosure lines underneath.
private struct HostedKeySection: View {
    let vendor: HostedVendor
    @State private var typed = ""
    @State private var said: String?
    @State private var problem: String?
    @State private var saved = false

    var body: some View {
        Section {
            SecureField(HostedPlannerWords.keyPlaceholder(vendor), text: $typed)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
            Button { save() } label: {
                Label(HostedPlannerWords.saveKey, systemImage: "key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if saved {
                Button(role: .destructive) {
                    HostedKeyStore.clear(vendor)
                    saved = false
                    said = HostedPlannerWords.forgotten(vendor)
                } label: {
                    Text(HostedPlannerWords.forgetKey).foregroundStyle(Theme.critical)
                }
            }
            if let said {
                Text(said).font(.footnote).foregroundStyle(Theme.measured)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem {
                Label(problem, systemImage: "xmark.octagon")
                    .font(.footnote).foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: vendor.name)
        } footer: {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                ForEach(HostedPlannerWords.card(vendor), id: \.self) { line in
                    Text(line)
                }
            }
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
        .task {
            if let key = HostedKeyStore.load(vendor) {
                saved = true
                said = HostedPlannerWords.savedHere(vendor, hint: DuckDream.hint(key))
            }
        }
    }

    private func save() {
        problem = nil
        switch vendor.cleaned(typed) {
        case .failure(let why):
            problem = why.says
        case .success(let key):
            HostedKeyStore.save(key, for: vendor)
            typed = ""
            saved = true
            said = HostedPlannerWords.savedHere(vendor, hint: DuckDream.hint(key))
        }
    }
}
