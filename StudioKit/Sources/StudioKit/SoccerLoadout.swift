import Foundation
import DuckKit

/// Your moves in Duck Soccer: which of your own skills plays when you shoot,
/// pass, do your Special, or celebrate.
///
/// A SKILL IS ANYTHING COMPARE CAN TURN INTO A CLIP: a recorded motion, a draft
/// you wrote, a sequence you drove, a behaviour recorded on a bench, or the
/// shooter you trained. The clip is what the duck does on the pitch, and where
/// it was recorded in physics it also decides the game effect: a shot holds the
/// duck for as long as the clip lasts, and a Special carries the duck as far as
/// the recording carried it. The ball's speed off a kick stays the game's own
/// tuning, and the screens say so.
public struct SoccerLoadout: Codable, Equatable, Sendable {

    public enum Slot: String, Codable, CaseIterable, Sendable, Identifiable {
        case shoot, pass, special, celebrate
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .shoot: return "Shoot"
            case .pass: return "Pass"
            case .special: return "Special"
            case .celebrate: return "Celebrate"
            }
        }

        public var symbol: String {
            switch self {
            case .shoot: return "soccerball"
            case .pass: return "arrow.up.forward"
            case .special: return "sparkles"
            case .celebrate: return "party.popper"
            }
        }

        /// What plays when nothing of yours is chosen.
        public var standard: String {
            switch self {
            case .shoot, .pass: return "Pollen's kick"
            case .special: return "The roulade"
            case .celebrate: return "The roulade"
            }
        }

        /// What the slot's clip changes in the game, in one line.
        public var effect: String {
            switch self {
            case .shoot, .pass: return "Your clip plays on the strike and holds the duck as long as it lasts."
            case .special: return "Your clip plays, and the duck travels as far as the clip moved it."
            case .celebrate: return "Your clip plays after your team scores."
            }
        }
    }

    /// One chosen skill, by what Compare knows it as.
    public struct Skill: Codable, Equatable, Sendable {
        public let kind: String
        public let key: String
        public let name: String
        public let digest: String

        public init(kind: String, key: String, name: String, digest: String) {
            self.kind = kind; self.key = key; self.name = name; self.digest = digest
        }

        public init(_ c: Compare.Contender) {
            self.init(kind: c.kind.rawValue, key: c.key, name: c.name, digest: c.digest)
        }

        public var contender: Compare.Contender? {
            guard let k = Compare.Contender.Kind(rawValue: kind) else { return nil }
            return Compare.Contender(kind: k, name: name, digest: digest, source: .yours, key: key)
        }
    }

    public var skills: [String: Skill] = [:]

    public init() {}

    public subscript(slot: Slot) -> Skill? {
        get { skills[slot.rawValue] }
        set { skills[slot.rawValue] = newValue }
    }

    public var isStandard: Bool { skills.isEmpty }

    /// The engine moves the resolved clips imply. A slot with no clip keeps
    /// the standard timing.
    public static func moves(from clips: [Slot: DuckIntentClip]) -> DuckSoccer.Moves {
        var moves = DuckSoccer.Moves.standard
        if let shot = clips[.shoot] { moves = DuckSoccer.Moves(shootLock: shot.duration, passLock: moves.passLock,
                                                               special: moves.special) }
        if let pass = clips[.pass] { moves = DuckSoccer.Moves(shootLock: moves.shootLock, passLock: pass.duration,
                                                              special: moves.special) }
        if let special = clips[.special] {
            moves = DuckSoccer.Moves(shootLock: moves.shootLock, passLock: moves.passLock,
                                     special: .init(distance: forwardTravel(special),
                                                    duration: special.duration))
        }
        return moves
    }

    /// How far a clip carried the duck along the way it started out facing,
    /// in metres. Zero for a clip with no root (a move played on the spot) or
    /// one that went backwards.
    public static func forwardTravel(_ clip: DuckIntentClip) -> Double {
        guard let first = clip.roots.first, let last = clip.roots.last else { return 0 }
        let (w, x, y, z) = first.quaternion
        let yaw = atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
        let dx = last.x - first.x, dy = last.y - first.y
        return max(0, dx * cos(yaw) + dy * sin(yaw))
    }

    // MARK: - stored

    public func encoded() -> String {
        (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? ""
    }

    public static func decoded(_ text: String) -> SoccerLoadout {
        (try? JSONDecoder().decode(SoccerLoadout.self, from: Data(text.utf8))) ?? SoccerLoadout()
    }
}
