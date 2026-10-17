import Foundation

extension DuckPacks {

    // MARK: - a row, as steps and as cards

    /// The steps a saved row makes, by the reader's own rules: laid out as Start, the row, End
    /// (`DuckCards.table`) and read (`DuckCards.read`), the way a Your card is read back. Repeat
    /// is unrolled and Your cards opened there, not here, so the board plays exactly what a duck
    /// would run.
    public static func steps(of row: [DuckCards.Entry], deck: DuckCards.Deck) -> [DuckCards.Step] {
        guard let layout = DuckCards.table(row, deck: deck) else { return [] }
        return DuckCards.read(layout, deck: deck).steps
    }

    /// Cards laid between Start and End: every card, Repeat and End repeat among them, and every
    /// card under one. A Your card is one card, which is what it is for.
    public static func cardCount(_ row: [DuckCards.Entry]) -> Int {
        row.reduce(0) { $0 + 1 + $1.under.count }
    }

    /// Repeat cards with no End repeat to close them. The reader still runs such a row, but the
    /// board does not count it as solved: a loop is Repeat and End repeat, and a par that a missing
    /// card could beat would teach the missing card.
    public static func openRepeats(_ row: [DuckCards.Entry]) -> Int {
        var depth = 0
        for e in row {
            if e.card == "repeat" { depth += 1 } else if e.card == "end_repeat" && depth > 0 { depth -= 1 }
        }
        return depth
    }

    // MARK: - the board

    /// What a row did on a challenge's board: the JSON both readers make, field for field.
    public struct Play: Equatable, Sendable {
        public let solved: Bool
        /// The start, then the place after every step played.
        public let path: [Place]
        /// The step, counted from 1, that walked into a wall or off the board; nil if none did.
        public let bumpedAt: Int?
        /// The gates passed, by their place in the challenge's list.
        public let gatesPassed: [Int]
        public let ended: Place
        public let steps: Int
        public let cards: Int
        /// `steps` or `cards`, as the pack scores.
        public let score: Int
        public let par: Int
        /// The play in one sentence, for a person.
        public let said: String

        public var json: [String: Any] {
            ["solved": solved, "path": path.map(\.json), "bumped_at": bumpedAt.map { $0 as Any } ?? NSNull(),
             "gates_passed": gatesPassed, "ended": ended.json, "steps": steps, "cards": cards, "score": score,
             "par": par, "said": said]
        }
    }

    enum Blocked { case edge, wall }

    static func walk(_ ch: Challenge, from at: Square, way: (dx: Int, dy: Int)) -> Result<Square, BlockedError> {
        let to = Square(at.x + way.dx, at.y + way.dy)
        guard (0..<ch.columns).contains(to.x), (0..<ch.rows).contains(to.y) else { return .failure(.init(why: .edge)) }
        if ch.walls.contains(Wall(at, to)) { return .failure(.init(why: .wall)) }
        return .success(to)
    }

    struct BlockedError: Error { let why: Blocked }

    static func gates(_ ch: Challenge, at to: Square, way: (dx: Int, dy: Int)) -> [Int] {
        let axis: Axis = way.dx == 0 ? .ns : .ew
        return ch.gates.indices.filter { ch.gates[$0].at == to && ch.gates[$0].axis == axis }
    }

    /// A program played on the challenge's board, by the board rule.
    ///
    /// A BUMP STOPS THE PLAY. A walk into a wall or off the board leaves the duck where it was, and
    /// nothing after it is played, because a class watching a duck walk into a wall needs to know
    /// which card did it, not where the rest of the row would have gone.
    public static func play(_ ch: Challenge, steps: [DuckCards.Step], cards: Int, score: Score,
                            deck: DuckCards.Deck? = nil, unclosed: Int = 0) -> Play {
        var at = ch.start.at, facing = ch.start.facing
        var path = [Place(at: at, facing: facing)]
        var passed: Set<Int> = []
        var bumped: Int?, why: Blocked?
        for (k, step) in steps.enumerated() {
            switch step.action {
            case "walk_forward", "walk_backward":
                let a = facing.ahead
                let way = step.action == "walk_forward" ? a : (dx: -a.dx, dy: -a.dy)
                switch walk(ch, from: at, way: way) {
                case .failure(let b): bumped = k + 1; why = b.why
                case .success(let to):
                    at = to
                    passed.formUnion(gates(ch, at: to, way: way))
                }
            case "turn_left": facing = facing.turned(-1)
            case "turn_right": facing = facing.turned(1)
            default: break
            }
            if bumped != nil { break }
            path.append(Place(at: at, facing: facing))
        }
        let missed = ch.gates.count - passed.count
        let finished = ch.finishWith == nil || (steps.last?.cards.first == ch.finishWith)
        let solved = bumped == nil && !steps.isEmpty && at == ch.goal && missed == 0 && finished && unclosed == 0
        let value = score == .steps ? steps.count : cards
        let said: String
        if let bumped {
            said = why == .wall ? "Bumped into a wall on step \(bumped)." : "Bumped into the edge of the board on step \(bumped)."
        } else if steps.isEmpty {
            said = "The row has no steps to play."
        } else if at != ch.goal {
            let away = abs(at.x - ch.goal.x) + abs(at.y - ch.goal.y)
            said = "The duck ended \(away) square\(away > 1 ? "s" : "") away from the goal."
        } else if missed > 0 {
            said = "The duck reached the goal but missed \(missed) gate\(missed > 1 ? "s" : "")."
        } else if !finished {
            let name = ch.finishWith.flatMap { deck?.card(code: $0)?.name ?? $0 } ?? ""
            said = "The duck reached the goal but did not finish with \(name)."
        } else if unclosed > 0 {
            said = "The duck reached the goal, but a Repeat has no End repeat. Close every loop."
        } else {
            let unit = score == .steps ? "steps" : "cards", how = score == .steps ? "in" : "with"
            if value == ch.par {
                said = "Solved \(how) \(value) \(unit), which is par."
            } else if value > ch.par {
                said = "Solved \(how) \(value) \(unit). Par is \(ch.par), so a shorter row is out there."
            } else {
                said = "Solved \(how) \(value) \(unit), under par \(ch.par). Tell whoever wrote the challenge."
            }
        }
        return Play(solved: solved, path: path, bumpedAt: bumped, gatesPassed: passed.sorted(),
                    ended: Place(at: at, facing: facing), steps: steps.count, cards: cards, score: value,
                    par: ch.par, said: said)
    }

    /// A saved row played on a challenge, scored as `score` says. The deck should already hold the
    /// pack's Your cards (`Pack.lent(to:)`). A row the camera read comes here through
    /// `DuckCards.savedRow`, so the board plays what was on the table.
    public static func play(_ ch: Challenge, row: [DuckCards.Entry], score: Score, deck: DuckCards.Deck) -> Play {
        play(ch, steps: steps(of: row, deck: deck), cards: cardCount(row), score: score, deck: deck,
             unclosed: openRepeats(row))
    }

    // MARK: - par

    struct SearchState: Hashable { let at: Square; let facing: Facing; let gates: Int }

    /// The fewest board steps that solve the challenge, by breadth-first search over (square,
    /// facing, gates passed), with the moving cards among `cards`. One more if it must finish with a
    /// card. Nil when the goal cannot be reached with every gate passed.
    public static func parSteps(_ ch: Challenge, cards: [String]) -> Int? {
        let usable = moves.filter { cards.contains($0) }
        let full = (1 << ch.gates.count) - 1
        let first = SearchState(at: ch.start.at, facing: ch.start.facing, gates: 0)
        var seen: [SearchState: Int] = [first: 0]
        var todo = [first], head = 0
        let extra = ch.finishWith == nil ? 0 : 1
        while head < todo.count {
            let s = todo[head]; head += 1
            if s.at == ch.goal && s.gates == full { return seen[s]! + extra }
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
                if seen[next] == nil {
                    seen[next] = seen[s]! + 1
                    todo.append(next)
                }
            }
        }
        return nil
    }

    /// Par as the pack scores it: for steps, the search; for cards, what the author found, which
    /// the checks hold the solution to.
    public static func par(_ ch: Challenge, in pack: Pack) -> Int? {
        pack.score == .steps ? parSteps(ch, cards: pack.cards) : ch.par
    }

    /// Every row one card swap away: one card that does something on its own (a move, a sound, a
    /// trick or a Your card) replaced by another such card in play, its under-cards kept. This is
    /// the cards page's Find the bug: one wrong card, fixed with a single swap.
    public static func swaps(_ row: [DuckCards.Entry], in pack: Pack, deck: DuckCards.Deck)
        -> [(index: Int, card: String, row: [DuckCards.Entry])] {
        func swappable(_ code: String) -> Bool { ["action", "yours"].contains(deck.card(code: code)?.kind ?? "") }
        var out: [(index: Int, card: String, row: [DuckCards.Entry])] = []
        for (i, e) in row.enumerated() where swappable(e.card) {
            for code in pack.cards where code != e.card && swappable(code) {
                var r = row
                r[i] = DuckCards.Entry(card: code, under: e.under)
                out.append((i, code, r))
            }
        }
        return out
    }
}
