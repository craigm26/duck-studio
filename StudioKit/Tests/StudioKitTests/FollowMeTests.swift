import XCTest
@testable import StudioKit

final class FollowMeTests: XCTestCase {

    /// The fact the mode is built to deliver.
    func testAPersonWalksThirteenTimesFasterThanTheDuck() {
        XCTAssertEqual(FollowMe.paceRatio(.measured), 13.2, accuracy: 0.2)
        XCTAssertEqual(FollowMe.paceRatio(.skates), 3.1, accuracy: 0.2)
    }

    func testItClosesToStandoffAndStops() {
        var follow = FollowMe(duck: .init(position: .init(0, 0), heading: 0))
        let person = DuckSoccer.Vec2(2.0, 0)
        for _ in 0..<3000 { follow.advance(dt: 0.02, person: person) }
        XCTAssertEqual(follow.range, FollowMe.standoff, accuracy: FollowMe.hysteresis + 0.02)
        XCTAssertFalse(follow.isWalking)
        XCTAssertEqual(follow.lost, 0, accuracy: 1e-9)
    }

    /// It cannot creep. Every tick either covers a full walking step or none —
    /// there is no intermediate speed, because the policy has no intermediate
    /// command.
    func testThereIsNoSlowFollowOnlyStopAndGo() {
        var follow = FollowMe(duck: .init(position: .init(0, 0), heading: 0))
        var person = DuckSoccer.Vec2(0.5, 0)
        var speeds: Set<Int> = []
        for _ in 0..<1500 {
            person = person + DuckSoccer.Vec2(0.02 * 0.02, 0)   // 0.02 m/s: a shuffle
            let before = follow.duck.position
            follow.advance(dt: 0.02, person: person)
            let moved = (follow.duck.position - before).length / 0.02
            speeds.insert(Int((moved * 1000).rounded()))
        }
        // Millimetre-per-second buckets: standing still, or the walk. Nothing
        // in between, and nothing slower than the dead band would allow.
        XCTAssertTrue(speeds.isSubset(of: [0, 106]), "observed \(speeds.sorted())")
        XCTAssertTrue(speeds.contains(0))
        XCTAssertTrue(speeds.contains(106))
    }

    func testItLosesAPersonWalkingAtHumanPace() {
        var follow = FollowMe(duck: .init(position: .init(0, 0), heading: 0))
        var person = DuckSoccer.Vec2(0.5, 0)
        for _ in 0..<500 {                       // ten seconds
            person = person + DuckSoccer.Vec2(FollowMe.humanPace * 0.02, 0)
            follow.advance(dt: 0.02, person: person)
        }
        XCTAssertTrue(follow.hasLostYou)
        XCTAssertGreaterThan(follow.range, 10.0)
    }

    /// And keeps one who walks slower than it does.
    func testItKeepsUpWithSomeoneWalkingSlowerThanItDoes()  {
        var follow = FollowMe(duck: .init(position: .init(0, 0), heading: 0))
        var person = DuckSoccer.Vec2(0.5, 0)
        for _ in 0..<1500 {                      // thirty seconds at 0.09 m/s
            person = person + DuckSoccer.Vec2(0.09 * 0.02, 0)
            follow.advance(dt: 0.02, person: person)
        }
        XCTAssertFalse(follow.hasLostYou)
        XCTAssertGreaterThan(follow.inStation / follow.elapsed, 0.9)
    }

    /// Someone standing behind it is reached on an arc: the duck never turns
    /// without also travelling, because turning on the spot is the one thing
    /// it cannot do.
    func testItComesRoundOnAnArcNeverOnTheSpot() {
        var follow = FollowMe(duck: .init(position: .init(0, 0), heading: 0))
        let person = DuckSoccer.Vec2(-1.2, 0.05)
        var pivots = 0
        for _ in 0..<3000 {
            let heading = follow.duck.heading, position = follow.duck.position
            follow.advance(dt: 0.02, person: person)
            let turned = abs(follow.duck.heading - heading) > 1e-9
            let moved = (follow.duck.position - position).length > 1e-9
            if turned && !moved { pivots += 1 }
        }
        XCTAssertEqual(pivots, 0)
        XCTAssertLessThan(follow.range, FollowMe.standoff + 0.2)
    }
}
