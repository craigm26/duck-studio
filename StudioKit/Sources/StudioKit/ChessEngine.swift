import Foundation

// MARK: - ChessColor

/// Side to move or piece owner in a chess game.
public enum ChessColor: String, CaseIterable, Sendable, Equatable, Hashable, Codable {
    case white
    case black

    /// The opposing color.
    public var opposite: ChessColor {
        self == .white ? .black : .white
    }

    /// Human-readable label ("White" or "Black").
    public var label: String {
        self == .white ? "White" : "Black"
    }

    /// FEN active-color character ("w" or "b").
    public var fenChar: Character {
        self == .white ? "w" : "b"
    }

    /// Forward pawn rank delta (+1 for White, -1 for Black).
    public var pawnDirection: Int {
        self == .white ? 1 : -1
    }

    /// Starting rank index (0-based) for pawns (1 for White, 6 for Black).
    public var pawnStartRank: Int {
        self == .white ? 1 : 6
    }

    /// Promotion rank index (0-based) for pawns (7 for White, 0 for Black).
    public var promotionRank: Int {
        self == .white ? 7 : 0
    }

    /// Home back rank index (0-based: 0 for White, 7 for Black).
    public var backRank: Int {
        self == .white ? 0 : 7
    }
}

// MARK: - ChessPieceKind

/// One of the six chess piece types.
public enum ChessPieceKind: String, CaseIterable, Sendable, Equatable, Hashable, Codable {
    case pawn
    case knight
    case bishop
    case rook
    case queen
    case king

    /// Standard material value in pawn units (P=1, N=3, B=3, R=5, Q=9, K=0).
    public var materialValue: Int {
        switch self {
        case .pawn: return 1
        case .knight: return 3
        case .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }

    /// Evaluation material value in centipawns.
    public var centipawnValue: Int {
        switch self {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook: return 500
        case .queen: return 900
        case .king: return 20_000
        }
    }

    /// Uppercase SAN and FEN symbol ("P", "N", "B", "R", "Q", "K").
    public var symbol: String {
        switch self {
        case .pawn: return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }

    /// Lowercase UCI piece character ("p", "n", "b", "r", "q", "k").
    public var uciChar: Character {
        switch self {
        case .pawn: return "p"
        case .knight: return "n"
        case .bishop: return "b"
        case .rook: return "r"
        case .queen: return "q"
        case .king: return "k"
        }
    }

    /// Human-readable piece label.
    public var label: String {
        switch self {
        case .pawn: return "Pawn"
        case .knight: return "Knight"
        case .bishop: return "Bishop"
        case .rook: return "Rook"
        case .queen: return "Queen"
        case .king: return "King"
        }
    }

    /// Standard promotion choices in UI order.
    public static let promotionKinds: [ChessPieceKind] = [.queen, .rook, .bishop, .knight]

    /// Standard Unicode chess glyph for a given color.
    public func unicodeGlyph(for color: ChessColor) -> String {
        switch (color, self) {
        case (.white, .king): return "\u{2654}"
        case (.white, .queen): return "\u{2655}"
        case (.white, .rook): return "\u{2656}"
        case (.white, .bishop): return "\u{2657}"
        case (.white, .knight): return "\u{2658}"
        case (.white, .pawn): return "\u{2659}"
        case (.black, .king): return "\u{265A}"
        case (.black, .queen): return "\u{265B}"
        case (.black, .rook): return "\u{265C}"
        case (.black, .bishop): return "\u{265D}"
        case (.black, .knight): return "\u{265E}"
        case (.black, .pawn): return "\u{265F}"
        }
    }

    /// Initialize from a FEN or SAN letter (case-insensitive).
    public init?(fenSymbol: Character) {
        switch fenSymbol.lowercased() {
        case "p": self = .pawn
        case "n": self = .knight
        case "b": self = .bishop
        case "r": self = .rook
        case "q": self = .queen
        case "k": self = .king
        default: return nil
        }
    }
}

// MARK: - ChessPiece

/// A chess piece with a color and kind.
public struct ChessPiece: Sendable, Equatable, Hashable, Codable {
    public let color: ChessColor
    public let kind: ChessPieceKind

    public init(color: ChessColor, kind: ChessPieceKind) {
        self.color = color
        self.kind = kind
    }

    /// FEN character (uppercase for White, lowercase for Black).
    public var fenChar: Character {
        let ch = kind.uciChar
        return color == .white ? Character(ch.uppercased()) : ch
    }

    /// Unicode glyph for this piece.
    public var unicodeGlyph: String {
        kind.unicodeGlyph(for: color)
    }

    /// Standard material value in pawns.
    public var materialValue: Int {
        kind.materialValue
    }

    /// Initialize from a FEN piece character.
    public init?(fenChar: Character) {
        guard let kind = ChessPieceKind(fenSymbol: fenChar) else { return nil }
        let isUpper = fenChar.isUppercase
        let isLower = fenChar.isLowercase
        guard isUpper || isLower else { return nil }
        self.color = isUpper ? .white : .black
        self.kind = kind
    }
}

// MARK: - ChessSquare

/// A square on the 8x8 chessboard, with file 0..7 ('a'..'h') and rank 0..7 ('1'..'8').
public struct ChessSquare: Sendable, Equatable, Hashable, Codable, Comparable, CustomStringConvertible {
    /// File index 0..7 corresponding to 'a'..'h'.
    public let file: Int
    /// Rank index 0..7 corresponding to '1'..'8'.
    public let rank: Int

    /// Creates a square if `file` and `rank` are both within `0...7`.
    public init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.file = file
        self.rank = rank
    }

    /// Creates a square from a 0..63 index (`rank * 8 + file`).
    public init?(index: Int) {
        guard (0..<64).contains(index) else { return nil }
        self.file = index & 7
        self.rank = index >> 3
    }

    /// Creates a square from standard algebraic notation such as `"e4"`.
    public init?(algebraic: String) {
        let trimmed = algebraic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bytes = Array(trimmed.utf8)
        guard bytes.count == 2 else { return nil }
        let f = Int(bytes[0]) - Int(UInt8(ascii: "a"))
        let r = Int(bytes[1]) - Int(UInt8(ascii: "1"))
        guard (0..<8).contains(f), (0..<8).contains(r) else { return nil }
        self.file = f
        self.rank = r
    }

    @inline(__always)
    internal init(uncheckedFile: Int, uncheckedRank: Int) {
        self.file = uncheckedFile
        self.rank = uncheckedRank
    }

    @inline(__always)
    internal init(uncheckedIndex: Int) {
        self.file = uncheckedIndex & 7
        self.rank = uncheckedIndex >> 3
    }

    /// Zero-based index `0...63` where `a1 == 0`, `h1 == 7`, `a8 == 56`, `h8 == 63`.
    public var index: Int {
        (rank << 3) | file
    }

    private static let fileChars: [Character] = ["a", "b", "c", "d", "e", "f", "g", "h"]
    private static let rankChars: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8"]

    /// File letter `'a'...'h'`.
    public var fileChar: Character {
        Self.fileChars[file]
    }

    /// Rank digit `'1'...'8'`.
    public var rankChar: Character {
        Self.rankChars[rank]
    }

    /// Standard algebraic coordinate, e.g. `"e4"`.
    public var algebraic: String {
        String([fileChar, rankChar])
    }

    /// True for light squares (`h1`, `a8`), false for dark squares (`a1`, `h8`).
    public var isLightSquare: Bool {
        ((file + rank) & 1) == 1
    }

    public var description: String {
        algebraic
    }

    public static func < (lhs: ChessSquare, rhs: ChessSquare) -> Bool {
        lhs.index < rhs.index
    }

    /// All 64 squares ordered by index `0...63` (`a1` through `h8`).
    public static let allSquares: [ChessSquare] = (0..<64).map { ChessSquare(uncheckedIndex: $0) }
}

// MARK: - ChessMove

/// A chess move defined by origin square, destination square, and optional promotion piece.
public struct ChessMove: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public let from: ChessSquare
    public let to: ChessSquare
    public let promotion: ChessPieceKind?

    public init(from: ChessSquare, to: ChessSquare, promotion: ChessPieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    /// Parses a UCI move string such as `"e2e4"` or `"e7e8q"`.
    public init?(uci: String) {
        let cleaned = uci.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let chars = Array(cleaned)
        guard chars.count == 4 || chars.count == 5 else { return nil }
        guard let from = ChessSquare(algebraic: String(chars[0..<2])),
              let to = ChessSquare(algebraic: String(chars[2..<4])) else {
            return nil
        }
        if chars.count == 5 {
            guard let promo = ChessPieceKind(fenSymbol: chars[4]),
                  ChessPieceKind.promotionKinds.contains(promo) else {
                return nil
            }
            self.promotion = promo
        } else {
            self.promotion = nil
        }
        self.from = from
        self.to = to
    }

    /// Standard UCI representation, e.g. `"e2e4"` or `"e7e8q"`.
    public var uci: String {
        if let promo = promotion {
            return "\(from.algebraic)\(to.algebraic)\(promo.uciChar)"
        }
        return "\(from.algebraic)\(to.algebraic)"
    }

    public var description: String {
        uci
    }
}

// MARK: - ChessMoveRecord

/// A completed half-move recorded in game history.
public struct ChessMoveRecord: Sendable, Equatable, Hashable, Codable, Identifiable {
    /// One-based ply number (1 for White's first move, 2 for Black's first move, etc.).
    public let ply: Int
    public let move: ChessMove
    public let san: String
    public let piece: ChessPiece
    public let captured: ChessPiece?
    public let fenAfter: String
    public let commentary: String?

    public var id: Int { ply }

    public init(
        ply: Int = 1,
        move: ChessMove,
        san: String,
        piece: ChessPiece,
        captured: ChessPiece? = nil,
        fenAfter: String,
        commentary: String? = nil
    ) {
        self.ply = ply
        self.move = move
        self.san = san
        self.piece = piece
        self.captured = captured
        self.fenAfter = fenAfter
        self.commentary = commentary
    }
}

// MARK: - ChessGameStatus

/// Current lifecycle status of a chess game.
public enum ChessGameStatus: Sendable, Equatable, Hashable, Codable {
    case active
    case check(ChessColor)
    case checkmate(winner: ChessColor)
    case stalemate
    case drawFiftyMove
    case drawThreefoldRepetition
    case drawInsufficientMaterial
    case drawAgreement
    case resigned(winner: ChessColor)

    /// True if no further moves can be played.
    public var isGameOver: Bool {
        switch self {
        case .active, .check:
            return false
        case .checkmate, .stalemate, .drawFiftyMove, .drawThreefoldRepetition,
             .drawInsufficientMaterial, .drawAgreement, .resigned:
            return true
        }
    }

    /// Winning side, if the game ended decisively.
    public var winner: ChessColor? {
        switch self {
        case .checkmate(let winner), .resigned(let winner):
            return winner
        default:
            return nil
        }
    }

    /// True if the game ended in a draw.
    public var isDraw: Bool {
        switch self {
        case .stalemate, .drawFiftyMove, .drawThreefoldRepetition,
             .drawInsufficientMaterial, .drawAgreement:
            return true
        default:
            return false
        }
    }

    /// Concise, user-facing status label.
    public var summaryText: String {
        switch self {
        case .active:
            return "Active"
        case .check(let color):
            return "\(color.label) in check"
        case .checkmate(let winner):
            return "Checkmate, \(winner.label) wins"
        case .stalemate:
            return "Draw by stalemate"
        case .drawFiftyMove:
            return "Draw by 50-move rule"
        case .drawThreefoldRepetition:
            return "Draw by threefold repetition"
        case .drawInsufficientMaterial:
            return "Draw by insufficient material"
        case .drawAgreement:
            return "Draw by agreement"
        case .resigned(let winner):
            return "\(winner.opposite.label) resigned, \(winner.label) wins"
        }
    }
}

// MARK: - ChessCastlingRights

/// Castling availability flags for both sides.
public struct ChessCastlingRights: Sendable, Equatable, Hashable, Codable {
    public var whiteKingside: Bool
    public var whiteQueenside: Bool
    public var blackKingside: Bool
    public var blackQueenside: Bool

    public init(
        whiteKingside: Bool = true,
        whiteQueenside: Bool = true,
        blackKingside: Bool = true,
        blackQueenside: Bool = true
    ) {
        self.whiteKingside = whiteKingside
        self.whiteQueenside = whiteQueenside
        self.blackKingside = blackKingside
        self.blackQueenside = blackQueenside
    }

    public static let all = ChessCastlingRights()
    public static let none = ChessCastlingRights(
        whiteKingside: false,
        whiteQueenside: false,
        blackKingside: false,
        blackQueenside: false
    )

    /// FEN castling field (e.g. `"KQkq"` or `"-"`).
    public var fenString: String {
        var result = ""
        if whiteKingside { result.append("K") }
        if whiteQueenside { result.append("Q") }
        if blackKingside { result.append("k") }
        if blackQueenside { result.append("q") }
        return result.isEmpty ? "-" : result
    }

    /// Parses a FEN castling availability field.
    public init?(fenString: String) {
        if fenString == "-" {
            self = .none
            return
        }
        guard !fenString.isEmpty else { return nil }
        var wk = false, wq = false, bk = false, bq = false
        for ch in fenString {
            switch ch {
            case "K":
                if wk { return nil }
                wk = true
            case "Q":
                if wq { return nil }
                wq = true
            case "k":
                if bk { return nil }
                bk = true
            case "q":
                if bq { return nil }
                bq = true
            default:
                return nil
            }
        }
        self.whiteKingside = wk
        self.whiteQueenside = wq
        self.blackKingside = bk
        self.blackQueenside = bq
    }

    /// Compact 4-bit mask representing castling flags.
    public var bitmask: UInt8 {
        var mask: UInt8 = 0
        if whiteKingside { mask |= 1 }
        if whiteQueenside { mask |= 2 }
        if blackKingside { mask |= 4 }
        if blackQueenside { mask |= 8 }
        return mask
    }
}

// MARK: - ChessBoardState

/// Complete value-type representation of a FIDE chess position.
public struct ChessBoardState: Sendable, Equatable, Hashable, Codable {
    /// Standard initial position FEN string.
    public static let standardInitialFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    /// Standard starting chess position.
    public static let standardInitial: ChessBoardState = {
        var squares = [ChessPiece?](repeating: nil, count: 64)
        let backRank: [ChessPieceKind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for file in 0..<8 {
            squares[file] = ChessPiece(color: .white, kind: backRank[file])
            squares[8 + file] = ChessPiece(color: .white, kind: .pawn)
            squares[48 + file] = ChessPiece(color: .black, kind: .pawn)
            squares[56 + file] = ChessPiece(color: .black, kind: backRank[file])
        }
        return ChessBoardState(
            squares: squares,
            sideToMove: .white,
            castlingRights: .all,
            enPassantTarget: nil,
            halfmoveClock: 0,
            fullmoveNumber: 1
        )
    }()

    /// Board squares indexed by `rank * 8 + file` (`a1 = 0`, `h8 = 63`).
    internal var squares: [ChessPiece?]
    public var sideToMove: ChessColor
    public var castlingRights: ChessCastlingRights
    public var enPassantTarget: ChessSquare?
    public var halfmoveClock: Int
    public var fullmoveNumber: Int

    internal init(
        squares: [ChessPiece?],
        sideToMove: ChessColor,
        castlingRights: ChessCastlingRights,
        enPassantTarget: ChessSquare?,
        halfmoveClock: Int,
        fullmoveNumber: Int
    ) {
        self.squares = squares
        self.sideToMove = sideToMove
        self.castlingRights = castlingRights
        self.enPassantTarget = enPassantTarget
        self.halfmoveClock = halfmoveClock
        self.fullmoveNumber = fullmoveNumber
    }

    /// Parses a standard FEN string (6 fields, or 4 fields with clocks defaulting to `0 1`).
    public init?(fen: String) {
        let parts = fen.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard parts.count == 6 || parts.count == 4 else { return nil }

        let ranks = parts[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return nil }

        var board = [ChessPiece?](repeating: nil, count: 64)
        var whiteKings = 0
        var blackKings = 0

        for (rankOffset, rankStr) in ranks.enumerated() {
            let rank = 7 - rankOffset
            var file = 0
            for ch in rankStr {
                if let digit = ch.wholeNumberValue, (1...8).contains(digit) {
                    file += digit
                } else if let piece = ChessPiece(fenChar: ch) {
                    guard file < 8 else { return nil }
                    board[(rank << 3) | file] = piece
                    if piece.kind == .king {
                        if piece.color == .white { whiteKings += 1 } else { blackKings += 1 }
                    }
                    file += 1
                } else {
                    return nil
                }
            }
            guard file == 8 else { return nil }
        }
        guard whiteKings == 1, blackKings == 1 else { return nil }

        let side: ChessColor
        switch parts[1] {
        case "w": side = .white
        case "b": side = .black
        default: return nil
        }

        guard let castling = ChessCastlingRights(fenString: parts[2]) else { return nil }

        let ep: ChessSquare?
        if parts[3] == "-" {
            ep = nil
        } else {
            guard let sq = ChessSquare(algebraic: parts[3]),
                  sq.rank == 2 || sq.rank == 5 else {
                return nil
            }
            ep = sq
        }

        let halfmove: Int
        let fullmove: Int
        if parts.count == 6 {
            guard let hm = Int(parts[4]), hm >= 0,
                  let fm = Int(parts[5]), fm >= 1 else {
                return nil
            }
            halfmove = hm
            fullmove = fm
        } else {
            halfmove = 0
            fullmove = 1
        }

        self.squares = board
        self.sideToMove = side
        self.castlingRights = castling
        self.enPassantTarget = ep
        self.halfmoveClock = halfmove
        self.fullmoveNumber = fullmove
    }

    /// Full 6-field FEN serialization of the current position.
    public var fen: String {
        var placement = ""
        placement.reserveCapacity(72)
        for rank in stride(from: 7, through: 0, by: -1) {
            var emptyCount = 0
            for file in 0..<8 {
                if let piece = squares[(rank << 3) | file] {
                    if emptyCount > 0 {
                        placement.append(String(emptyCount))
                        emptyCount = 0
                    }
                    placement.append(piece.fenChar)
                } else {
                    emptyCount += 1
                }
            }
            if emptyCount > 0 {
                placement.append(String(emptyCount))
            }
            if rank > 0 {
                placement.append("/")
            }
        }
        let epStr = enPassantTarget?.algebraic ?? "-"
        return "\(placement) \(sideToMove.fenChar) \(castlingRights.fenString) \(epStr) \(halfmoveClock) \(fullmoveNumber)"
    }

    /// Position identity key for FIDE threefold repetition detection (ignores move clocks
    /// and includes en passant only when a legal en passant capture actually exists).
    public var positionKey: String {
        var placement = ""
        placement.reserveCapacity(64)
        for idx in 0..<64 {
            if let piece = squares[idx] {
                placement.append(piece.fenChar)
            } else {
                placement.append(".")
            }
        }
        let epKey: String
        if let ep = enPassantTarget, hasLegalEnPassantCapture(to: ep) {
            epKey = ep.algebraic
        } else {
            epKey = "-"
        }
        return "\(placement) \(sideToMove.fenChar) \(castlingRights.fenString) \(epKey)"
    }

    /// Accesses the piece on a given square.
    public subscript(square: ChessSquare) -> ChessPiece? {
        get { squares[square.index] }
        set { squares[square.index] = newValue }
    }

    /// Accesses the piece at `(file, rank)` if within bounds `0...7`.
    public subscript(file: Int, rank: Int) -> ChessPiece? {
        get {
            guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
            return squares[(rank << 3) | file]
        }
        set {
            guard (0..<8).contains(file), (0..<8).contains(rank) else { return }
            squares[(rank << 3) | file] = newValue
        }
    }

    /// Returns the piece on the given square, if any.
    public func piece(at square: ChessSquare) -> ChessPiece? {
        squares[square.index]
    }

    /// Locates the king square for the given side.
    public func kingSquare(for color: ChessColor) -> ChessSquare? {
        for idx in 0..<64 {
            if let p = squares[idx], p.color == color && p.kind == .king {
                return ChessSquare(uncheckedIndex: idx)
            }
        }
        return nil
    }

    /// Material balance in pawn units (positive favors White, negative favors Black).
    public var materialBalance: Int {
        var total = 0
        for idx in 0..<64 {
            if let piece = squares[idx] {
                let value = piece.kind.materialValue
                total += piece.color == .white ? value : -value
            }
        }
        return total
    }

    // MARK: Attack & Check Detection

    /// Returns true if `square` is attacked by any piece belonging to `attacker`.
    public func isSquareAttacked(_ square: ChessSquare, by attacker: ChessColor) -> Bool {
        let f = square.file
        let r = square.rank

        // 1. Pawn attacks
        let pawnSourceRank = attacker == .white ? r - 1 : r + 1
        if pawnSourceRank >= 0 && pawnSourceRank < 8 {
            if f > 0, let p = squares[(pawnSourceRank << 3) | (f - 1)],
               p.color == attacker && p.kind == .pawn {
                return true
            }
            if f < 7, let p = squares[(pawnSourceRank << 3) | (f + 1)],
               p.color == attacker && p.kind == .pawn {
                return true
            }
        }

        // 2. Knight attacks
        for (df, dr) in Self.knightOffsets {
            let nf = f + df
            let nr = r + dr
            if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                if let p = squares[(nr << 3) | nf], p.color == attacker && p.kind == .knight {
                    return true
                }
            }
        }

        // 3. King attacks
        for (df, dr) in Self.kingOffsets {
            let kf = f + df
            let kr = r + dr
            if kf >= 0 && kf < 8 && kr >= 0 && kr < 8 {
                if let p = squares[(kr << 3) | kf], p.color == attacker && p.kind == .king {
                    return true
                }
            }
        }

        // 4. Diagonal rays (bishop / queen)
        for (df, dr) in Self.bishopDirections {
            var cf = f + df
            var cr = r + dr
            while cf >= 0 && cf < 8 && cr >= 0 && cr < 8 {
                if let p = squares[(cr << 3) | cf] {
                    if p.color == attacker && (p.kind == .bishop || p.kind == .queen) {
                        return true
                    }
                    break
                }
                cf += df
                cr += dr
            }
        }

        // 5. Orthogonal rays (rook / queen)
        for (df, dr) in Self.rookDirections {
            var cf = f + df
            var cr = r + dr
            while cf >= 0 && cf < 8 && cr >= 0 && cr < 8 {
                if let p = squares[(cr << 3) | cf] {
                    if p.color == attacker && (p.kind == .rook || p.kind == .queen) {
                        return true
                    }
                    break
                }
                cf += df
                cr += dr
            }
        }

        return false
    }

    /// Returns true if `color`'s king is currently in check.
    public func isInCheck(_ color: ChessColor) -> Bool {
        guard let kingSq = kingSquare(for: color) else { return false }
        return isSquareAttacked(kingSq, by: color.opposite)
    }

    // MARK: Legal Move Generation

    /// Generates all FIDE-legal moves for the side to move.
    public func legalMoves() -> [ChessMove] {
        var result: [ChessMove] = []
        result.reserveCapacity(40)
        let mover = sideToMove

        for idx in 0..<64 {
            guard let piece = squares[idx], piece.color == mover else { continue }
            let from = ChessSquare(uncheckedIndex: idx)
            appendLegalMoves(from: from, piece: piece, into: &result)
        }
        return result
    }

    /// Generates all FIDE-legal moves originating from `square`.
    public func legalMoves(from square: ChessSquare) -> [ChessMove] {
        guard let piece = squares[square.index], piece.color == sideToMove else {
            return []
        }
        var result: [ChessMove] = []
        appendLegalMoves(from: square, piece: piece, into: &result)
        return result
    }

    /// Returns true if `move` is legal in the current position.
    public func isLegalMove(_ move: ChessMove) -> Bool {
        legalMoves(from: move.from).contains(move)
    }

    /// Returns true if moving from `from` to `to` is a legal pawn promotion move.
    public func isPromotionMove(from: ChessSquare, to: ChessSquare) -> Bool {
        guard let piece = squares[from.index],
              piece.color == sideToMove,
              piece.kind == .pawn,
              to.rank == sideToMove.promotionRank else {
            return false
        }
        return legalMoves(from: from).contains { $0.to == to && $0.promotion != nil }
    }

    /// Applies a legal move and returns the resulting board state, or `nil` if illegal.
    public func applying(_ move: ChessMove) -> ChessBoardState? {
        guard isLegalMove(move) else { return nil }
        return applyingUnchecked(move).state
    }

    /// Fast internal move application assuming the move is pseudo-legal.
    internal func applyingUnchecked(
        _ move: ChessMove
    ) -> (state: ChessBoardState, movedPiece: ChessPiece, capturedPiece: ChessPiece?) {
        var next = self
        let fromIdx = move.from.index
        let toIdx = move.to.index
        let movedPiece = squares[fromIdx] ?? ChessPiece(color: sideToMove, kind: .pawn)
        var capturedPiece = squares[toIdx]

        next.squares[fromIdx] = nil

        // En passant capture removes the opponent pawn on the origin rank.
        let isEnPassant = movedPiece.kind == .pawn && enPassantTarget == move.to && capturedPiece == nil
        if isEnPassant {
            let capturedIdx = (move.from.rank << 3) | move.to.file
            capturedPiece = next.squares[capturedIdx]
            next.squares[capturedIdx] = nil
        }

        // Promotion or normal placement.
        if let promo = move.promotion, movedPiece.kind == .pawn {
            next.squares[toIdx] = ChessPiece(color: movedPiece.color, kind: promo)
        } else {
            next.squares[toIdx] = movedPiece
        }

        // Castling moves the corresponding rook.
        if movedPiece.kind == .king && abs(move.to.file - move.from.file) == 2 {
            let rank = move.from.rank
            if move.to.file == 6 {
                // Kingside: h-file rook to f-file
                next.squares[(rank << 3) | 5] = next.squares[(rank << 3) | 7]
                next.squares[(rank << 3) | 7] = nil
            } else if move.to.file == 2 {
                // Queenside: a-file rook to d-file
                next.squares[(rank << 3) | 3] = next.squares[(rank << 3) | 0]
                next.squares[(rank << 3) | 0] = nil
            }
        }

        // Update castling rights whenever kings or corner rook squares are touched.
        if movedPiece.kind == .king {
            if movedPiece.color == .white {
                next.castlingRights.whiteKingside = false
                next.castlingRights.whiteQueenside = false
            } else {
                next.castlingRights.blackKingside = false
                next.castlingRights.blackQueenside = false
            }
        }
        if fromIdx == 0 || toIdx == 0 { next.castlingRights.whiteQueenside = false }
        if fromIdx == 7 || toIdx == 7 { next.castlingRights.whiteKingside = false }
        if fromIdx == 56 || toIdx == 56 { next.castlingRights.blackQueenside = false }
        if fromIdx == 63 || toIdx == 63 { next.castlingRights.blackKingside = false }

        // En passant target square on double pawn push.
        if movedPiece.kind == .pawn && abs(move.to.rank - move.from.rank) == 2 {
            let epRank = (move.from.rank + move.to.rank) >> 1
            next.enPassantTarget = ChessSquare(uncheckedFile: move.from.file, uncheckedRank: epRank)
        } else {
            next.enPassantTarget = nil
        }

        // Clocks and side to move.
        if movedPiece.kind == .pawn || capturedPiece != nil {
            next.halfmoveClock = 0
        } else {
            next.halfmoveClock += 1
        }
        if sideToMove == .black {
            next.fullmoveNumber += 1
        }
        next.sideToMove = sideToMove.opposite

        return (next, movedPiece, capturedPiece)
    }

    private func appendLegalMoves(from: ChessSquare, piece: ChessPiece, into out: inout [ChessMove]) {
        var candidates: [ChessMove] = []
        candidates.reserveCapacity(16)
        appendPseudoLegalMoves(from: from, piece: piece, into: &candidates)

        let mover = piece.color
        for move in candidates {
            let after = applyingUnchecked(move).state
            if !after.isInCheck(mover) {
                out.append(move)
            }
        }
    }

    private func appendPseudoLegalMoves(from: ChessSquare, piece: ChessPiece, into out: inout [ChessMove]) {
        let f = from.file
        let r = from.rank
        let color = piece.color
        let enemy = color.opposite

        switch piece.kind {
        case .pawn:
            let dir = color.pawnDirection
            let nextRank = r + dir
            guard (0..<8).contains(nextRank) else { return }

            // Single push
            let forwardIdx = (nextRank << 3) | f
            if squares[forwardIdx] == nil {
                let target = ChessSquare(uncheckedFile: f, uncheckedRank: nextRank)
                if nextRank == color.promotionRank {
                    for promo in ChessPieceKind.promotionKinds {
                        out.append(ChessMove(from: from, to: target, promotion: promo))
                    }
                } else {
                    out.append(ChessMove(from: from, to: target))
                    // Double push from starting rank
                    if r == color.pawnStartRank {
                        let doubleRank = r + (dir * 2)
                        let doubleIdx = (doubleRank << 3) | f
                        if squares[doubleIdx] == nil {
                            out.append(ChessMove(
                                from: from,
                                to: ChessSquare(uncheckedFile: f, uncheckedRank: doubleRank)
                            ))
                        }
                    }
                }
            }

            // Captures (normal and en passant)
            for df in [-1, 1] {
                let tf = f + df
                guard (0..<8).contains(tf) else { continue }
                let targetIdx = (nextRank << 3) | tf
                let target = ChessSquare(uncheckedFile: tf, uncheckedRank: nextRank)
                if let victim = squares[targetIdx], victim.color == enemy {
                    if nextRank == color.promotionRank {
                        for promo in ChessPieceKind.promotionKinds {
                            out.append(ChessMove(from: from, to: target, promotion: promo))
                        }
                    } else {
                        out.append(ChessMove(from: from, to: target))
                    }
                } else if enPassantTarget == target {
                    // Ensure the enemy pawn actually sits beside our pawn before adding EP candidate.
                    let besideIdx = (r << 3) | tf
                    if let beside = squares[besideIdx], beside.color == enemy && beside.kind == .pawn {
                        out.append(ChessMove(from: from, to: target))
                    }
                }
            }

        case .knight:
            for (df, dr) in Self.knightOffsets {
                let tf = f + df
                let tr = r + dr
                guard (0..<8).contains(tf), (0..<8).contains(tr) else { continue }
                let idx = (tr << 3) | tf
                if squares[idx]?.color != color {
                    out.append(ChessMove(from: from, to: ChessSquare(uncheckedFile: tf, uncheckedRank: tr)))
                }
            }

        case .bishop:
            appendSlidingMoves(from: from, color: color, directions: Self.bishopDirections, into: &out)

        case .rook:
            appendSlidingMoves(from: from, color: color, directions: Self.rookDirections, into: &out)

        case .queen:
            appendSlidingMoves(from: from, color: color, directions: Self.bishopDirections, into: &out)
            appendSlidingMoves(from: from, color: color, directions: Self.rookDirections, into: &out)

        case .king:
            for (df, dr) in Self.kingOffsets {
                let tf = f + df
                let tr = r + dr
                guard (0..<8).contains(tf), (0..<8).contains(tr) else { continue }
                let idx = (tr << 3) | tf
                if squares[idx]?.color != color {
                    out.append(ChessMove(from: from, to: ChessSquare(uncheckedFile: tf, uncheckedRank: tr)))
                }
            }

            // Castling
            let homeRank = color.backRank
            guard r == homeRank && f == 4 else { return }
            guard !isSquareAttacked(from, by: enemy) else { return }

            let canKingside = color == .white ? castlingRights.whiteKingside : castlingRights.blackKingside
            if canKingside {
                let fSq = ChessSquare(uncheckedFile: 5, uncheckedRank: homeRank)
                let gSq = ChessSquare(uncheckedFile: 6, uncheckedRank: homeRank)
                let hIdx = (homeRank << 3) | 7
                if squares[fSq.index] == nil,
                   squares[gSq.index] == nil,
                   let rook = squares[hIdx], rook.color == color && rook.kind == .rook,
                   !isSquareAttacked(fSq, by: enemy),
                   !isSquareAttacked(gSq, by: enemy) {
                    out.append(ChessMove(from: from, to: gSq))
                }
            }

            let canQueenside = color == .white ? castlingRights.whiteQueenside : castlingRights.blackQueenside
            if canQueenside {
                let bIdx = (homeRank << 3) | 1
                let cSq = ChessSquare(uncheckedFile: 2, uncheckedRank: homeRank)
                let dSq = ChessSquare(uncheckedFile: 3, uncheckedRank: homeRank)
                let aIdx = (homeRank << 3) | 0
                if squares[bIdx] == nil,
                   squares[cSq.index] == nil,
                   squares[dSq.index] == nil,
                   let rook = squares[aIdx], rook.color == color && rook.kind == .rook,
                   !isSquareAttacked(dSq, by: enemy),
                   !isSquareAttacked(cSq, by: enemy) {
                    out.append(ChessMove(from: from, to: cSq))
                }
            }
        }
    }

    private func appendSlidingMoves(
        from: ChessSquare,
        color: ChessColor,
        directions: [(Int, Int)],
        into out: inout [ChessMove]
    ) {
        for (df, dr) in directions {
            var cf = from.file + df
            var cr = from.rank + dr
            while cf >= 0 && cf < 8 && cr >= 0 && cr < 8 {
                let idx = (cr << 3) | cf
                let target = ChessSquare(uncheckedFile: cf, uncheckedRank: cr)
                if let occupant = squares[idx] {
                    if occupant.color != color {
                        out.append(ChessMove(from: from, to: target))
                    }
                    break
                }
                out.append(ChessMove(from: from, to: target))
                cf += df
                cr += dr
            }
        }
    }

    private func hasLegalEnPassantCapture(to epSquare: ChessSquare) -> Bool {
        let mover = sideToMove
        let sourceRank = epSquare.rank - mover.pawnDirection
        guard (0..<8).contains(sourceRank) else { return false }
        for df in [-1, 1] {
            let sf = epSquare.file + df
            guard (0..<8).contains(sf) else { continue }
            let idx = (sourceRank << 3) | sf
            if let p = squares[idx], p.color == mover && p.kind == .pawn {
                let move = ChessMove(from: ChessSquare(uncheckedIndex: idx), to: epSquare)
                let after = applyingUnchecked(move).state
                if !after.isInCheck(mover) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: Draw & Game Status Evaluation

    /// True if neither side has sufficient mating material (K vs K, K+B vs K, K+N vs K,
    /// or K+B vs K+B with bishops on the same square color).
    public var isInsufficientMaterial: Bool {
        var minorPieces: [(ChessPiece, ChessSquare)] = []
        for idx in 0..<64 {
            guard let piece = squares[idx], piece.kind != .king else { continue }
            switch piece.kind {
            case .pawn, .rook, .queen:
                return false
            case .bishop, .knight:
                minorPieces.append((piece, ChessSquare(uncheckedIndex: idx)))
                if minorPieces.count > 2 {
                    return false
                }
            case .king:
                break
            }
        }

        switch minorPieces.count {
        case 0, 1:
            return true
        case 2:
            let first = minorPieces[0]
            let second = minorPieces[1]
            return first.0.kind == .bishop
                && second.0.kind == .bishop
                && first.0.color != second.0.color
                && first.1.isLightSquare == second.1.isLightSquare
        default:
            return false
        }
    }

    /// Computes the game status for this position given how many times this position
    /// has occurred so far in the game (including the current occurrence).
    public func status(repetitionCount: Int = 1) -> ChessGameStatus {
        let legal = legalMoves()
        if legal.isEmpty {
            if isInCheck(sideToMove) {
                return .checkmate(winner: sideToMove.opposite)
            }
            return .stalemate
        }
        if halfmoveClock >= 100 {
            return .drawFiftyMove
        }
        if repetitionCount >= 3 {
            return .drawThreefoldRepetition
        }
        if isInsufficientMaterial {
            return .drawInsufficientMaterial
        }
        if isInCheck(sideToMove) {
            return .check(sideToMove)
        }
        return .active
    }

    // MARK: SAN Formatting & Move Matching

    /// Formats a legal move in Standard Algebraic Notation (e.g. `Nf3`, `Nbd2`, `exd5+`, `O-O`, `e8=Q#`).
    public func san(for move: ChessMove) -> String? {
        let allLegal = legalMoves()
        guard allLegal.contains(move), let piece = squares[move.from.index] else {
            return nil
        }
        return formatSAN(move: move, piece: piece, allLegalMoves: allLegal)
    }

    internal func formatSAN(move: ChessMove, piece: ChessPiece, allLegalMoves: [ChessMove]) -> String {
        var text = ""
        let isCapture = squares[move.to.index] != nil
            || (piece.kind == .pawn && enPassantTarget == move.to)

        if piece.kind == .king && abs(move.to.file - move.from.file) == 2 {
            text = move.to.file > move.from.file ? "O-O" : "O-O-O"
        } else if piece.kind == .pawn {
            if isCapture {
                text = "\(move.from.fileChar)x\(move.to.algebraic)"
            } else {
                text = move.to.algebraic
            }
            if let promo = move.promotion {
                text += "=\(promo.symbol)"
            }
        } else {
            text = piece.kind.symbol
            let ambiguous = allLegalMoves.filter { other in
                other.from != move.from
                    && other.to == move.to
                    && squares[other.from.index]?.kind == piece.kind
            }
            if !ambiguous.isEmpty {
                let sameFile = ambiguous.contains { $0.from.file == move.from.file }
                let sameRank = ambiguous.contains { $0.from.rank == move.from.rank }
                if !sameFile {
                    text.append(move.from.fileChar)
                } else if !sameRank {
                    text.append(move.from.rankChar)
                } else {
                    text.append(move.from.algebraic)
                }
            }
            if isCapture {
                text.append("x")
            }
            text.append(move.to.algebraic)
        }

        let after = applyingUnchecked(move).state
        if after.isInCheck(after.sideToMove) {
            text.append(after.legalMoves().isEmpty ? "#" : "+")
        }
        return text
    }

    /// Matches a move given in either UCI (`"e2e4"`, `"e7e8q"`) or SAN (`"Nf3"`, `"O-O"`, `"exd5+"`, `"e8=Q#"`).
    public func move(matching input: String) -> ChessMove? {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?'\"`()[]{}"))
        guard !trimmed.isEmpty else { return nil }

        let allLegal = legalMoves()
        guard !allLegal.isEmpty else { return nil }

        // 1. Direct UCI match (also supports "e2-e4" style hyphenated coordinates)
        let compactUCI = trimmed.replacingOccurrences(of: "-", with: "").lowercased()
        if let uciMove = ChessMove(uci: compactUCI), allLegal.contains(uciMove) {
            return uciMove
        }

        // Normalize castling zeroes to capital O
        let castlingNormalized = trimmed
            .replacingOccurrences(of: "0-0-0", with: "O-O-O")
            .replacingOccurrences(of: "0-0", with: "O-O")

        // Build SAN table once for exact and normalized matching
        var sanPairs: [(move: ChessMove, san: String)] = []
        sanPairs.reserveCapacity(allLegal.count)
        for move in allLegal {
            if let piece = squares[move.from.index] {
                sanPairs.append((move, formatSAN(move: move, piece: piece, allLegalMoves: allLegal)))
            }
        }

        // 2. Exact SAN match
        if let exact = sanPairs.first(where: { $0.san == castlingNormalized }) {
            return exact.move
        }

        // 3. Stripped SAN match (ignoring +, #, !, ?, and optional =)
        func stripAnnotations(_ s: String) -> String {
            s.filter { !"+#!?".contains($0) }
        }
        let strippedInput = stripAnnotations(castlingNormalized)
        if let strippedExact = sanPairs.first(where: { stripAnnotations($0.san) == strippedInput }) {
            return strippedExact.move
        }

        // 4. Relaxed SAN match (ignoring x and = as well, case-sensitive first)
        func relaxSAN(_ s: String) -> String {
            s.filter { !"+#!?x=".contains($0) }
        }
        let relaxedInput = relaxSAN(castlingNormalized)
        let relaxedMatches = sanPairs.filter { relaxSAN($0.san) == relaxedInput }
        if relaxedMatches.count == 1 {
            return relaxedMatches[0].move
        }

        // 5. Case-insensitive fallback if unambiguous (e.g. "nf3" or "o-o")
        let lowerInput = strippedInput.lowercased()
        let lowerMatches = sanPairs.filter { stripAnnotations($0.san).lowercased() == lowerInput }
        if lowerMatches.count == 1 {
            return lowerMatches[0].move
        }

        return nil
    }

    // MARK: Perft

    /// Counts leaf nodes at the given ply depth from this position (useful for rule verification).
    public func perft(depth: Int) -> UInt64 {
        guard depth > 0 else { return 1 }
        let moves = legalMoves()
        if depth == 1 {
            return UInt64(moves.count)
        }
        var nodes: UInt64 = 0
        for move in moves {
            let next = applyingUnchecked(move).state
            nodes += next.perft(depth: depth - 1)
        }
        return nodes
    }

    // MARK: Direction Tables

    private static let knightOffsets: [(Int, Int)] = [
        (-2, -1), (-2, 1), (-1, -2), (-1, 2),
        (1, -2), (1, 2), (2, -1), (2, 1),
    ]

    private static let kingOffsets: [(Int, Int)] = [
        (-1, -1), (-1, 0), (-1, 1),
        (0, -1),           (0, 1),
        (1, -1),  (1, 0),  (1, 1),
    ]

    private static let bishopDirections: [(Int, Int)] = [
        (-1, -1), (-1, 1), (1, -1), (1, 1),
    ]

    private static let rookDirections: [(Int, Int)] = [
        (-1, 0), (1, 0), (0, -1), (0, 1),
    ]
}

// MARK: - ChessGame

/// Stateful chess game value type managing board state, history, undo stack, draws, and captures.
public struct ChessGame: Sendable, Equatable, Codable {
    /// Current board state.
    public private(set) var state: ChessBoardState
    /// Initial FEN used when this game started.
    public private(set) var initialFEN: String
    /// Chronological list of played half-moves.
    public private(set) var history: [ChessMoveRecord]
    /// Stack of prior board states for undo support.
    public private(set) var undoStack: [ChessBoardState]
    /// Current lifecycle status (active, check, checkmate, stalemate, draw, or resigned).
    public private(set) var status: ChessGameStatus

    /// Position keys recorded from initial state through current state (parallel to `undoStack + [state]`).
    private var positionHistory: [String]

    /// Creates a new chess game from the standard starting position or a custom FEN.
    /// If `fen` is invalid, falls back to `.standardInitial`.
    public init(fen: String? = nil) {
        let initial = fen.flatMap(ChessBoardState.init(fen:)) ?? .standardInitial
        self.state = initial
        self.initialFEN = initial.fen
        self.history = []
        self.undoStack = []
        self.positionHistory = [initial.positionKey]
        self.status = initial.status(repetitionCount: 1)
    }

    /// Creates a new chess game from a validated FEN string, returning `nil` if the FEN is invalid.
    public init?(validatingFEN fen: String) {
        guard let initial = ChessBoardState(fen: fen) else { return nil }
        self.state = initial
        self.initialFEN = initial.fen
        self.history = []
        self.undoStack = []
        self.positionHistory = [initial.positionKey]
        self.status = initial.status(repetitionCount: 1)
    }

    /// Side currently to move.
    public var sideToMove: ChessColor {
        state.sideToMove
    }

    /// True if the game has ended.
    public var isGameOver: Bool {
        status.isGameOver
    }

    /// True if at least one ply can be undone.
    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    /// Most recently played move, if any.
    public var lastMove: ChessMove? {
        history.last?.move
    }

    /// Black pieces captured by White, ordered from highest to lowest value.
    public var capturedByWhite: [ChessPiece] {
        history.compactMap { record in
            guard record.piece.color == .white, let captured = record.captured else { return nil }
            return captured
        }.sorted { $0.materialValue > $1.materialValue }
    }

    /// White pieces captured by Black, ordered from highest to lowest value.
    public var capturedByBlack: [ChessPiece] {
        history.compactMap { record in
            guard record.piece.color == .black, let captured = record.captured else { return nil }
            return captured
        }.sorted { $0.materialValue > $1.materialValue }
    }

    /// Current material balance on the board in pawn units (positive favors White).
    public var materialBalance: Int {
        state.materialBalance
    }

    /// All legal moves in the current position (empty if the game is already over).
    public func legalMoves() -> [ChessMove] {
        isGameOver ? [] : state.legalMoves()
    }

    /// All legal moves originating from `square` (empty if the game is already over).
    public func legalMoves(from square: ChessSquare) -> [ChessMove] {
        isGameOver ? [] : state.legalMoves(from: square)
    }

    /// Pairs of moves grouped by full-move number for display ribbons.
    public var movePairs: [(number: Int, white: ChessMoveRecord?, black: ChessMoveRecord?)] {
        var pairs: [(number: Int, white: ChessMoveRecord?, black: ChessMoveRecord?)] = []
        var idx = 0
        var moveNum = 1
        while idx < history.count {
            let first = history[idx]
            if first.piece.color == .white {
                let second: ChessMoveRecord? = (idx + 1 < history.count && history[idx + 1].piece.color == .black)
                    ? history[idx + 1]
                    : nil
                pairs.append((moveNum, first, second))
                idx += second == nil ? 1 : 2
            } else {
                pairs.append((moveNum, nil, first))
                idx += 1
            }
            moveNum += 1
        }
        return pairs
    }

    /// Executes a legal move, updates history/status, and returns the created record.
    @discardableResult
    public mutating func makeMove(_ move: ChessMove, commentary: String? = nil) -> ChessMoveRecord? {
        guard !isGameOver else { return nil }
        let allLegal = state.legalMoves()
        guard allLegal.contains(move), let piece = state.piece(at: move.from) else {
            return nil
        }

        let sanText = state.formatSAN(move: move, piece: piece, allLegalMoves: allLegal)
        let applied = state.applyingUnchecked(move)

        undoStack.append(state)
        state = applied.state

        let key = state.positionKey
        positionHistory.append(key)
        let repCount = positionHistory.reduce(0) { $0 + ($1 == key ? 1 : 0) }

        let record = ChessMoveRecord(
            ply: history.count + 1,
            move: move,
            san: sanText,
            piece: applied.movedPiece,
            captured: applied.capturedPiece,
            fenAfter: state.fen,
            commentary: commentary
        )
        history.append(record)
        status = state.status(repetitionCount: repCount)
        return record
    }

    /// Matches and executes a move given in UCI or SAN notation.
    @discardableResult
    public mutating func makeMove(matching input: String, commentary: String? = nil) -> ChessMoveRecord? {
        guard !isGameOver, let move = state.move(matching: input) else { return nil }
        return makeMove(move, commentary: commentary)
    }

    /// Undoes the last half-move and restores previous board state, clocks, and status.
    @discardableResult
    public mutating func undoLastPly() -> ChessMoveRecord? {
        guard let previousState = undoStack.popLast(),
              let removedRecord = history.popLast() else {
            return nil
        }
        if positionHistory.count > 1 {
            positionHistory.removeLast()
        }
        state = previousState
        let key = state.positionKey
        let repCount = positionHistory.reduce(0) { $0 + ($1 == key ? 1 : 0) }
        status = state.status(repetitionCount: repCount)
        return removedRecord
    }

    /// Records resignation by `color`, awarding victory to `color.opposite`.
    public mutating func resign(color: ChessColor) {
        guard !isGameOver else { return }
        status = .resigned(winner: color.opposite)
    }

    /// Ends the game in a draw by mutual agreement.
    public mutating func agreeDraw() {
        guard !isGameOver else { return }
        status = .drawAgreement
    }

    /// Resets the game to the standard starting position or an optional FEN.
    public mutating func reset(fen: String? = nil) {
        self = ChessGame(fen: fen)
    }
}
