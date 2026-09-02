import XCTest
@testable import StudioKit

/// The Robot tab's hardware figures are data with a source, not literals in a
/// view — and the one that has a computed twin says which is which.
final class DuckPublishedSpecsTests: XCTestCase {
    func testThePublishedFiguresAreTheOnesPollenPublish() {
        XCTAssertEqual(DuckPublishedSpecs.heightCentimetres, 25)
        XCTAssertEqual(DuckPublishedSpecs.massGrams, 800)
        XCTAssertEqual(DuckPublishedSpecs.sensors, "Camera, LiDAR, two IMUs")
        XCTAssertTrue(DuckPublishedSpecs.source.contains("Pollen Robotics"))
    }

    /// THE MODEL AND THE SPEC DISAGREE, AND THE SENTENCE SAYS SO. 737 g summed
    /// from the MJCF against 800 g published is an 8% gap; if it ever widened
    /// past a fifth the model would be standing in for a different robot.
    func testTheModelledMassIsTheDragConstantAndNearThePublishedOne() {
        XCTAssertEqual(DuckPublishedSpecs.modelledMassGrams,
                       Int((Retrieval.Drag.duckMass * 1000).rounded()))
        let gap = abs(Double(DuckPublishedSpecs.modelledMassGrams - DuckPublishedSpecs.massGrams))
        XCTAssertLessThan(gap / Double(DuckPublishedSpecs.massGrams), 0.2)
        XCTAssertTrue(DuckPublishedSpecs.massNote.contains("800 g is the published figure"))
        XCTAssertTrue(DuckPublishedSpecs.massNote.contains("\(DuckPublishedSpecs.modelledMassGrams) g"))
    }
}
