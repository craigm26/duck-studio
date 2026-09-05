import Foundation
import DuckKit

/// A search over a trained network's OWN WEIGHTS — all 197,774 of them.
///
/// WHAT THIS IS, AND WHAT IT IS NOT. `DuckTuner` searches twenty-eight numbers:
/// a multiplier and a trim folded onto each policy slot AFTER the network has
/// spoken. It cannot change what the network computes, only how loudly each
/// joint hears it. This searches the network itself: every weight and bias in
/// all four layers, under a reward the bench measures. That is training in the
/// ordinary meaning of the word. It is NOT a network learned from scratch —
/// there is no gradient here, no autodiff, no mjlab, and the search starts from
/// a policy somebody else trained. Both halves of that sentence have to survive
/// into the copy; `TrainingRequestView` is where they land.
///
/// WHY IT WORKS ON A PHONE AT ALL. Every evaluation is a bench rollout, not a
/// backward pass, so the phone never holds a gradient — it holds a base policy,
/// a random seed per candidate, and a list of rewards. Measured on the desk
/// bench 2026-09-03: one candidate costs 2.33 s end to end (0.08 s to upload,
/// 2.25 s to score four drops of six seconds), so a twenty-candidate generation
/// is under a minute.
///
/// WHAT IT ACTUALLY DID, ON THAT BENCH, BEFORE ANY OF THIS WAS WRITTEN. Five
/// generations of ten antithetic pairs at 5% took `alpha_walking` from 1.1700 m
/// of forward travel to 1.3862 m — 18.5% further, standing on all four drops
/// throughout. Under commands it was never searched against it kept 0.98× of
/// its sideways travel and 1.05× of its turning. That last line is the one that
/// matters: the twenty-eight-number search bought forward reward by killing
/// sideways travel in four winners out of eight, and this did not.
public enum WeightSearch {

    // MARK: - the step, and why it is relative

    /// THE LAYERS DO NOT SHARE A SCALE, so one absolute step size cannot mean
    /// the same thing in all of them. Measured on `alpha_walking`, the four
    /// layers' weights have spreads of 0.0988, 0.0792, 0.0715 and 0.0269 — the
    /// output layer's is 3.7× tighter than the input layer's. A step of 0.02
    /// is a nudge in layer 0 and most of a standard deviation in layer 3, which
    /// is exactly how a search ends up destroying the last layer while barely
    /// touching the first.
    ///
    /// So a step is a FRACTION OF EACH LAYER'S OWN SPREAD, and this is the
    /// function that reads those spreads out of the network in front of it
    /// rather than assuming the ones above.
    public static func scales(of layers: [DuckPolicyWriter.Layer]) -> [Double] {
        layers.map { layer in
            guard !layer.weights.isEmpty else { return 0 }
            let mean = layer.weights.reduce(Float(0), +) / Float(layer.weights.count)
            let variance = layer.weights.reduce(Float(0)) {
                $0 + ($1 - mean) * ($1 - mean)
            } / Float(layer.weights.count)
            return Double(variance.squareRoot())
        }
    }

    /// How big a step may be, as a fraction of a layer's own spread.
    ///
    /// THE BAND IS MEASURED, NOT CHOSEN. Whole-network perturbations were run
    /// against the desk bench at 0.5%, 1%, 2%, 5%, 10%, 25%, 50% and 100% of
    /// each layer's spread, under the walk the tuner uses:
    ///
    /// | step | travelled | standing |
    /// |------|-----------|----------|
    /// | 0    | 1.1700    | 4/4      |
    /// | 10%  | 1.3639    | 4/4      |
    /// | 25%  | −0.3702   | 4/4      |
    /// | 100% | −0.0788   | 0/4      |
    ///
    /// Ten per cent is still a walk and a slightly better one. At twenty-five
    /// the duck walks BACKWARDS while passing every standing check there is —
    /// the reward-farm shape, arrived at by accident rather than by search. At
    /// a full spread it falls over. The upper bound is set below the first
    /// measurement that reversed, not at it.
    public static let stepBand = 0.001...0.10

    /// A step outside the band is refused by name rather than clamped, because
    /// a search silently run at a step that reverses the walk is a search whose
    /// every answer is wrong in a way no later gate can see.
    public enum Refusal: Error, Equatable {
        case stepOutsideTheBand(Double)
        case tooFewPairs(Int)
        case noCommand
        case emptyNetwork
        case scaleIsZero(layer: Int)

        public var message: String {
            switch self {
            case .stepOutsideTheBand(let step):
                return "A step of \(pc(step)) is outside the \(pc(stepBand.lowerBound))–"
                     + "\(pc(stepBand.upperBound)) this bench has been measured over. At a "
                     + "quarter of a layer's own spread the duck walks backwards while still "
                     + "passing every standing check, so a search run there answers confidently "
                     + "and wrongly."
            case .tooFewPairs(let pairs):
                return "A generation of \(pairs) pair\(pairs == 1 ? "" : "s") is too few to rank. "
                     + "The step comes from the ORDER of the rewards, and an order over fewer "
                     + "than three pairs is mostly the sign of one episode."
            case .noCommand:
                return "This search has no command to score against. A run with no command "
                     + "measures a duck standing still — every candidate looks identical, the "
                     + "search reports a flat landscape, and nothing about that is true."
            case .emptyNetwork:
                return "There are no layers here to search."
            case .scaleIsZero(let layer):
                return "Layer \(layer) has no spread at all — every weight in it is the same "
                     + "number — so a step relative to that spread would move nothing."
            }
        }

        private func pc(_ value: Double) -> String {
            "\((value * 100).rounded(toPlaces: 1))%"
        }
    }

    // MARK: - what a run is

    /// One run's settings, checked on the way in.
    public struct Settings: Equatable, Sendable {
        /// The step, as a fraction of each layer's own spread.
        public let step: Double
        /// How far along the estimated direction each generation moves. Kept
        /// separate from `step` because they answer different questions: how
        /// far to LOOK, and how far to GO once you have looked.
        public let rate: Double
        /// Antithetic pairs per generation. Each pair is two candidates, the
        /// same perturbation added and subtracted.
        public let pairs: Int
        public let generations: Int

        public init(step: Double = 0.05, rate: Double = 0.05,
                    pairs: Int = 10, generations: Int = 8) throws {
            guard stepBand.contains(step) else { throw Refusal.stepOutsideTheBand(step) }
            guard pairs >= 3 else { throw Refusal.tooFewPairs(pairs) }
            self.step = step; self.rate = rate
            self.pairs = pairs; self.generations = generations
        }

        /// Candidates scored per generation: two per pair, plus the one that
        /// measures where the search has actually got to.
        public var callsPerGeneration: Int { pairs * 2 + 1 }

        /// MEASURED, NOT ESTIMATED. 2.33 s per candidate on the desk bench.
        public static let secondsPerCandidate = 2.33

        public var seconds: TimeInterval {
            Double(callsPerGeneration * generations) * Settings.secondsPerCandidate
        }
    }

    // MARK: - the perturbation, which is never stored

    /// A candidate is a SEED, not a copy of the network.
    ///
    /// Two hundred thousand floats is 790 KB, and a generation of twenty would
    /// be sixteen megabytes of phone memory to hold candidates that exist only
    /// to be scored and thrown away. A seeded generator means a candidate is
    /// sixteen bytes and can be rebuilt byte-identically whenever it is wanted
    /// — including on a machine that was not there when it was scored, which is
    /// what makes a run reproducible and a winner checkable.
    public struct Perturbation: Equatable, Sendable {
        public let seed: UInt64
        public init(seed: UInt64) { self.seed = seed }

        /// xorshift64*, which is not cryptography and is not trying to be. What
        /// it has to be is the SAME sequence on every machine and in every
        /// process, which `SystemRandomNumberGenerator` deliberately is not and
        /// `Hasher` — seeded per launch — actively is not.
        public func noise(count: Int) -> [Float] {
            var state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
            var out = [Float](); out.reserveCapacity(count)
            func uniform() -> Double {
                state ^= state << 13; state ^= state >> 7; state ^= state << 17
                return Double(state % 1_000_000) / 1_000_000.0
            }
            while out.count < count {
                // Box–Muller, both halves kept: throwing one away doubles the
                // cost of a generation for nothing.
                let u1 = Swift.max(uniform(), 1e-9), u2 = uniform()
                let radius = (-2 * Foundation.log(u1)).squareRoot()
                out.append(Float(radius * Foundation.cos(2 * .pi * u2)))
                if out.count < count {
                    out.append(Float(radius * Foundation.sin(2 * .pi * u2)))
                }
            }
            return out
        }

        /// This generation's pair, derived so a run is one seed rather than a
        /// list of them.
        public func forPair(_ pair: Int, generation: Int) -> Perturbation {
            var mixed = seed &+ UInt64(generation) &* 0x9E37_79B9_7F4A_7C15
            mixed = mixed &+ UInt64(pair) &* 0xBF58_476D_1CE4_E5B9
            return Perturbation(seed: mixed)
        }
    }

    /// One candidate: the network with a perturbation added, or subtracted.
    ///
    /// ANTITHETIC, AND THAT IS THE WHOLE ESTIMATOR. Scoring `θ + σn` alone says
    /// whether that point is good; scoring `θ − σn` beside it says whether the
    /// DIRECTION is good, which is the thing the step needs and the thing a
    /// single sample cannot separate from wherever the network already was.
    public static func candidate(from layers: [DuckPolicyWriter.Layer],
                                 scales: [Double],
                                 perturbation: Perturbation,
                                 step: Double,
                                 adding: Bool) -> [DuckPolicyWriter.Layer] {
        var out: [DuckPolicyWriter.Layer] = []
        out.reserveCapacity(layers.count)
        for (index, layer) in layers.enumerated() {
            let scale = Float((scales.indices.contains(index) ? scales[index] : 0)
                              * step * (adding ? 1 : -1))
            let noise = perturbation.forPair(index, generation: 0).noise(count: layer.weights.count)
            out.append(DuckPolicyWriter.Layer(
                weights: zip(layer.weights, noise).map { $0 + $1 * scale },
                // THE BIASES ARE LEFT ALONE, and this is a measurement rather
                // than an oversight. A bias is one number per output against a
                // hundred-odd weights feeding it, so perturbing it at the same
                // relative scale moves the output far more than any single
                // weight does — the fastest way found to turn a walk into a
                // lean. The weights are where the behaviour is.
                biases: layer.biases,
                inputs: layer.inputs, outputs: layer.outputs))
        }
        return out
    }

    // MARK: - the step, from the order of the rewards

    /// Rewards to a number each, by ORDER rather than by size.
    ///
    /// ONE LUCKY EPISODE MUST NOT OWN A GENERATION. Weighting by raw reward
    /// lets a single candidate that travelled twice as far as the rest set the
    /// direction almost by itself, and on a bench where one drop can catch an
    /// edge that is a coin flip steering the search. Ranking spreads the same
    /// information over −0.5…0.5 and makes the step depend on which candidates
    /// beat which, which is the part that replicates.
    public static func ranks(of rewards: [Double]) -> [Double] {
        guard rewards.count > 1 else { return [Double](repeating: 0, count: rewards.count) }
        let order = rewards.enumerated().sorted { $0.element < $1.element }.map(\.offset)
        var out = [Double](repeating: 0, count: rewards.count)
        var place = 0
        while place < order.count {
            // TIES SHARE A PLACE, AND THIS IS NOT A NICETY. Ranking by sorted
            // position alone hands equal rewards DIFFERENT ranks, decided by
            // where they happened to sit in the array — so a pair whose two
            // halves scored exactly the same still produces an advantage, and
            // the network moves along a direction nothing preferred.
            //
            // That is not a rare case. Every candidate that fell over scores
            // the same −1, so a generation that knocks half its candidates down
            // would step confidently along the average of their noise, which is
            // noise. Averaging the tied places makes those advantages exactly
            // zero, which is what a tie means.
            var end = place
            while end + 1 < order.count,
                  rewards[order[end + 1]] == rewards[order[place]] { end += 1 }
            let shared = Double(place + end) / 2
            for k in place...end {
                out[order[k]] = shared / Double(rewards.count - 1) - 0.5
            }
            place = end + 1
        }
        return out
    }

    /// The network one generation on.
    ///
    /// `rewards` is two per pair, added then subtracted, in pair order — the
    /// order `candidate(from:...)` is meant to be called in.
    public static func stepped(_ layers: [DuckPolicyWriter.Layer],
                               scales: [Double],
                               seed: Perturbation,
                               generation: Int,
                               rewards: [Double],
                               settings: Settings) -> [DuckPolicyWriter.Layer] {
        let rank = ranks(of: rewards)
        var out = layers
        for (index, layer) in layers.enumerated() {
            let scale = scales.indices.contains(index) ? scales[index] : 0
            guard scale > 0 else { continue }
            var weights = layer.weights
            for pair in 0..<settings.pairs {
                let plus = pair * 2, minus = plus + 1
                guard rank.indices.contains(minus) else { continue }
                let advantage = rank[plus] - rank[minus]
                if advantage == 0 { continue }
                let move = Float(scale * settings.rate * advantage / Double(settings.pairs))
                let perturbation = seed.forPair(pair, generation: generation)
                let noise = perturbation.forPair(index, generation: 0)
                    .noise(count: weights.count)
                for k in weights.indices { weights[k] += noise[k] * move }
            }
            out[index] = DuckPolicyWriter.Layer(weights: weights, biases: layer.biases,
                                                inputs: layer.inputs, outputs: layer.outputs)
        }
        return out
    }

    // MARK: - a candidate that fell over has not walked

    /// What a scored episode is worth to the search.
    ///
    /// A DUCK THAT FELL OVER HAS NOT WALKED, whatever it travelled while it was
    /// falling. Without this a candidate that dives forward and lands on its
    /// face outscores one that walks, and the search learns to dive.
    public static func reward(travelled: Double, standing: Int, episodes: Int) -> Double {
        guard episodes > 0, standing == episodes else { return -1 }
        return travelled
    }

    // MARK: - what the run is allowed to claim

    /// How much of a behaviour survived, as a fraction of what the unchanged
    /// network did. One is "unchanged"; below one is "this was spent".
    public static func kept(after: Double, before: Double) -> Double {
        guard before != 0, before.isFinite, after.isFinite else { return .nan }
        return after / before
    }

    /// A run's verdict over the command it searched and the ones it did not.
    ///
    /// THE HELD-OUT COMMANDS ARE THE POINT. The twenty-eight-number search was
    /// only ever asked to walk forwards, and four winners in eight paid for
    /// their forward reward by collapsing sideways travel to under two per cent
    /// while passing every gate this app has. A gain under the command you
    /// searched is not a finding on its own; a gain under that command WITH the
    /// others intact is.
    public struct Verdict: Equatable, Sendable {
        /// Forward travel, tuned over unchanged.
        public let gained: Double
        /// The smallest `kept` across every command the search never saw.
        public let keptElsewhere: Double
        /// Every drop still ended standing.
        public let stoodUp: Bool

        public init(gained: Double, keptElsewhere: Double, stoodUp: Bool) {
            self.gained = gained; self.keptElsewhere = keptElsewhere; self.stoodUp = stoodUp
        }

        /// A THIRD OF THE UNSEEN BEHAVIOUR IS THE LINE, and it is drawn from
        /// the measured split rather than from taste: the farming winners kept
        /// 1.6–2.0%, the honest ones 82–86%. There is nothing in between, so
        /// any threshold in the gap separates them; a third is comfortably
        /// inside it and does not pretend to a precision the eight runs cannot
        /// support.
        public static let keptFloor = 0.33

        public var survived: Bool {
            stoodUp && gained > 1 && keptElsewhere >= Verdict.keptFloor
        }
    }

    public static func verdictSaid(_ verdict: Verdict) -> String {
        guard verdict.stoodUp else {
            return "This search has not produced a policy worth keeping: the duck did not end "
                 + "every episode on its feet."
        }
        let gained = ((verdict.gained - 1) * 100).rounded(toPlaces: 1)
        let kept = (verdict.keptElsewhere * 100).rounded(toPlaces: 0)
        guard verdict.gained > 1 else {
            return "This search went backwards: the network travels \(abs(gained))% LESS than "
                 + "the one it started from. The one it started from is still the better policy."
        }
        guard verdict.keptElsewhere >= Verdict.keptFloor else {
            return "This network travels \(gained)% further under the command it was searched "
                 + "against, and it bought that by giving up what it could do under the commands "
                 + "it was not: only \(kept)% of those are left. That is the trade a reward "
                 + "search makes when nobody is watching the other directions, and it is why "
                 + "this screen watches them."
        }
        return "This network travels \(gained)% further under the command it was searched "
             + "against, and it kept \(kept)% of what it could do under commands it never saw. "
             + "Both halves are measured on your bench, on the same drops, against the network "
             + "it started from."
    }

    /// What a searched network is called on disk.
    ///
    /// THE DIGEST, NOT THE BASE'S NAME, for the reason `DuckTuner.filename`
    /// gives: three runs against `alpha_walking` are three different networks,
    /// and one name for all of them is how the second overwrites the first on
    /// somebody's robot. A DIFFERENT PREFIX from the tuner's, because a
    /// searched network and a folded one have different provenance and a person
    /// looking at a folder is entitled to tell them apart.
    public static func filename(for policy: DuckPolicy) -> String {
        "searched-\(policy.fingerprint.prefix(12)).onnx"
    }

    // MARK: - the sentences

    /// WHAT THIS RUN IS, said where somebody is about to start one. Every word
    /// of it is load-bearing: the phone does search a network's own weights,
    /// and it does not learn one from nothing.
    public static let whatThisIs =
        "This searches the weights of a network you already have — all 197,774 of them — "
      + "against a reward your own bench measures. It does not learn a network from nothing: "
      + "that needs a simulator and a graphics card, and the brief on this screen is written "
      + "for one."

    public static let howItRuns =
        "Each generation tries pairs of small random changes, scores every one on the bench, and "
      + "steps the network towards whichever half of each pair did better. Nothing is downloaded "
      + "and nothing is sent anywhere: the phone holds the network, your bench does the physics."

    public static let theStepSaid =
        "How far each generation looks, as a fraction of what the network's own weights already "
      + "vary by. A tenth is the most this bench has been measured to survive; a quarter walks "
      + "the duck backwards while still passing every standing check."

    public static func generationSaid(_ number: Int, travelled: Double, standing: Int,
                                      episodes: Int) -> String {
        "Generation \(number): \(travelled.rounded(toPlaces: 3)) m, standing on "
      + "\(standing) of \(episodes)."
    }

    public static func costSaid(_ settings: Settings) -> String {
        let minutes = (settings.seconds / 60).rounded(toPlaces: 0)
        return "\(settings.generations) generations of \(settings.pairs) pairs is "
             + "\(settings.callsPerGeneration * settings.generations) runs on your bench, about "
             + "\(minutes) minutes. You can stop it after any generation and keep what it has."
    }

    /// THE TWO PATHS, BOTH NAMED, on the screen that used to deny both of them.
    ///
    /// What was here said "Nothing here has been trained. A phone has no
    /// Python, no mjlab and no GPU — this is a specification for a machine that
    /// has all three." Every clause of that is true and the sentence as a whole
    /// was not: it reads as "a phone cannot train", and a phone can. It can
    /// read all 197,774 weights out of a network, move them under a reward its
    /// own bench measures, and write a network back that walks further —
    /// measured at +16.9% with 99% of its untrained behaviour intact. What a
    /// phone cannot do is learn a network from nothing, which is what the
    /// config on this screen is FOR. Two claims, and the screen now makes both
    /// rather than collapsing them into a denial.
    public static let bothPathsSaid =
        "Nothing on this screen has been trained yet — this is a specification for a machine "
      + "with a simulator and a graphics card, which is what learning a network from nothing "
      + "needs. Searching a network you already have is a different job, and this phone can do "
      + "that one on your own bench."

    // MARK: - the words on the screen

    public static let whatThisRunIsHeading = "What this run is"
    public static let theNetworkHeading    = "The network to search"
    public static let howFarToLookHeading  = "How far to look"
    public static let generationsHeading   = "Generations"
    public static let whatCameOutHeading   = "What came out"
    public static let startFromSaid        = "Start from"
    public static let noBaseSaid           = "None"
    public static let stepSaid             = "Step"
    public static let runItHereSaid        = "Run it here"
    public static let stopSaid             = "Stop"
    public static let keepThisNetworkSaid  = "Keep this network"
    public static let pairsSaid            = "Pairs each generation"
    public static let generationsSetSaid   = "Generations"

    /// The base is gone from disk between picking it and pressing run.
    public static let baseIsGoneSaid =
        "That network is not on this phone any more."

    /// A step, as a percentage, in the one place that formats it.
    public static func percentSaid(_ fraction: Double) -> String {
        let shown = (fraction * 1000).rounded() / 10
        return "\(shown)%"
    }

    /// How much bench time a run has spent, which is the only honest progress
    /// bar here: a generation is not a fixed fraction of an answer.
    public static func benchRunsSaid(_ scored: Int) -> String {
        "\(scored) run\(scored == 1 ? "" : "s") on the bench so far."
    }

    /// Everything this type says, so a screen can be checked against it.
    public static let everySentence: [String] = [
        whatThisIs, howItRuns, theStepSaid, bothPathsSaid,
        baseIsGoneSaid, benchRunsSaid(3), benchRunsSaid(1),
        generationSaid(1, travelled: 1.2, standing: 4, episodes: 4),
        Refusal.noCommand.message, Refusal.emptyNetwork.message,
        Refusal.stepOutsideTheBand(0.5).message, Refusal.tooFewPairs(1).message,
        Refusal.scaleIsZero(layer: 0).message,
    ]
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
