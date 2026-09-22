import Foundation

/// What the app says to somebody opening it for the first time.
///
/// THE FIRST THING IT HAS TO ADMIT IS THAT THEY PROBABLY HAVE NO DUCK. Pollen's
/// first Microduck deliveries are around Christmas 2026. An app that opens with
/// "pair your robot" is an app that fails for every person who has it, and
/// there is no honest way to hide that behind an illustration of a robot. So
/// the opening line says it, and then says what works anyway — which turns out
/// to be nearly everything, because every motion in here was recorded in
/// physics on a bigger machine and replays without hardware.
///
/// IT ENDS BY ASKING HOW MUCH TO SHOW. The two audiences want different first
/// screens and neither is the default for the other, so rather than guessing
/// from behaviour the app asks once, in one sentence per option, and never
/// again. `DetailLevel.installedDefault` covers anybody who skips.
public enum FirstRun {

    /// One thing worth knowing, in the order a person needs it.
    public struct Step: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let body: String
        /// The tab it is talking about, when it is talking about one.
        public let tab: String?

        public init(id: String, title: String, body: String, tab: String? = nil) {
            self.id = id; self.title = title; self.body = body; self.tab = tab
        }
    }

    /// Kept in one place so the copy is testable and cannot drift from what the
    /// app can actually do.
    public static let steps: [Step] = [
        .init(id: "no-duck",
              title: "You probably do not have a Microduck yet",
              body: "Pollen's first deliveries are around Christmas 2026. Nearly "
                  + "everything here works without one: every motion in the app was "
                  + "recorded in MuJoCo on a bigger machine, and it replays on a "
                  + "drawing of the robot at true scale.",
              tab: nil),
        .init(id: "watch",
              title: "Start by watching one move",
              body: "Behaviours holds the policies Pollen trained and the motions "
                  + "they produced. Open one and play it. The duck you are looking "
                  + "at is 25 cm tall, standing on a floor drawn to the same scale.",
              tab: "Behaviours"),
        .init(id: "make",
              title: "Then make one of your own",
              body: "Studio → Draft turns a sentence into keyframes you can fix by "
                  + "hand, or pose the robot joint by joint. What the stage draws is "
                  + "what you ASKED for — a phone has no physics engine, so it is "
                  + "never a promise about what the robot would do.",
              tab: "Studio"),
        .init(id: "play",
              title: "There are modes to play in",
              body: "Studio → Modes: soccer on your carpet, a ghost duck at true "
                  + "scale, a room you scan yourself. The ones that need a robot on "
                  + "the floor are not listed until there is one.",
              tab: "Studio"),
        .init(id: "arrives",
              title: "When yours arrives",
              body: "Control drives it — sticks, a pad of your own motions, and a "
                  + "camera that reads your pose onto the duck. Until then it drives "
                  + "the drawing, which behaves the same except for being weightless.",
              tab: "Control"),
    ]

    /// The question the last card asks, with the two answers.
    public static let detailQuestion =
        "How much of the app do you want in front of you?"

    /// Why it is asked at all, in a sentence under the question.
    public static let detailWhy =
        "Microduck Studio started as a tool for people who train these networks and "
        + "grew into one for people who own the robot. Neither is the default for the "
        + "other, so it asks once. Settings → Detail changes it any time."

    /// Whether the app should offer this. `false` once somebody has seen it,
    /// whichever way they left.
    public static func shouldShow(seenVersion: Int?) -> Bool {
        (seenVersion ?? 0) < currentVersion
    }

    /// Bumping this shows the run again after a release that changes what the
    /// steps say. It is a number rather than a Bool so a future change can
    /// re-introduce it without resetting anybody's detail choice.
    public static let currentVersion = 1
}
