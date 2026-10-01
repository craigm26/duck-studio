import Foundation
import Crypto
import DuckKit

/// Compare: watch two things the duck can do, side by side, and say which is
/// better. The human-feedback half of RLHF, made into a game.
///
/// WHAT THE APP DOES AND WHAT IT DOES NOT. Every pick is a labelled
/// preference, written as a `duck-feedback/0` record on this phone. Nothing on
/// the phone fits a model to them or trains a network: shared picks go to a
/// public dataset, where craigm26/duckbatch fits a preference model
/// (Bradley–Terry) and ranks what people like. The one thing ranked HERE is a
/// tournament's own bracket, from the picks made in it, so a person can see
/// their champion.
///
/// ANYTHING THAT BECOMES A CLIP CAN BE COMPARED. A network is recorded under a
/// command on a bench; a recorded motion already is a clip; a draft's
/// keyframes are performed in physics; a sequence is replayed. All four arrive
/// as the same `DuckIntentClip`, drawn on the same stage, so the only
/// difference between the two ducks on screen is the thing being judged.
public enum Compare {

    // MARK: - what can be compared

    /// One thing a person can judge.
    public struct Contender: Equatable, Hashable, Sendable, Identifiable {
        public enum Kind: String, Sendable, CaseIterable {
            /// A trained network, recorded under a command.
            case behaviour
            /// A recorded motion (Pollen's recordings, or one kept here).
            case motion
            /// Keyframes somebody wrote, performed in physics.
            case draft
            /// Stick commands and moves driven on the pad, replayed.
            case sequence
            /// A shooting controller's numbers (Train a duck to shoot), judged
            /// by the shot it takes from one ball spot.
            case shooter

            public var title: String {
                switch self {
                case .behaviour: return "Behaviours"
                case .motion: return "Recorded motions"
                case .draft: return "Your motions"
                case .sequence: return "Sequences"
                case .shooter: return "Shooters"
                }
            }

            /// What goes in the record's `kind`. A draft and a recording are
            /// both motions to the reader.
            var recordKind: String {
                switch self {
                case .behaviour: return "policy"
                case .motion, .draft: return "motion"
                case .sequence: return "sequence"
                case .shooter: return "shooter"
                }
            }

            /// Whether two of these are judged doing the same command. A
            /// motion or a sequence carries its own.
            public var takesACommand: Bool { self == .behaviour }
        }

        /// Whose it is, as the record says it.
        public enum Source: String, Sendable {
            case pollen, community, yours, device
            public var title: String {
                switch self {
                case .pollen: return "Pollen Robotics"
                case .community: return "Community"
                case .yours: return "Yours"
                case .device: return "On \(DeviceWords.current.this)"
                }
            }
        }

        public let kind: Kind
        public let name: String
        /// `sha256:<hex>`. A network's is its fingerprint; anything else's is
        /// the digest of its content, so a renamed motion is the same motion.
        public let digest: String
        public let source: Source
        /// Where the app finds it again: a library id, a clip name, a draft
        /// or sequence UUID. Not written into the record.
        public let key: String

        public var id: String { "\(kind.rawValue):\(digest)" }

        public init(kind: Kind, name: String, digest: String, source: Source, key: String) {
            self.kind = kind; self.name = name; self.digest = digest
            self.source = source; self.key = key
        }
    }

    /// The digest of anything that is not a network, from its content.
    public static func digest(of data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A clip's digest, from its frames and rate and nothing else, so the same
    /// recording under two names is one contender.
    public static func digest(of clip: DuckIntentClip) -> String {
        var text = String(format: "%.4f;", clip.hz)
        for frame in clip.frames {
            text += frame.map { String(format: "%.5f", $0) }.joined(separator: ",") + ";"
        }
        return digest(of: Data(text.utf8))
    }

    /// Two can be compared when they are the same kind (motions and drafts
    /// count as one kind) and are not the same thing.
    public static func canCompare(_ a: Contender, _ b: Contender) -> Bool {
        a.digest != b.digest && a.kind.recordKind == b.kind.recordKind
    }

    // MARK: - a tournament

    /// Three to eight contenders, a schedule of pairs, and a ranking fitted to
    /// the picks made so far.
    ///
    /// BRADLEY–TERRY, THE SAME MODEL DUCKBATCH FITS, but over names rather than
    /// features: each contender has a strength s, and P(a beats b) =
    /// s_a / (s_a + s_b). A tie counts as half a win each. "Neither is good"
    /// is recorded for training and moves nothing here. Every contender starts
    /// with one virtual draw against an average opponent, so a single pick
    /// cannot send anybody to infinity.
    public struct Tournament: Equatable, Sendable {
        public static let smallest = 3
        public static let largest = 8

        public let contenders: [Contender]
        public private(set) var results: [Result] = []

        public struct Result: Equatable, Sendable {
            public let a: Int, b: Int
            /// 1 = a won, 0 = b won, 0.5 = a tie; nil = neither was good.
            public let score: Double?
        }

        public enum Refusal: Error, Equatable {
            case tooFew, tooMany, mixedKinds, duplicate
            public var message: String {
                switch self {
                case .tooFew: return "A tournament needs at least \(Tournament.smallest)."
                case .tooMany: return "A tournament takes at most \(Tournament.largest)."
                case .mixedKinds: return "Everything in a tournament has to be the same kind."
                case .duplicate: return "The same one is in there twice."
                }
            }
        }

        public init(_ contenders: [Contender]) throws {
            guard contenders.count >= Self.smallest else { throw Refusal.tooFew }
            guard contenders.count <= Self.largest else { throw Refusal.tooMany }
            guard Set(contenders.map { $0.kind.recordKind }).count == 1 else {
                throw Refusal.mixedKinds
            }
            guard Set(contenders.map(\.digest)).count == contenders.count else {
                throw Refusal.duplicate
            }
            self.contenders = contenders
        }

        /// How many picks make a full tournament: every pair once up to five
        /// contenders; twice the field above that, which is enough for a
        /// stable top without asking for all 28 pairs of eight.
        public var length: Int {
            let n = contenders.count
            return n <= 5 ? n * (n - 1) / 2 : n * 2
        }

        public var isFinished: Bool { results.count >= length }

        /// The next pair to show, or nil when finished.
        ///
        /// FEWEST MEETINGS FIRST, THEN CLOSEST STRENGTHS. Early on that is a
        /// round robin; later it asks about the pairs the ranking is least sure
        /// of, which is where a pick teaches most.
        public func nextPair() -> (a: Int, b: Int)? {
            guard !isFinished else { return nil }
            let s = strengths()
            var best: (a: Int, b: Int, met: Int, gap: Double)?
            for i in contenders.indices {
                for j in contenders.indices where j > i {
                    let met = results.filter { ($0.a == i && $0.b == j) || ($0.a == j && $0.b == i) }.count
                    let gap = abs(log(s[i]) - log(s[j]))
                    if let b = best, (met, gap) >= (b.met, b.gap) { continue }
                    best = (i, j, met, gap)
                }
            }
            guard let best else { return nil }
            // Alternate sides so the same contender is not always on the left.
            return results.count % 2 == 0 ? (best.a, best.b) : (best.b, best.a)
        }

        /// Record a pick between `a` and `b` (indices into `contenders`).
        public mutating func record(a: Int, b: Int, choice: DuckFeedback.Choice) {
            let score: Double?
            switch choice {
            case .a: score = 1
            case .b: score = 0
            case .tie: score = 0.5
            case .bothBad: score = nil
            }
            results.append(Result(a: a, b: b, score: score))
        }

        /// Bradley–Terry strengths by the minorisation–maximisation update,
        /// with the one virtual draw each against a strength-1 opponent.
        public func strengths() -> [Double] {
            let n = contenders.count
            var s = [Double](repeating: 1, count: n)
            for _ in 0..<100 {
                var next = s
                for i in 0..<n {
                    var wins = 0.5       // the virtual draw
                    var denominator = 1 / (s[i] + 1)
                    for r in results {
                        guard let score = r.score else { continue }
                        if r.a == i {
                            wins += score; denominator += 1 / (s[i] + s[r.b])
                        } else if r.b == i {
                            wins += 1 - score; denominator += 1 / (s[i] + s[r.a])
                        }
                    }
                    next[i] = wins / denominator
                }
                s = next
            }
            return s
        }

        /// Contenders, strongest first, with their share of the total
        /// strength as a number a person can read.
        public func ranking() -> [(contender: Contender, share: Double)] {
            let s = strengths()
            let total = s.reduce(0, +)
            return contenders.indices
                .sorted { s[$0] > s[$1] }
                .map { (contenders[$0], s[$0] / total) }
        }

        /// The winner once the tournament is done.
        public var champion: Contender? {
            isFinished ? ranking().first?.contender : nil
        }
    }

    // MARK: - improving one thing by choosing

    /// Variants of a sequence for "Improve by choosing": the same drive,
    /// quicker and gentler, faster and slower. The original is always one of
    /// them, so "none of these is better" is an answer the bracket can give.
    public static func variants(of sequence: DuckSequence) -> [(label: String, sequence: DuckSequence)] {
        let scales: [(String, Double, Double)] = [
            ("As driven", 1, 1),
            ("Gentler", 0.75, 1),
            ("Bolder", 1.25, 1),
            ("Quicker", 1, 0.8),
            ("Slower", 1, 1.25),
        ]
        return scales.map { label, speed, time in
            (label, sequence.scaled(speed: speed, time: time, naming: "\(sequence.name) · \(label)"))
        }
    }

    // MARK: - streaks

    /// Consecutive days with at least one pick, ending today or yesterday.
    public static func streak(days: Set<String>, today: Date = Date(),
                              calendar: Calendar = .current) -> Int {
        func key(_ d: Date) -> String {
            let c = calendar.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        var day = today
        if !days.contains(key(day)) {
            guard let y = calendar.date(byAdding: .day, value: -1, to: day),
                  days.contains(key(y)) else { return 0 }
            day = y
        }
        var count = 0
        while days.contains(key(day)) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Every sentence the Compare screens say.
public enum CompareWords {
    public static let title = "Compare"
    public static let studioRow = "Compare"
    public static let studioRowSymbol = "rectangle.split.1x2"

    /// The one line at the top of the hub. RLHF with what it means here.
    public static let intro =
        "You are the judge. Watch two, pick the better one. This is RLHF's human feedback: "
      + "your picks are the labels, and training on them happens off the phone."

    public static let quickDuel = "Quick duel"
    public static let quickDuelDetail = "Pairs of Pollen's walkers, already recorded. No setup."
    public static let pickTwo = "Pick any two"
    public static let pickTwoDetail = "Networks, motions or sequences, from Pollen, the community or you."
    public static let tournament = "Tournament"
    public static let tournamentDetail = "Three to eight enter, your picks rank them, one is champion."
    public static let improve = "Improve by choosing"
    public static let improveDetail = "Start from one of yours; pick between variants until it is better."

    public static let chooseKind = "What are you comparing?"
    public static let chooseTwo = "Choose two"
    public static func chooseSome(_ n: Int) -> String {
        n < Compare.Tournament.smallest
            ? "Choose \(Compare.Tournament.smallest - n) more"
            : "\(n) chosen"
    }
    public static let start = "Start"
    public static let command = "Command"
    public static let running = "Running both on the bench…"
    public static let noBench = "Compare runs things on a bench. This iPhone is one; pick it in Settings → Benches."

    public static let left = "Left"
    public static let right = "Right"
    public static let tie = "Too close"
    public static let bothBad = "Neither"

    public static func tally(_ n: Int, streak: Int) -> String {
        let picks = n == 1 ? "1 pick" : "\(n) picks"
        guard streak > 1 else { return "\(picks) today" }
        return "\(picks) today · \(streak)-day streak"
    }

    public static func progress(_ done: Int, of total: Int) -> String {
        "Match \(min(done + 1, total)) of \(total)"
    }
    public static let champion = "Champion"
    public static let standings = "Standings"
    public static let again = "Run another"
    public static let keepChampion = "Keep the champion"
    public static func kept(_ name: String) -> String { "Kept as \(name)." }

    public static let sharing =
        "Picks stay on \(DeviceWords.current.this) unless Settings → Feedback says they may be shared. Shared "
      + "picks go to a public dataset on Hugging Face, where a preference model ranks what "
      + "people like."

    /// Commands a behaviour duel can be run under, named for a person.
    ///
    /// AT THE PAD'S TOP SPEED, because Pollen's walker has a dead band: at
    /// 0.20 m/s it travels 1.5 cm in 8 s, and two ducks standing still under
    /// "walk forward" ask a person nothing (the p001 finding).
    public static let commands: [(name: String, twist: DuckDrive.Twist)] = [
        ("Walk forward", DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0)),
        ("Turn on the spot", DuckDrive.Twist(vx: 0, vy: 0, vyaw: 1.0)),
        ("Walk an arc", DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0.6)),
        ("Stand still", DuckDrive.Twist(vx: 0, vy: 0, vyaw: 0)),
    ]
    /// How long a behaviour duel records.
    public static let seconds = 6.0
}
