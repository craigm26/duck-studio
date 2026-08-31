import XCTest
import DuckKit
@testable import StudioKit

/// A draft carries joints and no root, so the stage decides where the body
/// goes. It used to pin the trunk at standing height, which drew `sit` with its
/// feet 55 mm in the air and looked exactly like broken data.
final class StageFloorTests: XCTestCase {

    private let pinned = DuckIntentClip.Root(x: 0, y: 0, z: 0.11622, quaternion: (1, 0, 0, 0))

    /// THE MEASURED CASE. `sit`'s last frame reads +0.0549 m of clearance under
    /// a pinned trunk — measured against the real meshes by
    /// `DuckGroundClearance` — because the real motion lowered the body 56.9 mm.
    /// Resting it drops the trunk by exactly that.
    func testAPoseThatFloatsIsDroppedOntoTheFloor() {
        let rested = StageFloor.resting(pinned, clearanceMetres: 0.0549)
        XCTAssertEqual(rested.z, 0.11622 - 0.0549, accuracy: 1e-9)
        XCTAssertEqual(rested.x, pinned.x)
        XCTAssertEqual(rested.y, pinned.y)
        XCTAssertEqual(rested.quaternion.0, pinned.quaternion.0)
    }

    /// A pose already on the floor is left where it is — the four clips that do
    /// not change body height all read within 2 mm pinned, and must not be
    /// nudged.
    func testAPoseAlreadyOnTheFloorIsBarelyMoved() {
        let rested = StageFloor.resting(pinned, clearanceMetres: -0.0008)
        XCTAssertEqual(rested.z, 0.11622 + 0.0008, accuracy: 1e-9)
    }

    /// A pose whose lowest point is BELOW the floor comes up, not down.
    func testAPoseSunkIntoTheFloorIsLifted() {
        let rested = StageFloor.resting(pinned, clearanceMetres: -0.02)
        XCTAssertGreaterThan(rested.z, pinned.z)
    }

    /// NO SILENT NONSENSE. A clearance that is not a number means the mesh
    /// probe could not answer, and the honest response is to leave the root
    /// alone rather than move the duck to NaN.
    func testAnUnmeasurableClearanceLeavesTheRootAlone() {
        XCTAssertEqual(StageFloor.resting(pinned, clearanceMetres: .nan).z, pinned.z)
        XCTAssertEqual(StageFloor.resting(pinned, clearanceMetres: .infinity).z, pinned.z)
    }

    // MARK: - what the caption says

    /// THE SAME MEASUREMENT, STATED AS THE FACT. "55 mm above the grid" reads
    /// as a fault; "55 mm below standing" is what actually happened.
    func testASeatedPoseIsDescribedAsLowerRatherThanFloating() {
        let s = StageCaption.restedGround(dropMetres: 0.0549)
        XCTAssertTrue(s.contains("Feet on the floor"), s)
        XCTAssertTrue(s.contains("55 mm below standing"), s)
        XCTAssertFalse(s.contains("above the grid"), s)
        XCTAssertTrue(s.contains("legs are folded, not the ground moved"), s)
    }

    func testAPoseAtStandingHeightSaysSo() {
        XCTAssertEqual(StageCaption.restedGround(dropMetres: 0.001),
                       "Feet on the floor, at about standing height.")
    }

    func testAPoseReachingUpwardIsDescribedAsSuch() {
        XCTAssertTrue(StageCaption.restedGround(dropMetres: -0.03).contains("above standing"))
    }

    /// THE PINNED SENTENCE STAYS. It is still what a stage with a real recorded
    /// root should say, and deleting it would take the old floating-build guard
    /// with it.
    func testThePinnedSentenceIsStillAvailable() {
        XCTAssertTrue(StageCaption.pinnedGround(clearanceMetres: 0.0549)
                        .contains("above the grid"))
    }
}
