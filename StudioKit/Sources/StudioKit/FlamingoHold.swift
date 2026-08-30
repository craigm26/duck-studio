import Foundation

/// Flamingo hold: keep the duck on one foot while the world shoves it.
///
/// THE LIMITS ARE THE AUTHOR'S, NOT A DESIGNER'S. `flamingo-cycle`, published
/// to Hugging Face by Pollen's Rémi Fabre, states in its own manifest what it
/// survives: pushes up to 0.15 m/s from any direction; a harder push toward the
/// LIFTED side is absorbed by a brief touch-down and it re-lifts; toward the
/// STANDING side it steps down; and backward at 0.18 m/s or more **it falls**
/// (his stress battery: 20 held, 2 stepped down, 2 fell, in 24 random trials).
/// Those four sentences are the entire rule set. Nothing here was tuned.
///
/// So the game is not "press the button faster". It is that the same shove has
/// three different consequences depending on which way the duck is standing,
/// and the player has to know which foot is down.
public struct FlamingoHold: Equatable, Sendable {

    /// Which leg is in the air. `side` in the policy's own command block:
    /// +1 lifts the LEFT leg (right foot down), −1 the right.
    public enum Side: Int, Equatable, Sendable {
        case leftLifted = 1
        case rightLifted = -1

        /// The foot bearing the weight is the opposite one.
        public var standingFoot: String { self == .leftLifted ? "right" : "left" }
        public var liftedLeg: String { self == .leftLifted ? "left" : "right" }
    }

    public enum Direction: String, Equatable, Sendable, CaseIterable {
        case forward, backward, towardLifted, towardStanding
    }

    /// What a shove did. These are the author's four outcomes, in his words.
    public enum Result: Equatable, Sendable {
        /// Under 0.15 m/s from any direction: it just holds.
        case held
        /// Harder, toward the lifted side: a brief touch-down, then it re-lifts.
        case touchedDownAndRecovered
        /// Harder, toward the standing side: it steps down and the hold is over.
        case steppedDown
        /// Backward at 0.18 m/s or more: it falls.
        case fell
    }

    /// The published thresholds, in metres per second.
    public static let holdsUpTo = 0.15
    public static let fallsBackwardAt = 0.18

    public struct Push: Equatable, Sendable {
        public let direction: Direction
        public let speed: Double
        public init(direction: Direction, speed: Double) {
            self.direction = direction; self.speed = speed
        }
    }

    public private(set) var side: Side
    public private(set) var survived = 0
    public private(set) var elapsed = 0.0
    public private(set) var over = false
    public private(set) var lastResult: Result?

    public init(side: Side = .leftLifted) { self.side = side }

    /// What a push does, by the manifest's own rules and nothing else.
    ///
    /// BRACING IS REAL, AND IT IS THE ONE THING THE GAME ADDS. The policy has
    /// no brace input — it either holds or it does not — so a braced push is
    /// modelled as the player shifting weight in time, which this treats as
    /// halving the push. That is a game rule, not a measurement, and it is the
    /// only one in this file.
    public static func outcome(of push: Push, side: Side, braced: Bool) -> Result {
        let speed = braced ? push.speed / 2 : push.speed
        if speed <= holdsUpTo { return .held }
        if push.direction == .backward && speed >= fallsBackwardAt { return .fell }
        switch push.direction {
        case .towardLifted:   return .touchedDownAndRecovered
        case .towardStanding: return .steppedDown
        case .backward:       return .touchedDownAndRecovered   // hard but under 0.18
        case .forward:        return .steppedDown
        }
    }

    /// Take a push. `braced` is whether the player leaned the right way in time.
    @discardableResult
    public mutating func take(_ push: Push, braced: Bool, after seconds: Double = 0) -> Result {
        guard !over else { return lastResult ?? .held }
        elapsed += seconds
        let result = Self.outcome(of: push, side: side, braced: braced)
        lastResult = result
        switch result {
        case .held, .touchedDownAndRecovered:
            survived += 1
        case .steppedDown, .fell:
            over = true
        }
        return result
    }

    /// Swap feet between pushes — the policy does either side with the same
    /// network, ~1.5 s each way, so this is free and changes which shove is
    /// which.
    public mutating func switchSide() {
        guard !over else { return }
        side = side == .leftLifted ? .rightLifted : .leftLifted
    }

    public var summary: String {
        guard over else {
            return "\(survived) shoved off, standing on the \(side.standingFoot) foot"
        }
        switch lastResult {
        case .fell:        return "Over backwards after \(survived) — that is the one it cannot take."
        case .steppedDown: return "Put a foot down after \(survived)."
        default:           return "\(survived) survived."
        }
    }
}
