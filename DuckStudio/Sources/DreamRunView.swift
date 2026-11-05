import SwiftUI
import CoreGraphics
import StudioKit

/// Where Dream-1's pictures come from: the robot's head camera (`DuckCameraFeed`, mediad's `/frame`)
/// or the simulated duck's (`SimHeadCameraFeed`, drawn on this device).
@MainActor
protocol DreamFrameSource: AnyObject {
    /// The newest picture, at Dream-1's size or any other; nil before the first.
    var latestPicture: CGImage? { get }
    /// The newest pictures as Dream-1 is sent them, oldest first.
    func dreamWindow() -> [String]
    var keepsDreamFrames: Bool { get set }
}

extension DuckCameraFeed: DreamFrameSource {
    var latestPicture: CGImage? { picture }
}

/// Runs Dream-1 on a duck: the robot through its bridge, or the duck in this device's physics.
///
/// THE KEY: this device's (Settings, `DreamDirect`) first, else the robot's computer's (bridge
/// `dream.*`, OpenCastor 3.7). The rows are played through `DreamPilot`, which clamps every step to
/// the sticks' envelope.
@MainActor
final class DreamRunModel: ObservableObject {
    @Published private(set) var models: [DuckDream.Model] = []
    @Published private(set) var key: String?
    @Published private(set) var checked = false
    @Published private(set) var line: String?
    @Published private(set) var running = false
    @Published var chosen: String?
    private var task: Task<Void, Never>?
    private var direct: DreamDirect?
    /// The duck the running pilot drives, so Stop can reach it without waiting on the pilot.
    private var driving: (any DuckPeer)?

    func check(_ peer: any DuckPeer, bridgeAnswersDream: Bool) async {
        do {
            let answer: DuckDream.KeyAnswer
            if let direct = DreamKeyStore.client() {
                self.direct = direct
                answer = try await direct.models()
            } else if bridgeAnswersDream {
                direct = nil
                answer = try DuckDream.readKey(try await peer.call(.dream(.keyCheck)))
            } else {
                direct = nil
                key = nil
                models = []
                line = DuckDream.Words.saveKeyInSettings
                checked = true
                return
            }
            key = answer.key
            models = answer.duckModels
            if chosen == nil || !models.contains(where: { $0.id == chosen }) { chosen = models.first?.id }
            line = models.isEmpty ? DuckDream.Words.noDuckModel : nil
        } catch let refusal as DuckDream.ReadError {
            key = nil
            models = []
            line = refusal.message
        } catch {
            line = error.localizedDescription
        }
        checked = true
    }

    func run(_ peer: any DuckPeer, on duck: DuckIdentity.Kind, source: DreamFrameSource, prompt: String,
             stopDriving: (() async -> Void)?) {
        guard !running, let chosen else { return }
        DuckRuns.shared.makeWay()
        running = true
        line = nil
        lastWalk = nil
        driving = peer
        source.keepsDreamFrames = true
        let pilot = DreamPilot(checkpoint: chosen, prompt: prompt)
        let rows: any DreamRows = direct ?? BridgeDreamRows(peer)
        task = Task { [weak self] in
            await stopDriving?()
            // THE CAP LIVES WITH THE RUN, not only with Play's arbiter, whose tick ends when Play
            // leaves the screen. Close the sheet, tap Moves, and the duck is still capped.
            let caps = ControlArbiter.Caps.standard
            let capped = await caps.enforce(on: duck, stop: { DuckRuns.shared.stop() }) {
                // A first window of pictures before the first ask: the model reads motion, not one frame.
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await pilot.run(on: peer, rows: rows,
                                frames: { await source.dreamWindow() },
                                events: { event in await self?.apply(event) })
            }.capped
            await MainActor.run {
                if capped { self?.line = ControlArbiter.Words.capped(caps.seconds(on: duck)) }
                source.keepsDreamFrames = false
                self?.running = false
                if let token = self?.stopToken { DuckRuns.shared.finished(token); self?.stopToken = nil }
            }
        }
        // A GOAL IS A RUN THE ONE STOP CANCELS: the red disc, the pill on any sheet, Siri later.
        // StopPath has already sent robot.stop by the time this is called.
        let running = task
        stopToken = DuckRuns.shared.track(.goal) { running?.cancel() }
    }

    private var stopToken: StopPath.Token?

    /// Walk to the ball is running, on either duck (its status line says so, not Dream-1's).
    @Published private(set) var walking = false
    /// The line after the last walk, kept on the card until the next one.
    @Published private(set) var lastWalk: BallWalk.LastRun?

    /// Walk to the ball on the practice duck: M1's run, on this device.
    ///
    /// THE SAME PIECES AS M1. `DriverTrial.load` loads the driver, `BallRunStart` lays the start,
    /// `SimHeadCameraFeed` draws, `DreamPilot` plays `LocalDreamRows`, and the one Stop, the Auto cap
    /// and a stick touch all end it through the arbiter and `DuckRuns`, as they end Dream-1.
    /// `stepAside` runs first, so the stick loop and this never write the duck at once.
    /// `seen` gives the screen each state: the stage draws what the driver is doing.
    func walkToBall(_ peer: BenchPeer, feed: SimHeadCameraFeed, folder: String,
                    stepAside: @escaping @MainActor () async -> Void,
                    seen: @escaping @MainActor (DuckDrive.Live) -> Void,
                    walkerOn: @escaping @MainActor () -> Void) {
        guard !running else { return }
        DuckRuns.shared.makeWay()
        running = true
        walking = true
        line = nil
        lastWalk = nil
        ended = nil
        driving = peer
        let start = BallRunStart(seed: UInt64.random(in: 1...(UInt64.max >> 16)))
        let feedWasRunning = feed.running
        task = Task { [weak self] in
            await stepAside()
            var said: String?
            var watched = BallRunWatch()
            var p50: Int?
            do {
                let loaded = try await Task.detached {
                    try DriverTrial.load(folder: folder, decode: { DriverPicture.rgb($0) },
                                         tooHot: { ProcessInfo.processInfo.thermalState == .critical })
                }.value
                // THE LOAD IGNORES CANCEL. A Stop while it ran must not lay the world out after.
                try Task.checkCancellation()
                try await peer.layOut(start)
                walkerOn()
                try Task.checkCancellation()
                feed.stop()
                feed.start(peer)
                feed.keepsDreamFrames = true
                defer { feed.keepsDreamFrames = false }
                var waited = 0.0
                while feed.dreamWindow().count < BallRunStart.picturesFirst {
                    try await Task.sleep(nanoseconds: UInt64(DriverTrial.cameraPeriod * 1e9))
                    waited += DriverTrial.cameraPeriod
                    if waited > BallRunStart.picturesWithin { throw DuckDream.ReadError.refused(BallRunStart.Words.cameraTooSlow) }
                }
                let watcher = Task { @MainActor [weak self] in
                    var watch = BallRunWatch()
                    while !Task.isCancelled {
                        if let now = await peer.live {
                            seen(now)
                            if watch.see(now) { self?.stop(); break }
                        }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                    return watch
                }
                // THE CAP LIVES WITH THE RUN, as Dream-1's does: Play's tick ends with its tab.
                _ = await ControlArbiter.Caps.standard.enforce(on: .sim, stop: { DuckRuns.shared.stop() }) {
                    await DreamPilot(checkpoint: loaded.modelID, prompt: loaded.manifest.task)
                        .run(on: peer, rows: loaded.rows, frames: { await feed.dreamWindow() },
                             events: { event in
                                 await self?.apply(event)
                                 if case .ended(let last) = event { await self?.noteEnd(last) }
                             })
                }
                watcher.cancel()
                watched = await watcher.value
                said = self?.ended
                p50 = await loaded.rows.timings()?.p50
            } catch is CancellationError {
                said = DuckDream.Words.stopped
            } catch let refusal as DuckDream.ReadError {
                said = refusal.message
            } catch let problem as DriverTrial.Problem {
                said = problem.message
            } catch {
                said = Task.isCancelled ? DuckDream.Words.stopped : error.localizedDescription
            }
            if !feedWasRunning { feed.stop() }
            guard let self else { return }
            let walked = watched.line(pilotSaid: said, p50: p50)
            self.lastWalk = BallWalk.LastRun(duck: .sim, line: walked)
            self.line = walked
            self.walking = false
            self.running = false
            if let token = self.stopToken { DuckRuns.shared.finished(token); self.stopToken = nil }
        }
        // THE SAME STOP AS A DREAM-1 RUN: StopPath has already sent robot.stop by the time this runs.
        let running = task
        stopToken = DuckRuns.shared.track(.goal) { running?.cancel() }
    }

    /// Walk to the ball on a real duck: the same pieces as the practice run, and none of its bench.
    ///
    /// NOTHING HERE TOUCHES A WORLD. No reset, no ball, no network load: the driver is loaded as on
    /// the practice duck, its pictures come from the duck's own camera (`DuckCameraFeed`, cut by
    /// `BallWalk.Framing`), and its rows go through `DreamPilot` as ordinary moves. The run is under
    /// the real cap, the one Stop and the foreground rule, and `stepAside` runs first, as for Dream-1.
    ///
    /// READY THE WAY TELL IS. A sitting duck is told what to do, and any other, limp ones included,
    /// gets `robot.init` and `robot.enable` as a Tell walk does. That cannot be skipped, because
    /// nothing says whether a duck is driving, and a limp duck ignores every move without a word.
    ///
    /// THE END IS THE DRIVER'S OWN, OR THE CLOCK'S (`BallWalk.Watch`). Nothing measures the ball, so
    /// the line after a run claims nothing about it.
    func walkToBallReal(_ peer: any DuckPeer, feed: DuckCameraFeed, folder: String,
                        stepAside: @escaping @MainActor () async -> Void) {
        guard !running else { return }
        DuckRuns.shared.makeWay()
        running = true
        walking = true
        line = nil
        lastWalk = nil
        ended = nil
        driving = peer
        task = Task { [weak self] in
            await stepAside()
            let caps = ControlArbiter.Caps.standard
            // THE CAP COVERS THE WHOLE RUN, standing up included, as Play's arbiter counts it.
            let run = await caps.enforce(on: .real, stop: { DuckRuns.shared.stop() }) { () -> (said: String?, p50: Int?) in
                var said: String?
                var p50: Int?
                do {
                    let loaded = try await Task.detached {
                        try DriverTrial.load(folder: folder, decode: { DriverPicture.rgb($0) },
                                             tooHot: { ProcessInfo.processInfo.thermalState == .critical })
                    }.value
                    // A DUCK STILL IN STRIDE COMES TO REST FIRST: `robot.init` takes its balance away.
                    try await Task.sleep(nanoseconds: UInt64(BallWalk.restAfterStop * 1e9))
                    let ready = await DuckOrder.Readiness.ask(peer)
                    if let why = BallWalk.notReady(ready) { throw DuckDream.ReadError.refused(why) }
                    try Task.checkCancellation()
                    switch await DuckOrderRunner.run(.stand, ready: ready, on: peer, stopPath: DuckRuns.shared.path) {
                    case .finished, .handedOff: break
                    case .stopped: throw CancellationError()
                    case .refused(let why): throw DuckDream.ReadError.refused(why)
                    }
                    try await Task.sleep(nanoseconds: UInt64(DuckOrder.settleSeconds * 1e9))
                    feed.beginDriverPictures(fill: BallWalk.fill(loaded.manifest))
                    defer { feed.endDriverPictures() }
                    var waited = 0.0
                    while feed.dreamWindow().count < BallWalk.Pictures.first {
                        try await Task.sleep(nanoseconds: UInt64(DriverTrial.cameraPeriod * 1e9))
                        waited += DriverTrial.cameraPeriod
                        if waited > BallWalk.Pictures.within {
                            throw DuckDream.ReadError.refused(feed.problem ?? BallWalk.Words.cameraTooSlow)
                        }
                    }
                    await DreamPilot(checkpoint: loaded.modelID, prompt: loaded.manifest.task)
                        .run(on: peer, rows: loaded.rows, frames: { await feed.dreamWindow() },
                             events: { event in
                                 await self?.apply(event)
                                 if case .ended(let last) = event { await self?.noteEnd(last) }
                             },
                             watch: BallWalk.pilotWatch(pictureAge: { await feed.dreamPictureAge() }))
                    said = self?.ended
                    p50 = await loaded.rows.timings()?.p50
                } catch is CancellationError {
                    said = DuckDream.Words.stopped
                } catch let refusal as DuckDream.ReadError {
                    said = refusal.message
                } catch let problem as DriverTrial.Problem {
                    said = problem.message
                } catch {
                    said = Task.isCancelled ? DuckDream.Words.stopped : error.localizedDescription
                }
                return (said, p50)
            }
            guard let self else { return }
            let walked = BallWalk.line(pilotSaid: run.result.said, capped: run.capped,
                                       capSeconds: caps.seconds(on: .real), p50: run.result.p50)
            self.lastWalk = BallWalk.LastRun(duck: .real, line: walked)
            self.line = walked
            self.walking = false
            self.running = false
            if let token = self.stopToken { DuckRuns.shared.finished(token); self.stopToken = nil }
        }
        // THE SAME STOP AS EVERY OTHER RUN: StopPath has already sent robot.stop by the time this runs.
        let running = task
        stopToken = DuckRuns.shared.track(.goal) { running?.cancel() }
    }

    private var ended: String?
    private func noteEnd(_ said: String) { ended = said }

    /// Stop on the wire first, then cancel: the duck stops even if the model is mid-answer.
    func stop() {
        if let peer = driving { Task { await DreamPilot.stopNow(peer) } }
        task?.cancel()
    }

    private func apply(_ event: DreamPilot.Event) {
        switch event {
        case .asked: break
        case .played(let rows, let seconds): line = DuckDream.Words.running(rows, seconds)
        case .waiting(let said): line = said
        case .ended(let said): line = said
        }
    }
}

/// Run Dream-1, and record runs to train it: one panel for a real duck and the simulated one.
struct DreamPanel: View {
    let peer: (any DuckPeer)?
    let source: DreamFrameSource
    var bridgeAnswersDream = false
    /// The duck this drives, for its time cap.
    var duck: DuckIdentity.Kind = .real
    var stopDriving: (() async -> Void)?
    @ObservedObject var model: DreamRunModel
    @ObservedObject var recorder: DreamRecorder
    /// Whether a picture is there to send; the source's own published state, passed in.
    var hasPicture: Bool
    @AppStorage("dream.prompt") private var prompt = ""
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.standard)) {
            runSection
            Divider()
            DreamRecordSection(peer: peer, source: source, recorder: recorder, hasPicture: hasPicture)
        }
        .task(id: peer.map { ObjectIdentifier($0) }) {
            if let peer { await model.check(peer, bridgeAnswersDream: bridgeAnswersDream) }
        }
        .confirmationDialog(DuckDream.Words.run, isPresented: $confirming, titleVisibility: .visible) {
            Button(DuckDream.Words.run, role: .destructive) {
                guard let peer else { return }
                model.run(peer, on: duck, source: source, prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                          stopDriving: stopDriving)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DuckDream.Words.howItDrives)
        }
    }

    @ViewBuilder private var runSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            Text(DuckDream.Words.heading).font(.headline)
            if !model.models.isEmpty {
                Picker(DuckDream.Words.model, selection: $model.chosen) {
                    ForEach(model.models) { m in Text(m.label).tag(String?.some(m.id)) }
                }
                .font(.footnote)
                TextField(DuckDream.Words.promptPlaceholder, text: $prompt, axis: .vertical)
                    .font(.callout)
                    .frame(minHeight: DesignMetric.minimumTarget)
                if model.running {
                    Button(DuckDream.Words.stop) { DuckRuns.shared.stop() }
                        .buttonStyle(.primaryAction)
                } else {
                    Button(DuckDream.Words.run) { confirming = true }
                        .buttonStyle(.primaryActionMoves)
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || model.chosen == nil || !hasPicture || recorder.recording)
                }
            }
            if let line = model.line {
                Text(line).font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The key, from the bridge screen: pasted once, checked with Dream Labs by
/// the robot's computer, and kept there. The field empties after a save, so
/// the key is on this screen only while it is being typed.
struct DreamKeySection: View {
    @ObservedObject var robot: BridgeLink
    @State private var typed = ""
    @State private var busy = false
    @State private var said: String?
    @State private var problem: String?

    var body: some View {
        Section {
            Text(DuckDream.Words.whatItIs)
                .font(.footnote).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(DuckDream.Words.keepOnRobot)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField(DuckDream.Words.keyPlaceholder, text: $typed)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
            Button { Task { await save() } } label: {
                HStack(spacing: Theme.spacing(.tight)) {
                    Text(DuckDream.Words.saveKey).frame(maxWidth: .infinity)
                    if busy { ProgressView() }
                }
            }
            .buttonStyle(.primaryAction)
            .disabled(busy || typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let said {
                Text(said).font(.footnote).foregroundStyle(Theme.measured)
                    .fixedSize(horizontal: false, vertical: true)
                Button(DuckDream.Words.clearKey, role: .destructive) { Task { await clear() } }
                    .font(.footnote)
            }
            if let problem {
                Label(problem, systemImage: "xmark.octagon")
                    .font(.footnote).foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: DuckDream.Words.heading)
        }
        .listRowBackground(Theme.surfacePrimary)
        .task { await status() }
    }

    private func status() async {
        guard let peer = robot.peer else { return }
        if let answer = try? DuckDream.readKey(try await peer.call(.dream(.keyCheck))), let key = answer.key {
            said = describe(DuckDream.Words.saved(key), answer)
        }
    }

    private func describe(_ first: String, _ answer: DuckDream.KeyAnswer) -> String {
        answer.duckModels.isEmpty ? first + " " + DuckDream.Words.noDuckModel
            : first + " " + answer.duckModels.map(\.id).joined(separator: ", ")
    }

    private func save() async {
        guard let peer = robot.peer else { return }
        problem = nil
        switch DuckDream.cleaned(typed) {
        case .failure(let why): problem = why.message; return
        case .success(let key):
            busy = true
            defer { busy = false }
            do {
                let answer = try DuckDream.readKey(try await peer.call(.dream(.keySet(key))))
                typed = ""
                said = describe(DuckDream.Words.saved(answer.key ?? DuckDream.hint(key)), answer)
            } catch let refusal as DuckDream.ReadError {
                problem = refusal.message
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func clear() async {
        guard let peer = robot.peer else { return }
        do {
            _ = try DuckDream.readCleared(try await peer.call(.dream(.keyClear)))
            said = nil
        } catch let refusal as DuckDream.ReadError {
            problem = refusal.message
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// The key on this device, from Settings: checked with Dream Labs, then kept in
/// the Keychain. Dream-1 then runs over any link that drives the duck, with
/// nothing about Dream on the robot's computer.
struct DreamKeyHereSection: View {
    @State private var typed = ""
    @State private var busy = false
    @State private var said: String?
    @State private var problem: String?
    @State private var saved = DreamKeyStore.load() != nil

    var body: some View {
        Section {
            SecureField(DuckDream.Words.keyPlaceholder, text: $typed)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
            Button { Task { await save() } } label: {
                Label(busy ? "Checking…" : DuckDream.Words.saveKey, systemImage: "key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .disabled(busy || typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if saved {
                Button(role: .destructive) {
                    DreamKeyStore.clear(); saved = false; said = nil
                } label: {
                    Text(DuckDream.Words.removeHere).foregroundStyle(Theme.critical)
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
            SectionHeading(text: DuckDream.Words.heading)
        } footer: {
            Text(DuckDream.Words.whatItIsHere).foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
        .task {
            if let key = DreamKeyStore.load() { said = DuckDream.Words.savedHere(DuckDream.hint(key)) }
        }
    }

    private func save() async {
        problem = nil
        switch DuckDream.cleaned(typed) {
        case .failure(let why): problem = why.message
        case .success(let key):
            busy = true
            defer { busy = false }
            do {
                // CHECKED BEFORE IT IS KEPT. A key Dream Labs refuses is not saved.
                let answer = try await DreamDirect(key: key, version: DreamKeyStore.version).models()
                DreamKeyStore.save(key)
                typed = ""
                saved = true
                let first = DuckDream.Words.savedHere(DuckDream.hint(key))
                said = answer.duckModels.isEmpty ? first + " " + DuckDream.Words.noDuckModel
                    : first + " " + answer.duckModels.map(\.id).joined(separator: ", ")
            } catch let refusal as DuckDream.ReadError {
                problem = refusal.message
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
