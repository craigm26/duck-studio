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
    ///
    /// THE FIRST CARD SAYS WHOSE APP THIS IS NOT. Pollen Robotics are building
    /// the official Microduck app and asked that this one not be mistaken for
    /// it (pollen-robotics/microduck#329). Somebody opening an app named after
    /// the robot is exactly the person who would assume otherwise, and the
    /// first screen is the one screen every one of them sees. The view draws
    /// `Provenance.links` under it.
    public static let steps: [Step] = [
        .init(id: "not-official",
              title: Provenance.notOfficialTitle,
              body: Provenance.independence,
              tab: nil),
        .init(id: "play",
              title: "Start by playing",
              body: "Pollen's first Microducks ship around Christmas 2026, and everything here "
                  + "works without one: Play drives a duck drawn at true scale, in real physics, "
                  + "right on this phone.",
              tab: "Play"),
        .init(id: "learn",
              title: "Learn the rest when you want to",
              body: "Learn walks from driving, to how Pollen trains a move, to making and "
                  + "measuring your own. A preview runs no physics: it shows what you ASKED for.",
              tab: "Learn"),
    ]

    /// Whether the app should offer this. `false` once somebody has seen it,
    /// whichever way they left.
    public static func shouldShow(seenVersion: Int?) -> Bool {
        (seenVersion ?? 0) < currentVersion
    }

    /// Bumping this shows the run again after a release that changes what the
    /// steps say. It is a number rather than a Bool so a future change can
    /// re-introduce it without resetting anybody's detail choice.
    ///
    /// 2: the "not the official app" card, shown once to everybody who saw
    /// version 1 without it.
    ///
    /// 3: three cards for the Play / Learn layout, and no detail question
    /// (a new install starts Simple; Learn's last lesson is the way out).
    public static let currentVersion = 3
}
