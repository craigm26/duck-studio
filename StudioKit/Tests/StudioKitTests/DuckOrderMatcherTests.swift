import XCTest
import DuckKit
@testable import StudioKit

final class DuckOrderMatcherTests: XCTestCase {

    let skills = ["kick_left", "kick_right", "roulade", "sit_toggle", "happy", "pick_up"]

    func m(_ s: String) -> StudioKit.DuckOrder? {
        DuckOrderMatcher.match(s, skills: skills, names: ["Puddle"])
    }

    func testStop() {
        for s in ["stop", "Stop the duck!", "freeze", "no", "No, sit down", "halt"] {
            XCTAssertEqual(m(s), .stop, s)
        }
        XCTAssertNotEqual(m("start the stopwatch"), .stop)
    }

    func testSitAndStand() {
        XCTAssertEqual(m("sit"), .sit)
        XCTAssertEqual(m("Sit down, please."), .sit)
        XCTAssertEqual(m("Puddle, sit down"), .sit)
        XCTAssertEqual(m("stand up"), .stand)
        XCTAssertEqual(m("Wake up the duck"), .stand)
        XCTAssertEqual(m("get up"), .stand)
        XCTAssertNil(m("sit on the ball"))
    }

    func testSkillsByNameFromTheList() {
        XCTAssertEqual(m("kick left"), .skill("kick_left"))
        XCTAssertEqual(m("left kick"), .skill("kick_left"))
        XCTAssertEqual(m("do a roulade"), .skill("roulade"))
        XCTAssertEqual(m("Pick up"), .skill("pick_up"))
        XCTAssertEqual(m("be happy"), nil)
        XCTAssertEqual(m("happy"), .skill("happy"))
        // Two kicks: "kick" alone is a guess, so nil.
        XCTAssertNil(m("kick"))
        // Not on this duck's list.
        XCTAssertNil(DuckOrderMatcher.match("roulade", skills: ["kick_left"]))
        // sit_toggle is read only as sit or stand.
        XCTAssertNil(DuckOrderMatcher.match("sit toggle", skills: ["sit_toggle"]))
    }

    func testSounds() {
        XCTAssertEqual(m("quack"), .sound(.chirp))
        XCTAssertEqual(m("Quack, duck!"), .sound(.chirp))
        XCTAssertEqual(m("make a honk sound"), .sound(.alarm))
        XCTAssertEqual(m("play coo"), .sound(.coo))
        XCTAssertNil(m("quack and honk"))
    }

    func testLook() {
        XCTAssertEqual(m("look at me"), .look(.me))
        XCTAssertEqual(m("Look here"), .look(.ahead))
        XCTAssertEqual(m("look ahead"), .look(.ahead))
        // v1 aims level only; a side look is not this command.
        XCTAssertNil(m("look left"))
    }

    func testOneWalkThroughDuckTalk() {
        XCTAssertEqual(m("walk forward"), .walk(.forward, seconds: 1))
        XCTAssertEqual(m("go back for two seconds"), .walk(.back, seconds: 2))
        XCTAssertEqual(m("Puddle, turn left for 3 seconds"), .walk(.turnLeft, seconds: 3))
        // Clamped to the command's five seconds.
        XCTAssertEqual(m("forward for ten seconds"), .walk(.forward, seconds: 5))
    }

    func testUnsureIsNil() {
        for s in ["", "   ", "forward then turn left", "walk forward gently", "turn left 90 degrees",
                  "turn 90°", "go get the ball", "dance like nobody is watching", "walk to the kitchen",
                  "forward quickly", "the"] {
            XCTAssertNil(m(s), s)
        }
    }
}
