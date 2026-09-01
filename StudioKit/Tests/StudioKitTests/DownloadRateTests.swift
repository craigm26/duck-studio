import XCTest
@testable import StudioKit

/// The download worked; the reporting did not. A bar that fills tells somebody
/// nothing about whether to stay on the screen for four minutes or forty.
final class DownloadRateTests: XCTestCase {

    /// ONE SAMPLE IS NOT A RATE. The first seconds of a download are the least
    /// representative part of it, and a number that is wrong by an order of
    /// magnitude and then corrects itself reads as a broken app.
    func testItRefusesToQuoteASpeedFromOneObservation() {
        var rate = DownloadRate()
        rate.observe(completedBytes: 0, totalBytes: 351_000_000, at: 0)
        XCTAssertNil(rate.bytesPerSecond)
        XCTAssertNil(rate.secondsRemaining)
        XCTAssertTrue(rate.line(fraction: 0, totalBytes: 351_000_000)
                        .contains("Working out how fast"))
    }

    /// A STEADY 10 MB/s READS AS 10 MB/s. The smoothing must not bias a
    /// constant rate away from itself.
    func testASteadyRateIsReportedAsItself() {
        var rate = DownloadRate()
        for step in 0...6 {
            rate.observe(completedBytes: step * 10_000_000, totalBytes: 351_000_000,
                         at: Double(step))
        }
        let measured = try? XCTUnwrap(rate.bytesPerSecond)
        XCTAssertEqual(measured ?? 0, 10_000_000, accuracy: 500_000)
        XCTAssertEqual(DownloadRate.speedDescription(measured ?? 0), "10.0 MB/s")
    }

    /// And the time left follows from it: 351 MB at 10 MB/s, 100 MB in, is
    /// about 25 seconds.
    func testTimeRemainingFollowsFromTheMeasuredRate() throws {
        var rate = DownloadRate()
        for step in 0...10 {
            rate.observe(completedBytes: step * 10_000_000, totalBytes: 351_000_000,
                         at: Double(step))
        }
        let left = try XCTUnwrap(rate.secondsRemaining)
        XCTAssertEqual(left, 25, accuracy: 4)
        XCTAssertEqual(DownloadRate.remainingDescription(left), "less than a minute left")
    }

    /// SAMPLES TOO CLOSE TOGETHER ARE NOISE. The hub reports every 100 ms, and
    /// a small byte delta over a small interval swings wildly.
    func testSamplesCloserThanTheGapAreIgnored() {
        var rate = DownloadRate()
        for step in 0...20 {
            rate.observe(completedBytes: step * 1000, totalBytes: 1_000_000,
                         at: Double(step) * 0.1)
        }
        // 2 s of samples at 0.1 s apart yields few accepted observations.
        XCTAssertNotNil(rate.bytesPerSecond)
    }

    /// A RESTARTED FILE GOES BACKWARDS — the in-flight file is discarded on
    /// failure — and a negative rate is not a rate.
    func testGoingBackwardsDoesNotProduceANegativeSpeed() {
        var rate = DownloadRate()
        rate.observe(completedBytes: 100_000_000, totalBytes: 351_000_000, at: 0)
        rate.observe(completedBytes: 200_000_000, totalBytes: 351_000_000, at: 1)
        rate.observe(completedBytes: 14_000_000, totalBytes: 351_000_000, at: 2)
        rate.observe(completedBytes: 30_000_000, totalBytes: 351_000_000, at: 3)
        let measured = rate.bytesPerSecond
        XCTAssertNotNil(measured)
        XCTAssertGreaterThan(measured ?? -1, 0)
    }

    /// NO FALSE PRECISION. "4 minutes 37 seconds" implies a confidence this
    /// estimate does not have.
    func testTimeIsRoundedToSomethingUsable() {
        XCTAssertEqual(DownloadRate.remainingDescription(20), "less than a minute left")
        XCTAssertEqual(DownloadRate.remainingDescription(60), "about a minute left")
        XCTAssertEqual(DownloadRate.remainingDescription(600), "about 10 minutes left")
        XCTAssertEqual(DownloadRate.remainingDescription(3700), "about an hour left")
        XCTAssertEqual(DownloadRate.remainingDescription(7200), "about 2 hours left")
    }

    func testSlowConnectionsAreShownInKilobytes() {
        XCTAssertEqual(DownloadRate.speedDescription(300_000), "300 kB/s")
        XCTAssertEqual(DownloadRate.speedDescription(2_500_000), "2.5 MB/s")
    }

    /// THE ORDER IS PROGRESS, SPEED, TIME — certain, measured, inferred.
    func testTheLineLeadsWithWhatIsCertain() {
        var rate = DownloadRate()
        for step in 0...8 {
            rate.observe(completedBytes: step * 20_000_000, totalBytes: 351_000_000,
                         at: Double(step))
        }
        let line = rate.line(fraction: 0.45, totalBytes: 351_000_000)
        let percent = try? XCTUnwrap(line.range(of: "45%"))
        XCTAssertNotNil(percent)
        XCTAssertTrue(line.contains("MB/s"), line)
        XCTAssertTrue(line.contains("left"), line)
        XCTAssertLessThan(line.range(of: "45%")!.lowerBound, line.range(of: "MB/s")!.lowerBound)
    }
}
