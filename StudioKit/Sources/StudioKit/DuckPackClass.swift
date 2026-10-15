import Foundation

/// A class's own challenges: drawn in Studio, checked here, kept in a pack of the class's own.
///
/// THE EDITOR DRAWS AND THIS DECIDES. Where a tap puts a wall, whether a gate may sit on a square,
/// whether the goal can be reached and in how many steps: `Draft` holds a challenge being drawn and
/// `checked` turns it into one a reader takes, or says in a sentence why it will not. Par is the
/// board rule's own search (`parSteps`), never a number a person types.
///
/// THE CLASS PACK IS A PACK LIKE ANY OTHER. It is written as `duck-pack/0`, read back through
/// `Pack.read` before it is kept, and its solution is the search's own shortest row, so the duck's
/// card reader and `scripts/check_duck_packs.py` take it as they take the starter packs.
extension DuckPacks {

    // MARK: - a challenge, written

    /// The class pack's challenges are scored by steps, so par is the search, exactly.
    public static let classScore = Score.steps

    /// A challenge's fields, given rather than read: how the editor makes one.
    public static func challenge(id: String, name: String, columns: Int, rows: Int, start: Place, goal: Square,
                                 walls: Set<Wall>, gates: [Gate], finishWith: String? = nil, par: Int,
                                 solution: [DuckCards.Entry], buggy: [DuckCards.Entry]? = nil,
                                 hint: String) -> Challenge {
        Challenge(id: id, name: name, columns: columns, rows: rows, start: start, goal: goal, walls: walls,
                  gates: gates, finishWith: finishWith, par: par, solution: solution, buggy: buggy, hint: hint)
    }

    /// A challenge as `duck-pack/0` spells it. Walls are written top to bottom, left to right, so the
    /// same board always writes the same bytes.
    public static func json(_ ch: Challenge) -> [String: Any] {
        let walls = ch.walls.map { w -> [Square] in
            w.squares.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        }.sorted { ($0[0].y, $0[0].x, $0[1].y, $0[1].x) < ($1[0].y, $1[0].x, $1[1].y, $1[1].x) }
        return [
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

        /// The smallest board the editor offers: one square has no challenge on it.
        public static let smallest = 2

        /// A clear board: the duck at the bottom left facing up the page, the goal at the top right.
        public init(columns: Int, rows: Int) {
            let c = min(max(columns, Draft.smallest), largestBoard), r = min(max(rows, Draft.smallest), largestBoard)
            self.columns = c; self.rows = r
            start = Place(at: Square(0, r - 1), facing: .north)
            goal = Square(c - 1, 0)
            walls = []; gates = []; name = ""; hint = ""
        }

        /// A challenge to draw a copy of. Its finishing card, if any, is not kept: a class
        /// challenge is solved on the board.
        public init(_ ch: Challenge) {
            columns = ch.columns; rows = ch.rows; start = ch.start; goal = ch.goal
            walls = ch.walls; gates = ch.gates; name = ch.name; hint = ch.hint
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

        /// The drawing as a challenge, par and solution not yet worked out.
        func unchecked(id: String) -> Challenge {
            Challenge(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), columns: columns, rows: rows,
                      start: start, goal: goal, walls: walls, gates: gates, finishWith: nil, par: 0, solution: [],
                      buggy: nil, hint: hint.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        /// Par as it stands, while drawing: the fewest board steps with the moving cards among
        /// `cards`, or nil when the goal cannot be reached.
        public func par(cards: [String]) -> Int? { parSteps(unchecked(id: "draft"), cards: cards) }

        /// The challenge, with par and a fewest-steps solution from the search. Refused in a
        /// sentence for no name, no hint, a goal that cannot be reached, a goal the duck starts on,
        /// or a solution longer than a reader plays.
        public func checked(id: String, cards: [String]) throws -> Challenge {
            let ch = unchecked(id: id)
            guard !ch.name.isEmpty else { throw DraftRefusal.noName }
            guard let row = shortestRow(ch, cards: cards) else { throw DraftRefusal.unreachable }
            guard !row.isEmpty else { throw DraftRefusal.alreadyThere }
            guard row.count <= DuckCards.maxSteps else { throw DraftRefusal.tooLong(row.count) }
            guard !ch.hint.isEmpty else { throw DraftRefusal.noHint }
            return DuckPacks.challenge(id: id, name: ch.name, columns: columns, rows: rows, start: start, goal: goal,
                                       walls: walls, gates: gates, par: row.count, solution: row, hint: ch.hint)
        }
    }

    // MARK: - the class pack

    /// The pack a class's own challenges are kept in and shared as.
    public enum ClassPack {
        public static let id = "our-class-pack"
        public static let fileName = "class.duckpack"
        public static let name = "Our class pack"
        public static let grades = "Any grade"
        public static let about = "Challenges this class drew in Microduck Studio, each one checked to be solvable."
        public static let credit = "Drawn in Microduck Studio. Duck Cards, from microduckstudio.com"
        public static let license = "CC-BY-4.0"
        /// The default board a new challenge is drawn on.
        public static let columns = 4, rows = 4
        /// The printed floor square, for people. How far a duck walks is not measured, so it stays null.
        public static let squareCm = 30.0

        /// Every card the deck prints is in play, as in Design a level: a class challenge is a
        /// board, and what is laid on it is up to whoever plays.
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

        /// The next free id for a challenge in the class pack: class-1, class-2, and so on.
        public static func nextID(after held: [Challenge]) -> String {
            let used = Set(held.map(\.id))
            var n = held.count + 1
            while used.contains("class-\(n)") { n += 1 }
            return "class-\(n)"
        }

        /// The class pack's file, holding these challenges, read back through `Pack.read` before it
        /// is handed over so it is never a file a reader would refuse. Nil for no challenges: a pack
        /// holds at least one.
        public static func written(_ challenges: [Challenge], deck: DuckCards.Deck) throws -> Pack? {
            guard !challenges.isEmpty else { return nil }
            let top: [String: Any] = [
                "format": DuckPacks.format, "id": id, "name": name, "grades": grades,
                "grade_from": -1, "grade_to": 12,
                "vocabulary": deckVocabulary(deck) ?? "", "license": license, "credit": credit, "about": about,
                "cards": cards(deck), "score": classScore.rawValue,
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
