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

    /// BUILD 91 FLIPPED THIS: the app draws the target tree.
    func testTheAppShipsTheTarget() {
        XCTAssertEqual(ScreenHierarchy.shipped, ScreenHierarchy.target)
        XCTAssertEqual(ScreenHierarchy.differences(from: ScreenHierarchy.shipped,
                                                    to: ScreenHierarchy.target), [])
        XCTAssertNotEqual(ScreenHierarchy.differences(from: ScreenHierarchy.today,
                                                       to: ScreenHierarchy.shipped), [])
    }

    /// The `-tab` contract: by index, by name, and by the old names.
    func testLaunchByIndexAndByName() {
        let L = ScreenHierarchy.launch
        XCTAssertEqual(L(nil, ScreenHierarchy.shipped).tab, "play")
        XCTAssertEqual(L("0", ScreenHierarchy.shipped).tab, "play")
        XCTAssertEqual(L("1", ScreenHierarchy.shipped).tab, "moves")
        XCTAssertEqual(L("2", ScreenHierarchy.shipped).tab, "studio")
        XCTAssertEqual(L("play", ScreenHierarchy.shipped).tab, "play")
        XCTAssertEqual(L("moves", ScreenHierarchy.shipped).tab, "moves")
        XCTAssertEqual(L("studio", ScreenHierarchy.shipped).tab, "studio")
    }

    /// `-tab control` is an alias of Play; the old Learn and Behaviours names reach Studio;
    /// `-tab duck` opens Play with the Duck sheet up.
    func testTheOldTabNamesStillLand() {
        XCTAssertEqual(ScreenHierarchy.launch("control"), .init(tab: "play", duckSheet: false))
        XCTAssertEqual(ScreenHierarchy.launch("learn"), .init(tab: "studio", duckSheet: false))
        XCTAssertEqual(ScreenHierarchy.launch("behaviours"), .init(tab: "studio", duckSheet: false))
        XCTAssertEqual(ScreenHierarchy.launch("duck"), .init(tab: "play", duckSheet: true))
    }

    /// Anything else opens the first tab rather than failing: an index past the end (the old
    /// `-tab 3` and `-tab 4`), a negative one, a word that is no tab, and blank.
    func testAnUnknownLaunchOpensPlay() {
        for asked in ["3", "4", "-1", "robot", "", "  "] {
            XCTAssertEqual(ScreenHierarchy.launch(asked), .init(tab: "play", duckSheet: false), asked)
        }
    }

    /// Every feature of the inventory has a home that exists in the target, and Bench's only
    /// home is Measure.
    func testEveryFeatureHasAHomeInTheTarget() {
        let ids = Set(ScreenHierarchy.target.allNodes.map(\.id))
        for (feature, home) in ScreenHierarchy.inventory {
            XCTAssertTrue(ids.contains(home), "\(feature) -> \(home) is not a node")
            XCTAssertFalse(feature.contains("\u{2014}"))
        }
        XCTAssertEqual(ScreenHierarchy.inventory["Bench"], "studio.measure.benches")
        XCTAssertEqual(ScreenHierarchy.inventory.filter { $0.value.hasPrefix("studio.measure.benches") }.keys.sorted(),
                       ["Bench"])
        for named in ["Link lens", "Imports", "Head mode", "Dream key"] {
            XCTAssertNotNil(ScreenHierarchy.inventory[named], named)
        }
    }

    /// The tap-count table of the plan, at its targets: a game is one tap from Moves, and the
    /// real duck drives from Play with no taps after onboarding.
    func testGamesAreOneTapFromMoves() {
        let moves = ScreenHierarchy.target.tab("moves")!
        let games = moves.sections.first { $0.id == "moves.games" }
        XCTAssertNotNil(games)
        XCTAssertEqual(ScreenHierarchy.target.opensOn, "play")
        XCTAssertTrue(ScreenHierarchy.target.tab("play")!.sections.contains { $0.id == "play.stage" })
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
