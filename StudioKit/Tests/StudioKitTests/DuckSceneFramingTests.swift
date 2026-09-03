import XCTest
import DuckKit
@testable import StudioKit

/// The camera's framing, once a stage can be a shape other than the one it
/// shipped as.
///
/// THE PRECONDITION THAT WENT AWAY IS THE WHOLE SUBJECT HERE. `authoringFraming`
/// solved the distance against the VERTICAL field on the written ground that
/// "the stage is at least as wide as it is tall on every phone". That was true
/// of a 351 × 300 card and stops being true the moment somebody can make the
/// picture taller — and what falls off the side first is the first riser, which
/// is the one thing this framing exists to hold.
final class DuckSceneFramingTests: XCTestCase {

    /// The shape a phone's stage takes once it can grow: portrait glass, square
    /// glass, and a landscape iPad. 0.56 is a 371 × 660 stage — a full-bleed
    /// picture on a 6.1" phone.
    private let aspects = [0.50, 0.56, 0.74, 1.00, 1.60, 2.20]

    private var halfV: Double { DuckScene.authoringFieldOfView / 2 }
    private func halfH(_ aspect: Double) -> Double { atan(tan(halfV) * max(aspect, 0.01)) }

    /// The stair scene the app actually ships the editor against.
    private func stairs() -> DuckScene {
        DuckScene.stairsChallenge(rise: StairsChallenge.defaultRise, count: 4)
    }

    /// The two half-extents the framing has to hold, recomputed here rather
    /// than read off the type — a test that asked the code for its own inputs
    /// would pass whatever the code did with them.
    private func extents(_ scene: DuckScene) -> (across: Double, up: Double) {
        let first = scene.steps.min(by: { $0.x < $1.x })!
        let face = first.x - first.halfDepth
        let targetX = face / 2
        let targetZ = (first.top + DuckKinematics.trunkOriginInModelFrame.z) / 2
        let across = max(abs(face - targetX), abs(targetX)) + DuckScene.duckHalfSpan
        let elevation = DuckScene.authoringElevation
        let up = max(abs(DuckScene.duckStandingHeight - targetZ), abs(targetZ)) * cos(elevation)
               + DuckScene.duckHalfSpan * sin(elevation)
        return (across, up)
    }

    /// A square stage is the framing that shipped, for every scene the app has.
    /// GUARDS `DuckWorld.swift` AND THE FOUR `ChallengeSceneTests` CALLERS,
    /// which all read the property and must keep getting the same four numbers.
    func testASquareStageIsTheFramingThatShipped() {
        var checked = 0
        for scene in DuckScene.starters {
            XCTAssertEqual(scene.authoringFraming(aspect: 1), scene.authoringFraming,
                           "starter '\(scene.name)' moved at aspect 1")
            checked += 1
        }
        for rise in StairsChallenge.rises {
            let scene = DuckScene.stairsChallenge(rise: rise, count: 4)
            XCTAssertEqual(scene.authoringFraming(aspect: 1), scene.authoringFraming,
                           "the \(rise) m flight moved at aspect 1")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 5, "a pass over nothing is not a pass")
    }

    /// THE ONE THAT HAD TO BE WATCHED GO RED. Against the shipped expression
    /// — `max(across, up) / tan(halfV)` — this fails at 0.50, 0.56 and 0.74,
    /// because the horizontal half-angle on a tall stage is a fraction of the
    /// vertical one and the riser face is the thing that leaves the frame.
    func testTheFirstRiserIsInsideTheFrameAtEveryStageShape() throws {
        let scene = stairs()
        let (across, up) = extents(scene)
        for aspect in aspects {
            let framing = try XCTUnwrap(scene.authoringFraming(aspect: aspect))
            let reach = framing.distance / DuckScene.authoringMargin
            XCTAssertLessThanOrEqual(across, reach * tan(halfH(aspect)) + 1e-9,
                "the first riser is off the SIDE at aspect \(aspect): "
              + "across \(across) m against \(reach * tan(halfH(aspect))) m of half-frame")
            XCTAssertLessThanOrEqual(up, reach * tan(halfV) + 1e-9,
                "the duck's head is off the TOP at aspect \(aspect): "
              + "up \(up) m against \(reach * tan(halfV)) m of half-frame")
        }
    }

    /// A taller stage stands further back, and it is the HORIZONTAL axis that
    /// puts it there.
    ///
    /// THE PLAN ASKED FOR A RATIO THIS SCENE DOES NOT HAVE, and the number is
    /// worth writing down rather than loosening a tolerance around. §C.4 wanted
    /// `distance(0.56) / distance(1)` within 2% of `tan(halfV)/tan(halfH)`, i.e.
    /// 1.786. It is 1.129, and that is correct: at aspect 1 the framing is bound
    /// by the VERTICAL extent (`up` 0.1207 m against `across` 0.1037 m), so the
    /// square distance is not the horizontal bound scaled — the two axes swap
    /// which one binds on the way to 0.56. The field ratio is therefore a
    /// CEILING on the growth, not the growth, and the exact claim is the one
    /// below: at 0.56 the distance is precisely the horizontal solution.
    func testATallStageStandsFurtherBack() throws {
        let scene = stairs()
        let (across, up) = extents(scene)
        XCTAssertGreaterThan(up, across, "at aspect 1 the vertical extent is the binding one")
        let square = try XCTUnwrap(scene.authoringFraming(aspect: 1)).distance
        let tall = try XCTUnwrap(scene.authoringFraming(aspect: 0.56)).distance
        XCTAssertGreaterThan(tall, square)
        XCTAssertEqual(tall, across / tan(halfH(0.56)) * DuckScene.authoringMargin,
                       accuracy: 1e-9)
        XCTAssertLessThanOrEqual(tall / square, tan(halfV) / tan(halfH(0.56)) + 1e-9)
    }

    /// A WIDE STAGE IS BOUND BY THE VERTICAL FIELD, which is the case the old
    /// expression was written for and still gets right.
    func testAWideStageIsBoundedByTheVerticalField() throws {
        let scene = stairs()
        let (_, up) = extents(scene)
        let framing = try XCTUnwrap(scene.authoringFraming(aspect: 2.2))
        XCTAssertEqual(framing.distance,
                       up / tan(halfV) * DuckScene.authoringMargin, accuracy: 1e-9)
    }

    /// Only the DISTANCE moves with the shape. Making the picture bigger must
    /// not swing the camera onto a different part of the scene.
    func testTheTargetAndElevationDoNotDependOnShape() throws {
        let scene = stairs()
        let base = try XCTUnwrap(scene.authoringFraming(aspect: 1))
        for aspect in aspects {
            let framing = try XCTUnwrap(scene.authoringFraming(aspect: aspect))
            XCTAssertEqual(framing.targetX, base.targetX, accuracy: 1e-12, "at \(aspect)")
            XCTAssertEqual(framing.targetZ, base.targetZ, accuracy: 1e-12, "at \(aspect)")
            XCTAssertEqual(framing.elevation, base.elevation, "at \(aspect)")
        }
    }

    /// A scene with nothing in it has no opinion at any shape, including the
    /// degenerate one a `GeometryReader` hands over before layout has happened.
    func testABareFloorHasNoFramingAtAnyAspect() {
        for aspect in aspects + [0, -1] {
            XCTAssertNil(DuckScene.bareFloor().authoringFraming(aspect: aspect),
                         "bare floor invented a framing at aspect \(aspect)")
        }
    }
}
