import Foundation
import DuckKit

/// What to say about a motion somebody else's policy produced.
///
/// THE APP REPLAYS A RECORDING; IT DOES NOT REPRODUCE A CLAIM. For Pollen's
/// nine that distinction rarely bites — this project holds their policies,
/// their training configs and their robot model, so a replay and the original
/// agree. For a contributed file none of that is true: the network arrived on
/// its own, the environment it was trained in is not public, and the only thing
/// that can be checked is that the weights are what they are.
///
/// The `headspin.onnx` case is why this exists as a sentence rather than as a
/// silence. Its owner's render shows the robot balanced vertically on its head.
/// This project's replay puts it belly-up on its torso shell with a leg raised
/// — inverted, held, and not the same posture. Two plant differences are
/// visible from here and neither is fixable: the model this app ships has NO
/// collision geometry on the head, so a balance on the head is not available in
/// it at all, and the actuator in the scene is a position servo where Pollen
/// train against a friction model with lag. Saying "recorded the same way" and
/// stopping there would let a viewer read our replay as a verdict on their
/// policy.
public enum ClipNote {

    /// The line to put under a contributed motion, or nil for one recorded from
    /// a policy this project holds the training config for.
    public static func provenance(for clip: DuckIntentClip) -> String? {
        guard let credit = clip.credit else { return nil }
        return "Contributed — \(credit). This project did not train it and cannot see the "
             + "simulator it was trained in, so what you are watching is our replay of the "
             + "network, not a reproduction of what its owner saw. The pose its actions are "
             + "measured from comes from the file's own declaration, which for this one differs "
             + "from every policy Pollen ship."
    }

    /// The line about what a replay cannot settle, for a contributed motion
    /// whose owner has shown something different.
    ///
    /// Named facts only. "Our physics may differ" is unfalsifiable and tells a
    /// reader nothing; "there is no collision geometry on the head" is a
    /// statement about this model that somebody can go and check.
    public static let plantCaveat =
        "Where a replay and an owner's own render disagree, the model is the first place to "
      + "look rather than the policy. Seven of the fifteen drawn bodies in this model carry no "
      + "collision geometry at all — including every part of the head and neck — so a balance "
      + "on the head is not something this scene can represent, however well the network does it."

    /// Whether that caveat is worth showing: a contributed motion that ends in
    /// a posture the model may not be able to represent.
    public static func needsPlantCaveat(_ clip: DuckIntentClip) -> Bool {
        clip.credit != nil && (clip.endsIn == .inverted || clip.endsIn == .toppled)
    }
}
