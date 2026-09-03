import Foundation

/// The two things the Control tab reaches for that live in Studio: a MOTION
/// somebody authored, and a SCENE somebody built.
///
/// WHY THEY BELONG ON THIS TAB AT ALL. Studio is where a motion is written and
/// a scene is arranged; Control is where a duck is standing in a room with a
/// thumb on a stick. Until now, running an authored motion meant leaving the
/// duck, going to Studio, finding the draft and pressing Run; and putting a
/// saved scene under the duck meant opening the drawer and finding it in a
/// picker of nineteen rows. Both are one tap from the picture now, and neither
/// of them is a new way to run anything: the motion goes through
/// `BenchRoute.of(draft:scene:)` exactly as the pipeline screen's Run does, and
/// the scene goes through `DuckWorld.plan(for:)` exactly as the world picker's
/// rows do. What is new is the door, not the engine.
///
/// A MOTION IS NOT A LIVE COMMAND, AND THIS FILE SAYS SO OUT LOUD. The live
/// lane carries one thing — a velocity twist — and an authored motion is a
/// track of joint angles that a bench runs in a batch and answers with what
/// happened. So running one from here STOPS THE DRIVE LOOP, runs it, and hands
/// the sticks back. Anything else would be a screen pretending a batch call is
/// a steering command.
public enum ControlShelf {

    // MARK: - the chips

    public static let sceneChip = "Scene"
    /// The button on a motion's row, and the heading its answer lands under.
    public static let runItHere = "Run it here"
    public static let whatHappened = "What happened"
    public static let motionsChip = "Motions"

    /// The scene chip's second line: what is standing right now. The world's
    /// own name when it has one, and the bench's own world when nothing has
    /// been set — never a guess about a bench that has not answered.
    public static func standingSaid(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "The bench's own world" }
        return name
    }

    // MARK: - what the two sheets promise

    public static let sceneSheetSaid =
        "Every scene this phone holds, and the three challenge flights, laid on the bench you "
      + "are driving. Picking one posts it and reads back what actually stood — the same door "
      + "the world picker under the controls opens, one tap from the picture."

    public static let motionSheetSaid =
        "Every motion in Studio, run on the bench you are driving. A motion is a track of joint "
      + "angles rather than a steering command, so running one stops the drive loop, runs it "
      + "once, and hands the sticks back."

    /// The one fact a person needs before they press Run, and it is the fact
    /// build 47's `/perform` established: a batch run lays its OWN room out of
    /// the motion's scene, and the world the live lane is standing in is not
    /// touched by it. Saying this is what stops "run it here" reading as "run
    /// it in what I can see".
    public static let runsInItsOwnRoom =
        "A motion runs in the room it was authored in: the bench lays that room, runs the track "
      + "once, and answers with what happened. The world you are driving in is left standing."

    /// Above the Run button, every time. A person who has just watched a duck
    /// walk under their thumb is about to press something that takes the duck
    /// away for a few seconds, and the screen says so before it happens rather
    /// than afterwards.
    public static let runningStopsTheDrive =
        "Running this stops driving. The duck is put back on its feet, the motion runs once on "
      + "the bench, and the sticks come back when it is done."

    public static func running(_ name: String) -> String {
        "Running \(name) on the bench…"
    }

    /// The room this motion will lay, named, so a person can set it as the
    /// world afterwards if they want to drive in it. NOT A REFUSAL: the run
    /// happens either way.
    public static func authoredIn(_ scene: String) -> String {
        "Authored in \(scene), and that is the room it will lay for the run."
    }

    /// A motion with no scene: it was authored on a bare floor, so the room it
    /// lays is a bare floor.
    public static let authoredAnywhere =
        "Authored on a bare floor, so a bare floor is the room it will lay."

    /// Studio holds nothing yet. A door to an empty room says why it is empty.
    public static let noMotionsYet =
        "No motions yet. A motion is a track of poses you write in Studio — record one from a "
      + "bench, or author one on the timeline — and every one of them turns up here."

    /// Nothing in this app can put a motion on a pad button yet, said where
    /// somebody would look for it.
    public static let notOnAButtonYet =
        "A motion cannot go on a pad button yet. A button press is answered inside one round "
      + "trip of the drive loop and a motion is a batch run that takes seconds, so it needs a "
      + "door that can say \"this is running\" and hand the sticks back. Run it from here."

    /// Everything this type says, so a screen can be checked against it.
    public static let everySentence: [String] = [
        sceneChip, motionsChip, runItHere, whatHappened, sceneSheetSaid, motionSheetSaid, runsInItsOwnRoom,
        runningStopsTheDrive, authoredAnywhere, noMotionsYet, notOnAButtonYet,
    ]
}
