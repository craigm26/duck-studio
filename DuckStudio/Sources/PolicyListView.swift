import SwiftUI
import DuckKit
import DuckEvidence
import StudioKit

/// The library: every policy this app holds, and where each one came from.
///
/// ORGANISED BY PROVENANCE, NOT BY FOLDER. The sections are "Released by Pollen
/// Robotics" and "From elsewhere", and which section a policy lands in is
/// decided by its parameter fingerprint — not by whether it shipped in the
/// bundle. Those two answers diverge the moment anyone downloads a policy from
/// Pollen's own repository, and a heading that said "Bundled" would be telling
/// the reader where a file came from while looking like it was telling them
/// what it is.
struct PolicyListView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var scenes: SceneStore
    @ObservedObject var drafts: DraftStore
    /// Not used on this screen — carried through to the clip player and the
    /// bench, because a motion remixed from a policy's own recordings opens the
    /// same editor as one remixed from the Intents tab, and the Ask panel there
    /// was dead for want of this one argument. No screen in this app puts a
    /// store in the environment; every one is passed by hand, so a feature that
    /// needs one three screens down has to be threaded through the two between.
    @ObservedObject var models: EndpointStore

    private var released: [PolicyLibrary.Entry] {
        model.library.entries.filter { isReleased(model.standing(for: $0)) }
    }
    private var elsewhere: [PolicyLibrary.Entry] {
        model.library.entries.filter { !isReleased(model.standing(for: $0)) }
    }

    var body: some View {
        List {
            if let message = model.lastImport {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            if !released.isEmpty {
                Section {
                    ForEach(released) { row($0) }
                } header: {
                    Text("Released by Pollen Robotics")
                } footer: {
                    Text("Matched by fingerprint — a digest of the trained weights, not of the file. A re-export under a newer opset still matches; one changed weight does not.")
                }
            }
            if !elsewhere.isEmpty {
                Section {
                    ForEach(elsewhere) { row($0) }
                } header: {
                    Text("From elsewhere")
                } footer: {
                    Text("Trained by someone else, or newer than this app knows about. This only says the weights are unfamiliar — not that they are bad.")
                }
            }
            if model.library.entries.isEmpty {
                Section {
                    Text("No policies yet. Send one to Duck Studio from Files, Mail or AirDrop.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Policies")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("\(model.library.runnableCount) of \(model.library.entries.count) run")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { RemoteRunView(scenes: scenes, drafts: drafts, models: models) } label: {
                    Label("Run on your network", systemImage: "wifi")
                }
                NavigationLink { CatalogueView(model: model) } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        // The destination's own title. An icon-only link
                        // announces the SF Symbol's name or nothing at all —
                        // "antenna radiowaves left and right" is not where
                        // anybody is trying to go, and the screen this opens is
                        // called Pollen Robotics.
                        .accessibilityLabel(Text("Pollen Robotics"))
                }
            }
        }
    }

    private func isReleased(_ standing: DuckOfficialPolicies.Standing) -> Bool {
        if case .released = standing { return true }
        return false
    }

    private func row(_ entry: PolicyLibrary.Entry) -> some View {
        NavigationLink {
            PolicyDetailView(entry: entry, standing: model.standing(for: entry),
                             scenes: scenes, drafts: drafts, models: models)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.isRunnable ? "checkmark.seal" : "exclamationmark.triangle")
                    .foregroundStyle(entry.isRunnable ? Color.accentColor : .orange)
                    // WHETHER THIS FILE RUNS IS THE ONE THING THE ROW SAYS IN
                    // A SEAL AND A COLOUR AND NOWHERE ELSE. The verdict is
                    // StudioKit's sentence, written for exactly this — "One
                    // short line, suitable for a row in a list" — so the icon
                    // reads it out rather than this view inventing a second
                    // wording of the same judgement.
                    .accessibilityLabel(Text(entry.report.headline))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName).font(.subheadline.weight(.medium))
                    HStack(spacing: 6) {
                        // Sixteen characters is what a person compares at a
                        // glance; the full digest is on the detail screen,
                        // because a truncated hash is a weaker claim and the
                        // place it is VERIFIED should show the whole thing.
                        Text(entry.shortIdentity).font(.caption2.monospaced())
                        Text(entry.origin.label).font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One policy: what it is, where it came from, and what is inside it.
struct PolicyDetailView: View {
    let entry: PolicyLibrary.Entry
    let standing: DuckOfficialPolicies.Standing
    @ObservedObject var scenes: SceneStore
    @ObservedObject var drafts: DraftStore
    /// For the player below: a recording listed here opens the same viewer, and
    /// a remix from it opens the same editor, as the Intents tab. Without this
    /// the Ask panel in that editor was disabled with a message pointing at a
    /// screen this view tree does not contain.
    @ObservedObject var models: EndpointStore
    @State private var clips: [String: DuckIntentClip] = [:]
    @State private var outgoing: Outgoing?
    @State private var failure: String?

    /// Clips whose recorded-from policy is this file. Matched on the filename
    /// the recorder wrote, which is the only link the clip carries.
    private var madeFromThisPolicy: [DuckIntentClip] {
        clips.values.filter { $0.policy == entry.displayName }.sorted { $0.name < $1.name }
    }

    var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { share() } label: { Image(systemName: "square.and.arrow.up") }
                        // The button people go hunting for, and the one an
                        // unlabelled square-and-arrow-up hides best.
                        .accessibilityLabel(Text("Share this policy"))
                        .disabled(!entry.isRunnable && !entry.identity.isNetworkIdentity)
                }
            }
            .sheet(item: $outgoing) { out in
                NavigationStack {
                    ShareDestinationsView(title: entry.displayName,
                                          file: out.url, message: out.message)
                }
            }
            .alert("Could not share", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(failure ?? "") }
    }

    /// Hand over the policy FILE, with a message that leads with the digest.
    /// The person pasting this is about to ask strangers to run it on a robot,
    /// so an unrecognised policy is described as unrecognised.
    private func share() {
        guard let data = PolicyStore.data(for: entry) else {
            failure = "The policy file could not be re-read."
            return
        }
        do {
            let url = try ExportFile.write(data, named: entry.displayName)
            outgoing = Outgoing(url: url,
                                message: CommunityShare.message(forPolicy: entry, standing: standing))
        } catch let error as ExportFile.Failure {
            failure = error.message
        } catch {
            failure = "\(error)"
        }
    }

    private var content: some View {
        List {
            Section("Provenance") {
                Text(DuckOfficialPolicies.summary(for: standing))
                    .font(.footnote)
                LabeledContent(entry.identity.isNetworkIdentity ? "Weights" : "File digest") {
                    Text(entry.identity.value)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                if !entry.identity.isNetworkIdentity {
                    Text("This file does not load, so it has no weights to fingerprint. It is identified by the bytes of the file instead — which is a weaker kind of identity, and the reason it says so.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Arrived", value: entry.origin.label)
            }

            Section(entry.isRunnable ? "Verdict" : "Why it will not load here") {
                Text(entry.report.headline).font(.subheadline.weight(.medium))
                if !entry.report.reason.isEmpty {
                    Text(entry.report.reason).font(.footnote)
                }
                if let remedy = entry.report.remedy {
                    Text(remedy).font(.footnote).foregroundStyle(.secondary)
                }
                // WHERE THE REFUSAL STOPS. This app reads one exact
                // architecture and the robot's runtime reads far less, so a
                // refusal here is not the robot's answer — and a person looking
                // at "will not load" is exactly the person about to conclude
                // their file is broken.
                if entry.report.outcome == .refused {
                    Text(PolicyReport.refusalIsAboutThisApp)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if entry.isRunnable {
                Section {
                    NavigationLink { BenchView(entry: entry, store: scenes) } label: {
                        Label("Probe this network", systemImage: "slider.horizontal.below.square.filled.and.square")
                    }
                } footer: {
                    Text("Hand it an observation and see the fourteen numbers it answers with, and the robot they command. A network has no time axis — nothing plays here.")
                }

                // The real link between the two halves of this app: a clip
                // names the policy it was recorded from, so a policy can list
                // its own recordings. Shown only when there ARE any, rather
                // than as an empty section implying something is missing.
                let recordings = madeFromThisPolicy
                if !recordings.isEmpty {
                    Section {
                        ForEach(recordings, id: \.name) { clip in
                            NavigationLink { IntentPlayerView(clip: clip, store: scenes, drafts: drafts,
                                                              models: models) } label: {
                                HStack {
                                    Text(clip.name).font(.subheadline)
                                    Spacer()
                                    Text("\(clip.startsFrom.rawValue) → \(clip.endsIn.rawValue)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Recorded from this policy")
                    } footer: {
                        Text("Motions this network produced when it drove a robot in physics. These play; the network itself does not.")
                    }
                }
            }

            Section("Structure") {
                ForEach(entry.report.facts, id: \.label) { fact in
                    LabeledContent(fact.label) {
                        Text(fact.value)
                            .font(.caption.monospaced())
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .navigationTitle(entry.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { clips = (try? DuckIntentClip.bundled()) ?? [:] }
    }
}
