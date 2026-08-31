import Foundation

/// What the Lab holds, and how much of each of it is real.
///
/// WHY THIS IS A TABLE AND NOT A SCREEN FULL OF ROWS. The Lab is where this app
/// is most likely to start overclaiming: a ghost duck standing on your carpet
/// and a duck chasing a ball both LOOK like capability, and neither is a robot
/// doing anything. Every other surface in this app states what it measured and
/// what it assumed; the Lab has to as well, and the cheapest way to make that
/// true is to keep the claim beside the mode in a place `swift test` can read.
///
/// NOTHING HERE TALKS TO A ROBOT, AND THAT IS SAID ONCE RATHER THAN NINE TIMES.
/// Pollen's stated first Microduck deliveries are around Christmas 2026. Until
/// then every mode below runs on a recorded policy, a trained network on the
/// phone, or a physics bench on somebody's desk. `preamble` is that sentence,
/// and a screen that shows any of these modes must show it.
public enum LabCatalogue {

    /// How much of a mode exists, which is the only thing a row must not lie
    /// about. A row whose status is anything but `.here` is a row the screen
    /// must draw disabled, with the reason next to it — the same rule the rest
    /// of the app follows for a control that cannot work yet.
    public enum Status: Equatable, Sendable {
        /// Built, in this app, reachable now.
        case here
        /// Written and shipping in another app in this family, not yet ported.
        /// Carries the app it comes from, because "coming soon" is what a row
        /// says when nobody has written it.
        case portingFrom(String)
        /// Designed, not written anywhere.
        case planned
        /// Cannot be honest without a robot on the floor.
        case waitingOnHardware

        /// What the row says about itself when it is not usable yet.
        ///
        /// EVERY ONE OF THESE NAMES A REASON, not a date. This family has three
        /// apps that were planned, gated, given bundle identifiers and never
        /// written, and "coming soon" is exactly what their rows would have
        /// said for a year.
        public var reason: String? {
            switch self {
            case .here:
                return nil
            case .portingFrom(let app):
                return "Written and running in \(app). Not ported here yet."
            case .planned:
                return "Designed, not written. There is nothing behind this row yet."
            case .waitingOnHardware:
                return "Needs a Microduck on the floor. Nobody has one until Pollen ships."
            }
        }
    }

    public struct Mode: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        /// The SF Symbol the row is drawn with. Presentation truth lives here
        /// with the sentence it sits beside, so the two cannot be changed apart.
        public let symbol: String
        /// One line saying what the mode DOES, in terms of what is real about
        /// it. Never what it feels like.
        public let blurb: String
        public let status: Status

        public init(id: String, name: String, symbol: String, blurb: String, status: Status) {
            self.id = id; self.name = name; self.symbol = symbol
            self.blurb = blurb; self.status = status
        }
    }

    /// The sentence that has to appear above any list of these.
    public static let preamble =
        "No Microduck exists yet — Pollen's first deliveries are around Christmas 2026. "
      + "Nothing in the Lab is talking to a robot. What runs here is a trained policy on "
      + "this phone, a physics bench on your own network, or a recorded motion."

    /// Why the Lab is one tab rather than three apps.
    public static let rationale =
        "Duck Soccer, Duckboard and Duck Diary were three separate apps on paper. Each one "
      + "needed its own shell, icon, privacy label and review before it could show anybody a "
      + "duck. They are screens here instead."

    /// Ordered as a person meets them: what works now, then what is being
    /// brought over, then what is waiting on a robot.
    public static let modes: [Mode] = [
        .init(id: "bench", name: "Physics bench", symbol: "server.rack",
              blurb: "A machine on your network that has MuJoCo, which a phone does not. "
                   + "Run an imported policy, record it into a motion, or measure how often "
                   + "it ends standing.",
              status: .here),
        .init(id: "ghost", name: "Ghost duck", symbol: "figure.walk.motion",
              blurb: "A life-size duck at 1:1, replaying a gait recorded from the trained "
                   + "policy — and the seven games that hang off it: golf, fetch, follow me, "
                   + "the bow bridge, the trick run, the slalom and the flamingo hold. "
                   + "Kinematics, not a simulation of a robot.",
              status: .here),
        .init(id: "soccer", name: "Duck soccer", symbol: "soccerball",
              blurb: "A ball on a stage or on your own floor. Goals are hash-chained and "
                   + "signed on the device; practice matches are refused for export on "
                   + "purpose.",
              status: .here),
        // WHAT IT WRITES IS AN MJCF FILE, NOT A SCENE, and the blurb used to say
        // otherwise. `RoomCaptureView.emit()` sets `mjcf` text and shows it in a
        // read-only sheet; it never touches `SceneStore`, so nothing else in
        // the app can stand a duck in the room you captured. The geometry is
        // real — LiDAR planes reduced to boxes — which is exactly why the
        // sentence has to be precise about where it stops.
        .init(id: "room", name: "Room capture", symbol: "square.split.bottomrightquarter",
              blurb: "Measures the room around you and writes it out as MuJoCo scene geometry "
                   + "— real boxes at real dimensions, for a simulator elsewhere. It does not "
                   + "yet become a scene this app can stand a duck in.",
              status: .here),
        .init(id: "trials", name: "Trials", symbol: "chart.dots.scatter",
              blurb: "Place an object at a bearing and a range, run a policy at it a set "
                   + "number of times, and report the fraction that met a stated criterion. "
                   + "A success rate, not a highlight reel.",
              status: .planned),
        .init(id: "bobsled", name: "Bobsled", symbol: "figure.snowboarding",
              blurb: "A run down a mountain, steered. The version in OpenCastor is a rover "
                   + "game wearing a duck; this one is to be built for the duck's own turn "
                   + "radius rather than ported.",
              status: .planned),
        .init(id: "deck", name: "Deck", symbol: "square.grid.2x2",
              blurb: "Six fat buttons and a stop bar you can hit without looking, over your "
                   + "own Wi-Fi. The whole design is about how fast a stop reaches a robot.",
              status: .waitingOnHardware),
        .init(id: "diary", name: "Diary", symbol: "book.closed",
              blurb: "A signed, hash-chained ledger of what a duck actually did — distance, "
                   + "falls, how often it hit its own speed limit. Share a number and you "
                   + "share a signature over it.",
              status: .waitingOnHardware),
    ]

    /// The modes a person can actually open today.
    public static var usable: [Mode] { modes.filter { $0.status == .here } }
}
