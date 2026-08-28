import SwiftUI
import DuckKit
import DuckEvidence
import StudioKit

/// The recordings. A separate place from the policies, because they are a
/// separate kind of thing.
///
/// A POLICY IS A NETWORK; AN INTENT IS A MOTION. A policy has no time axis at
/// all — you hand it an observation and it answers with fourteen numbers, and
/// that is the whole of it. An intent has nothing BUT a time axis: it is what
/// happened over four seconds when a policy drove a robot in a physics engine.
/// One is probed, the other is watched.
///
/// The first cut of this app put them on one screen, and the seam showed
/// immediately: opening `roulade.onnx` and tapping through to its bench offered
/// a list of clips that had nothing to do with roulade, under a heading about
/// standard deviations that described the observation rather than any of them.
/// They are two lists now, and the real relationship between them — every clip
/// names the policy it was recorded from — is shown as a link rather than as an
/// accident of layout.
struct IntentListView: View {
    @State private var clips: [String: DuckIntentClip] = [:]

    private var fromPollen: [DuckIntentClip] {
        sorted(clips.values.filter { !$0.authored && $0.credit == nil })
    }
    private var authored: [DuckIntentClip] {
        sorted(clips.values.filter { $0.authored })
    }
    private var shared: [DuckIntentClip] {
        sorted(clips.values.filter { $0.credit != nil })
    }

    private func sorted(_ c: [DuckIntentClip]) -> [DuckIntentClip] {
        c.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            Section {
                Text("Motions recorded in MuJoCo from the trained policies, because the policy cannot run live on a phone. Playing one shows what the robot did; it does not re-run the network.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if !fromPollen.isEmpty {
                Section {
                    ForEach(fromPollen, id: \.name) { row($0) }
                } header: {
                    Text("From Pollen's policies")
                } footer: {
                    Text("The policy's own output, driven in physics and recorded.")
                }
            }
            if !authored.isEmpty {
                Section {
                    ForEach(authored, id: \.name) { row($0) }
                } header: {
                    Text("Authored moves")
                } footer: {
                    Text("A keyframe track riding on a standing policy as offsets — searched against a prop rather than trained. These are the ones most likely to fail, and the posture each ends in says whether it did.")
                }
            }
            if !shared.isEmpty {
                Section {
                    ForEach(shared, id: \.name) { row($0) }
                } header: {
                    Text("Shared by other owners")
                } footer: {
                    Text("Recorded the same way, from a policy this app did not ship.")
                }
            }
        }
        .navigationTitle("Intents")
        .onAppear { clips = (try? DuckIntentClip.bundled()) ?? [:] }
    }

    private func row(_ clip: DuckIntentClip) -> some View {
        NavigationLink {
            IntentPlayerView(clip: clip)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(clip.name).font(.subheadline.weight(.medium))
                    if clip.environment.hasProps {
                        Image(systemName: "square.3.layers.3d")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.1fs", clip.duration))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                // The measured start and end posture. It is the single most
                // useful line in the row: step_up reads "standing → toppled",
                // which is the move failing, stated plainly.
                HStack(spacing: 4) {
                    Text(clip.startsFrom.rawValue)
                    Image(systemName: "arrow.right").font(.caption2)
                    Text(clip.endsIn.rawValue)
                        .foregroundStyle(worrying(clip.endsIn) ? .orange : .secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Ending on the floor is worth colouring. Not an error — a roll passes
    /// through it deliberately — but it is what someone scanning the list is
    /// looking for.
    private func worrying(_ posture: DuckIntentClip.Posture) -> Bool {
        posture == .fallen || posture == .toppled
    }
}

/// One recording, played.
struct IntentPlayerView: View {
    let clip: DuckIntentClip

    @State private var playhead: TimeInterval = 0
    @State private var isRunning = true
    @State private var orbit = OrbitState()
    @State private var showProps = true
    @State private var shareURL: URL?
    @State private var shareFailure: String?

    private var pose: DuckIntentClip.Pose { clip.pose(at: playhead) }

    /// Package the motion and hand it to the system.
    private func share() {
        let export = IntentExport(clip: clip, policyFingerprint: nil)
        do {
            let data = try export.encoded()
            guard let url = ExportFile.write(data, named: export.suggestedFilename) else {
                shareFailure = "The file could not be written."
                return
            }
            shareURL = url
        } catch {
            shareFailure = "\(error)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                DuckStage(jointAngles: pose.jointAngles,
                          environment: showProps ? clip.environment : nil,
                          orbit: $orbit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.environment.hasProps && showProps
                         ? "Against the \(clip.environment.steps.isEmpty ? "wall" : "staircase") it was recorded on"
                         : "On flat ground")
                        .font(.caption2.weight(.medium))
                    Text("Drag to orbit · pinch to zoom · double-tap to reset")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(10).foregroundStyle(.white)
            }
            .frame(maxHeight: 340)

            TransportBar(duration: clip.duration, playhead: $playhead, isRunning: $isRunning)
                .padding(.horizontal).padding(.vertical, 8)

            List {
                Section("What happened") {
                    LabeledContent("Starts", value: clip.startsFrom.rawValue)
                    LabeledContent("Ends", value: clip.endsIn.rawValue)
                    LabeledContent("Turns") {
                        Text(String(format: "%+.2f rad", clip.netYaw)).monospacedDigit()
                    }
                    LabeledContent("Length") {
                        Text(String(format: "%.1f s · %d ticks", clip.duration, clip.frames.count))
                            .monospacedDigit()
                    }
                }

                Section("Recorded from") {
                    LabeledContent("Policy", value: clip.policy)
                    if clip.authored {
                        Text("A keyframe track riding on that policy as offsets, not the policy's own output. It was searched against a prop, and searching found what worked in that one situation — not a motion that generalises.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let credit = clip.credit {
                        LabeledContent("Contributed", value: credit)
                    }
                }

                Section {
                    Button { share() } label: {
                        Label("Share this motion", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text("Sends a .duckintent file — the frames, the postures, and the digest of the policy it was recorded from. The digest lets whoever receives it check they hold the same network; it does not say who made the motion, because a signature nobody can anchor would not tell them that either.")
                }

                if clip.environment.hasProps {
                    Section {
                        Toggle("Show what it was recorded against", isOn: $showProps)
                    } footer: {
                        Text("Hiding the props is how you see the motion alone; showing them is how you see whether it worked. \(clip.name) was performed against \(clip.environment.steps.isEmpty ? "a wall" : "a four-step flight"), and without it on screen a duck that falls over looks like it fell over for no reason.")
                    }
                }
            }
        }
        .navigationTitle(clip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { share() } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .sheet(item: Binding(get: { shareURL.map(SharePayload.init) },
                             set: { shareURL = $0?.url })) { payload in
            ShareSheet(items: [payload.url])
        }
        .alert("Could not share", isPresented: Binding(
            get: { shareFailure != nil }, set: { if !$0 { shareFailure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(shareFailure ?? "") }
        .onReceive(Timer.publish(every: 1.0 / DuckModel.tickHz, on: .main, in: .common).autoconnect()) { _ in
            guard isRunning else { return }
            playhead += 1.0 / DuckModel.tickHz
            if pose.hasFinished && !clip.loops { playhead = 0 }
        }
    }
}

/// Play, pause, restart, scrub.
struct TransportBar: View {
    let duration: TimeInterval
    @Binding var playhead: TimeInterval
    @Binding var isRunning: Bool

    var body: some View {
        HStack(spacing: 14) {
            Button { isRunning.toggle() } label: {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
            }
            Button { playhead = 0; isRunning = true } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            Slider(value: $playhead, in: 0...max(duration, 0.01)) { editing in
                // Scrubbing pauses, or the playhead fights the thumb and the
                // duck twitches between where you dragged and where the timer
                // has got to.
                if editing { isRunning = false }
            }
            Text(String(format: "%.2fs", playhead))
                .font(.caption2.monospacedDigit())
                .frame(width: 46, alignment: .trailing)
        }
        .buttonStyle(.borderless)
    }
}

/// A URL made identifiable, so it can drive a sheet.
private struct SharePayload: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
