import XCTest
@testable import StudioKit

/// How tall a stage is, and whether the things floating on it are over the
/// robot.
///
/// THE OCCLUSION HALF IS THE POINT. Build 41 shipped a legend 76 points tall
/// over a 340-point viewport and the screenshot that came back had no robot in
/// it. Nothing could have caught that: a padding is a number typed in a view and
/// a drawn height is not. Every gap below is computed from the glass, the field
/// of view and the camera distance, and asserted at every viewport this app
/// draws — including the negative, that two centimetres closer WOULD cover it.
final class StageViewportTests: XCTestCase {

    // The four glasses this track draws a column on, plus the two full-bleed
    // Control shapes the override added. 351 × 300 is the shipped inline stage
    // on a 6.1" phone; 393 × 534 is the editor's grown stage; 700 × 320 is an
    // iPad in landscape; 351 × 220 is the short case.
    private let inlineGlass = StageViewport.Glass(351, 300)
    private let grownGlass  = StageViewport.Glass(393, 534)
    private let padGlass    = StageViewport.Glass(700, 320)
    private let shortGlass  = StageViewport.Glass(351, 220)
    private var everyGlass: [StageViewport.Glass] {
        [inlineGlass, grownGlass, padGlass, shortGlass]
    }

    /// The Control tab's full-bleed glass: the whole tab, above the Stop bar.
    private let controlGlass = StageViewport.Glass(393, 740)
    /// A SMALLER, HYPOTHETICAL chrome: 96 points at the top, 208 at the bottom.
    /// The app measures its strip and its cluster at runtime and defines
    /// neither number; this shape is kept as the case a lighter Control tab
    /// would be, not as the one that ships (that is `shippedChrome`). The Stop
    /// bar is in neither — it is a `safeAreaInset` outside the stage.
    private let padUpChrome = StageViewport.Chrome.column.over(top: 96, bottom: 208)
    /// The chrome the Control tab actually lays out on a 393 x 740 glass at
    /// the default text size: the venue switch, the 44-point caption row and
    /// the chip row (about 176) at the top; the compact pad with its face
    /// buttons folded two by two and the drawer handle (about 256) at the
    /// bottom. Measured by hand from the layout, not read from the app.
    private let shippedChrome = StageViewport.Chrome.column.over(top: 176, bottom: 256)
    private var drawerChrome: StageViewport.Chrome {
        StageViewport.Chrome.column.over(
            top: 96, bottom: 208 + StageViewport.drawerHeight(available: 740))
    }

    // MARK: - how tall

    func testTheStandardHeightIsTheOneThreeHundred() {
        XCTAssertEqual(StageViewport.standardHeight, 300)
        XCTAssertEqual(StageViewport.height(.standard, available: 812, reserved: 260), 300)
    }

    func testTallTakesWhatTheContainerHasLeft() {
        XCTAssertEqual(StageViewport.height(.tall, available: 812, reserved: 260), 552)
    }

    func testTallIsNeverShorterThanStandard() {
        XCTAssertEqual(StageViewport.height(.tall, available: 554, reserved: 500), 300)
    }

    func testTallNeverExceedsTheContainer() {
        XCTAssertEqual(StageViewport.height(.tall, available: 280, reserved: 1), 280)
        for available in stride(from: 200.0, through: 1200.0, by: 25) {
            for reserved in stride(from: 1.0, through: 600.0, by: 25) {
                XCTAssertLessThanOrEqual(
                    StageViewport.height(.tall, available: available, reserved: reserved),
                    available, "tall overflowed at \(available) / \(reserved)")
            }
        }
    }

    /// A SUMMING PREFERENCE KEY STARTS AT ZERO, so the first pass through layout
    /// asks this question before anything has been measured. It must answer the
    /// height that shipped rather than claim the whole container for one frame.
    func testBeforeLayoutTheStandardHeightHolds() {
        XCTAssertEqual(StageViewport.height(.tall, available: 812, reserved: 0), 300)
        XCTAssertEqual(StageViewport.height(.tall, available: 0, reserved: 260), 300)
        XCTAssertEqual(StageViewport.height(.tall, available: .nan, reserved: 260), 300)
        XCTAssertEqual(StageViewport.height(.tall, available: 812, reserved: .nan), 300)
        XCTAssertFalse(StageViewport.canGrow(available: 800, reserved: 0))
    }

    func testTheControlIsNotOfferedWhenItWouldGainNothing() {
        XCTAssertFalse(StageViewport.canGrow(available: 554, reserved: 284))
        XCTAssertTrue(StageViewport.canGrow(available: 746, reserved: 284))
    }

    func testTheGainThresholdIsExact() {
        XCTAssertTrue(StageViewport.canGrow(available: 460, reserved: 100))
        XCTAssertFalse(StageViewport.canGrow(available: 459, reserved: 100))
    }

    /// The row a handle tap scrolls to, written as its parts so the number
    /// cannot drift away from the thing it reserves.
    func testTheRowReserveIsARowAndItsLabel() {
        XCTAssertEqual(StageViewport.rowReserve, 76)
        XCTAssertEqual(StageViewport.rowReserve, 44 + 8 + 8 + 16)
    }

    // MARK: - the drawer

    /// Half the picture, and never so little that it is a strip that scrolls.
    func testTheDrawerTakesHalfThePictureAndNeverMoreThanThereIs() {
        XCTAssertEqual(StageViewport.drawerHeight(available: 740), 370)
        XCTAssertEqual(StageViewport.drawerHeight(available: 300),
                       StageViewport.drawerLeastHeight)
        XCTAssertEqual(StageViewport.drawerHeight(available: 200), 200)
        for available in stride(from: 100.0, through: 1200.0, by: 20) {
            XCTAssertLessThanOrEqual(StageViewport.drawerHeight(available: available),
                                     available, "the drawer overflowed at \(available)")
        }
        XCTAssertEqual(StageViewport.drawerHeight(available: 0),
                       StageViewport.drawerLeastHeight)
        XCTAssertEqual(StageViewport.drawerHeight(available: .nan),
                       StageViewport.drawerLeastHeight)
    }

    // MARK: - nothing over the duck

    func testNothingCoversTheDuckAtTheInlineStage() {
        let clear = StageViewport.clearance(inlineGlass, at: 0.85)
        XCTAssertFalse(clear.coversTheDuck)
        XCTAssertGreaterThan(clear.gapPoints, 0)
        XCTAssertFalse(clear.duckIsOffTheGlass)
    }

    func testNothingCoversTheDuckAtTheNearestStop() {
        for glass in everyGlass {
            let near = StageViewport.nearestDistance(glass)
            let clear = StageViewport.clearance(glass, at: near)
            XCTAssertFalse(clear.coversTheDuck,
                "chrome is over the duck at the near stop on "
              + "\(glass.widthPoints)×\(glass.heightPoints): gap \(clear.gapPoints)")
            XCTAssertFalse(clear.duckIsOffTheGlass,
                "the duck is off the glass at its own near stop on "
              + "\(glass.widthPoints)×\(glass.heightPoints)")
        }
    }

    /// MUST FAIL IF THE CLEARANCE MATHS IS WRONG. A near stop that is not the
    /// binding bound is a near stop that lets the next press hide the robot, and
    /// a check nobody has watched fail is not a check. Two centimetres is one
    /// twentieth of the closest stop on any of these glasses.
    func testZoomingPastTheNearestStopWouldCoverTheDuck() {
        for glass in everyGlass {
            let near = StageViewport.nearestDistance(glass)
            let closer = StageViewport.clearance(glass, at: near - 0.02)
            XCTAssertTrue(closer.coversTheDuck || closer.duckIsOffTheGlass,
                "two centimetres inside the near stop is still clear on "
              + "\(glass.widthPoints)×\(glass.heightPoints) — gap \(closer.gapPoints), "
              + "which means the stop is not the bound")
        }
    }

    /// THE INHERITED ERROR, WRITTEN DOWN. The drive stage aims at the scene's
    /// bounding box, and a world whose steps stand over a metre to one side puts
    /// the robot well off the middle of the picture.
    func testAnOffCentreDuckIsNotAssumedCentred() {
        let centred = StageViewport.clearance(inlineGlass, at: 0.85)
        let offset = StageViewport.clearance(inlineGlass, at: 0.85, duckOffsetMetres: 0.30)
        XCTAssertLessThan(offset.gapPoints, centred.gapPoints)
        XCTAssertTrue(StageViewport.clearance(inlineGlass, at: 0.85,
                                              duckOffsetMetres: 0.55).coversTheDuck)
    }

    /// Today's near stop is not a framing anybody would want: at 200 mm the
    /// robot is drawn taller than the whole stage.
    func testTodaysNearStopPutsMostOfTheDuckOffTheGlass() {
        let clear = StageViewport.clearance(inlineGlass, at: StageCamera.nearStopFloor)
        XCTAssertGreaterThan(clear.duckHeightPoints, 500)
        XCTAssertTrue(clear.duckIsOffTheGlass)
    }

    func testTheColumnIsNarrowerThanAQuarterOfEveryViewportItIsDrawnOn() {
        XCTAssertEqual(StageViewport.Chrome.column.footprint, 76)
        for glass in everyGlass + [controlGlass] {
            XCTAssertLessThan(StageViewport.Chrome.column.footprint / glass.widthPoints, 0.25,
                              "the column is over a quarter of \(glass.widthPoints)")
        }
    }

    // MARK: - the full-bleed Control tab

    /// THE WHOLE CHROME, NOT ONE COLUMN. With the pad up, the piece nearest the
    /// robot is the bottom cluster, not the column — which is exactly why the
    /// occlusion check had to learn about all three.
    func testTheFullBleedControlChromeIsClearOfTheDuck() {
        let clear = StageViewport.clearance(controlGlass, at: 0.85, chrome: padUpChrome)
        XCTAssertFalse(clear.coversTheDuck)
        XCTAssertGreaterThan(clear.gapPoints, 0)
        XCTAssertEqual(clear.gapPoints, clear.bottomGapPoints, accuracy: 1e-9,
                       "the bottom cluster is the binding piece here, not the column")
        XCTAssertLessThan(clear.bottomGapPoints, clear.columnGapPoints)
        XCTAssertTrue(StageViewport.canClear(controlGlass, chrome: padUpChrome))
    }

    func testTheFullBleedNearStopIsTheBoundAndOneNotchInsideItCovers() {
        let near = StageViewport.nearestDistance(controlGlass, chrome: padUpChrome)
        XCTAssertLessThan(near, 0.85, "the stage opens inside its own near stop")
        XCTAssertFalse(StageViewport.clearance(controlGlass, at: near,
                                               chrome: padUpChrome).coversTheDuck)
        XCTAssertTrue(StageViewport.clearance(controlGlass, at: near - 0.02,
                                              chrome: padUpChrome).coversTheDuck)
    }

    /// THE DRAWER IS A COVER AND THE MATHS SAYS SO. It slides the settings up
    /// over the bottom half of the picture; no camera distance undoes that, and
    /// pretending otherwise is the failure this whole file exists to prevent.
    /// What makes it acceptable is that it ships closed — see
    /// `drawerCostSaid`, which puts the same fact on the glass.
    /// THE SHIPPED CHROME OPENS INSIDE ITS OWN NEAR STOP. At the shape the
    /// Control tab really draws, the bottom cluster binds: the stage's default
    /// distance would put it over the duck, so `orbit.fit` has to clamp the
    /// camera out on open, and the near stop stands beyond that default. This
    /// is the case the hypothetical shape above could not see.
    func testTheShippedFullBleedChromeOpensInsideItsOwnNearStop() {
        XCTAssertTrue(StageViewport.canClear(controlGlass, chrome: shippedChrome))
        let near = StageViewport.nearestDistance(controlGlass, chrome: shippedChrome)
        XCTAssertGreaterThan(near, 0.85, "the near stop is beyond the opening distance")
        XCTAssertTrue(StageViewport.clearance(controlGlass, at: 0.85,
                                              chrome: shippedChrome).coversTheDuck,
                      "at the opening distance the pad cluster is over the duck")
        XCTAssertFalse(StageViewport.clearance(controlGlass, at: near,
                                               chrome: shippedChrome).coversTheDuck)
    }

    func testTheOpenDrawerIsAdmittedToCoverTheDuck() {
        XCTAssertFalse(StageViewport.canClear(controlGlass, chrome: drawerChrome))
        XCTAssertTrue(StageViewport.clearance(controlGlass, at: 0.85,
                                              chrome: drawerChrome).coversTheDuck)
        XCTAssertEqual(StageViewport.nearestDistance(controlGlass, chrome: drawerChrome),
                       StageCamera.farStopFloor,
                       "a chrome nothing can clear must not answer a distance that clears it")
    }

    // MARK: - the words

    func testTheSizeWordsAreTheOnesTheAppDraws() {
        XCTAssertEqual(StageViewport.biggerSaid, "Bigger picture")
        XCTAssertEqual(StageViewport.smallerSaid, "Smaller picture")
        XCTAssertEqual(StageViewport.spoken(.standard), "Standard picture")
        XCTAssertEqual(StageViewport.spoken(.tall), "Bigger picture")
    }

    func testTheCostSentenceNamesWhatSurvives() {
        XCTAssertTrue(StageViewport.growTakesFromTheListSaid.contains("still scrolls"))
        XCTAssertTrue(StageViewport.growTakesFromTheListSaid.contains("does not move"))
    }

    /// TURNING THE PHONE SHORTENS THE VERTICAL FIELD, which is what sets the
    /// duck's drawn height, so advice to rotate makes the picture smaller.
    /// Advice that makes it worse is worse than none.
    func testTheNoRoomSentenceDoesNotSendAnybodyToLandscape() {
        XCTAssertFalse(StageViewport.noRoomToGrowSaid.contains("rotate"))
        XCTAssertFalse(StageViewport.noRoomToGrowSaid.contains("side"))
    }

    func testTheDrawerWordsSayWhatAPressDoesAndWhatItCosts() {
        XCTAssertEqual(StageViewport.drawerSaid(open: false), "Show the controls")
        XCTAssertEqual(StageViewport.drawerSaid(open: true), "Hide the controls")
        XCTAssertEqual(StageViewport.drawerCostSaid,
            "The controls slide up over the lower part of the picture. The drive keeps running "
          + "behind them, and the Stop bar along the bottom of the screen does not move.")
        // IT ADMITS THE COVER RATHER THAN CLAIMING THE DUCK IS STILL CLEAR.
        XCTAssertTrue(StageViewport.drawerCostSaid.contains("over the lower part"))
        XCTAssertTrue(StageViewport.drawerCostSaid.contains("Stop bar"))
    }

    func testTheDrawerSectionsNameWhereTheThingTheySwitchIs() {
        XCTAssertEqual(StageViewport.drawerLayersSaid, "On the picture")
        XCTAssertEqual(StageViewport.drawerPadRestSaid, "The rest of the pad")
    }

    func testTheCaptionDisclosureSaysWhichWayItGoes() {
        XCTAssertEqual(StageViewport.captionSaid(expanded: false), "What this venue is")
        XCTAssertEqual(StageViewport.captionSaid(expanded: true), "Hide what this venue is")
    }

    func testTheFloatingChromeSentenceNamesWhereTheSettingsWent() {
        XCTAssertEqual(StageViewport.chromeFloatsSaid,
            "The picture is the whole screen here. The switch, the sticks and the camera buttons "
          + "float on top of it, and the settings are behind the handle above the Stop bar.")
        XCTAssertTrue(StageViewport.chromeFloatsSaid.contains("Stop bar"))
    }

    /// The chrome's ground is near-opaque, because `Theme` measures its inks
    /// against a solid surface and a half-strength ground over a live render is
    /// a contrast nothing has checked.
    func testTheChromeGroundIsNearlyOpaque() {
        XCTAssertEqual(StageViewport.Chrome.backing, 0.85)
        XCTAssertGreaterThanOrEqual(StageViewport.Chrome.backing, 0.8)
    }

    func testTheSizeRoundTripsThroughStorage() {
        for size in StageViewport.Size.allCases {
            XCTAssertEqual(StageViewport.Size(rawValue: size.rawValue), size)
        }
    }

    /// The AR venue's refusal, letter by letter — and it must carry the same
    /// 2.9 m figure `arIsNot` states, so the two cannot drift.
    func testTheArVenueSaysWhyItHasNoZoom() {
        XCTAssertEqual(DriveVenue.arHasNoZoom,
            "There is no zoom on your floor. The duck, the steps and the square are drawn at the "
          + "size they really are — a 250 mm robot in a 2.9 m world — so the way to see it closer "
          + "is to walk closer, or to tap the floor nearer to you to put it down again.")
        XCTAssertFalse(DriveVenue.arHasNoZoom.contains("bigger"),
                       "the Control tab has no size control to send anybody to")
        XCTAssertTrue(DriveVenue.arHasNoZoom.contains("walk closer"))
        XCTAssertTrue(DriveVenue.arHasNoZoom.contains("2.9 m"))
        XCTAssertTrue(DriveVenue.arIsNot.contains("2.9 m"))
        XCTAssertFalse(DriveVenue.arHasNoZoom.contains("scale"))
    }
}
