import GameController
import StudioKit

/// A paired Bluetooth controller, read as held state each engine tick.
///
/// POLLED, NOT EVENT-DRIVEN, because the engine wants held state: "is sprint
/// down right now" is a poll, and wiring valueChangedHandlers into published
/// state would rebuild half the referee for what a read-per-tick answers in
/// four lines. The FIFA mapping, because that is the muscle memory every
/// football player brings: A/✕ pass, B/○ shoot, Y/△ the skill move, L1
/// switch player, R2 sprint. The left stick steers in FIELD space — up is
/// always toward the CPU goal, same as the on-screen stick.
@MainActor
final class GamepadInput {

    static let shared = GamepadInput()
    private init() {}

    var isConnected: Bool { GCController.controllers().first?.extendedGamepad != nil }

    /// L1 fires once per press, so switching player is a tap, not a hold —
    /// this remembers the previous poll's state to find the edge.
    private var switchWasDown = false

    struct Snapshot {
        var control = DuckSoccer.Control()
        var switchPressed = false
    }

    /// The controller's current held state, or nil when none is paired —
    /// the caller falls back to the touch controls.
    func poll() -> Snapshot? {
        guard let pad = GCController.controllers().first?.extendedGamepad else {
            switchWasDown = false
            return nil
        }
        var snapshot = Snapshot()
        let x = Double(pad.leftThumbstick.xAxis.value)
        let y = Double(pad.leftThumbstick.yAxis.value)
        // Stick up = pitch +x (toward the CPU goal); stick right = pitch −y.
        snapshot.control.stick = DuckSoccer.Vec2(y, -x)
        snapshot.control.pass = pad.buttonA.isPressed
        snapshot.control.kick = pad.buttonB.isPressed
        snapshot.control.special = pad.buttonY.isPressed
        snapshot.control.sprint = pad.rightTrigger.value > 0.3
            || pad.rightShoulder.isPressed

        let switchDown = pad.leftShoulder.isPressed
        snapshot.switchPressed = switchDown && !switchWasDown
        switchWasDown = switchDown
        return snapshot
    }
}
