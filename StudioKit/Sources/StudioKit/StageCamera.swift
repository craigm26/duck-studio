import Foundation

/// How far back the camera stands, and what one press of a zoom button does.
///
/// THIS IS A FACT ABOUT THE ROBOT, NOT A LAYOUT DECISION. The near stop is set
/// by a 250 mm duck and the far stop by a staircase over a metre long —
/// `OrbitState` says so in as many words and then keeps the numbers where
/// nothing can read them. The moment those clamps became a VISIBLE control they
/// also became a thing that can be SEEN to be wrong.
public enum StageCamera {

    public static let defaultDistance     = 0.85
    public static let defaultElevation    = 0.30
    public static let nearStopFloor       = 0.20
    public static let farStopFloor        = 4.0
    public static let elevationFloor      = -0.2
    public static let elevationCeiling    = 1.3
    public static let radiansPerDragPoint = 0.01
    public static let orbitNotchPoints    = 24.0
    /// One press. Seven reach each stop from the default framing; fourteen
    /// cross the whole range.
    public static let zoomNotch           = 1.25

    /// Two distances are the same distance when they are this close. A
    /// nanometre, which is nine orders of magnitude under anything this stage
    /// can draw and is here only so a clamp that landed exactly on a stop is
    /// not called "still able to move" by floating point.
    static let sameDistance = 1e-9

    /// THE RANGE ALWAYS CONTAINS THE FRAMING THE STAGE OPENED ON, AT BOTH ENDS.
    /// `frame(_:)` and `resetView()` wrote `distance` unclamped while `zoom`
    /// clamped, so a scene framed beyond 4 m snapped inward on the first pinch
    /// and jumped back out on the next reset — and a scene framed closer than
    /// 0.20 m clamped OUT while `homeDistance` kept the smaller number, so reset
    /// restored a distance the zoom law refused. Invisible while zoom was a
    /// pinch; with a button on the glass it is a control that looks broken.
    public struct Limits: Equatable, Sendable {
        public let nearest: Double
        public let farthest: Double

        public init(nearest: Double, farthest: Double) {
            // A RANGE THAT IS THE WRONG WAY ROUND CLAMPS EVERYTHING TO ONE
            // NUMBER AND SAYS NOTHING ABOUT IT. Ordering here is what stops a
            // caller's arithmetic slip from becoming a stage that will not zoom.
            self.nearest = Swift.min(nearest, farthest)
            self.farthest = Swift.max(nearest, farthest)
        }

        /// Today's numbers, which every stage gets until it says otherwise.
        public static let stage = Limits(nearest: nearStopFloor, farthest: farStopFloor)

        /// Widened at whichever end `home` falls outside. Never narrowed.
        public func containing(_ home: Double) -> Limits {
            guard home.isFinite, home > 0 else { return self }
            return Limits(nearest: Swift.min(nearest, home),
                          farthest: Swift.max(farthest, home))
        }

        /// The near stop derived from the glass: as close as the whole robot
        /// still fits and still clears the chrome standing on the picture.
        public static func fitting(_ glass: StageViewport.Glass,
                                   duckOffsetMetres: Double = 0,
                                   chrome: StageViewport.Chrome = .column,
                                   home: Double?) -> Limits {
            let nearest = StageViewport.nearestDistance(glass,
                                                        duckOffsetMetres: duckOffsetMetres,
                                                        chrome: chrome)
            let fitted = Limits(nearest: nearest, farthest: farStopFloor)
            guard let home else { return fitted }
            return fitted.containing(home)
        }
    }

    public enum Stop: Equatable, Sendable { case free, nearest, farthest }

    public static func clamped(_ metres: Double, to limits: Limits) -> Double {
        guard metres.isFinite else { return limits.nearest }
        return Swift.min(Swift.max(metres, limits.nearest), limits.farthest)
    }

    /// One notch of zoom. `scale > 1` is inward, which is why it DIVIDES — the
    /// pinch recogniser hands over a ratio of finger separation and a spread
    /// means "closer".
    public static func zoomed(_ metres: Double, by scale: Double, to limits: Limits) -> Double {
        guard metres.isFinite, scale.isFinite, scale > 0 else {
            return metres.isFinite ? metres : limits.nearest
        }
        return clamped(metres / scale, to: limits)
    }

    public static func clampedElevation(_ radians: Double) -> Double {
        guard radians.isFinite else { return defaultElevation }
        return Swift.min(Swift.max(radians, elevationFloor), elevationCeiling)
    }

    public static func stop(at metres: Double, in limits: Limits) -> Stop {
        let here = clamped(metres, to: limits)
        if here <= limits.nearest + sameDistance { return .nearest }
        if here >= limits.farthest - sameDistance { return .farthest }
        return .free
    }

    /// Whether a press would move the camera at all. `false` is what disables
    /// the button, and the button then carries `nearestSaid`/`farthestSaid`.
    public static func canZoom(inward: Bool, from metres: Double, to limits: Limits) -> Bool {
        guard metres.isFinite else { return false }
        let next = zoomed(metres, by: inward ? zoomNotch : 1 / zoomNotch, to: limits)
        return abs(next - clamped(metres, to: limits)) > sameDistance
    }

    // MARK: - what the readout says

    /// Against the FRAMING, not against the duck. `distance` is to the aim
    /// point, and the aim point is an explicit focus, the trunk, or the scene's
    /// box depending on the screen — "850 mm from the duck" is false on two of
    /// the three.
    public static func framingSaid(distanceMetres: Double, home: Double?) -> String {
        let base = "camera \(millimetres(distanceMetres)) mm from what it is aimed at"
        guard let home, home > 0, distanceMetres > 0,
              home.isFinite, distanceMetres.isFinite else { return base }
        let closer = home / distanceMetres
        if abs(closer - 1) < 0.01 { return base + " · the framing this stage opened on" }
        return closer > 1
            ? base + " · \(times(closer))× closer than this stage opened on"
            : base + " · \(times(1 / closer))× further back than this stage opened on"
    }

    private static func millimetres(_ metres: Double) -> String {
        guard metres.isFinite else { return "0" }
        return String(format: "%.0f", metres * 1000)
    }

    private static func times(_ ratio: Double) -> String {
        String(format: "%.1f", ratio)
    }

    // Canonical English for the seven rotor actions and the camera chip. These
    // are rendered VERBATIM by `Text(...)`, as every other kit sentence in this
    // app already is (`Text(DriveVenue.robotIsNotDrivenYet)`,
    // `Text(JointHandles.homeActionSaid)`). There is no .lproj and no
    // .xcstrings in this app; a LocalizedStringKey split would be a new pattern
    // buying nothing, against a rule that says every user-visible sentence is a
    // tested kit string.
    public static let zoomInSaid     = "Zoom in"
    public static let zoomOutSaid    = "Zoom out"
    public static let resetSaid      = "Reset the view"
    public static let orbitLeftSaid  = "Orbit left"
    public static let orbitRightSaid = "Orbit right"
    public static let lookHigherSaid = "Look from higher"
    public static let lookLowerSaid  = "Look from lower"
    public static let cameraSaid     = "Camera"
    public static let followingSaid  = "Following"
    public static let fixedSaid      = "Fixed"

    /// The ten, in one place, so a test can assert there are ten of them and
    /// that nothing on any stage spells one of them a second way.
    public static let words = [zoomInSaid, zoomOutSaid, resetSaid,
                               orbitLeftSaid, orbitRightSaid,
                               lookHigherSaid, lookLowerSaid,
                               cameraSaid, followingSaid, fixedSaid]

    /// The near stop of a range nobody fitted to the glass: the editor's, and
    /// the Control tab's while the camera is Fixed. It claims nothing about
    /// where the robot is drawn, because nothing measured that.
    public static let nearStopSaid =
        "That is as close as this stage goes. It stops at 200 mm."

    public static let nearestSaid =
        "That is as close as the whole robot fits on the glass. Any closer and part of it would "
      + "be off the edge or behind these controls, so the stage stops here."

    public static let farthestSaid =
        "That is as far back as this stage goes. It reaches four metres, or the framing this "
      + "stage opened on if that was further. This does not say the whole scene is in the "
      + "picture at that distance — only that the camera stops here."
}
