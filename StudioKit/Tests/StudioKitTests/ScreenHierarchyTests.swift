import XCTest
@testable import StudioKit

final class ScreenHierarchyTests: XCTestCase {

    func testTodayIsWellFormed() {
        XCTAssertEqual(ScreenHierarchy.problems(ScreenHierarchy.today), [])
    }

    func testTargetIsWellFormed() {
        XCTAssertEqual(ScreenHierarchy.problems(ScreenHierarchy.target), [])
    }

    /// The checks can fail: a tree with a duplicated id, an untagged target
    /// node and a missing opening tab is reported.
    func testProblemsAreReported() {
        let bad = ScreenHierarchy.Tree(
            name: "bad",
            tabs: [.init("a", "A", [.init("x", "X", .keep), .init("x", "Y")])],
            opensOn: "b", sheets: [])
        let found = ScreenHierarchy.problems(bad)
        XCTAssertTrue(found.contains("node x used twice"), "\(found)")
        XCTAssertTrue(found.contains("node x has no tag"), "\(found)")
        XCTAssertTrue(found.contains("opens on b, not a tab"), "\(found)")
    }

    /// Today: AppTab's five cases in order, opening on Play.
    func testTodayMatchesAppTab() {
        let t = ScreenHierarchy.today
        XCTAssertEqual(t.tabs.map(\.id), ["control", "learn", "behaviours", "studio", "duck"])
        XCTAssertEqual(t.tabs.map(\.title), ["Play", "Learn", "Behaviours", "Studio", "My Microduck"])
        XCTAssertEqual(t.opensOn, "control")
        XCTAssertEqual(t.tab("learn")?.sections.first?.children.count, Learn.lessons.count)
    }

    /// Target: three tabs, Play, Moves, Studio, with `-tab control` and
    /// `-tab duck` still reaching Play and the old names reaching Studio.
    func testTargetIsThreeTabsAndKeepsTheOldNamesWorking() {
        let t = ScreenHierarchy.target
        XCTAssertEqual(t.tabs.map(\.id), ["play", "moves", "studio"])
        XCTAssertEqual(t.opensOn, "play")
        XCTAssertEqual(t.tab("control")?.id, "play")
        XCTAssertEqual(t.tab("duck")?.id, "play")
        XCTAssertEqual(t.tab("learn")?.id, "studio")
        XCTAssertEqual(t.tab("behaviours")?.id, "studio")
        XCTAssertEqual(t.tab("studio")?.sections.map(\.title),
                       ["Show expert tools", "Make", "Behaviours", "Train", "Measure", "Learn", "Settings"])
        XCTAssertEqual(t.sheets.map(\.id), ["welcome", "duckSheet"])
    }

    /// Stop is on Play in the target.
    func testTargetHasStopOnPlay() {
        let play = ScreenHierarchy.target.tab("play")!
        XCTAssertTrue(play.sections.contains { $0.id == "play.stop" })
    }

    /// Nothing today names disappears silently: every app file in today's
    /// tree has a home in the target, or a reason in `retired`.
    func testEveryScreenTodayHasAHomeOrAReason() {
        let homeless = ScreenHierarchy.today.sources
            .subtracting(ScreenHierarchy.target.sources)
        XCTAssertEqual(homeless, Set(ScreenHierarchy.retired.keys))
        for reason in ScreenHierarchy.retired.values { XCTAssertFalse(reason.contains("\u{2014}")) }
    }

    /// BUILD 91 FLIPS THIS. The app ships today's tree until then; when it
    /// ships the target, change `shipped` and the first assertion below.
    func testTheAppShipsTodaysTree() {
        XCTAssertEqual(ScreenHierarchy.shipped, ScreenHierarchy.today)
        XCTAssertNotEqual(ScreenHierarchy.differences(from: ScreenHierarchy.shipped,
                                                       to: ScreenHierarchy.target), [])
    }

    /// Every difference between today and the target, so a reviewer sees the
    /// whole move in one list.
    func testTheDifferencesFromTodayToTheTarget() {
        let diff = ScreenHierarchy.differences(from: ScreenHierarchy.today, to: ScreenHierarchy.target)
            .map(\.description)
        XCTAssertEqual(diff, [
            "tab control -> play",
            "-play: Venue switch: Sim, Your floor, Robot",
            "-play: Link lens",
            "-play: Settings",
            "-play: Sticks and face buttons",
            "-play: Shelf chips: Pose, Scene, Mimic, Dream, Record, Sequences, Plan",
            "-play: Talk to the duck",
            "-play: Play drawer: layers, pad rest, Stop and Reset, pad map, controller",
            "-play: Pose bar",
            "-play: Mimic bar",
            "+play: Duck pill",
            "+play: Mode switch: Drive, Tell, Auto",
            "+play: Stop",
            "+play: Stick",
            "+play: Move buttons and mic",
            "+play: Head drag",
            "+play: Second Stop while Auto runs",
            "+play: Readout chip",
            "+play: Moves sheet",
            "+play: Pose",
            "+play: Tell",
            "+play: Auto goals",
            "+play: More",
            "-tab learn",
            "-tab behaviours",
            "tab studio 3 -> 2",
            "-studio: Play",
            "-studio: Train and measure",
            "-studio: Tools row (Simple), sends to Learn",
            "+studio: Show expert tools",
            "+studio: Behaviours",
            "+studio: Train",
            "+studio: Measure",
            "+studio: Learn",
            "-tab duck",
            "+tab moves",
            "-sheet firstRun",
            "+sheet welcome",
            "+sheet duckSheet",
        ])
    }

    func testNothingToDifferFromItself() {
        XCTAssertEqual(ScreenHierarchy.differences(from: ScreenHierarchy.target, to: ScreenHierarchy.target), [])
        XCTAssertEqual(ScreenHierarchy.differences(from: ScreenHierarchy.today, to: ScreenHierarchy.today), [])
    }
}
