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

// MARK: - framing a run that has already happened

public extension StageCamera {

    /// Where a camera has to LOOK and how far back it has to STAND for a
    /// recorded run to be visible in full.
    struct RunFraming: Equatable, Sendable {
        /// The point the camera aims at: the middle of the travel, never below
        /// the middle of a standing robot, so the shot is of the duck rather
        /// than of the floor under it.
        public let x, y, z: Double
        /// Far enough back that the whole path plus the robot on it is inside
        /// the glass — unless the range says no, which `reaches` records.
        public let distance: Double
        /// Whether `distance` actually fits the run. False when the travel
        /// needs more room than `Limits.farthest` allows: the caller has a
        /// framing that is as good as this stage gets and is NOT the whole run.
        public let reaches: Bool

        public init(x: Double, y: Double, z: Double, distance: Double, reaches: Bool) {
            self.x = x; self.y = y; self.z = z
            self.distance = distance; self.reaches = reaches
        }
    }

    /// A STILL CAMERA IS WHAT MAKES TRAVEL VISIBLE, and a run is mostly travel.
    ///
    /// This is the arithmetic behind a bug that survived three fixes. The
    /// Control tab drives with the camera ON the trunk, which is right while
    /// somebody is steering: the duck stays in the middle of a world fifteen
    /// times its size. Play a recorded motion under that same camera and the
    /// camera subtracts the motion — a roll that carries the body half a metre
    /// is drawn as a body rolling on the spot, and the honest report is "it
    /// barely moves". The editor never had the bug because its player opens a
    /// fresh, fixed camera every time.
    ///
    /// SO THE PLAYBACK BRINGS ITS OWN AIM POINT. Not by turning `follows` off
    /// — that is the person's setting and it has to come back — but by naming
    /// the one point worth looking at for as long as the clip is on screen.
    ///
    /// BOTH AXES, BECAUSE THE CAMERA CAN BE ANYWHERE ON THE ORBIT. A run one
    /// metre along x is one metre wide seen from z and one metre DEEP seen from
    /// x, and the caller does not know which way round the person has dragged
    /// the stage to. Taking the larger of the two is what makes the answer
    /// independent of the azimuth, which is the only way it can be computed
    /// here at all.
    ///
    /// - Parameter roots: the run's own trunk positions, IN THE FRAME THE
    ///   CAMERA WORKS IN. This is arithmetic over a set of points and has no
    ///   opinion about which axis is up; the caller converts, because the
    ///   caller is the one that knows what its renderer calls y. `y` here is
    ///   the axis the glass measures its field of view along.
    /// - Parameter duckHeightMetres: the robot's own size, added to the travel
    ///   so the duck at each end of the path is inside the picture rather than
    ///   half off it.
    /// - Returns: nil for an empty run, which has nothing to look at.
    static func framing(forRun roots: [(x: Double, y: Double, z: Double)],
                        on glass: StageViewport.Glass,
                        within limits: Limits = .stage,
                        duckHeightMetres: Double = DuckScene.duckStandingHeight)
        -> RunFraming? {
        guard let first = roots.first else { return nil }
        var low = first, high = first
        for point in roots {
            low = (x: Swift.min(low.x, point.x), y: Swift.min(low.y, point.y),
                   z: Swift.min(low.z, point.z))
            high = (x: Swift.max(high.x, point.x), y: Swift.max(high.y, point.y),
                    z: Swift.max(high.z, point.z))
        }
        // THE ROBOT HAS A SIZE. Framing the PATH alone puts the duck's head and
        // feet off the glass at both ends of it, which is a picture of a line
        // with a duck-shaped hole moving along it.
        let across = Swift.max(high.x - low.x, high.z - low.z) + duckHeightMetres
        let up = (high.y - low.y) + duckHeightMetres
        let half = tan(glass.fieldOfView / 2)
        guard half > 0 else { return nil }
        let forHeight = up / (2 * half)
        // THE HORIZONTAL FIELD IS THE VERTICAL ONE TIMES THE ASPECT, so a tall
        // narrow glass — which is what a phone held upright is — needs the
        // camera FURTHER back for the same sideways travel, not nearer.
        let aspect = glass.aspect > 0 ? glass.aspect : 1
        let forWidth = across / (2 * half * aspect)
        let wanted = Swift.max(defaultDistance, Swift.max(forHeight, forWidth))
        let distance = clamped(wanted, to: limits)
        return RunFraming(x: (low.x + high.x) / 2,
                          // NEVER THE FLOOR. A run that never leaves the ground
                          // has a midpoint at ankle height; aiming there points
                          // the camera under the duck.
                          y: Swift.max((low.y + high.y) / 2, duckHeightMetres / 2),
                          z: (low.z + high.z) / 2,
                          distance: distance,
                          reaches: distance >= wanted - 1e-9)
    }
}
