import XCTest
@testable import StudioKit

/// A world read twice is the same world.
///
/// THE BUG THESE EXIST FOR, WHICH SHIPPED. `DuckScene.Prop.id` defaults to a
/// fresh `UUID()`, `Prop`'s synthesised `==` compares it, and `DuckWorld.asProps`
/// minted its props on every single call. The Control tab's stage rebuilds its
/// RealityKit props only when `shownGraspables != graspables` — a guard that
/// could therefore never once short-circuit, so every body pass tore down and
/// regenerated every step box, every lip and every graspable. Standing still
/// that is invisible. Under a clip playing at fifty frames a second it is most
/// of the main thread, the playback drops the frames it cannot draw in time,
/// and a motion that ran correctly on the bench arrives on screen as three or
/// four lurches. The owner reported that three times as "it does not fully
/// execute", and the editor never showed it because its props list is empty.
final class WorldPropIdentityTests: XCTestCase {

    private func world() -> DuckWorld {
        DuckWorld(isSet: true, name: "bench", steps: [],
                  ball: DuckWorld.Point(x: 0.55, y: 0.1),
                  props: [DuckWorld.Seated(name: "block", x: 0.3, y: 0.2, kilograms: 0.2),
                          DuckWorld.Seated(name: "block", x: 0.5, y: 0.2, kilograms: 0.2),
                          DuckWorld.Seated(name: "cone", x: 0.1, y: 0.4, kilograms: 0.1)])
    }

    /// THE ONE THAT WOULD HAVE CAUGHT IT.
    func testReadingTheSameWorldTwiceGivesEqualProps() {
        let read = world()
        XCTAssertEqual(read.asProps, read.asProps)
    }

    /// AND EQUAL ALL THE WAY DOWN, id included — because `==` compares the id
    /// and the renderer's guard is `==`.
    func testThePropIdsAreStableAcrossReads() {
        let read = world()
        XCTAssertEqual(read.asProps.map(\.id), read.asProps.map(\.id))
    }

    /// TWO BODIES WITH ONE NAME ARE STILL TWO PROPS. A name is not unique in a
    /// bench world, and two props sharing an id is the same bug in a hat.
    func testBodiesSharingANameDoNotShareAnID() {
        let props = world().asProps
        XCTAssertEqual(Set(props.map(\.id)).count, props.count)
    }

    /// A DIFFERENT WORLD IS DIFFERENT. A guard that never fires is as broken as
    /// one that always does: moving a block has to reach the picture.
    func testMovingABodyChangesTheProps() {
        let moved = DuckWorld(isSet: true, name: "bench", steps: [], ball: nil,
                              props: [DuckWorld.Seated(name: "block", x: 0.9, y: 0.2,
                                                       kilograms: 0.2)])
        let still = DuckWorld(isSet: true, name: "bench", steps: [], ball: nil,
                              props: [DuckWorld.Seated(name: "block", x: 0.3, y: 0.2,
                                                       kilograms: 0.2)])
        XCTAssertNotEqual(moved.asProps, still.asProps)
    }

    /// THE SECOND LOCK. `drawing` leaves the identity out, so a renderer can
    /// ask "does this look different?" without asking "is this the same
    /// object?" — and the next caller that mints a prop by hand cannot bring
    /// the frame cost back silently.
    func testTwoPropsThatLookTheSameHaveTheSameDrawing() {
        let a = DuckScene.ball(x: 0.2, y: 0.3)
        let b = DuckScene.ball(x: 0.2, y: 0.3)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.drawing, b.drawing)
    }

    func testADrawingStillNoticesAMove() {
        XCTAssertNotEqual(DuckScene.ball(x: 0.2, y: 0.3).drawing,
                          DuckScene.ball(x: 0.9, y: 0.3).drawing)
    }

    /// A DERIVED ID IS A FUNCTION OF ITS SEED, in this process and the next.
    /// `Hasher` is seeded per launch and would have passed the test above while
    /// failing this one.
    func testADerivedIDIsTheSameForTheSameSeed() {
        XCTAssertEqual(DuckScene.Prop.derivedID("world.0.block"),
                       DuckScene.Prop.derivedID("world.0.block"))
        XCTAssertNotEqual(DuckScene.Prop.derivedID("world.0.block"),
                          DuckScene.Prop.derivedID("world.1.block"))
    }
}

/// The same rule for a world that was LAID rather than read back.
///
/// `Pipeline.LaidWorld.asProps` feeds the pipeline card's stage and had the
/// identical defect: fresh ids on every call, so the renderer's memo could
/// never short-circuit there either.
final class LaidWorldPropIdentityTests: XCTestCase {

    private func laid() -> Pipeline.LaidWorld {
        Pipeline.LaidWorld(
            name: "stairs",
            steps: [], ball: nil,
            props: [Pipeline.LaidWorld.Seated(name: "block", x: 0.3, y: 0.2, kilograms: 0.2),
                    Pipeline.LaidWorld.Seated(name: "block", x: 0.6, y: 0.2, kilograms: 0.2)],
            notes: [], bankCount: 0, parked: 0, spawn: nil,
            sagMillimetres: nil, plantName: nil, plantDigest: nil)
    }

    func testLayingTheSameWorldTwiceGivesEqualProps() {
        let world = laid()
        XCTAssertEqual(world.asProps, world.asProps)
    }

    func testTwoLaidBodiesSharingANameDoNotShareAnID() {
        let props = laid().asProps
        XCTAssertEqual(Set(props.map(\.id)).count, props.count)
    }

    /// A LAID WORLD AND A READ-BACK WORLD ARE NOT THE SAME WORLD, so a block in
    /// one is not the same prop as a block in the other.
    func testALaidBlockIsNotAReadBackBlock() {
        XCTAssertNotEqual(DuckScene.Prop.derivedID("laid.0.block"),
                          DuckScene.Prop.derivedID("world.0.block"))
    }
}
