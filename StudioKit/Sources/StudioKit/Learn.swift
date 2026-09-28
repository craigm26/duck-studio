import Foundation

/// The Learn tab: a short path from driving the duck to changing how it moves.
///
/// ONE LESSON, ONE IDEA, ONE BUTTON. The app grew a screen for every tool and
/// a paragraph under every screen, and a new owner met all of it at once. The
/// path puts the tools in the order a person can use them: drive it, play its
/// moves, see what a trained network is, learn how Pollen trains one, then make
/// and measure moves of your own. Each lesson is two sentences and a button
/// that opens the real screen, so the lesson never describes a tool the app
/// cannot open.
///
/// THE LAST LESSON TURNS EVERYTHING ON. Simple is the default for a new
/// install, and this path is how somebody leaves it when they are ready,
/// rather than by finding a setting.
public enum Learn {

    /// Where a lesson's button goes. The app maps each case to a tab or a
    /// screen; the kit only names them.
    public enum Go: String, Sendable, CaseIterable {
        case play, behaviours, preference, motions, challenges, tune, shoot, everything
    }

    public struct Lesson: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let body: String
        public let symbol: String
        /// The button's words, and where it goes. Nil for a lesson that is
        /// only something to read.
        public let button: String?
        public let go: Go?
    }

    public static let title = "Learn"

    public static let intro =
        "From driving to training, one step at a time"

    public static let lessons: [Lesson] = [
        .init(id: "drive",
              title: "Drive it",
              body: "Push the left stick to walk and the right one to turn. Stop freezes the duck; "
                  + "Reset stands it back up.",
              symbol: "gamecontroller", button: "Open Play", go: .play),
        .init(id: "moves",
              title: "Play a move",
              body: "The buttons between the sticks play moves Pollen trained, like a roll and a "
                  + "pick-up; more are in the drawer. Each one swaps in a different network.",
              symbol: "figure.roll", button: "Open Play", go: .play),
        .init(id: "networks",
              title: "Every move is a network",
              body: "Behaviours lists the trained networks on this phone. Open one and play a "
                  + "recording of what it did in physics.",
              symbol: "brain.head.profile", button: "Open Behaviours", go: .behaviours),
        .init(id: "training",
              title: "How Microduck learns",
              body: "Pollen trains each move by reinforcement learning in mjlab, a MuJoCo "
                  + "simulator: thousands of simulated ducks practise at once, each scored by a "
                  + "reward. The finished network reads 61 sensor values and sets 14 joints, "
                  + "50 times a second.",
              symbol: "graduationcap", button: nil, go: nil),
        .init(id: "judge",
              title: "Be the judge",
              body: "A reward is a judgement written as numbers. In Compare you watch two and pick "
                  + "the better: RLHF's human feedback, with training done off the phone.",
              symbol: "rectangle.split.1x2", button: "Open Compare", go: .preference),
        .init(id: "make",
              title: "Make a motion",
              body: "Pose the duck, copy a person with the camera, or describe a move in words. "
                  + "A preview shows what you asked for; only a run shows what physics does.",
              symbol: "wand.and.stars", button: "Open Motions", go: .motions),
        .init(id: "measure",
              title: "Measure it",
              body: "This phone runs MuJoCo, the physics engine Pollen trains in. A challenge "
                  + "scores a move over many tries instead of one good take.",
              symbol: "trophy", button: "Open Challenges", go: .challenges),
        .init(id: "shoot",
              title: "Train a duck to shoot",
              body: "Walk to a ball, line up, kick it into a goal. Build the controller that joins "
                  + "Pollen's walker to its kick, then train its numbers on goals scored.",
              symbol: "soccerball", button: "Open the pitch", go: .shoot),
        .init(id: "tune",
              title: "Tune a network",
              body: "A phone cannot train from scratch, but it can nudge a trained network and keep "
                  + "what scores better on Pollen's own reward.",
              symbol: "slider.horizontal.3", button: "Tune on this phone", go: .tune),
        .init(id: "everything",
              title: "Show every tool",
              body: "Turn on the rest: network internals, weight search, formal evaluations, the "
                  + "robot's diagnostics and publishing.",
              symbol: "square.stack.3d.up", button: "Show every tool", go: .everything),
    ]

    /// The footer under the list, saying where the path leads in one line.
    public static func progress(done: Int) -> String {
        "\(done) of \(lessons.count) done"
    }
}
