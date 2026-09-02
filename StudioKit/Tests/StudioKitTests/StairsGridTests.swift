import XCTest
@testable import StudioKit

/// The fourteen cells, against `climb/robust.mjs`'s own constants.
final class StairsGridTests: XCTestCase {

    // Transcribed from duck-sounds/climb/robust.mjs, lines 494–518, on
    // 2026-09-02. Written out here rather than referenced so this test fails
    // if the app's copy drifts from the harness the numbers came from.
    //
    //   export const PLANTS = [{drop:0.120,fmul:1.0},{drop:0.130,fmul:0.7},{drop:0.125,fmul:1.3}]
    //   export const DHS = [-0.010, 0.000, 0.010]
    //   export const EXT_DHS = [-0.005, 0.005]           // nominal plant only
    //   export const EXT_PLANT = { drop: 0.140, fmul: 0.5 }
    //   export const EXT_CELL_COUNT = 14
    //   export const UPRIGHT_TAIL_MIN = 45
    static let plants: [(drop: Double, fmul: Double)] =
        [(0.120, 1.0), (0.130, 0.7), (0.125, 1.3)]
    static let dhs: [Double] = [-0.010, 0.000, 0.010]
    static let extendedDHs: [Double] = [-0.005, 0.005]
    static let extendedPlant: (drop: Double, fmul: Double) = (0.140, 0.5)

    func testThePinnedFallbackIsRobustMjssGrid() {
        XCTAssertEqual(StairsChallenge.Grid.dhs, Self.dhs)
        XCTAssertEqual(StairsChallenge.Grid.extendedDHs, Self.extendedDHs)
        XCTAssertEqual(StairsChallenge.Grid.plants.map(\.drop), Self.plants.map(\.drop))
        XCTAssertEqual(StairsChallenge.Grid.plants.map(\.fmul), Self.plants.map(\.fmul))
        XCTAssertEqual(StairsChallenge.Grid.extendedPlant.drop, Self.extendedPlant.drop)
        XCTAssertEqual(StairsChallenge.Grid.extendedPlant.fmul, Self.extendedPlant.fmul)
        XCTAssertEqual(StairsChallenge.uprightTailMinimum, 45)
    }

    /// THE ORDER IS PART OF THE GRID. `scoreRobust` builds its plan as
    /// `for (const dh of DHS) for (const p of PLANTS)`, then the two extended
    /// rises on the nominal plant, then the three core rises on the slippery
    /// one. A partial run in a different order is a partial run of a different
    /// grid.
    func testTheGridIsBuiltInScoreRobustsOrder() {
        var wanted: [DuckBench.Cell] = []
        for dh in Self.dhs {
            for plant in Self.plants {
                wanted.append(DuckBench.Cell(dh: dh, drop: plant.drop, fmul: plant.fmul,
                                             tier: .core))
            }
        }
        for dh in Self.extendedDHs {
            wanted.append(DuckBench.Cell(dh: dh, drop: Self.plants[0].drop,
                                         fmul: Self.plants[0].fmul, tier: .ext))
        }
        for dh in Self.dhs {
            wanted.append(DuckBench.Cell(dh: dh, drop: Self.extendedPlant.drop,
                                         fmul: Self.extendedPlant.fmul, tier: .ext))
        }
        XCTAssertEqual(StairsChallenge.Grid.fallback, wanted)
        XCTAssertEqual(wanted.count, 14)
    }

    func testTheCoreNineComeFirstSoAPartialRunIsStillTheRoundThreeGrid() {
        let cells = StairsChallenge.Grid.fallback
        XCTAssertEqual(cells.prefix(9).filter { $0.tier == .core }.count, 9)
        XCTAssertEqual(cells.suffix(5).filter { $0.tier == .ext }.count, 5)
        XCTAssertEqual(StairsChallenge.Grid.coreCount, 9)
        XCTAssertEqual(StairsChallenge.Grid.count, 14)
    }

    /// Every rise offset the contract allows, and nothing else.
    func testTheOnlyRiseOffsetsAreTheFiveTheContractNames() {
        XCTAssertEqual(Set(StairsChallenge.Grid.fallback.map(\.dh)),
                       [-0.010, -0.005, 0.0, 0.005, 0.010])
    }

    func testTierIsWorkedOutFromTheCellsOwnNumbers() {
        XCTAssertEqual(StairsChallenge.Grid.tier(dh: 0, drop: 0.120, fmul: 1.0), .core)
        XCTAssertEqual(StairsChallenge.Grid.tier(dh: -0.005, drop: 0.120, fmul: 1.0), .ext)
        XCTAssertEqual(StairsChallenge.Grid.tier(dh: 0, drop: 0.140, fmul: 0.5), .ext)
    }

    /// The bench's grid wins whenever it says anything at all.
    func testTheBenchesGridWinsAndTheFallbackFillsSilence() throws {
        XCTAssertEqual(StairsChallenge.Grid.cells(from: nil), StairsChallenge.Grid.fallback)
        XCTAssertEqual(StairsChallenge.Grid.cells(from: Data("not json".utf8)),
                       StairsChallenge.Grid.fallback)
        let said = Data(#"{"cells":[{"dh":0,"drop":0.12,"fmul":1,"tier":"core"}]}"#.utf8)
        XCTAssertEqual(StairsChallenge.Grid.cells(from: said),
                       [DuckBench.Cell(dh: 0, drop: 0.12, fmul: 1, tier: .core)])
    }

    func testAGridThatIsNotThePublishedOneIsSaidSo() {
        XCTAssertTrue(StairsChallenge.Grid.isPublishedGrid(StairsChallenge.Grid.fallback))
        XCTAssertFalse(StairsChallenge.Grid.isPublishedGrid(
            Array(StairsChallenge.Grid.fallback.dropLast())))
    }

    /// The harness's own label for a cell, which is what the published results
    /// print — `"60/.120/x1.0"` in `r6_judge-results.json` → `cellsXZ`.
    func testACellsLabelIsTheOneThePublishedResultsPrint() {
        let cells = StairsChallenge.Grid.fallback
        XCTAssertEqual(cells[0].said(rise: 0.060), "50/.120/x1.0")
        XCTAssertEqual(cells[4].said(rise: 0.060), "60/.130/x0.7")
        XCTAssertEqual(cells[13].said(rise: 0.060), "70/.140/x0.5")
    }
}
