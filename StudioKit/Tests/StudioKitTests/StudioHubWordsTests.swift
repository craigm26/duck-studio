import XCTest
@testable import StudioKit

final class StudioHubWordsTests: XCTestCase {
    func testEveryRowLineFitsOnePhoneLine() {
        for line in StudioHubWords.all {
            XCTAssertLessThanOrEqual(line.count, 60, line)
            XCTAssertTrue(line.hasSuffix("."), line)
        }
    }

    func testEveryModeSummaryFitsOnePhoneLine() {
        for mode in LabCatalogue.modes {
            XCTAssertLessThanOrEqual(mode.summary.count, 66, mode.name)
            XCTAssertFalse(mode.summary.contains("—"), mode.name)
        }
    }
}
