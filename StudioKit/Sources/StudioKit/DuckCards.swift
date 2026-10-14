import Foundation

/// Duck Cards, read off a picture: codes become cards, cards become rows, rows
/// become the plan this app already runs.
///
/// THE SAME READER TWICE, HELD TO ONE SET OF ANSWERS. The duck reads cards for
/// itself with `cardreader/` (Python, on the robot beside the bridge); this is
/// that reader in Swift, for Studio reading the duck's own camera. Both take
/// what the AprilTag library found — an id and four corners per code — and
/// must make the same rows, words, notes and plan of it. `cardreader/vectors`
/// is the contract: eighteen cases, three of them the library's own answers to
/// simulated duck-camera pictures, copied into this package's fixtures byte for
/// byte, and `DuckCardsTests` reads every one. A rule changed in one reader
/// and not the other fails there, not in a classroom.
///
/// THE PLAN IS `duck-intent-plan/0`, WITH `model: "duck-cards/0"`. A card is
/// not a guess, so every label goes at confidence 1.0 and nothing is flagged;
/// the plan editor still shows the whole chain before anything moves, because
/// a row read by a camera is a proposal like a sentence read by a router.
///
/// WHERE THE CARD IS, FROM WHERE ITS CODE IS. The code's black square is 19.2%
/// of the card's width at a fixed place in its bottom right corner
/// (microduckstudio.com's `site.css`, every size a share of the card's width):
/// in card units 100 wide and 140 tall, the square runs 73.9 to 93.1 across
/// and 109.3 to 128.5 down. One square, at any size and turned any way, says
/// where its card is and which way is up on it.
public enum DuckCards {

    public static let deckFormat = "duck-cards/0"
    public static let model = "duck-cards/0"

    /// Internal so the sha256 pin reads the file the app ships, not a test copy of it.
    static var deckURL: URL? { Bundle.module.url(forResource: "DuckCards/duck-cards", withExtension: "json") }

    // MARK: - the card's geometry, in its own units

    static let cardWidth = 100.0, cardHeight = 140.0
    static let squareLeft = 73.9, squareTop = 109.3, squareRight = 93.1, squareBottom = 128.5
    static var squareSide: Double { squareRight - squareLeft }
    static var centreRight: Double { (cardWidth / 2 - (squareLeft + squareRight) / 2) / squareSide }
    static var centreDown: Double { (cardHeight / 2 - (squareTop + squareBottom) / 2) / squareSide }
    static var widthInSquares: Double { cardWidth / squareSide }
    static var heightInSquares: Double { cardHeight / squareSide }

    // MARK: - the deck

    public struct Card: Equatable, Sendable {
        public let tag: Int
        public let code: String
        public let name: String
        public let category: String
        /// action, modifier, control, event, yours
        public let kind: String
        /// The labels this card puts into a plan, as the deck says; nil for a card that shapes a
        /// row rather than moving the duck.
        public let plan: [String: String]?
    }

    public struct Deck: Sendable {
        public let cards: [Int: Card]
        public let yours: ClosedRange<Int>

        public enum ReadError: Error, Equatable { case notADeck(String) }

        public static func read(_ data: Data) throws -> Deck {
            guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (top["format"] as? String) == DuckCards.deckFormat,
                  let rows = top["cards"] as? [[String: Any]],
                  let cats = top["categories"] as? [[String: Any]]
            else { throw ReadError.notADeck("not a \(DuckCards.deckFormat) deck") }
            var cards: [Int: Card] = [:]
            for c in rows {
                guard let tag = c["tag"] as? Int, let code = c["code"] as? String,
                      let name = c["name"] as? String, let category = c["category"] as? String,
                      let kind = c["kind"] as? String else { continue }
                cards[tag] = Card(tag: tag, code: code, name: name, category: category, kind: kind,
                                  plan: c["plan"] as? [String: String])
            }
            let range = (cats.first { $0["id"] as? String == "yours" }?["codes"] as? [Int]) ?? [200, 299]
            return Deck(cards: cards, yours: range[0]...range[1])
        }

        /// The deck this app ships: microduckstudio.com's `duck-cards.json`, byte for byte.
        public static let bundled: Deck? = {
            guard let url = DuckCards.deckURL, let data = try? Data(contentsOf: url) else { return nil }
            return try? read(data)
        }()

        /// A Your card the starter deck did not print is still a Your card: the whole range is set
        /// aside for them, so a class that made a tenth one has not made a stranger's code.
        public func card(_ tag: Int) -> Card? {
            if let c = cards[tag] { return c }
            guard yours.contains(tag) else { return nil }
            return Card(tag: tag, code: "card_\(tag - yours.lowerBound + 1)", name: "Your card",
                        category: "yours", kind: "yours", plan: nil)
        }

        public func card(code: String) -> Card? { cards.values.first { $0.code == code } }
    }

    // MARK: - one code, found

    public struct Point: Equatable, Sendable {
        public var x: Double, y: Double
        public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
        static func + (a: Point, b: Point) -> Point { Point(a.x + b.x, a.y + b.y) }
        static func - (a: Point, b: Point) -> Point { Point(a.x - b.x, a.y - b.y) }
        static func * (a: Point, k: Double) -> Point { Point(a.x * k, a.y * k) }
        func dot(_ b: Point) -> Double { x * b.x + y * b.y }
        var length: Double { (x * x + y * y).squareRoot() }
        var unit: Point { length > 0 ? self * (1 / length) : Point(1, 0) }
    }

    /// What the AprilTag library answered for one code. Corners in the library's order: for a code
    /// drawn upright, top right, top left, bottom left, bottom right.
    public struct Detection: Equatable, Sendable {
        public let id: Int
        public let hamming: Int
        public let margin: Double
        public let corners: [Point]
        public init(id: Int, hamming: Int, margin: Double, corners: [Point]) {
            self.id = id; self.hamming = hamming; self.margin = margin; self.corners = corners
        }
    }

    /// A code read with at most one bit corrected and a margin the library calls confident. A false
    /// card is a duck doing something nobody asked for, so tag36h11's wider correction is not used.
    public static let maxHamming = 1
    public static let minMargin = 20.0

    public struct Seen: Sendable {
        public let card: Card
        public let corners: [Point]
        public let centre: Point
        public let right: Point      // one square to the card's right, in pixels
        public let down: Point       // one square down the card, in pixels
        public let cardCentre: Point
    }

    public static func place(_ card: Card, corners p: [Point]) -> Seen {
        let (tr, tl, bl, br) = (p[0], p[1], p[2], p[3])
        let right = ((tr - tl) + (br - bl)) * 0.5
        let down = ((bl - tl) + (br - tr)) * 0.5
        let centre = (tr + tl + bl + br) * 0.25
        let cardCentre = centre + right * centreRight + down * centreDown
        return Seen(card: card, corners: p, centre: centre, right: right, down: down, cardCentre: cardCentre)
    }

    public struct Look: Sendable {
        public let seen: [Seen]
        /// Codes found that are not Duck Cards.
        public let foreign: Int
        /// Duck Card codes found but not trusted.
        public let doubtful: Int
    }

    public static func look(_ found: [Detection], deck: Deck) -> Look {
        var seen: [Seen] = [], foreign = 0, doubtful = 0
        for d in found {
            guard let card = deck.card(d.id) else { foreign += 1; continue }
            guard d.hamming <= maxHamming, d.margin >= minMargin, d.corners.count == 4 else {
                doubtful += 1; continue
            }
            seen.append(place(card, corners: d.corners))
        }
        return Look(seen: seen, foreign: foreign, doubtful: doubtful)
    }

    // MARK: - rows

    /// Under: this many card heights below its card, and within this many card widths sideways.
    static let underBelow = 0.45...1.65
    static let underSideways = 0.6
    /// A new row starts this many card heights below the row so far.
    static let newRow = 0.6
    /// A card turned more than this many degrees from the row's direction is not in it.
    static let turnedDegrees = 50.0

    public struct Slot: Sendable {
        public let card: Seen
        public let under: [Seen]
    }

    public struct Row: Sendable {
        public let slots: [Slot]
        public var codes: [String] { slots.map(\.card.card.code) }
    }

    public struct Layout: Sendable {
        public let rows: [Row]
        public let turned: [Seen]
        /// Rows as code lists, an under-card after its card: `walk_forward/slow`.
        public var described: [[String]] {
            rows.map { $0.slots.map { ([$0.card.card.code] + $0.under.map(\.card.code)).joined(separator: "/") } }
        }
    }

    /// READ THE WAY THE CARDS FACE, NOT THE WAY THE PICTURE DOES. A row on the floor seen from the
    /// far side is upside down in the picture; every code says which way is up on its card, so the
    /// row's direction is the cards' own right, averaged, and under is their own down.
    public static func arrange(_ seen: [Seen]) -> Layout {
        guard !seen.isEmpty else { return Layout(rows: [], turned: []) }
        let rights = seen.map(\.right.unit)
        let sum = rights.reduce(Point(0, 0), +)
        let direction = sum.length < 1e-6 ? rights[0] : sum.unit
        let cosTurned = cos(turnedDegrees * .pi / 180)
        var facing: [Seen] = [], turned: [Seen] = []
        for (s, r) in zip(seen, rights) {
            if r.dot(direction) >= cosTurned { facing.append(s) } else { turned.append(s) }
        }
        let down = facing.map(\.down.unit).reduce(Point(0, 0), +).unit
        func along(_ s: Seen) -> Double { s.cardCentre.dot(direction) }
        func across(_ s: Seen) -> Double { s.cardCentre.dot(down) }
        func width(_ s: Seen) -> Double { s.right.length * widthInSquares }
        func height(_ s: Seen) -> Double { s.down.length * heightInSquares }

        // Index everything, because Seen is a value and identity is what attaches an under-card.
        let modifiers = facing.indices.filter { facing[$0].card.kind == "modifier" }
        let mains = facing.indices.filter { facing[$0].card.kind != "modifier" }
        var underOf: [Int: [Int]] = [:]
        var owner: [Int: Int] = [:]
        var loose: [Int] = []
        for m in modifiers.sorted(by: { across(facing[$0]) < across(facing[$1]) }) {
            var best: Int?, bestD = 0.0
            for c in mains + modifiers.filter({ owner[$0] != nil }) {
                let h = (height(facing[c]) + height(facing[m])) / 2
                let w = (width(facing[c]) + width(facing[m])) / 2
                let below = (across(facing[m]) - across(facing[c])) / h
                let side = abs(along(facing[m]) - along(facing[c])) / w
                if underBelow.contains(below) && side <= underSideways {
                    let d = abs(below - 1) + side
                    if best == nil || d < bestD { best = c; bestD = d }
                }
            }
            if let b = best {
                let main = owner[b] ?? b
                owner[m] = main
                underOf[main, default: []].append(m)
            } else {
                loose.append(m)
            }
        }
        var rows: [[Int]] = []
        for i in (mains + loose).sorted(by: { across(facing[$0]) < across(facing[$1]) }) {
            if var row = rows.last {
                let mean = row.map { across(facing[$0]) }.reduce(0, +) / Double(row.count)
                let h = row.map { height(facing[$0]) }.reduce(0, +) / Double(row.count)
                if (across(facing[i]) - mean) / h < newRow {
                    row.append(i)
                    rows[rows.count - 1] = row
                    continue
                }
            }
            rows.append([i])
        }
        let built = rows.map { row in
            Row(slots: row.sorted { along(facing[$0]) < along(facing[$1]) }.map { i in
                Slot(card: facing[i],
                     under: (underOf[i] ?? []).sorted { across(facing[$0]) < across(facing[$1]) }.map { facing[$0] })
            })
        }
        return Layout(rows: built, turned: turned)
    }

    // MARK: - the program

    /// r001, `DuckIntentPlan.Vocabulary`: which heads an action carries. A walk or turn takes a
    /// speed and a head, a stop a head, a sound its sound, a trick nothing under it.
    static let carries: [String: Set<String>] = [
        "walk_forward": ["speed", "head"], "walk_backward": ["speed", "head"],
        "turn_left": ["speed", "head"], "turn_right": ["speed", "head"], "stop": ["head"],
        "make_sound": ["sound"],
    ]
    /// Nothing reads the number written on Repeat yet.
    public static let repeatTimes = 2
    public static let maxSteps = 40

    public struct Step: Equatable, Sendable {
        public let labels: [String: String]
        public let clause: String
        public let cards: [String]
        public var action: String { labels["action"] ?? "unsupported" }
    }

    public struct Program: Sendable {
        public enum Kind: String, Sendable { case row, card, none }
        public let steps: [Step]
        public let onFall: [Step]
        public let notes: [String]
        public let complete: Bool
        public let kind: Kind
        public var words: String { steps.map { $0.clause + "." }.joined(separator: " ") }
    }

    static func step(_ slot: Slot, _ notes: inout [String]) -> Step? {
        let card = slot.card.card
        var labels = card.plan ?? [:]
        guard let action = labels["action"] else { return nil }
        let takes = carries[action] ?? []
        var kept: [Card] = []
        for u in slot.under {
            guard let (head, value) = (u.card.plan ?? [:]).first else { continue }
            guard takes.contains(head) else {
                notes.append("\(card.name) takes nothing under it, so \(u.card.name) was not used.")
                continue
            }
            if let had = labels[head], had != value {
                notes.append("\(card.name) has two \(head) cards under it; the first was used.")
                continue
            }
            labels[head] = value
            kept.append(u.card)
        }
        if takes.contains("speed") && labels["speed"] == nil { labels["speed"] = "normal" }
        if takes.contains("head") && labels["head"] == nil { labels["head"] = "straight" }
        let clause = ([card.name] + kept.map { $0.name.lowercased() }).joined(separator: ", ")
        return Step(labels: labels, clause: clause, cards: [card.code] + kept.map(\.code))
    }

    static func compile(_ slots: [Slot], _ notes: inout [String], yours: [Int: [String]], deck: Deck) -> [Step] {
        var out: [Step] = []
        var i = 0
        while i < slots.count {
            let card = slots[i].card.card
            if card.code == "repeat" {
                var depth = 1, j = i + 1
                while j < slots.count && depth > 0 {
                    switch slots[j].card.card.code {
                    case "repeat": depth += 1
                    case "end_repeat": depth -= 1
                    default: break
                    }
                    j += 1
                }
                let body = depth == 0 ? Array(slots[(i + 1)..<(j - 1)]) : Array(slots[(i + 1)..<j])
                if depth > 0 {
                    notes.append("Repeat has no End repeat after it, so it repeats to the end of the row.")
                }
                notes.append("Nothing reads the number written on Repeat yet, so it repeats \(repeatTimes) times.")
                let inner = compile(body, &notes, yours: yours, deck: deck)
                for _ in 0..<repeatTimes { out += inner }
                i = j
                continue
            }
            if card.code == "end_repeat" {
                notes.append("End repeat has no Repeat before it, so it was skipped.")
            } else if card.kind == "yours" {
                if let meaning = yours[card.tag], !meaning.isEmpty {
                    let inner = meaning.compactMap { deck.card(code: $0) }.map { c in
                        Slot(card: Seen(card: c, corners: [], centre: Point(0, 0), right: Point(1, 0),
                                        down: Point(0, 1), cardCentre: Point(0, 0)), under: [])
                    }
                    out += compile(inner, &notes, yours: yours, deck: deck)
                } else {
                    notes.append("Your card \(card.tag) has no meaning saved yet, so it was skipped.")
                }
            } else if card.kind == "event" {
                notes.append("\(card.name) starts a row of its own; in the middle of a row it was skipped.")
            } else if card.kind == "modifier" {
                notes.append("\(card.name) is not under any card, so it was not used.")
            } else if card.kind == "control" {
                notes.append("A second \(card.name) in the row was skipped.")
            } else if let s = step(slots[i], &notes) {
                out.append(s)
            }
            i += 1
        }
        return out
    }

    /// THE PROGRAM IS THE ROW WITH START IN IT. Between Start and End, left to right, is what runs;
    /// a row that begins with When it falls is what runs after a fall; with no Start anywhere, one
    /// card on its own is a program of one step, and several are not a program yet.
    public static func read(_ layout: Layout, yours: [Int: [String]] = [:], deck: Deck) -> Program {
        var notes: [String] = []
        var mainIndex: Int?, fallIndex: Int?
        for (k, row) in layout.rows.enumerated() {
            let codes = row.codes
            if codes.first == "when_falls" { if fallIndex == nil { fallIndex = k } }
            else if codes.contains("start") && mainIndex == nil { mainIndex = k }
        }
        if !layout.turned.isEmpty {
            notes.append("Turned the other way from the rest, so not read: "
                         + layout.turned.map(\.card.name).joined(separator: ", ") + ".")
        }
        var onFall: [Step] = []
        if let f = fallIndex {
            let body = Array(layout.rows[f].slots.dropFirst())
            let end = body.firstIndex { $0.card.card.code == "end" }
            onFall = compile(end.map { Array(body[..<$0]) } ?? body, &notes, yours: yours, deck: deck)
        }
        guard let m = mainIndex else {
            let others = layout.rows.indices.filter { $0 != fallIndex }.flatMap { layout.rows[$0].slots }
            let actions = others.filter { ["action", "yours"].contains($0.card.card.kind) }
            let controls = others.filter { $0.card.card.kind == "control" }
            if actions.count == 1 && controls.isEmpty {
                let steps = compile(actions, &notes, yours: yours, deck: deck)
                return Program(steps: steps, onFall: onFall, notes: notes, complete: !steps.isEmpty, kind: .card)
            }
            if !actions.isEmpty { notes.append("These cards have no Start, so there is no row to run yet.") }
            return Program(steps: [], onFall: onFall, notes: notes, complete: false, kind: .none)
        }
        let row = layout.rows[m]
        let codes = row.codes
        let start = codes.firstIndex(of: "start")!
        let end = codes[start...].firstIndex(of: "end")
        if start > 0 { notes.append("Cards before Start are not part of the row.") }
        let body: [Slot]
        if let e = end {
            if e + 1 < codes.count { notes.append("Cards after End are not part of the row.") }
            body = Array(row.slots[(start + 1)..<e])
        } else {
            notes.append("There is a Start but no End yet.")
            body = Array(row.slots[(start + 1)...])
        }
        var steps = compile(body, &notes, yours: yours, deck: deck)
        if steps.count > maxSteps {
            notes.append("The row unrolls to \(steps.count) steps; a duck runs at most \(maxSteps).")
            steps = Array(steps.prefix(maxSteps))
        }
        return Program(steps: steps, onFall: onFall, notes: notes, complete: end != nil && !steps.isEmpty, kind: .row)
    }

    // MARK: - the plan

    /// `duck-intent-plan/0`, as `DuckIntentPlan.read` takes it.
    public static func planJSON(_ program: Program) -> [String: Any] {
        [
            "format": DuckIntentPlan.format,
            "request": program.words,
            "model": model,
            "steps": program.steps.map { s in
                ["clause": s.clause, "labels": s.labels,
                 "confidence": Dictionary(uniqueKeysWithValues: s.labels.keys.map { ($0, 1.0) })] as [String: Any]
            },
        ]
    }

    /// The program as a plan the plan editor opens, read back through `DuckIntentPlan.read` so a
    /// row that would be refused there is refused here, by the same rules and in the same words.
    public static func intentPlan(_ program: Program) throws -> DuckIntentPlan {
        let data = try JSONSerialization.data(withJSONObject: planJSON(program), options: [.sortedKeys])
        return try DuckIntentPlan.read(data)
    }
}
