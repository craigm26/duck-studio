import Foundation

/// A class's own challenges: drawn in Studio, checked here, kept in a pack of the class's own.
///
/// THE EDITOR DRAWS AND THIS DECIDES. Where a tap puts a wall, whether a gate may sit on a square,
/// whether the goal can be reached and in how many steps: `Draft` holds a challenge being drawn and
/// `checked` turns it into one a reader takes, or says in a sentence why it will not. Par is the
/// board rule's own search (`parSteps`), never a number a person types.
///
/// THE CLASS PACK IS A PACK LIKE ANY OTHER. It is written as `duck-pack/0`, read back through
/// `Pack.read` before it is kept, and its solution is the search's own shortest row (or, scored by
/// cards, a shorter row the author laid and the board played), so the duck's card reader and
/// `scripts/check_duck_packs.py` take it as they take the starter packs.
///
/// EVERY CLASS'S PACK IS ITS OWN. Its id is minted once per install (`class-` and six letters and
/// numbers) and kept, so two classes' packs opened on one phone sit side by side instead of the
/// second replacing the first. The teacher names it, chooses the score and the cards in play.
extension DuckPacks {

    // MARK: - a challenge, written

    /// A challenge's fields, given rather than read: how the editor makes one.
    public static func challenge(id: String, name: String, columns: Int, rows: Int, start: Place, goal: Square,
                                 walls: Set<Wall>, gates: [Gate], finishWith: String? = nil, par: Int,
                                 solution: [DuckCards.Entry], buggy: [DuckCards.Entry]? = nil,
                                 hint: String, note: String? = nil) -> Challenge {
        Challenge(id: id, name: name, columns: columns, rows: rows, start: start, goal: goal, walls: walls,
                  gates: gates, finishWith: finishWith, par: par, solution: solution, buggy: buggy, hint: hint,
                  note: note)
    }

    /// A challenge as `duck-pack/0` spells it. Walls are written top to bottom, left to right, so the
    /// same board always writes the same bytes.
    public static func json(_ ch: Challenge) -> [String: Any] {
        let walls = ch.walls.map { w -> [Square] in
            w.squares.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        }.sorted { ($0[0].y, $0[0].x, $0[1].y, $0[1].x) < ($1[0].y, $1[0].x, $1[1].y, $1[1].x) }
        var out: [String: Any] = [
            "id": ch.id, "name": ch.name, "columns": ch.columns, "rows": ch.rows,
            "start": ch.start.json, "goal": ch.goal.json,
            "walls": walls.map { ["between": [$0[0].json, $0[1].json]] },
            "gates": ch.gates.map { ["at": $0.at.json, "axis": $0.axis.rawValue] },
            "finish_with": ch.finishWith.map { $0 as Any } ?? NSNull(),
            "par": ch.par,
            "solution": ch.solution.map(\.json),
            "buggy": ch.buggy.map { $0.map(\.json) as Any } ?? NSNull(),
            "hint": ch.hint,
        ]
        if let note = ch.note { out["note"] = note }
        return out
    }

    // MARK: - the shortest row

    /// The moving cards of one fewest-steps solution, found by the same breadth-first search as
    /// `parSteps`, in the same order. Nil when the goal cannot be reached with every gate passed.
    static func shortestMoves(_ ch: Challenge, cards: [String]) -> [String]? {
        let usable = moves.filter { cards.contains($0) }
        let full = (1 << ch.gates.count) - 1
        let first = SearchState(at: ch.start.at, facing: ch.start.facing, gates: 0)
        var came: [SearchState: (from: SearchState, card: String)] = [:]
        var seen: Set<SearchState> = [first]
        var todo = [first], head = 0
        while head < todo.count {
            let s = todo[head]; head += 1
            if s.at == ch.goal && s.gates == full {
                var out: [String] = [], at = s
                while let back = came[at] { out.append(back.card); at = back.from }
                return out.reversed()
            }
            for m in usable {
                let next: SearchState
                switch m {
                case "turn_left": next = SearchState(at: s.at, facing: s.facing.turned(-1), gates: s.gates)
                case "turn_right": next = SearchState(at: s.at, facing: s.facing.turned(1), gates: s.gates)
                default:
                    let a = s.facing.ahead
                    let way = m == "walk_forward" ? a : (dx: -a.dx, dy: -a.dy)
                    guard case .success(let to) = walk(ch, from: s.at, way: way) else { continue }
                    var mask = s.gates
                    for k in gates(ch, at: to, way: way) { mask |= 1 << k }
                    next = SearchState(at: to, facing: s.facing, gates: mask)
                }
                if !seen.contains(next) {
                    seen.insert(next)
                    came[next] = (s, m)
                    todo.append(next)
                }
            }
        }
        return nil
    }

    /// One row that solves the challenge in the fewest board steps, as a `solution` is written: the
    /// search's moves, then the card it must finish with. Nil when nothing solves it.
    public static func shortestRow(_ ch: Challenge, cards: [String]) -> [DuckCards.Entry]? {
        guard let found = shortestMoves(ch, cards: cards) else { return nil }
        return (found + [ch.finishWith].compactMap { $0 }).map { DuckCards.Entry(card: $0) }
    }

    // MARK: - a challenge being drawn

    /// Why a drawn challenge was not saved, in a sentence that says what to change.
    public enum DraftRefusal: Error, Equatable, Sendable {
        case noName
        case noHint
        /// The goal cannot be reached from the start with every gate passed.
        case unreachable
        /// The duck is on the goal before a card is laid.
        case alreadyThere
        /// The fewest steps are more than a reader plays.
        case tooLong(Int)
        /// The finishing card is not a card in play.
        case finishNotInPlay(String)
        /// The shorter row the author laid does not solve the challenge; the board's sentence.
        case shorterDoesNotSolve(String)
        /// The shorter row lays cards that are not in play, by name.
        case shorterNotInPlay([String])
        /// A challenge already saved cannot be solved with the cards now in play, by its name.
        case notSolvable(String)

        public var message: String {
            switch self {
            case .noName: return "Give the challenge a name first."
            case .noHint: return "Give the challenge a hint, one sentence for whoever plays it."
            case .unreachable:
                return "The duck cannot reach the goal from the start with every gate passed, so the challenge "
                     + "was not saved. Look at the walls and the gates."
            case .alreadyThere:
                return "The duck starts on the goal, so there is nothing to solve. Move the goal, or add a gate to go round."
            case .tooLong(let n):
                return "The shortest row is \(n) steps, more than the \(DuckCards.maxSteps) a reader plays. Bring the goal closer."
            case .finishNotInPlay(let card):
                return "\(card) is not in play in this class pack, so a challenge cannot finish with it. "
                     + "Choose another card, or None."
            case .shorterDoesNotSolve(let said):
                return "The shorter row does not solve it: \(said) Fix the row, or clear it to keep the plain row's par."
            case .shorterNotInPlay(let names):
                return "The shorter row lays \(DuckCards.Words.listed(names)), which "
                     + (names.count == 1 ? "is" : "are") + " not in play in this class pack."
            case .notSolvable(let name):
                return "\(name) cannot be solved with those cards in play, so nothing was changed. "
                     + "Put the Walk and Turn cards it needs back, or take \(name) out first."
            }
        }
    }

    /// A challenge as it is drawn: the board, where the duck starts and faces, the goal, the walls
    /// and the gates, a name and a hint. Every tap the editor takes is one of these methods.
    public struct Draft: Equatable, Sendable {
        public private(set) var columns: Int
        public private(set) var rows: Int
        public private(set) var start: Place
        public private(set) var goal: Square
        public private(set) var walls: Set<Wall>
        public private(set) var gates: [Gate]
        public var name: String
        public var hint: String
        /// A card the row must end with, standing still (`canFinish`), or nil.
        public var finishWith: String?
        /// One optional line for the class.
        public var note: String
        /// For a pack scored by cards: a row the author found that may beat the plain row's card
        /// count, usually with a Repeat. Empty means none; the board plays it before it counts.
        public var shorter: [DuckCards.Entry]

        /// The smallest board the editor offers: one square has no challenge on it.
        public static let smallest = 2

        /// A clear board: the duck at the bottom left facing up the page, the goal at the top right.
        public init(columns: Int, rows: Int) {
            let c = min(max(columns, Draft.smallest), largestBoard), r = min(max(rows, Draft.smallest), largestBoard)
            self.columns = c; self.rows = r
            start = Place(at: Square(0, r - 1), facing: .north)
            goal = Square(c - 1, 0)
            walls = []; gates = []; name = ""; hint = ""; finishWith = nil; note = ""; shorter = []
        }

        /// A challenge to draw a copy of, its finishing card and note with it. Its solution is not
        /// kept as the shorter row: the copy is a new board, and its par is worked out again.
        public init(_ ch: Challenge) {
            columns = ch.columns; rows = ch.rows; start = ch.start; goal = ch.goal
            walls = ch.walls; gates = ch.gates; name = ch.name; hint = ch.hint
            finishWith = ch.finishWith; note = ch.note ?? ""; shorter = []
        }

        func onBoard(_ s: Square) -> Bool { (0..<columns).contains(s.x) && (0..<rows).contains(s.y) }

        /// A new size. Anything now off the board goes, and the start and the goal come back on.
        public mutating func resize(columns: Int, rows: Int) {
            self.columns = min(max(columns, Draft.smallest), largestBoard)
            self.rows = min(max(rows, Draft.smallest), largestBoard)
            func clamp(_ s: Square) -> Square { Square(min(s.x, self.columns - 1), min(s.y, self.rows - 1)) }
            start = Place(at: clamp(start.at), facing: start.facing)
            goal = clamp(goal)
            walls = walls.filter { $0.squares.allSatisfy(onBoard) }
            gates = gates.filter { onBoard($0.at) && $0.at != start.at }
        }

        /// Put the duck's start on a square. Tapping the start again turns it a quarter to the
        /// right, so one tool sets both where and which way. A gate on that square goes: a gate on
        /// the start can never be walked into.
        public mutating func placeStart(_ s: Square) {
            guard onBoard(s) else { return }
            start = s == start.at ? Place(at: s, facing: start.facing.turned(1)) : Place(at: s, facing: start.facing)
            gates.removeAll { $0.at == s }
        }

        public mutating func placeGoal(_ s: Square) {
            guard onBoard(s) else { return }
            goal = s
        }

        /// The wall between two squares that share an edge: put up if there is none, taken down if
        /// there is. The board's own edge is always a wall and is not toggled.
        public mutating func toggleWall(_ a: Square, _ b: Square) {
            guard onBoard(a), onBoard(b), abs(a.x - b.x) + abs(a.y - b.y) == 1 else { return }
            let w = Wall(a, b)
            if walls.contains(w) { walls.remove(w) } else { walls.insert(w) }
        }

        public func hasWall(_ a: Square, _ b: Square) -> Bool { walls.contains(Wall(a, b)) }

        /// A gate on a square, round the three: none, north to south, east to west, none. Never on
        /// the start square.
        public mutating func cycleGate(_ s: Square) {
            guard onBoard(s), s != start.at else { return }
            if let k = gates.firstIndex(where: { $0.at == s }) {
                if gates[k].axis == .ns { gates[k] = Gate(at: s, axis: .ew) } else { gates.remove(at: k) }
            } else {
                gates.append(Gate(at: s, axis: .ns))
            }
        }

        public func gate(at s: Square) -> Gate? { gates.first { $0.at == s } }

        /// Which neighbour a tap inside a square means when walls are being drawn: the side of the
        /// square nearest the tap, given as how far across (0 to 1) and down (0 to 1) it landed.
        public static func side(across fx: Double, down fy: Double) -> Facing {
            let distances: [(Facing, Double)] = [(.north, fy), (.south, 1 - fy), (.west, fx), (.east, 1 - fx)]
            return distances.min { $0.1 < $1.1 }!.0
        }

        /// The square on the other side of one side of a square, if it is on the board.
        public func neighbour(_ s: Square, _ side: Facing) -> Square? {
            let n = Square(s.x + side.ahead.dx, s.y + side.ahead.dy)
            return onBoard(n) ? n : nil
        }

        /// The note as it is written into the file: one line, or nil for none.
        var noteLine: String? {
            let line = note.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? nil : line
        }

        /// The drawing as a challenge, par and solution not yet worked out.
        func unchecked(id: String, par: Int = 0, solution: [DuckCards.Entry] = []) -> Challenge {
            Challenge(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), columns: columns, rows: rows,
                      start: start, goal: goal, walls: walls, gates: gates, finishWith: finishWith, par: par,
                      solution: solution, buggy: nil, hint: hint.trimmingCharacters(in: .whitespacesAndNewlines),
                      note: noteLine)
        }

        /// Par as it stands, while drawing: the fewest board steps with the moving cards among
        /// `cards`, one more for a finishing card, or nil when the goal cannot be reached. It is
        /// also the card count of the plain row (one card a step), which is par for a pack scored
        /// by cards until a shorter row is laid.
        public func par(cards: [String]) -> Int? { parSteps(unchecked(id: "draft"), cards: cards) }

        /// The cards a challenge may finish with, among `cards` in play: the ones `Pack.read` takes
        /// (`canFinish`) that are a step on their own (a sound, a trick, Stop), in the order given.
        public static func finishes(_ cards: [String], deck: DuckCards.Deck) -> [String] {
            cards.filter { canFinish(with: $0) && deck.card(code: $0)?.kind == "action" }
        }

        /// What the board says of the shorter row, for a pack scored by cards.
        public enum Shorter: Equatable, Sendable {
            /// No row laid, or the goal cannot be reached at all.
            case none
            /// It solves it in this many cards, fewer than the plain row's.
            case beats(cards: Int, plain: Int)
            /// It solves it, but in no fewer cards than the plain row, so par stays the plain row's.
            case noBetter(cards: Int, plain: Int)
            /// It does not solve it; the board's sentence.
            case fails(String)
            /// It lays cards that are not in play, by name.
            case notInPlay([String])
        }

        /// The shorter row played on the board, by the pack's `cards` score. Only a row that solves
        /// it in fewer cards than the plain row lowers par; anything else is said.
        public func shorterVerdict(cards: [String], deck: DuckCards.Deck) -> Shorter {
            guard !shorter.isEmpty, let plain = par(cards: cards) else { return .none }
            let outside = shorter.flatMap { [$0.card] + $0.under }.filter { !cards.contains($0) }
            if !outside.isEmpty {
                var seen: Set<String> = []
                return .notInPlay(outside.filter { seen.insert($0).inserted }.map { deck.card(code: $0)?.name ?? $0 })
            }
            let played = play(unchecked(id: "draft", par: plain), row: shorter, score: .cards, deck: deck)
            guard played.solved else { return .fails(played.said) }
            let n = cardCount(shorter)
            return n < plain ? .beats(cards: n, plain: plain) : .noBetter(cards: n, plain: plain)
        }

        /// The challenge, with par and a solution. Scored by steps, par is the search and the
        /// solution its shortest row. Scored by cards, par is the plain row's card count, or a
        /// shorter row's when the author laid one and the board played it to the goal in fewer
        /// cards. Refused in a sentence for no name, no hint, a goal that cannot be reached, a goal
        /// the duck starts on, a solution longer than a reader plays, a finishing card not in play,
        /// or a shorter row that does not solve it.
        public func checked(id: String, cards: [String], score: Score = .steps,
                            deck: DuckCards.Deck? = nil) throws -> Challenge {
            let ch = unchecked(id: id)
            guard !ch.name.isEmpty else { throw DraftRefusal.noName }
            if let finish = finishWith, !cards.contains(finish) {
                throw DraftRefusal.finishNotInPlay(deck?.card(code: finish)?.name ?? finish)
            }
            guard let moved = shortestMoves(ch, cards: cards), let row = shortestRow(ch, cards: cards) else {
                throw DraftRefusal.unreachable
            }
            guard !moved.isEmpty else { throw DraftRefusal.alreadyThere }
            guard row.count <= DuckCards.maxSteps else { throw DraftRefusal.tooLong(row.count) }
            guard !ch.hint.isEmpty else { throw DraftRefusal.noHint }
            var par = row.count, solution = row
            if score == .cards, let deck {
                switch shorterVerdict(cards: cards, deck: deck) {
                case .beats(let n, _): par = n; solution = shorter
                case .fails(let said): throw DraftRefusal.shorterDoesNotSolve(said)
                case .notInPlay(let names): throw DraftRefusal.shorterNotInPlay(names)
                case .none, .noBetter: break
                }
            }
            return DuckPacks.challenge(id: id, name: ch.name, columns: columns, rows: rows, start: start, goal: goal,
                                       walls: walls, gates: gates, finishWith: finishWith, par: par,
                                       solution: solution, hint: ch.hint, note: ch.note)
        }
    }

    // MARK: - the class pack

    /// The pack a class's own challenges are kept in and shared as.
    public enum ClassPack {
        /// The one id every class pack used to share, before each class had its own. A pack with it
        /// still opens; Studio mints its own class a new id when it finds this one.
        public static let legacyID = "our-class-pack"
        /// What an id minted here starts with.
        public static let idPrefix = "class-"
        public static let fileName = "class.duckpack"
        public static let settingsFileName = "class-settings.json"
        /// The name until the teacher gives one.
        public static let name = "Our class pack"
        public static let grades = "Any grade"
        public static let about = "Challenges this class drew in Microduck Studio, each one checked to be solvable."
        public static let credit = "Drawn in Microduck Studio. Duck Cards, from microduckstudio.com"
        public static let license = "CC-BY-4.0"
        /// The default board a new challenge is drawn on.
        public static let columns = 4, rows = 4
        /// The printed floor square, for people. How far a duck walks is not measured, so it stays null.
        public static let squareCm = 30.0
        /// The longest name a teacher may give, so it fits a list row and a printed card.
        public static let longestName = 60

        /// A new id for this install's class pack: `class-` and six small letters and numbers, with
        /// no 0, o, 1 or l to misread. Minted once and kept (`Settings`); 32 to the sixth is about a
        /// billion, so two classes that swap packs will not meet the same one.
        public static func mintID<G: RandomNumberGenerator>(using rng: inout G) -> String {
            let letters = Array("abcdefghijkmnpqrstuvwxyz23456789")
            return idPrefix + String((0..<6).map { _ in letters.randomElement(using: &rng)! })
        }

        public static func mintID() -> String {
            var rng = SystemRandomNumberGenerator()
            return mintID(using: &rng)
        }

        /// Every card the deck prints, in tag order: the cards in play unless the teacher narrows
        /// them, as in Design a level.
        public static func cards(_ deck: DuckCards.Deck) -> [String] {
            guard let top = (try? JSONSerialization.jsonObject(with: deck.source)) as? [String: Any],
                  let rows = top["cards"] as? [[String: Any]] else { return [] }
            return rows.filter { ($0["printed"] as? Bool) == true }
                .compactMap { c -> (Int, String)? in
                    guard let tag = c["tag"] as? Int, let code = c["code"] as? String else { return nil }
                    return (tag, code)
                }
                .sorted { $0.0 < $1.0 }.map(\.1)
        }

        /// The cards that are always in play: a row is laid between them.
        public static let always = ["start", "end"]

        /// What the teacher chose for the class pack: its id (minted once, kept), its name, how it
        /// is scored, and which printed cards are in play. Kept beside the pack so a class with no
        /// challenges yet still has them.
        public struct Settings: Codable, Equatable, Sendable {
            public var id: String
            public var name: String
            public var score: Score
            /// The printed cards in play, or nil for every one.
            public var cards: [String]?

            public init(id: String = ClassPack.mintID(), name: String = ClassPack.name, score: Score = .steps,
                        cards: [String]? = nil) {
                self.id = id; self.name = name; self.score = score; self.cards = cards
            }

            /// The name as it is written: one line, trimmed, at most `longestName`, or the default.
            public var shownName: String {
                let line = name.split(whereSeparator: \.isNewline).joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                return line.isEmpty ? ClassPack.name : String(line.prefix(longestName))
            }

            /// The cards in play, in the deck's printed order: every printed card, or the ones
            /// chosen, with Start and End always among them.
            public func inPlay(_ deck: DuckCards.Deck) -> [String] {
                let printed = ClassPack.cards(deck)
                guard let cards else { return printed }
                return printed.filter { always.contains($0) || cards.contains($0) }
            }

            public var data: Data {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                return (try? encoder.encode(self)) ?? Data()
            }

            /// Settings read back, or nil for a file that is not them or whose id is not a pack id.
            public static func read(_ data: Data) -> Settings? {
                guard let s = try? JSONDecoder().decode(Settings.self, from: data), isID(s.id) else { return nil }
                return s
            }

            /// The settings a class pack written before there were settings carries: its name, its
            /// score and its cards, and a new id if it still has the one every class shared.
            public static func of(_ pack: Pack, deck: DuckCards.Deck) -> Settings {
                Settings(id: pack.id == legacyID ? ClassPack.mintID() : pack.id, name: pack.name, score: pack.score,
                         cards: pack.cards == ClassPack.cards(deck) ? nil : pack.cards)
            }
        }

        /// The next free id for a challenge in the class pack: class-1, class-2, and so on.
        public static func nextID(after held: [Challenge]) -> String {
            let used = Set(held.map(\.id))
            var n = held.count + 1
            while used.contains("class-\(n)") { n += 1 }
            return "class-\(n)"
        }

        /// The challenges held to new settings: scored by steps, par is the search again and the
        /// solution its shortest row; scored by cards, a row the author laid is kept while it still
        /// solves it in fewer cards than the plain row, and otherwise the plain row is par. Refused
        /// in a sentence, changing nothing, when a challenge cannot be solved with the cards now in
        /// play or finishes with a card no longer in play.
        public static func rechecked(_ challenges: [Challenge], settings: Settings,
                                     deck: DuckCards.Deck) throws -> [Challenge] {
            let cards = settings.inPlay(deck)
            return try challenges.map { ch in
                if let finish = ch.finishWith, !cards.contains(finish) {
                    throw DraftRefusal.finishNotInPlay(deck.card(code: finish)?.name ?? finish)
                }
                guard let plain = shortestRow(ch, cards: cards), plain.count <= DuckCards.maxSteps else {
                    throw DraftRefusal.notSolvable(ch.name)
                }
                var par = plain.count, solution = plain
                if settings.score == .cards {
                    let laid = ch.solution
                    let inPlay = laid.flatMap { [$0.card] + $0.under }.allSatisfy(cards.contains)
                    let probe = DuckPacks.challenge(id: ch.id, name: ch.name, columns: ch.columns, rows: ch.rows,
                                                    start: ch.start, goal: ch.goal, walls: ch.walls, gates: ch.gates,
                                                    finishWith: ch.finishWith, par: plain.count, solution: laid,
                                                    hint: ch.hint)
                    if inPlay, cardCount(laid) < plain.count,
                       play(probe, row: laid, score: .cards, deck: deck).solved {
                        par = cardCount(laid); solution = laid
                    }
                }
                return DuckPacks.challenge(id: ch.id, name: ch.name, columns: ch.columns, rows: ch.rows,
                                           start: ch.start, goal: ch.goal, walls: ch.walls, gates: ch.gates,
                                           finishWith: ch.finishWith, par: par, solution: solution,
                                           buggy: ch.buggy, hint: ch.hint, note: ch.note)
            }
        }

        /// The class pack's file, holding these challenges under these settings, read back through
        /// `Pack.read` before it is handed over so it is never a file a reader would refuse. Nil for
        /// no challenges: a pack holds at least one.
        public static func written(_ challenges: [Challenge], settings: Settings,
                                   deck: DuckCards.Deck) throws -> Pack? {
            guard !challenges.isEmpty else { return nil }
            let top: [String: Any] = [
                "format": DuckPacks.format, "id": settings.id, "name": settings.shownName, "grades": grades,
                "grade_from": -1, "grade_to": 12,
                "vocabulary": deckVocabulary(deck) ?? "", "license": license, "credit": credit, "about": about,
                "cards": settings.inPlay(deck), "score": settings.score.rawValue,
                "board": ["columns": columns, "rows": rows, "square_cm": squareCm, "duck_square_cm": NSNull()] as [String: Any],
                "challenges": challenges.map(DuckPacks.json),
                "lessons": [] as [Any], "yours": [] as [Any],
            ]
            let data: Data
            do {
                data = try JSONSerialization.data(withJSONObject: top, options: [.prettyPrinted, .sortedKeys])
            } catch {
                throw Refusal.notAPack("The class pack could not be written as JSON.")
            }
            return try Pack.read(data, deck: deck)
        }
    }

    // MARK: - a row, to the duck

    /// A row laid on the board, handed to the plan editor the way a row read off cards is
    /// (`DuckCards.handed`): laid out as Start, the row, End, read by the reader's own rules, and
    /// proposed by the cards and the deck. The same steps the board played, so the duck runs what
    /// the board showed; where it stops is the duck's walking, not a square.
    public static func handed(_ row: [DuckCards.Entry], deck: DuckCards.Deck) throws -> DuckIntentPlan.Handed {
        guard let layout = DuckCards.table(row, deck: deck) else { throw DuckCards.Refusal.empty }
        let program = DuckCards.read(layout, deck: deck)
        return DuckIntentPlan.Handed(plan: try DuckCards.intentPlan(program), by: .cards(deck),
                                     notes: DuckCards.Words.planNotes(program))
    }
}
