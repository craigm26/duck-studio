import XCTest
@testable import StudioKit

/// The zoom law, once it is a pair of buttons on the glass instead of a pinch.
///
/// A CLAMP NOBODY COULD SEE IS A CLAMP NOBODY COULD CHECK. `OrbitState.zoom`
/// clamped to 0.20…4.0 while `frame(_:)` and `resetView()` wrote `distance`
/// straight through — so a scene framed beyond four metres snapped inward on the
/// first pinch and jumped back out on the next reset, and a scene framed inside
/// twenty centimetres clamped OUT while `homeDistance` kept the smaller number.
/// Invisible while zoom was a gesture. With a button on the picture it is a
/// control that looks broken.
final class StageCameraTests: XCTestCase {

    private let stage = StageCamera.Limits.stage

    func testSevenPressesReachEachStopFromTheDefault() {
        var inward = StageCamera.defaultDistance
        for press in 1...6 {
            inward = StageCamera.zoomed(inward, by: StageCamera.zoomNotch, to: stage)
            XCTAssertGreaterThan(inward, StageCamera.nearStopFloor,
                                 "press \(press) reached the near stop early")
        }
        inward = StageCamera.zoomed(inward, by: StageCamera.zoomNotch, to: stage)
        XCTAssertEqual(inward, StageCamera.nearStopFloor, accuracy: 1e-9)

        var outward = StageCamera.defaultDistance
        for press in 1...6 {
            outward = StageCamera.zoomed(outward, by: 1 / StageCamera.zoomNotch, to: stage)
            XCTAssertLessThan(outward, StageCamera.farStopFloor,
                              "press \(press) reached the far stop early")
        }
        outward = StageCamera.zoomed(outward, by: 1 / StageCamera.zoomNotch, to: stage)
        XCTAssertEqual(outward, StageCamera.farStopFloor, accuracy: 1e-9)
    }

    func testAStageFramedBeyondTheFarStopKeepsItsFraming() {
        let wide = stage.containing(5.2)
        XCTAssertEqual(wide.farthest, 5.2)
        XCTAssertEqual(StageCamera.zoomed(5.2, by: 1 / StageCamera.zoomNotch, to: wide), 5.2)
        XCTAssertFalse(StageCamera.canZoom(inward: false, from: 5.2, to: wide))
        XCTAssertTrue(StageCamera.canZoom(inward: true, from: 5.2, to: wide))
    }

    func testAStageFramedInsideTheNearStopKeepsItsFraming() {
        let close = stage.containing(0.14)
        XCTAssertLessThanOrEqual(close.nearest, 0.14)
        XCTAssertEqual(StageCamera.clamped(0.14, to: close), 0.14)
    }

    func testContainingNeverNarrows() {
        XCTAssertEqual(stage.containing(1.0), stage)
        XCTAssertEqual(stage.containing(.nan), stage)
        XCTAssertEqual(stage.containing(0), stage)
        XCTAssertEqual(stage.containing(-3), stage)
    }

    /// RESET MUST LAND SOMEWHERE THE ZOOM LAW ALLOWS. This is the pair that was
    /// broken: reset restored `homeDistance` unclamped, then the first press of
    /// a zoom button snapped the camera somewhere else.
    func testResetAlwaysLandsInsideTheRange() {
        for home in [0.14, 0.30, 0.85, 1.60, 5.20] {
            let limits = stage.containing(home)
            XCTAssertEqual(StageCamera.clamped(home, to: limits), home,
                           accuracy: 1e-12, "reset to \(home) was clamped away")
        }
    }

    func testOneButtonNotchIsOnePinchNotch() {
        for distance in stride(from: 0.15, through: 4.5, by: 0.05) {
            XCTAssertEqual(StageCamera.zoomed(distance, by: StageCamera.zoomNotch, to: stage),
                           StageCamera.clamped(distance / StageCamera.zoomNotch, to: stage),
                           accuracy: 1e-12, "at \(distance)")
        }
    }

    func testEachEndOfTheRangeIsNamed() {
        XCTAssertEqual(StageCamera.stop(at: stage.nearest, in: stage), .nearest)
        XCTAssertEqual(StageCamera.stop(at: stage.farthest, in: stage), .farthest)
        XCTAssertEqual(StageCamera.stop(at: (stage.nearest + stage.farthest) / 2, in: stage),
                       .free)
    }

    func testTheButtonsRefuseOnlyAtTheStops() {
        XCTAssertFalse(StageCamera.canZoom(inward: true, from: 0.20, to: stage))
        XCTAssertTrue(StageCamera.canZoom(inward: false, from: 0.20, to: stage))
        XCTAssertFalse(StageCamera.canZoom(inward: false, from: 4.0, to: stage))
        XCTAssertTrue(StageCamera.canZoom(inward: true, from: 4.0, to: stage))
        XCTAssertTrue(StageCamera.canZoom(inward: true, from: 0.85, to: stage))
        XCTAssertTrue(StageCamera.canZoom(inward: false, from: 0.85, to: stage))
    }

    func testANonsenseScaleMovesNothing() {
        XCTAssertEqual(StageCamera.zoomed(0.85, by: 0, to: stage), 0.85)
        XCTAssertEqual(StageCamera.zoomed(0.85, by: .nan, to: stage), 0.85)
        XCTAssertEqual(StageCamera.zoomed(0.85, by: -1, to: stage), 0.85)
        XCTAssertEqual(StageCamera.clampedElevation(.nan), StageCamera.defaultElevation)
        XCTAssertEqual(StageCamera.clampedElevation(9), StageCamera.elevationCeiling)
        XCTAssertEqual(StageCamera.clampedElevation(-9), StageCamera.elevationFloor)
    }

    /// THE READOUT NAMES THE AIM POINT AND NOT THE DUCK, because on two of the
    /// three stages that draw it the camera is aimed at a focus or at a scene's
    /// bounding box and "850 mm from the duck" would be false.
    func testTheReadoutNamesTheAimPointAndNotTheDuck() {
        XCTAssertEqual(StageCamera.framingSaid(distanceMetres: 0.85, home: nil),
                       "camera 850 mm from what it is aimed at")
        XCTAssertEqual(StageCamera.framingSaid(distanceMetres: 0.425, home: 0.85),
                       "camera 425 mm from what it is aimed at · "
                     + "2.0× closer than this stage opened on")
        XCTAssertEqual(StageCamera.framingSaid(distanceMetres: 0.85, home: 0.85),
                       "camera 850 mm from what it is aimed at · "
                     + "the framing this stage opened on")
        XCTAssertEqual(StageCamera.framingSaid(distanceMetres: 1.70, home: 0.85),
                       "camera 1700 mm from what it is aimed at · "
                     + "2.0× further back than this stage opened on")
        for said in [StageCamera.framingSaid(distanceMetres: 0.85, home: nil),
                     StageCamera.framingSaid(distanceMetres: 0.425, home: 0.85),
                     StageCamera.framingSaid(distanceMetres: 1.70, home: 0.85)] {
            XCTAssertFalse(said.contains("duck"), "\(said) claims a distance to the robot")
        }
    }

    func testTheStopSentencesSayWhyAndClaimNothingElse() {
        XCTAssertTrue(StageCamera.nearestSaid.contains("as close as the whole robot fits"))
        XCTAssertTrue(StageCamera.nearStopSaid.contains("200 mm"))
        XCTAssertFalse(StageCamera.nearStopSaid.contains("fits"),
                       "an un-fitted stop must not claim a fit")
        XCTAssertTrue(StageCamera.farthestSaid
            .contains("does not say the whole scene is in the picture"))
        for said in [StageCamera.nearestSaid, StageCamera.farthestSaid] {
            XCTAssertFalse(said.contains("error"))
            XCTAssertFalse(said.contains("unsupported"))
        }
    }

    /// THE PIN THAT STOPS THE NEW COLUMN AND THE LEGEND'S CHIP SPELLING ONE
    /// STATE TWO WAYS. These ten are exactly what `DuckStage` draws today, at
    /// its accessibility actions and at the camera chip.
    func testTheCameraWordsAreOnePairEverywhere() {
        XCTAssertEqual(StageCamera.words,
                       ["Zoom in", "Zoom out", "Reset the view",
                        "Orbit left", "Orbit right",
                        "Look from higher", "Look from lower",
                        "Camera", "Following", "Fixed"])
        XCTAssertEqual(Set(StageCamera.words).count, 10, "one of the ten is spelled twice")
    }

    /// The near stop a measured glass gives is exactly the one the occlusion
    /// maths solved — one law, in one place, and not a second clamp beside it.
    func testTheFittedLimitsNeverPutTheColumnOverTheDuck() {
        for glass in [StageViewport.Glass(351, 300), StageViewport.Glass(393, 534),
                      StageViewport.Glass(700, 320), StageViewport.Glass(351, 220)] {
            let fitted = StageCamera.Limits.fitting(glass, home: nil)
            XCTAssertEqual(fitted.nearest, StageViewport.nearestDistance(glass), accuracy: 1e-12)
            XCTAssertEqual(fitted.farthest, StageCamera.farStopFloor)
            XCTAssertFalse(StageViewport.clearance(glass, at: fitted.nearest).coversTheDuck)
        }
    }

    /// A FITTED RANGE STILL CONTAINS THE FRAMING THE STAGE OPENED ON. The editor
    /// frames the duck and the first riser at about half a metre; a fitted near
    /// stop further out than that would refuse the view the screen opened with.
    func testAFittedRangeStillHoldsTheOpeningFraming() {
        let glass = StageViewport.Glass(351, 220)
        let home = 0.30
        let fitted = StageCamera.Limits.fitting(glass, home: home)
        XCTAssertLessThanOrEqual(fitted.nearest, home)
        XCTAssertEqual(StageCamera.clamped(home, to: fitted), home, accuracy: 1e-12)
    }
}

/// Framing a run that has already happened.
///
/// THE BUG THESE EXIST FOR. The Control tab plays a clip under the camera it
/// drives with, which follows the trunk — so the travel, which is most of what
/// a motion IS, is subtracted from the picture before it is drawn. Three
/// separate fixes went looking for it in the bench, in the request and in the
/// playback loop; the bench was answering the same bytes to both tabs the whole
/// time. Each of these must be able to FAIL: a framing that ignores the travel
/// passes none of them.
final class StageCameraRunFramingTests: XCTestCase {

    private let phone = StageViewport.Glass(393, 740)

    private func run(_ points: [(Double, Double, Double)])
        -> [(x: Double, y: Double, z: Double)] {
        points.map { (x: $0.0, y: $0.1, z: $0.2) }
    }

    func testAnEmptyRunHasNothingToLookAt() {
        XCTAssertNil(StageCamera.framing(forRun: [], on: phone))
    }

    func testAStillRunIsFramedAtTheDefaultDistance() {
        let framing = StageCamera.framing(forRun: run([(0, 0.09, 0), (0, 0.09, 0)]),
                                          on: phone)
        XCTAssertEqual(framing?.distance, StageCamera.defaultDistance)
        XCTAssertEqual(framing?.reaches, true)
    }

    /// THE ONE THAT WOULD HAVE CAUGHT IT. Travel has to move the answer.
    func testTravelStandsTheCameraFurtherBack() {
        let near = StageCamera.framing(forRun: run([(0, 0.09, 0), (0.1, 0.09, 0)]), on: phone)
        let far  = StageCamera.framing(forRun: run([(0, 0.09, 0), (1.2, 0.09, 0)]), on: phone)
        XCTAssertNotNil(near); XCTAssertNotNil(far)
        XCTAssertGreaterThan(far!.distance, near!.distance)
    }

    /// AND THE WHOLE RUN IS ACTUALLY ON THE GLASS at the distance it answers,
    /// robot included — not merely "further back than before".
    func testTheWholeTravelFitsTheGlass() {
        let travel = 0.9
        let framing = StageCamera.framing(forRun: run([(0, 0.09, 0), (travel, 0.09, 0)]),
                                          on: phone,
                                          within: StageCamera.Limits(nearest: 0.2,
                                                                     farthest: 40))
        let framed = try! XCTUnwrap(framing)
        XCTAssertTrue(framed.reaches)
        XCTAssertGreaterThanOrEqual(phone.visibleWidthMetres(at: framed.distance),
                                    travel + DuckScene.duckStandingHeight - 1e-9)
    }

    /// A RUN ALONG z IS THE SAME RUN. The person may have orbited the stage to
    /// any azimuth, so the answer cannot depend on which axis the duck walked.
    func testTheAxisTheDuckWalkedDoesNotChangeTheAnswer() {
        let alongX = StageCamera.framing(forRun: run([(0, 0.09, 0), (0.8, 0.09, 0)]), on: phone)
        let alongZ = StageCamera.framing(forRun: run([(0, 0.09, 0), (0, 0.09, 0.8)]), on: phone)
        XCTAssertEqual(alongX?.distance, alongZ?.distance)
    }

    /// THE AIM POINT IS THE MIDDLE OF THE TRAVEL, which is the half a following
    /// camera gets wrong even when the distance is right.
    func testTheCameraLooksAtTheMiddleOfTheRun() {
        let framing = StageCamera.framing(forRun: run([(0, 0.09, 0), (1.0, 0.09, 0.4)]),
                                          on: phone)
        XCTAssertEqual(framing?.x ?? .nan, 0.5, accuracy: 1e-12)
        XCTAssertEqual(framing?.z ?? .nan, 0.2, accuracy: 1e-12)
    }

    /// NEVER THE FLOOR. A run that never leaves the ground has a midpoint at
    /// ankle height, and a camera aimed there is aimed under the duck.
    func testTheAimPointIsNeverBelowTheRobotsMiddle() {
        let framing = StageCamera.framing(forRun: run([(0, 0, 0), (0.3, 0.01, 0)]), on: phone)
        XCTAssertEqual(framing?.y ?? .nan,
                       DuckScene.duckStandingHeight / 2, accuracy: 1e-12)
    }

    /// A CLIMB IS TRAVEL TOO. Height has to count, or a duck going up a
    /// staircase is framed as though it stood still.
    func testRisingCountsAsTravel() {
        let flat    = StageCamera.framing(forRun: run([(0, 0.09, 0), (0.05, 0.09, 0)]), on: phone)
        let climbed = StageCamera.framing(forRun: run([(0, 0.09, 0), (0.05, 1.10, 0)]), on: phone)
        XCTAssertGreaterThan(climbed!.distance, flat!.distance)
    }

    /// AND WHEN THE STAGE CANNOT REACH, IT SAYS SO rather than answering a
    /// distance that quietly does not contain the run.
    func testARunTooBigForTheStageSaysItDoesNotReach() {
        let framing = StageCamera.framing(forRun: run([(0, 0.09, 0), (60, 0.09, 0)]),
                                          on: phone, within: .stage)
        XCTAssertEqual(framing?.distance, StageCamera.farStopFloor)
        XCTAssertEqual(framing?.reaches, false)
    }

    /// A TALLER, NARROWER GLASS NEEDS MORE ROOM for the same sideways travel,
    /// because the horizontal field is the vertical one times the aspect.
    func testANarrowerGlassStandsFurtherBackForTheSameTravel() {
        let wide = StageViewport.Glass(900, 600)
        let tall = StageViewport.Glass(400, 900)
        let path = run([(0, 0.09, 0), (1.0, 0.09, 0)])
        let a = StageCamera.framing(forRun: path, on: wide,
                                    within: StageCamera.Limits(nearest: 0.2, farthest: 40))
        let b = StageCamera.framing(forRun: path, on: tall,
                                    within: StageCamera.Limits(nearest: 0.2, farthest: 40))
        XCTAssertGreaterThan(b!.distance, a!.distance)
    }
}
