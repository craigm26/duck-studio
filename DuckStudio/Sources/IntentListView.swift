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
    @ObservedObject var store: SceneStore
    @ObservedObject var model: LibraryModel
    @ObservedObject var drafts: DraftStore
    @State private var editing: IntentDraft?
    @State private var clips: [String: DuckIntentClip] = [:]
    @State private var picking = false
    /// Rolled-out rates, loaded once. The list is the place these matter most:
    /// scanning fourteen motions for the ones that actually work is the whole
    /// reason to have measured them.
    @State private var odds: DuckIntentSuccess?

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

            Section {
                ForEach(drafts.drafts) { draft in
                    Button { editing = draft } label: { draftRow(draft) }
                        .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets { drafts.delete(drafts.drafts[index]) }
                }
                Button {
                    let fresh = IntentDraft.blank()
                    drafts.save(fresh)
                    editing = fresh
                } label: { Label("Write a new motion", systemImage: "plus") }
            } header: {
                Text("Written here")
            } footer: {
                Text("Poses and times, interpolated. A phone has no physics engine, so this is what you asked the robot for — not what it would do. Every authored move already in this app was written the same way, and all four stair ones get up their flight 0 times in 16.")
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
            if !model.importedClips.isEmpty {
                Section {
                    ForEach(model.importedClips, id: \.name) { row($0) }
                } header: {
                    Text("Sent to you")
                } footer: {
                    Text("Motions imported from a .duckintent file. Each names the policy it was recorded from by digest, so you can check whether you hold the same network.")
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { picking = true } label: { Image(systemName: "square.and.arrow.down") }
            }
        }
        .fileImporter(isPresented: $picking,
                      allowedContentTypes: [.json, .data],
                      allowsMultipleSelection: false) { result in
            // The same door as onOpenURL, so a motion picked from Files and one
            // AirDropped end up in the same place having had the same checks.
            if case .success(let urls) = result, let url = urls.first { model.open(url) }
        }
        .onAppear {
            clips = (try? DuckIntentClip.bundled()) ?? [:]
            odds = try? DuckIntentSuccess.bundled()
        }
        .sheet(item: $editing) { draft in
            NavigationStack {
                IntentAuthorView(draft: draft, scenes: store) { drafts.save($0) }
            }
        }
    }

    private func row(_ clip: DuckIntentClip) -> some View {
        NavigationLink {
            IntentPlayerView(clip: clip, store: store, drafts: drafts)
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
                    if let outcome = odds?[clip.name] {
                        Text("·")
                        // The measured rate, not the posture. `climb` ends
                        // standing every time and gets up the flight none of
                        // them, and the posture alone cannot say that.
                        Text("works \(outcome.achieves)/\(outcome.rollouts)")
                            .foregroundStyle(outcome.achieves == 0 ? .orange : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func draftRow(_ draft: IntentDraft) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(draft.name).font(.subheadline.weight(.medium))
                Spacer()
                if !draft.isPlayable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Text(String(format: "%.1fs", draft.duration))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("\(draft.keys.count) keyframes · no physics")
                .font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
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
    /// Scenes this phone holds, so a motion can be played somewhere other than
    /// where it was recorded. Optional because the bench opens this view too.
    var store: SceneStore?
    var drafts: DraftStore?

    @State private var remixed: IntentDraft?
    @State private var playhead: TimeInterval = 0
    @State private var isRunning = true
    @State private var orbit = OrbitState()
    @State private var showProps = true
    @State private var elsewhere: DuckScene?
    @State private var shareURL: URL?
    @State private var shareFailure: String?
    @State private var panel: Panel = .story

    enum Panel: String, CaseIterable, Identifiable {
        case story = "What happened", numbers = "Numbers"
        case curves = "Over time", reward = "Reward", odds = "How often"
        var id: String { rawValue }
    }

    private var pose: DuckIntentClip.Pose { clip.pose(at: playhead) }

    /// What the robot is standing in. The recording's own world unless somebody
    /// has deliberately moved the motion somewhere else — and when they have,
    /// the screen says so, because a clip replayed against a different
    /// staircase is no longer evidence about the one it was recorded on.
    private var world: DuckIntentClip.Environment {
        if let elsewhere { return elsewhere.environment }
        return showProps ? clip.environment : .bareFloor
    }

    private var metrics: RunMetrics {
        RunMetrics(clip: clip, success: try? DuckIntentSuccess.bundled())
    }

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
                DuckStage(pose: .at(pose),
                          environment: world,
                          trail: clip.roots,
                          progress: playhead / max(clip.duration, 1e-9),
                          orbit: $orbit)
                StageLegend(pose: .at(pose),
                            environment: world, orbit: $orbit)
            }
            .frame(maxHeight: 340)

            TransportBar(duration: clip.duration, playhead: $playhead, isRunning: $isRunning)
                .padding(.horizontal).padding(.vertical, 8)

            Picker("Panel", selection: $panel) {
                ForEach(Panel.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.bottom, 6)

            List {
                if let elsewhere {
                    Section {
                        Label("Playing in \(elsewhere.name), not where it was recorded.",
                              systemImage: "arrow.triangle.branch")
                            .font(.footnote).foregroundStyle(.orange)
                        Button("Back to the recorded world") { self.elsewhere = nil }
                    }
                }

                switch panel {
                case .numbers:  numbers
                case .curves:   curves
                case .reward:   reward
                case .odds:     odds
                case .story:    story
                }
            }
        }
        .navigationTitle(clip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { share() } label: {
                        Label("Share this motion", systemImage: "square.and.arrow.up")
                    }
                    if let store, !store.scenes.isEmpty {
                        Menu("Play somewhere else") {
                            ForEach(store.scenes) { scene in
                                Button(scene.name) { elsewhere = scene; playhead = 0 }
                            }
                        }
                    }
                    if let drafts {
                        Button {
                            // A REMIX KEEPS THE SHAPES AND LOSES THE PHYSICS.
                            // Eight smoothstepped keyframes are not a recording
                            // at fifty hertz, and the draft's provenance line
                            // says so — a remix of a clip that works is not a
                            // motion that works.
                            let draft = IntentDraft.remix(clip)
                            drafts.save(draft)
                            remixed = draft
                        } label: {
                            Label("Remix into a new motion", systemImage: "wand.and.stars")
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
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
        .sheet(item: $remixed) { draft in
            NavigationStack {
                IntentAuthorView(draft: draft, scenes: store ?? SceneStore()) {
                    drafts?.save($0)
                }
            }
        }
        .onReceive(Timer.publish(every: 1.0 / DuckModel.tickHz, on: .main, in: .common).autoconnect()) { _ in
            guard isRunning else { return }
            playhead += 1.0 / DuckModel.tickHz
            if pose.hasFinished && !clip.loops { playhead = 0 }
        }
    }

    // MARK: - what happened

    @ViewBuilder private var story: some View {
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

    // MARK: - the numbers

    /// EVERY MEASURABLE THING ABOUT THE RUN. A three-line summary is enough to
    /// browse a list and not enough to judge a motion: "ends toppled" says a
    /// move failed and not how close it came, and the difference between a
    /// climb that stalls 4 mm short and one that never left the floor is the
    /// whole of whether it is worth another attempt.
    @ViewBuilder private var numbers: some View {
        let m = metrics
        Section("Where it went") { ForEach(m.travel) { ReadingRow(reading: $0) } }
        Section("How it held itself") { ForEach(m.attitude) { ReadingRow(reading: $0) } }
        Section("What the joints did") { ForEach(m.joints) { ReadingRow(reading: $0) } }
        Section {
            ForEach(m.control) { ReadingRow(reading: $0) }
        } header: {
            Text("What the policy emitted")
        } footer: {
            Text(m.telemetryMissing
                 ? "This recording stored the robot's joint angles only. The network's own output was not kept, so nothing here can be derived from it."
                 : "The network's raw output, before the gait scales it and before the travel stops clamp it.")
        }
    }

    // MARK: - how often it works

    /// A RATE CANNOT COME FROM A RECORDING, and this panel exists because
    /// somebody will read "ends standing" and hear "works". A clip is one run;
    /// the number here comes from running the motion again, many times, with
    /// the drop height, the footpad friction, the shove and the trunk's centre
    /// of mass all varied over the ranges Pollen train against.
    @ViewBuilder private var odds: some View {
        let m = metrics
        if m.success.isEmpty {
            Section {
                Text("Nobody has rolled this motion out. A rate needs repeated runs under varied conditions, and this clip has only ever been recorded once — which is one run, not a measurement.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(m.success) { ReadingRow(reading: $0) }
            } header: {
                Text("Measured by rolling it out again")
            } footer: {
                Text("Two rates rather than one, because they are different questions and they come apart on exactly the motions that matter. A stair move that reliably ends upright on the floor repeats perfectly and achieves nothing.")
            }
        }
    }

    // MARK: - over time

    /// A summary says how far; a curve says when. Roulade is supposed to go
    /// past 90° and step_up is not, and in a table of peaks the two are
    /// indistinguishable.
    @ViewBuilder private var curves: some View {
        let series = RunSeries(clip: clip)
        Section {
            Text("Sampled once per tick at \(Int(clip.hz)) Hz, unsmoothed. The interesting features here are the sharp ones — the instant a foot lands, the tick a joint hits its stop — and a filter would remove exactly those. The orange line is the playhead.")
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(series.tracks) { track in
            Section { RunChart(track: track, playhead: playhead) }
        }
    }

    // MARK: - the reward

    @ViewBuilder private var reward: some View {
        let m = metrics
        Section { Text(m.provenance).font(.footnote).foregroundStyle(.secondary) }

        if !m.rewards.isEmpty {
            Section("Scored on this recording") {
                ForEach(m.rewards) { RewardRow(term: $0) }
            }
        }
        if !m.unevaluated.isEmpty {
            Section {
                ForEach(m.unevaluated) { ReadingRow(reading: $0) }
            } header: {
                Text("Terms a recording cannot answer")
            } footer: {
                Text("These are real terms in the training config and they are not scored here, because each reads a sensor a clip does not carry. Listing them is the honest alternative to a shorter panel that looks complete.")
            }
        }
        if m.rewards.isEmpty && m.unevaluated.isEmpty {
            Section {
                Text("No reward is scored for this motion. Weights belong to a training config, and attaching the wrong one would give every number on this screen an authority it has not earned.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// One measured number.
private struct ReadingRow: View {
    let reading: RunMetrics.Reading

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(reading.label).font(.subheadline)
                Spacer()
                Text(reading.value).font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let detail = reading.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// One of Pollen's reward terms, and what this recording could say about it.
private struct RewardRow: View {
    let term: RunMetrics.RewardTerm

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(term.name).font(.subheadline.monospaced())
                Spacer()
                switch term.standing {
                case .evaluated(let mean, let weighted):
                    Text(String(format: "%.3f × %+.3f = %+.3f", mean, term.weight, weighted))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(weighted < 0 ? .orange : .secondary)
                case .missing:
                    Text("not scored").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(term.purpose).font(.caption).foregroundStyle(.secondary)
            if case .missing(let why) = term.standing {
                Text("Not scored: \(why).").font(.caption).foregroundStyle(.orange)
            }
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
