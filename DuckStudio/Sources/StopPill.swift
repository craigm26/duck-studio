import SwiftUI
import StudioKit

/// What is running on the duck right now, for every screen, and the one Stop they all press.
///
/// A THIN, OBSERVABLE FRONT ON `StopPath.shared`. StopPath is the kit's deterministic stop (robot.stop
/// first, then the latch, then every registered run cancelled, nothing awaited); it is not
/// observable, so the pill on Moves, on Studio and on every sheet could not know when to show.
/// This publishes what StopPath holds and adds nothing to the order a stop takes.
///
/// THE DUCK A STOP GOES TO IS THE ONE PLAY IS ON. The controller attaches its peer whenever the
/// venue or the link changes, so a Stop pressed on Studio reaches the duck the person last drove.
@MainActor
final class DuckRuns: ObservableObject {
    static let shared = DuckRuns()

    /// The runs a Stop would cancel now.
    @Published private(set) var running: [StopPath.RunKind] = []
    /// The last thing a run or a stop said.
    @Published private(set) var caption: String?
    /// Bumped on every stop, so the controller can put its own stick and loop back as well.
    @Published private(set) var stops = 0
    /// The kind of duck attached, or nil when there is none.
    @Published private(set) var duck: DuckIdentity.Kind?

    let path: StopPath
    private(set) var peer: (any DuckPeer)?

    init(path: StopPath = .shared) { self.path = path }

    var isRunning: Bool { !running.isEmpty }

    /// Play's own drive loop (the sticks, a sequence replay) is moving the duck. It is not a
    /// registered run, so without this a sheet opened over Play while the duck walks shows no
    /// Stop at all. Play stops its loop when `stops` moves.
    @Published var playIsDriving = false

    /// Whether the pill shows: any registered run, or Play's loop.
    var showsStop: Bool { isRunning || playIsDriving }

    /// One order started outside Play's panels (Siri, a Shortcut, a Moves tile), while it runs.
    /// Play watches this and books it with its `ControlArbiter`, so Take over covers it as it
    /// covers a Tell order; the cap is `runOrder`'s own, so it holds with Play off screen (build 93).
    struct OutsideOrder: Equatable {
        let id: UUID
        let duck: DuckIdentity.Kind
        let owner: ControlArbiter.Owner
        /// The order's name, for Auto's status line.
        let what: String
    }
    @Published private(set) var outsideOrder: OutsideOrder?

    /// Run one order from Siri, a Moves tile or a real duck's face button: whatever was moving the
    /// duck is stopped first, Play is told so its arbiter books the run, and the order runs like
    /// any other, under the duck's time cap.
    func runOrder(_ order: DuckOrder, owner: ControlArbiter.Owner) async -> DuckOrderRunner.Ended {
        makeWay()
        guard let duck else { return await run(order) }
        let mine = OutsideOrder(id: UUID(), duck: duck, owner: owner,
                                what: DuckDecider.chip(for: order).title)
        outsideOrder = mine
        defer { if outsideOrder == mine { outsideOrder = nil } }
        let caps = ControlArbiter.Caps.standard
        let ended = await caps.enforce(on: duck, stop: { [weak self] in self?.stop() }) { await run(order) }
        if ended.capped { caption = ControlArbiter.Words.capped(caps.seconds(on: duck)) }
        return ended.result
    }

    /// A person's own tap starts something new: whatever was moving the duck stops first, so two
    /// runs never share it, and the latch opens for the person who asked.
    func makeWay() {
        if playIsDriving || isRunning {
            stop()
            // That stop made way for the new run. Its "Stopped." is not what the new run ended with.
            caption = nil
        }
        path.rearm()
    }

    /// The duck Stop and the Moves tiles go to.
    func attach(_ peer: (any DuckPeer)?, kind: DuckIdentity.Kind?) {
        self.peer = peer
        duck = peer == nil ? nil : kind
        path.attach(peer)
    }

    /// Register a run; Stop cancels it.
    @discardableResult
    func track(_ kind: StopPath.RunKind, cancel: @escaping @Sendable () -> Void) -> StopPath.Token {
        let token = path.register(kind, cancel: cancel)
        refresh()
        return token
    }

    /// Register a run on a named duck.
    ///
    /// A NAMED DUCK THAT IS NOT PLAY'S GETS ITS OWN robot.stop. StopPath writes robot.stop to the
    /// attached peer only, which may be another duck (the practice one, during the welcome, or
    /// while a plan runs on the robot), so the duck actually moving would never be told. The stop
    /// goes on its way before the run is cancelled, and nothing waits for it.
    @discardableResult
    func track(_ kind: StopPath.RunKind, on duck: any DuckPeer,
               cancel: @escaping @Sendable () -> Void) -> StopPath.Token {
        let separate = duck !== peer
        return track(kind) {
            if separate { Task.detached(priority: .high) { _ = try? await duck.call(.stop) } }
            cancel()
        }
    }

    func finished(_ token: StopPath.Token) {
        path.finished(token)
        refresh()
    }

    /// THE ONE STOP. Synchronous: no surface can put an await in front of it.
    @discardableResult
    func stop() -> String {
        let pressed = path.stop()
        caption = pressed.caption
        stops += 1
        refresh()
        Haptic.stopRequested()
        return pressed.caption
    }

    /// Leaving the foreground ends every chain, plan and goal (the plan's "Leaving the
    /// foreground"). Nothing here holds a Live Activity yet, so there is no exception.
    func leftForeground() {
        guard !path.registered.isEmpty else { return }
        stop()
        caption = ControlArbiter.Words.leftForeground
    }

    func say(_ line: String?) { caption = line }

    /// Run one order on the attached duck. Only a person's own tap or sentence calls this, so it
    /// re-opens the stop latch first: a model, a bridge or a reconnect never does.
    ///
    /// THE DUCK IS ASKED HOW IT STANDS FIRST (build 92). The practice duck's answer is fixed
    /// (`Readiness.practiceDuck`); a real duck is asked `robot.policies`, so Sit knows whether it
    /// is sitting and a standing duck is not re-homed before every walk. An order this duck
    /// cannot do is refused in a sentence before anything is sent.
    func run(_ order: DuckOrder) async -> DuckOrderRunner.Ended {
        guard let peer else {
            caption = ControllerWords.tellNoDuck
            return .refused(ControllerWords.tellNoDuck)
        }
        if let duck, let why = order.notOn(duck) {
            caption = why
            return .refused(why)
        }
        // THE WAIT FOR THE ANSWER IS PART OF THE RUN (build 93). The latch opens before it, not
        // after, and the wait is registered, so a Stop pressed while the duck answers ends the run
        // instead of being undone by a re-arm that comes later.
        path.rearm()
        let asking = Task { @MainActor in await self.readiness(of: peer) }
        let token = track(.command, on: peer) { asking.cancel() }
        let ready = await asking.value
        finished(token)
        guard path.admits, !asking.isCancelled else { return .stopped }
        return await play(order, on: peer, ready: ready)
    }

    /// How the attached duck stands, as it says so.
    func readiness(of peer: any DuckPeer) async -> DuckOrder.Readiness {
        duck == .sim ? .practiceDuck : await DuckOrder.Readiness.ask(peer)
    }

    /// Run a short plan of orders, one at a time, as ONE run: one Stop ends all of it.
    ///
    /// THE LATCH IS RE-OPENED ONCE, at the start, for the person who asked. Every later step goes
    /// through `DuckOrderRunner` directly, which checks the latch before each wire write, so a
    /// Stop between steps ends the plan instead of being undone by the next step. The duck is
    /// asked how it stands before every step, because a stand or a sit changes the answer.
    func runPlan(_ orders: [DuckOrder], step: @escaping (Int) -> Void) async -> DuckOrderRunner.Ended {
        guard let peer else {
            caption = ControllerWords.tellNoDuck
            return .refused(ControllerWords.tellNoDuck)
        }
        if let duck, let why = orders.lazy.compactMap({ $0.notOn(duck) }).first {
            caption = why
            return .refused(why)
        }
        path.rearm()
        let path = self.path
        let work = Task { @MainActor () -> DuckOrderRunner.Ended in
            for (i, order) in orders.enumerated() {
                guard path.admits, !Task.isCancelled else { return .stopped }
                step(i)
                let ready = await self.readiness(of: peer)
                let ended = await DuckOrderRunner.run(order, ready: ready, on: peer, stopPath: path,
                                                      said: { line in await MainActor.run { DuckRuns.shared.say(line) } })
                switch ended {
                case .finished: continue
                default: return ended
                }
            }
            return .finished
        }
        let token = track(.command) { work.cancel() }
        let ended = await work.value
        finished(token)
        switch ended {
        case .finished: caption = DuckDecider.Words.done
        case .stopped: break
        case .refused(let why): caption = why
        case .handedOff: break
        }
        return ended
    }

    /// Run one order on a named duck: the welcome sheet's quack and Stand up go to the duck just
    /// connected, before Play has switched to it. Registered like any run, so the Stop pill shows
    /// and stops it.
    func run(_ order: DuckOrder, on peer: any DuckPeer,
             ready: DuckOrder.Readiness = .unknown) async -> DuckOrderRunner.Ended {
        path.rearm()
        return await play(order, on: peer, ready: ready)
    }

    /// Run one order with the latch already open.
    private func play(_ order: DuckOrder, on peer: any DuckPeer,
                      ready: DuckOrder.Readiness) async -> DuckOrderRunner.Ended {
        let path = self.path
        let work = Task { () -> DuckOrderRunner.Ended in
            await DuckOrderRunner.run(order, ready: ready, on: peer, stopPath: path,
                                      said: { line in await MainActor.run { DuckRuns.shared.say(line) } })
        }
        let token = track(.command, on: peer) { work.cancel() }
        let ended = await work.value
        finished(token)
        switch ended {
        case .finished: if caption == nil { caption = ControllerWords.tellDone }
        case .stopped: break
        case .refused(let why): caption = why
        case .handedOff: break
        }
        return ended
    }

    private func refresh() { running = path.registered }
}

/// The floating red Stop pill: on Moves, on Studio and on top of every sheet, while anything runs.
///
/// ONE MODIFIER, so no sheet can grow its own stop that forgets a step. Play draws the solid
/// disc instead and does not need this.
struct StopPillModifier: ViewModifier {
    @ObservedObject private var runs = DuckRuns.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if runs.showsStop {
                Button { runs.stop() } label: {
                    Label(ControllerWords.stopPill, systemImage: "stop.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.spacing(.standard))
                        .frame(minHeight: StopMetric.pillHeight)
                        .background(StopMetric.red, in: Capsule())
                        // Pond Day: the same 2pt ink outline every filled
                        // control wears, so the pill holds its edge on a light
                        // sheet as well as a dark one.
                        .overlay(Capsule().strokeBorder(Theme.outline,
                                                        lineWidth: DesignMetric.outlineStroke))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(ControllerWords.stopHint))
                .padding(.bottom, Theme.spacing(.standard))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

extension View {
    /// The floating Stop pill, shown while anything runs on the duck.
    func stopPill() -> some View { modifier(StopPillModifier()) }
}

/// The solid red Stop disc on Play. Never glass: legibility cannot depend on a tint.
struct StopDisc: View {
    var size: CGFloat = StopMetric.disc
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(StopMetric.red, in: Circle())
                // A 3pt white ring inside a 2pt ink outline: the ring carries
                // the disc on the dark floor (red is 2.00:1 there), the ink
                // carries it on the light page.
                .overlay(Circle().strokeBorder(.white, lineWidth: 3)
                    .padding(DesignMetric.outlineStroke))
                .overlay(Circle().strokeBorder(Theme.outline,
                                               lineWidth: DesignMetric.outlineStroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(ControllerWords.stop))
        .accessibilityHint(Text(ControllerWords.stopHint))
        .accessibilitySortPriority(2)
    }
}

enum StopMetric {
    /// Red is Stop and nothing else: `Palette`'s `stop` token, #D92A2A in
    /// both schemes. The only place the app names it.
    static let red = Theme.stop
    static let disc: CGFloat = 56
    static let pillHeight: CGFloat = 48
}
