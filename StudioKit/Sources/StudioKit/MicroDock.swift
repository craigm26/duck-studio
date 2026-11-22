import Foundation
import DuckKit
import DuckEvidence

/// The MicroDock scoot networks, by fingerprint, and who made them.
///
/// THREE NETWORKS THAT ARE NOT POLLEN'S, AND THE TABLE SAYS SO BY BEING A SECOND TABLE.
/// `DuckOfficialPolicies` lists what Pollen Robotics released, and a match there puts a policy
/// under "Released by Pollen Robotics". These were trained by Hannes von Essen (Vottivott) in
/// `microduck-playground`, for the MicroDock v2 seated dock, and released under Apache-2.0. Adding
/// them to Pollen's table would put somebody else's training under Pollen's name, which is the one
/// claim that table exists to make carefully. So they are recognised here, as community work with
/// a named source, and nothing here makes them "released".
///
/// PINNED TO ONE COMMIT. `commit` is the upstream HEAD these files were copied from
/// (c1ba96f, 2026-11-21). A newer upstream export is a different set of weights and is simply not
/// recognised here, which is the honest answer for a table that was built from three files.
///
/// REGENERATE, NEVER RETYPE. Each fingerprint is `DuckPolicy.fingerprint` of the file as upstream
/// ships it; `MicroDockTests` loads the files and fails if a digest here was typed rather than
/// measured. A miss proves only that this table has not seen those weights.
///
/// WHAT A MATCH DOES NOT SAY. Upstream's own words: "These are simulation results: none of the
/// scoot policies has run on a robot." `credit` carries that sentence's substance wherever the
/// name is drawn, so recognising a network never reads as vouching for it.
public enum MicroDock {

    /// One of the three.
    public struct Network: Equatable, Sendable, Identifiable {
        /// What to call it on a screen.
        public let title: String
        /// The file's own name, upstream and in this app's bundle.
        public let fileName: String
        /// Where the file sits in the upstream repository.
        public let upstreamPath: String
        /// SHA-256 over `DuckPolicy.canonicalParameterBytes`, lowercase hex.
        public let fingerprint: String
        /// One line about what it does, in upstream's terms.
        public let purpose: String
        /// Upstream calls it experimental: evaluated less, and its training check disagrees with
        /// its docking results.
        public let experimental: Bool
        /// Whether this app ships it. The two the Dock routine drives are bundled, because the
        /// practice duck on this phone runs only bundled networks (`PhoneBenchAssets`); the
        /// experimental one is not used by anything here and is fetched by address if wanted.
        public let bundled: Bool

        public var id: String { fingerprint }

        /// The file at the pinned commit, for the fetch-by-address path.
        public var sourceURL: URL {
            URL(string: "https://raw.githubusercontent.com/\(MicroDock.repository)/\(MicroDock.commit)/\(upstreamPath)")!
        }
    }

    /// The upstream repository, `owner/name`.
    public static let repository = "Vottivott/microduck-playground"
    /// The commit the files were copied from.
    public static let commit = "c1ba96f596df5e99829cbb6590971eca97d96e2d"
    /// The seven characters a person compares.
    public static var shortCommit: String { String(commit.prefix(7)) }
    /// The software licence the policies are under (upstream `LICENSE`, `NOTICE`).
    public static let licence = "Apache-2.0"
    /// The dock, explained, on this app's own site.
    public static let page = URL(string: "https://microduckstudio.com/dock/")!

    /// The docking policy: backs a seated duck in, holds still at zero.
    public static let scootBack = Network(
        title: "Scoot back (dock)",
        fileName: "scoot_dock.onnx",
        upstreamPath: "hardware/microdock-v2/policy/scoot_dock.onnx",
        fingerprint: "d9034c8335fbd19666a07a044297b1362323a04ad5f63e1eec9141a3213fc5c2",
        purpose: "Scoots a seated duck backward on its seat on command, and sits still at a zero command.",
        experimental: false, bundled: true)

    /// The undocking policy: scoots forward out of the dock against the magnet.
    public static let scootOut = Network(
        title: "Scoot out (undock)",
        fileName: "scoot_undock.onnx",
        upstreamPath: "hardware/microdock-v2/policy/scoot_undock.onnx",
        fingerprint: "a481e624df123636ca40cfb264a277470a63651777c4eb64e2453cf41c90ac34",
        purpose: "Scoots a seated duck forward out of the dock, against its magnet, so it can stand up.",
        experimental: false, bundled: true)

    /// One network for both directions; only the command's sign differs.
    public static let scootBoth = Network(
        title: "Scoot both ways (experimental)",
        fileName: "scoot_dock_undock.onnx",
        upstreamPath: "hardware/microdock-v2/policy/experimental/scoot_dock_undock.onnx",
        fingerprint: "bc523fa497fafb38476d41a547344d968d3756d0527da511d3035fd77fa5c7ff",
        purpose: "Backs in and scoots out with one network. Upstream calls it experimental: it was checked less than the other two.",
        experimental: true, bundled: false)

    /// All three, in the order a screen lists them.
    public static let networks = [scootBack, scootOut, scootBoth]

    /// The network these parameters are, when they are one of the three.
    public static func network(fingerprint: String) -> Network? {
        networks.first { $0.fingerprint == fingerprint }
    }

    /// The network a file name points at. A display hint only: identity is the fingerprint.
    public static func network(fileName: String) -> Network? {
        networks.first { $0.fileName == fileName }
    }

    /// The sentence beside a recognised network, wherever its name is drawn.
    public static let credit =
        "Trained by Hannes von Essen (Vottivott) for the MicroDock, in microduck-playground at "
      + "commit c1ba96f, Apache-2.0. Tested in simulation only: none of these has run on a robot."
}

/// The Dock routine: sit, scoot back, rest, scoot out, stand. On the practice duck only.
///
/// EVERY NUMBER IS UPSTREAM'S. The steps are MicroDock v2's own sequence
/// (`hardware/microdock-v2/README.md`, "How docking works" and "How undocking works"), and each
/// duration and command is read from the script that produced upstream's results, cited per step
/// in `Step.source`. Nothing here was tuned on this app's bench.
///
/// THE PRACTICE DUCK HAS NO DOCK, AND THE ROUTINE SAYS SO. There is no hood, no magnet and no USB
/// power on the bench, so upstream's "until the tip meets the adapter" becomes the duration of
/// upstream's own command battery (`results/scoot_dock_commands.json`, 4.0 s), and the undock's
/// "70 mm out" is measured from where the duck rested, on a bare floor. The bench also runs
/// Pollen's MuJoCo plant without the BAM XL330 actuator model or the training's latencies that
/// upstream's simulation used, and upstream found the undock only breaks free of the magnet WITH
/// those latencies. So this shows the scoot, not docking, and `practiceLine` says that.
///
/// MEASURED ON THE BENCH BEFORE IT WAS WRITTEN (2026-11-22, duckbench at a75d4dc, Pollen's
/// plant `scene.mjb`, the phone's engine `policyforward.mjs` on canonical bytes from DuckKit, the
/// app's bundled sit-stand v6): sat 69 mm back, scooted back 165.5 mm in 4.0 s (0.0414 m/s;
/// upstream's battery says 0.040 at this command), drifted 4.4 mm at rest, scooted out 70.5 mm in
/// 3.0 s, stood to a 116.5 mm trunk, upright throughout. On onnxruntime, as a desk bench runs it,
/// every phase matched except the scoot out, 72.9 mm in 3.1 s. One run each, deterministic: it is
/// a check that the bench reproduces scooting, not a success rate. `scripts/measure_dock_routine.mjs`
/// is that run.
///
/// A REAL DUCK IS REFUSED, IN ONE SENTENCE. Pollen's robotd starts nothing from the seat except
/// standing up (`robotd/src/control.rs` `move_blocked`, pollen-robotics/microduck 56424ef: "one
/// move at a time, and none from the seat"), and every scoot starts seated. No call in this app
/// works around that, and `realDuck` is the reason a screen draws.
///
/// STOP ENDS IT WHERE IT IS. The run is cancelled between bench calls and the bench is told to
/// stop, which holds a zero command under whichever network was driving. Nothing is switched back
/// after a Stop, because a Stop that then changed networks would be a move nobody asked for.
public enum DockRoutine {

    /// Which network a step drives.
    public enum Role: Equatable, Sendable {
        /// Pollen's `alpha_sitstand`, which upstream sits and stands with.
        case sitStand
        case scootBack
        case scootOut
    }

    /// One phase of the routine.
    public enum Phase: String, Equatable, Sendable, CaseIterable {
        case sit, handOver, scootBack, rest, scootOut, still, stand

        /// What the caption says while it runs.
        public var caption: String {
            switch self {
            case .sit: return "Sitting down."
            case .handOver: return "Handing over to the scoot network."
            case .scootBack: return "Scooting back on its seat."
            case .rest: return "Resting where a dock would charge it."
            case .scootOut: return "Scooting out."
            case .still: return "Holding still before standing."
            case .stand: return "Standing up."
            }
        }
    }

    public struct Step: Equatable, Sendable {
        public let phase: Phase
        public let role: Role
        /// The command block's first value. A twist for the scoot networks; for the sit-stand
        /// network it is the posture flag, 1 to sit and 0 to stand, which is how the bench feeds it
        /// (duckbench `sim/record_intents.mjs`, the `sit` and `stand` clips).
        public let vx: Double
        /// How long the step holds, in sim seconds.
        public let seconds: Double
        /// Ends the step early once the duck is this far along its heading from where the step
        /// began, in metres. Nil holds for the whole `seconds`.
        public let untilMetres: Double?
        /// Where the numbers come from, upstream.
        public let source: String
    }

    /// The routine, in order.
    public static let steps: [Step] = [
        Step(phase: .sit, role: .sitStand, vx: 1, seconds: 4.0, untilMetres: nil,
             source: "sim/docking_seated.py --sit_s 4.0"),
        Step(phase: .handOver, role: .scootBack, vx: 0, seconds: 0.5, untilMetres: nil,
             source: "sim/docking_seated.py --handover_s 0.5"),
        Step(phase: .scootBack, role: .scootBack, vx: -0.05, seconds: 4.0, untilMetres: nil,
             source: "sim/docking_seated.py --vback -0.05; results/scoot_dock_commands.json seconds 4.0"),
        Step(phase: .rest, role: .scootBack, vx: 0, seconds: 3.0, untilMetres: nil,
             source: "sim/docking_seated.py --hold 3.0"),
        Step(phase: .scootOut, role: .scootOut, vx: 0.05, seconds: 10.0, untilMetres: 0.070,
             source: "sim/undocking_seated.py undock(): vx 0.05 until 70 mm out, at most 500 steps"),
        Step(phase: .still, role: .scootOut, vx: 0, seconds: 0.5, untilMetres: nil,
             source: "sim/undocking_seated.py undock(): 25 steps still"),
        Step(phase: .stand, role: .sitStand, vx: 0, seconds: 3.5, untilMetres: nil,
             source: "sim/undocking_seated.py undock(): 175 steps of the sitstand"),
    ]

    /// The longest a bench holds one `/intent` (`duckbench-core.mjs` clamps `hold` to 2 s).
    static let longestHold = 2.0
    /// How often a step with an end point looks at where the duck is: five control ticks.
    static let checkEvery = 0.1

    /// The sit-stand file names a bench may hold it under, role name first.
    static let sitStandNames = ["alpha_sitstand.onnx", "BEST_alpha_sitstand.onnx"]

    /// The names this routine needs on a bench, and what has to be uploaded first.
    public struct Plan: Equatable, Sendable {
        public let sitStand: String
        /// The bench's name for each scoot network, or nil when it has to be uploaded.
        public let scootBack: String?
        public let scootOut: String?
        /// The network the duck was on before, to hand it back to at the end; nil when the bench
        /// did not say, or the duck was already on one of the routine's own.
        public let handBack: String?

        public func name(for role: Role) -> String? {
            switch role {
            case .sitStand: return sitStand
            case .scootBack: return scootBack
            case .scootOut: return scootOut
            }
        }
    }

    /// Match the routine to what a bench holds.
    ///
    /// A BENCH WITHOUT A SIT-STAND NETWORK IS REFUSED, because the routine starts and ends with
    /// one and nothing else can sit the duck. A missing scoot network is not a refusal: a desk
    /// bench takes an upload, and the phone's own bench already holds both because they are
    /// bundled. The hand-back is the network the duck was on, so Play's stick drives what it drove
    /// before; a duck that started on one of the routine's own networks gets the walk slot.
    public static func plan(benchHolds held: [String], startedOn: String?) -> Result<Plan, Refusal> {
        func holds(_ file: String) -> String? {
            if held.contains(file) { return file }
            let stem = String(file.dropLast(".onnx".count))
            return held.contains(stem) ? stem : nil
        }
        guard let sit = sitStandNames.lazy.compactMap(holds).first else {
            return .failure(.noSitStand)
        }
        let back = holds(MicroDock.scootBack.fileName) ?? holds(uploadName(MicroDock.scootBack))
        let out = holds(MicroDock.scootOut.fileName) ?? holds(uploadName(MicroDock.scootOut))
        let ours: Set<String?> = [sit, back, out]
        var handBack = startedOn.flatMap { ours.contains($0) ? nil : $0 }
        if handBack == nil {
            handBack = DuckQuickActions.filename(filling: .walk, among: held)
        }
        return .success(Plan(sitStand: sit, scootBack: back, scootOut: out, handBack: handBack))
    }

    /// The name an upload asks for. Not the file name: a bench refuses an upload that takes the
    /// name of a policy it ships, and the bundled name is the shape of one.
    public static func uploadName(_ network: MicroDock.Network) -> String {
        String(network.fileName.dropLast(".onnx".count))
    }

    /// Why the routine did not run.
    public enum Refusal: Error, Equatable, Sendable {
        case realDuck
        case noDuck
        case noSitStand
        case notBundled(String)

        public var sentence: String {
            switch self {
            case .realDuck: return Words.realDuck
            case .noDuck: return Words.noDuck
            case .noSitStand: return Words.noSitStand
            case .notBundled(let file): return Words.notBundled(file)
            }
        }
    }

    /// What the routine measured, from the bench's own positions.
    public struct Outcome: Equatable, Sendable {
        /// Along the heading, metres; negative is backward.
        public let scootedBack: Double
        public let scootedOut: Double
        public let scootOutSeconds: Double
        public let stoodHeight: Double
        public let uprightThroughout: Bool

        /// The line after a run: what happened, in millimetres, on this duck.
        public var sentence: String {
            guard uprightThroughout else { return Words.fell }
            return String(format: "Scooted back %.0f mm and out %.0f mm, then stood up. Practice duck, no dock.",
                          abs(scootedBack) * 1000, scootedOut * 1000)
        }
    }

    /// How far along `heading` the duck went from `from` to `to`, in metres.
    static func along(from: DuckIntentClip.Root, to: DuckIntentClip.Root, heading: Double) -> Double {
        (to.x - from.x) * cos(heading) + (to.y - from.y) * sin(heading)
    }

    /// The trunk's heading, radians, from its orientation (w, x, y, z).
    static func heading(_ root: DuckIntentClip.Root) -> Double {
        let (w, x, y, z) = root.quaternion
        return atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
    }

    /// The holds one step is sent as: the bench takes at most `longestHold` at a time, and a step
    /// with an end point is sent in `checkEvery` pieces so it can stop near it.
    static func holds(for step: Step) -> [Double] {
        let piece = step.untilMetres == nil ? longestHold : checkEvery
        var left = step.seconds, out: [Double] = []
        while left > 1e-9 {
            let h = min(piece, left)
            out.append(h)
            left -= h
        }
        return out
    }

    public enum Words {
        public static let title = "Dock"
        public static let symbol = "powerplug"
        /// On the practice duck, before it runs.
        public static let practiceLine =
            "Sits, scoots back on its seat for 4 seconds, rests, scoots out and stands up, "
          + "with the MicroDock networks. The practice duck has no dock or magnet, so this shows "
          + "the scoot, not docking."
        /// On a real duck, the one plain sentence.
        public static let realDuck =
            "Your own duck can't do this yet: its robotd starts nothing from the seat except standing up."
        public static let noDuck = "Pick the practice duck on Play first."
        public static let noSitStand =
            "This bench has no sit-stand network, and the routine starts by sitting down."
        public static func notBundled(_ file: String) -> String {
            "\(file) is not in this copy of the app, so the bench has nothing to scoot with."
        }
        public static let fell = "The duck fell over during the routine."
        public static let aboutTheDock = "About the MicroDock"
        public static let stopNote =
            "Stop leaves the duck where it is, on whichever network was driving. Reset on Play stands it back up."
        public static let all = [title, practiceLine, realDuck, noDuck, noSitStand, fell,
                                 aboutTheDock, stopNote, notBundled("scoot_dock.onnx")]
    }
}

extension BenchPeer {

    /// Run the Dock routine on this bench, step by step, and say what it measured.
    ///
    /// `bundled` hands over a network's bytes by file name, for a bench that has to be sent one;
    /// `said` hears each phase as it starts. Cancelling the task ends it before the next bench call.
    /// Throws a `DockRoutine.Refusal` before anything moves, or the bench's own refusal.
    public func runDock(bundled: @Sendable (String) -> Data?,
                        said: @Sendable (DockRoutine.Phase) async -> Void) async throws -> DockRoutine.Outcome {
        let health = try DuckBench.readHealth(try await ask(DuckBench.health(address)))
        var plan: DockRoutine.Plan
        switch DockRoutine.plan(benchHolds: health.policies, startedOn: live?.policy) {
        case .failure(let refusal): throw refusal
        case .success(let p): plan = p
        }
        var back = plan.scootBack, out = plan.scootOut
        for (network, held) in [(MicroDock.scootBack, back), (MicroDock.scootOut, out)] where held == nil {
            guard let bytes = bundled(network.fileName) else {
                throw DockRoutine.Refusal.notBundled(network.fileName)
            }
            try Task.checkCancellation()
            let name = try DuckBench.readUploaded(try await ask(
                DuckBench.upload(address, onnx: bytes, name: DockRoutine.uploadName(network))))
            if network == MicroDock.scootBack { back = name } else { out = name }
        }
        plan = DockRoutine.Plan(sitStand: plan.sitStand, scootBack: back, scootOut: out,
                                handBack: plan.handBack)

        var upright = true
        var marks: [DockRoutine.Phase: (start: DuckIntentClip.Root, end: DuckIntentClip.Root, t0: Double, t1: Double)] = [:]
        var height = 0.0
        for step in DockRoutine.steps {
            try Task.checkCancellation()
            await said(step.phase)
            try Task.checkCancellation()
            guard let name = plan.name(for: step.role) else { throw DockRoutine.Refusal.noSitStand }
            var now = try await drive(try DuckDrive.load(address, policy: name))
            let start = now.stance.root, t0 = now.t
            let heading = DockRoutine.heading(start)
            for hold in DockRoutine.holds(for: step) {
                try Task.checkCancellation()
                now = try await drive(try DuckDrive.intent(
                    address, DuckDrive.Twist(vx: step.vx, vy: 0, vyaw: 0), hold: hold))
                upright = upright && now.upright
                if let until = step.untilMetres,
                   DockRoutine.along(from: start, to: now.stance.root, heading: heading) >= until { break }
            }
            marks[step.phase] = (start, now.stance.root, t0, now.t)
            height = now.height
        }
        if let handBack = plan.handBack {
            try Task.checkCancellation()
            _ = try await drive(try DuckDrive.load(address, policy: handBack))
        }
        func along(_ phase: DockRoutine.Phase) -> Double {
            guard let m = marks[phase] else { return 0 }
            return DockRoutine.along(from: m.start, to: m.end, heading: DockRoutine.heading(m.start))
        }
        let outSeconds = marks[.scootOut].map { $0.t1 - $0.t0 } ?? 0
        return DockRoutine.Outcome(scootedBack: along(.scootBack), scootedOut: along(.scootOut),
                                   scootOutSeconds: outSeconds, stoodHeight: height,
                                   uprightThroughout: upright)
    }
}
