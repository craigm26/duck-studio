import Foundation
import Combine
import StudioKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - ChessPlayMode

/// Opponent and table configuration for Sim Chess.
enum ChessPlayMode: String, CaseIterable, Identifiable, Sendable {
    case vsEngine
    case vsLocalAI
    case vsCloudAI
    case twoPlayerSameBoard

    var id: String { rawValue }

    /// Short title suitable for segmented pickers and pills.
    var title: String {
        switch self {
        case .vsEngine: return "Engine"
        case .vsLocalAI: return "Local AI"
        case .vsCloudAI: return "Cloud AI"
        case .twoPlayerSameBoard: return "2-Player"
        }
    }

    /// Descriptive title for setup sheets and mode cards.
    var fullTitle: String {
        switch self {
        case .vsEngine: return "Built-in Chess Engine"
        case .vsLocalAI: return "Local On-Device AI"
        case .vsCloudAI: return "Cloud / Remote AI"
        case .twoPlayerSameBoard: return "2-Player Pass & Play"
        }
    }

    /// Concise explanation of how this mode plays.
    var subtitle: String {
        switch self {
        case .vsEngine:
            return "Instant offline alpha-beta engine with selectable strength."
        case .vsLocalAI:
            return "Plays with your downloaded MLX model or Apple Intelligence on device."
        case .vsCloudAI:
            return "Plays through your configured remote endpoint or hosted API key."
        case .twoPlayerSameBoard:
            return "Two human players share one board with auto-flip or tabletop view."
        }
    }

    /// SF Symbol representing this play mode.
    var symbol: String {
        switch self {
        case .vsEngine: return "cpu"
        case .vsLocalAI: return "iphone.gen3"
        case .vsCloudAI: return "cloud"
        case .twoPlayerSameBoard: return "person.2.fill"
        }
    }

    var isTwoPlayer: Bool {
        self == .twoPlayerSameBoard
    }

    var usesAI: Bool {
        !isTwoPlayer
    }
}

// MARK: - ChessTimeControl

/// Optional chess clock presets for Sim Chess.
enum ChessTimeControl: String, CaseIterable, Identifiable, Sendable {
    case untimed
    case blitz3Plus2
    case blitz5Plus0
    case rapid10Plus0

    var id: String { rawValue }

    var title: String {
        switch self {
        case .untimed: return "Untimed"
        case .blitz3Plus2: return "3+2"
        case .blitz5Plus0: return "5+0"
        case .rapid10Plus0: return "10+0"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .untimed: return "Untimed"
        case .blitz3Plus2: return "3 minutes plus 2 seconds increment"
        case .blitz5Plus0: return "5 minutes"
        case .rapid10Plus0: return "10 minutes"
        }
    }

    /// Starting time in seconds per player, or `nil` when untimed.
    var initialSeconds: TimeInterval? {
        switch self {
        case .untimed: return nil
        case .blitz3Plus2: return 180
        case .blitz5Plus0: return 300
        case .rapid10Plus0: return 600
        }
    }

    /// Fischer increment added after each completed move.
    var incrementSeconds: TimeInterval {
        switch self {
        case .blitz3Plus2: return 2
        case .untimed, .blitz5Plus0, .rapid10Plus0: return 0
        }
    }
}

// MARK: - MicroDuckChessMood

/// Live emotional and animation state for the Sim MicroDuck companion beside the chessboard.
enum MicroDuckChessMood: String, Equatable, Sendable {
    case idle
    case thinking
    case happyCapture
    case checkAlert
    case checkmateWin
    case checkmateLoss
    case drawBow

    var badgeLabel: String {
        switch self {
        case .idle: return "Ready"
        case .thinking: return "Thinking"
        case .happyCapture: return "Capture"
        case .checkAlert: return "Check!"
        case .checkmateWin: return "Victory"
        case .checkmateLoss: return "Well played"
        case .drawBow: return "Draw"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "sparkles"
        case .thinking: return "ellipsis.bubble"
        case .happyCapture: return "star.fill"
        case .checkAlert: return "exclamationmark.triangle.fill"
        case .checkmateWin: return "crown.fill"
        case .checkmateLoss: return "hands.clap.fill"
        case .drawBow: return "handshake.fill"
        }
    }
}

// MARK: - ChessGameSession

/// Production `@MainActor` session controller for Sim Chess in DuckStudio.
///
/// Supports four modes:
/// 1. Built-in offline alpha-beta engine (`ChessSearchAI`)
/// 2. Local on-device AI (downloaded MLX via `PhoneModelRuntime` + `PhoneModelFiles`, or Apple Intelligence)
/// 3. Cloud / Remote AI (configured `EndpointStore` OpenAI-compatible server, or Anthropic / OpenAI BYOK keys)
/// 4. 2-Player Pass & Play on the same board (with `autoFlipBoard`, `tabletopFaceToFace`, and optional clocks)
@MainActor
final class ChessGameSession: ObservableObject {

    // MARK: Published Game State

    @Published private(set) var game: ChessGame = ChessGame()
    @Published var playMode: ChessPlayMode = .vsEngine
    @Published var difficulty: ChessAIDifficulty = .club
    @Published var humanColor: ChessColor = .white
    @Published var timeControl: ChessTimeControl = .untimed

    /// In 2-player mode, rotates the board 180 degrees automatically after each turn.
    @Published var autoFlipBoard: Bool = false {
        didSet {
            if autoFlipBoard {
                if tabletopFaceToFace { tabletopFaceToFace = false }
                if playMode == .twoPlayerSameBoard {
                    isBoardFlipped = (game.sideToMove == .black)
                }
            }
            refreshAIStatusSummary()
        }
    }

    /// In 2-player mode, keeps the board fixed while rotating the opposite side's pieces 180 degrees
    /// so two people sitting across a table can play naturally on the same screen.
    @Published var tabletopFaceToFace: Bool = false {
        didSet {
            if tabletopFaceToFace && autoFlipBoard {
                autoFlipBoard = false
            }
            refreshAIStatusSummary()
        }
    }

    /// Current board orientation (`false` = White at bottom, `true` = Black at bottom).
    @Published var isBoardFlipped: Bool = false

    /// Customizable player names for 2-player Pass & Play mode.
    @Published var whitePlayerName: String = "Player 1"
    @Published var blackPlayerName: String = "Player 2"

    // MARK: Selection, Promotion & Hints

    @Published private(set) var selectedSquare: ChessSquare? = nil
    @Published private(set) var legalDestinations: Set<ChessSquare> = []
    @Published private(set) var pendingPromotion: (from: ChessSquare, to: ChessSquare)? = nil
    @Published private(set) var hintMove: ChessMove? = nil
    @Published private(set) var isComputingHint: Bool = false

    // MARK: Clocks & Timeout

    @Published private(set) var whiteClockSeconds: TimeInterval = 0
    @Published private(set) var blackClockSeconds: TimeInterval = 0
    @Published private(set) var timeoutWinner: ChessColor? = nil

    // MARK: AI Bridge Status

    @Published private(set) var isAIThinking: Bool = false
    @Published private(set) var aiStatusLine: String = "Built-in Engine (Club)"
    @Published private(set) var aiProviderBadge: String = "Engine: Club"
    @Published private(set) var lastAILatencySeconds: Double? = nil
    @Published private(set) var aiUsedFallback: Bool = false

    // MARK: Sim MicroDuck Companion State

    @Published private(set) var duckMood: MicroDuckChessMood = .idle
    @Published private(set) var duckLine: String = "Quack! Tap any piece to start our chess match."
    /// Suggested head yaw angle in degrees (`-30...30`) for animating the Sim MicroDuck companion.
    @Published private(set) var duckHeadYaw: Double = 0
    /// Suggested bounce intensity (`0...1`) for animating the Sim MicroDuck companion.
    @Published private(set) var duckBounce: Double = 0

    // MARK: Private Runtime Wiring

    private var endpointStore: EndpointStore
    private let ownsEndpointStore: Bool
    private var aiTask: Task<Void, Never>? = nil
    private var hintTask: Task<Void, Never>? = nil
    private var clockTask: Task<Void, Never>? = nil
    private var lastClockTickDate: Date? = nil
    private var stateGeneration: UInt64 = 0

    // MARK: Initialization

    /// Initializes a chess session. Pass the shared `EndpointStore` when available, or omit it
    /// to load saved endpoints directly from `UserDefaults` and Keychain.
    init(
        models: EndpointStore? = nil,
        playMode: ChessPlayMode = .vsEngine,
        difficulty: ChessAIDifficulty = .club,
        humanColor: ChessColor = .white,
        timeControl: ChessTimeControl = .untimed
    ) {
        if let models {
            self.endpointStore = models
            self.ownsEndpointStore = false
        } else {
            self.endpointStore = EndpointStore()
            self.ownsEndpointStore = true
        }
        self.playMode = playMode
        self.difficulty = difficulty
        self.humanColor = humanColor
        self.timeControl = timeControl
        self.isBoardFlipped = playMode.usesAI && humanColor == .black
        resetClocksForCurrentControl()
        refreshAIStatusSummary()
        setInitialDuckGreeting()
        if playMode.usesAI && humanColor == .black {
            scheduleAIMoveIfNeeded()
        }
    }

    // MARK: Derived Properties for Views

    var isGameOver: Bool {
        game.isGameOver || timeoutWinner != nil
    }

    var winner: ChessColor? {
        timeoutWinner ?? game.status.winner
    }

    var isDraw: Bool {
        timeoutWinner == nil && game.status.isDraw
    }

    var sideToMove: ChessColor {
        game.sideToMove
    }

    var lastMove: ChessMove? {
        game.lastMove
    }

    var isHumanTurn: Bool {
        guard !isGameOver else { return false }
        if playMode == .twoPlayerSameBoard {
            return true
        }
        return game.sideToMove == humanColor
    }

    var canUndo: Bool {
        guard game.canUndo else { return false }
        if playMode == .twoPlayerSameBoard {
            return true
        }
        // In AI modes, allow undo if AI is moving/thinking (1 ply back) or human has played at least once (2 plies back).
        if game.sideToMove != humanColor || isAIThinking || isGameOver {
            return true
        }
        return game.undoStack.count >= 2
    }

    var canRequestHint: Bool {
        !isGameOver && !isAIThinking && !isComputingHint && isHumanTurn && pendingPromotion == nil
    }

    var pendingPromotionColor: ChessColor? {
        pendingPromotion == nil ? nil : game.sideToMove
    }

    /// Square of a king currently in check (including checkmate), for highlighting a crimson halo.
    var checkKingSquare: ChessSquare? {
        if case .check(let color) = game.status {
            return game.state.kingSquare(for: color)
        }
        if case .checkmate(let winner) = game.status {
            return game.state.kingSquare(for: winner.opposite)
        }
        return nil
    }

    /// Clear turn or game-over banner string.
    var turnBannerText: String {
        if isGameOver {
            return statusSummary
        }
        if isAIThinking {
            return "\(aiOpponentShortName) is thinking..."
        }
        if case .check(let checked) = game.status {
            return "\(checked.label) to move (Check)"
        }
        if playMode == .twoPlayerSameBoard {
            let player = playerLabel(for: game.sideToMove)
            return "\(game.sideToMove.label) to move (\(player))"
        }
        return "\(game.sideToMove.label) to move"
    }

    /// Concise status text including timeout outcomes.
    var statusSummary: String {
        if let winner = timeoutWinner {
            return "Time out, \(winner.label) wins"
        }
        return game.status.summaryText
    }

    /// Primary headline for the game-over banner or sheet.
    var gameOverHeadline: String {
        if let winner = timeoutWinner {
            return "\(winner.label) wins on time"
        }
        switch game.status {
        case .checkmate(let winner):
            if playMode.usesAI {
                return winner == humanColor ? "Checkmate! You win" : "Checkmate! \(aiOpponentShortName) wins"
            }
            return "Checkmate! \(winner.label) wins"
        case .resigned(let winner):
            if playMode.usesAI {
                return winner == humanColor ? "You win by resignation" : "\(aiOpponentShortName) wins by resignation"
            }
            return "\(winner.label) wins by resignation"
        case .stalemate:
            return "Draw by stalemate"
        case .drawFiftyMove:
            return "Draw by 50-move rule"
        case .drawThreefoldRepetition:
            return "Draw by repetition"
        case .drawInsufficientMaterial:
            return "Draw by insufficient material"
        case .drawAgreement:
            return "Draw agreed"
        case .active, .check:
            return "Game in progress"
        }
    }

    /// Secondary detail line for the game-over banner or sheet.
    var gameOverDetail: String {
        let plyCount = game.history.count
        let moveLabel = plyCount == 1 ? "1 ply played" : "\(plyCount) plies played"
        return "\(statusSummary). \(moveLabel)."
    }

    /// Color rendered at the top of the board.
    var topColor: ChessColor {
        isBoardFlipped ? .white : .black
    }

    /// Color rendered at the bottom of the board.
    var bottomColor: ChessColor {
        isBoardFlipped ? .black : .white
    }

    var topPlayerLabel: String {
        playerLabel(for: topColor)
    }

    var bottomPlayerLabel: String {
        playerLabel(for: bottomColor)
    }

    /// Material advantage for `color` in pawn units (positive only when ahead, else 0).
    func materialAdvantage(for color: ChessColor) -> Int {
        let balance = game.materialBalance
        switch color {
        case .white: return max(0, balance)
        case .black: return max(0, -balance)
        }
    }

    /// Captured opponent pieces collected by `color`.
    func capturedPieces(by color: ChessColor) -> [ChessPiece] {
        color == .white ? game.capturedByWhite : game.capturedByBlack
    }

    /// Display label for the given color's player strip.
    func playerLabel(for color: ChessColor) -> String {
        if playMode == .twoPlayerSameBoard {
            let trimmed = (color == .white ? whitePlayerName : blackPlayerName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
            return color == .white ? "Player 1" : "Player 2"
        }
        if color == humanColor {
            return "You"
        }
        return aiOpponentShortName
    }

    /// Short name for the active AI opponent.
    var aiOpponentShortName: String {
        switch playMode {
        case .vsEngine:
            return "MicroDuck (\(difficulty.label))"
        case .vsLocalAI:
            if let local = resolveReadyLocalModel() {
                return "Local AI (\(local.label))"
            }
            if isAppleIntelligenceAvailable() {
                return "Apple AI"
            }
            return "Local AI"
        case .vsCloudAI:
            if let cloud = resolveCloudTarget() {
                return cloud.shortLabel
            }
            return "Cloud AI"
        case .twoPlayerSameBoard:
            return "Player 2"
        }
    }

    /// Returns whether a piece on the board should be rotated 180 degrees for Tabletop Face-to-Face play.
    func shouldRotatePiece180(for pieceColor: ChessColor) -> Bool {
        guard playMode == .twoPlayerSameBoard && tabletopFaceToFace else { return false }
        return pieceColor == topColor
    }

    /// Returns the piece at `square`, if any.
    func piece(at square: ChessSquare) -> ChessPiece? {
        game.state.piece(at: square)
    }

    /// True if `square` is a legal capture destination (including en passant) for the currently selected piece.
    func isCaptureDestination(_ square: ChessSquare) -> Bool {
        guard legalDestinations.contains(square) else { return false }
        if game.state.piece(at: square) != nil {
            return true
        }
        if let selected = selectedSquare,
           let piece = game.state.piece(at: selected),
           piece.kind == .pawn,
           game.state.enPassantTarget == square {
            return true
        }
        return false
    }

    /// Clock remaining in seconds for `color`.
    func clockSeconds(for color: ChessColor) -> TimeInterval {
        color == .white ? whiteClockSeconds : blackClockSeconds
    }

    /// True when `color`'s clock is currently ticking down.
    func isClockRunning(for color: ChessColor) -> Bool {
        guard timeControl != .untimed, !isGameOver else { return false }
        guard !game.history.isEmpty || isAIThinking else { return false }
        return game.sideToMove == color
    }

    /// Formatted clock readout for `color` (e.g. `"5:00"`, `"0:08.4"`, or `"Untimed"`).
    func formattedClock(for color: ChessColor) -> String {
        guard timeControl != .untimed else { return "Untimed" }
        let remaining = max(0, clockSeconds(for: color))
        if remaining < 10 {
            let seconds = Int(remaining)
            let tenths = Int((remaining - Double(seconds)) * 10)
            return String(format: "0:%02d.%d", seconds, tenths)
        }
        let total = Int(remaining.rounded(.up))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Human-readable readiness description for Local On-Device AI (for mode pickers and setup sheets).
    var localAIReadinessDescription: String {
        if let local = resolveReadyLocalModel() {
            if !PhoneModelRuntime.shared.isSupported {
                return "MLX model downloaded (\(local.label)); Simulator uses Engine fallback."
            }
            return "Ready: Local MLX (\(local.label))"
        }
        if isAppleIntelligenceAvailable() {
            return "Ready: Apple Intelligence on device"
        }
        return "No local model downloaded yet. Uses Built-in Engine fallback until you download one in Models."
    }

    /// Human-readable readiness description for Cloud / Remote AI (for mode pickers and setup sheets).
    var cloudAIReadinessDescription: String {
        if let target = resolveCloudTarget() {
            return "Ready: \(target.detailLabel)"
        }
        return "No cloud endpoint or API key configured in Models. Uses Built-in Engine fallback."
    }

    // MARK: Configuration & Lifecycle Actions

    /// Reloads endpoint configuration from `UserDefaults` / Keychain if this session owns its store.
    func refreshAIConfiguration() {
        if ownsEndpointStore {
            endpointStore = EndpointStore()
        }
        refreshAIStatusSummary()
    }

    /// Starts a fresh game with optional updated mode, difficulty, human color, and time control.
    func startNewGame(
        mode: ChessPlayMode? = nil,
        difficulty: ChessAIDifficulty? = nil,
        humanColor: ChessColor? = nil,
        timeControl: ChessTimeControl? = nil,
        fen: String? = nil
    ) {
        cancelInFlightTasks()
        stateGeneration &+= 1

        if ownsEndpointStore {
            endpointStore = EndpointStore()
        }
        if let mode { self.playMode = mode }
        if let difficulty { self.difficulty = difficulty }
        if let humanColor { self.humanColor = humanColor }
        if let timeControl { self.timeControl = timeControl }

        game.reset(fen: fen)
        selectedSquare = nil
        legalDestinations = []
        pendingPromotion = nil
        hintMove = nil
        timeoutWinner = nil
        lastAILatencySeconds = nil
        aiUsedFallback = false

        resetClocksForCurrentControl()

        if self.playMode == .twoPlayerSameBoard {
            if autoFlipBoard {
                isBoardFlipped = (game.sideToMove == .black)
            } else {
                isBoardFlipped = false
            }
        } else {
            isBoardFlipped = (self.humanColor == .black)
        }

        refreshAIStatusSummary()
        setInitialDuckGreeting()

        if self.playMode.usesAI && game.sideToMove != self.humanColor && !isGameOver {
            scheduleAIMoveIfNeeded()
        }
    }

    /// Convenience rematch keeping current mode, difficulty, human side, and time control.
    func rematch() {
        startNewGame()
    }

    /// Switches play mode immediately and resets the board cleanly.
    func selectPlayMode(_ mode: ChessPlayMode) {
        startNewGame(mode: mode)
    }

    /// Updates built-in engine difficulty (takes effect on the next AI turn without resetting the board).
    func setDifficulty(_ newDifficulty: ChessAIDifficulty) {
        difficulty = newDifficulty
        refreshAIStatusSummary()
    }

    /// Switches human color in AI modes and starts a fresh game from that side.
    func setHumanColor(_ color: ChessColor) {
        startNewGame(humanColor: color)
    }

    /// Manually flips the board 180 degrees.
    func flipBoard() {
        isBoardFlipped.toggle()
    }

    /// Stops active AI, hint, and clock background tasks (call from `.onDisappear`).
    func stopAllTasks() {
        cancelInFlightTasks()
        stopClockLoop()
    }

    /// Resumes the chess clock if a timed game is active (call from `.onAppear`).
    func resumeClockIfNeeded() {
        if ownsEndpointStore {
            endpointStore = EndpointStore()
        }
        refreshAIStatusSummary()
        if timeControl != .untimed && !isGameOver && (!game.history.isEmpty || isAIThinking) {
            ensureClockLoopRunning()
        }
    }

    // MARK: Tap-to-Select & Tap-to-Move Interaction

    /// Handles a tap on any board square.
    func tapSquare(_ square: ChessSquare) {
        guard !isGameOver, !isAIThinking, isHumanTurn else { return }
        guard pendingPromotion == nil else { return }

        // Tapping the already selected square deselects it.
        if selectedSquare == square {
            clearSelection()
            return
        }

        // If a piece is selected and this square is a legal destination, move or prompt promotion.
        if let origin = selectedSquare, legalDestinations.contains(square) {
            if game.state.isPromotionMove(from: origin, to: square) {
                pendingPromotion = (from: origin, to: square)
                duckMood = .idle
                duckLine = "Pawn promoted! Pick a Queen, Rook, Bishop, or Knight."
                duckBounce = 0.45
                return
            }
            let move = ChessMove(from: origin, to: square)
            commitHumanMove(move)
            return
        }

        // Otherwise, select a friendly piece if one occupies `square`.
        if let piece = game.state.piece(at: square), piece.color == game.sideToMove {
            let movesFromSquare = game.legalMoves(from: square)
            selectedSquare = square
            legalDestinations = Set(movesFromSquare.map(\.to))
            hintMove = nil
            return
        }

        clearSelection()
    }

    /// Completes a pending pawn promotion with the chosen piece kind (Queen, Rook, Bishop, or Knight).
    func completePromotion(_ pieceKind: ChessPieceKind) {
        guard let pending = pendingPromotion else { return }
        guard ChessPieceKind.promotionKinds.contains(pieceKind) else { return }
        pendingPromotion = nil
        let move = ChessMove(from: pending.from, to: pending.to, promotion: pieceKind)
        commitHumanMove(move)
    }

    /// Cancels a pending pawn promotion overlay without making a move.
    func cancelPromotion() {
        pendingPromotion = nil
        clearSelection()
    }

    // MARK: Hint, Undo, Resign, Draw

    /// Computes a suggested move for the active human player using `ChessSearchAI`.
    func requestHint() {
        guard canRequestHint else { return }
        hintTask?.cancel()
        isComputingHint = true
        hintMove = nil
        duckMood = .thinking
        duckHeadYaw = 10
        duckLine = "Let me scan the board for a sharp move..."

        let snapshotState = game.state
        let capturedGen = stateGeneration
        let hintDifficulty: ChessAIDifficulty = .strong

        hintTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                ChessSearchAI.bestMove(for: snapshotState, difficulty: hintDifficulty)
            }.value

            guard let self, !Task.isCancelled, self.stateGeneration == capturedGen else { return }
            self.isComputingHint = false

            guard let result, !self.isGameOver, self.isHumanTurn else { return }
            self.hintMove = result.move
            self.selectedSquare = result.move.from
            self.legalDestinations = Set(self.game.legalMoves(from: result.move.from).map(\.to))
            self.duckMood = .idle
            self.duckHeadYaw = Double(result.move.to.file) * 6.0 - 21.0
            self.duckBounce = 0.4
            self.duckLine = "Hint: try \(result.san) (\(result.move.from.algebraic) to \(result.move.to.algebraic))."
        }
    }

    /// Undoes 1 ply in 2-player mode, or undoes back to the human's turn in vs-AI modes.
    func undo() {
        guard canUndo else { return }
        cancelInFlightTasks()
        stateGeneration &+= 1
        clearSelection()
        pendingPromotion = nil
        hintMove = nil
        timeoutWinner = nil

        if playMode == .twoPlayerSameBoard {
            _ = game.undoLastPly()
            if autoFlipBoard {
                isBoardFlipped = (game.sideToMove == .black)
            }
        } else {
            // Undo back to the human's turn.
            if game.sideToMove != humanColor {
                _ = game.undoLastPly()
            } else if game.undoStack.count >= 2 {
                _ = game.undoLastPly()
                _ = game.undoLastPly()
            }
        }

        if game.history.isEmpty {
            stopClockLoop()
            resetClocksForCurrentControl()
            setInitialDuckGreeting()
        } else {
            if timeControl != .untimed && !isGameOver {
                ensureClockLoopRunning()
            }
            duckMood = .idle
            duckHeadYaw = 0
            duckBounce = 0.2
            duckLine = "Move taken back. \(game.sideToMove.label) to play!"
        }
    }

    /// Resigns for the currently active human side (or the human color in AI modes).
    func resign() {
        guard !isGameOver else { return }
        cancelInFlightTasks()
        stopClockLoop()
        stateGeneration &+= 1
        clearSelection()
        pendingPromotion = nil
        hintMove = nil

        let resigningColor: ChessColor = playMode.usesAI ? humanColor : game.sideToMove
        game.resign(color: resigningColor)

        if playMode.usesAI {
            duckMood = .checkmateWin
            duckHeadYaw = 0
            duckBounce = 0.65
            duckLine = "Good match! Tap Rematch whenever you want another round."
        } else {
            let victor = resigningColor.opposite
            duckMood = .checkmateWin
            duckHeadYaw = 0
            duckBounce = 0.65
            duckLine = "\(resigningColor.label) resigned. \(victor.label) wins!"
        }
    }

    /// Ends the current game in a mutual draw by agreement.
    func agreeDraw() {
        guard !isGameOver else { return }
        cancelInFlightTasks()
        stopClockLoop()
        stateGeneration &+= 1
        clearSelection()
        pendingPromotion = nil
        hintMove = nil

        game.agreeDraw()
        duckMood = .drawBow
        duckHeadYaw = 0
        duckBounce = 0.35
        duckLine = "Draw agreed! MicroDuck bows to both players."
    }

    // MARK: Private Move Commit & Turn Progression

    private func commitHumanMove(_ move: ChessMove) {
        let movingColor = game.sideToMove
        guard let record = game.makeMove(move) else {
            clearSelection()
            return
        }

        stateGeneration &+= 1
        clearSelection()
        hintMove = nil
        applyClockIncrement(for: movingColor)

        updateDuckReaction(after: record, wasAIMove: false)

        if isGameOver {
            stopClockLoop()
            return
        }

        if timeControl != .untimed {
            ensureClockLoopRunning()
        }

        if playMode == .twoPlayerSameBoard {
            if autoFlipBoard {
                isBoardFlipped = (game.sideToMove == .black)
            }
        } else {
            scheduleAIMoveIfNeeded()
        }
    }

    private func commitAIMove(
        _ move: ChessMove,
        commentary: String?,
        statusLine: String,
        providerBadge: String,
        latencySeconds: Double,
        usedFallback: Bool
    ) {
        let movingColor = game.sideToMove
        let sanitizedComment = commentary.map {
            ChessLLMPrompt.sanitizeCommentary($0, fallbackSAN: game.state.san(for: move) ?? move.uci)
        }

        guard let record = game.makeMove(move, commentary: sanitizedComment) else {
            // Absolute safety net: if anything unexpected occurred, play a deterministic legal engine move.
            if let safe = ChessSearchAI.bestMove(for: game.state, difficulty: difficulty),
               let safeRecord = game.makeMove(safe.move, commentary: safe.commentary) {
                stateGeneration &+= 1
                applyClockIncrement(for: movingColor)
                aiStatusLine = "Built-in Engine fallback (\(difficulty.label))"
                aiProviderBadge = "Engine Fallback"
                lastAILatencySeconds = latencySeconds
                aiUsedFallback = true
                updateDuckReaction(after: safeRecord, wasAIMove: true)
                if isGameOver { stopClockLoop() }
            }
            return
        }

        stateGeneration &+= 1
        applyClockIncrement(for: movingColor)
        aiStatusLine = statusLine
        aiProviderBadge = providerBadge
        lastAILatencySeconds = latencySeconds
        aiUsedFallback = usedFallback

        updateDuckReaction(after: record, wasAIMove: true)

        if isGameOver {
            stopClockLoop()
        } else if timeControl != .untimed {
            ensureClockLoopRunning()
        }
    }

    private func clearSelection() {
        selectedSquare = nil
        legalDestinations = []
    }

    private func cancelInFlightTasks() {
        aiTask?.cancel()
        aiTask = nil
        hintTask?.cancel()
        hintTask = nil
        isAIThinking = false
        isComputingHint = false
    }

    // MARK: AI Turn Scheduling & Execution

    private func scheduleAIMoveIfNeeded() {
        guard playMode.usesAI, !isGameOver, game.sideToMove != humanColor else { return }

        aiTask?.cancel()
        isAIThinking = true
        hintTask?.cancel()
        isComputingHint = false
        hintMove = nil

        if timeControl != .untimed {
            ensureClockLoopRunning()
        }

        duckMood = .thinking
        duckHeadYaw = game.sideToMove == .white ? 12 : -12
        duckBounce = 0.2
        duckLine = thinkingDuckLine()

        let capturedGen = stateGeneration
        let gameSnapshot = game
        let modeSnapshot = playMode
        let difficultySnapshot = difficulty

        aiTask = Task { [weak self] in
            guard let self else { return }
            let started = Date()

            let outcome: AIMoveOutcome
            switch modeSnapshot {
            case .vsEngine:
                outcome = await self.computeEngineMove(
                    for: gameSnapshot.state,
                    difficulty: difficultySnapshot,
                    minimumFeelDelay: 0.28,
                    fallbackPrefix: nil
                )
            case .vsLocalAI:
                outcome = await self.computeLocalAIMove(
                    for: gameSnapshot,
                    difficulty: difficultySnapshot
                )
            case .vsCloudAI:
                outcome = await self.computeCloudAIMove(
                    for: gameSnapshot,
                    difficulty: difficultySnapshot
                )
            case .twoPlayerSameBoard:
                return
            }

            guard !Task.isCancelled, self.stateGeneration == capturedGen else { return }
            self.isAIThinking = false

            guard let move = outcome.move else { return }
            let elapsed = max(0.01, Date().timeIntervalSince(started))
            self.commitAIMove(
                move,
                commentary: outcome.commentary,
                statusLine: outcome.statusLine,
                providerBadge: outcome.providerBadge,
                latencySeconds: elapsed,
                usedFallback: outcome.usedFallback
            )
        }
    }

    private struct AIMoveOutcome: Sendable {
        let move: ChessMove?
        let commentary: String?
        let statusLine: String
        let providerBadge: String
        let usedFallback: Bool
    }

    // MARK: 1. Built-in Alpha-Beta Engine

    private func computeEngineMove(
        for state: ChessBoardState,
        difficulty: ChessAIDifficulty,
        minimumFeelDelay: TimeInterval,
        fallbackPrefix: String?
    ) async -> AIMoveOutcome {
        let started = Date()
        let result = await Task.detached(priority: .userInitiated) {
            ChessSearchAI.bestMove(for: state, difficulty: difficulty)
        }.value

        let elapsed = Date().timeIntervalSince(started)
        if minimumFeelDelay > elapsed {
            let waitNs = UInt64((minimumFeelDelay - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: waitNs)
        }

        guard let result else {
            return AIMoveOutcome(
                move: nil,
                commentary: nil,
                statusLine: "No legal moves available",
                providerBadge: "Engine",
                usedFallback: fallbackPrefix != nil
            )
        }

        let status: String
        let badge: String
        if let prefix = fallbackPrefix {
            status = "\(prefix), using Built-in Engine fallback"
            badge = "Engine Fallback"
        } else {
            status = "Built-in Engine (\(difficulty.label)): depth \(result.depth), \(result.nodesSearched) nodes"
            badge = "Engine: \(difficulty.label)"
        }

        return AIMoveOutcome(
            move: result.move,
            commentary: result.commentary,
            statusLine: status,
            providerBadge: badge,
            usedFallback: fallbackPrefix != nil
        )
    }

    // MARK: 2. Local On-Device AI (MLX + Apple Intelligence)

    private struct LocalMLXTarget {
        let repository: String
        let label: String
        let timeout: TimeInterval
    }

    private func resolveReadyLocalModel() -> LocalMLXTarget? {
        // 1. Prefer the user's selected endpoint if it is a complete downloaded MLX model.
        let selected = endpointStore.selected
        if selected.kind == .downloadedMLX,
           !selected.model.isEmpty,
           PhoneModelFiles.state(selected.model) == .complete {
            return LocalMLXTarget(
                repository: selected.model,
                label: selected.name.isEmpty ? shortRepoName(selected.model) : selected.name,
                timeout: min(max(selected.timeout, 15), 30)
            )
        }

        // 2. Otherwise check any saved downloaded MLX endpoint in EndpointStore.
        for endpoint in endpointStore.endpoints where endpoint.kind == .downloadedMLX {
            if !endpoint.model.isEmpty, PhoneModelFiles.state(endpoint.model) == .complete {
                return LocalMLXTarget(
                    repository: endpoint.model,
                    label: endpoint.name.isEmpty ? shortRepoName(endpoint.model) : endpoint.name,
                    timeout: min(max(endpoint.timeout, 15), 30)
                )
            }
        }

        // 3. Finally scan PhoneModel.all on disk in case weights exist before an endpoint row was selected.
        for model in PhoneModel.all {
            if PhoneModelFiles.state(model.repository) == .complete {
                return LocalMLXTarget(
                    repository: model.repository,
                    label: model.name,
                    timeout: 25
                )
            }
        }

        return nil
    }

    private func isAppleIntelligenceAvailable() -> Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
#endif
        return false
    }

    private func computeLocalAIMove(
        for gameSnapshot: ChessGame,
        difficulty: ChessAIDifficulty
    ) async -> AIMoveOutcome {
        if ownsEndpointStore {
            endpointStore = EndpointStore()
        }

        let instructions = ChessLLMPrompt.instructions(for: gameSnapshot.sideToMove)
        let prompt = ChessLLMPrompt.userPrompt(for: gameSnapshot)

        // Path A: On-device MLX model via PhoneModelRuntime.shared.ask
        if let local = resolveReadyLocalModel() {
            let runtime = PhoneModelRuntime.shared
            if runtime.isSupported, PhoneModelFiles.bytesOnDisk(local.repository) != nil {
                let budget = Int(os_proc_available_memory())
                let resident = runtime.isResident(local.repository)
                let knownFits: Bool
                if budget > 0,
                   let known = PhoneModel.all.first(where: { $0.repository == local.repository }) {
                    knownFits = known.fits(budgetBytes: budget, alreadyResident: resident)
                } else {
                    knownFits = budget > 0
                }

                if knownFits {
                    aiStatusLine = "Local AI (MLX): \(local.label) thinking..."
                    aiProviderBadge = "MLX: \(local.label)"
                    let started = Date()
                    do {
                        let rawReply = try await runtime.ask(
                            local.repository,
                            instructions: instructions,
                            prompt: prompt,
                            deadline: local.timeout
                        )
                        if Task.isCancelled {
                            return AIMoveOutcome(move: nil, commentary: nil, statusLine: "", providerBadge: "", usedFallback: false)
                        }
                        if let decision = ChessLLMPrompt.parseResponse(rawReply, in: gameSnapshot.state) {
                            let elapsed = Date().timeIntervalSince(started)
                            return AIMoveOutcome(
                                move: decision.move,
                                commentary: decision.commentary,
                                statusLine: String(format: "Local AI (MLX): %@ (%.1fs)", local.label, elapsed),
                                providerBadge: "MLX: \(local.label)",
                                usedFallback: false
                            )
                        }
                        return await computeEngineMove(
                            for: gameSnapshot.state,
                            difficulty: difficulty,
                            minimumFeelDelay: 0.12,
                            fallbackPrefix: "Local AI (MLX) \(local.label) returned an illegal move"
                        )
                    } catch let failure as PhoneModelRuntime.Failure {
                        return await computeEngineMove(
                            for: gameSnapshot.state,
                            difficulty: difficulty,
                            minimumFeelDelay: 0.12,
                            fallbackPrefix: "Local AI (MLX) unavailable (\(failure.message))"
                        )
                    } catch {
                        if Task.isCancelled {
                            return AIMoveOutcome(move: nil, commentary: nil, statusLine: "", providerBadge: "", usedFallback: false)
                        }
                        return await computeEngineMove(
                            for: gameSnapshot.state,
                            difficulty: difficulty,
                            minimumFeelDelay: 0.12,
                            fallbackPrefix: "Local AI (MLX) error"
                        )
                    }
                } else {
                    return await computeEngineMove(
                        for: gameSnapshot.state,
                        difficulty: difficulty,
                        minimumFeelDelay: 0.2,
                        fallbackPrefix: "Local AI (MLX) \(local.label) needs more free memory"
                    )
                }
            } else if !isAppleIntelligenceAvailable() {
                return await computeEngineMove(
                    for: gameSnapshot.state,
                    difficulty: difficulty,
                    minimumFeelDelay: 0.25,
                    fallbackPrefix: "Local MLX needs a real device GPU"
                )
            }
        }

        // Path B: Apple on-device FoundationModels (iOS 26+ / macOS 26+)
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                aiStatusLine = "Local AI (Apple Intelligence) thinking..."
                aiProviderBadge = "Apple AI"
                let started = Date()
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let rawReply = try await session.respond(to: prompt).content
                    if Task.isCancelled {
                        return AIMoveOutcome(move: nil, commentary: nil, statusLine: "", providerBadge: "", usedFallback: false)
                    }
                    if let decision = ChessLLMPrompt.parseResponse(rawReply, in: gameSnapshot.state) {
                        let elapsed = Date().timeIntervalSince(started)
                        return AIMoveOutcome(
                            move: decision.move,
                            commentary: decision.commentary,
                            statusLine: String(format: "Local AI (Apple Intelligence) (%.1fs)", elapsed),
                            providerBadge: "Apple AI",
                            usedFallback: false
                        )
                    }
                    return await computeEngineMove(
                        for: gameSnapshot.state,
                        difficulty: difficulty,
                        minimumFeelDelay: 0.12,
                        fallbackPrefix: "Apple Intelligence returned an illegal move"
                    )
                } catch {
                    if Task.isCancelled {
                        return AIMoveOutcome(move: nil, commentary: nil, statusLine: "", providerBadge: "", usedFallback: false)
                    }
                    return await computeEngineMove(
                        for: gameSnapshot.state,
                        difficulty: difficulty,
                        minimumFeelDelay: 0.12,
                        fallbackPrefix: "Apple Intelligence could not answer"
                    )
                }
            }
        }
#endif

        // Path C: Graceful fallback to Built-in Engine
        return await computeEngineMove(
            for: gameSnapshot.state,
            difficulty: difficulty,
            minimumFeelDelay: 0.28,
            fallbackPrefix: "No local model downloaded yet"
        )
    }

    // MARK: 3. Cloud / Remote AI (EndpointStore + Hosted Anthropic / OpenAI Keys)

    private enum CloudTarget {
        case openAICompatible(ModelEndpoint)
        case anthropicKey(String)
        case openAIKey(String)

        var shortLabel: String {
            switch self {
            case .openAICompatible(let ep):
                return ep.name.isEmpty ? "Remote AI" : ep.name
            case .anthropicKey:
                return "Anthropic"
            case .openAIKey:
                return "OpenAI"
            }
        }

        var detailLabel: String {
            switch self {
            case .openAICompatible(let ep):
                return "\(ep.name) (\(ep.model))"
            case .anthropicKey:
                return "Anthropic (\(HostedVendor.anthropic.modelName))"
            case .openAIKey:
                return "OpenAI (\(HostedVendor.openai.modelName))"
            }
        }
    }

    private func resolveCloudTarget() -> CloudTarget? {
        // 1. Prefer selected endpoint if it is a configured OpenAI-compatible remote/LAN server.
        let selected = endpointStore.selected
        if selected.kind == .openAICompatible,
           !selected.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           (try? selected.chatURL()) != nil {
            return .openAICompatible(endpointStore.armed(selected))
        }

        // 2. Otherwise find the best configured OpenAI-compatible endpoint (preferring cloud/HTTPS/relay first).
        let openAIEndpoints = endpointStore.endpoints.filter {
            $0.kind == .openAICompatible
                && !$0.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (try? $0.chatURL()) != nil
        }
        if let remote = openAIEndpoints.first(where: { ep in
            if ep.relay { return true }
            if let host = URL(string: ep.baseURL)?.host {
                return !ModelEndpoint.isLocalHost(host)
            }
            return false
        }) {
            return .openAICompatible(endpointStore.armed(remote))
        }
        if let anyServer = openAIEndpoints.first {
            return .openAICompatible(endpointStore.armed(anyServer))
        }

        // 3. Hosted BYOK keys saved in Keychain (Anthropic or OpenAI).
        if let anthropicKey = HostedKeyStore.load(.anthropic), !anthropicKey.isEmpty {
            return .anthropicKey(anthropicKey)
        }
        if let openAIKey = HostedKeyStore.load(.openai), !openAIKey.isEmpty {
            return .openAIKey(openAIKey)
        }

        return nil
    }

    private func computeCloudAIMove(
        for gameSnapshot: ChessGame,
        difficulty: ChessAIDifficulty
    ) async -> AIMoveOutcome {
        if ownsEndpointStore {
            endpointStore = EndpointStore()
        }

        guard let target = resolveCloudTarget() else {
            return await computeEngineMove(
                for: gameSnapshot.state,
                difficulty: difficulty,
                minimumFeelDelay: 0.28,
                fallbackPrefix: "No cloud endpoint configured in Models"
            )
        }

        let instructions = ChessLLMPrompt.instructions(for: gameSnapshot.sideToMove)
        let prompt = ChessLLMPrompt.userPrompt(for: gameSnapshot)
        aiStatusLine = "Cloud AI: \(target.detailLabel) thinking..."
        aiProviderBadge = target.shortLabel
        let started = Date()

        do {
            let rawReply: String
            switch target {
            case .openAICompatible(let endpoint):
                rawReply = try await requestOpenAICompatibleMove(
                    endpoint: endpoint,
                    instructions: instructions,
                    prompt: prompt
                )
            case .anthropicKey(let apiKey):
                rawReply = try await requestAnthropicMove(
                    apiKey: apiKey,
                    instructions: instructions,
                    prompt: prompt
                )
            case .openAIKey(let apiKey):
                rawReply = try await requestOpenAIResponsesMove(
                    apiKey: apiKey,
                    instructions: instructions,
                    prompt: prompt
                )
            }

            if Task.isCancelled {
                return AIMoveOutcome(move: nil, commentary: nil, statusLine: "", providerBadge: "", usedFallback: false)
            }

            if let decision = ChessLLMPrompt.parseResponse(rawReply, in: gameSnapshot.state) {
                let elapsed = Date().timeIntervalSince(started)
                return AIMoveOutcome(
                    move: decision.move,
                    commentary: decision.commentary,
                    statusLine: String(format: "Cloud AI: %@ (%.1fs)", target.detailLabel, elapsed),
                    providerBadge: target.shortLabel,
                    usedFallback: false
                )
            }

            return await computeEngineMove(
                for: gameSnapshot.state,
                difficulty: difficulty,
                minimumFeelDelay: 0.12,
                fallbackPrefix: "Cloud AI (\(target.shortLabel)) returned an illegal move"
            )
        } catch {
            if Task.isCancelled {
                return AIMoveOutcome(move: nil, commentary: nil, statusLine: "", providerBadge: "", usedFallback: false)
            }
            return await computeEngineMove(
                for: gameSnapshot.state,
                difficulty: difficulty,
                minimumFeelDelay: 0.12,
                fallbackPrefix: "Cloud AI (\(target.shortLabel)) unreachable"
            )
        }
    }

    private func requestOpenAICompatibleMove(
        endpoint: ModelEndpoint,
        instructions: String,
        prompt: String
    ) async throws -> String {
        let url = try endpoint.chatURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = min(max(endpoint.timeout, 10), 30)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = endpoint.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let maxTokens = min(max(endpoint.maxTokens ?? 320, 200), 1200)
        request.httpBody = try ChatWire.requestBody(
            model: endpoint.model,
            instructions: instructions,
            prompt: prompt,
            temperature: 0.2,
            maxTokens: maxTokens,
            suppressReasoning: endpoint.suppressReasoning
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CloudChessError.httpFailure((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try ChatWire.content(from: data)
    }

    private func requestAnthropicMove(
        apiKey: String,
        instructions: String,
        prompt: String
    ) async throws -> String {
        var request = URLRequest(url: AnthropicPlanner.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(AnthropicPlanner.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        // Anthropic API version 2026-10-21 forbids sampling fields such as temperature.
        let payload: [String: Any] = [
            "model": AnthropicPlanner.defaultModel,
            "max_tokens": 256,
            "system": instructions,
            "messages": [
                ["role": "user", "content": prompt]
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CloudChessError.httpFailure((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = top["content"] as? [[String: Any]] else {
            throw CloudChessError.unreadableResponse
        }
        let texts = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        guard !texts.isEmpty else {
            throw CloudChessError.unreadableResponse
        }
        return texts.joined(separator: "\n")
    }

    private func requestOpenAIResponsesMove(
        apiKey: String,
        instructions: String,
        prompt: String
    ) async throws -> String {
        var request = URLRequest(url: OpenAIPlanner.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": OpenAIPlanner.defaultModel,
            "instructions": instructions,
            "input": prompt,
            "store": false,
            "max_output_tokens": 256,
            "reasoning": ["effort": "none"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CloudChessError.httpFailure((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudChessError.unreadableResponse
        }
        if let direct = top["output_text"] as? String, !direct.isEmpty {
            return direct
        }
        if let output = top["output"] as? [[String: Any]] {
            var collected: [String] = []
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                for part in content {
                    if let text = part["text"] as? String, !text.isEmpty {
                        collected.append(text)
                    }
                }
            }
            if !collected.isEmpty {
                return collected.joined(separator: "\n")
            }
        }
        throw CloudChessError.unreadableResponse
    }

    private enum CloudChessError: Error {
        case httpFailure(Int)
        case unreadableResponse
    }

    // MARK: Clock Management

    private func resetClocksForCurrentControl() {
        stopClockLoop()
        if let initial = timeControl.initialSeconds {
            whiteClockSeconds = initial
            blackClockSeconds = initial
        } else {
            whiteClockSeconds = 0
            blackClockSeconds = 0
        }
    }

    private func applyClockIncrement(for mover: ChessColor) {
        guard timeControl != .untimed, timeControl.incrementSeconds > 0 else { return }
        if mover == .white {
            whiteClockSeconds += timeControl.incrementSeconds
        } else {
            blackClockSeconds += timeControl.incrementSeconds
        }
    }

    private func ensureClockLoopRunning() {
        guard timeControl != .untimed, !isGameOver else {
            stopClockLoop()
            return
        }
        guard clockTask == nil else { return }
        lastClockTickDate = Date()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, !Task.isCancelled else { break }
                self.tickClock()
                if self.isGameOver || self.timeControl == .untimed {
                    break
                }
            }
        }
    }

    private func stopClockLoop() {
        clockTask?.cancel()
        clockTask = nil
        lastClockTickDate = nil
    }

    private func tickClock() {
        guard timeControl != .untimed, !isGameOver else {
            stopClockLoop()
            return
        }
        guard !game.history.isEmpty || isAIThinking else {
            lastClockTickDate = Date()
            return
        }
        let now = Date()
        let delta = max(0, min(1.0, now.timeIntervalSince(lastClockTickDate ?? now)))
        lastClockTickDate = now

        if game.sideToMove == .white {
            whiteClockSeconds = max(0, whiteClockSeconds - delta)
            if whiteClockSeconds <= 0 {
                handleTimeout(loser: .white)
            }
        } else {
            blackClockSeconds = max(0, blackClockSeconds - delta)
            if blackClockSeconds <= 0 {
                handleTimeout(loser: .black)
            }
        }
    }

    private func handleTimeout(loser: ChessColor) {
        cancelInFlightTasks()
        stopClockLoop()
        stateGeneration &+= 1
        clearSelection()
        pendingPromotion = nil
        hintMove = nil

        let victor = loser.opposite
        timeoutWinner = victor

        if playMode.usesAI {
            if victor == humanColor {
                duckMood = .checkmateLoss
                duckLine = "Time expired! You win on the clock."
            } else {
                duckMood = .checkmateWin
                duckLine = "Flag fell! MicroDuck wins on time."
            }
        } else {
            duckMood = .checkmateWin
            duckLine = "\(loser.label) ran out of time. \(victor.label) wins!"
        }
        duckHeadYaw = 0
        duckBounce = 0.7
    }

    // MARK: Status & MicroDuck Companion Helpers

    private func refreshAIStatusSummary() {
        switch playMode {
        case .vsEngine:
            aiStatusLine = "Built-in Engine (\(difficulty.label)): 100% offline"
            aiProviderBadge = "Engine: \(difficulty.label)"
            aiUsedFallback = false
        case .vsLocalAI:
            if let local = resolveReadyLocalModel() {
                if PhoneModelRuntime.shared.isSupported {
                    aiStatusLine = "Local AI (MLX): \(local.label)"
                    aiProviderBadge = "MLX: \(local.label)"
                    aiUsedFallback = false
                } else {
                    aiStatusLine = "Local MLX needs a real device GPU, using Built-in Engine fallback"
                    aiProviderBadge = "Engine Fallback"
                    aiUsedFallback = true
                }
            } else if isAppleIntelligenceAvailable() {
                aiStatusLine = "Local AI (Apple Intelligence)"
                aiProviderBadge = "Apple AI"
                aiUsedFallback = false
            } else {
                aiStatusLine = "No local model downloaded yet, using Built-in Engine fallback"
                aiProviderBadge = "Engine Fallback"
                aiUsedFallback = true
            }
        case .vsCloudAI:
            if let target = resolveCloudTarget() {
                aiStatusLine = "Cloud AI: \(target.detailLabel)"
                aiProviderBadge = target.shortLabel
                aiUsedFallback = false
            } else {
                aiStatusLine = "No cloud endpoint configured in Models, using Built-in Engine fallback"
                aiProviderBadge = "Engine Fallback"
                aiUsedFallback = true
            }
        case .twoPlayerSameBoard:
            aiStatusLine = tabletopFaceToFace
                ? "2-Player Tabletop mode: share the board face to face"
                : (autoFlipBoard ? "2-Player Pass & Play: auto-flip enabled" : "2-Player Pass & Play on the same board")
            aiProviderBadge = "2-Player"
            aiUsedFallback = false
        }
    }

    private func setInitialDuckGreeting() {
        duckMood = .idle
        duckHeadYaw = 0
        duckBounce = 0.2
        switch playMode {
        case .vsEngine:
            duckLine = humanColor == .white
                ? "Quack! You have White. Make your opening move."
                : "Quack! I have White. Opening the game now!"
        case .vsLocalAI:
            duckLine = "Local AI chess ready! Tap a piece to begin."
        case .vsCloudAI:
            duckLine = "Cloud AI chess ready! Tap a piece to begin."
        case .twoPlayerSameBoard:
            duckLine = "Pass & Play ready! White makes the first move."
        }
    }

    private func thinkingDuckLine() -> String {
        switch playMode {
        case .vsEngine:
            return "MicroDuck is calculating lines..."
        case .vsLocalAI:
            return "Thinking on device..."
        case .vsCloudAI:
            return "Consulting remote AI..."
        case .twoPlayerSameBoard:
            return "Your move!"
        }
    }

    private func updateDuckReaction(after record: ChessMoveRecord, wasAIMove: Bool) {
        let yawFromFile = Double(record.move.to.file) * 7.0 - 24.5

        switch game.status {
        case .checkmate(let victor):
            if playMode.usesAI {
                if victor == humanColor {
                    duckMood = .checkmateLoss
                    duckLine = "Checkmate with \(record.san)! You outplayed this duck."
                } else {
                    duckMood = .checkmateWin
                    duckLine = record.commentary ?? "Checkmate with \(record.san)! Quack-mate!"
                }
            } else {
                duckMood = .checkmateWin
                duckLine = "Checkmate with \(record.san)! \(victor.label) wins!"
            }
            duckHeadYaw = 0
            duckBounce = 1.0

        case .stalemate, .drawFiftyMove, .drawThreefoldRepetition, .drawInsufficientMaterial, .drawAgreement:
            duckMood = .drawBow
            duckHeadYaw = 0
            duckBounce = 0.45
            duckLine = "\(game.status.summaryText). MicroDuck bows to a sharp game!"

        case .check(let checkedColor):
            duckMood = .checkAlert
            duckHeadYaw = checkedColor == .white ? -18 : 18
            duckBounce = 0.85
            if wasAIMove, let comment = record.commentary, !comment.isEmpty {
                duckLine = comment
            } else {
                duckLine = "Check with \(record.san)! Watch \(checkedColor.label)'s king."
            }

        case .active:
            if let captured = record.captured {
                duckMood = .happyCapture
                duckHeadYaw = yawFromFile
                duckBounce = captured.materialValue >= 5 ? 0.9 : 0.65
                if wasAIMove, let comment = record.commentary, !comment.isEmpty {
                    duckLine = comment
                } else {
                    duckLine = "Snatched the \(captured.kind.label.lowercased()) with \(record.san)!"
                }
            } else {
                duckMood = .idle
                duckHeadYaw = yawFromFile * 0.6
                duckBounce = 0.25
                if wasAIMove, let comment = record.commentary, !comment.isEmpty {
                    duckLine = comment
                } else if record.san == "O-O" || record.san == "O-O-O" {
                    duckLine = "Safe king! Castled with \(record.san)."
                } else if record.move.promotion != nil {
                    duckLine = "Promotion with \(record.san)! Big upgrade."
                } else if playMode == .twoPlayerSameBoard {
                    duckLine = "Played \(record.san). Over to \(game.sideToMove.label)!"
                } else {
                    duckLine = "Nice move: \(record.san)."
                }
            }

        case .resigned(let victor):
            duckMood = .checkmateWin
            duckHeadYaw = 0
            duckBounce = 0.5
            duckLine = "\(victor.label) wins by resignation."
        }
    }

    private func shortRepoName(_ repository: String) -> String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}
