import Foundation
import GameController
import StudioKit

/// A real Bluetooth controller, read as `DuckPad` describes it.
///
/// THE SAME PAD THE ROBOT IS DRIVEN WITH. `padd` reads a controller over
/// Bluetooth on the robot; iOS pairs the same hardware — Xbox, DualSense, and
/// anything MFi — through `GameController`. So a Pollen tester with a pad in
/// the drawer can drive the bench with it, using the bindings already in their
/// thumbs, and the on-screen pads become the fallback rather than the only way.
///
/// IT OWNS NO MAPPING. Which button means what is `DuckPad`'s, tested without
/// a controller in the room; this class turns Apple's callbacks into those
/// controls and nothing else.
@MainActor
final class PadReader: ObservableObject {

    /// The pad in hand, if there is one.
    @Published private(set) var name: String?
    /// Sticks, in the same -1...1 shape the on-screen pads produce.
    @Published private(set) var sticks = DuckDrive.Sticks.centred
    /// The last control pressed, so a screen can flash it.
    @Published private(set) var lastPressed: DuckPad.Control?

    /// Called on the press EDGE of a button, never while it is held.
    ///
    /// EDGES, BECAUSE A HELD BUTTON IS ONE INTENT. `padd` makes the same point
    /// about Start — "a held Start must toggle once, not fifty times a second"
    /// — and here a held A would hot-swap the policy on every frame, which is
    /// a request storm at the bench and a duck that never finishes anything.
    var onPress: ((DuckPad.Control) -> Void)?

    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    /// What was down last frame, so only changes are reported.
    private var held: Set<DuckPad.Control> = []

    func begin() {
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.adopt(note.object as? GCController) }
        }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.letGo() }
        }
        // ALREADY-PAIRED PADS ARE THE COMMON CASE. Somebody who connected a
        // controller before opening this screen gets no connect notification,
        // and a screen that only listened for one would tell them there is no
        // pad while they are holding it.
        adopt(GCController.controllers().first)
        GCController.startWirelessControllerDiscovery {}
    }

    func stop() {
        GCController.stopWirelessControllerDiscovery()
        [connectObserver, disconnectObserver].compactMap { $0 }
            .forEach(NotificationCenter.default.removeObserver)
        connectObserver = nil; disconnectObserver = nil
        letGo()
    }

    private func letGo() {
        name = nil
        sticks = .centred
        held = []
    }

    private func adopt(_ controller: GCController?) {
        guard let controller, let pad = controller.extendedGamepad else { return }
        name = controller.vendorName ?? "Controller"
        pad.valueChangedHandler = { [weak self] pad, _ in
            MainActor.assumeIsolated { self?.read(pad) }
        }
        read(pad)
    }

    private func read(_ pad: GCExtendedGamepad) {
        sticks = DuckDrive.Sticks(
            left: .init(x: Double(pad.leftThumbstick.xAxis.value),
                        y: Double(pad.leftThumbstick.yAxis.value)),
            right: .init(x: Double(pad.rightThumbstick.xAxis.value),
                         y: Double(pad.rightThumbstick.yAxis.value)))

        // APPLE'S LETTERS ARE ALREADY THE FACE LETTERS. `buttonA` is the south
        // button on every layout Apple supports, which is the one `padd` calls
        // `Button::South` — so no compass translation is needed here, and doing
        // one would be a second place for the mapping to drift.
        var down: Set<DuckPad.Control> = []
        func note(_ button: GCControllerButtonInput?, _ control: DuckPad.Control) {
            if button?.isPressed == true { down.insert(control) }
        }
        note(pad.buttonA, .a); note(pad.buttonB, .b)
        note(pad.buttonX, .x); note(pad.buttonY, .y)
        note(pad.leftShoulder, .leftBumper); note(pad.rightShoulder, .rightBumper)
        note(pad.leftTrigger, .leftTrigger); note(pad.rightTrigger, .rightTrigger)
        note(pad.dpad.up, .dpadUp); note(pad.dpad.down, .dpadDown)
        note(pad.dpad.left, .dpadLeft); note(pad.dpad.right, .dpadRight)
        note(pad.buttonMenu, .start); note(pad.buttonOptions, .select)

        for control in down.subtracting(held) {
            lastPressed = control
            onPress?(control)
        }
        held = down
    }
}
