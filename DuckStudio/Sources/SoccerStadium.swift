import UIKit
import RealityKit

/// The non-AR stadium: a themed pitch in its own little world, no camera feed.
///
/// AR IS A PLACE; A STADIUM IS A MOOD. The AR pitch borrows your carpet and
/// keeps the classic paint. Stadium mode owns the whole frame, so it gets to
/// be what a duck football broadcast should be — pastel and gloriously
/// nineties. Each theme is a full palette rather than one accent swapped, and
/// the palettes are opinionated on purpose: a mint pitch under a peach sky is
/// a decision, not a default.
struct SoccerTheme: Identifiable, Hashable {
    let name: String
    let sky: UIColor
    let floor: UIColor
    /// Alternating mow-stripe tint laid over the floor. Same as `floor` for a
    /// theme without stripes.
    let stripe: UIColor
    let line: UIColor
    let board: UIColor
    let stands: UIColor
    let homeGoal: UIColor
    let awayGoal: UIColor
    let ball: UIColor
    var id: String { name }

    static let classic = SoccerTheme(
        name: "Classic AR",
        sky: .black, floor: .clear, stripe: .clear,
        line: UIColor.white.withAlphaComponent(0.75),
        board: UIColor.white.withAlphaComponent(0.28),
        stands: .clear,
        homeGoal: .systemYellow, awayGoal: .systemTeal,
        ball: .systemOrange)

    /// Sherbet mint pitch, peach sky, strawberry boards.
    static let pastel = SoccerTheme(
        name: "Pastel Cup",
        sky: UIColor(red: 1.00, green: 0.87, blue: 0.80, alpha: 1),
        floor: UIColor(red: 0.72, green: 0.92, blue: 0.80, alpha: 1),
        stripe: UIColor(red: 0.65, green: 0.88, blue: 0.74, alpha: 1),
        line: UIColor(red: 1.00, green: 0.99, blue: 0.94, alpha: 1),
        board: UIColor(red: 0.98, green: 0.72, blue: 0.76, alpha: 1),
        stands: UIColor(red: 0.80, green: 0.76, blue: 0.94, alpha: 1),
        homeGoal: UIColor(red: 0.99, green: 0.85, blue: 0.46, alpha: 1),
        awayGoal: UIColor(red: 0.62, green: 0.83, blue: 0.95, alpha: 1),
        ball: UIColor(red: 0.98, green: 0.55, blue: 0.45, alpha: 1))

    /// Magenta dusk, cyan lines, the grid-sunset nineties.
    static let vaporwave = SoccerTheme(
        name: "Vaporwave FC",
        sky: UIColor(red: 0.16, green: 0.05, blue: 0.28, alpha: 1),
        floor: UIColor(red: 0.23, green: 0.09, blue: 0.36, alpha: 1),
        stripe: UIColor(red: 0.28, green: 0.11, blue: 0.42, alpha: 1),
        line: UIColor(red: 0.30, green: 0.95, blue: 0.93, alpha: 1),
        board: UIColor(red: 0.95, green: 0.35, blue: 0.75, alpha: 1),
        stands: UIColor(red: 0.35, green: 0.16, blue: 0.52, alpha: 1),
        homeGoal: UIColor(red: 1.00, green: 0.45, blue: 0.85, alpha: 1),
        awayGoal: UIColor(red: 0.35, green: 0.90, blue: 1.00, alpha: 1),
        ball: UIColor(red: 1.00, green: 0.85, blue: 0.30, alpha: 1))

    /// The bowling-alley carpet: deep purple, neon confetti colours.
    static let arcade = SoccerTheme(
        name: "Arcade Carpet",
        sky: UIColor(red: 0.07, green: 0.06, blue: 0.16, alpha: 1),
        floor: UIColor(red: 0.22, green: 0.13, blue: 0.38, alpha: 1),
        stripe: UIColor(red: 0.17, green: 0.10, blue: 0.32, alpha: 1),
        line: UIColor(red: 0.98, green: 0.93, blue: 0.35, alpha: 1),
        board: UIColor(red: 0.20, green: 0.85, blue: 0.55, alpha: 1),
        stands: UIColor(red: 0.13, green: 0.10, blue: 0.24, alpha: 1),
        homeGoal: UIColor(red: 1.00, green: 0.35, blue: 0.35, alpha: 1),
        awayGoal: UIColor(red: 0.35, green: 0.65, blue: 1.00, alpha: 1),
        ball: UIColor(red: 1.00, green: 0.60, blue: 0.10, alpha: 1))

    /// Saturday-morning primary colours on cream.
    static let saturday = SoccerTheme(
        name: "Saturday Cartoon",
        sky: UIColor(red: 0.99, green: 0.96, blue: 0.86, alpha: 1),
        floor: UIColor(red: 0.45, green: 0.78, blue: 0.42, alpha: 1),
        stripe: UIColor(red: 0.40, green: 0.72, blue: 0.38, alpha: 1),
        line: .white,
        board: UIColor(red: 0.95, green: 0.30, blue: 0.25, alpha: 1),
        stands: UIColor(red: 0.30, green: 0.55, blue: 0.90, alpha: 1),
        homeGoal: UIColor(red: 1.00, green: 0.80, blue: 0.10, alpha: 1),
        awayGoal: UIColor(red: 0.55, green: 0.35, blue: 0.85, alpha: 1),
        ball: .white)

    /// The stadium palettes a match can be played in. Classic stays out —
    /// it is the AR look, and AR keeps it.
    static let stadiums: [SoccerTheme] = [.pastel, .vaporwave, .arcade, .saturday]
}

/// The broadcast camera: an orbit around the centre spot, driven by the same
/// drag-and-pinch a person already knows from every 3D screen in these apps.
struct StadiumCamera {
    // SIDE-LINE, THE TV ANGLE. The pitch's length runs along x, goals at
    // x = ±halfL, so the side-line is azimuth 0 (or π): the first version's
    // π/2 sat behind the CPU goal and inverted the stick on both axes.
    var azimuth: Float = 0
    var elevation: Float = 0.55
    var distance: Float = 2.6

    mutating func drag(dx: Float, dy: Float) {
        azimuth -= dx * 0.008
        elevation = min(max(elevation + dy * 0.008, 0.15), 1.35)
    }

    mutating func zoom(by scale: Float) {
        distance = min(max(distance / scale, 1.0), 5.0)
    }

    var position: SIMD3<Float> {
        let horizontal = distance * cos(elevation)
        return SIMD3(horizontal * sin(azimuth),
                     0.15 + distance * sin(elevation),
                     horizontal * cos(azimuth))
    }
}
