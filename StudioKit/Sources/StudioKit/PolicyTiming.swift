import Foundation
import DuckKit

/// How long one forward pass of a policy takes on THIS device, measured here.
///
/// WHY THE APP MEASURES IT ITSELF. Every latency number in the Microduck family
/// so far came from somewhere other than a phone: duckbatch's bench is
/// onnxruntime on an x86 laptop, the phone bench's tick was timed in Chromium
/// on a Pi (`PhoneBenchReport.speedIsUnmeasuredOnAPhone`). A distilled student
/// is interesting precisely because it is cheaper to run, and "cheaper" is only
/// a claim about a device once it has been timed on that device. This times
/// `DuckPolicy.infer` — the exact function the app drives a duck with — so the
/// number is the app's own cost, not an estimate from FLOPs.
///
/// WHAT IT DOES NOT CLAIM. It is one thread, warm caches, a fixed handful of
/// observations cycled, and whatever else the device was doing at the time.
/// Percentiles, not a mean, because a 50 Hz loop cares about the slow tail. The
/// device is recorded with every result, and results from two devices are never
/// compared as if they were one.
public struct PolicyTiming: Equatable, Sendable {

    public let runs: Int
    /// Microseconds per `infer`, at the 50th, 95th and 99th percentile.
    public let p50Micros: Double
    public let p95Micros: Double
    public let p99Micros: Double
    /// Learned weights and biases of the network that was timed.
    public let parameterCount: Int
    /// `[inputs, h1, …, 14]`, so a result says which network it describes.
    public let widths: [Int]
    /// Where it ran, as `ProcessInfo` reports it — never a guess.
    public let device: String

    /// The 50 Hz control tick, in microseconds: the budget one pass must fit
    /// inside, with the rest of the loop.
    public static let tickBudgetMicros: Double = 1_000_000 / Double(DuckModel.tickHz)

    /// Time `runs` passes after `warmup` untimed ones, cycling `observations`.
    ///
    /// The observations matter only in that they are real ones: ELU's
    /// exponential branch costs more than its identity branch, so a pass over
    /// zeros is not a pass over a walking duck. Callers pass what they have —
    /// the goldens in tests, a recorded stream in the app.
    public static func measure(_ policy: DuckPolicy, observations: [DuckObservation],
                               runs: Int = 2_000, warmup: Int = 200) -> PolicyTiming {
        precondition(!observations.isEmpty && runs > 0, "nothing to time")
        var sink: Float = 0
        for i in 0..<warmup {
            sink += policy.infer(observations[i % observations.count])[0]
        }
        let clock = ContinuousClock()
        var micros = [Double](repeating: 0, count: runs)
        for i in 0..<runs {
            let obs = observations[i % observations.count]
            let elapsed = clock.measure { sink += policy.infer(obs)[0] }
            micros[i] = Double(elapsed.components.seconds) * 1e6
                + Double(elapsed.components.attoseconds) / 1e12
        }
        // Keep the result live so the optimiser cannot drop the passes.
        if sink.isNaN { micros[0] += 0 }
        micros.sort()
        func percentile(_ p: Double) -> Double {
            micros[min(runs - 1, Int((Double(runs - 1) * p).rounded()))]
        }
        let w = policy.layerWidths
        return PolicyTiming(runs: runs, p50Micros: percentile(0.50), p95Micros: percentile(0.95),
                            p99Micros: percentile(0.99), parameterCount: policy.parameterCount,
                            widths: [w.first?.inputs ?? 0] + w.map(\.outputs),
                            device: deviceDescription())
    }

    /// "18 µs a pass on this device (p95 24 µs): 0.1% of the 20 ms tick."
    public var sentence: String {
        let share = p95Micros / PolicyTiming.tickBudgetMicros * 100
        return "\(Int(p50Micros.rounded())) µs a pass on this device "
            + "(p95 \(Int(p95Micros.rounded())) µs): "
            + "\(String(format: share < 1 ? "%.2f" : "%.1f", share))% of the 20 ms tick."
    }

    /// "7.5× fewer parameters, 2.7× faster here than 61-512-256-128-14" — two
    /// timings from the same device only, which is the only comparison that means
    /// anything.
    public func comparedWith(_ other: PolicyTiming) -> String? {
        guard device == other.device, other.p50Micros > 0, p50Micros > 0 else { return nil }
        let fewer = Double(other.parameterCount) / Double(max(parameterCount, 1))
        let faster = other.p50Micros / p50Micros
        return String(format: "%.1f× fewer parameters, %.1f× faster here than ", fewer, faster)
            + other.widths.map(String.init).joined(separator: "-")
    }

    static func deviceDescription() -> String {
        let info = ProcessInfo.processInfo
        #if os(Linux)
        let system = "Linux"
        #else
        let system = info.operatingSystemVersionString
        #endif
        return "\(system), \(info.activeProcessorCount) cores"
    }
}
