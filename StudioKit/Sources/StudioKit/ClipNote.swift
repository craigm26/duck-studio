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
/// silence — and why the sentence has been rewritten once already. Its owner's
/// render shows the robot balanced vertically on its head. The first version of
/// this caveat blamed the model: "no collision geometry on the head". That was
/// FALSE — the scene compiles Pollen's own `robot_allcollisions.xml`
/// byte-identical, and the head carries three collision meshes (top shell, jaw,
/// bottom shell). Measured instead: PLACED into the headstand, this network
/// holds it for the whole clip, on jaw contact, every seed tried; started
/// standing, it never mounts under any command tried. The balance was trained;
/// the entry, on this plant, was not — and the contributor's own training
/// environment is private, so which initial states it saw cannot be checked.
public enum ClipNote {

    /// The line to put under a contributed motion, or nil for one recorded from
    /// a policy this project holds the training config for.
    public static func provenance(for clip: DuckIntentClip) -> String? {
        guard let credit = clip.credit else { return nil }
        // A CREDIT IS NOT A CONTRIBUTION. This fired on ANY non-nil credit and
        // called the clip "Contributed", with a paragraph about not being able
        // to see the owner's simulator. That was true of the one case it was
        // written for — a motion somebody else trained and sent — and became
        // false the moment `DuckBench.recordedCredit` started stamping the
        // plant onto clips recorded on the person's OWN bench. A recording
        // made here, in a world this app can name and digest, is the opposite
        // of unverifiable, and captioning it "This project did not train it"
        // is a sentence about somebody who does not exist.
        guard !DuckBench.wasRecordedHere(credit) else { return credit }
        return "Contributed — \(credit). This project did not train it and cannot see the "
             + "simulator it was trained in, so what you are watching is our replay of the "
             + "network, not a reproduction of what its owner saw. The pose its actions are "
             + "measured from comes from the file's own declaration, which for this one differs "
             + "from every policy Pollen ship."
    }

    /// The line about what a replay cannot settle, for a contributed motion
    /// whose owner has shown something different.
    ///
    /// Named, MEASURED facts only — the first version of this string named a
    /// checkable fact that was false ("no collision geometry on the head"; the
    /// head has three collision meshes), which is worse than vagueness because
    /// a checkable falsehood survives until somebody actually checks.
    public static let plantCaveat =
        "Where this replay and the owner's render disagree, the difference is in how the "
      + "motion STARTS, not in whether the balance is possible: placed into the headstand, "
      + "this network holds it — every seed tried, balanced on the jaw — and started standing "
      + "it never mounts under any command tried. The balance was trained; the entry, in this "
      + "simulator, was not, and the owner's training environment is not public, so which "
      + "starting states it saw cannot be checked. The physics here is Pollen's own "
      + "full-collision robot model; the one knowingly simplified part is the actuator, a "
      + "position servo standing in for the friction-and-lag motor model they train against."

    /// Whether that caveat is worth showing: a contributed motion that ends in
    /// a posture the model may not be able to represent.
    public static func needsPlantCaveat(_ clip: DuckIntentClip) -> Bool {
        clip.credit != nil && (clip.endsIn == .inverted || clip.endsIn == .toppled)
    }
}
