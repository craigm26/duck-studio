import XCTest
@testable import StudioKit

final class ChessEngineTests: XCTestCase {

    // MARK: - Initial Position & Perft

    func testInitialPositionHasTwentyLegalMoves() {
        let board = ChessBoardState.standardInitial
        XCTAssertEqual(board.fen, ChessBoardState.standardInitialFEN)
        XCTAssertEqual(board.sideToMove, .white)
        XCTAssertFalse(board.isInCheck(.white))
        XCTAssertFalse(board.isInCheck(.black))
        XCTAssertEqual(board.materialBalance, 0)
        XCTAssertEqual(board.status(), .active)
        XCTAssertEqual(board.legalMoves().count, 20)
    }

    func testPerftStandardPosition() {
        let board = ChessBoardState.standardInitial
        XCTAssertEqual(board.perft(depth: 1), 20)
        XCTAssertEqual(board.perft(depth: 2), 400)
        XCTAssertEqual(board.perft(depth: 3), 8_902)
    }

    func testPerftKiwipetePosition() throws {
        // Famous Kiwipete position exercising castling, captures, promotions, en passant, and pins.
        let fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        let board = try XCTUnwrap(ChessBoardState(fen: fen))
        XCTAssertEqual(board.perft(depth: 1), 48)
        XCTAssertEqual(board.perft(depth: 2), 2_039)
    }

    // MARK: - Castling Rules

    func testCastlingLegalBothSidesWhenClearAndSafe() throws {
        let board = try XCTUnwrap(ChessBoardState(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
        let kingMoves = board.legalMoves(from: try XCTUnwrap(ChessSquare(algebraic: "e1")))
        let ucis = Set(kingMoves.map(\.uci))
        XCTAssertTrue(ucis.contains("e1g1"))
        XCTAssertTrue(ucis.contains("e1c1"))

        let afterKS = try XCTUnwrap(board.applying(try XCTUnwrap(ChessMove(uci: "e1g1"))))
        XCTAssertEqual(afterKS[try XCTUnwrap(ChessSquare(algebraic: "g1"))], ChessPiece(color: .white, kind: .king))
        XCTAssertEqual(afterKS[try XCTUnwrap(ChessSquare(algebraic: "f1"))], ChessPiece(color: .white, kind: .rook))
        XCTAssertNil(afterKS[try XCTUnwrap(ChessSquare(algebraic: "h1"))])
        XCTAssertFalse(afterKS.castlingRights.whiteKingside)
        XCTAssertFalse(afterKS.castlingRights.whiteQueenside)
        XCTAssertTrue(afterKS.castlingRights.blackKingside)
        XCTAssertTrue(afterKS.castlingRights.blackQueenside)
    }

    func testCastlingBlockedInCheckAndThroughCheck() throws {
        // King in check from black rook on e8 -> neither castling allowed.
        let inCheck = try XCTUnwrap(ChessBoardState(fen: "4r2k/8/8/8/8/8/8/R3K2R w KQ - 0 1"))
        let inCheckMoves = Set(inCheck.legalMoves(from: try XCTUnwrap(ChessSquare(algebraic: "e1"))).map(\.uci))
        XCTAssertFalse(inCheckMoves.contains("e1g1"))
        XCTAssertFalse(inCheckMoves.contains("e1c1"))

        // Rook on f8 attacks f1 -> kingside castling forbidden, queenside still allowed.
        let throughCheck = try XCTUnwrap(ChessBoardState(fen: "5r1k/8/8/8/8/8/8/R3K2R w KQ - 0 1"))
        let throughMoves = Set(throughCheck.legalMoves(from: try XCTUnwrap(ChessSquare(algebraic: "e1"))).map(\.uci))
        XCTAssertFalse(throughMoves.contains("e1g1"))
        XCTAssertTrue(throughMoves.contains("e1c1"))

        // Rook on b8 attacks b1 (not passed through by king) -> queenside castling IS legal!
        let b1Attacked = try XCTUnwrap(ChessBoardState(fen: "1r5k/8/8/8/8/8/8/R3K2R w KQ - 0 1"))
        let b1Moves = Set(b1Attacked.legalMoves(from: try XCTUnwrap(ChessSquare(algebraic: "e1"))).map(\.uci))
        XCTAssertTrue(b1Moves.contains("e1c1"))

        // Knight on b1 blocks queenside castling.
        let blocked = try XCTUnwrap(ChessBoardState(fen: "7k/8/8/8/8/8/8/RN2K2R w KQ - 0 1"))
        let blockedMoves = Set(blocked.legalMoves(from: try XCTUnwrap(ChessSquare(algebraic: "e1"))).map(\.uci))
        XCTAssertFalse(blockedMoves.contains("e1c1"))
        XCTAssertTrue(blockedMoves.contains("e1g1"))
    }

    func testCapturingUnmovedRookRevokesCastlingRight() throws {
        let board = try XCTUnwrap(ChessBoardState(fen: "r3k2r/8/8/8/8/8/1B6/4K3 w kq - 0 1"))
        let captureRook = try XCTUnwrap(ChessMove(uci: "b2h8"))
        let after = try XCTUnwrap(board.applying(captureRook))
        XCTAssertFalse(after.castlingRights.blackKingside)
        XCTAssertTrue(after.castlingRights.blackQueenside)
    }

    // MARK: - En Passant & Pinned En Passant

    func testEnPassantCaptureRemovesEnemyPawn() throws {
        var game = ChessGame()
        XCTAssertNotNil(game.makeMove(matching: "e4"))
        XCTAssertNotNil(game.makeMove(matching: "a6"))
        XCTAssertNotNil(game.makeMove(matching: "e5"))
        XCTAssertNotNil(game.makeMove(matching: "d5"))
        XCTAssertEqual(game.state.enPassantTarget, ChessSquare(algebraic: "d6"))

        let epRecord = try XCTUnwrap(game.makeMove(matching: "exd6"))
        XCTAssertEqual(epRecord.move.uci, "e5d6")
        XCTAssertEqual(epRecord.captured, ChessPiece(color: .black, kind: .pawn))
        XCTAssertNil(game.state[try XCTUnwrap(ChessSquare(algebraic: "d5"))])
        XCTAssertEqual(game.state[try XCTUnwrap(ChessSquare(algebraic: "d6"))], ChessPiece(color: .white, kind: .pawn))
    }

    func testEnPassantHorizontalPinEdgeCaseIsForbidden() throws {
        // White King on a5, White Pawn on b5, Black Pawn on c5 (EP target c6), Black Rook on h5.
        // Capturing bxc6 would remove BOTH rank-5 pawns and expose the White King to the rook on h5!
        let pinned = try XCTUnwrap(ChessBoardState(fen: "8/8/8/KPp4r/8/8/8/7k w - c6 0 1"))
        let pawnMoves = pinned.legalMoves(from: try XCTUnwrap(ChessSquare(algebraic: "b5")))
        XCTAssertFalse(pawnMoves.map(\.uci).contains("b5c6"))
        XCTAssertTrue(pawnMoves.map(\.uci).contains("b5b6"))

        // Without the rook on h5, b5c6 IS legal.
        let unpinned = try XCTUnwrap(ChessBoardState(fen: "8/8/8/KPp5/8/8/8/7k w - c6 0 1"))
        let unpinnedMoves = unpinned.legalMoves(from: try XCTUnwrap(ChessSquare(algebraic: "b5")))
        XCTAssertTrue(unpinnedMoves.map(\.uci).contains("b5c6"))
    }

    // MARK: - Pawn Promotion

    func testPawnPromotionGeneratesAllFourChoices() throws {
        let board = try XCTUnwrap(ChessBoardState(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"))
        let a7 = try XCTUnwrap(ChessSquare(algebraic: "a7"))
        let a8 = try XCTUnwrap(ChessSquare(algebraic: "a8"))
        XCTAssertTrue(board.isPromotionMove(from: a7, to: a8))

        let moves = board.legalMoves(from: a7)
        XCTAssertEqual(moves.count, 4)
        XCTAssertEqual(Set(moves.compactMap(\.promotion)), Set(ChessPieceKind.promotionKinds))

        let underpromo = try XCTUnwrap(ChessMove(uci: "a7a8n"))
        let after = try XCTUnwrap(board.applying(underpromo))
        XCTAssertEqual(after[a8], ChessPiece(color: .white, kind: .knight))
    }

    // MARK: - Checkmate, Stalemate & Draw Rules

    func testFoolsMate() throws {
        var game = ChessGame()
        XCTAssertNotNil(game.makeMove(matching: "f3"))
        XCTAssertNotNil(game.makeMove(matching: "e5"))
        XCTAssertNotNil(game.makeMove(matching: "g4"))
        let mateRecord = try XCTUnwrap(game.makeMove(matching: "Qh4"))
        XCTAssertEqual(mateRecord.san, "Qh4#")
        XCTAssertEqual(game.status, .checkmate(winner: .black))
        XCTAssertTrue(game.isGameOver)
        XCTAssertTrue(game.legalMoves().isEmpty)
    }

    func testScholarsMate() throws {
        var game = ChessGame()
        for san in ["e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6"] {
            XCTAssertNotNil(game.makeMove(matching: san), "Failed to play \(san)")
        }
        let mateRecord = try XCTUnwrap(game.makeMove(matching: "Qxf7"))
        XCTAssertEqual(mateRecord.san, "Qxf7#")
        XCTAssertEqual(game.status, .checkmate(winner: .white))
        XCTAssertEqual(game.status.winner, .white)
    }

    func testStalemateDetection() throws {
        let board = try XCTUnwrap(ChessBoardState(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
        XCTAssertEqual(board.legalMoves().count, 0)
        XCTAssertFalse(board.isInCheck(.black))
        XCTAssertEqual(board.status(), .stalemate)
        XCTAssertTrue(board.status().isDraw)
    }

    func testFiftyMoveDrawRule() throws {
        var game = try XCTUnwrap(ChessGame(validatingFEN: "4k3/8/8/8/8/8/4P3/4K2R w K - 99 60"))
        XCTAssertEqual(game.status, .active)

        // Quiet rook move hits halfmoveClock == 100 -> automatic draw.
        XCTAssertNotNil(game.makeMove(matching: "Rh2"))
        XCTAssertEqual(game.state.halfmoveClock, 100)
        XCTAssertEqual(game.status, .drawFiftyMove)

        // Undoing and pushing a pawn resets the 50-move clock.
        XCTAssertNotNil(game.undoLastPly())
        XCTAssertNotNil(game.makeMove(matching: "e3"))
        XCTAssertEqual(game.state.halfmoveClock, 0)
        XCTAssertEqual(game.status, .active)
    }

    func testThreefoldRepetitionDraw() {
        var game = ChessGame()
        let sequence = ["Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1", "Ng8"]
        for (idx, san) in sequence.enumerated() {
            XCTAssertNotNil(game.makeMove(matching: san))
            if idx < sequence.count - 1 {
                XCTAssertEqual(game.status, .active, "Unexpected early status at ply \(idx + 1)")
            }
        }
        XCTAssertEqual(game.status, .drawThreefoldRepetition)
    }

    func testInsufficientMaterialDetection() throws {
        let drawFENs = [
            "4k3/8/8/8/8/8/8/4K3 w - - 0 1",            // K vs K
            "4k3/8/8/8/8/8/8/4KB2 w - - 0 1",           // K+B vs K
            "4k3/8/8/8/8/8/8/4KN2 w - - 0 1",           // K+N vs K
            "4k1b1/8/8/8/8/8/8/4KB2 w - - 0 1",         // K+B (light f1) vs K+B (light g8: 6+7=13 odd, f1: 5+0=5 odd)
        ]
        for fen in drawFENs {
            let board = try XCTUnwrap(ChessBoardState(fen: fen))
            XCTAssertTrue(board.isInsufficientMaterial, "Expected insufficient material for \(fen)")
            XCTAssertEqual(board.status(), .drawInsufficientMaterial)
        }

        // Opposite-color bishops (c1 dark, g8 light) -> NOT insufficient material.
        let oppBishops = try XCTUnwrap(ChessBoardState(fen: "4k1b1/8/8/8/8/8/8/2B1K3 w - - 0 1"))
        XCTAssertFalse(oppBishops.isInsufficientMaterial)
        XCTAssertEqual(oppBishops.status(), .active)

        // K+R vs K -> sufficient material.
        let rookEndgame = try XCTUnwrap(ChessBoardState(fen: "4k3/8/8/8/8/8/8/4KR2 w - - 0 1"))
        XCTAssertFalse(rookEndgame.isInsufficientMaterial)
    }

    // MARK: - FEN Round-Trip

    func testFENRoundTripAndValidation() throws {
        let validFENs = [
            ChessBoardState.standardInitialFEN,
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
            "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2",
            "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 12 45",
        ]
        for fen in validFENs {
            let parsed = try XCTUnwrap(ChessBoardState(fen: fen), "Failed to parse \(fen)")
            XCTAssertEqual(parsed.fen, fen)
        }

        XCTAssertNil(ChessBoardState(fen: "invalid fen"))
        XCTAssertNil(ChessBoardState(fen: "8/8/8/8/8/8/8/8 w - - 0 1")) // Missing kings
        XCTAssertNil(ChessBoardState(fen: "4k3/8/8/8/8/8/8/4K3 x - - 0 1")) // Bad side
        XCTAssertNil(ChessBoardState(fen: "4k3/8/8/8/8/8/8/4K3 w KQkq e4 0 1")) // Bad EP rank
    }

    // MARK: - SAN Formatting & Parsing

    func testSANFormattingDisambiguationAndMatching() throws {
        // Two knights on b1 and f3 can both reach d2 -> "Nbd2" vs "Nfd2".
        let knightBoard = try XCTUnwrap(ChessBoardState(fen: "4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1"))
        let nbd2 = try XCTUnwrap(ChessMove(uci: "b1d2"))
        let nfd2 = try XCTUnwrap(ChessMove(uci: "f3d2"))
        XCTAssertEqual(knightBoard.san(for: nbd2), "Nbd2")
        XCTAssertEqual(knightBoard.san(for: nfd2), "Nfd2")
        XCTAssertEqual(knightBoard.move(matching: "Nbd2"), nbd2)
        XCTAssertEqual(knightBoard.move(matching: "b1d2"), nbd2)

        // Two rooks on a1 and a8 can both reach a4 -> rank disambiguation "R1a4" vs "R8a4".
        let rookBoard = try XCTUnwrap(ChessBoardState(fen: "R7/4k3/8/8/8/8/8/R3K3 w - - 0 1"))
        let r1a4 = try XCTUnwrap(ChessMove(uci: "a1a4"))
        let r8a4 = try XCTUnwrap(ChessMove(uci: "a8a4"))
        XCTAssertEqual(rookBoard.san(for: r1a4), "R1a4")
        XCTAssertEqual(rookBoard.san(for: r8a4), "R8a4")
        XCTAssertEqual(rookBoard.move(matching: "R1a4"), r1a4)

        // Promotion with checkmate: e7 -> e8=Q#
        let promoMateBoard = try XCTUnwrap(ChessBoardState(fen: "6k1/4Pppp/8/8/8/8/8/4K3 w - - 0 1"))
        let promoMove = try XCTUnwrap(ChessMove(uci: "e7e8q"))
        XCTAssertEqual(promoMateBoard.san(for: promoMove), "e8=Q#")
        XCTAssertEqual(promoMateBoard.move(matching: "e8=Q#"), promoMove)
        XCTAssertEqual(promoMateBoard.move(matching: "e8=Q"), promoMove)
        XCTAssertEqual(promoMateBoard.move(matching: "e7e8q"), promoMove)

        // Castling matching with O-O and 0-0
        let castleBoard = try XCTUnwrap(ChessBoardState(fen: "4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1"))
        XCTAssertEqual(castleBoard.move(matching: "O-O"), ChessMove(uci: "e1g1"))
        XCTAssertEqual(castleBoard.move(matching: "0-0-0"), ChessMove(uci: "e1c1"))
    }

    // MARK: - ChessGame Undo, Captures, Resign & Draw

    func testChessGameUndoCapturesAndResign() throws {
        var game = ChessGame()
        XCTAssertFalse(game.canUndo)

        XCTAssertNotNil(game.makeMove(matching: "e4"))
        XCTAssertNotNil(game.makeMove(matching: "d5"))
        let capture = try XCTUnwrap(game.makeMove(matching: "exd5"))
        XCTAssertEqual(capture.san, "exd5")
        XCTAssertEqual(game.capturedByWhite.count, 1)
        XCTAssertEqual(game.capturedByWhite[0].kind, .pawn)
        XCTAssertEqual(game.materialBalance, 1)
        XCTAssertTrue(game.canUndo)

        // Undo capture restores material balance and exact FEN.
        let undone = try XCTUnwrap(game.undoLastPly())
        XCTAssertEqual(undone.san, "exd5")
        XCTAssertEqual(game.capturedByWhite.count, 0)
        XCTAssertEqual(game.materialBalance, 0)
        XCTAssertEqual(game.history.count, 2)

        // Resign ends game, reset restores initial state.
        game.resign(color: .white)
        XCTAssertEqual(game.status, .resigned(winner: .black))
        XCTAssertTrue(game.isGameOver)
        XCTAssertNil(game.makeMove(matching: "Nf3"))

        game.reset()
        XCTAssertEqual(game.state, .standardInitial)
        XCTAssertEqual(game.status, .active)
        XCTAssertTrue(game.history.isEmpty)

        // Agree draw
        game.agreeDraw()
        XCTAssertEqual(game.status, .drawAgreement)
        XCTAssertTrue(game.status.isDraw)
    }

    // MARK: - ChessSearchAI

    func testSearchAIFindsForcedMateInOne() throws {
        // White to move: Ra8# is forced mate in 1.
        let emDash = try XCTUnwrap(Unicode.Scalar(UInt32(0x2014)))
        let mateInOne = try XCTUnwrap(ChessBoardState(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"))
        for difficulty in ChessAIDifficulty.allCases {
            let result = try XCTUnwrap(ChessSearchAI.bestMove(for: mateInOne, difficulty: difficulty, deterministicSeed: 42))
            XCTAssertEqual(result.move.uci, "a1a8", "Difficulty \(difficulty) missed forced mate-in-1")
            XCTAssertEqual(result.san, "Ra8#")
            XCTAssertFalse(result.commentary.isEmpty)
            XCTAssertFalse(result.commentary.unicodeScalars.contains(emDash))
        }
    }

    func testSearchAICapturesFreeQueen() throws {
        // Black queen hanging on d5; White rook on d1 should capture Rxd5.
        let emDash = try XCTUnwrap(Unicode.Scalar(UInt32(0x2014)))
        let freeQueen = try XCTUnwrap(ChessBoardState(fen: "4k3/ppp2ppp/8/3q4/8/8/PPP2PPP/3RK3 w - - 0 1"))
        let result = try XCTUnwrap(ChessSearchAI.bestMove(for: freeQueen, difficulty: .strong, deterministicSeed: 7))
        XCTAssertEqual(result.move.uci, "d1d5")
        XCTAssertGreaterThanOrEqual(result.scoreCentipawns, 450)
        XCTAssertGreaterThan(result.nodesSearched, 0)
        XCTAssertFalse(result.commentary.unicodeScalars.contains(emDash))
    }

    func testSearchAIOpeningResponseIsLegalAndFast() throws {
        let start = Date()
        let result = try XCTUnwrap(ChessSearchAI.bestMove(for: .standardInitial, difficulty: .club, deterministicSeed: 1))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(ChessBoardState.standardInitial.isLegalMove(result.move))
        XCTAssertLessThan(elapsed, 2.0)
    }

    // MARK: - ChessLLMPrompt

    func testLLMPromptIncludesFENAndLegalMovesWithoutEmDash() throws {
        let game = ChessGame()
        let instructions = ChessLLMPrompt.instructions(for: .black)
        let prompt = ChessLLMPrompt.userPrompt(for: game)

        XCTAssertTrue(prompt.contains(ChessBoardState.standardInitialFEN))
        XCTAssertTrue(prompt.contains("e2e4 (e4)"))
        XCTAssertTrue(prompt.contains("g1f3 (Nf3)"))

        let emDash = try XCTUnwrap(Unicode.Scalar(UInt32(0x2014)))
        XCTAssertFalse(instructions.unicodeScalars.contains(emDash))
        XCTAssertFalse(prompt.unicodeScalars.contains(emDash))
    }

    func testLLMResponseParsingFormatsAndEmDashSanitization() throws {
        let state = ChessBoardState.standardInitial
        let emDash = String(try XCTUnwrap(Unicode.Scalar(UInt32(0x2014))))

        // 1. Clean JSON with em-dash in commentary -> stripped cleanly.
        let jsonRaw = """
        {"move": "e2e4", "comment": "Claiming the center\(emDash)classic opening!"}
        """
        let jsonDecision = try XCTUnwrap(ChessLLMPrompt.parseResponse(jsonRaw, in: state))
        XCTAssertEqual(jsonDecision.move.uci, "e2e4")
        XCTAssertEqual(jsonDecision.san, "e4")
        XCTAssertFalse(jsonDecision.commentary.contains(emDash))
        XCTAssertEqual(jsonDecision.commentary, "Claiming the center, classic opening!")

        // 2. Reasoning block + markdown fenced JSON with SAN move.
        let noisyJSON = """
        <think>Let's consider d2d4 or g1f3. Actually g1f3 is great.</think>
        ```json
        {"move": "Nf3", "comment": "Developing the knight early."}
        ```
        """
        let noisyDecision = try XCTUnwrap(ChessLLMPrompt.parseResponse(noisyJSON, in: state))
        XCTAssertEqual(noisyDecision.move.uci, "g1f3")
        XCTAssertEqual(noisyDecision.san, "Nf3")

        // 3. MOVE: / COMMENT: line format.
        let labeledRaw = """
        MOVE: d2d4
        COMMENT: Opening the queen pawn file.
        """
        let labeledDecision = try XCTUnwrap(ChessLLMPrompt.parseResponse(labeledRaw, in: state))
        XCTAssertEqual(labeledDecision.move.uci, "d2d4")
        XCTAssertEqual(labeledDecision.san, "d4")
        XCTAssertEqual(labeledDecision.commentary, "Opening the queen pawn file.")

        // 4. Plain prose containing a legal SAN token.
        let proseRaw = "I like playing Nc3 here to control d5."
        let proseDecision = try XCTUnwrap(ChessLLMPrompt.parseResponse(proseRaw, in: state))
        XCTAssertEqual(proseDecision.move.uci, "b1c3")
        XCTAssertEqual(proseDecision.san, "Nc3")

        // 5. Illegal move returns nil.
        let illegalRaw = #"{"move": "e2e5", "comment": "Teleporting!"}"#
        XCTAssertNil(ChessLLMPrompt.parseResponse(illegalRaw, in: state))
    }
}
