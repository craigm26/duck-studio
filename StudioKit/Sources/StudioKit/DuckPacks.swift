import Foundation

/// Duck Card packs: a game for the cards, set for a grade band, and the board it is played on.
///
/// A pack is one JSON file, `duck-pack/0`, shared as `.duckpack` (docs/PACKS.md is the spec): the
/// cards in play, a board, a ramp of challenges and the teacher's lessons. This reads one and
/// refuses it in sentences a teacher can act on; `DuckPackBoard.swift` plays a row on a
/// challenge's board and works out par.
///
/// THE SAME PACK TWICE, HELD TO ONE SET OF ANSWERS. The duck's card reader reads packs with
/// `cardreader/duckcards/packs.py`; this is that file in Swift, for Studio. Both play the vectors in
/// `cardreader/vectors/pack_*.json` to the same JSON, and `DuckPacksTests` reads every one.
///
/// THE BOARD RULE IS EXACT; THE DUCK IS NOT. One Walk card is one square and one Turn card a
/// quarter turn, on the board. A Microduck walks for a time and drifts, so nothing here says where a
/// real duck would stop: `Board.duckSquareCm` is nil until someone measures it.
public enum DuckPacks {

    public static let format = "duck-pack/0"
    public static let fileExtension = "duckpack"
    /// A board this size still fits a classroom floor in 30 cm squares, and keeps the search small.
    public static let largestBoard = 12
    /// The cards that move the duck on the board. Everything else is a step taken standing still.
    public static let moves = ["walk_forward", "walk_backward", "turn_left", "turn_right"]

    // MARK: - the model

    public enum Facing: String, CaseIterable, Sendable {
        case north, east, south, west
        /// Which way this facing moves on the printed board: x grows to the right, y down the page.
        public var ahead: (dx: Int, dy: Int) {
            switch self {
            case .north: return (0, -1)
            case .east: return (1, 0)
            case .south: return (0, 1)
            case .west: return (-1, 0)
            }
        }
        /// A quarter turn: -1 to the left, 1 to the right.
        public func turned(_ by: Int) -> Facing {
            let all = Facing.allCases
            return all[((all.firstIndex(of: self)! + by) % 4 + 4) % 4]
        }
    }

    /// A square, `[x, y]` in the file: x from 0 at the left, y from 0 at the top.
    public struct Square: Hashable, Sendable {
        public let x: Int, y: Int
        public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
        public var json: [Int] { [x, y] }
    }

    public struct Place: Equatable, Sendable {
        public let at: Square
        public let facing: Facing
        public init(at: Square, facing: Facing) { self.at = at; self.facing = facing }
        public var json: [String: Any] { ["at": at.json, "facing": facing.rawValue] }
    }

    public enum Axis: String, Sendable { case ns, ew }

    /// A gate (the tunnel) is passed when the duck walks into its square moving along its axis.
    public struct Gate: Equatable, Sendable {
        public let at: Square
        public let axis: Axis
    }

    /// A wall between two squares that share an edge, the same whichever is named first.
    public struct Wall: Hashable, Sendable {
        public let squares: Set<Square>
        public init(_ a: Square, _ b: Square) { squares = [a, b] }
    }

    public enum Score: String, Sendable {
        /// Fewest board steps, the floor robot's rule.
        case steps
        /// Fewest cards in the row, where Repeat and Your cards pay off.
        case cards
    }

    public struct Board: Equatable, Sendable {
        public let columns: Int, rows: Int
        /// The printed or taped floor square, for people.
        public let squareCm: Double
        /// How far one Walk forward carries a duck, measured; nil until it is.
        public let duckSquareCm: Double?
    }

    public struct Lesson: Equatable, Sendable {
        public let title: String, skill: String, body: String, ask: String
    }

    public struct Challenge: Equatable, Sendable {
        public let id: String
        public let name: String
        public let columns: Int, rows: Int
        public let start: Place
        public let goal: Square
        public let walls: Set<Wall>
        public let gates: [Gate]
        /// A card that must be the last step, like Hello at the pond.
        public let finishWith: String?
        public let par: Int
        /// One row that solves it, between Start and End, in the deck's `example.row` shape.
        public let solution: [DuckCards.Entry]
        /// A row one card swap away from a solution, for Find the bug.
        public let buggy: [DuckCards.Entry]?
        public let hint: String
    }

    public struct Pack: Sendable {
        public let id: String
        public let name: String
        public let grades: String
        /// PreK is -1, K is 0, then 1 to 12.
        public let gradeFrom: Int, gradeTo: Int
        public let vocabulary: String
        public let license: String
        public let credit: String
        public let about: String
        /// The card codes in play. A card not in play still runs; a reader says it is not in the game.
        public let cards: [String]
        public let score: Score
        public let board: Board
        public let challenges: [Challenge]
        public let lessons: [Lesson]
        /// Your cards this pack lends, read the way a deck file carries them.
        public let yours: [DuckCards.Card]
        /// The file it was read from, so Studio shares the same bytes it opened.
        public let source: Data

        public func challenge(_ id: String) -> Challenge? { challenges.first { $0.id == id } }

        /// The cards among `codes` this pack does not play, in the words a reader says them.
        public func notInPlay(_ codes: [String], deck: DuckCards.Deck) -> [String] {
            var seen: Set<String> = [], out: [String] = []
            for code in codes where !seen.contains(code) {
                seen.insert(code)
                if !cards.contains(code) { out.append("\(deck.card(code: code)?.name ?? code) is not in \(name).") }
            }
            return out
        }

        /// The deck with this pack's Your cards in it (`DuckPacks.lend`).
        public func lent(to deck: DuckCards.Deck, replacing: Bool = false) throws -> (deck: DuckCards.Deck, clashes: [Int]) {
            try DuckPacks.lend(yours, to: deck, replacing: replacing)
        }

        public static func read(_ data: Data, deck: DuckCards.Deck) throws -> Pack {
            try DuckPacks.read(data, deck: deck)
        }
    }

    /// Why a pack was not opened, in a sentence that says what to fix.
    public enum Refusal: Error, Equatable, Sendable {
        case notAPack(String)
        public var message: String {
            switch self { case .notAPack(let why): return why }
        }
    }

    // MARK: - the packs this app ships

    static var packsURL: URL? { Bundle.module.url(forResource: "DuckPacks", withExtension: nil) }

    /// The starter packs, youngest grades first. Empty if the deck or the files did not load,
    /// which `DuckPacksTests` would have said first.
    public static let bundled: [Pack] = {
        guard let deck = DuckCards.Deck.bundled, let dir = packsURL,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        let packs = files.filter { $0.pathExtension == fileExtension }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? read($0, deck: deck) } }
        return packs.sorted { ($0.gradeFrom, $0.gradeTo, $0.id) < ($1.gradeFrom, $1.gradeTo, $1.id) }
    }()

    // MARK: - lending Your cards

    /// A deck with a pack's Your cards in it, the way a class's deck file lends its own.
    ///
    /// A CLASS'S OWN CARD IS NOT WRITTEN OVER WITHOUT ASKING. Where the class already saved a
    /// different row for the same number, that card keeps the class's meaning unless `replacing`;
    /// the numbers come back either way, so a screen can ask.
    public static func lend(_ yours: [DuckCards.Card], to deck: DuckCards.Deck,
                            replacing: Bool = false) throws -> (deck: DuckCards.Deck, clashes: [Int]) {
        var clashes: [Int] = [], lent: [[String: Any]] = []
        for y in yours {
            if let have = deck.cards[y.tag]?.row, !have.isEmpty, have != (y.row ?? []) {
                clashes.append(y.tag)
                if !replacing { continue }
            }
            var entry: [String: Any] = ["tag": y.tag, "code": y.code, "name": y.name, "category": "yours",
                                        "kind": "yours", "plan": NSNull(), "row": (y.row ?? []).map(\.json)]
            if let does = y.does { entry["does"] = does }
            lent.append(entry)
        }
        guard !lent.isEmpty else { return (deck, clashes) }
        do {
            return (try deck.replacing(lent), clashes)
        } catch let error as DuckCards.Deck.ReadError {
            switch error {
            case .notADeck(let why), .badCard(let why):
                throw Refusal.notAPack("A Your card in this pack cannot be read: \(why).")
            }
        }
    }

    // MARK: - reading a pack

    static func need(_ ok: Bool, _ message: @autoclosure () -> String) throws {
        if !ok { throw Refusal.notAPack(message()) }
    }

    static func text(_ d: [String: Any], _ key: String, _ whereIs: String) throws -> String {
        let v = d[key] as? String
        try need(v.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false,
                 "\(whereIs) needs \(key), written as words.")
        return v!
    }

    /// A JSON true is not the number 1. JSONSerialization hands back NSNumber for both, and `is
    /// Bool` says yes to any NSNumber that is 0 or 1, so the number's own type code decides.
    static func isBool(_ v: Any) -> Bool {
        guard let n = v as? NSNumber else { return v is Bool }
        let code = String(cString: n.objCType)
        return code == "c" || code == "B"
    }

    static func int(_ v: Any?) -> Int? {
        guard let v, !(v is NSNull), !isBool(v), let n = v as? NSNumber else { return nil }
        // 30.0 is not a whole number to the duck's reader either: Python's json reads it as a float.
        let code = String(cString: n.objCType)
        return code == "d" || code == "f" ? nil : n.intValue
    }

    static func number(_ v: Any?) -> Double? {
        guard let v, !(v is NSNull), !isBool(v) else { return nil }
        return (v as? NSNumber)?.doubleValue
    }

    static let idPattern = try! NSRegularExpression(pattern: "^[a-z0-9]+(-[a-z0-9]+)*$")
    static func isID(_ s: String?) -> Bool {
        guard let s else { return false }
        return idPattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func square(_ v: Any?, columns: Int, rows: Int, _ whereIs: String, _ what: String) throws -> Square {
        let list = v as? [Any]
        let xy = list?.compactMap { int($0) } ?? []
        try need(list?.count == 2 && xy.count == 2, "\(whereIs): \(what) needs a square written as [x, y].")
        try need((0..<columns).contains(xy[0]) && (0..<rows).contains(xy[1]),
                 "\(whereIs): \(what) [\(xy[0]), \(xy[1])] is off the \(columns) x \(rows) board.")
        return Square(xy[0], xy[1])
    }

    static func row(_ v: Any?, deck: DuckCards.Deck, _ whereIs: String, _ what: String) throws -> [DuckCards.Entry] {
        guard let list = v as? [Any] else { throw Refusal.notAPack("\(whereIs): \(what) is a list of cards.") }
        return try list.map { item in
            guard let e = item as? [String: Any], let code = e["card"] as? String else {
                throw Refusal.notAPack("\(whereIs): every card in \(what) needs a card code.")
            }
            let rawUnder = e["under"] ?? [String]()
            guard let under = rawUnder as? [String] else {
                throw Refusal.notAPack("\(whereIs): under \(code) in \(what) is not a list of card codes.")
            }
            for c in [code] + under where deck.card(code: c) == nil {
                throw Refusal.notAPack("\(whereIs): \(what) holds '\(c)', which is not a card in the deck.")
            }
            let rawTimes = e["times"].flatMap { $0 is NSNull ? nil : $0 }
            let times = int(rawTimes)
            if code == "repeat" {
                try need(times.map { (1...DuckCards.repeatMost).contains($0) } ?? false,
                         "\(whereIs): a Repeat in \(what) needs times, 1 to \(DuckCards.repeatMost).")
            } else {
                try need(rawTimes == nil, "\(whereIs): only a Repeat takes times, and \(what) gives one to \(code).")
            }
            try need(code != "start" && code != "end",
                     "\(whereIs): \(what) is the row between Start and End, so it leaves them out.")
            return DuckCards.Entry(card: code, under: under, times: times)
        }
    }

    /// One challenge, read strictly. Internal so a vector, which carries a challenge on its own,
    /// is read by exactly the rules a pack's challenges are.
    static func challenge(_ any: Any, board: Board, cards: [String], deck: DuckCards.Deck, number n: Int) throws -> Challenge {
        guard let c = any as? [String: Any] else { throw Refusal.notAPack("Challenge \(n) is not written as a challenge.") }
        let id = c["id"] as? String
        try need(isID(id), "Challenge \(n) needs an id in small letters, numbers and dashes, like pond-3.")
        let w = id!
        let name = try text(c, "name", w)
        let columns = c["columns"] == nil ? board.columns : int(c["columns"])
        let rows = c["rows"] == nil ? board.rows : int(c["rows"])
        try need(columns.map { (1...largestBoard).contains($0) } == true && rows.map { (1...largestBoard).contains($0) } == true,
                 "\(w): a board is 1 to \(largestBoard) squares each way.")
        let cols = columns!, rws = rows!
        guard let start = c["start"] as? [String: Any] else { throw Refusal.notAPack("\(w) needs a start: a square and a facing.") }
        let at = try square(start["at"], columns: cols, rows: rws, w, "the start")
        guard let facing = (start["facing"] as? String).flatMap(Facing.init(rawValue:)) else {
            throw Refusal.notAPack("\(w): the start faces north, east, south or west.")
        }
        let goal = try square(c["goal"], columns: cols, rows: rws, w, "the goal")
        var walls: Set<Wall> = []
        for item in (c["walls"] as? [Any]) ?? [] {
            let between = (item as? [String: Any])?["between"] as? [Any]
            try need(between?.count == 2, "\(w): a wall sits between two squares.")
            let a = try square(between![0], columns: cols, rows: rws, w, "a wall")
            let b = try square(between![1], columns: cols, rows: rws, w, "a wall")
            try need(abs(a.x - b.x) + abs(a.y - b.y) == 1,
                     "\(w): a wall sits between two squares that share an edge, and [\(a.x), \(a.y)] and [\(b.x), \(b.y)] do not.")
            walls.insert(Wall(a, b))
        }
        var gates: [Gate] = []
        for item in (c["gates"] as? [Any]) ?? [] {
            guard let g = item as? [String: Any] else { throw Refusal.notAPack("\(w): a gate needs a square and an axis.") }
            let gat = try square(g["at"], columns: cols, rows: rws, w, "a gate")
            guard let axis = (g["axis"] as? String).flatMap(Axis.init(rawValue:)) else {
                throw Refusal.notAPack("\(w): a gate's axis is ns or ew.")
            }
            try need(gat != at, "\(w): a gate on the start square can never be walked into.")
            gates.append(Gate(at: gat, axis: axis))
        }
        var finish: String?
        if let f = c["finish_with"], !(f is NSNull) {
            try need((f as? String).map { cards.contains($0) } ?? false, "\(w): finish_with must be a card in play.")
            let code = f as! String
            try need(!moves.contains(code) && !["start", "end", "repeat", "end_repeat"].contains(code),
                     "\(w): finish_with is a card the duck does standing still, like Hello.")
            finish = code
        }
        let par = int(c["par"])
        try need(par.map { $0 >= 0 } ?? false, "\(w) needs a par, a whole number.")
        let solution = try row(c["solution"], deck: deck, w, "the solution")
        var buggy: [DuckCards.Entry]?
        if let b = c["buggy"], !(b is NSNull) { buggy = try row(b, deck: deck, w, "the buggy row") }
        let hint = try text(c, "hint", w)
        return Challenge(id: w, name: name, columns: cols, rows: rws, start: Place(at: at, facing: facing), goal: goal,
                         walls: walls, gates: gates, finishWith: finish, par: par!, solution: solution, buggy: buggy,
                         hint: hint)
    }

    static func yourCards(_ any: Any?, deck: DuckCards.Deck) throws -> [DuckCards.Card] {
        let list: [Any]
        if any == nil || any is NSNull { list = [] } else {
            guard let l = any as? [Any] else { throw Refusal.notAPack("The pack's yours is a list of Your cards.") }
            list = l
        }
        let range = deck.yours
        var out: [DuckCards.Card] = []
        for item in list {
            let y = item as? [String: Any]
            let tag = int(y?["tag"])
            try need(tag.map { range.contains($0) } == true && (y?["kind"] as? String) == "yours",
                     "Every card in yours is a Your card, numbered \(range.lowerBound) to \(range.upperBound).")
            let code = deck.card(tag!)!.code
            try need((y?["code"] as? String) == code,
                     "Your card \(tag!) is called \(code), not \(quoted(y?["code"])).")
            try need(((y?["row"] as? [Any])?.count ?? 0) > 0, "Your card \(tag!) in this pack needs the row it stands for.")
            let name = try text(y!, "name", "Your card \(tag!)")
            let row: [DuckCards.Entry]?
            do {
                row = try DuckCards.Deck.entries(code, y?["row"])
            } catch let error as DuckCards.Deck.ReadError {
                switch error {
                case .notADeck(let why), .badCard(let why):
                    throw Refusal.notAPack("A Your card in this pack cannot be read: \(why).")
                }
            }
            out.append(DuckCards.Card(tag: tag!, code: code, name: name, category: "yours", kind: "yours", plan: nil,
                                      row: row, does: y?["does"] as? String))
        }
        try need(Set(out.map(\.tag)).count == out.count, "Two Your cards in this pack have the same number.")
        return out
    }

    /// How Python's `repr` writes a value a refusal quotes: 'text', or None.
    static func quoted(_ v: Any?) -> String {
        if let s = v as? String { return "'\(s)'" }
        return "None"
    }

    static func read(_ data: Data, deck: DuckCards.Deck) throws -> Pack {
        guard let any = try? JSONSerialization.jsonObject(with: data) else {
            throw Refusal.notAPack("This file is not a Duck Cards pack: it is not JSON.")
        }
        guard let top = any as? [String: Any], (top["format"] as? String) == format else {
            throw Refusal.notAPack("This file is not a Duck Cards pack: its format is not \(format).")
        }
        try need(isID(top["id"] as? String), "The pack needs an id in small letters, numbers and dashes, like get-to-the-pond.")
        var words: [String: String] = [:]
        for key in ["name", "grades", "about", "license", "credit"] { words[key] = try text(top, key, "The pack") }
        let lo = int(top["grade_from"]), hi = int(top["grade_to"])
        try need(lo.map { (-1...12).contains($0) } == true && hi.map { (-1...12).contains($0) } == true && lo! <= hi!,
                 "The pack's grades run from grade_from to grade_to: PreK is -1, K is 0, then 1 to 12.")
        let deckVocabulary = deckVocabulary(deck)
        try need((top["vocabulary"] as? String) == deckVocabulary,
                 "The pack is written for vocabulary \(quoted(top["vocabulary"])), and this deck is \(quoted(deckVocabulary)).")
        guard let score = (top["score"] as? String).flatMap(Score.init(rawValue:)) else {
            throw Refusal.notAPack("The pack's score is steps or cards.")
        }

        // Your cards first: a solution may hold them, so the deck it is read against must have them.
        let yours = try yourCards(top["yours"], deck: deck)
        let played = try lend(yours, to: deck, replacing: true).deck

        guard let cards = top["cards"] as? [String] else { throw Refusal.notAPack("The pack's cards is a list of card codes.") }
        for code in cards where played.card(code: code) == nil {
            throw Refusal.notAPack("The pack plays '\(code)', which is not a card in the deck.")
        }
        try need(Set(cards).count == cards.count, "The pack names a card in play twice.")
        try need(cards.contains("start") && cards.contains("end"), "Every pack plays Start and End.")

        guard let b = top["board"] as? [String: Any] else { throw Refusal.notAPack("The pack needs a board.") }
        let columns = int(b["columns"]), rows = int(b["rows"])
        try need(columns.map { (1...largestBoard).contains($0) } == true && rows.map { (1...largestBoard).contains($0) } == true,
                 "The pack's board is 1 to \(largestBoard) squares each way.")
        let square = number(b["square_cm"])
        try need(square.map { $0 > 0 } ?? false, "The board's square_cm is the size of a printed square, in centimetres.")
        let rawDuck = b["duck_square_cm"].flatMap { $0 is NSNull ? nil : $0 }
        let duck = number(rawDuck)
        try need(rawDuck == nil || (duck.map { $0 > 0 } ?? false),
                 "duck_square_cm is null until one Walk forward has been measured, then centimetres.")
        let board = Board(columns: columns!, rows: rows!, squareCm: square!, duckSquareCm: duck)

        guard let raw = top["challenges"] as? [Any], !raw.isEmpty else {
            throw Refusal.notAPack("The pack needs at least one challenge.")
        }
        let challenges = try raw.enumerated().map {
            try challenge($0.element, board: board, cards: cards, deck: played, number: $0.offset + 1)
        }
        try need(Set(challenges.map(\.id)).count == challenges.count, "Two challenges in this pack have the same id.")

        var lessons: [Lesson] = []
        for item in (top["lessons"] as? [Any]) ?? [] {
            guard let l = item as? [String: Any] else {
                throw Refusal.notAPack("Every lesson has a title, a skill, a body and a question to ask.")
            }
            lessons.append(Lesson(title: try text(l, "title", "A lesson"), skill: try text(l, "skill", "A lesson"),
                                  body: try text(l, "body", "A lesson"), ask: try text(l, "ask", "A lesson")))
        }
        return Pack(id: top["id"] as! String, name: words["name"]!, grades: words["grades"]!, gradeFrom: lo!, gradeTo: hi!,
                    vocabulary: deckVocabulary!, license: words["license"]!, credit: words["credit"]!,
                    about: words["about"]!, cards: cards, score: score, board: board, challenges: challenges,
                    lessons: lessons, yours: yours, source: data)
    }

    /// The deck's `vocabulary`, read from the file it came from: `DuckCards.Deck` keeps the cards,
    /// and the vocabulary is the one other thing a pack is held to.
    static func deckVocabulary(_ deck: DuckCards.Deck) -> String? {
        ((try? JSONSerialization.jsonObject(with: deck.source)) as? [String: Any])?["vocabulary"] as? String
    }
}
