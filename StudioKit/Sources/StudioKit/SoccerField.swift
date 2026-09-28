import Foundation

/// A proper football pitch's markings, fitted to Duck Soccer's pitch.
///
/// SCALED FROM A REAL PITCH, FITTED AROUND THIS GAME'S GOAL. A full-size pitch is
/// 105 m long; this one is 2.4 m, so a metre there is 2.286 cm here. The goal
/// is the exception: the game's goal is wider than a scaled one so a duck can
/// score, so the goal area and penalty area are drawn the real distance OUT
/// FROM THE POSTS (5.5 m and 16.5 m) rather than at their absolute widths,
/// which is what keeps them wider than the goal they surround.
extension DuckSoccer.Pitch {

    public struct Markings: Sendable {
        /// Straight lines, as end points on the floor.
        public var lines: [(DuckSoccer.Vec2, DuckSoccer.Vec2)] = []
        /// Spots: the centre spot and both penalty spots.
        public var spots: [DuckSoccer.Vec2] = []
        /// Where the four corner flags stand.
        public var corners: [DuckSoccer.Vec2] = []
    }

    /// Metres on a real pitch, as metres on this one.
    public var scale: Double { length / 105 }

    public var penaltyAreaDepth: Double { 16.5 * scale }
    public var goalAreaDepth: Double { 5.5 * scale }
    public var penaltySpot: Double { 11 * scale }
    public var centreCircle: Double { 9.15 * scale }
    public var penaltyAreaHalfWidth: Double { min(goalHalfWidth + 16.5 * scale, halfWidth - 0.03) }
    public var goalAreaHalfWidth: Double { goalHalfWidth + 5.5 * scale }

    /// Every marking, arcs broken into short straight pieces.
    public func markings(arcPieces: Int = 36) -> Markings {
        typealias V = DuckSoccer.Vec2
        var m = Markings()
        let L = halfLength, W = halfWidth
        // The boundary and the halfway line.
        m.lines += [(V(-L, -W), V(L, -W)), (V(-L, W), V(L, W)),
                    (V(-L, -W), V(-L, W)), (V(L, -W), V(L, W)),
                    (V(0, -W), V(0, W))]
        func arc(_ c: V, _ r: Double, from a0: Double, to a1: Double, pieces: Int) {
            for i in 0..<pieces {
                let t0 = a0 + (a1 - a0) * Double(i) / Double(pieces)
                let t1 = a0 + (a1 - a0) * Double(i + 1) / Double(pieces)
                m.lines.append((V(c.x + r * cos(t0), c.y + r * sin(t0)),
                                V(c.x + r * cos(t1), c.y + r * sin(t1))))
            }
        }
        arc(V(0, 0), centreCircle, from: 0, to: 2 * .pi, pieces: arcPieces)
        m.spots.append(V(0, 0))
        for side in [-1.0, 1.0] {
            let goalLine = side * L
            // Penalty area and goal area: three sides each, open at the goal line.
            for (depth, half) in [(penaltyAreaDepth, penaltyAreaHalfWidth), (goalAreaDepth, goalAreaHalfWidth)] {
                let inner = goalLine - side * depth
                m.lines += [(V(goalLine, -half), V(inner, -half)),
                            (V(goalLine, half), V(inner, half)),
                            (V(inner, -half), V(inner, half))]
            }
            let spot = V(goalLine - side * penaltySpot, 0)
            m.spots.append(spot)
            // The penalty arc: the part of the circle round the spot that lies
            // outside the penalty area.
            let edge = goalLine - side * penaltyAreaDepth
            let dx = abs(edge - spot.x)
            if dx < centreCircle {
                let half = acos(dx / centreCircle)
                let facing = side > 0 ? Double.pi : 0
                arc(spot, centreCircle, from: facing - half, to: facing + half, pieces: arcPieces / 3)
            }
            // Corner arcs, a quarter circle at each corner.
            for ySide in [-1.0, 1.0] {
                let corner = V(goalLine, ySide * W)
                m.corners.append(corner)
                let start = side > 0 ? (ySide > 0 ? Double.pi : Double.pi / 2) : (ySide > 0 ? -Double.pi / 2 : 0)
                arc(corner, max(1.0 * scale, 0.04), from: start, to: start + .pi / 2, pieces: 6)
            }
        }
        return m
    }
}
