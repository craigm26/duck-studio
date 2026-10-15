import SwiftUI
import StudioKit

/// What a board shows: its size, where the duck starts and faces, the goal, the walls and the gates.
/// The same for a challenge being played and one being drawn.
struct DuckPackBoardContents: Equatable {
    let columns: Int, rows: Int
    let start: DuckPacks.Place
    let goal: DuckPacks.Square
    let walls: Set<DuckPacks.Wall>
    let gates: [DuckPacks.Gate]

    init(_ ch: DuckPacks.Challenge) {
        columns = ch.columns; rows = ch.rows; start = ch.start; goal = ch.goal; walls = ch.walls; gates = ch.gates
    }

    init(_ draft: DuckPacks.Draft) {
        columns = draft.columns; rows = draft.rows; start = draft.start; goal = draft.goal
        walls = draft.walls; gates = draft.gates
    }
}

/// What the board does with a tap while a challenge is drawn, and what VoiceOver says and offers for
/// each square. The tap carries how far across and down the square it landed, for walls.
struct DuckPackBoardEditing {
    struct Action { let name: String; let perform: () -> Void }
    let tap: (DuckPacks.Square, Double, Double) -> Void
    let label: (DuckPacks.Square) -> String
    let actions: (DuckPacks.Square) -> [Action]
}

/// A challenge's board, drawn by the board rule: a grid of squares, the start and the way it faces,
/// the goal, walls on the edges between squares, and gates with the axis they are walked through.
///
/// THE BOARD, NOT THE FLOOR. One Walk card is one square here because that is the rule the paper
/// game and every check use. Nothing on this view says where a real duck would stop.
///
/// DRAWN IN A CANVAS, THE DUCK ON TOP OF IT. The board is still while a row plays, so it is one
/// Canvas; the duck moves, so it is a view laid over it whose place animates, on the app's spring,
/// or as a cross-fade from square to square under Reduce Motion.
///
/// VOICEOVER HEARS THE BOARD IN SENTENCES (`DuckPacks.Words.board`), and while drawing, each square
/// is an element of its own with what is on it and actions for the tool's taps.
struct DuckPackBoardView: View {
    let contents: DuckPackBoardContents
    /// Where the duck is now; the start when nothing is playing.
    var duck: DuckPacks.Place? = nil
    /// The places played so far, start first, drawn as a trail.
    var trail: [DuckPacks.Place] = []
    /// Gates passed so far, by their place in the list.
    var passed: Set<Int> = []
    /// Changes when the duck moves, so Reduce Motion can cross-fade it.
    var step = 0
    /// What VoiceOver hears for the whole board when it is not being drawn.
    var label: String = ""
    var editing: DuckPackBoardEditing? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var aspect: CGFloat { CGFloat(contents.columns) / CGFloat(contents.rows) }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width / CGFloat(contents.columns), geo.size.height / CGFloat(contents.rows))
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in draw(&context, side: side) }
                    .frame(width: side * CGFloat(contents.columns), height: side * CGFloat(contents.rows))
                    .accessibilityHidden(true)
                duckMarker(side: side)
                if let editing { tapLayer(editing, side: side) }
            }
            .frame(width: side * CGFloat(contents.columns), height: side * CGFloat(contents.rows))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 420)
        .modifier(BoardAccessibility(editing: editing != nil, label: label,
                                     value: DuckPacks.Words.duckAt(duck ?? contents.start)))
    }

    // MARK: - drawing

    private func rect(_ s: DuckPacks.Square, _ side: CGFloat) -> CGRect {
        CGRect(x: CGFloat(s.x) * side, y: CGFloat(s.y) * side, width: side, height: side)
    }

    private func centre(_ s: DuckPacks.Square, _ side: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(s.x) + 0.5) * side, y: (CGFloat(s.y) + 0.5) * side)
    }

    private func draw(_ context: inout GraphicsContext, side: CGFloat) {
        let board = CGRect(x: 0, y: 0, width: side * CGFloat(contents.columns), height: side * CGFloat(contents.rows))
        context.fill(Path(board), with: .color(Theme.surfaceElevated))

        // The goal, filled, with a flag on it.
        let goal = rect(contents.goal, side).insetBy(dx: side * 0.06, dy: side * 0.06)
        context.fill(Path(roundedRect: goal, cornerRadius: side * 0.1), with: .color(Theme.success.opacity(0.28)))
        var flag = context.resolve(Image(systemName: "flag.fill"))
        flag.shading = .color(Theme.success)
        context.draw(flag, in: goal.insetBy(dx: side * 0.28, dy: side * 0.28))

        // The start, outlined, so it can still be seen once the duck has walked off it.
        let start = rect(contents.start.at, side).insetBy(dx: side * 0.08, dy: side * 0.08)
        context.stroke(Path(roundedRect: start, cornerRadius: side * 0.1), with: .color(Theme.actionSecondary),
                       style: StrokeStyle(lineWidth: 2, dash: [5, 4]))

        // The grid.
        var grid = Path()
        for x in 1..<max(contents.columns, 1) {
            grid.move(to: CGPoint(x: CGFloat(x) * side, y: 0)); grid.addLine(to: CGPoint(x: CGFloat(x) * side, y: board.maxY))
        }
        for y in 1..<max(contents.rows, 1) {
            grid.move(to: CGPoint(x: 0, y: CGFloat(y) * side)); grid.addLine(to: CGPoint(x: board.maxX, y: CGFloat(y) * side))
        }
        context.stroke(grid, with: .color(Theme.separator), lineWidth: 1)

        // The trail of a row played so far.
        if trail.count > 1 {
            var path = Path()
            path.move(to: centre(trail[0].at, side))
            for p in trail.dropFirst() { path.addLine(to: centre(p.at, side)) }
            context.stroke(path, with: .color(Theme.actionSecondary.opacity(0.55)),
                           style: StrokeStyle(lineWidth: max(side * 0.06, 2), lineCap: .round, lineJoin: .round))
        }

        // Gates: two rails along the way the duck walks through, and an arrow both ways between them.
        for (k, gate) in contents.gates.enumerated() {
            let r = rect(gate.at, side), c = centre(gate.at, side)
            let colour = passed.contains(k) ? Theme.success : Theme.sensorActive
            var rails = Path(), arrow = Path()
            let along = side * 0.36, across = side * 0.3, head = side * 0.1
            if gate.axis == .ns {
                for dx in [-across, across] {
                    rails.move(to: CGPoint(x: c.x + dx, y: r.minY + side * 0.12)); rails.addLine(to: CGPoint(x: c.x + dx, y: r.maxY - side * 0.12))
                }
                arrow.move(to: CGPoint(x: c.x, y: c.y - along)); arrow.addLine(to: CGPoint(x: c.x, y: c.y + along))
                for sign in [-1.0, 1.0] {
                    let tip = CGPoint(x: c.x, y: c.y + along * sign)
                    arrow.move(to: CGPoint(x: tip.x - head, y: tip.y - head * sign)); arrow.addLine(to: tip)
                    arrow.addLine(to: CGPoint(x: tip.x + head, y: tip.y - head * sign))
                }
            } else {
                for dy in [-across, across] {
                    rails.move(to: CGPoint(x: r.minX + side * 0.12, y: c.y + dy)); rails.addLine(to: CGPoint(x: r.maxX - side * 0.12, y: c.y + dy))
                }
                arrow.move(to: CGPoint(x: c.x - along, y: c.y)); arrow.addLine(to: CGPoint(x: c.x + along, y: c.y))
                for sign in [-1.0, 1.0] {
                    let tip = CGPoint(x: c.x + along * sign, y: c.y)
                    arrow.move(to: CGPoint(x: tip.x - head * sign, y: tip.y - head)); arrow.addLine(to: tip)
                    arrow.addLine(to: CGPoint(x: tip.x - head * sign, y: tip.y + head))
                }
            }
            context.stroke(rails, with: .color(colour), style: StrokeStyle(lineWidth: max(side * 0.07, 3), lineCap: .round))
            context.stroke(arrow, with: .color(colour), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }

        // Walls on the edge two squares share, and the board's own edge, which is a wall too.
        var walls = Path()
        for wall in contents.walls {
            let pair = Array(wall.squares)
            guard pair.count == 2 else { continue }
            let a = pair[0], b = pair[1]
            if a.y == b.y {
                let x = CGFloat(max(a.x, b.x)) * side, y = CGFloat(a.y) * side
                walls.move(to: CGPoint(x: x, y: y)); walls.addLine(to: CGPoint(x: x, y: y + side))
            } else {
                let y = CGFloat(max(a.y, b.y)) * side, x = CGFloat(a.x) * side
                walls.move(to: CGPoint(x: x, y: y)); walls.addLine(to: CGPoint(x: x + side, y: y))
            }
        }
        context.stroke(walls, with: .color(Theme.textPrimary), style: StrokeStyle(lineWidth: max(side * 0.08, 4), lineCap: .round))
        context.stroke(Path(board), with: .color(Theme.textPrimary), lineWidth: 3)
    }

    // MARK: - the duck

    private func duckMarker(side: CGFloat) -> some View {
        let place = duck ?? contents.start
        let degrees: Double = {
            switch place.facing {
            case .north: return 0
            case .east: return 90
            case .south: return 180
            case .west: return 270
            }
        }()
        return Image(systemName: "location.north.circle.fill")
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.palette)
            .foregroundStyle(Theme.surfacePrimary, Theme.actionPrimary)
            .rotationEffect(.degrees(degrees))
            .frame(width: side * 0.62, height: side * 0.62)
            .position(centre(place.at, side))
            // UNDER REDUCE MOTION THE DUCK DOES NOT SLIDE. A new identity each step makes the move a
            // cross-fade, which is what the app gives Reduce Motion everywhere (`Theme.reducedMotion`).
            .id(reduceMotion ? step : 0)
            .transition(.opacity)
            .animation(Theme.motion(reduced: reduceMotion), value: step)
            .accessibilityHidden(true)
    }

    // MARK: - drawing a challenge

    private func tapLayer(_ editing: DuckPackBoardEditing, side: CGFloat) -> some View {
        Color.clear
            .frame(width: side * CGFloat(contents.columns), height: side * CGFloat(contents.rows))
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                let x = Int(point.x / side), y = Int(point.y / side)
                guard (0..<contents.columns).contains(x), (0..<contents.rows).contains(y) else { return }
                editing.tap(DuckPacks.Square(x, y), Double(point.x / side) - Double(x), Double(point.y / side) - Double(y))
            }
            .accessibilityElement(children: .contain)
            .accessibilityChildren {
                VStack(spacing: 0) {
                    ForEach(0..<contents.rows, id: \.self) { y in
                        HStack(spacing: 0) {
                            ForEach(0..<contents.columns, id: \.self) { x in
                                squareElement(DuckPacks.Square(x, y), editing, side: side)
                            }
                        }
                    }
                }
            }
    }

    private func squareElement(_ s: DuckPacks.Square, _ editing: DuckPackBoardEditing, side: CGFloat) -> some View {
        let actions = editing.actions(s)
        return Rectangle()
            .fill(Color.clear)
            .frame(width: side, height: side)
            .accessibilityElement()
            .accessibilityLabel(Text(editing.label(s)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { actions.first?.perform() }
            .accessibilityActions {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.name, action: action.perform)
                }
            }
    }
}

/// The board as one VoiceOver element, said in sentences, while it is played; while it is drawn,
/// its squares are the elements instead.
private struct BoardAccessibility: ViewModifier {
    let editing: Bool
    let label: String
    let value: String

    @ViewBuilder func body(content: Content) -> some View {
        if editing {
            content
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(value))
        }
    }
}
