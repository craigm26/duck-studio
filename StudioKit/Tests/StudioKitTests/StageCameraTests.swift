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
