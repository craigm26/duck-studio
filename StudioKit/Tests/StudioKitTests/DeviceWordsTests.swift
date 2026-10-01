import XCTest
@testable import StudioKit

/// The Mac's wording, tested on a machine that is not a Mac.
///
/// `DeviceWords.current` is decided at compile time, and these tests run on
/// Linux — where it is the phone. So every existing sentence test keeps
/// guarding the phone wording, and the Mac wording is reached here by passing
/// `.mac` to the functions that take a device.
final class DeviceWordsTests: XCTestCase {

    func testTheTestsRunAsThePhone() {
        XCTAssertEqual(DeviceWords.current, .phone,
                       "the kit's existing sentence tests assume the phone wording")
    }

    func testTheWordsForEachMachine() {
        XCTAssertEqual(DeviceWords.mac.this, "this Mac")
        XCTAssertEqual(DeviceWords.mac.This, "This Mac")
        XCTAssertEqual(DeviceWords.mac.system, "macOS")
        XCTAssertEqual(DeviceWords.phone.this, "this phone")
        XCTAssertEqual(DeviceWords.phone.system, "iOS")
    }

    /// THE BUILT-IN BENCH IS NAMED FOR THE MACHINE IT IS INSIDE, and a Mac is
    /// not an iPad that happens to be large.
    func testTheBuiltInBenchIsCalledThisMacOnAMac() {
        XCTAssertEqual(PhoneBenchReport.name(onPad: false, device: .mac), "This Mac")
        XCTAssertEqual(PhoneBenchReport.name(onPad: true, device: .mac), "This Mac")
        XCTAssertEqual(PhoneBenchReport.name(onPad: true, device: .phone), "This iPad")
        XCTAssertEqual(PhoneBenchReport.name(onPad: false, device: .phone), "This iPhone")
    }

    /// A PHONE KILLS, A MAC SWAPS, and each sentence says what happens where it
    /// is read.
    func testTooBigSaysSwappingOnAMacAndKilledOnAPhone() throws {
        let model = try XCTUnwrap(PhoneModel.macUntried.last)
        let mac = PhoneModel.tooBig(model, budgetBytes: 4_000_000_000, device: .mac)
        XCTAssertTrue(mac.contains("this Mac can spare about 4.0 GB"), mac)
        XCTAssertTrue(mac.contains("slow to a crawl"), mac)
        XCTAssertFalse(mac.contains("iOS"), mac)
        XCTAssertFalse(mac.contains("killed"), mac)

        let phone = PhoneModel.tooBig(model, budgetBytes: 4_000_000_000, device: .phone)
        XCTAssertTrue(phone.contains("iOS is offering this app about 4.0 GB"), phone)
        XCTAssertTrue(phone.contains("killed"), phone)

        let loaded = PhoneModel.tooBigWhileLoaded("Qwen3 8B", budgetBytes: 200_000_000, device: .mac)
        XCTAssertTrue(loaded.contains("without swapping"), loaded)
        XCTAssertFalse(loaded.contains("iOS"), loaded)
    }

    /// SEARCH AND CATALOGUE SAY THE SAME "TOO BIG", because they are one
    /// sentence now.
    func testSearchUsesTheCatalogueSentence() throws {
        let said = try XCTUnwrap(PhoneModelSearch.doesNotFit("X", bytes: 5_000_000_000,
                                                             budgetBytes: 1_000_000_000))
        XCTAssertEqual(said, PhoneModel.doesNotFitSentence("X", needs: 5_350_000_000,
                                                           budgetBytes: 1_000_000_000))
    }

    func testThePreambleDoesNotCompareAMacWithADesktop() {
        let mac = PhoneModel.preamble(on: .mac)
        XCTAssertTrue(mac.contains("on this Mac itself"), mac)
        XCTAssertFalse(mac.contains("anything on a desktop"), mac)
        XCTAssertTrue(PhoneModel.preamble(on: .phone).contains("on the phone itself"))
    }

    /// THE LARGER MODELS ARE OFFERED ONLY WHERE THEY CAN FIT, AND ONLY AS
    /// UNTRIED. Neither has been run here; folding them into `catalogue` would
    /// spend the promise that list makes.
    func testLargerModelsAreMacOnlyAndUntried() {
        let biggestTried = PhoneModel.catalogue.map(\.downloadBytes).max() ?? 0
        XCTAssertFalse(PhoneModel.macUntried.isEmpty)
        for model in PhoneModel.macUntried {
            XCTAssertGreaterThan(model.downloadBytes, biggestTried, model.name)
            XCTAssertFalse(PhoneModel.catalogue.contains(model), model.name)
            XCTAssertTrue(PhoneModel.untried(on: .mac).contains(model), model.name)
            XCTAssertFalse(PhoneModel.untried(on: .phone).contains(model), model.name)
            XCTAssertTrue(model.repository.hasPrefix("mlx-community/"), model.repository)
            XCTAssertTrue(model.note.contains("run"), "an untried note says it is untried: \(model.note)")
        }
    }

    func testAMacIsNotWarnedAboutCellularData() {
        XCTAssertFalse(PhoneModelInstall.downloadFooter(on: .mac).contains("cellular"))
        XCTAssertTrue(PhoneModelInstall.downloadFooter(on: .phone).contains("cellular"))
    }
}
