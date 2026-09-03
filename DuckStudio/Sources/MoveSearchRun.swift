import SwiftUI
import DuckKit
import StudioKit

/// The keyframe search, as a thing that runs rather than a thing that is drawn.
///
/// EVERY DECISION IN HERE IS THE KIT'S. What a cell is worth is
/// `MoveSearch.cellScore`; what a candidate is, is `MoveSearch.mutate`; what is
/// thrown away is `MoveSearch.rejected`; what the verdict says is
/// `MoveSearch.heldOutVerdict`. This type owns the HTTP, the ordering and the
/// stopping, and nothing else — the app target draws and does not compute, and
/// a search that invented its own arithmetic would be the largest violation of
/// that rule the app could contain.
///
/// MODELLED ON `TuneRun`, AND THE PER-CELL LOOP IS RE-IMPLEMENTED RATHER THAN
/// SHARED. `StairsChallengeView.scoreAll` does the same fourteen requests with
/// the same 180 s client allowance, and that file belongs to another owner:
/// reaching into it would be an edit to a screen this track does not own, and
/// copying its shape is the smaller cost. What is copied is the SHAPE — one
/// cell per request, a failed cell named and the run continuing — not any
/// arithmetic, because there is none there either.
@MainActor
final class MoveSearchRun: ObservableObject {

    // MARK: - what the screen watches

    @Published var probing = true
    /// The bench answered and has no `/climb`. A permanent fact about that
    /// bench, and a different sentence from one that did not answer at all.
    @Published var notYet: String?
    @Published var unreachable: String?
    @Published var host: DuckBench.Health.Host?
    @Published var grid: [DuckBench.Cell] = StairsChallenge.Grid.fallback
    @Published var gridIsThePublishedOne = true

    @Published var isRunning = false
    /// What it is doing right now, in a person's words.
    @Published var phase = ""
    @Published var requestsDone = 0
    @Published var duration = DuckTuner.durationNotMeasuredYet

    /// The move as written, measured on all fourteen.
    @Published var baseline: MoveSearch.Reading?
    @Published var baselineCells: [DuckBench.Climbed] = []
    /// What each handle is worth, and the spread it is ranked against.
    @Published var swings: [MoveSearch.Swing] = []
    @Published var spread: Double?
    /// Whether `spread` came from a held-out check on THIS move. Nil spread
    /// with this false is "not measured yet"; nil with it true is "measured
    /// and could not be" — two different sentences on the swing table.
    @Published var spreadWasMeasured = false
    /// How many requests the phase in flight will make — the denominator the
    /// live counter is honest against. The whole-workflow figure belongs to
    /// the cost sentence, not to a tally that resets every run.
    @Published var expectedRequests = 0
    @Published var generations: [MoveSearch.Generation] = []
    @Published var result: Result?
    @Published var failure: String?
    /// Named cells that did not come back, kept rather than swallowed.
    @Published var failedCells: [String] = []

    struct Result {
        let verdict: String
        let residual: String
        let score: StairsChallenge.Score
        let move: StairsChallenge.Move
        let point: MoveSearch.Point
        let staleParams: Bool
        let carriesALandingLaw: Bool
    }

    private var stopped = false
    private var startedAt = Date()

    /// STOP IS NEVER DISABLED. It sets a flag the loops read between cells; the
    /// request in flight finishes and nothing after it is sent.
    func stop() { stopped = true; phase = "Stopping after this cell…" }

    // MARK: - asking the bench what it can do

    func probe(benches: BenchStore) async {
        probing = true
        defer { probing = false }
        notYet = nil; unreachable = nil
        let address: DuckBench.Address, token: String?
        do {
            (address, token) = try Self.armed(benches)
            host = try DuckBench.readHealth(
                await Self.ask(DuckBench.health(address), token: token,
                               seconds: Self.gridSeconds)).host
        } catch {
            // A BENCH THAT DID NOT ANSWER AT ALL IS NOT A BENCH THAT CANNOT
            // SCORE. Two states, two sentences.
            unreachable = PhoneBenchReport.notListening
            return
        }
        do {
            let data = try await Self.ask(DuckBench.climbGrid(address), token: token,
                                          seconds: Self.gridSeconds)
            grid = StairsChallenge.Grid.cells(from: data)
            gridIsThePublishedOne = StairsChallenge.Grid.isPublishedGrid(grid)
        } catch {
            grid = StairsChallenge.Grid.fallback
            gridIsThePublishedOne = true
            notYet = StairsChallenge.noClimbHere(bench: benches.selected?.name ?? "this bench")
        }
    }

    var canScore: Bool { notYet == nil && unreachable == nil && !probing }

    // MARK: - the move as written

    func measure(_ move: StairsChallenge.Move, rise: Double, benches: BenchStore) async {
        await run(label: "Measuring this move as written", expecting: self.grid.count,
                  benches: benches) { address, token in
            // A NEW BASELINE INVALIDATES THE LAST HELD-OUT SPREAD, and the
            // swings that were ranked against it: they were about another
            // measurement of another move.
            self.spread = nil; self.spreadWasMeasured = false; self.swings = []
            let cells = try await self.score(move, rise: rise, cells: self.grid,
                                             address: address, token: token)
            guard !cells.isEmpty else { return }
            // THE READING FIRST. A partial re-measure must not overwrite the
            // cells while the older validated reading stays, leaving the
            // swing button enabled over a baseline that no longer matches.
            let reading = try MoveSearch.reading(cells)
            self.baselineCells = cells
            self.baseline = reading
        }
    }

    // MARK: - what each handle is worth

    /// Two real scored runs per handle, at +room and −room, on the core nine.
    ///
    /// A FINITE DIFFERENCE, NOT A GRADIENT. Nothing here differentiates
    /// anything, and the sentence under each row says "the score swung".
    func measureSwings(_ move: StairsChallenge.Move, spec: MoveSearch.Spec,
                       benches: BenchStore) async {
        guard let baselineCells = baselineCellsCore else {
            failure = MoveSearch.Refusal.noBaselineYet.message
            return
        }
        await run(label: "Measuring what each handle is worth",
                  expecting: spec.handles.count * 2 * self.core.count,
                  benches: benches) { address, token in
            var measured: [MoveSearch.Swing] = []
            let base = MoveSearch.coreMean(baselineCells)
            for handle in spec.handles {
                if self.stopped { break }
                var ends: [Double] = []
                for direction in [1.0, -1.0] {
                    let point = MoveSearch.probe(spec, handle: handle, direction: direction)
                    let edited = try MoveSearch.apply(point, to: move, spec: spec)
                    let cells = try await self.score(edited, rise: spec.rise,
                                                     cells: self.core,
                                                     address: address, token: token)
                    // THE SAME TWO GUARDS THE SEARCH LOOP TAKES, in the same
                    // order: a probe with fewer than nine cells or an invalid
                    // one is named, not averaged. `rejected` answers nil for
                    // an empty array, so the count must be checked first.
                    guard cells.count == self.core.count else {
                        self.failedCells.append(
                            "\(handle.title(in: move)) \(handle.roomSaid): "
                            + MoveSearch.Refusal.partialGrid(answered: cells.count,
                                                             of: self.core.count).message)
                        break
                    }
                    if let rejection = MoveSearch.rejected(cells) {
                        self.failedCells.append(
                            "\(handle.title(in: move)) \(handle.roomSaid): \(rejection.message)")
                        break
                    }
                    ends.append(MoveSearch.coreMean(cells))
                }
                // ONE UNUSABLE HANDLE SKIPS ITS ROW, not every row after it; a
                // real Stop still leaves through the check at the top.
                guard ends.count == 2 else { continue }
                measured.append(MoveSearch.Swing(handle: handle, base: base,
                                                 up: ends[0], down: ends[1]))
                self.swings = measured
            }
        }
    }

    // MARK: - the search

    func search(_ move: StairsChallenge.Move, spec: MoveSearch.Spec,
                benches: BenchStore) async {
        guard let baselineCells = baselineCellsCore,
              let baselineExtended = baselineCellsExtended else {
            failure = MoveSearch.Refusal.noBaselineYet.message
            return
        }
        generations = []; result = nil
        await run(label: "Searching",
                  expecting: MoveSearch.budget(for: spec).searchRequests
                           + MoveSearch.budget(for: spec).checkRequests,
                  benches: benches) { address, token in
            var rng = DuckTuner.Seeded(seed: spec.seed)
            var parent = MoveSearch.Point.unchanged
            var parentScore = MoveSearch.coreMean(baselineCells)
            var parentCells = baselineCells

            for index in 1...max(spec.generations, 1) {
                if self.stopped { break }
                var bestChild: MoveSearch.Point?
                var bestChildScore = parentScore
                var bestChildCells: [DuckBench.Climbed] = []
                var invalid = 0, noFlight = 0

                for _ in 0..<max(spec.lambda, 1) {
                    if self.stopped { break }
                    let child = MoveSearch.mutate(parent, with: spec, using: &rng)
                    let edited = try MoveSearch.apply(child, to: move, spec: spec)
                    let cells = try await self.score(edited, rise: spec.rise, cells: self.core,
                                                     address: address, token: token)
                    guard cells.count == self.core.count else { continue }
                    // TWO WAYS OUT BEFORE A NUMBER IS COMPARED, each counted
                    // under its own name. There is no torque rejection — see
                    // `MoveSearch.rejected`.
                    switch MoveSearch.rejected(cells) {
                    case .invalid?:            invalid += 1; continue
                    case .neverReachedFlight?: noFlight += 1; continue
                    case nil:                  break
                    }
                    let scored = MoveSearch.coreMean(cells)
                    if scored > bestChildScore {
                        bestChild = child; bestChildScore = scored; bestChildCells = cells
                    }
                }
                if let bestChild, !bestChildCells.isEmpty {
                    parent = bestChild; parentScore = bestChildScore; parentCells = bestChildCells
                }
                self.generations.append(.init(index: index, best: parentScore,
                                              rejectedAsInvalid: invalid,
                                              rejectedAsNeverReachedFlight: noFlight))
            }

            // THE ONLY QUESTION THAT MATTERS: did it survive the conditions it
            // was never searched on?
            // A CUT RUN PERFORMS NO HELD-OUT CHECK AND PUBLISHES NO RESULT.
            // `score` returns nothing once stopped, and a Result built from
            // nine core cells and zero extended ones would print a fourteen-
            // cell claim. Everything measured so far stays on screen in
            // `generations`.
            if self.stopped { return }
            let winner = try MoveSearch.apply(parent, to: move, spec: spec)
            let checked = try await self.score(winner, rise: spec.rise, cells: self.extended,
                                               address: address, token: token)
            let differences = MoveSearch.pairedDifferences(candidate: checked,
                                                           baseline: baselineExtended)
            let measured = MoveSearch.conditionSpread(differences)
            self.spread = measured
            self.spreadWasMeasured = true
            let verdict = measured.map {
                MoveSearch.heldOutVerdict(
                    meanGain: MoveSearch.mean(differences), conditionSpread: $0,
                    flightKept: MoveSearch.flightCells(checked),
                    baselineFlight: MoveSearch.flightCells(baselineExtended))
            } ?? MoveSearch.noConditionSpread

            self.result = Result(
                verdict: verdict,
                residual: parent.described(spec, in: move),
                score: MoveSearch.winnersScore(rise: spec.rise, core: parentCells,
                                               extended: checked),
                move: winner, point: parent,
                staleParams: MoveSearch.carriesParams(move),
                carriesALandingLaw: MoveSearch.carriesALandingLaw(move))
            Haptic.finished()
        }
    }

    // MARK: - the grid, split the way the search uses it

    private var core: [DuckBench.Cell] { grid.filter { $0.tier == .core } }
    private var extended: [DuckBench.Cell] { grid.filter { $0.tier == .ext } }

    private var baselineCellsCore: [DuckBench.Climbed]? {
        let core = baselineCells.filter { $0.cell.tier == .core }
        return core.isEmpty ? nil : core
    }

    private var baselineCellsExtended: [DuckBench.Climbed]? {
        let ext = baselineCells.filter { $0.cell.tier == .ext }
        return ext.isEmpty ? nil : ext
    }

    // MARK: - the wire

    /// One cell per request, a failed cell NAMED and the run continuing.
    ///
    /// A CELL THAT FAILED IS NAMED AND THE REST STILL RUN, which is what
    /// `StairsChallengeView` does for the same reason: abandoning thirteen real
    /// measurements to avoid printing one sentence is a worse answer than the
    /// sentence.
    private func score(_ move: StairsChallenge.Move, rise: Double, cells: [DuckBench.Cell],
                       address: DuckBench.Address, token: String?) async throws
        -> [DuckBench.Climbed] {
        var done: [DuckBench.Climbed] = []
        for cell in cells {
            if stopped { break }
            let call = try DuckBench.climb(address, move: move, rise: rise, cell: cell)
            do {
                done.append(try DuckBench.readClimbed(
                    await Self.ask(call, token: token, seconds: Self.cellSeconds)))
            } catch {
                failedCells.append("\(cell.said(rise: rise)): \(Self.message(error))")
            }
            requestsDone += 1
            duration = DuckTuner.durationMeasured(episodes: requestsDone,
                                                  elapsed: Date().timeIntervalSince(startedAt))
        }
        return done
    }

    /// The one place a run starts, ends and reports. Everything above hands it
    /// a body and a label.
    private func run(label: String, expecting: Int, benches: BenchStore,
                     _ body: (DuckBench.Address, String?) async throws -> Void) async {
        guard !isRunning else { return }
        isRunning = true; stopped = false; failure = nil
        failedCells = []; requestsDone = 0; expectedRequests = expecting; startedAt = Date()
        phase = label
        defer { isRunning = false; phase = "" }
        do {
            let (address, token) = try Self.armed(benches)
            try await body(address, token)
        } catch let refusal as MoveSearch.Refusal {
            failure = refusal.message
        } catch let refusal as DuckBench.Refusal {
            failure = refusal.message
        } catch let refusal as BenchEndpoint.Refusal {
            failure = refusal.message
        } catch let refusal as StairsChallenge.Move.Refusal {
            failure = refusal.message
        } catch let error as DuckBench.ReadError {
            failure = error.message
        } catch {
            failure = error.localizedDescription
        }
    }

    private static func armed(_ benches: BenchStore) throws -> (DuckBench.Address, String?) {
        guard let chosen = benches.selected else { throw DuckBench.Refusal.empty }
        let armed = benches.armed(chosen)
        return (try armed.resolved(), armed.token)
    }

    private static func ask(_ call: DuckBench.Call, token: String?,
                            seconds: Double) async throws -> Data {
        var request = DuckBench.urlRequest(for: call, token: token)
        request.timeoutInterval = seconds
        return try await URLSession.shared.data(for: request).0
    }

    /// GENEROUS, BECAUSE THE FLOOR IS THE PHONE. Read from
    /// `StairsChallengeView`'s own allowance: a client timeout shorter than the
    /// bench's own per-request deadline reports a working bench as a dead one.
    private static let cellSeconds: Double = 180
    private static let gridSeconds: Double = 30

    private static func message(_ error: Error) -> String {
        if let refusal = error as? DuckBench.Refusal { return refusal.message }
        if let refusal = error as? BenchEndpoint.Refusal { return refusal.message }
        if let read = error as? DuckBench.ReadError { return read.message }
        return error.localizedDescription
    }
}
