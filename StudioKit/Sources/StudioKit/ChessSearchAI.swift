import Foundation

// MARK: - ChessAIDifficulty

/// Strength preset for the built-in offline alpha-beta chess engine.
public enum ChessAIDifficulty: String, CaseIterable, Sendable, Equatable, Hashable, Codable, Identifiable {
    case casual
    case club
    case strong

    public var id: String { rawValue }

    /// Short label suitable for compact UI pills.
    public var label: String {
        switch self {
        case .casual: return "Casual"
        case .club: return "Club"
        case .strong: return "Strong"
        }
    }

    /// Base full-width search depth in plies.
    public var searchDepth: Int {
        switch self {
        case .casual: return 1
        case .club: return 2
        case .strong: return 3
        }
    }

    /// Maximum quiescence extension plies on tactical captures.
    internal var quiescenceDepth: Int {
        switch self {
        case .casual: return 0
        case .club: return 4
        case .strong: return 6
        }
    }

    /// Node safety cap to guarantee fast response times on mobile and Linux.
    internal var nodeBudget: Int {
        switch self {
        case .casual: return 2_000
        case .club: return 15_000
        case .strong: return 55_000
        }
    }
}

// MARK: - ChessSearchResult

/// Output of the built-in alpha-beta chess search engine.
public struct ChessSearchResult: Sendable, Equatable, Hashable, Codable {
    public let move: ChessMove
    public let san: String
    /// Evaluation score in centipawns from the perspective of the side that made `move`.
    public let scoreCentipawns: Int
    public let depth: Int
    public let nodesSearched: Int
    /// Short, friendly MicroDuck commentary line (guaranteed free of em-dashes).
    public let commentary: String

    public init(
        move: ChessMove,
        san: String,
        scoreCentipawns: Int,
        depth: Int,
        nodesSearched: Int,
        commentary: String
    ) {
        self.move = move
        self.san = san
        self.scoreCentipawns = scoreCentipawns
        self.depth = depth
        self.nodesSearched = nodesSearched
        self.commentary = commentary
    }
}

// MARK: - ChessSearchAI

/// Deterministic negamax + alpha-beta + quiescence chess engine with piece-square tables.
public enum ChessSearchAI {
    private static let mateScore = 100_000
    private static let infinityScore = 1_000_000

    /// Computes the best move for `state` at the requested `difficulty`.
    /// Returns `nil` only when no legal moves exist (checkmate or stalemate).
    public static func bestMove(
        for state: ChessBoardState,
        difficulty: ChessAIDifficulty,
        deterministicSeed: UInt64? = nil
    ) -> ChessSearchResult? {
        let legal = state.legalMoves()
        guard !legal.isEmpty else { return nil }

        // Instant return if only one legal move exists.
        if legal.count == 1 {
            let only = legal[0]
            let san = state.san(for: only) ?? only.uci
            let after = state.applyingUnchecked(only).state
            let eval = -evaluateStatic(after)
            let commentary = buildCommentary(move: only, san: san, score: eval, stateBefore: state)
            return ChessSearchResult(
                move: only,
                san: san,
                scoreCentipawns: eval,
                depth: 1,
                nodesSearched: 1,
                commentary: commentary
            )
        }

        // Convert to compact fast search board (zero heap churn during make/unmake).
        let fast = FastBoard(from: state)
        let nonKingPieces = fast.nonKingPieceCount()
        let effectiveMaxDepth: Int
        if difficulty == .strong && nonKingPieces <= 10 {
            effectiveMaxDepth = 4
        } else {
            effectiveMaxDepth = difficulty.searchDepth
        }

        var searcher = AlphaBetaSearcher(
            board: fast,
            qDepth: difficulty.quiescenceDepth,
            nodeBudget: difficulty.nodeBudget
        )

        var bestFastMove = FastMove.none
        var bestScore = -infinityScore
        var completedDepth = 0
        var rootScoredMoves: [(move: FastMove, score: Int)] = []

        // Iterative deepening from depth 1 up to effectiveMaxDepth.
        for depth in 1...effectiveMaxDepth {
            let iteration = searcher.searchRoot(depth: depth, previousBest: bestFastMove)
            if iteration.completed || depth == 1 {
                if let chosen = iteration.bestMove {
                    bestFastMove = chosen
                    bestScore = iteration.bestScore
                    completedDepth = depth
                    rootScoredMoves = iteration.scoredMoves
                }
            }
            if searcher.aborted || abs(bestScore) > mateScore - 100 {
                break
            }
        }

        // Casual mode adds light controlled variety among near-best moves, while still
        // always playing forced mates and big captures.
        var chosenFastMove = bestFastMove
        var chosenScore = bestScore
        if difficulty == .casual && bestScore < mateScore - 100 && rootScoredMoves.count > 1 {
            let sorted = rootScoredMoves.sorted { $0.score > $1.score }
            let threshold = sorted[0].score - 75
            let pool = sorted.prefix(3).filter { $0.score >= threshold }
            if pool.count > 1 {
                let seed = deterministicSeed ?? fnvHash(state.fen)
                let index = Int(seed % UInt64(pool.count))
                chosenFastMove = pool[index].move
                chosenScore = pool[index].score
            }
        }

        let resolvedMove = chosenFastMove.toChessMove()
        let finalMove = legal.contains(resolvedMove) ? resolvedMove : legal[0]
        let san = state.san(for: finalMove) ?? finalMove.uci
        let commentary = buildCommentary(
            move: finalMove,
            san: san,
            score: chosenScore,
            stateBefore: state
        )

        return ChessSearchResult(
            move: finalMove,
            san: san,
            scoreCentipawns: chosenScore,
            depth: max(1, completedDepth),
            nodesSearched: max(1, searcher.nodesSearched),
            commentary: commentary
        )
    }

    // MARK: Commentary Builder (Strictly Zero Em-Dashes)

    private static func buildCommentary(
        move: ChessMove,
        san: String,
        score: Int,
        stateBefore: ChessBoardState
    ) -> String {
        if san.hasSuffix("#") {
            return "Checkmate with \(san)! Great game."
        }
        if score > mateScore - 100 {
            return "Spotted a forcing checkmate line with \(san)."
        }
        if san.hasSuffix("+") {
            return "Check with \(san)! Watch your king."
        }
        if san == "O-O" || san == "O-O-O" {
            return "Tucking the king safely away with \(san)."
        }
        if move.promotion != nil {
            return "Promoting on \(move.to.algebraic) with \(san)!"
        }
        if san.contains("x") {
            if score >= 250 {
                return "Winning material cleanly with \(san)."
            }
            return "Trading pieces with \(san)."
        }
        if score >= 250 {
            return "Pressing the advantage with \(san)."
        }
        if score <= -250 {
            return "Digging in defensively with \(san)."
        }

        let options = [
            "Playing \(san) to stay active.",
            "Developing cleanly with \(san).",
            "Claiming useful squares with \(san).",
            "Keeping the pressure steady with \(san).",
            "Solid choice: \(san).",
        ]
        let idx = Int(fnvHash("\(stateBefore.fen)|\(san)") % UInt64(options.count))
        return options[idx]
    }

    private static func fnvHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private static func evaluateStatic(_ state: ChessBoardState) -> Int {
        let fb = FastBoard(from: state)
        return fb.evaluate()
    }

    // MARK: Fast Search Representation

    /// Piece codes: 0 empty, 1..6 White P,N,B,R,Q,K, -1..-6 Black P,N,B,R,Q,K.
    private struct FastMove: Equatable {
        let from: UInt8
        let to: UInt8
        let promo: Int8 // 0 = none, 2=N, 3=B, 4=R, 5=Q
        let captured: Int8
        let isEnPassant: Bool
        let isCastle: Bool

        static let none = FastMove(from: 0, to: 0, promo: 0, captured: 0, isEnPassant: false, isCastle: false)

        func toChessMove() -> ChessMove {
            let promoKind: ChessPieceKind?
            switch promo {
            case 2: promoKind = .knight
            case 3: promoKind = .bishop
            case 4: promoKind = .rook
            case 5: promoKind = .queen
            default: promoKind = nil
            }
            return ChessMove(
                from: ChessSquare(uncheckedIndex: Int(from)),
                to: ChessSquare(uncheckedIndex: Int(to)),
                promotion: promoKind
            )
        }
    }

    private struct UndoInfo {
        let castlingMask: UInt8
        let epSquare: Int8
        let halfmoveClock: Int16
        let captured: Int8
        let movedPiece: Int8
    }

    private struct FastBoard {
        var cells: [Int8] // 64 squares
        var whiteToMove: Bool
        var castlingMask: UInt8 // bit0 WK, bit1 WQ, bit2 BK, bit3 BQ
        var epSquare: Int8 // -1 if none, else 0..63
        var halfmoveClock: Int16
        var whiteKingSq: Int
        var blackKingSq: Int

        init(from state: ChessBoardState) {
            var arr = [Int8](repeating: 0, count: 64)
            var wk = 4
            var bk = 60
            for idx in 0..<64 {
                if let p = state.squares[idx] {
                    let code: Int8
                    switch p.kind {
                    case .pawn: code = 1
                    case .knight: code = 2
                    case .bishop: code = 3
                    case .rook: code = 4
                    case .queen: code = 5
                    case .king: code = 6
                    }
                    arr[idx] = p.color == .white ? code : -code
                    if p.kind == .king {
                        if p.color == .white { wk = idx } else { bk = idx }
                    }
                }
            }
            self.cells = arr
            self.whiteToMove = state.sideToMove == .white
            self.castlingMask = state.castlingRights.bitmask
            self.epSquare = state.enPassantTarget.map { Int8($0.index) } ?? -1
            self.halfmoveClock = Int16(min(state.halfmoveClock, 200))
            self.whiteKingSq = wk
            self.blackKingSq = bk
        }

        func nonKingPieceCount() -> Int {
            var count = 0
            for idx in 0..<64 {
                let absCode = abs(cells[idx])
                if absCode >= 1 && absCode <= 5 {
                    count += 1
                }
            }
            return count
        }

        mutating func makeMove(_ m: FastMove) -> UndoInfo {
            let from = Int(m.from)
            let to = Int(m.to)
            let moved = cells[from]
            let undo = UndoInfo(
                castlingMask: castlingMask,
                epSquare: epSquare,
                halfmoveClock: halfmoveClock,
                captured: m.captured,
                movedPiece: moved
            )

            cells[from] = 0
            if m.isEnPassant {
                let capIdx = (from & 56) | (to & 7)
                cells[capIdx] = 0
            }

            if m.promo != 0 {
                cells[to] = whiteToMove ? m.promo : -m.promo
            } else {
                cells[to] = moved
            }

            if moved == 6 {
                whiteKingSq = to
                castlingMask &= ~3
            } else if moved == -6 {
                blackKingSq = to
                castlingMask &= ~12
            }

            if m.isCastle {
                let rankBase = from & 56
                if (to & 7) == 6 {
                    cells[rankBase | 5] = cells[rankBase | 7]
                    cells[rankBase | 7] = 0
                } else {
                    cells[rankBase | 3] = cells[rankBase]
                    cells[rankBase] = 0
                }
            }

            if from == 0 || to == 0 { castlingMask &= ~2 }
            if from == 7 || to == 7 { castlingMask &= ~1 }
            if from == 56 || to == 56 { castlingMask &= ~8 }
            if from == 63 || to == 63 { castlingMask &= ~4 }

            if abs(moved) == 1 && abs(to - from) == 16 {
                epSquare = Int8((from + to) >> 1)
            } else {
                epSquare = -1
            }

            if abs(moved) == 1 || m.captured != 0 {
                halfmoveClock = 0
            } else {
                halfmoveClock += 1
            }

            whiteToMove.toggle()
            return undo
        }

        mutating func unmakeMove(_ m: FastMove, undo: UndoInfo) {
            whiteToMove.toggle()
            let from = Int(m.from)
            let to = Int(m.to)

            cells[from] = undo.movedPiece
            if m.isEnPassant {
                cells[to] = 0
                let capIdx = (from & 56) | (to & 7)
                cells[capIdx] = undo.captured
            } else {
                cells[to] = undo.captured
            }

            if undo.movedPiece == 6 {
                whiteKingSq = from
            } else if undo.movedPiece == -6 {
                blackKingSq = from
            }

            if m.isCastle {
                let rankBase = from & 56
                if (to & 7) == 6 {
                    cells[rankBase | 7] = cells[rankBase | 5]
                    cells[rankBase | 5] = 0
                } else {
                    cells[rankBase] = cells[rankBase | 3]
                    cells[rankBase | 3] = 0
                }
            }

            castlingMask = undo.castlingMask
            epSquare = undo.epSquare
            halfmoveClock = undo.halfmoveClock
        }

        @inline(__always)
        func isAttacked(square sq: Int, byWhite: Bool) -> Bool {
            let f = sq & 7
            let r = sq >> 3
            let sign: Int8 = byWhite ? 1 : -1

            // Pawns
            let pr = byWhite ? r - 1 : r + 1
            if pr >= 0 && pr < 8 {
                let pCode = sign
                if f > 0 && cells[(pr << 3) | (f - 1)] == pCode { return true }
                if f < 7 && cells[(pr << 3) | (f + 1)] == pCode { return true }
            }

            // Knights
            let nCode: Int8 = 2 * sign
            for i in 0..<8 {
                let nf = f + Self.knightDF[i]
                let nr = r + Self.knightDR[i]
                if (nf | nr) & ~7 == 0 && cells[(nr << 3) | nf] == nCode {
                    return true
                }
            }

            // King
            let kCode: Int8 = 6 * sign
            for i in 0..<8 {
                let kf = f + Self.kingDF[i]
                let kr = r + Self.kingDR[i]
                if (kf | kr) & ~7 == 0 && cells[(kr << 3) | kf] == kCode {
                    return true
                }
            }

            // Diagonal sliders
            let bCode: Int8 = 3 * sign
            let qCode: Int8 = 5 * sign
            for i in 0..<4 {
                let df = Self.bishopDF[i]
                let dr = Self.bishopDR[i]
                var cf = f + df
                var cr = r + dr
                while (cf | cr) & ~7 == 0 {
                    let c = cells[(cr << 3) | cf]
                    if c != 0 {
                        if c == bCode || c == qCode { return true }
                        break
                    }
                    cf += df
                    cr += dr
                }
            }

            // Orthogonal sliders
            let rCode: Int8 = 4 * sign
            for i in 0..<4 {
                let df = Self.rookDF[i]
                let dr = Self.rookDR[i]
                var cf = f + df
                var cr = r + dr
                while (cf | cr) & ~7 == 0 {
                    let c = cells[(cr << 3) | cf]
                    if c != 0 {
                        if c == rCode || c == qCode { return true }
                        break
                    }
                    cf += df
                    cr += dr
                }
            }

            return false
        }

        @inline(__always)
        func inCheck(white: Bool) -> Bool {
            isAttacked(square: white ? whiteKingSq : blackKingSq, byWhite: !white)
        }

        mutating func hasAnyLegalMove() -> Bool {
            let moves = generatePseudoLegalMoves(capturesOnly: false)
            let moverWhite = whiteToMove
            for move in moves {
                let undo = makeMove(move)
                let stillInCheck = inCheck(white: moverWhite)
                unmakeMove(move, undo: undo)
                if !stillInCheck {
                    return true
                }
            }
            return false
        }

        func generatePseudoLegalMoves(capturesOnly: Bool) -> [FastMove] {
            var moves: [FastMove] = []
            moves.reserveCapacity(capturesOnly ? 16 : 44)
            let isWhite = whiteToMove

            for idx in 0..<64 {
                let piece = cells[idx]
                if piece == 0 { continue }
                if isWhite ? (piece < 0) : (piece > 0) { continue }

                let f = idx & 7
                let r = idx >> 3
                let absPiece = abs(piece)

                switch absPiece {
                case 1: // Pawn
                    let dir = isWhite ? 1 : -1
                    let nr = r + dir
                    let promoRank = isWhite ? 7 : 0
                    let startRank = isWhite ? 1 : 6

                    if !capturesOnly {
                        let fwd = (nr << 3) | f
                        if cells[fwd] == 0 {
                            if nr == promoRank {
                                for promo: Int8 in [5, 4, 3, 2] {
                                    moves.append(FastMove(from: UInt8(idx), to: UInt8(fwd), promo: promo, captured: 0, isEnPassant: false, isCastle: false))
                                }
                            } else {
                                moves.append(FastMove(from: UInt8(idx), to: UInt8(fwd), promo: 0, captured: 0, isEnPassant: false, isCastle: false))
                                if r == startRank {
                                    let dbl = ((r + dir * 2) << 3) | f
                                    if cells[dbl] == 0 {
                                        moves.append(FastMove(from: UInt8(idx), to: UInt8(dbl), promo: 0, captured: 0, isEnPassant: false, isCastle: false))
                                    }
                                }
                            }
                        }
                    } else if nr == promoRank {
                        // Include quiet queen promotions in quiescence search
                        let fwd = (nr << 3) | f
                        if cells[fwd] == 0 {
                            moves.append(FastMove(from: UInt8(idx), to: UInt8(fwd), promo: 5, captured: 0, isEnPassant: false, isCastle: false))
                        }
                    }

                    for df in [-1, 1] {
                        let tf = f + df
                        if tf < 0 || tf > 7 { continue }
                        let tIdx = (nr << 3) | tf
                        let target = cells[tIdx]
                        if target != 0 && (isWhite ? target < 0 : target > 0) {
                            if nr == promoRank {
                                let promos: [Int8] = capturesOnly ? [5] : [5, 4, 3, 2]
                                for promo in promos {
                                    moves.append(FastMove(from: UInt8(idx), to: UInt8(tIdx), promo: promo, captured: target, isEnPassant: false, isCastle: false))
                                }
                            } else {
                                moves.append(FastMove(from: UInt8(idx), to: UInt8(tIdx), promo: 0, captured: target, isEnPassant: false, isCastle: false))
                            }
                        } else if Int8(tIdx) == epSquare {
                            let epCapIdx = (r << 3) | tf
                            let epVictim = cells[epCapIdx]
                            if epVictim == (isWhite ? -1 : 1) {
                                moves.append(FastMove(from: UInt8(idx), to: UInt8(tIdx), promo: 0, captured: epVictim, isEnPassant: true, isCastle: false))
                            }
                        }
                    }

                case 2: // Knight
                    for i in 0..<8 {
                        let tf = f + Self.knightDF[i]
                        let tr = r + Self.knightDR[i]
                        if (tf | tr) & ~7 != 0 { continue }
                        let tIdx = (tr << 3) | tf
                        let target = cells[tIdx]
                        if target == 0 {
                            if !capturesOnly {
                                moves.append(FastMove(from: UInt8(idx), to: UInt8(tIdx), promo: 0, captured: 0, isEnPassant: false, isCastle: false))
                            }
                        } else if isWhite ? (target < 0) : (target > 0) {
                            moves.append(FastMove(from: UInt8(idx), to: UInt8(tIdx), promo: 0, captured: target, isEnPassant: false, isCastle: false))
                        }
                    }

                case 3, 4, 5: // Bishop, Rook, Queen
                    if absPiece != 4 {
                        for i in 0..<4 {
                            let df = Self.bishopDF[i]
                            let dr = Self.bishopDR[i]
                            var cf = f + df
                            var cr = r + dr
                            while (cf | cr) & ~7 == 0 {
                                let tIdx = (cr << 3) | cf
                                let target = cells[tIdx]
                                if target == 0 {
                                    if !capturesOnly {
                                        moves.append(FastMove(from: UInt8(idx), to: UInt8(tIdx), promo: 0, captured: 0, isEnPassant: false, isCastle: false))
                                    }
                                } else {
                                    if isWhite ? (target < 0) : (target > 0) {
                                        moves.append(FastMove(from: UInt8(idx), to: UInt8(tIdx), promo: 0, captured: target, isEnPassant: false, isCastle: false))
                                    }
                                    break
                                }
                                cf += df
                                cr += dr
                            }
                        }
                    }
                    if absPiece != 3 {
                        for i in 0..<4 {
                            let df = Self.rookDF[i]
                            let dr = Self.rookDR[i]
                            var cf = f + df
                            var cr = r + dr
                            while (cf | cr) & ~7 == 0 {
                                let tIdx = (cr << 3) | cf
                                let target = cells[tIdx]
                                if target == 0 {
                                    if !capturesOnly {
                                        moves.append(FastMove(from: UInt8(idx), to: UInt8(tIdx), promo: 0, captured: 0, isEnPassant: false, isCastle: false))
                                    }
                                } else {
                                    if isWhite ? (target < 0) : (target > 0) {
                                        moves.append(FastMove(from: UInt8(idx), to: UInt8(tIdx), promo: 0, captured: target, isEnPassant: false, isCastle: false))
                                    }
                                    break
                                }
                                cf += df
                                cr += dr
                            }
                        }
                    }

                case 6: // King
                    for i in 0..<8 {
                        let tf = f + Self.kingDF[i]
                        let tr = r + Self.kingDR[i]
                        if (tf | tr) & ~7 != 0 { continue }
                        let tIdx = (tr << 3) | tf
                        let target = cells[tIdx]
                        if target == 0 {
                            if !capturesOnly {
                                moves.append(FastMove(from: UInt8(idx), to: UInt8(tIdx), promo: 0, captured: 0, isEnPassant: false, isCastle: false))
                            }
                        } else if isWhite ? (target < 0) : (target > 0) {
                            moves.append(FastMove(from: UInt8(idx), to: UInt8(tIdx), promo: 0, captured: target, isEnPassant: false, isCastle: false))
                        }
                    }

                    if !capturesOnly {
                        let homeRank = isWhite ? 0 : 7
                        let base = homeRank << 3
                        if idx == (base | 4) && !isAttacked(square: idx, byWhite: !isWhite) {
                            let ksBit: UInt8 = isWhite ? 1 : 4
                            let qsBit: UInt8 = isWhite ? 2 : 8
                            let friendlyRook: Int8 = isWhite ? 4 : -4

                            if (castlingMask & ksBit) != 0,
                               cells[base | 5] == 0,
                               cells[base | 6] == 0,
                               cells[base | 7] == friendlyRook,
                               !isAttacked(square: base | 5, byWhite: !isWhite),
                               !isAttacked(square: base | 6, byWhite: !isWhite) {
                                moves.append(FastMove(from: UInt8(idx), to: UInt8(base | 6), promo: 0, captured: 0, isEnPassant: false, isCastle: true))
                            }
                            if (castlingMask & qsBit) != 0,
                               cells[base | 1] == 0,
                               cells[base | 2] == 0,
                               cells[base | 3] == 0,
                               cells[base] == friendlyRook,
                               !isAttacked(square: base | 3, byWhite: !isWhite),
                               !isAttacked(square: base | 2, byWhite: !isWhite) {
                                moves.append(FastMove(from: UInt8(idx), to: UInt8(base | 2), promo: 0, captured: 0, isEnPassant: false, isCastle: true))
                            }
                        }
                    }

                default:
                    break
                }
            }

            return moves
        }

        /// Static evaluation in centipawns from the side-to-move's perspective.
        func evaluate() -> Int {
            var score = 0
            var whiteBishops = 0
            var blackBishops = 0
            var nonPawnMaterial = 0

            for idx in 0..<64 {
                let code = cells[idx]
                if code == 0 { continue }
                let absCode = Int(abs(code))
                let isWhite = code > 0
                // PSTs are indexed from White's perspective with rank 7 (a8=0) at top:
                // White square index mapped to table: `idx ^ 56`; Black mirrored vertically: `idx`.
                let pstIdx = isWhite ? (idx ^ 56) : idx

                let pieceVal: Int
                switch absCode {
                case 1:
                    pieceVal = 100 + Self.pawnPST[pstIdx]
                case 2:
                    pieceVal = 320 + Self.knightPST[pstIdx]
                    nonPawnMaterial += 320
                case 3:
                    pieceVal = 330 + Self.bishopPST[pstIdx]
                    nonPawnMaterial += 330
                    if isWhite { whiteBishops += 1 } else { blackBishops += 1 }
                case 4:
                    pieceVal = 500 + Self.rookPST[pstIdx]
                    nonPawnMaterial += 500
                case 5:
                    pieceVal = 900 + Self.queenPST[pstIdx]
                    nonPawnMaterial += 900
                case 6:
                    pieceVal = 0 // Evaluated below with endgame blend
                default:
                    pieceVal = 0
                }
                score += isWhite ? pieceVal : -pieceVal
            }

            // King safety in middlegame vs centralization in endgame.
            let isEndgame = nonPawnMaterial <= 2_600
            let wkPst = whiteKingSq ^ 56
            let bkPst = blackKingSq
            if isEndgame {
                score += Self.kingEndgamePST[wkPst] - Self.kingEndgamePST[bkPst]
            } else {
                score += Self.kingMiddlegamePST[wkPst] - Self.kingMiddlegamePST[bkPst]
            }

            // Bishop pair bonus.
            if whiteBishops >= 2 { score += 30 }
            if blackBishops >= 2 { score -= 30 }

            return whiteToMove ? score : -score
        }

        // Direction lookup tables
        private static let knightDF = [-2, -2, -1, -1, 1, 1, 2, 2]
        private static let knightDR = [-1, 1, -2, 2, -2, 2, -1, 1]
        private static let kingDF = [-1, -1, -1, 0, 0, 1, 1, 1]
        private static let kingDR = [-1, 0, 1, -1, 1, -1, 0, 1]
        private static let bishopDF = [-1, -1, 1, 1]
        private static let bishopDR = [-1, 1, -1, 1]
        private static let rookDF = [-1, 1, 0, 0]
        private static let rookDR = [0, 0, -1, 1]

        // Simplified Evaluation Function piece-square tables (rank 8 at top, a8..h1).
        private static let pawnPST: [Int] = [
             0,  0,  0,  0,  0,  0,  0,  0,
            50, 50, 50, 50, 50, 50, 50, 50,
            10, 10, 20, 30, 30, 20, 10, 10,
             5,  5, 10, 25, 25, 10,  5,  5,
             0,  0,  0, 20, 20,  0,  0,  0,
             5, -5,-10,  0,  0,-10, -5,  5,
             5, 10, 10,-20,-20, 10, 10,  5,
             0,  0,  0,  0,  0,  0,  0,  0,
        ]

        private static let knightPST: [Int] = [
            -50,-40,-30,-30,-30,-30,-40,-50,
            -40,-20,  0,  0,  0,  0,-20,-40,
            -30,  0, 10, 15, 15, 10,  0,-30,
            -30,  5, 15, 20, 20, 15,  5,-30,
            -30,  0, 15, 20, 20, 15,  0,-30,
            -30,  5, 10, 15, 15, 10,  5,-30,
            -40,-20,  0,  5,  5,  0,-20,-40,
            -50,-40,-30,-30,-30,-30,-40,-50,
        ]

        private static let bishopPST: [Int] = [
            -20,-10,-10,-10,-10,-10,-10,-20,
            -10,  0,  0,  0,  0,  0,  0,-10,
            -10,  0,  5, 10, 10,  5,  0,-10,
            -10,  5,  5, 10, 10,  5,  5,-10,
            -10,  0, 10, 10, 10, 10,  0,-10,
            -10, 10, 10, 10, 10, 10, 10,-10,
            -10,  5,  0,  0,  0,  0,  5,-10,
            -20,-10,-10,-10,-10,-10,-10,-20,
        ]

        private static let rookPST: [Int] = [
             0,  0,  0,  0,  0,  0,  0,  0,
             5, 10, 10, 10, 10, 10, 10,  5,
            -5,  0,  0,  0,  0,  0,  0, -5,
            -5,  0,  0,  0,  0,  0,  0, -5,
            -5,  0,  0,  0,  0,  0,  0, -5,
            -5,  0,  0,  0,  0,  0,  0, -5,
            -5,  0,  0,  0,  0,  0,  0, -5,
             0,  0,  0,  5,  5,  0,  0,  0,
        ]

        private static let queenPST: [Int] = [
            -20,-10,-10, -5, -5,-10,-10,-20,
            -10,  0,  0,  0,  0,  0,  0,-10,
            -10,  0,  5,  5,  5,  5,  0,-10,
             -5,  0,  5,  5,  5,  5,  0, -5,
              0,  0,  5,  5,  5,  5,  0, -5,
            -10,  5,  5,  5,  5,  5,  0,-10,
            -10,  0,  5,  0,  0,  0,  0,-10,
            -20,-10,-10, -5, -5,-10,-10,-20,
        ]

        private static let kingMiddlegamePST: [Int] = [
            -30,-40,-40,-50,-50,-40,-40,-30,
            -30,-40,-40,-50,-50,-40,-40,-30,
            -30,-40,-40,-50,-50,-40,-40,-30,
            -30,-40,-40,-50,-50,-40,-40,-30,
            -20,-30,-30,-40,-40,-30,-30,-20,
            -10,-20,-20,-20,-20,-20,-20,-10,
             20, 20,  0,  0,  0,  0, 20, 20,
             20, 30, 10,  0,  0, 10, 30, 20,
        ]

        private static let kingEndgamePST: [Int] = [
            -50,-40,-30,-20,-20,-30,-40,-50,
            -30,-20,-10,  0,  0,-10,-20,-30,
            -30,-10, 20, 30, 30, 20,-10,-30,
            -30,-10, 30, 40, 40, 30,-10,-30,
            -30,-10, 30, 40, 40, 30,-10,-30,
            -30,-10, 20, 30, 30, 20,-10,-30,
            -30,-30,  0,  0,  0,  0,-30,-30,
            -50,-30,-30,-30,-30,-30,-30,-50,
        ]
    }

    private struct AlphaBetaSearcher {
        var board: FastBoard
        let qDepth: Int
        let nodeBudget: Int
        var nodesSearched: Int = 0
        var aborted: Bool = false

        private static let pieceWeights = [0, 100, 320, 330, 500, 900, 20_000]

        struct RootResult {
            let bestMove: FastMove?
            let bestScore: Int
            let scoredMoves: [(move: FastMove, score: Int)]
            let completed: Bool
        }

        mutating func searchRoot(depth: Int, previousBest: FastMove) -> RootResult {
            var moves = board.generatePseudoLegalMoves(capturesOnly: false)
            orderMoves(&moves, pvMove: previousBest)

            var alpha = -infinityScore
            let beta = infinityScore
            var bestMove: FastMove? = nil
            var bestScore = -infinityScore
            var scored: [(move: FastMove, score: Int)] = []
            let moverWhite = board.whiteToMove

            for move in moves {
                let undo = board.makeMove(move)
                if board.inCheck(white: moverWhite) {
                    board.unmakeMove(move, undo: undo)
                    continue
                }

                let score = -negamax(depth: depth - 1, alpha: -beta, beta: -alpha, ply: 1)
                board.unmakeMove(move, undo: undo)

                if aborted && depth > 1 {
                    return RootResult(bestMove: bestMove, bestScore: bestScore, scoredMoves: scored, completed: false)
                }

                scored.append((move, score))
                if score > bestScore {
                    bestScore = score
                    bestMove = move
                }
                if score > alpha {
                    alpha = score
                }
            }

            return RootResult(bestMove: bestMove, bestScore: bestScore, scoredMoves: scored, completed: !aborted || depth == 1)
        }

        private mutating func negamax(depth: Int, alpha initialAlpha: Int, beta: Int, ply: Int) -> Int {
            nodesSearched += 1
            if nodesSearched >= nodeBudget {
                aborted = true
                return 0
            }

            if board.halfmoveClock >= 100 {
                return 0
            }

            if depth <= 0 {
                if board.inCheck(white: board.whiteToMove), !board.hasAnyLegalMove() {
                    return -mateScore + ply
                }
                if qDepth > 0 {
                    return quiescence(alpha: initialAlpha, beta: beta, remainingQDepth: qDepth)
                }
                return board.evaluate()
            }

            var moves = board.generatePseudoLegalMoves(capturesOnly: false)
            orderMoves(&moves, pvMove: .none)

            var alpha = initialAlpha
            var legalCount = 0
            let moverWhite = board.whiteToMove

            for move in moves {
                let undo = board.makeMove(move)
                if board.inCheck(white: moverWhite) {
                    board.unmakeMove(move, undo: undo)
                    continue
                }
                legalCount += 1

                let score = -negamax(depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
                board.unmakeMove(move, undo: undo)

                if aborted { return 0 }

                if score >= beta {
                    return beta
                }
                if score > alpha {
                    alpha = score
                }
            }

            if legalCount == 0 {
                if board.inCheck(white: moverWhite) {
                    return -mateScore + ply
                }
                return 0
            }

            return alpha
        }

        private mutating func quiescence(alpha initialAlpha: Int, beta: Int, remainingQDepth: Int) -> Int {
            nodesSearched += 1
            if nodesSearched >= nodeBudget {
                aborted = true
                return 0
            }

            let standPat = board.evaluate()
            if standPat >= beta {
                return beta
            }
            var alpha = max(initialAlpha, standPat)
            if remainingQDepth <= 0 {
                return alpha
            }

            var captures = board.generatePseudoLegalMoves(capturesOnly: true)
            orderMoves(&captures, pvMove: .none)

            let moverWhite = board.whiteToMove
            for move in captures {
                let undo = board.makeMove(move)
                if board.inCheck(white: moverWhite) {
                    board.unmakeMove(move, undo: undo)
                    continue
                }

                let score = -quiescence(alpha: -beta, beta: -alpha, remainingQDepth: remainingQDepth - 1)
                board.unmakeMove(move, undo: undo)

                if aborted { return 0 }

                if score >= beta {
                    return beta
                }
                if score > alpha {
                    alpha = score
                }
            }

            return alpha
        }

        private func moveOrderScore(_ move: FastMove, pvMove: FastMove) -> Int {
            if move == pvMove && pvMove != .none {
                return 1_000_000
            }
            var score = 0
            if move.captured != 0 {
                let victim = Self.pieceWeights[Int(abs(move.captured))]
                let attacker = Self.pieceWeights[Int(abs(board.cells[Int(move.from)]))]
                score += 10_000 + (victim * 10) - attacker
            }
            if move.promo != 0 {
                score += 9_000 + Self.pieceWeights[Int(move.promo)]
            }
            if move.isCastle {
                score += 200
            }
            return score
        }

        private func orderMoves(_ moves: inout [FastMove], pvMove: FastMove) {
            moves.sort { lhs, rhs in
                moveOrderScore(lhs, pvMove: pvMove) > moveOrderScore(rhs, pvMove: pvMove)
            }
        }
    }
}

// MARK: - ChessLLMDecision & ChessLLMPrompt

/// Parsed move and cleaned commentary returned by a local or cloud LLM opponent.
public struct ChessLLMDecision: Sendable, Equatable, Hashable, Codable {
    public let move: ChessMove
    public let san: String
    public let commentary: String

    public init(move: ChessMove, san: String, commentary: String) {
        self.move = move
        self.san = san
        self.commentary = commentary
    }
}

/// Prompt builder and robust response parser for local MLX and cloud LLM chess opponents.
public enum ChessLLMPrompt {
    /// System instructions guiding an LLM to pick a strictly legal chess move with short commentary.
    public static func instructions(for color: ChessColor, persona: String = "MicroDuck") -> String {
        """
        You are \(persona), a playful and sharp chess partner playing as \(color.label).
        Pick ONE strictly legal move from the provided legal move list.
        Reply with a single compact JSON object only, with no markdown fences:
        {"move":"<uci>","comment":"<short friendly sentence under 18 words>"}
        Never invent illegal moves. Never use em-dashes in your comment.
        """
    }

    /// User prompt for an active `ChessGame`, including FEN, recent SAN history, and every legal move.
    public static func userPrompt(for game: ChessGame) -> String {
        let recentSANs = game.history.suffix(12).map(\.san)
        return userPrompt(for: game.state, recentSANs: recentSANs)
    }

    /// User prompt for a raw `ChessBoardState` and optional recent SAN list.
    public static func userPrompt(for state: ChessBoardState, recentSANs: [String] = []) -> String {
        let legal = state.legalMoves()
        let moveList = legal.map { move -> String in
            let san = state.san(for: move) ?? move.uci
            return "\(move.uci) (\(san))"
        }.joined(separator: ", ")

        let historyLine = recentSANs.isEmpty
            ? "Opening move (no moves played yet)"
            : recentSANs.joined(separator: " ")

        let checkNote = state.isInCheck(state.sideToMove)
            ? "\nStatus: \(state.sideToMove.label) is in CHECK."
            : ""

        return """
        Side to move: \(state.sideToMove.label)
        FEN: \(state.fen)\(checkNote)
        Recent moves: \(historyLine)
        Legal moves (UCI and SAN): \(moveList)

        Choose the strongest move from the legal moves list above and return JSON {"move":"<uci>","comment":"<short remark>"}.
        """
    }

    /// Extracts a legal chess move and sanitized commentary from raw LLM text.
    /// Supports JSON objects, markdown-fenced JSON, `MOVE:` lines, and inline UCI/SAN tokens.
    public static func parseResponse(_ raw: String, in state: ChessBoardState) -> ChessLLMDecision? {
        let stripped = stripThinkingBlocks(raw)
        let primaryText = stripped.isEmpty ? raw : stripped

        if let decision = parseJSONDecision(in: primaryText, state: state) {
            return decision
        }
        if let decision = parseLabeledLineDecision(in: primaryText, state: state) {
            return decision
        }
        if let decision = parseTokenScanDecision(in: primaryText, state: state) {
            return decision
        }
        // Last resort: scan raw text if stripping thinking blocks removed the move.
        if stripped != raw {
            if let decision = parseJSONDecision(in: raw, state: state) {
                return decision
            }
            if let decision = parseLabeledLineDecision(in: raw, state: state) {
                return decision
            }
            if let decision = parseTokenScanDecision(in: raw, state: state) {
                return decision
            }
        }
        return nil
    }

    /// Removes em-dashes and excessive whitespace from LLM commentary.
    public static func sanitizeCommentary(_ raw: String?, fallbackSAN: String) -> String {
        guard let raw else {
            return "Played \(fallbackSAN)."
        }
        let emDash = Unicode.Scalar(UInt32(0x2014)).map { String($0) } ?? ""
        let enDash = Unicode.Scalar(UInt32(0x2013)).map { String($0) } ?? ""
        var cleaned = raw
            .replacingOccurrences(of: emDash, with: ", ")
            .replacingOccurrences(of: enDash, with: ", ")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))

        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        while cleaned.contains(" ,") {
            cleaned = cleaned.replacingOccurrences(of: " ,", with: ",")
        }
        while cleaned.contains(",,") {
            cleaned = cleaned.replacingOccurrences(of: ",,", with: ",")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return "Played \(fallbackSAN)."
        }
        if cleaned.count > 160 {
            let cutoff = cleaned.index(cleaned.startIndex, offsetBy: 157)
            cleaned = String(cleaned[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return cleaned
    }

    // MARK: Private Parsing Helpers

    private static func stripThinkingBlocks(_ text: String) -> String {
        var working = text
        // Remove <think>...</think> blocks produced by reasoning models.
        while let start = working.range(of: "<think>", options: .caseInsensitive),
              let end = working.range(of: "</think>", options: .caseInsensitive, range: start.upperBound..<working.endIndex) {
            working.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseJSONDecision(in text: String, state: ChessBoardState) -> ChessLLMDecision? {
        // Extract candidate {...} slices, preferring the last valid JSON object in the response.
        let candidates = extractJSONObjects(from: text)
        for candidate in candidates.reversed() {
            guard let data = candidate.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let moveKeys = ["move", "uci", "san", "best_move", "bestMove"]
            var rawMove: String?
            for key in moveKeys {
                if let val = obj[key] as? String, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    rawMove = val
                    break
                }
            }
            guard let moveString = rawMove,
                  let resolved = resolveMoveField(moveString, in: state) else {
                continue
            }
            let commentKeys = ["comment", "commentary", "reason", "message", "note"]
            var rawComment: String?
            for key in commentKeys {
                if let val = obj[key] as? String {
                    rawComment = val
                    break
                }
            }
            let san = state.san(for: resolved) ?? resolved.uci
            return ChessLLMDecision(
                move: resolved,
                san: san,
                commentary: sanitizeCommentary(rawComment, fallbackSAN: san)
            )
        }
        return nil
    }

    private static func resolveMoveField(_ field: String, in state: ChessBoardState) -> ChessMove? {
        if let direct = state.move(matching: field) {
            return direct
        }
        // Handle formats like "e2e4 (e4)" where the model echoed both UCI and SAN.
        let tokens = field.split(whereSeparator: { $0.isWhitespace || "()[]{}:,;".contains($0) }).map(String.init)
        for token in tokens {
            if let matched = state.move(matching: token) {
                return matched
            }
        }
        return nil
    }

    private static func extractJSONObjects(from text: String) -> [String] {
        var results: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var startIndex: String.Index?

        var idx = text.startIndex
        while idx < text.endIndex {
            let ch = text[idx]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    if depth == 0 {
                        startIndex = idx
                    }
                    depth += 1
                } else if ch == "}" {
                    if depth > 0 {
                        depth -= 1
                        if depth == 0, let start = startIndex {
                            results.append(String(text[start...idx]))
                            startIndex = nil
                        }
                    }
                }
            }
            idx = text.index(after: idx)
        }
        return results
    }

    private static func parseLabeledLineDecision(in text: String, state: ChessBoardState) -> ChessLLMDecision? {
        let lines = text.components(separatedBy: .newlines)
        var matchedMove: ChessMove?
        var rawComment: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if matchedMove == nil,
               (lower.hasPrefix("move:") || lower.hasPrefix("best move:") || lower.hasPrefix("uci:") || lower.hasPrefix("san:")) {
                if let colon = trimmed.firstIndex(of: ":") {
                    let value = String(trimmed[trimmed.index(after: colon)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    matchedMove = resolveMoveField(value, in: state)
                }
            } else if rawComment == nil,
                      (lower.hasPrefix("comment:") || lower.hasPrefix("commentary:") || lower.hasPrefix("reason:")) {
                if let colon = trimmed.firstIndex(of: ":") {
                    rawComment = String(trimmed[trimmed.index(after: colon)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        guard let move = matchedMove else { return nil }
        let san = state.san(for: move) ?? move.uci
        return ChessLLMDecision(
            move: move,
            san: san,
            commentary: sanitizeCommentary(rawComment, fallbackSAN: san)
        )
    }

    private static func parseTokenScanDecision(in text: String, state: ChessBoardState) -> ChessLLMDecision? {
        let legal = state.legalMoves()
        guard !legal.isEmpty else { return nil }

        let tokens = text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?'\"`()[]{}*")) }
            .filter { !$0.isEmpty }

        // Pass 1: Look for exact legal UCI tokens first (highest precision).
        let uciLookup = Dictionary(uniqueKeysWithValues: legal.map { ($0.uci, $0) })
        for token in tokens {
            let compact = token.replacingOccurrences(of: "-", with: "").lowercased()
            if let move = uciLookup[compact] {
                let san = state.san(for: move) ?? move.uci
                return ChessLLMDecision(
                    move: move,
                    san: san,
                    commentary: sanitizeCommentary(extractProseComment(from: text, excluding: token), fallbackSAN: san)
                )
            }
        }

        // Pass 2: Look for exact legal SAN tokens (case-sensitive to avoid matching English words).
        var sanLookup: [String: ChessMove] = [:]
        var strippedSanLookup: [String: ChessMove] = [:]
        for move in legal {
            if let san = state.san(for: move) {
                sanLookup[san] = move
                let stripped = san.filter { !"+#".contains($0) }
                strippedSanLookup[stripped] = move
            }
        }

        for token in tokens {
            let normalized = token
                .replacingOccurrences(of: "0-0-0", with: "O-O-O")
                .replacingOccurrences(of: "0-0", with: "O-O")
            if let move = sanLookup[normalized] ?? strippedSanLookup[normalized] {
                let san = state.san(for: move) ?? move.uci
                return ChessLLMDecision(
                    move: move,
                    san: san,
                    commentary: sanitizeCommentary(extractProseComment(from: text, excluding: token), fallbackSAN: san)
                )
            }
        }

        return nil
    }

    private static func extractProseComment(from text: String, excluding token: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned == token || cleaned.isEmpty {
            return nil
        }
        // Only treat short single-paragraph responses as usable commentary.
        if cleaned.count <= 140 {
            return cleaned
        }
        return nil
    }
}
