import Foundation

/// The sentences on the Behaviours tab and a behaviour's own screen.
///
/// ONE LINE ON THE SCREEN, THE REST UNDER EVERYTHING. These rows and footers
/// grew a paragraph each, and a person picking a move met all of them at once.
/// Each place now says one line; the honest detail it used to say in full is
/// kept as a `…Note` that the app shows only when Settings → Detail is on
/// Everything (`DetailLevel.Surface.notes`). `BehavioursWordsTests` holds the
/// lines to one sentence and the notes to the caveats they exist to carry.
public enum BehavioursWords {

    // MARK: - Discover's doors

    public static let pollenDoor = "Releases that ship with the robot, plus anything newer"
    public static let communityDoor = "Networks other people trained and shared on Hugging Face"
    public static let challengesDoor = "Score a move over many tries, in simulation"

    /// The empty library's second way in, beside Pollen's catalogue.
    public static let browseCommunity = "Browse community behaviours"

    // MARK: - Retrain

    public static let retrainLine =
        "Describe a move and Draft turns it into a checked training request."

    public static let retrainNote =
        "Draft refuses what the robot's own physics rules out, in a second rather than after a "
      + "day of training. Nothing here keeps a request: it lives on the card that wrote it, and "
      + "travels as a file you send to a machine that has Python, mjlab and a GPU."

    // MARK: - a behaviour's actions

    public static let nothingRecordedLine =
        "Nothing recorded from this network yet. Run it on a bench to watch it move."

    public static var nothingRecordedNote: String {
        "A preview cannot play a policy; watching one move means running it on a bench, and "
      + "\(DeviceWords.current.this) is one. Keep the recording and it comes back under Studio → "
      + "Motions, in \"Brought in\". Probe hands the network one observation and shows the "
      + "fourteen numbers it answers with, with no bench at all, but a network has no time axis, "
      + "so nothing plays there either."
    }

    public static let recordedLine =
        "Watch it move plays a recording of this network driving a robot in physics."

    public static let recordedNote =
        "It shows what the network did, not what somebody asked for. Probe hands it one "
      + "observation and shows the fourteen numbers it answers with; nothing plays there, "
      + "because a network has no time axis. Run it on a bench to record it again under your "
      + "own commands, on your own floor."

    // MARK: - what Simple holds back on this screen

    /// One line naming every section Simple hid on a screen, in place of one
    /// placeholder per section. Nil when nothing is hidden.
    public static func hiddenLine(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let it = names.count == 1 ? "it" : "them"
        return "Hidden in Simple: " + names.joined(separator: ", ")
             + ". Settings → Detail shows \(it)."
    }
}
