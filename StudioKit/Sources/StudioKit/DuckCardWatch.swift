import Foundation

extension DuckCards {

    /// A stream of single-picture reads, turned into a few decisions — `cardreader`'s `Watcher`,
    /// rule for rule, so the duck and Studio decide the same way when a card is being shown.
    ///
    /// A READ MUST HOLD STILL. One picture can catch a hand mid-swap; `need` pictures in a row
    /// reading the same thing is a card someone is showing. A card that has been acted on is not
    /// acted on again until it has been gone for `forget` seconds, so holding a card up is one
    /// kick, not one a frame. A Start held up with no End for `unfinishedAfter` seconds is asked
    /// about once.
    public struct Watcher: Sendable {
        public enum Event: Equatable, Sendable {
            case card(String)
            case row(String)
            case unfinished(String)
        }

        struct Key: Equatable, Sendable {
            let kind: Program.Kind
            let words: String
            let complete: Bool
        }

        public let need: Int
        public let forget: Double
        public let unfinishedAfter: Double
        private var key: Key?
        private var count = 0
        private var firedKey: Key?
        private var lastSeenFired = -1e9
        private var startSince: Double?
        private var asked = false

        public init(need: Int = 3, forget: Double = 1.5, unfinishedAfter: Double = 4.0) {
            self.need = need
            self.forget = forget
            self.unfinishedAfter = unfinishedAfter
        }

        public mutating func feed(_ program: Program, at now: Double) -> Event? {
            let current: Key? = (program.kind == .none || program.steps.isEmpty)
                ? nil : Key(kind: program.kind, words: program.words, complete: program.complete)
            if current == key {
                count += 1
            } else {
                key = current
                count = current == nil ? 0 : 1
            }
            if firedKey != nil && current == firedKey { lastSeenFired = now }
            if firedKey != nil && now - lastSeenFired > forget { firedKey = nil }
            if program.kind == .row && !program.complete {
                if startSince == nil { startSince = now }
                if !asked, let since = startSince, now - since >= unfinishedAfter {
                    asked = true
                    return .unfinished(program.words)
                }
            } else {
                startSince = nil
                asked = false
            }
            guard let k = current, count >= need, k != firedKey else { return nil }
            if k.kind == .row && !k.complete { return nil }
            firedKey = k
            lastSeenFired = now
            return k.kind == .card ? .card(k.words) : .row(k.words)
        }
    }

    /// Every sentence the camera card says about cards. Here rather than in a view, so `swift test`
    /// reads them.
    public enum Words {
        public static let toggle = "Read Duck Cards"
        public static let noCards = "No Duck Cards in the picture."
        public static let notACard = "A code in the picture is not a Duck Card."

        /// A row whose Repeat number nobody could read: what the camera card leads with.
        public static let waitsForRepeat = "Row, once Repeat has its number"

        /// One line for what the camera sees now: the row in its own words, or why there is none.
        public static func sees(_ reading: Reading) -> String {
            let program = reading.program
            if !program.steps.isEmpty {
                let lead = program.kind == .card ? "Card"
                    : program.complete ? "Row" : program.asks.isEmpty ? "Row so far" : waitsForRepeat
                return "\(lead): \(program.words)"
            }
            if let note = program.notes.first { return note }
            if reading.look.foreign > 0 { return notACard }
            return noCards
        }
    }
}
