import Foundation
import DuckKit
import StudioKit

/// Drives a search over a network's own weights, one generation at a time.
///
/// THE SAME SHAPE AS `TuneRun`, AND DELIBERATELY SO: the same `armed`/`ask`/
/// `put` trio, the same "stop after any generation and keep what you have", the
/// same refusal-first handling. What differs is what is being searched. `TuneRun`
/// moves twenty-eight numbers folded onto the network's output; this moves the
/// 197,774 numbers the network is made of, which is the difference between
/// trimming a policy and training one.
///
/// EVERY DECISION IN HERE IS THE KIT'S. This class holds a socket, a cancel
/// flag and a list of published values; the step, the ranking, the reward, the
/// band and the verdict all live in `WeightSearch` where they can be tested on
/// a machine with no bench and no phone.
@MainActor
final class WeightSearchRun: ObservableObject {

    @Published var isRunning = false
    @Published var generations: [Line] = []
    @Published var verdict: WeightSearch.Verdict?
    @Published var said: String?
    @Published var failure: String?
    @Published var result: Result?
    /// Candidates scored so far, against the number the settings promised, so
    /// the screen can say how far through it is rather than how long it feels.
    @Published var scored = 0

    private var stopped = false

    struct Line: Identifiable {
        let id: Int
        let travelled: Double
        let standing: Int
        let episodes: Int
        var said: String {
            WeightSearch.generationSaid(id, travelled: travelled,
                                        standing: standing, episodes: episodes)
        }
    }

    struct Result {
        let onnx: Data
        let filename: String
        let verdict: WeightSearch.Verdict
    }

    func stop() { stopped = true }

    /// One search. `base` is the network to start from; everything else the run
    /// needs it reads off the bench.
    ///
    /// THE HELD-OUT COMMAND IS NOT OPTIONAL AND NOT A SETTING. A gain measured
    /// only under the command the search optimised is the exact number four of
    /// eight tuned policies used to look good while having quietly stopped
    /// moving sideways. It is measured before the run and again after it, on
    /// the same drops, and it goes in the verdict whatever it says.
    func search(base: Data,
                settings: WeightSearch.Settings,
                benches: BenchStore) async {
        isRunning = true; stopped = false
        failure = nil; result = nil; verdict = nil; said = nil
        generations = []; scored = 0
        defer { isRunning = false }

        do {
            let (address, token) = try armed(benches)
            let host = try? DuckBench.readHealth(
                await ask(DuckBench.health(address), token: token)).host

            let policy = try DuckPolicy.load(from: base)
            let start = policy.parameters
            guard !start.layers.isEmpty else { throw WeightSearch.Refusal.emptyNetwork }
            let scales = WeightSearch.scales(of: start.layers)
            guard let widest = scales.max(), widest > 0 else {
                throw WeightSearch.Refusal.scaleIsZero(layer: 0)
            }

            func score(_ layers: [DuckPolicyWriter.Layer],
                       under command: [DuckBench.Step]) async throws
                -> (travelled: Double, standing: Int, episodes: Int) {
                let file = try DuckPolicyWriter.encoded(mean: start.mean, std: start.std,
                                                        layers: layers)
                let named = try await put(file, address: address, token: token, host: host)
                let answer = try DuckBench.readTuned(await ask(try DuckBench.tune(
                    address, policy: named,
                    gain: [Double](repeating: 1, count: DuckModel.policyJointCount),
                    offset: [Double](repeating: 0, count: DuckModel.policyJointCount),
                    seconds: DuckTuner.Schedule.onAPhone.seconds,
                    drops: DuckTuner.Schedule.onAPhone.heldOutDrops,
                    schedule: command,
                    terms: DuckTuner.terms.map(\.key)), token: token))
                scored += 1
                return (answer.travelled, answer.standing, answer.episodes)
            }

            // WHERE IT STARTED, UNDER BOTH COMMANDS, BEFORE ANYTHING MOVES.
            let before = try await score(start.layers, under: DuckBench.walkingCommand)
            let beforeElsewhere = try await score(start.layers, under: DuckBench.sidewaysCommand)
            generations.append(Line(id: 0, travelled: before.travelled,
                                    standing: before.standing, episodes: before.episodes))

            let seed = WeightSearch.Perturbation(seed: UInt64.random(in: 1...UInt64(Int32.max)))
            var theta = start.layers

            for generation in 1...settings.generations {
                if stopped { break }
                var rewards: [Double] = []
                for pair in 0..<settings.pairs {
                    if stopped { break }
                    let perturbation = seed.forPair(pair, generation: generation)
                    for adding in [true, false] {
                        let candidate = WeightSearch.candidate(
                            from: theta, scales: scales, perturbation: perturbation,
                            step: settings.step, adding: adding)
                        let got = try await score(candidate, under: DuckBench.walkingCommand)
                        rewards.append(WeightSearch.reward(travelled: got.travelled,
                                                           standing: got.standing,
                                                           episodes: got.episodes))
                    }
                }
                // A GENERATION CUT IN HALF IS NOT STEPPED. Ranking an incomplete
                // set puts the pairs that were scored against pairs that were
                // not, which is a step along whichever direction happened to be
                // measured first.
                guard rewards.count == settings.pairs * 2 else { break }
                theta = WeightSearch.stepped(theta, scales: scales, seed: seed,
                                             generation: generation, rewards: rewards,
                                             settings: settings)
                let now = try await score(theta, under: DuckBench.walkingCommand)
                generations.append(Line(id: generation, travelled: now.travelled,
                                        standing: now.standing, episodes: now.episodes))
            }

            let after = try await score(theta, under: DuckBench.walkingCommand)
            let afterElsewhere = try await score(theta, under: DuckBench.sidewaysCommand)
            let reached = WeightSearch.Verdict(
                gained: WeightSearch.kept(after: after.travelled, before: before.travelled),
                keptElsewhere: WeightSearch.kept(after: afterElsewhere.travelled,
                                                 before: beforeElsewhere.travelled),
                stoodUp: after.standing == after.episodes)
            verdict = reached
            said = WeightSearch.verdictSaid(reached)
            let searched = try DuckPolicyWriter.encoded(mean: start.mean, std: start.std,
                                                        layers: theta)
            result = Result(onnx: searched,
                            filename: WeightSearch.filename(for: try DuckPolicy.load(from: searched)),
                            verdict: reached)
        } catch let refusal as WeightSearch.Refusal {
            failure = refusal.message
        } catch let refusal as DuckBench.Refusal {
            failure = refusal.message
        } catch let error as DuckBench.ReadError {
            failure = error.message
        } catch {
            failure = error.localizedDescription
        }
    }

    // MARK: - the bench, exactly as `TuneRun` reaches it

    private func armed(_ benches: BenchStore) throws -> (DuckBench.Address, String?) {
        guard let chosen = benches.selected else { throw DuckBench.Refusal.empty }
        let armed = benches.armed(chosen)
        return (try armed.resolved(), armed.token)
    }

    private func ask(_ call: DuckBench.Call, token: String?) async throws -> Data {
        try await URLSession.shared.data(
            for: DuckBench.urlRequest(for: call, token: token)).0
    }

    /// THE PHONE BENCH AND A DESK BENCH WANT DIFFERENT BYTES, and `TuneView`
    /// documents at length how that was found. The same branch, for the same
    /// reason: a desk bench loads the file through onnxruntime but cannot dump
    /// an upload's parameters, and `/tune` folds a gain into the last layer,
    /// so it needs both.
    private func put(_ file: Data, address: DuckBench.Address,
                     token: String?, host: DuckBench.Health.Host?) async throws -> String {
        let bytes = try DuckPolicy.load(from: file).canonicalParameterBytes
        if host?.kind == .phone {
            return try DuckBench.readUploaded(
                await ask(try DuckBench.uploadParameters(address, canonicalBytes: bytes),
                          token: token))
        }
        return try DuckBench.readUploaded(
            await ask(try DuckBench.upload(address, onnx: file, parameters: bytes), token: token))
    }
}
