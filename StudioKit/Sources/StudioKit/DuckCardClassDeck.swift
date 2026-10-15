import Foundation

extension DuckCards {

    // MARK: - why not

    /// Why a row did not become a Your card, a card was not forgotten, or a deck file was not
    /// taken. Each one says so in a sentence, here where `swift test` reads it.
    public enum Refusal: Error, Equatable, Sendable {
        /// No row in the picture has a Start.
        case noRow
        /// The row has a Start and no End.
        case noEnd
        /// This many Repeat cards still wait for their number.
        case asks(Int)
        /// Nothing between Start and End makes a step.
        case empty
        case noName
        /// A number outside the deck's Your card numbers, which are given with it.
        case notYours(Int, ClosedRange<Int>)
        /// The row holds the very card it would be saved as.
        case holdsItself(Int)
        /// The row holds a Your card that leads back to the one it would be saved as.
        case loop(Int, through: Int)
        /// Saved, the card would hold Your cards deeper than a reader goes.
        case tooDeep(Int)
        /// The number already means something, and saving would replace it.
        case wouldReplace(Card)
        /// Saved, the card would not read back to the row's own steps.
        case readsDifferently(Int)
        /// There is no meaning saved for this card, so nothing to forget.
        case notSaved(Int)
        /// A deck file the reader cannot follow, in `Deck.read`'s own words.
        case notADeck(String)
        /// The class deck could not be written where Studio keeps it.
        case notWritten(String)
        /// The starter deck did not load, so there is no class deck at all.
        case noDeck

        public var message: String {
            switch self {
            case .noRow:
                return "There is no Start in the picture, so there is no row to save."
            case .noEnd:
                return "The row has no End yet. Put End after its last card, then save it."
            case .asks(let n):
                return n == 1 ? "Say how many times the Repeat goes first."
                              : "Say how many times each Repeat goes first."
            case .empty:
                return "Nothing between Start and End makes a step, so there is nothing to save."
            case .noName:
                return "Give the card a name first."
            case .notYours(let n, let range):
                return "\(n) is not a Your card. Your cards are numbered \(range.lowerBound) to \(range.upperBound)."
            case .holdsItself(let tag):
                return "The row holds card \(tag) itself, so it cannot be saved as \(tag)."
            case .loop(let tag, let through):
                return "The row holds card \(through), which leads back to \(tag), so it cannot be saved as \(tag)."
            case .tooDeep(let tag):
                return "Saved as card \(tag), the row would hold Your cards inside Your cards more than "
                     + "\(DuckCards.yoursDepth) deep. A reader stops at \(DuckCards.yoursDepth), so it was not saved."
            case .wouldReplace(let card):
                return "Card \(card.tag) already means \(card.name), so it was not replaced."
            case .readsDifferently(let tag):
                return "Saved as card \(tag), the row would not read the same, so it was not saved."
            case .notSaved(let tag):
                return "Card \(tag) means nothing yet, so there is nothing to forget."
            case .notADeck(let why):
                return "That deck was not opened: \(why)."
            case .notWritten(let why):
                return "The class deck could not be written. \(why)"
            case .noDeck:
                return "The starter deck did not load, so there is no class deck to keep cards in."
            }
        }
    }

    // MARK: - a row, as a Your card holds it

    /// The row a reader runs: the first one with a Start that does not begin with When it falls,
    /// found the way `read` finds it, with where its Start is.
    static func mainRow(_ layout: Layout) -> (row: Row, start: Int)? {
        for row in layout.rows {
            let codes = row.codes
            if codes.first == "when_falls" { continue }
            if let start = codes.firstIndex(of: "start") { return (row, start) }
        }
        return nil
    }

    /// The main row has an End after its Start.
    static func ended(_ layout: Layout) -> Bool {
        guard let (row, start) = mainRow(layout) else { return false }
        return row.codes[start...].contains("end")
    }

    /// A reading that can be held still and used: one card on its own, or a row from Start to End
    /// whose only gap is a Repeat number Studio asks for. A row with no End is not finished yet.
    public static func usable(_ reading: Reading) -> Bool {
        let program = reading.program
        guard !program.steps.isEmpty else { return false }
        switch program.kind {
        case .card: return true
        case .row: return ended(reading.layout)
        case .none: return false
        }
    }

    /// A reading whose row can be saved as a Your card once its Repeat numbers are given.
    public static func savable(_ reading: Reading) -> Bool {
        reading.program.kind == .row && !reading.program.steps.isEmpty && ended(reading.layout)
    }

    /// The number a Repeat question starts at. The person still says it.
    public static let repeatOffered = 2
    /// What a Repeat can be told: one figure in the box on the card.
    public static let repeatRange = 1...repeatMost

    /// The answers to a reading's Repeat questions: what the person gave for each one asked, and
    /// where they gave nothing, the number the question started at; each kept to 1 to 9.
    public static func answers(_ asks: [Int], given: [Int: Int]) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for ask in asks {
            out[ask] = min(max(given[ask] ?? repeatOffered, repeatRange.lowerBound), repeatRange.upperBound)
        }
        return out
    }

    /// WHAT A YOUR CARD HOLDS IS THE ROW AS IT LIES. The main row's cards between Start and End,
    /// left to right, each with the cards under it, in the deck's `example.row` shape. A Repeat
    /// carries its number: the answer given for it (`counts`, by `Program.asks`'s positions),
    /// else the number read off the card, as `read` takes them. A Your card in the row is kept by
    /// its code, so a routine can call a routine. Cards the read skipped are kept too, and read
    /// back the same way, skipped, so the card says what the table said.
    ///
    /// Refused while the row still asks something, has no End, or makes no step.
    public static func savedRow(_ layout: Layout, deck: Deck, counts: [Int: Int] = [:]) throws -> [Entry] {
        guard let (row, start) = mainRow(layout) else { throw Refusal.noRow }
        guard let end = row.codes[start...].firstIndex(of: "end") else { throw Refusal.noEnd }
        let program = read(layout, deck: deck, counts: counts)
        guard program.asks.isEmpty else { throw Refusal.asks(program.asks.count) }
        guard !program.steps.isEmpty else { throw Refusal.empty }
        // Repeats are numbered along the main row from 0, as `times` numbers them.
        var repeats = 0
        return try row.slots[(start + 1)..<end].map { (slot: Slot) throws -> Entry in
            let card = slot.card.card
            var times: Int?
            if card.code == "repeat" {
                let index = repeats
                repeats += 1
                if let given = counts[index], repeatRange.contains(given) {
                    times = given
                } else if let readOff = slot.card.count, repeatRange.contains(readOff) {
                    times = readOff
                } else {
                    throw Refusal.asks(1)
                }
            }
            return Entry(card: card.code, under: slot.under.map(\.card.code), times: times)
        }
    }

    /// The same, for a reading in hand.
    public static func savedRow(_ reading: Reading, deck: Deck, counts: [Int: Int] = [:]) throws -> [Entry] {
        try savedRow(reading.layout, deck: deck, counts: counts)
    }

    /// A saved row laid out the way a reader lays out a table: Start, the row, End. Where each
    /// card lies does not matter to `read`, only what it is and what is under it.
    static func table(_ row: [Entry], deck: Deck) -> Layout? {
        guard let start = deck.card(code: "start"), let end = deck.card(code: "end") else { return nil }
        var slots = [Slot(card: saved(start), under: [])]
        for e in row {
            guard let card = deck.card(code: e.card) else { return nil }
            slots.append(Slot(card: saved(card, times: e.times),
                              under: e.under.compactMap { deck.card(code: $0).map { saved($0) } }))
        }
        slots.append(Slot(card: saved(end), under: []))
        return Layout(rows: [Row(slots: slots)], turned: [])
    }

    // MARK: - the class's deck

    /// STUDIO'S COPY OF THE CLASS'S DECK FILE, KEPT AS A FILE. The cards page's spec puts what a
    /// Your card means in the deck, not in a phone: it starts as the starter deck, and saving a
    /// row writes the Your card's `row`, `name` and `does` into the file with `Deck.replacing`,
    /// keeping everything else the file said. The same bytes are what Studio exports as
    /// `.duckcards`, what another phone opens, and what the duck reads with `--deck`.
    ///
    /// WRITTEN ATOMICALLY AND NEVER EXCLUSIVELY. A save writes the whole file over the last one, and
    /// an atomic write that also refuses to overwrite traps on device
    /// (`scripts/check_no_atomic_exclusive_write.sh`).
    ///
    /// A VALUE, SO THE APP'S STORE PUBLISHES EVERY CHANGE. Each change is written to the file
    /// first and only then kept here, so this and the disk never disagree.
    public struct ClassDeck: Sendable {
        public static let fileExtension = "duckcards"
        /// The name the duck's own README gives it: `--deck class.duckcards`.
        public static let fileName = "class.duckcards"

        /// Where Studio keeps it.
        public let file: URL
        /// The deck a forgotten card goes back to.
        public let starter: Deck
        /// The deck to read cards with.
        public private(set) var deck: Deck {
            didSet { printed = ClassDeck.printedTags(in: deck) }
        }
        /// Said when a file was there and could not be read, so the starter deck is in use.
        public private(set) var problem: String?
        /// The Your cards the deck file marks as printed: the starter deck's blank sheet.
        private var printed: Set<Int>

        public init(file: URL, starter: Deck) {
            self.file = file
            self.starter = starter
            var deck = starter
            var problem: String?
            if FileManager.default.fileExists(atPath: file.path) {
                do {
                    deck = try ClassDeck.read(try Data(contentsOf: file))
                } catch let refusal as Refusal {
                    problem = Words.classDeckUnread(refusal)
                } catch {
                    problem = Words.classDeckUnread(.notADeck(error.localizedDescription))
                }
            }
            self.deck = deck
            self.problem = problem
            self.printed = ClassDeck.printedTags(in: deck)
        }

        /// The class deck at `file`, over the deck this app ships.
        public static func opened(at file: URL) -> ClassDeck? {
            Deck.bundled.map { ClassDeck(file: file, starter: $0) }
        }

        /// A deck file, read the way the duck's reader reads one, refused in its words.
        public static func read(_ data: Data) throws -> Deck {
            do {
                return try Deck.read(data)
            } catch let error as Deck.ReadError {
                switch error {
                case .notADeck(let why), .badCard(let why): throw Refusal.notADeck(why)
                }
            } catch {
                // Not JSON at all: `Deck.read`'s words for anything that is not its format.
                throw Refusal.notADeck("not a \(DuckCards.deckFormat) deck")
            }
        }

        // MARK: what the cards mean

        /// The card at this number when it already means something: a Your card with a row saved
        /// for it, or a card of another kind that a deck put among the Your card numbers.
        public func means(_ tag: Int) -> Card? {
            guard deck.yours.contains(tag), let card = deck.cards[tag] else { return nil }
            if card.kind != "yours" { return card }
            guard let row = card.row, !row.isEmpty else { return nil }
            return card
        }

        /// Every Your card number that means something, in order.
        public var saved: [Card] { deck.yours.compactMap { means($0) } }

        /// THE NUMBERS FREE TO SAVE AS, THE PRINTED BLANKS FIRST. The starter deck prints 200 to
        /// 208; every number to 299 is a Your card too, so they follow, in order.
        public var free: [Int] {
            let open = deck.yours.filter { means($0) == nil }
            return open.filter { printed.contains($0) } + open.filter { !printed.contains($0) }
        }

        /// Every number a card can be saved as: the free ones first, then those that would replace
        /// something.
        public var numbers: [Int] { free + saved.map(\.tag) }

        /// The number a save starts at: the first free one that no saved card already holds, since
        /// a blank another card calls is one somebody meant to fill.
        public var suggested: Int? {
            free.first { heldBy($0).isEmpty } ?? free.first
        }

        /// Whether the deck file marks this card as printed.
        public func isPrinted(_ tag: Int) -> Bool { printed.contains(tag) }

        /// The Your cards whose rows hold this one, by number.
        public func heldBy(_ tag: Int) -> [Int] {
            guard let code = deck.card(tag)?.code else { return [] }
            return saved.filter { card in (card.row ?? []).contains { $0.card == code } }.map(\.tag)
        }

        /// The card read on a row of its own, Start, the card, End: what the duck does for it.
        public func reads(_ tag: Int) -> Program? {
            guard let card = deck.card(tag), let layout = DuckCards.table([Entry(card: card.code)], deck: deck)
            else { return nil }
            return DuckCards.read(layout, deck: deck)
        }

        // MARK: saving

        /// Write a row into the deck as a Your card's meaning. Refused for an empty name, a number
        /// outside the Your cards, an empty row, a row that would hold the card itself or go past
        /// four Your cards deep, and, unless `replacing`, a number that already means something:
        /// `means` says so first, so a screen can ask. Saved, the card reads back through `read` to
        /// the row's own steps, or it is not saved at all.
        @discardableResult
        public mutating func save(row: [Entry], asCard tag: Int, name: String, does: String? = nil,
                                  replacing: Bool = false) throws -> Card {
            let named = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !named.isEmpty else { throw Refusal.noName }
            guard deck.yours.contains(tag), let blank = deck.card(tag) else { throw Refusal.notYours(tag, deck.yours) }
            guard !row.isEmpty else { throw Refusal.empty }
            if let through = leadsBack(row, to: tag) {
                throw through == tag ? Refusal.holdsItself(tag) : Refusal.loop(tag, through: through)
            }
            var entry = ClassDeck.entry(tag, in: deck.source) ?? [:]
            entry["tag"] = tag
            entry["code"] = blank.code
            entry["category"] = "yours"
            entry["kind"] = "yours"
            if entry["plan"] == nil { entry["plan"] = NSNull() }
            entry["name"] = named
            entry["row"] = row.map(\.json)
            let said = (does ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if said.isEmpty { entry.removeValue(forKey: "does") } else { entry["does"] = said }
            let next: Deck
            do {
                next = try deck.replacing([entry])
            } catch let error as Deck.ReadError {
                switch error {
                case .notADeck(let why), .badCard(let why): throw Refusal.notADeck(why)
                }
            } catch {
                throw Refusal.notADeck("not a \(DuckCards.deckFormat) deck")
            }
            guard ClassDeck.depth(of: tag, in: next) <= DuckCards.yoursDepth else { throw Refusal.tooDeep(tag) }
            // THE ROUND TRIP, CHECKED BEFORE IT IS KEPT: the card on a row of its own reads to the
            // steps the row read to on the table.
            guard let table = DuckCards.table(row, deck: deck), let alone = DuckCards.table([Entry(card: blank.code)], deck: next),
                  DuckCards.read(table, deck: deck).steps == DuckCards.read(alone, deck: next).steps
            else { throw Refusal.readsDifferently(tag) }
            if !replacing, let held = means(tag) { throw Refusal.wouldReplace(held) }
            try keep(next)
            return next.card(tag) ?? blank
        }

        /// Take a card's meaning away: a printed blank goes back to the starter deck's own entry, a
        /// number the starter deck does not list leaves the file. A card holding it then says it
        /// has no meaning saved, as the reader says of any blank.
        public mutating func forget(_ tag: Int) throws {
            guard means(tag) != nil else { throw Refusal.notSaved(tag) }
            guard var top = (try? JSONSerialization.jsonObject(with: deck.source)) as? [String: Any],
                  let rows = top["cards"] as? [[String: Any]]
            else { throw Refusal.notADeck("not a \(DuckCards.deckFormat) deck") }
            var byTag: [Int: [String: Any]] = [:]
            for c in rows { if let t = c["tag"] as? Int { byTag[t] = c } }
            byTag[tag] = ClassDeck.entry(tag, in: starter.source)
            top["cards"] = byTag.keys.sorted().compactMap { byTag[$0] }
            let data: Data
            do {
                data = try JSONSerialization.data(withJSONObject: top, options: [.prettyPrinted, .sortedKeys])
            } catch {
                throw Refusal.notADeck("not a \(DuckCards.deckFormat) deck")
            }
            try keep(try ClassDeck.read(data))
        }

        // MARK: sharing

        /// The bytes of a `.duckcards` file: the class's deck file, as Studio keeps it.
        public var exported: Data { deck.source }

        /// What opening a deck file did.
        public struct Taken: Equatable, Sendable {
            /// The Your cards the opened deck gives a meaning to, by number.
            public let cards: [Card]
            /// Cards this deck meant something by that the opened one does not mean the same way.
            public let replaced: [Card]
        }

        /// A deck file from another phone, through the import door. Read the way the duck reads
        /// one and refused in its words; taken whole, byte for byte, as this phone's class deck.
        @discardableResult
        public mutating func take(_ data: Data) throws -> Taken {
            let next = try ClassDeck.read(data)
            let before = saved
            try keep(next)
            let after = saved
            return Taken(cards: after, replaced: before.filter { !after.contains($0) })
        }

        // MARK: the file

        mutating func keep(_ next: Deck) throws {
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try next.source.write(to: file, options: .atomic)
            } catch {
                throw Refusal.notWritten(error.localizedDescription)
            }
            deck = next
            problem = nil
        }

        /// One card's entry, as the deck file spells it.
        static func entry(_ tag: Int, in source: Data) -> [String: Any]? {
            guard let top = (try? JSONSerialization.jsonObject(with: source)) as? [String: Any],
                  let rows = top["cards"] as? [[String: Any]] else { return nil }
            return rows.first { ($0["tag"] as? Int) == tag }
        }

        static func printedTags(in deck: Deck) -> Set<Int> {
            guard let top = (try? JSONSerialization.jsonObject(with: deck.source)) as? [String: Any],
                  let rows = top["cards"] as? [[String: Any]] else { return [] }
            return Set(rows.compactMap { c in
                guard let tag = c["tag"] as? Int, deck.yours.contains(tag), (c["printed"] as? Bool) == true else { return nil }
                return tag
            })
        }

        /// The first Your card in the row that leads back to `tag`, or `tag` itself when the row
        /// holds it, following meanings as the deck stands now.
        func leadsBack(_ row: [Entry], to tag: Int) -> Int? {
            func reaches(_ card: Int, _ seen: Set<Int>) -> Bool {
                if card == tag { return true }
                guard !seen.contains(card), let inner = deck.card(card)?.row else { return false }
                return inner.contains { e in
                    guard let c = deck.card(code: e.card), c.kind == "yours" else { return false }
                    return reaches(c.tag, seen.union([card]))
                }
            }
            for e in row {
                guard let c = deck.card(code: e.card), c.kind == "yours" else { continue }
                if reaches(c.tag, []) { return c.tag }
            }
            return nil
        }

        /// How many Your cards deep a card goes when it is read: itself and the longest run of
        /// Your cards with a meaning inside it, cut where one would hold itself, as `open` cuts.
        static func depth(of tag: Int, in deck: Deck) -> Int {
            func down(_ tag: Int, _ path: [Int]) -> Int {
                guard !path.contains(tag), let row = deck.card(tag)?.row, !row.isEmpty else { return 0 }
                var most = 0
                for e in row {
                    guard let c = deck.card(code: e.card), c.kind == "yours" else { continue }
                    most = max(most, down(c.tag, path + [tag]))
                }
                return 1 + most
            }
            return down(tag, [])
        }
    }
}

extension DuckIntentPlan.RouterIdentity {
    /// DUCK CARDS AS THE PROPOSER, PINNED TO THE DECK THEY WERE READ WITH. A plan read off cards
    /// is a proposal like one read off a sentence, and its records name what read it: the card
    /// reader (`duck-cards/0`) and the sha256 of the deck file, because a class's Your cards are
    /// part of what the cards meant.
    public static func cards(_ deck: DuckCards.Deck) -> DuckIntentPlan.RouterIdentity {
        DuckIntentPlan.RouterIdentity(model: DuckCards.model,
                                      revision: "deck sha256 " + String(DuckPolicyInstall.digest(of: deck.source).prefix(12)))
    }
}

extension DuckIntentPlan {
    /// A plan read somewhere other than the editor and handed to it to be checked: the plan, who
    /// proposed it, and the reader's notes on what it read. The editor shows it as proposed;
    /// nothing moves until the person runs it.
    public struct Handed: Equatable, Sendable {
        public let plan: DuckIntentPlan
        public let by: RouterIdentity
        public let notes: [String]
        public init(plan: DuckIntentPlan, by: RouterIdentity, notes: [String] = []) {
            self.plan = plan; self.by = by; self.notes = notes
        }
    }
}

extension DuckCards {
    /// A reading as the plan editor takes it: `intentPlan`, so the editor shows the format's own
    /// plan, proposed by the cards and the deck they were read with, under the reader's notes.
    /// Refused, in `DuckIntentPlan.read`'s words, for a reading with no step.
    public static func handed(_ reading: Reading, deck: Deck) throws -> DuckIntentPlan.Handed {
        DuckIntentPlan.Handed(plan: try intentPlan(reading.program), by: .cards(deck),
                              notes: Words.planNotes(reading.program))
    }
}
