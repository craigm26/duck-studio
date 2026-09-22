import XCTest
@testable import StudioKit

final class DetailLevelTests: XCTestCase {

    /// Everything shows everything. If this ever fails, Full has started
    /// hiding something and the level has become a second release gate.
    func testFullShowsEverySurface() {
        for surface in DetailLevel.Surface.allCases {
            XCTAssertTrue(DetailLevel.full.shows(surface), surface.rawValue)
        }
        XCTAssertNil(DetailLevel.full.withheldNote)
    }

    func testSimpleHidesTheNetworkScreens() {
        for surface in DetailLevel.Surface.allCases {
            XCTAssertFalse(DetailLevel.simple.shows(surface), surface.rawValue)
        }
    }

    /// AN UPDATE MUST NOT TAKE SOMETHING AWAY. Everybody holding this app today
    /// installed it for the inspector; defaulting them into Simple would remove
    /// the reason they have it without asking.
    func testTheDefaultIsEverything() {
        XCTAssertEqual(DetailLevel.installedDefault, .full)
    }

    /// Hiding a screen silently is how somebody concludes a feature was
    /// removed. Simple has to name what it is holding back AND the way back.
    func testSimpleNamesWhatItHidesAndWhereTheSwitchIs() {
        let note = try? XCTUnwrap(DetailLevel.simple.withheldNote)
        let text = note ?? ""
        for surface in DetailLevel.Surface.allCases {
            XCTAssertTrue(text.contains(surface.name), "should name \(surface.name)")
        }
        XCTAssertTrue(text.contains("Settings"), "should say where the switch is")
    }

    func testAHiddenSectionLeavesASentenceThatNamesItself() {
        let text = DetailLevel.placeholder(for: .networkInternals)
        XCTAssertTrue(text.contains("Network internals"))
        XCTAssertTrue(text.contains("Simple"))
        XCTAssertTrue(text.contains("Settings"))
    }

    /// The line is drawn at screens only legible if you know what a policy is.
    /// Driving, modes, scenes and drafting are for anybody with a duck, and
    /// there is deliberately no surface for them to hide behind.
    func testThereIsNoSurfaceForTheThingsEverybodyWants() {
        let hidden = Set(DetailLevel.Surface.allCases.map(\.rawValue))
        for everyday in ["control", "modes", "scenes", "drafting", "motions"] {
            XCTAssertFalse(hidden.contains(everyday),
                           "\(everyday) must not be something Simple can hide")
        }
    }

    /// It is stored, so it has to survive a round trip.
    func testItRoundTrips() throws {
        for level in DetailLevel.allCases {
            let data = try JSONEncoder().encode(level)
            XCTAssertEqual(try JSONDecoder().decode(DetailLevel.self, from: data), level)
        }
        XCTAssertEqual(DetailLevel(rawValue: "simple"), .simple)
    }

    func testEverySurfaceHasAReadableName() {
        for surface in DetailLevel.Surface.allCases {
            XCTAssertFalse(surface.name.isEmpty)
            XCTAssertFalse(surface.name.contains("_"), "\(surface.rawValue) needs prose")
        }
    }
}
