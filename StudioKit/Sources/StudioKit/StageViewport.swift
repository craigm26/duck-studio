import Foundation

/// How tall a stage is, how much of it the chrome standing on it takes, and
/// whether anything of the robot is left underneath.
///
/// THE 300 WAS WRITTEN FIVE TIMES — `DriveMetric.viewportHeight`,
/// `AuthoringMetric.stageHeight`, `SceneMetric.viewportHeight`, `TuneView`'s own
/// instance `let` and `BenchMetric`'s 320. Five independent answers to one
/// question, defensible while the number never moved. A control that changes it
/// makes them five things that drift.
///
/// AND THE OCCLUSION HALF IS HERE FOR A REASON THIS PROJECT HAS ALREADY PAID
/// FOR ONCE. Build 41 shipped a legend that stood 76 points tall over a 340
/// point viewport, and the screenshot that came back was a grid, a card and no
/// robot. "It looks fine on my phone" is not a claim anything can check; a gap
/// in points, computed from the glass and the camera distance and asserted at
/// every viewport the app draws, is.
public enum StageViewport {

    public static let standardHeight: Double = 300

    /// The least a bigger picture must actually gain before the control is
    /// offered. Sixty points is the app's own moving target: under that the
    /// picture does not visibly change, and a button that changes nothing
    /// visible is the failure this app names as inert.
    public static let minimumGain: Double = 60

    /// One list row and its label — 44 of target, 8 above, 8 below, 16 of
    /// caption. THE ROW A HANDLE TAP SCROLLS TO. A stage allowed to eat this is
    /// a stage where tapping a joint lights a handle and scrolls to a row that
    /// is not on screen.
    public static let rowReserve: Double = 76

    public enum Size: String, CaseIterable, Sendable, Equatable { case standard, tall }

    /// The height a stage gets, in points. Clamped at BOTH ends.
    ///
    /// `reserved <= 0` is the pass before layout has happened (a summing
    /// PreferenceKey starts at zero) and keeps the standard height rather than
    /// claiming the whole container for one frame.
    public static func height(_ size: Size, available: Double, reserved: Double) -> Double {
        guard size == .tall, available.isFinite, reserved.isFinite,
              available > 0, reserved > 0 else { return standardHeight }
        return min(available, max(standardHeight, available - reserved))
    }

    public static func canGrow(available: Double, reserved: Double) -> Bool {
        guard available.isFinite, reserved.isFinite, available > 0, reserved > 0 else {
            return false
        }
        return available - reserved >= standardHeight + minimumGain
    }

    // MARK: - the drawer

    /// How much of the picture the controls drawer takes when it is up.
    ///
    /// HALF, AND IT IS A COVER, WHICH THIS SAYS RATHER THAN DENIES. The Control
    /// tab's stage is the whole tab now and the settings list slides up over the
    /// bottom of it. Nothing here pretends the duck is still clear underneath —
    /// `clearance` reports the drawer's own footprint like any other chrome and
    /// answers `coversTheDuck` when it is over the robot, which is the honest
    /// reading and the one `drawerCostSaid` puts on screen. What keeps that
    /// acceptable is that the drawer ships CLOSED and only a deliberate press
    /// opens it.
    public static let drawerFraction = 0.5

    /// The least a drawer may be and still be a list: four rows and their
    /// headings. Under this it is a strip that scrolls, which is worse than a
    /// control the person has to open twice.
    public static let drawerLeastHeight: Double = 220

    public static func drawerHeight(available: Double) -> Double {
        guard available.isFinite, available > 0 else { return drawerLeastHeight }
        return min(available, max(drawerLeastHeight, available * drawerFraction))
    }

    // MARK: - the glass, for occlusion

    /// A stage's real dimensions and the camera's vertical field.
    public struct Glass: Equatable, Sendable {
        public let widthPoints: Double
        public let heightPoints: Double
        /// VERTICAL, in radians — the axis RealityKit measures.
        public let fieldOfView: Double

        public init(widthPoints: Double, heightPoints: Double,
                    fieldOfView: Double = DuckScene.authoringFieldOfView) {
            self.widthPoints = widthPoints
            self.heightPoints = heightPoints
            self.fieldOfView = fieldOfView
        }

        /// The shorthand the tests are written in, because a glass is a pair of
        /// numbers everywhere it appears.
        public init(_ widthPoints: Double, _ heightPoints: Double,
                    fieldOfView: Double = DuckScene.authoringFieldOfView) {
            self.init(widthPoints: widthPoints, heightPoints: heightPoints,
                      fieldOfView: fieldOfView)
        }

        public var aspect: Double {
            heightPoints > 0 ? widthPoints / heightPoints : 1
        }

        public func visibleHeightMetres(at distance: Double) -> Double {
            2 * distance * tan(fieldOfView / 2)
        }

        public func visibleWidthMetres(at distance: Double) -> Double {
            visibleHeightMetres(at: distance) * aspect
        }

        /// How many points of glass a length in metres covers, at a distance.
        public func points(metres: Double, at distance: Double) -> Double {
            let visible = visibleHeightMetres(at: distance)
            guard visible > 0, heightPoints > 0 else { return 0 }
            return metres / visible * heightPoints
        }

        /// Points of glass per metre at a distance — the one ratio every line
        /// below is written in, so it is derived once.
        func scale(at distance: Double) -> Double {
            points(metres: 1, at: distance)
        }
    }

    /// What the floating chrome takes out of the picture.
    ///
    /// THREE FOOTPRINTS, NOT ONE COLUMN. The plan sized a trailing column of
    /// four buttons and stopped there, which was right while the stage was a
    /// 300-point card with everything else stacked above and below it. On the
    /// Control tab the stage is the whole tab and the switch, the caption, the
    /// pad and the drawer are all drawn ON it — so an occlusion check that only
    /// knew about the column would be a check that could not see the piece most
    /// likely to be over the robot.
    public struct Chrome: Equatable, Sendable {
        /// The trailing column: 44 pt of target, tight padding inside and out.
        public let columnWidth: Double
        public let margin: Double
        /// The strip along the top — the venue switch and the collapsed caption.
        public let topPoints: Double
        /// The cluster along the bottom — the sticks, the faces, the drawer
        /// handle, and the drawer itself when it is up. NOT the Stop bar: that
        /// is a `safeAreaInset` outside the stage and takes nothing off it.
        public let bottomPoints: Double

        public init(columnWidth: Double, margin: Double,
                    topPoints: Double = 0, bottomPoints: Double = 0) {
            self.columnWidth = columnWidth
            self.margin = margin
            self.topPoints = topPoints
            self.bottomPoints = bottomPoints
        }

        public var footprint: Double { columnWidth + margin * 2 }   // 76

        public static let column = Chrome(columnWidth: 44, margin: 16)
        public static let none = Chrome(columnWidth: 0, margin: 0)

        /// The same column with a measured top strip and bottom cluster added.
        public func over(top: Double, bottom: Double) -> Chrome {
            Chrome(columnWidth: columnWidth, margin: margin,
                   topPoints: max(0, top), bottomPoints: max(0, bottom))
        }

        /// How solid a floating piece's ground is over a live picture.
        ///
        /// EIGHTY-FIVE HUNDREDTHS, AND IT IS THE NUMBER THE APP ALREADY USES.
        /// `StageCaptionBox.backing` in `DesignComponents` is the same value for
        /// the same job — words on a translucent `surfacePrimary` over a render
        /// — and this is the kit's copy so a test can read it. Two copies of one
        /// opacity is a thing this build accepted and wrote down rather than
        /// fixed: `DesignComponents.swift` is not this track's file. See the
        /// requests in the build log.
        ///
        /// It is deliberately near-opaque. `Theme` measures its inks against
        /// `surfacePrimary` at 4.5:1; a ground at half strength is a ground
        /// nothing has measured, over a picture that changes every frame.
        public static let backing = 0.85
    }

    /// How close to an edge still counts as on the glass.
    ///
    /// HALF A POINT, WHICH IS UNDER ONE PIXEL ON EVERY DEVICE THIS SHIPS TO —
    /// the same threshold and the same argument `DuckStage.Coordinator`'s
    /// `stillEnough` makes about a projection that has not really moved. It is
    /// here because `nearestDistance` solves for the EXACT bound, so the duck at
    /// the near stop sits on the edge to within floating-point noise: without a
    /// tolerance, `clearance(g, at: nearestDistance(g))` reports the stop it
    /// just computed as an overlap, on three of the four glasses this app draws.
    /// The near stop is still exact; what this decides is only whether a gap of
    /// minus two hundredths of a pixel is a gap.
    public static let touching: Double = 0.5

    /// How much room the chrome leaves the robot, in points, at one distance.
    public struct Clearance: Equatable, Sendable {
        public let glassWidthPoints: Double
        public let glassHeightPoints: Double
        public let duckHalfWidthPoints: Double
        public let duckHeightPoints: Double
        /// Signed, from the centre of the glass. NOT ASSUMED ZERO: on the drive
        /// stage the camera aims at the scene's bounding box, and a world whose
        /// steps stand 1.305 m to one side puts the duck well off centre.
        public let duckCentreXPoints: Double
        /// Where the trailing column's band begins, from the leading edge.
        public let chromeStartsAtPoints: Double
        /// The tightest of the three gaps. Negative means chrome is over the duck.
        public let gapPoints: Double
        /// Each gap on its own, so a failure names the piece that caused it.
        public let columnGapPoints: Double
        public let topGapPoints: Double
        public let bottomGapPoints: Double

        public var coversTheDuck: Bool { gapPoints < -StageViewport.touching }

        /// Whether any part of the robot's box is past an edge of the glass.
        /// A DIFFERENT FAILURE FROM BEING COVERED, and the near stop has to
        /// refuse both: chrome over the duck and duck off the picture look the
        /// same from the far side of a zoom button and are fixed by the same
        /// press.
        public var duckIsOffTheGlass: Bool {
            let slack = StageViewport.touching
            let centre = glassWidthPoints / 2 + duckCentreXPoints
            let left = centre - duckHalfWidthPoints
            let right = centre + duckHalfWidthPoints
            let top = glassHeightPoints / 2 - duckHeightPoints / 2
            let bottom = glassHeightPoints / 2 + duckHeightPoints / 2
            return left < -slack || right > glassWidthPoints + slack
                || top < -slack || bottom > glassHeightPoints + slack
        }
    }

    /// Where the chrome is against where the robot is drawn, at one distance.
    ///
    /// THE ROBOT IS TAKEN AS A BOX ON THE MIDDLE OF THE GLASS, vertically. That
    /// is what the camera does: it looks at the duck when it follows and at the
    /// scene's box when it does not, and either way the aim point is the middle
    /// of the picture. `duckOffsetMetres` is how far the robot stands from that
    /// aim point along the glass's horizontal axis; the caller passes a
    /// magnitude, because the azimuth decides which side and the trailing side
    /// is the one with a column standing on it.
    public static func clearance(_ glass: Glass, at distanceMetres: Double,
                                 duckOffsetMetres: Double = 0,
                                 duckHalfSpanMetres: Double = DuckScene.duckHalfSpan,
                                 duckHeightMetres: Double = DuckScene.duckStandingHeight,
                                 chrome: Chrome = .column) -> Clearance {
        let scale = distanceMetres > 0 && distanceMetres.isFinite
            ? glass.scale(at: distanceMetres) : 0
        let halfWidth = duckHalfSpanMetres * scale
        let height = duckHeightMetres * scale
        let centreX = duckOffsetMetres * scale
        let startsAt = glass.widthPoints - chrome.footprint

        let trailingEdge = glass.widthPoints / 2 + centreX + halfWidth
        let columnGap = startsAt - trailingEdge
        let topGap = (glass.heightPoints / 2 - height / 2) - chrome.topPoints
        let bottomGap = (glass.heightPoints - chrome.bottomPoints)
                      - (glass.heightPoints / 2 + height / 2)

        return Clearance(glassWidthPoints: glass.widthPoints,
                         glassHeightPoints: glass.heightPoints,
                         duckHalfWidthPoints: halfWidth,
                         duckHeightPoints: height,
                         duckCentreXPoints: centreX,
                         chromeStartsAtPoints: startsAt,
                         gapPoints: Swift.min(columnGap, topGap, bottomGap),
                         columnGapPoints: columnGap,
                         topGapPoints: topGap,
                         bottomGapPoints: bottomGap)
    }

    /// As close as the WHOLE robot still fits on the glass and clear of the
    /// chrome.
    ///
    /// SOLVED, NOT SEARCHED. Every constraint is of the form "a length in
    /// metres, scaled by `k / d`, must fit in a number of points", so each one
    /// is a lower bound on `d` and the answer is the largest of them. That
    /// matters for more than speed: a bound that is exactly the binding one is
    /// what makes `clearance(g, at: n - 0.02)` fail, and a check nobody has
    /// watched fail is not a check.
    ///
    /// A CHROME TALLER THAN HALF THE GLASS CANNOT BE CLEARED AT ANY DISTANCE,
    /// and that is a real case — it is what the controls drawer is. This answers
    /// the far stop there rather than a number that would be a lie, and
    /// `canClear` is the question to ask first.
    public static func nearestDistance(_ glass: Glass,
                                       duckOffsetMetres: Double = 0,
                                       duckHalfSpanMetres: Double = DuckScene.duckHalfSpan,
                                       duckHeightMetres: Double = DuckScene.duckStandingHeight,
                                       chrome: Chrome = .column) -> Double {
        guard glass.widthPoints > 0, glass.heightPoints > 0 else {
            return StageCamera.farStopFloor
        }
        // Points per metre at one metre: `points = metres * k / d`.
        let k = glass.scale(at: 1)
        guard k > 0 else { return StageCamera.farStopFloor }

        var bounds: [Double] = []
        func bound(_ metres: Double, fitsIn points: Double) -> Bool {
            guard metres > 0 else { return true }
            guard points > 0 else { return false }
            bounds.append(metres * k / points)
            return true
        }

        // The trailing side, against the column.
        var possible = bound(duckOffsetMetres + duckHalfSpanMetres,
                             fitsIn: glass.widthPoints / 2 - chrome.footprint)
        // The leading side, against the edge.
        possible = bound(duckHalfSpanMetres - duckOffsetMetres,
                         fitsIn: glass.widthPoints / 2) && possible
        // The top strip and the bottom cluster, each measured from the middle.
        possible = bound(duckHeightMetres / 2,
                         fitsIn: glass.heightPoints / 2 - chrome.topPoints) && possible
        possible = bound(duckHeightMetres / 2,
                         fitsIn: glass.heightPoints / 2 - chrome.bottomPoints) && possible

        guard possible else { return StageCamera.farStopFloor }
        return bounds.max() ?? StageCamera.nearStopFloor
    }

    /// Whether any distance at all keeps the robot clear of this chrome.
    /// FALSE IS NOT AN ERROR: an open drawer is chrome over the lower half of
    /// the picture on purpose, and the honest answer is that no camera move
    /// undoes it.
    public static func canClear(_ glass: Glass,
                                duckOffsetMetres: Double = 0,
                                duckHalfSpanMetres: Double = DuckScene.duckHalfSpan,
                                chrome: Chrome = .column) -> Bool {
        glass.widthPoints / 2 - chrome.footprint > 0
            && glass.widthPoints / 2 > 0
            && glass.heightPoints / 2 - chrome.topPoints > 0
            && glass.heightPoints / 2 - chrome.bottomPoints > 0
            && (duckHalfSpanMetres + duckOffsetMetres) > 0
    }

    // MARK: - what the screen says

    public static let biggerSaid  = "Bigger picture"
    public static let smallerSaid = "Smaller picture"

    /// What the size the stage is at now is CALLED, as the button's value.
    public static func spoken(_ size: Size) -> String {
        switch size {
        case .standard: return "Standard picture"
        case .tall:     return "Bigger picture"
        }
    }

    public static let growTakesFromTheListSaid =
        "The bigger picture takes its room from the list below it, which still scrolls. "
      + "The bar along the bottom of the screen does not move."

    public static let noRoomToGrowSaid =
        "The picture is already as big as this screen allows. The stage takes everything above "
      + "the controls, and the pad has to stay where a thumb can reach it. On a taller screen "
      + "this control appears."

    // MARK: - the Control tab's floating chrome

    /// The drawer handle, as what a press DOES.
    public static let drawerOpenSaid  = "Show the controls"
    public static let drawerCloseSaid = "Hide the controls"

    public static func drawerSaid(open: Bool) -> String {
        open ? drawerCloseSaid : drawerOpenSaid
    }

    /// What opening it costs, said before it happens rather than discovered.
    ///
    /// IT ADMITS THE COVER. The drawer slides the settings up over the bottom of
    /// the picture; nothing here claims the duck is still fully visible, because
    /// `clearance` says it is not. What it names instead are the two things that
    /// do not change: the loop keeps running behind it, and the Stop bar does
    /// not move.
    public static let drawerCostSaid =
        "The controls slide up over the lower part of the picture. The drive keeps running "
      + "behind them, and the Stop bar along the bottom of the screen does not move."

    /// The two sections the drawer gained when the picture took the whole tab.
    ///
    /// THEY NAME WHERE THE THING THEY SWITCH ACTUALLY IS. The layer chips used
    /// to sit in a row directly under the stage, where "what they are for" was
    /// obvious from six inches of proximity; in a drawer they need saying. And
    /// the pad's remaining controls — the dpad and the two system buttons — are
    /// here rather than on the picture because none of them moves the duck
    /// against a bench, so the heading says they are the REST of it rather than
    /// implying the sticks are missing.
    public static let drawerLayersSaid  = "On the picture"
    public static let drawerPadRestSaid = "The rest of the pad"

    /// The disclosure over the picture that opens the venue's own sentence.
    /// COLLAPSED, BECAUSE THE SENTENCE IS LONG AND THE PICTURE IS THE POINT.
    public static let captionOpenSaid  = "What this venue is"
    public static let captionCloseSaid = "Hide what this venue is"

    public static func captionSaid(expanded: Bool) -> String {
        expanded ? captionCloseSaid : captionOpenSaid
    }

    /// Why the controls are not stacked under the picture any more, said once,
    /// where somebody looking for them would look.
    public static let chromeFloatsSaid =
        "The picture is the whole screen here. The switch, the sticks and the camera buttons "
      + "float on top of it, and the settings are behind the handle above the Stop bar."
}
