import Foundation

/// How fast a download is going, and how long is left.
///
/// WHY A PERCENTAGE WAS NOT ENOUGH. A bar that fills is a bar; a person
/// deciding whether to stay on a screen for a 2.3 GB fetch over cellular needs
/// to know whether that is four minutes or forty. The download itself was fine
/// — the reporting was the whole complaint.
///
/// IT REFUSES TO GUESS FROM ONE SAMPLE. A rate needs two observations and a
/// little elapsed time, and until it has them it says so rather than printing a
/// number that will be wrong by an order of magnitude and then correct itself.
/// The first seconds of a download are the least representative part of it.
///
/// AND IT SMOOTHS, because an unsmoothed instantaneous rate on a mobile
/// connection swings between 2 MB/s and 40 MB/s twice a second, which is
/// unreadable and looks broken. An exponential moving average over the recent
/// samples is what makes it a number somebody can act on.
public struct DownloadRate: Equatable, Sendable {

    /// Ignore samples closer together than this: the hub reports every 100 ms,
    /// and dividing a small byte delta by a small time gives noise.
    public static let minimumSampleGap: TimeInterval = 0.5
    /// How much a new sample moves the average. Low enough to be steady, high
    /// enough to notice a connection getting slower.
    public static let smoothing = 0.3
    /// Below this, a rate is not yet worth quoting.
    public static let minimumSamples = 2

    private var lastAt: TimeInterval?
    private var lastBytes: Int?
    private var samples = 0
    private var smoothed: Double?

    public init() {}

    /// Take an observation. `now` is passed in rather than read, so a test can
    /// drive time without sleeping.
    public mutating func observe(completedBytes: Int, totalBytes: Int, at now: TimeInterval) {
        defer { total = totalBytes; completed = completedBytes }
        guard let lastAt, let lastBytes else {
            self.lastAt = now
            self.lastBytes = completedBytes
            return
        }
        let elapsed = now - lastAt
        guard elapsed >= DownloadRate.minimumSampleGap else { return }

        // A RESTARTED FILE GOES BACKWARDS. The in-flight file is discarded on
        // failure, so completed can drop; a negative rate is not a rate.
        let moved = completedBytes - lastBytes
        self.lastAt = now
        self.lastBytes = completedBytes
        guard moved > 0 else { return }

        let instant = Double(moved) / elapsed
        smoothed = smoothed.map { $0 + DownloadRate.smoothing * (instant - $0) } ?? instant
        samples += 1
    }

    private var total = 0
    private var completed = 0

    /// Bytes per second, or nil while there is not enough evidence.
    public var bytesPerSecond: Double? {
        guard samples >= DownloadRate.minimumSamples, let smoothed, smoothed > 0 else {
            return nil
        }
        return smoothed
    }

    /// Seconds left, or nil when the rate is unknown or the total is not.
    public var secondsRemaining: TimeInterval? {
        guard let rate = bytesPerSecond, total > completed else { return nil }
        return Double(total - completed) / rate
    }

    // MARK: - what the screen says

    public static func speedDescription(_ bytesPerSecond: Double) -> String {
        bytesPerSecond >= 1_000_000
            ? String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
            : String(format: "%.0f kB/s", bytesPerSecond / 1_000)
    }

    /// Rounded to something a person can use. NOBODY NEEDS "4 minutes 37
    /// seconds" for a download — the false precision implies a confidence the
    /// estimate does not have.
    public static func remainingDescription(_ seconds: TimeInterval) -> String {
        if seconds < 45 { return "less than a minute left" }
        if seconds < 90 { return "about a minute left" }
        if seconds < 3600 {
            return "about \(Int((seconds / 60).rounded())) minutes left"
        }
        let hours = seconds / 3600
        return hours < 1.5 ? "about an hour left"
                           : "about \(Int(hours.rounded())) hours left"
    }

    /// The whole line: how far, how fast, how long.
    ///
    /// THE ORDER IS DELIBERATE. Progress first because it is certain, speed
    /// next because it is measured, time last because it is inferred from the
    /// other two and is the least reliable of the three.
    public func line(fraction: Double, totalBytes: Int) -> String {
        var out = PhoneModelInstall.downloading(fraction: fraction, totalBytes: totalBytes)
        guard let rate = bytesPerSecond else {
            // SAID, NOT GUESSED. A speed invented from one sample is wrong by
            // an order of magnitude and then corrects itself, which reads as a
            // broken app rather than an early one.
            return out + " Working out how fast…"
        }
        out += " \(DownloadRate.speedDescription(rate))"
        if let left = secondsRemaining {
            out += ", \(DownloadRate.remainingDescription(left))"
        }
        return out + "."
    }
}
