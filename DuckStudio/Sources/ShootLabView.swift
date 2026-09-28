import SwiftUI
import DuckKit
import StudioKit

/// Train a duck to shoot, end to end, on this phone's physics.
///
/// ONE SCREEN, SIX STEPS, EACH OF THEM THE REAL THING. The pitch is drawn over
/// the canon plant; every shot is a `POST /shoot` to the selected bench (this
/// iPhone by default); training is `Shoot.Search` over the controller's numbers,
/// scored by goals; judging goes through Compare's record; the camera test
/// reruns the trained shooter seeing only what its head camera could.
struct ShootLabView: View {
    @ObservedObject var benches: BenchStore
    @StateObject private var compare = CompareStore()

    // What is on the pitch now.
    @State private var cellIndex = 4
    @State private var shot: Shoot.Shot?
    @State private var kickAlone: DuckIntentClip?
    @State private var playhead: TimeInterval = 0
    @State private var isRunning = true
    @State private var orbit = OrbitState()

    // Work in flight and what it said.
    @State private var busy: String?
    @State private var line: String?
    @State private var task: Task<Void, Never>?

    // The shooter being trained, and what it has scored.
    @State private var search = Shoot.Search(children: 3)
    @State private var trainedWith: String = "the hand-written numbers"
    @State private var testScore: (state: Shoot.Score?, camera: Shoot.Score?) = (nil, nil)
    @State private var duel: (left: Shoot.Shot, right: Shoot.Shot, leftIsTrained: Bool)?
    @AppStorage("duckstudio.shooter") private var savedShooter = ""

    /// Five of the nine core spots train; all nine test.
    private let trainCells = [0, 2, 4, 6, 8].map { Shoot.coreCells[$0] }
    private var cell: Shoot.Cell { Shoot.coreCells[cellIndex] }
    private var pitch: Shoot.Pitch { .canon }

    var body: some View {
        VStack(spacing: 0) {
            stage.frame(height: 300)
            List {
                Section {
                    Text(ShootWords.intro).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let busy {
                        HStack { ProgressView(); Text(busy).font(.footnote) }
                        Button("Stop", role: .cancel) { task?.cancel(); self.busy = nil }
                    }
                    if let line {
                        Text(line).font(.footnote).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listRowBackground(Theme.surfacePrimary)
                stepPitch
                stepKickAlone
                stepHandWritten
                stepTrain
                stepJudge
                stepCamera
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
        }
        .navigationTitle(ShootWords.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: restore)
        .onDisappear { task?.cancel() }
    }

    // MARK: - the pitch

    @ViewBuilder private var stage: some View {
        if let duel {
            DuelStage(left: duel.left.clip, right: duel.right.clip,
                      caption: "Same ball spot. Which shot looks better?",
                      balls: (duel.left.ball, duel.right.ball), pitch: pitch) { choice, reasons in
                judge(choice, reasons)
            }
        } else {
            VStack(spacing: 0) {
                let clip = shot?.clip ?? kickAlone
                let t = min(playhead, clip?.duration ?? 0)
                let ball = shot?.ball(at: t) ?? (kickAlone == nil ? SIMD2(cell.x, cell.y) : nil)
                DuckStage(pose: clip.map { .at($0.pose(at: t)) } ?? startPose,
                          environment: .bareFloor,
                          props: ball.map { [ShootBall.prop(at: $0)] } ?? [],
                          orbit: $orbit, rolling: ball, pitch: kickAlone == nil ? pitch : nil)
                    .overlay(alignment: .topLeading) { badge(t) }
                if let clip {
                    TransportBar(duration: clip.duration, playhead: $playhead, isRunning: $isRunning)
                        .padding(.horizontal, Theme.spacing(.snug))
                }
            }
        }
    }

    private var startPose: StagePose {
        var s = DuckStance.home
        s = DuckStance(jointAngles: s.jointAngles,
                       root: DuckIntentClip.Root(x: pitch.duckStart.x, y: pitch.duckStart.y, z: 0.12,
                                                 quaternion: (1, 0, 0, 0)))
        return s
    }

    @ViewBuilder private func badge(_ t: TimeInterval) -> some View {
        if let shot {
            let ended = t >= shot.clip.duration - 0.05
            Text(ended ? shot.outcome.said : shot.phase(at: t).capitalized)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(ended && shot.goal ? Theme.measured : Color.black.opacity(0.55),
                            in: Capsule())
                .foregroundStyle(.white)
                .padding(10)
        }
    }

    // MARK: - the six steps

    private func step(_ i: Int) -> ShootWords.Step { ShootWords.steps[i] }

    private func card<Content: View>(_ i: Int, @ViewBuilder _ content: () -> Content) -> some View {
        Section {
            Text(step(i).body).font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        } header: {
            SectionHeading(text: step(i).title)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var stepPitch: some View {
        card(0) {
            Picker("Ball spot", selection: $cellIndex) {
                ForEach(Shoot.coreCells.indices, id: \.self) { i in
                    let c = Shoot.coreCells[i]
                    Text(spotName(c)).tag(i)
                }
            }
            .onChange(of: cellIndex) { _, _ in shot = nil; kickAlone = nil; duel = nil }
        }
    }

    private var stepKickAlone: some View {
        card(1) {
            Button("Play Pollen's kick where the duck stands") { kickOnItsOwn() }
                .disabled(busy != nil)
        }
    }

    private var stepHandWritten: some View {
        card(2) {
            Button("Take a shot with the hand-written numbers") {
                run("Shooting…") { shot = try await play(cell, .defaults) }
            }
            .disabled(busy != nil)
        }
    }

    private var stepTrain: some View {
        card(3) {
            if let score = search.bestScore {
                LabeledContent("Best so far", value: ShootWords.score(score) + " (training spots)")
                chart
            }
            Text("Starting from \(trainedWith). " + ShootWords.searchNote)
                .font(.caption).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button(search.bestScore == nil ? "Train (3 rounds)" : "Train 3 more rounds") { train() }
                .buttonStyle(.borderedProminent)
                .disabled(busy != nil)
            Button("Use the head start instead") {
                search = Shoot.Search(start: .headStart, children: 3)
                trainedWith = "the Pi's head start"
                line = Shoot.Params.headStartSaid
            }
            .disabled(busy != nil)
            Button("Take a shot with the trained numbers") {
                run("Shooting…") { shot = try await play(cell, search.best) }
            }
            .disabled(busy != nil)
            Button("Test on all nine spots") { test(.state) }
                .disabled(busy != nil)
            if let s = testScore.state {
                LabeledContent("Test", value: ShootWords.score(s))
            }
            Button("Keep this shooter") {
                savedShooter = encode(search.best)
                line = "Kept. It is the shooter this screen starts from next time."
            }
            .disabled(busy != nil)
        }
    }

    private var stepJudge: some View {
        card(4) {
            if duel == nil {
                Button("Compare the hand-written and trained shots") { startDuel() }
                    .disabled(busy != nil)
            } else {
                Button("Back to the pitch") { duel = nil }
            }
            Text(CompareWords.tally(compare.today, streak: compare.streak))
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private var stepCamera: some View {
        card(5) {
            Button("Test the trained shooter with the head camera only") { test(.camera) }
                .disabled(busy != nil)
            if let s = testScore.camera {
                LabeledContent("With the camera", value: ShootWords.score(s))
                if let k = testScore.state {
                    LabeledContent("Knowing where the ball is", value: ShootWords.score(k))
                }
            }
        }
    }

    /// Goals per round, as bars.
    private var chart: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(search.history.enumerated()), id: \.offset) { i, s in
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(i == search.history.count - 1 ? Theme.measured : Theme.actionSecondary)
                        .frame(width: 18, height: max(4, CGFloat(s.goals) / CGFloat(max(s.shots, 1)) * 60))
                    Text("\(s.goals)").font(.caption2).monospacedDigit()
                }
            }
        }
        .frame(height: 80, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Goals per round: " + search.history.map { "\($0.goals)" }.joined(separator: ", ")))
    }

    // MARK: - doing it

    private func spotName(_ c: Shoot.Cell) -> String {
        let depth = c.x < 0 ? "near" : c.x > 0 ? "far" : "middle"
        let side = c.y > 0 ? "left" : c.y < 0 ? "right" : "centre"
        return "\(depth), \(side)"
    }

    private func address() throws -> (DuckBench.Address, String?) {
        guard let bench = benches.selected else { throw ContenderRunner.Failure.said(ShootWords.noBench) }
        return (try bench.resolved(), benches.armed(bench).token)
    }

    private func play(_ cell: Shoot.Cell, _ params: Shoot.Params,
                      sensing: Shoot.Sensing = .state, seed: Int = 1) async throws -> Shoot.Shot {
        let (address, token) = try address()
        let call = try Shoot.call(address, cell: cell, params: params, sensing: sensing, seed: seed)
        let data = try await URLSession.shared.data(for: DuckBench.urlRequest(for: call, token: token)).0
        return try Shoot.read(data, cell: cell, named: "shot")
    }

    private func show(_ s: Shoot.Shot) {
        kickAlone = nil
        shot = s
        playhead = 0
        isRunning = true
    }

    private func run(_ what: String, _ work: @escaping () async throws -> Void) {
        busy = what; line = nil; duel = nil
        task = Task {
            do { try await work() } catch is CancellationError {
            } catch { line = ContenderRunner.words(error) }
            busy = nil
            playhead = 0; isRunning = true
        }
    }

    private func kickOnItsOwn() {
        run("Kicking…") {
            let (address, token) = try address()
            let call = try DuckBench.record(address, policy: "ball_kick_left.onnx", seconds: 2.5,
                                            schedule: [DuckBench.Step(at: 0)])
            let data = try await URLSession.shared.data(for: DuckBench.urlRequest(for: call, token: token)).0
            kickAlone = try DuckBench.readClip(data, named: "kick")
            shot = nil
            line = "The kick, played where the duck stands. It kicks at the air: it cannot see the "
                 + "ball and cannot walk to it. On the ball challenge it scores 0 of 14."
        }
    }

    private func train() {
        run("Training…") {
            var rng = SystemRandomNumberGenerator()
            if search.bestScore == nil {
                var shots: [Shoot.Shot] = []
                for (i, c) in trainCells.enumerated() {
                    busy = "Scoring the starting numbers: spot \(i + 1) of \(trainCells.count)"
                    let s = try await play(c, search.best); shots.append(s); show(s)
                }
                search.seed(Shoot.Score(shots))
            }
            for round in 0..<3 {
                try Task.checkCancellation()
                var tried: [(Shoot.Params, Shoot.Score)] = []
                for (k, p) in search.proposals(using: &rng).enumerated() {
                    var shots: [Shoot.Shot] = []
                    for (i, c) in trainCells.enumerated() {
                        busy = "Round \(search.generation + 1) (\(round + 1) of 3): variation \(k + 1), "
                             + "spot \(i + 1) of \(trainCells.count)"
                        let s = try await play(c, p); shots.append(s); show(s)
                    }
                    tried.append((p, Shoot.Score(shots)))
                }
                search.finish(tried)
                if let best = search.bestScore { line = "Round \(search.generation): " + ShootWords.score(best) }
            }
            Haptic.finished()
        }
    }

    private func test(_ sensing: Shoot.Sensing) {
        run(sensing == .camera ? "Testing with the camera…" : "Testing…") {
            var shots: [Shoot.Shot] = []
            for (i, c) in Shoot.coreCells.enumerated() {
                busy = "Spot \(i + 1) of \(Shoot.coreCells.count)"
                let s = try await play(c, search.best, sensing: sensing, seed: i + 1)
                shots.append(s); show(s)
            }
            let score = Shoot.Score(shots)
            if sensing == .camera { testScore.camera = score } else { testScore.state = score }
            Haptic.finished()
        }
    }

    private func startDuel() {
        run("Shooting both…") {
            let hand = try await play(cell, .defaults)
            let trained = try await play(cell, search.best)
            let leftIsTrained = Bool.random()
            duel = leftIsTrained ? (trained, hand, true) : (hand, trained, false)
        }
    }

    private func judge(_ choice: DuckFeedback.Choice, _ reasons: [DuckFeedback.Reason]) {
        guard let duel else { return }
        func contender(_ trained: Bool) -> Compare.Contender {
            let p = trained ? search.best : .defaults
            return Compare.Contender(kind: .shooter, name: trained ? "Trained shooter" : "Hand-written shooter",
                                     digest: p.digest, source: .yours, key: trained ? "trained" : "hand")
        }
        let left = contender(duel.leftIsTrained), right = contender(!duel.leftIsTrained)
        guard left.digest != right.digest else {
            line = "The trained numbers are still the hand-written ones: train first."
            self.duel = nil; return
        }
        compare.pick(left: left, right: right, chose: choice, reasons: reasons, context: "duel",
                     command: nil)
        line = "Picked. Left was the \(duel.leftIsTrained ? "trained" : "hand-written") shooter."
        self.duel = nil
    }

    // MARK: - a kept shooter

    private func encode(_ p: Shoot.Params) -> String {
        var o: [String: Any] = p.values; o["foot"] = p.foot
        return (try? String(decoding: JSONSerialization.data(withJSONObject: o), as: UTF8.self)) ?? ""
    }

    private func restore() {
        guard search.bestScore == nil, !savedShooter.isEmpty,
              let o = try? JSONSerialization.jsonObject(with: Data(savedShooter.utf8)) as? [String: Any]
        else { return }
        var values: [String: Double] = [:]
        for (k, v) in o { if let d = v as? Double { values[k] = d } }
        search = Shoot.Search(start: Shoot.Params(values: values, foot: o["foot"] as? String ?? "auto").clamped,
                              children: 3)
        trainedWith = "the shooter you kept"
    }
}
