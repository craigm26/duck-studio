import XCTest
@testable import StudioKit

/// The fourteen cells and the four constants the criterion is made of,
/// against the ball challenge's contract.
///
/// TRANSCRIBED HERE RATHER THAN REFERENCED, exactly as `StairsGridTests`
/// transcribes `robust.mjs`'s. The point of a pinned grid is that it is
/// checkable against something written down twice; a test that read the same
/// constant the code reads would pass on any pair of matching mistakes.
///
///   BEARINGS = [-20, 0, 20]      degrees, positive is LEFT
///   RANGES   = [0.45, 0.70, 0.95]  metres
///   nominal plant  drop 0.120, fmul 1.0
///   ext 1  bearing 0,   range 0.70, drop 0.130 / fmul 0.7
///   ext 2  bearing 0,   range 0.70, drop 0.125 / fmul 1.3
///   ext 3  bearing -40, range 0.70, nominal
///   ext 4  bearing +40, range 0.70, nominal
///   ext 5  bearing 0,   range 1.20, nominal
///   TOUCH_MM = 3.0  TRAVEL_MIN_MM = 100.0  TAIL_TICKS = 50  UPRIGHT_TAIL_MIN = 45
final class BallGridTests: XCTestCase {

    static let bearings: [Double] = [-20, 0, 20]
    static let ranges: [Double] = [0.45, 0.70, 0.95]
    static let nominal: (drop: Double, fmul: Double) = (0.120, 1.0)

    func testTheConstantsAreChaseScoresOwn() {
        XCTAssertEqual(BallChallenge.Grid.bearings, Self.bearings)
        XCTAssertEqual(BallChallenge.Grid.ranges, Self.ranges)
        XCTAssertEqual(BallChallenge.Grid.extendedBearings, [-40, 40])
        XCTAssertEqual(BallChallenge.Grid.extendedRange, 1.20)
        XCTAssertEqual(BallChallenge.Grid.nominal.drop, Self.nominal.drop)
        XCTAssertEqual(BallChallenge.Grid.nominal.fmul, Self.nominal.fmul)
        XCTAssertEqual(BallChallenge.touchMillimetres, 3.0)
        XCTAssertEqual(BallChallenge.travelMinimumMillimetres, 100.0)
        XCTAssertEqual(BallChallenge.tailTicks, 50)
        XCTAssertEqual(BallChallenge.uprightTailMinimum, 45)
    }

    /// THE TWO OFF-NOMINAL PLANTS ARE THE STAIRS CHALLENGE'S OWN, verbatim, so
    /// "the slippery plant" means the same thing in both. A ball challenge
    /// that invented its own perturbation would make the two challenges'
    /// robustness numbers un-comparable for no reason.
    func testThePlantPerturbationsAreLiftedFromTheStairsChallenge() {
        XCTAssertEqual(BallChallenge.Grid.slippery.drop, StairsChallenge.Grid.plants[1].drop)
        XCTAssertEqual(BallChallenge.Grid.slippery.fmul, StairsChallenge.Grid.plants[1].fmul)
        XCTAssertEqual(BallChallenge.Grid.grippy.drop, StairsChallenge.Grid.plants[2].drop)
        XCTAssertEqual(BallChallenge.Grid.grippy.fmul, StairsChallenge.Grid.plants[2].fmul)
        XCTAssertEqual(BallChallenge.uprightTailMinimum, StairsChallenge.uprightTailMinimum)
        XCTAssertEqual(BallChallenge.plantDigest, StairsChallenge.plantDigest)
    }

    /// THE ORDER IS PART OF THE GRID: each range crossed with each bearing,
    /// core first, so a run stopped halfway is still the core grid every
    /// `k of 9` is quoted against.
    func testTheGridIsBuiltInChaseRobustsOrder() {
        var wanted: [DuckBench.ChaseCell] = []
        for range in Self.ranges {
            for bearing in Self.bearings {
                wanted.append(DuckBench.ChaseCell(bearing: bearing, range: range,
                                                  drop: Self.nominal.drop,
                                                  fmul: Self.nominal.fmul, tier: .core))
            }
        }
        wanted.append(DuckBench.ChaseCell(bearing: 0, range: 0.70, drop: 0.130, fmul: 0.7,
                                          tier: .ext))
        wanted.append(DuckBench.ChaseCell(bearing: 0, range: 0.70, drop: 0.125, fmul: 1.3,
                                          tier: .ext))
        wanted.append(DuckBench.ChaseCell(bearing: -40, range: 0.70, drop: 0.120, fmul: 1.0,
                                          tier: .ext))
        wanted.append(DuckBench.ChaseCell(bearing: 40, range: 0.70, drop: 0.120, fmul: 1.0,
                                          tier: .ext))
        wanted.append(DuckBench.ChaseCell(bearing: 0, range: 1.20, drop: 0.120, fmul: 1.0,
                                          tier: .ext))
        XCTAssertEqual(BallChallenge.Grid.fallback, wanted)
        XCTAssertEqual(wanted.count, 14)
    }

    func testTheCoreNineComeFirst() {
        let cells = BallChallenge.Grid.fallback
        XCTAssertEqual(cells.prefix(9).filter { $0.tier == .core }.count, 9)
        XCTAssertEqual(cells.suffix(5).filter { $0.tier == .ext }.count, 5)
        XCTAssertEqual(BallChallenge.Grid.coreCount, 9)
        XCTAssertEqual(BallChallenge.Grid.extendedCount, 5)
        XCTAssertEqual(BallChallenge.Grid.count, 14)
        XCTAssertEqual(BallChallenge.Grid.core.count, 9)
        XCTAssertEqual(BallChallenge.Grid.extended.count, 5)
    }

    /// THE CENTRE CELL IS IN THE CORE NINE and it is the one the two plant
    /// perturbations perturb. A `centre` that was not in `fallback` would be a
    /// fifteenth cell nobody scores.
    func testTheCentreCellIsOneOfTheNine() {
        XCTAssertTrue(BallChallenge.Grid.fallback.contains(BallChallenge.Grid.centre))
        XCTAssertEqual(BallChallenge.Grid.centre.tier, .core)
        XCTAssertEqual(BallChallenge.Grid.centre.bearing, 0)
        XCTAssertEqual(BallChallenge.Grid.centre.range, 0.70)
    }

    /// EVERY CORE CELL IS OUT OF REACH OF A LUNGE, which is the grid's whole
    /// design: Pollen's kick spawns the ball 90 mm in front of the toe, so the
    /// nearest cell here is five times that.
    func testTheNearestCellIsFiveTimesPollensKickDistance() {
        let nearest = BallChallenge.Grid.fallback.map(\.range).min()
        XCTAssertEqual(nearest, 0.45)
        XCTAssertEqual((nearest ?? 0) / 0.09, 5, accuracy: 1e-9)
    }

    /// The off-bearing cells are what the challenge is about, so there have to
    /// be some: a grid that was all bearing 0 would look solved.
    func testMostCellsAreOffTheDucksHeading() {
        let off = BallChallenge.Grid.fallback.filter { $0.bearing != 0 }
        XCTAssertEqual(off.count, 8)
        XCTAssertEqual(Set(BallChallenge.Grid.fallback.map(\.bearing)), [-40, -20, 0, 20, 40])
    }

    func testTierIsWorkedOutFromTheCellsOwnNumbers() {
        XCTAssertEqual(BallChallenge.Grid.tier(bearing: 0, range: 0.70, drop: 0.120, fmul: 1.0),
                       .core)
        XCTAssertEqual(BallChallenge.Grid.tier(bearing: 40, range: 0.70, drop: 0.120, fmul: 1.0),
                       .ext)
        XCTAssertEqual(BallChallenge.Grid.tier(bearing: 0, range: 1.20, drop: 0.120, fmul: 1.0),
                       .ext)
        XCTAssertEqual(BallChallenge.Grid.tier(bearing: 0, range: 0.70, drop: 0.130, fmul: 0.7),
                       .ext)
    }

    /// The bench's grid wins whenever it says anything at all.
    func testTheBenchesGridWinsAndTheFallbackFillsSilence() {
        XCTAssertEqual(BallChallenge.Grid.cells(from: nil), BallChallenge.Grid.fallback)
        XCTAssertEqual(BallChallenge.Grid.cells(from: Data("not json".utf8)),
                       BallChallenge.Grid.fallback)
        let said = Data(#"{"cells":[{"bearing":0,"range":0.7,"drop":0.12,"fmul":1,"tier":"core"}]}"#
                        .utf8)
        XCTAssertEqual(BallChallenge.Grid.cells(from: said),
                       [DuckBench.ChaseCell(bearing: 0, range: 0.7, drop: 0.12, fmul: 1,
                                            tier: .core)])
    }

    func testAGridThatIsNotThePublishedOneIsSaidSo() {
        XCTAssertTrue(BallChallenge.Grid.isPublishedGrid(BallChallenge.Grid.fallback))
        XCTAssertFalse(BallChallenge.Grid.isPublishedGrid(
            Array(BallChallenge.Grid.fallback.dropLast())))
    }

    /// A cell's label carries the SIGN of the bearing, because a grid of ±20
    /// with no sign on the row is a grid nobody can reproduce.
    func testACellsLabelCarriesTheSignOfTheBearing() {
        let cells = BallChallenge.Grid.fallback
        XCTAssertEqual(cells[0].said, "-20°/0.45/.120/x1.0")
        XCTAssertEqual(cells[4].said, "0°/0.70/.120/x1.0")
        XCTAssertEqual(cells[2].said, "+20°/0.45/.120/x1.0")
        XCTAssertEqual(cells[9].said, "0°/0.70/.130/x0.7")
        XCTAssertEqual(cells[13].said, "0°/1.20/.120/x1.0")
    }

    func testACellSaysItselfInWordsToo() {
        XCTAssertEqual(BallChallenge.Grid.fallback[12].longSaid,
                       "ball +40° at 0.70 m, drop 0.120, friction ×1.0")
    }

    // MARK: - reading a bench's grid

    func testAFullGridAnswerIsRead() throws {
        let data = Data("""
        {"cells":[{"bearing":-20,"range":0.45,"drop":0.12,"fmul":1,"tier":"core"},
                  {"bearing":40,"range":0.7,"drop":0.12,"fmul":1,"tier":"ext"}],
         "chaseable":true,"uprightTailMin":45,"touch_mm":3,"travelMin_mm":100,
         "criterion":"\(BallChallenge.criterionSentence)",
         "plantName":"scene.mjb","plantDigest":"\(BallChallenge.plantDigest)"}
        """.utf8)
        let grid = try DuckBench.readChaseGrid(data)
        XCTAssertEqual(grid.cells.count, 2)
        XCTAssertTrue(grid.chaseable)
        XCTAssertEqual(grid.uprightTailMinimum, 45)
        XCTAssertEqual(grid.touchMillimetres, 3)
        XCTAssertEqual(grid.travelMinimumMillimetres, 100)
        XCTAssertEqual(grid.criterion, BallChallenge.criterionSentence)
        XCTAssertEqual(grid.plantDigest, BallChallenge.plantDigest)
    }

    /// A BENCH THAT ANSWERS THE GRID AND CANNOT SCORE IT is the case
    /// `chaseable` exists for: fourteen rows and a Score button over a plant
    /// with no free ball in it.
    func testABenchThatAnswersTheGridAndCannotScoreItSaysSo() throws {
        let text = #"{"cells":[{"bearing":0,"range":0.7,"drop":0.12,"fmul":1}],"#
                 + #""chaseable":false,"why":"this plant has no free ball"}"#
        let data = Data(text.utf8)
        let grid = try DuckBench.readChaseGrid(data)
        XCTAssertFalse(grid.chaseable)
        XCTAssertEqual(grid.why, "this plant has no free ball")
    }

    func testABareArrayOfCellsIsAcceptedAndATierIsWorkedOut() throws {
        let data = Data(#"[{"bearing":0,"range":1.2,"drop":0.12,"fmul":1}]"#.utf8)
        let grid = try DuckBench.readChaseGrid(data)
        XCTAssertEqual(grid.cells.first?.tier, .ext)
    }

    func testABenchWithoutChaseArrivesAsItsOwnWords() {
        XCTAssertThrowsError(try DuckBench.readChaseGrid(Data(#"{"error":"no /chase here"}"#.utf8))) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .bench("no /chase here"))
        }
    }
}
