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
    func run(_ order: DuckOrder, ready: DuckOrder.Readiness = .unknown) async -> DuckOrderRunner.Ended {
        guard let peer else {
            caption = ControllerWords.tellNoDuck
            return .refused(ControllerWords.tellNoDuck)
        }
        return await run(order, on: peer, ready: ready)
    }

    /// Run one order on a named duck: the welcome sheet's quack and Stand up go to the duck just
    /// connected, before Play has switched to it. Registered like any run, so the Stop pill shows
    /// and stops it.
    func run(_ order: DuckOrder, on peer: any DuckPeer,
             ready: DuckOrder.Readiness = .unknown) async -> DuckOrderRunner.Ended {
        path.rearm()
        let path = self.path
        let work = Task { () -> DuckOrderRunner.Ended in
            await DuckOrderRunner.run(order, ready: ready, on: peer, stopPath: path,
                                      said: { line in await MainActor.run { DuckRuns.shared.say(line) } })
        }
        // A NAMED DUCK THAT IS NOT PLAY'S GETS ITS OWN robot.stop. StopPath writes robot.stop to
        // the attached peer only, which during the welcome is still Play's duck (often the
        // practice one), so the duck actually standing up would never be told. The stop goes on
        // its way before the run is cancelled, and nothing waits for it.
        let separate = peer !== self.peer
        let token = track(.command) {
            if separate { Task.detached(priority: .high) { _ = try? await peer.call(.stop) } }
            work.cancel()
        }
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
            if runs.isRunning {
                Button { runs.stop() } label: {
                    Label(ControllerWords.stopPill, systemImage: "stop.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.spacing(.standard))
                        .frame(minHeight: StopMetric.pillHeight)
                        .background(StopMetric.red, in: Capsule())
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
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(ControllerWords.stop))
        .accessibilityHint(Text(ControllerWords.stopHint))
        .accessibilitySortPriority(2)
    }
}

enum StopMetric {
    /// Red is Stop and nothing else.
    static let red = Color(red: 0.86, green: 0.12, blue: 0.12)
    static let disc: CGFloat = 56
    static let pillHeight: CGFloat = 48
}
