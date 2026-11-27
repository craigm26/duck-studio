import Foundation
import DuckKit
import DuckEvidence

/// Kid-friendly visual backdrops, interactive playgrounds, sound labels and toy-pad buttons
/// for Play.
///
/// STUDIOKIT DECIDES, DUCKSTUDIO DRAWS. Every playground coordinate, every goal-line check,
/// every short button title and every voice label lives here so Linux tests can assert them
/// and so no user-visible literal is invented inside a view file.
public enum PlayWorld {

    // MARK: - Visual backdrops (mapped to StageTheme in DuckStudio)

    /// The six stage palettes already shipped in DuckStudio (`StageTheme`).
    public enum Backdrop: String, CaseIterable, Identifiable, Sendable {
        case pond
        case meadow
        case snow
        case arcade
        case dusk
        case park

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .pond: return "Pond"
            case .meadow: return "Meadow"
            case .snow: return "Snow"
            case .arcade: return "Arcade"
            case .dusk: return "Twilight"
            case .park: return "Park"
            }
        }

        public var symbol: String {
            switch self {
            case .pond: return "drop.fill"
            case .meadow: return "leaf.fill"
            case .snow: return "snowflake"
            case .arcade: return "gamecontroller.fill"
            case .dusk: return "moon.stars.fill"
            case .park: return "tree.fill"
            }
        }
    }

    // MARK: - Interactive physics playgrounds

    /// One-tap playgrounds built purely from bodies already compiled into the physics world
    /// (`ball`, `block_a`, `block_b`, `block_c`, `cone_a`, `cone_b`, and the step bank).
    public enum Playground: String, CaseIterable, Identifiable, Sendable {
        case openFloor
        case soccerGoal
        case bowling
        case blockParty
        case kickBall
        case tinySteps

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .openFloor: return "Open floor"
            case .soccerGoal: return "Soccer goal"
            case .bowling: return "Bowling"
            case .blockParty: return "Block party"
            case .kickBall: return "Kick ball"
            case .tinySteps: return "Tiny steps"
            }
        }

        public var subtitle: String {
            switch self {
            case .openFloor: return "Wide open mat to zoom around."
            case .soccerGoal: return "Kick the orange ball into the net."
            case .bowling: return "Knock down cones and bright blocks."
            case .blockParty: return "Push and tumble colorful blocks."
            case .kickBall: return "Ball right at the duck's feet."
            case .tinySteps: return "Gentle 30 mm steps to climb."
            }
        }

        public var symbol: String {
            switch self {
            case .openFloor: return "square.grid.2x2"
            case .soccerGoal: return "soccerball"
            case .bowling: return "triangle.fill"
            case .blockParty: return "cube.fill"
            case .kickBall: return "sportscourt.fill"
            case .tinySteps: return "stairs"
            }
        }

        /// Whether the soccer goalposts and net should be drawn on the stage.
        public var showsGoal: Bool { self == .soccerGoal }

        /// A suggested backdrop that pairs nicely when a child picks this playground, or nil to keep theirs.
        public var suggestedBackdrop: Backdrop? {
            switch self {
            case .soccerGoal: return .meadow
            case .bowling: return .arcade
            case .tinySteps: return .snow
            default: return nil
            }
        }

        /// The physics world plan sent to the simulator. Guaranteed sendable (zero refusals).
        public func plan(on bank: DuckWorld.Bank = .pinned,
                         graspables: [DuckBench.Health.Graspable] = []) -> DuckWorld.Plan {
            switch self {
            case .openFloor:
                return DuckWorld.Plan(name: title, clear: true)
            case .soccerGoal:
                return DuckWorld.Plan(
                    name: title,
                    clear: true,
                    ball: DuckWorld.Point(x: 0.45, y: 0.0))
            case .bowling:
                return DuckWorld.Plan(
                    name: title,
                    clear: true,
                    ball: DuckWorld.Point(x: 0.35, y: 0.0),
                    props: [
                        DuckWorld.Requested(name: "cone_a", x: 0.72, y: 0.0),
                        DuckWorld.Requested(name: "block_a", x: 0.86, y: 0.11),
                        DuckWorld.Requested(name: "block_b", x: 0.86, y: -0.11),
                        DuckWorld.Requested(name: "cone_b", x: 1.00, y: 0.18),
                        DuckWorld.Requested(name: "block_c", x: 1.00, y: -0.18),
                    ])
            case .blockParty:
                return DuckWorld.Plan(
                    name: title,
                    clear: true,
                    ball: DuckWorld.Point(x: 0.55, y: -0.25),
                    props: [
                        DuckWorld.Requested(name: "block_a", x: 0.38, y: 0.18),
                        DuckWorld.Requested(name: "block_b", x: 0.48, y: -0.05),
                        DuckWorld.Requested(name: "block_c", x: 0.62, y: 0.16),
                        DuckWorld.Requested(name: "cone_a", x: 0.42, y: -0.32),
                        DuckWorld.Requested(name: "cone_b", x: 0.70, y: -0.18),
                    ])
            case .kickBall:
                return DuckWorld.Plan(
                    name: title,
                    clear: true,
                    ball: DuckWorld.Point(x: 0.28, y: 0.0))
            case .tinySteps:
                let stairs = DuckScene.stairsChallenge(rise: 0.03)
                return DuckWorld.plan(for: stairs, on: bank, graspables: graspables)
            }
        }
    }

    // MARK: - Soccer goal check

    /// True when the rolling ball has crossed the goal line between the posts.
    public static func isGoal(ballX: Double, ballY: Double,
                              pitch: Shoot.Pitch = .canon) -> Bool {
        ballX >= pitch.goalX && abs(ballY) <= pitch.goalHalfWidth
    }

    // MARK: - Kid-friendly short toy-button labels and icons

    /// Short, playful labels and SF Symbols for the four Simple-mode face buttons on Play.
    public struct ToyButton: Equatable, Sendable {
        public let title: String
        public let symbol: String

        public init(title: String, symbol: String) {
            self.title = title
            self.symbol = symbol
        }
    }

    /// Kid-friendly title and symbol for an official move slot.
    public static func toyButton(for slot: DuckOfficialPolicies.Slot) -> ToyButton {
        switch slot {
        case .kickRight, .kickLeft:
            return ToyButton(title: "Kick", symbol: "soccerball")
        case .roulade:
            return ToyButton(title: "Roll", symbol: "arrow.triangle.2.circlepath")
        case .groundPick:
            return ToyButton(title: "Peck", symbol: "arrow.down.to.line")
        case .sitstand:
            return ToyButton(title: "Sit", symbol: "chair.fill")
        case .walk:
            return ToyButton(title: "Walk", symbol: "figure.walk")
        case .stand:
            return ToyButton(title: "Stand", symbol: "figure.stand")
        }
    }

    // MARK: - Kid-friendly duck sound labels

    /// Short, cheerful labels and symbols for the seven synthesized duck voices.
    public static func soundTitle(_ sound: DuckSound) -> String {
        switch sound {
        case .chirp: return "Quack!"
        case .greet: return "Hi!"
        case .wheee: return "Wheee!"
        case .coo: return "Purr"
        case .inquire: return "Huh?"
        case .peck: return "Peck"
        case .alarm: return "Honk!"
        }
    }

    public static func soundSymbol(_ sound: DuckSound) -> String {
        switch sound {
        case .chirp: return "speaker.wave.2.fill"
        case .greet: return "hand.wave.fill"
        case .wheee: return "sparkles"
        case .coo: return "heart.fill"
        case .inquire: return "questionmark.bubble.fill"
        case .peck: return "arrow.down.to.line"
        case .alarm: return "megaphone.fill"
        }
    }

    /// Ordered with the most fun sounds first for a six-year-old.
    public static let kidSounds: [DuckSound] = [
        .chirp, .wheee, .greet, .coo, .alarm, .inquire, .peck
    ]

    // MARK: - Copy for the Worlds sheet

    public enum Words {
        public static let title = "Worlds"
        public static let backdrops = "Colors and sky"
        public static let playgrounds = "Playgrounds"
        public static let moreScenes = "All saved scenes"
        public static let goalBanner = "GOAL! Great kick!"
        public static let allWords: [String] = [
            title, backdrops, playgrounds, moreScenes, goalBanner,
        ]
            + Backdrop.allCases.map(\.title)
            + Playground.allCases.flatMap { [$0.title, $0.subtitle] }
            + DuckSound.allCases.map(soundTitle)
            + DuckOfficialPolicies.Slot.allCases.map { toyButton(for: $0).title }
    }
}
