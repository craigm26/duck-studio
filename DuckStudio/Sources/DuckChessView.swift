import SwiftUI
import StudioKit

/// Interactive Sim Chess inside DuckStudio.
///
/// Supports four modes on a single high-contrast 8x8 board:
/// - 2-Player Pass & Play (with Auto-Flip and Tabletop 180-degree piece rotation)
/// - Local On-Device AI (downloaded MLX or Apple Intelligence with Engine fallback)
/// - Cloud / Remote AI (configured EndpointStore / API keys with Engine fallback)
/// - Built-in Offline Alpha-Beta Engine (Casual, Club, Strong)
///
/// Follows DuckStudio house rules:
/// - StudioKit (`ChessEngine`, `ChessSearchAI`) computes; `ChessGameSession` orchestrates;
///   this view renders and binds.
/// - Every sheet carries `.stopPill()`.
/// - Uses `SectionHeading` for list section headers and Pond Day button styles.
/// - Zero em-dashes in strings, zero force unwraps, dark and light scheme adaptive.
struct DuckChessView: View {
    @StateObject private var session: ChessGameSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showSetupSheet = false
    @State private var showResignConfirm = false
    @State private var showGameOverOverlay = true
    @State private var checkPulse = false

    /// Ordered mode pills for the top bar.
    private static let modeOrder: [ChessPlayMode] = [
        .twoPlayerSameBoard,
        .vsLocalAI,
        .vsCloudAI,
        .vsEngine,
    ]

    init(models: EndpointStore? = nil) {
        _session = StateObject(wrappedValue: ChessGameSession(models: models))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing(.tight)) {
                modeAndControlsPanel
                microDuckCompanionStrip
                playerStrip(for: session.topColor, isTop: true)
                boardSection
                playerStrip(for: session.bottomColor, isTop: false)
                moveHistoryRibbon
                actionToolbar
            }
            .padding(.horizontal, Theme.spacing(.snug))
            .padding(.vertical, Theme.spacing(.tight))
            .frame(maxWidth: sizeClass == .regular ? 640 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundSecondary)
        .navigationTitle("Sim Chess")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSetupSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: session.timeControl == .untimed ? "slider.horizontal.3" : "timer")
                        if session.timeControl != .untimed {
                            Text(session.timeControl.title)
                                .font(.caption.weight(.bold).monospacedDigit())
                        }
                    }
                }
                .accessibilityLabel(Text("Match setup and clock"))
            }
        }
        .sheet(isPresented: $showSetupSheet) {
            ChessSetupSheet(session: session)
                .stopPill()
        }
        .confirmationDialog(
            "End Current Game?",
            isPresented: $showResignConfirm,
            titleVisibility: .visible
        ) {
            Button("Resign", role: .destructive) {
                session.resign()
            }
            Button("Agree to Draw") {
                session.agreeDraw()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can resign this match or end it as a mutual draw.")
        }
        .onAppear {
            session.resumeClockIfNeeded()
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    checkPulse = true
                }
            }
        }
        .onDisappear {
            session.stopAllTasks()
        }
        .onChange(of: session.isGameOver) { _, ended in
            if ended {
                showGameOverOverlay = true
                Haptic.finished()
            }
        }
    }

    // MARK: - 1. Top Mode & Contextual Opponent Bar

    private var modeAndControlsPanel: some View {
        VStack(spacing: Theme.spacing(.tight)) {
            HStack(spacing: 5) {
                ForEach(Self.modeOrder) { mode in
                    let isSelected = session.playMode == mode
                    Button {
                        withAnimation(Theme.motion(reduced: reduceMotion)) {
                            session.selectPlayMode(mode)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: mode.symbol)
                                .font(.caption2.weight(.bold))
                            Text(mode.title)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .foregroundStyle(isSelected ? Theme.onFill : Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 34)
                        .padding(.horizontal, 4)
                        .background(
                            Capsule().fill(isSelected ? Theme.actionTeal : Theme.backgroundSecondary)
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                isSelected ? Theme.outline : Theme.separator,
                                lineWidth: isSelected ? 1.5 : DesignMetric.hairlineStroke
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityLabel(Text(mode.fullTitle))
                }
            }

            contextualSubControls
        }
        .padding(Theme.spacing(.tight))
        .pondPanel()
    }

    @ViewBuilder
    private var contextualSubControls: some View {
        switch session.playMode {
        case .twoPlayerSameBoard:
            HStack(spacing: 6) {
                compactTogglePill(
                    title: "Auto-Flip",
                    symbol: "arrow.triangle.2.circlepath",
                    isOn: session.autoFlipBoard
                ) {
                    withAnimation(Theme.motion(reduced: reduceMotion)) {
                        session.autoFlipBoard.toggle()
                    }
                }
                compactTogglePill(
                    title: "Tabletop",
                    symbol: "arrow.up.arrow.down.circle",
                    isOn: session.tabletopFaceToFace
                ) {
                    withAnimation(Theme.motion(reduced: reduceMotion)) {
                        session.tabletopFaceToFace.toggle()
                    }
                }
                Spacer(minLength: 2)
                turnBadgePill
            }

        case .vsLocalAI:
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    providerBadgeChip(
                        text: session.aiProviderBadge,
                        symbol: "iphone.gen3",
                        isFallback: session.aiUsedFallback
                    )
                    Spacer(minLength: 4)
                    humanSideSegmentedChip
                }
                if session.aiUsedFallback || session.aiStatusLine.localizedCaseInsensitiveContains("fallback") {
                    statusNoteRow(session.aiStatusLine, isWarning: true)
                } else {
                    statusNoteRow(session.aiStatusLine, isWarning: false)
                }
            }

        case .vsCloudAI:
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    providerBadgeChip(
                        text: session.aiProviderBadge,
                        symbol: "cloud",
                        isFallback: session.aiUsedFallback
                    )
                    Spacer(minLength: 4)
                    humanSideSegmentedChip
                }
                statusNoteRow(
                    cloudStatusLineWithLatency,
                    isWarning: session.aiUsedFallback || session.aiStatusLine.localizedCaseInsensitiveContains("fallback")
                )
            }

        case .vsEngine:
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(ChessAIDifficulty.allCases) { level in
                        let selected = session.difficulty == level
                        Button {
                            session.setDifficulty(level)
                        } label: {
                            Text(level.label)
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(selected ? Theme.onFill : Theme.textSecondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(selected ? Theme.actionYellow : Theme.backgroundSecondary)
                                )
                                .overlay(
                                    Capsule().strokeBorder(
                                        selected ? Theme.outline : Theme.separator,
                                        lineWidth: selected ? 1.5 : DesignMetric.hairlineStroke
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                Spacer(minLength: 4)
                humanSideSegmentedChip
            }
        }
    }

    private var cloudStatusLineWithLatency: String {
        if let latency = session.lastAILatencySeconds, !session.aiUsedFallback {
            return "\(session.aiStatusLine) (\(String(format: "%.1fs", latency)))"
        }
        return session.aiStatusLine
    }

    private func compactTogglePill(
        title: String,
        symbol: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption2.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? Theme.onFill : Theme.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isOn ? Theme.actionYellow : Theme.backgroundSecondary)
            )
            .overlay(
                Capsule().strokeBorder(
                    isOn ? Theme.outline : Theme.separator,
                    lineWidth: isOn ? 1.5 : DesignMetric.hairlineStroke
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }

    private var turnBadgePill: some View {
        let isWhite = session.sideToMove == .white
        let isCheck: Bool = {
            if case .check = session.game.status { return true }
            return false
        }()
        return HStack(spacing: 5) {
            Circle()
                .fill(isWhite ? ChessBoardColors.whitePieceFill : ChessBoardColors.blackPieceFill)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle().strokeBorder(
                        isWhite ? ChessBoardColors.whitePieceStroke : ChessBoardColors.blackPieceStroke,
                        lineWidth: 1.2
                    )
                )
            Text(session.isGameOver ? "Final" : (isCheck ? "\(session.sideToMove.label) Check" : "\(session.sideToMove.label) Turn"))
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .foregroundStyle(isCheck ? Theme.refused : Theme.textPrimary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.backgroundSecondary, in: Capsule())
        .overlay(Capsule().strokeBorder(isCheck ? Theme.refused : Theme.separator, lineWidth: 1))
    }

    private var humanSideSegmentedChip: some View {
        HStack(spacing: 3) {
            sideChoiceButton(.white, title: "Play White")
            sideChoiceButton(.black, title: "Play Black")
        }
        .padding(2)
        .background(Theme.backgroundSecondary, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: DesignMetric.hairlineStroke))
    }

    private func sideChoiceButton(_ color: ChessColor, title: String) -> some View {
        let selected = session.humanColor == color
        return Button {
            if session.humanColor != color {
                withAnimation(Theme.motion(reduced: reduceMotion)) {
                    session.setHumanColor(color)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(color == .white ? ChessBoardColors.whitePieceFill : ChessBoardColors.blackPieceFill)
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle().strokeBorder(
                            color == .white ? ChessBoardColors.whitePieceStroke : ChessBoardColors.blackPieceStroke,
                            lineWidth: 1
                        )
                    )
                Text(color == .white ? "White" : "Black")
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.onFill : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(selected ? Theme.actionPrimary : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func providerBadgeChip(text: String, symbol: String, isFallback: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isFallback ? "cpu" : symbol)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(isFallback ? Theme.warning : Theme.measured)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.backgroundSecondary, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                isFallback ? Theme.warning.opacity(0.6) : Theme.measured.opacity(0.45),
                lineWidth: 1
            )
        )
    }

    private func statusNoteRow(_ text: String, isWarning: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isWarning ? "info.circle.fill" : "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(isWarning ? Theme.warning : Theme.measured)
            Text(text)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 2. Sim MicroDuck Companion Strip

    private var microDuckCompanionStrip: some View {
        HStack(spacing: Theme.spacing(.tight)) {
            SimMicroDuckAvatar(
                mood: session.duckMood,
                headYaw: session.duckHeadYaw,
                bounce: session.duckBounce,
                isThinking: session.isAIThinking || session.isComputingHint
            )
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("DIGITAL SIM")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.onFill)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.actionTeal, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: 1))

                    Label(session.duckMood.badgeLabel, systemImage: session.duckMood.symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(moodTint(session.duckMood))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if session.isAIThinking || session.isComputingHint {
                        HStack(spacing: 4) {
                            LensIndicator(state: .connecting, size: 16)
                            Text(session.isComputingHint ? "Hint" : "Thinking")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.measured)
                        }
                    } else if session.timeControl != .untimed {
                        Label(session.timeControl.title, systemImage: "timer")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Text(session.duckLine)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(Theme.motion(reduced: reduceMotion), value: session.duckLine)
            }
        }
        .padding(.horizontal, Theme.spacing(.snug))
        .padding(.vertical, Theme.spacing(.tight))
        .pondPanel()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Digital Sim MicroDuck, \(session.duckMood.badgeLabel). \(session.duckLine)"))
    }

    private func moodTint(_ mood: MicroDuckChessMood) -> Color {
        switch mood {
        case .idle: return Theme.measured
        case .thinking: return Theme.actionInk
        case .happyCapture: return Theme.success
        case .checkAlert: return Theme.refused
        case .checkmateWin: return Theme.success
        case .checkmateLoss: return Theme.textSecondary
        case .drawBow: return Theme.measured
        }
    }

    // MARK: - 3. Player Strips (Captured Pieces, Material & Clocks)

    private func playerStrip(for color: ChessColor, isTop: Bool) -> some View {
        let isTurn = !session.isGameOver && session.sideToMove == color
        let captured = session.capturedPieces(by: color)
        let advantage = session.materialAdvantage(for: color)
        let isTabletopRotated = isTop && session.playMode == .twoPlayerSameBoard && session.tabletopFaceToFace
        let clockRunning = session.isClockRunning(for: color)
        let remaining = session.clockSeconds(for: color)
        let isLowTime = session.timeControl != .untimed && remaining < 15 && !session.isGameOver

        return HStack(spacing: Theme.spacing(.tight)) {
            Circle()
                .fill(color == .white ? ChessBoardColors.whitePieceFill : ChessBoardColors.blackPieceFill)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle().strokeBorder(
                        isTurn ? Theme.actionPrimary : (color == .white ? ChessBoardColors.whitePieceStroke : ChessBoardColors.blackPieceStroke),
                        lineWidth: isTurn ? 2.5 : 1.5
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.playerLabel(for: color))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    if isTurn {
                        Text(session.isAIThinking && session.playMode.usesAI && color != session.humanColor ? "Thinking" : "To move")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.onFill)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.actionPrimary, in: Capsule())
                    }
                }

                if !captured.isEmpty || advantage > 0 {
                    HStack(spacing: 4) {
                        capturedPiecesRow(captured)
                        if advantage > 0 {
                            Text("+\(advantage)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.measured)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            if session.timeControl != .untimed {
                Text(session.formattedClock(for: color))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(
                        isLowTime ? .white : (clockRunning ? Theme.onFill : Theme.textPrimary)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
                            isLowTime
                                ? Theme.refused
                                : (clockRunning ? Theme.actionYellow : Theme.backgroundSecondary)
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(
                            clockRunning || isLowTime ? Theme.outline : Theme.separator,
                            lineWidth: clockRunning ? 1.5 : 1
                        )
                    )
            }
        }
        .padding(.horizontal, Theme.spacing(.snug))
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius(.card), style: .continuous)
                .fill(Theme.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius(.card), style: .continuous)
                .strokeBorder(
                    isTurn ? Theme.actionPrimary : Theme.outline.opacity(0.22),
                    lineWidth: isTurn ? 1.8 : DesignMetric.hairlineStroke
                )
        )
        .rotationEffect(isTabletopRotated ? .degrees(180) : .zero)
        .animation(Theme.motion(reduced: reduceMotion), value: isTabletopRotated)
    }

    private func capturedPiecesRow(_ pieces: [ChessPiece]) -> some View {
        let sorted = pieces.sorted { $0.materialValue > $1.materialValue }
        return HStack(spacing: -2) {
            ForEach(Array(sorted.prefix(12).enumerated()), id: \.offset) { _, piece in
                ChessPieceGlyph(piece: piece)
                    .frame(width: 14, height: 14)
            }
            if sorted.count > 12 {
                Text("+\(sorted.count - 12)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 3)
            }
        }
    }

    // MARK: - 4. Interactive 8x8 Chess Board

    private var boardSection: some View {
        ZStack {
            GeometryReader { geo in
                let boardSize = min(geo.size.width, geo.size.height)
                let squareSize = boardSize / 8.0

                ZStack {
                    VStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<8, id: \.self) { col in
                                    let file = session.isBoardFlipped ? (7 - col) : col
                                    let rank = session.isBoardFlipped ? row : (7 - row)
                                    if let square = ChessSquare(file: file, rank: rank) {
                                        boardSquareView(
                                            square: square,
                                            row: row,
                                            col: col,
                                            squareSize: squareSize
                                        )
                                    }
                                }
                            }
                        }
                    }

                    if let hint = session.hintMove {
                        HintArrowOverlay(
                            move: hint,
                            isFlipped: session.isBoardFlipped,
                            squareSize: squareSize
                        )
                        .allowsHitTesting(false)
                    }
                }
                .frame(width: boardSize, height: boardSize)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ChessBoardColors.boardFrame, lineWidth: 2.5)
                )
                .shadow(color: PondShadow.colour, radius: PondShadow.blur, y: PondShadow.y)
            }
            .aspectRatio(1, contentMode: .fit)

            if session.pendingPromotion != nil, let promoColor = session.pendingPromotionColor {
                promotionOverlay(for: promoColor)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            if session.isGameOver && showGameOverOverlay {
                gameOverCardOverlay
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(Theme.motion(reduced: reduceMotion), value: session.pendingPromotion != nil)
        .animation(Theme.motion(reduced: reduceMotion), value: session.isGameOver && showGameOverOverlay)
    }

    private func boardSquareView(
        square: ChessSquare,
        row: Int,
        col: Int,
        squareSize: CGFloat
    ) -> some View {
        let piece = session.piece(at: square)
        let isSelected = session.selectedSquare == square
        let isLegalTarget = session.legalDestinations.contains(square)
        let isCaptureTarget = session.isCaptureDestination(square)
        let isLastMoveSquare = session.lastMove?.from == square || session.lastMove?.to == square
        let isHintSquare = session.hintMove?.from == square || session.hintMove?.to == square
        let isCheckKing = session.checkKingSquare == square
        let baseColor = square.isLightSquare ? ChessBoardColors.lightSquare : ChessBoardColors.darkSquare
        let coordColor = square.isLightSquare ? ChessBoardColors.darkSquare : ChessBoardColors.lightSquare

        return Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.84)) {
                session.tapSquare(square)
            }
        } label: {
            ZStack {
                Rectangle().fill(baseColor)

                if isLastMoveSquare {
                    Rectangle().fill(ChessBoardColors.lastMoveTint)
                }

                if isSelected {
                    Rectangle().fill(ChessBoardColors.selectedTint)
                    Rectangle()
                        .strokeBorder(Theme.actionTeal, lineWidth: max(2, squareSize * 0.06))
                }

                if isHintSquare {
                    Rectangle()
                        .strokeBorder(Theme.actionPrimary, lineWidth: max(2.2, squareSize * 0.065))
                }

                if isCheckKing {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    ChessBoardColors.checkCrimson.opacity(checkPulse ? 0.85 : 0.62),
                                    ChessBoardColors.checkCrimson.opacity(0.05),
                                ],
                                center: .center,
                                startRadius: squareSize * 0.08,
                                endRadius: squareSize * 0.52
                            )
                        )
                        .overlay(
                            Rectangle().strokeBorder(
                                ChessBoardColors.checkCrimson.opacity(checkPulse ? 0.95 : 0.6),
                                lineWidth: 2.5
                            )
                        )
                }

                // Rank coordinate along left edge
                if col == 0 {
                    Text(String(square.rankChar))
                        .font(.system(size: max(9, squareSize * 0.21), weight: .bold, design: .rounded))
                        .foregroundStyle(coordColor.opacity(0.88))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 2)
                        .padding(.top, 1)
                }

                // File coordinate along bottom edge
                if row == 7 {
                    Text(String(square.fileChar))
                        .font(.system(size: max(9, squareSize * 0.21), weight: .bold, design: .rounded))
                        .foregroundStyle(coordColor.opacity(0.88))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 2)
                        .padding(.bottom, 1)
                }

                if let piece {
                    ChessPieceGlyph(piece: piece)
                        .frame(width: squareSize * 0.84, height: squareSize * 0.84)
                        .rotationEffect(
                            session.shouldRotatePiece180(for: piece.color) ? .degrees(180) : .zero
                        )
                        .scaleEffect(isSelected ? 1.07 : 1.0)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                if isLegalTarget {
                    if isCaptureTarget {
                        Circle()
                            .strokeBorder(
                                ChessBoardColors.legalMarker.opacity(0.85),
                                lineWidth: max(3.5, squareSize * 0.11)
                            )
                            .padding(squareSize * 0.06)
                    } else {
                        Circle()
                            .fill(ChessBoardColors.legalMarker.opacity(0.52))
                            .frame(width: squareSize * 0.30, height: squareSize * 0.30)
                    }
                }
            }
            .frame(width: squareSize, height: squareSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(squareAccessibilityLabel(square, piece: piece, isLegal: isLegalTarget, isCapture: isCaptureTarget)))
    }

    private func squareAccessibilityLabel(
        _ square: ChessSquare,
        piece: ChessPiece?,
        isLegal: Bool,
        isCapture: Bool
    ) -> String {
        var parts: [String] = [square.algebraic]
        if let piece {
            parts.append("\(piece.color.label) \(piece.kind.label)")
        } else {
            parts.append("empty")
        }
        if isCapture {
            parts.append("legal capture")
        } else if isLegal {
            parts.append("legal move")
        }
        return parts.joined(separator: ", ")
    }

    private func promotionOverlay(for color: ChessColor) -> some View {
        ZStack {
            Color.black.opacity(0.42)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture {
                    session.cancelPromotion()
                }

            VStack(spacing: Theme.spacing(.tight)) {
                Text("Promote Pawn")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: Theme.spacing(.tight)) {
                    ForEach(ChessPieceKind.promotionKinds, id: \.self) { kind in
                        Button {
                            withAnimation(Theme.motion(reduced: reduceMotion)) {
                                session.completePromotion(kind)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                ChessPieceGlyph(piece: ChessPiece(color: color, kind: kind))
                                    .frame(width: 44, height: 44)
                                Text(kind.label)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .frame(width: 64, height: 74)
                            .background(Theme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.outline, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Cancel") {
                    session.cancelPromotion()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 2)
            }
            .padding(Theme.spacing(.standard))
            .pondPanel()
            .padding(Theme.spacing(.standard))
        }
    }

    private var gameOverCardOverlay: some View {
        ZStack {
            Color.black.opacity(0.46)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: Theme.spacing(.snug)) {
                Image(systemName: session.isDraw ? "handshake.fill" : "crown.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(session.isDraw ? Theme.actionTeal : Theme.actionYellow)

                Text(session.gameOverHeadline)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(session.gameOverDetail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: Theme.spacing(.tight)) {
                    Button("Rematch") {
                        withAnimation(Theme.motion(reduced: reduceMotion)) {
                            session.rematch()
                        }
                    }
                    .buttonStyle(.primaryAction)

                    Button("Inspect Board") {
                        withAnimation(Theme.motion(reduced: reduceMotion)) {
                            showGameOverOverlay = false
                        }
                    }
                    .buttonStyle(.raisedAction)
                }
            }
            .padding(Theme.spacing(.standard))
            .pondPanel()
            .padding(Theme.spacing(.standard))
        }
    }

    // MARK: - 5. Scrollable SAN Move History Ribbon

    private var moveHistoryRibbon: some View {
        let pairs = session.game.movePairs
        return HStack(spacing: Theme.spacing(.tight)) {
            Image(systemName: "list.number")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textTertiary)

            if pairs.isEmpty {
                Text(session.turnBannerText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pairs, id: \.number) { pair in
                                HStack(spacing: 4) {
                                    Text("\(pair.number).")
                                        .font(.caption.monospacedDigit().weight(.bold))
                                        .foregroundStyle(Theme.textTertiary)
                                    if let white = pair.white {
                                        Text(white.san)
                                            .font(.caption.monospaced().weight(.semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                    }
                                    if let black = pair.black {
                                        Text(black.san)
                                            .font(.caption.monospaced().weight(.semibold))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Theme.backgroundSecondary, in: Capsule())
                                .id(pair.number)
                            }
                        }
                    }
                    .onChange(of: session.game.history.count) { _, _ in
                        if let lastNumber = session.game.movePairs.last?.number {
                            withAnimation(Theme.motion(reduced: reduceMotion)) {
                                proxy.scrollTo(lastNumber, anchor: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.spacing(.snug))
        .padding(.vertical, 8)
        .frame(minHeight: 38)
        .pondPanel()
    }

    // MARK: - 6. Action Toolbar

    private var actionToolbar: some View {
        HStack(spacing: 6) {
            toolbarActionButton(
                title: "Undo",
                symbol: "arrow.uturn.backward",
                disabled: !session.canUndo
            ) {
                withAnimation(Theme.motion(reduced: reduceMotion)) {
                    session.undo()
                }
            }

            toolbarActionButton(
                title: "Hint",
                symbol: "lightbulb.fill",
                disabled: !session.canRequestHint
            ) {
                session.requestHint()
            }

            toolbarActionButton(
                title: "Flip",
                symbol: "arrow.up.arrow.down",
                disabled: false
            ) {
                withAnimation(Theme.motion(reduced: reduceMotion)) {
                    session.flipBoard()
                }
            }

            toolbarActionButton(
                title: "New",
                symbol: "plus.circle.fill",
                accent: true,
                disabled: false
            ) {
                showSetupSheet = true
            }

            toolbarActionButton(
                title: session.isGameOver ? "Rematch" : "Resign",
                symbol: session.isGameOver ? "arrow.clockwise" : "flag.fill",
                destructive: !session.isGameOver,
                disabled: false
            ) {
                if session.isGameOver {
                    withAnimation(Theme.motion(reduced: reduceMotion)) {
                        session.rematch()
                    }
                } else {
                    showResignConfirm = true
                }
            }
        }
    }

    private func toolbarActionButton(
        title: String,
        symbol: String,
        accent: Bool = false,
        destructive: Bool = false,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
                Text(title)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(
                disabled
                    ? Theme.textTertiary
                    : (accent ? Theme.onFill : (destructive ? Theme.refused : Theme.textPrimary))
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: DesignMetric.minimumTarget + 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(
                    disabled
                        ? Theme.surfaceInteractive
                        : (accent ? Theme.actionPrimary : Theme.surfacePrimary)
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(
                    disabled ? Theme.separator : (accent ? Theme.outline : Theme.outline.opacity(0.28)),
                    lineWidth: accent ? 1.8 : DesignMetric.hairlineStroke
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Board Palette

private enum ChessBoardColors {
    static let lightSquare = Color(red: 0.945, green: 0.898, blue: 0.796)
    static let darkSquare = Color(red: 0.443, green: 0.561, blue: 0.427)
    static let boardFrame = Color(red: 0.220, green: 0.286, blue: 0.235)

    static let lastMoveTint = Color(red: 0.98, green: 0.80, blue: 0.25).opacity(0.38)
    static let selectedTint = Color(red: 0.20, green: 0.78, blue: 0.76).opacity(0.36)
    static let legalMarker = Color(red: 0.11, green: 0.22, blue: 0.18)
    static let checkCrimson = Color(red: 0.88, green: 0.15, blue: 0.18)

    static let whitePieceFill = Color(red: 0.996, green: 0.984, blue: 0.945)
    static let whitePieceStroke = Color(red: 0.125, green: 0.161, blue: 0.184)
    static let whitePieceDetail = Color(red: 0.765, green: 0.725, blue: 0.655)

    static let blackPieceFill = Color(red: 0.137, green: 0.165, blue: 0.192)
    static let blackPieceStroke = Color(red: 0.933, green: 0.894, blue: 0.808)
    static let blackPieceDetail = Color(red: 0.420, green: 0.455, blue: 0.490)
}

// MARK: - Crisp Vector Staunton Chess Piece Glyph

/// High-contrast vector Staunton chess piece drawn on a `Canvas` so White pieces
/// (bright ivory with dark charcoal stroke) and Black pieces (deep obsidian charcoal
/// with warm cream rim) are instantly readable on every square and color scheme.
private struct ChessPieceGlyph: View {
    let piece: ChessPiece

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let s = min(w, h)
            let ox = (w - s) / 2
            let oy = (h - s) / 2

            let fill = piece.color == .white ? ChessBoardColors.whitePieceFill : ChessBoardColors.blackPieceFill
            let stroke = piece.color == .white ? ChessBoardColors.whitePieceStroke : ChessBoardColors.blackPieceStroke
            let detail = piece.color == .white ? ChessBoardColors.whitePieceDetail : ChessBoardColors.blackPieceDetail
            let strokeWidth = max(1.1, s * 0.048)

            func pt(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
                CGPoint(x: ox + nx * s, y: oy + ny * s)
            }

            var mainPath = Path()
            var accentLines = Path()

            switch piece.kind {
            case .pawn:
                // Classic pawn finial, neck collar, body, and base
                mainPath.addEllipse(in: CGRect(x: ox + s * 0.34, y: oy + s * 0.16, width: s * 0.32, height: s * 0.30))
                var body = Path()
                body.move(to: pt(0.36, 0.45))
                body.addLine(to: pt(0.64, 0.45))
                body.addQuadCurve(to: pt(0.72, 0.76), control: pt(0.60, 0.60))
                body.addLine(to: pt(0.80, 0.84))
                body.addLine(to: pt(0.80, 0.90))
                body.addLine(to: pt(0.20, 0.90))
                body.addLine(to: pt(0.20, 0.84))
                body.addLine(to: pt(0.28, 0.76))
                body.addQuadCurve(to: pt(0.36, 0.45), control: pt(0.40, 0.60))
                body.closeSubpath()
                mainPath.addPath(body)

                accentLines.move(to: pt(0.30, 0.78))
                accentLines.addLine(to: pt(0.70, 0.78))

            case .rook:
                // Crenelated battlement tower
                mainPath.move(to: pt(0.22, 0.16))
                mainPath.addLine(to: pt(0.34, 0.16))
                mainPath.addLine(to: pt(0.34, 0.26))
                mainPath.addLine(to: pt(0.44, 0.26))
                mainPath.addLine(to: pt(0.44, 0.16))
                mainPath.addLine(to: pt(0.56, 0.16))
                mainPath.addLine(to: pt(0.56, 0.26))
                mainPath.addLine(to: pt(0.66, 0.26))
                mainPath.addLine(to: pt(0.66, 0.16))
                mainPath.addLine(to: pt(0.78, 0.16))
                mainPath.addLine(to: pt(0.78, 0.36))
                mainPath.addLine(to: pt(0.70, 0.42))
                mainPath.addLine(to: pt(0.70, 0.72))
                mainPath.addLine(to: pt(0.82, 0.82))
                mainPath.addLine(to: pt(0.82, 0.90))
                mainPath.addLine(to: pt(0.18, 0.90))
                mainPath.addLine(to: pt(0.18, 0.82))
                mainPath.addLine(to: pt(0.30, 0.72))
                mainPath.addLine(to: pt(0.30, 0.42))
                mainPath.addLine(to: pt(0.22, 0.36))
                mainPath.closeSubpath()

                accentLines.move(to: pt(0.30, 0.42))
                accentLines.addLine(to: pt(0.70, 0.42))
                accentLines.move(to: pt(0.28, 0.74))
                accentLines.addLine(to: pt(0.72, 0.74))

            case .knight:
                // Sculpted Staunton horse silhouette
                mainPath.move(to: pt(0.22, 0.90))
                mainPath.addLine(to: pt(0.22, 0.82))
                mainPath.addLine(to: pt(0.30, 0.74))
                mainPath.addQuadCurve(to: pt(0.46, 0.48), control: pt(0.32, 0.58))
                mainPath.addLine(to: pt(0.30, 0.56))
                mainPath.addQuadCurve(to: pt(0.20, 0.47), control: pt(0.21, 0.54))
                mainPath.addQuadCurve(to: pt(0.38, 0.24), control: pt(0.22, 0.32))
                mainPath.addLine(to: pt(0.42, 0.13))
                mainPath.addLine(to: pt(0.52, 0.21))
                mainPath.addQuadCurve(to: pt(0.76, 0.46), control: pt(0.74, 0.24))
                mainPath.addQuadCurve(to: pt(0.72, 0.74), control: pt(0.78, 0.62))
                mainPath.addLine(to: pt(0.80, 0.82))
                mainPath.addLine(to: pt(0.80, 0.90))
                mainPath.closeSubpath()

                // Eye dot & mane accent
                accentLines.addEllipse(in: CGRect(x: ox + s * 0.36, y: oy + s * 0.31, width: s * 0.06, height: s * 0.06))
                accentLines.move(to: pt(0.28, 0.78))
                accentLines.addLine(to: pt(0.74, 0.78))

            case .bishop:
                // Mitre finial, dome head, collar, and flared base
                mainPath.addEllipse(in: CGRect(x: ox + s * 0.43, y: oy + s * 0.10, width: s * 0.14, height: s * 0.13))
                var mitre = Path()
                mitre.move(to: pt(0.50, 0.22))
                mitre.addQuadCurve(to: pt(0.70, 0.50), control: pt(0.72, 0.33))
                mitre.addQuadCurve(to: pt(0.64, 0.68), control: pt(0.68, 0.60))
                mitre.addLine(to: pt(0.78, 0.82))
                mitre.addLine(to: pt(0.78, 0.90))
                mitre.addLine(to: pt(0.22, 0.90))
                mitre.addLine(to: pt(0.22, 0.82))
                mitre.addLine(to: pt(0.36, 0.68))
                mitre.addQuadCurve(to: pt(0.30, 0.50), control: pt(0.32, 0.60))
                mitre.addQuadCurve(to: pt(0.50, 0.22), control: pt(0.28, 0.33))
                mitre.closeSubpath()
                mainPath.addPath(mitre)

                // Diagonal bishop slash and collar
                accentLines.move(to: pt(0.45, 0.34))
                accentLines.addLine(to: pt(0.60, 0.48))
                accentLines.move(to: pt(0.34, 0.68))
                accentLines.addLine(to: pt(0.66, 0.68))

            case .queen:
                // Five-point coronet crown with pearl tips
                mainPath.move(to: pt(0.22, 0.90))
                mainPath.addLine(to: pt(0.22, 0.80))
                mainPath.addLine(to: pt(0.14, 0.34))
                mainPath.addLine(to: pt(0.31, 0.56))
                mainPath.addLine(to: pt(0.34, 0.25))
                mainPath.addLine(to: pt(0.46, 0.52))
                mainPath.addLine(to: pt(0.50, 0.20))
                mainPath.addLine(to: pt(0.54, 0.52))
                mainPath.addLine(to: pt(0.66, 0.25))
                mainPath.addLine(to: pt(0.69, 0.56))
                mainPath.addLine(to: pt(0.86, 0.34))
                mainPath.addLine(to: pt(0.78, 0.80))
                mainPath.addLine(to: pt(0.78, 0.90))
                mainPath.closeSubpath()

                for pearl in [pt(0.14, 0.30), pt(0.34, 0.21), pt(0.50, 0.16), pt(0.66, 0.21), pt(0.86, 0.30)] {
                    let r = s * 0.045
                    mainPath.addEllipse(in: CGRect(x: pearl.x - r, y: pearl.y - r, width: r * 2, height: r * 2))
                }
                accentLines.move(to: pt(0.26, 0.78))
                accentLines.addLine(to: pt(0.74, 0.78))

            case .king:
                // Royal cross finial + broad twin-lobe crown + base
                mainPath.addRect(CGRect(x: ox + s * 0.46, y: oy + s * 0.10, width: s * 0.08, height: s * 0.22))
                mainPath.addRect(CGRect(x: ox + s * 0.38, y: oy + s * 0.16, width: s * 0.24, height: s * 0.07))

                var crown = Path()
                crown.move(to: pt(0.50, 0.36))
                crown.addQuadCurve(to: pt(0.82, 0.45), control: pt(0.72, 0.28))
                crown.addQuadCurve(to: pt(0.74, 0.76), control: pt(0.85, 0.62))
                crown.addLine(to: pt(0.80, 0.83))
                crown.addLine(to: pt(0.80, 0.90))
                crown.addLine(to: pt(0.20, 0.90))
                crown.addLine(to: pt(0.20, 0.83))
                crown.addLine(to: pt(0.26, 0.76))
                crown.addQuadCurve(to: pt(0.18, 0.45), control: pt(0.15, 0.62))
                crown.addQuadCurve(to: pt(0.50, 0.36), control: pt(0.28, 0.28))
                crown.closeSubpath()
                mainPath.addPath(crown)

                accentLines.move(to: pt(0.50, 0.38))
                accentLines.addLine(to: pt(0.50, 0.74))
                accentLines.move(to: pt(0.26, 0.77))
                accentLines.addLine(to: pt(0.74, 0.77))
            }

            // Soft contact shadow for depth
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: Color.black.opacity(0.28), radius: max(1, s * 0.045), x: 0, y: max(1, s * 0.03)))
                layer.fill(mainPath, with: .color(fill))
            }

            ctx.stroke(
                mainPath,
                with: .color(stroke),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
            )
            ctx.stroke(
                accentLines,
                with: .color(piece.color == .white ? stroke.opacity(0.68) : detail.opacity(0.88)),
                style: StrokeStyle(lineWidth: max(1.0, strokeWidth * 0.78), lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Hint Arrow Overlay

private struct HintArrowOverlay: View {
    let move: ChessMove
    let isFlipped: Bool
    let squareSize: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let start = center(for: move.from)
            let end = center(for: move.to)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length > 1 else { return }

            let ux = dx / length
            let uy = dy / length
            let headLen = min(squareSize * 0.34, length * 0.45)
            let shaftEnd = CGPoint(x: end.x - ux * headLen * 0.75, y: end.y - uy * headLen * 0.75)

            var shaft = Path()
            shaft.move(to: start)
            shaft.addLine(to: shaftEnd)

            ctx.stroke(
                shaft,
                with: .color(Theme.actionPrimary.opacity(0.86)),
                style: StrokeStyle(lineWidth: max(4, squareSize * 0.14), lineCap: .round)
            )

            let perpX = -uy
            let perpY = ux
            let wing = headLen * 0.62
            var head = Path()
            head.move(to: end)
            head.addLine(to: CGPoint(x: end.x - ux * headLen + perpX * wing, y: end.y - uy * headLen + perpY * wing))
            head.addLine(to: CGPoint(x: end.x - ux * headLen - perpX * wing, y: end.y - uy * headLen - perpY * wing))
            head.closeSubpath()

            ctx.fill(head, with: .color(Theme.actionPrimary.opacity(0.92)))
        }
    }

    private func center(for sq: ChessSquare) -> CGPoint {
        let col = isFlipped ? (7 - sq.file) : sq.file
        let row = isFlipped ? sq.rank : (7 - sq.rank)
        return CGPoint(
            x: (CGFloat(col) + 0.5) * squareSize,
            y: (CGFloat(row) + 0.5) * squareSize
        )
    }
}

// MARK: - Animated Sim MicroDuck Companion Canvas

/// Playful animated MicroDuck companion avatar reacting live to `MicroDuckChessMood`,
/// `duckHeadYaw`, and `duckBounce` from `ChessGameSession`.
private struct SimMicroDuckAvatar: View {
    let mood: MicroDuckChessMood
    let headYaw: Double
    let bounce: Double
    let isThinking: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bobPhase = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(stageBackdrop)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.outline.opacity(0.35), lineWidth: 1.5)
                )

            Canvas { ctx, size in
                drawMicroDuck(ctx: &ctx, size: size)
            }
            .offset(y: verticalOffset)
            .rotationEffect(.degrees(reduceMotion ? 0 : headYaw * 0.25))
            .animation(Theme.motion(reduced: reduceMotion), value: headYaw)
            .animation(Theme.motion(reduced: reduceMotion), value: bounce)
            .animation(Theme.motion(reduced: reduceMotion), value: mood)
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    bobPhase = true
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var verticalOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        let baseBob: CGFloat = (isThinking || mood == .checkmateWin || mood == .happyCapture)
            ? (bobPhase ? -3.0 : 1.5)
            : (bobPhase ? -1.0 : 0.5)
        return baseBob - CGFloat(bounce) * 2.5
    }

    private var stageBackdrop: Color {
        switch mood {
        case .checkAlert:
            return Theme.refused.opacity(0.16)
        case .checkmateWin, .happyCapture:
            return Theme.actionYellow.opacity(0.24)
        case .thinking:
            return Theme.actionTeal.opacity(0.22)
        default:
            return Theme.backgroundSecondary
        }
    }

    private func drawMicroDuck(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let ink = Color(red: 0.11, green: 0.15, blue: 0.18)
        let bodyTeal = Color(red: 0.26, green: 0.72, blue: 0.72)
        let headCream = Color(red: 0.99, green: 0.95, blue: 0.84)
        let beakOrange = Color(red: 0.97, green: 0.53, blue: 0.18)
        let lensYellow = Color(red: 0.98, green: 0.82, blue: 0.24)

        // Torso / chassis base
        let torsoRect = CGRect(x: w * 0.22, y: h * 0.62, width: w * 0.56, height: h * 0.30)
        let torso = Path(roundedRect: torsoRect, cornerRadius: w * 0.14)
        ctx.fill(torso, with: .color(bodyTeal))
        ctx.stroke(torso, with: .color(ink), lineWidth: 1.6)

        // Head dome
        let headRect = CGRect(x: w * 0.18, y: h * 0.22, width: w * 0.64, height: h * 0.46)
        let head = Path(roundedRect: headRect, cornerRadius: w * 0.20)
        ctx.fill(head, with: .color(headCream))
        ctx.stroke(head, with: .color(ink), lineWidth: 1.6)

        // Antenna ears
        var leftEar = Path()
        leftEar.move(to: CGPoint(x: w * 0.32, y: h * 0.23))
        leftEar.addLine(to: CGPoint(x: w * 0.26, y: h * 0.11))
        var rightEar = Path()
        rightEar.move(to: CGPoint(x: w * 0.68, y: h * 0.23))
        rightEar.addLine(to: CGPoint(x: w * 0.74, y: h * 0.11))
        ctx.stroke(leftEar, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        ctx.stroke(rightEar, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Camera eyes (react to mood)
        let eyeShift = CGFloat(max(-1.0, min(1.0, headYaw / 30.0))) * (w * 0.04)
        let leftEyeCenter = CGPoint(x: w * 0.38 + eyeShift, y: h * 0.41)
        let rightEyeCenter = CGPoint(x: w * 0.62 + eyeShift, y: h * 0.41)
        let eyeR = w * 0.085

        for center in [leftEyeCenter, rightEyeCenter] {
            let outer = CGRect(x: center.x - eyeR, y: center.y - eyeR, width: eyeR * 2, height: eyeR * 2)
            ctx.fill(Path(ellipseIn: outer), with: .color(ink))
            let irisScale: CGFloat = (mood == .thinking) ? 0.48 : 0.62
            let irisR = eyeR * irisScale
            let iris = CGRect(x: center.x - irisR, y: center.y - irisR, width: irisR * 2, height: irisR * 2)
            let irisColor: Color = (mood == .checkAlert) ? ChessBoardColors.checkCrimson : lensYellow
            ctx.fill(Path(ellipseIn: iris), with: .color(irisColor))
            let dotR = eyeR * 0.22
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - irisR * 0.4, y: center.y - irisR * 0.45, width: dotR * 2, height: dotR * 2)),
                with: .color(.white)
            )
        }

        // Duck bill
        let billRect = CGRect(x: w * 0.34 + eyeShift * 0.6, y: h * 0.51, width: w * 0.32, height: h * 0.14)
        let bill = Path(roundedRect: billRect, cornerRadius: h * 0.065)
        ctx.fill(bill, with: .color(beakOrange))
        ctx.stroke(bill, with: .color(ink), lineWidth: 1.4)

        // Victory crown overlay
        if mood == .checkmateWin {
            var crown = Path()
            crown.move(to: CGPoint(x: w * 0.34, y: h * 0.22))
            crown.addLine(to: CGPoint(x: w * 0.36, y: h * 0.09))
            crown.addLine(to: CGPoint(x: w * 0.44, y: h * 0.16))
            crown.addLine(to: CGPoint(x: w * 0.50, y: h * 0.07))
            crown.addLine(to: CGPoint(x: w * 0.56, y: h * 0.16))
            crown.addLine(to: CGPoint(x: w * 0.64, y: h * 0.09))
            crown.addLine(to: CGPoint(x: w * 0.66, y: h * 0.22))
            crown.closeSubpath()
            ctx.fill(crown, with: .color(lensYellow))
            ctx.stroke(crown, with: .color(ink), lineWidth: 1.2)
        }
    }
}

// MARK: - New Game & Match Setup Sheet

private struct ChessSetupSheet: View {
    @ObservedObject var session: ChessGameSession
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMode: ChessPlayMode
    @State private var selectedDifficulty: ChessAIDifficulty
    @State private var selectedHumanColor: ChessColor
    @State private var selectedClock: ChessTimeControl
    @State private var autoFlip: Bool
    @State private var tabletop: Bool
    @State private var whiteName: String
    @State private var blackName: String

    init(session: ChessGameSession) {
        self.session = session
        _selectedMode = State(initialValue: session.playMode)
        _selectedDifficulty = State(initialValue: session.difficulty)
        _selectedHumanColor = State(initialValue: session.humanColor)
        _selectedClock = State(initialValue: session.timeControl)
        _autoFlip = State(initialValue: session.autoFlipBoard)
        _tabletop = State(initialValue: session.tabletopFaceToFace)
        _whiteName = State(initialValue: session.whitePlayerName)
        _blackName = State(initialValue: session.blackPlayerName)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ChessPlayMode.allCases) { mode in
                        Button {
                            selectedMode = mode
                        } label: {
                            HStack(spacing: Theme.spacing(.snug)) {
                                Image(systemName: mode.symbol)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.actionInk)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.fullTitle)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(mode.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                if selectedMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.actionInk)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    SectionHeading(text: "Play Mode")
                }
                .listRowBackground(Theme.surfacePrimary)

                if selectedMode.usesAI {
                    Section {
                        Picker("Your Side", selection: $selectedHumanColor) {
                            Text("Play White").tag(ChessColor.white)
                            Text("Play Black").tag(ChessColor.black)
                        }
                        .pickerStyle(.segmented)

                        if selectedMode == .vsEngine {
                            Picker("Engine Strength", selection: $selectedDifficulty) {
                                ForEach(ChessAIDifficulty.allCases) { level in
                                    Text(level.label).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                        } else if selectedMode == .vsLocalAI {
                            Text(session.localAIReadinessDescription)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if selectedMode == .vsCloudAI {
                            Text(session.cloudAIReadinessDescription)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        SectionHeading(text: "Opponent Options")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                } else {
                    Section {
                        Toggle("Auto-Flip Board Each Turn", isOn: $autoFlip)
                            .tint(Theme.actionPrimary)
                            .onChange(of: autoFlip) { _, on in
                                if on { tabletop = false }
                            }
                        Toggle("Tabletop Mode (Rotate Black 180 deg)", isOn: $tabletop)
                            .tint(Theme.actionPrimary)
                            .onChange(of: tabletop) { _, on in
                                if on { autoFlip = false }
                            }
                        TextField("White Player Name", text: $whiteName)
                        TextField("Black Player Name", text: $blackName)
                    } header: {
                        SectionHeading(text: "2-Player Pass & Play")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                Section {
                    Picker("Chess Clock", selection: $selectedClock) {
                        ForEach(ChessTimeControl.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    SectionHeading(text: "Time Control")
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    Button {
                        session.whitePlayerName = whiteName
                        session.blackPlayerName = blackName
                        session.autoFlipBoard = autoFlip
                        session.tabletopFaceToFace = tabletop
                        session.startNewGame(
                            mode: selectedMode,
                            difficulty: selectedDifficulty,
                            humanColor: selectedHumanColor,
                            timeControl: selectedClock
                        )
                        dismiss()
                    } label: {
                        Text("Start New Match")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
            .navigationTitle("New Chess Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DuckChessView()
    }
}
