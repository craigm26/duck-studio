import Foundation

/// The Microduck stairs challenge, as this app carries it.
///
/// WHAT THE CHALLENGE IS, IN THE ONE SENTENCE THE SCREEN SHOWS. Get a
/// 250 mm bipedal duck from the floor onto a step, in simulation, and leave it
/// standing there — not touching the step, not a foot up: upright on the tread
/// with both feet resting on it, fifty ticks after the authored move ends.
///
/// AND WHAT THE BAR IS. A submission is scored over fourteen perturbations of
/// the rise and the plant; the nine "core" cells are what every published
/// number is quoted against. Seven of those nine, still standing, is the bar.
/// Nothing has ever met it: the record is FIVE, at a 60 mm rise, by a move
/// that plants the duck's beak on the tread and pivots its whole body over its
/// own head. Round six then measured why — the trunk's PEAK gets over the
/// 95 mm bar in at most five of the nine cells, which bounds every landing law
/// there could be — so the bar was never reachable at this scale, and the
/// package publishes that negative result rather than hiding it.
///
/// EVERY NUMBER HERE IS SIMULATION AND NOTHING IN IT HAS RUN ON HARDWARE.
/// `realDuckCaveat` is the sentence that has to appear wherever this app
/// offers to send one of these moves to a robot, and it is not softenable:
/// there is no score off the bench, the staircase belongs to whoever is
/// standing next to it, and in the cells where the trunk got over the bar at
/// least one of the fourteen servos is pinned at its 0.6405 N·m ceiling for
/// three quarters of the push-off.
///
/// THE FILES ARE THE DATASET'S OWN BYTES. `intent(named:)` reads a file copied
/// out of `duck-sounds/challenge/intents` without a byte changed, and
/// `StairsChallengeResourceTests` pins all nineteen by sha256. An app that
/// retyped a leaderboard would be publishing numbers that cannot be traced to
/// the run that produced them.
public enum StairsChallenge {

    // MARK: - what it is

    public static let title = "Stairs Challenge"

    public static let oneSentence =
        "Get the duck from the floor onto a step in simulation and leave it standing there — "
      + "upright on the tread with both feet resting on it, fifty ticks after your move ends."

    /// The bar, and the fact that it stands unmet. A challenge screen that
    /// showed the bar without that fact would be inviting somebody to assume
    /// the top of the table had reached it.
    public static let barSaid =
        "The bar is 7 of the 9 core cells, cleared and still standing. Nothing has met it: "
      + "the record is 5 of 9 at a 60 mm rise, and round six measured the trunk's peak height "
      + "as the reason 7 was never reachable at this scale."

    /// THE CRITERION, VERBATIM AS `sim/climb_score.mjs` EXPORTS IT
    /// (`CRITERION_SENTENCE`, line 245). The bench sends its own copy back
    /// with every scored cell and `Score.criterion` carries it; this constant
    /// exists so the app can say what it is about to ask for before the first
    /// answer arrives, and so a second challenge can be shown beside this one
    /// in the same words.
    public static let criterionSentence =
        "honest: at the scored instant the trunk is upright, past the riser at x > 120 mm, "
      + "more than 95 mm above the tread, with at least two feet resting on a tread "
      + "(past the riser, within 5 mm below to 45 mm above it, and within 3 mm of a step), "
      + "and the duck never left the 340 mm-wide flight at any tick of the episode. "
      + "stable: honest, and upright for at least 45 of the 50 tail ticks."

    /// How many of the nine core cells a submission has to clear stably.
    public static let bar = 7

    /// Millimetres of trunk above the tread the criterion needs
    /// (`climb/rig3.mjs` line 330: `s.above > 0.095`).
    public static let barMillimetres = 95.0

    /// Tail ticks upright a clear needs to count as STABLE
    /// (`climb/robust.mjs` line 528, `UPRIGHT_TAIL_MIN`).
    public static let uprightTailMinimum = 45

    /// The plant every published number was produced in.
    public static let plantName = "scene.mjb"
    public static let plantDigest =
        "3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec78d80dca242547be"

    /// The rises the app offers, in metres. 60 mm is the default because it is
    /// the only rise anything has cleared more than twice, and therefore the
    /// only one where a person's first run is likely to show them anything.
    public static let rises: [Double] = [0.040, 0.050, 0.060, 0.070, 0.080, 0.090, 0.120, 0.180]
    public static let defaultRise = 0.060

    public static let datasetURL =
        URL(string: "https://huggingface.co/datasets/craigm26/microduck-stairs-challenge")!
    public static let harnessURL = URL(string: "https://github.com/craigm26/duck-sounds")!

    public static func riseSaid(_ rise: Double) -> String {
        "\(Int((rise * 1000).rounded())) mm"
    }

    // MARK: - the room the score was measured in

    /// The staircase's geometry, transcribed from the vendored harness this
    /// app ships and replays — `assets/stairs.js` and `assets/climb_score.mjs`
    /// — with the file and the line each number came from.
    ///
    /// TRANSCRIBED, BECAUSE THE APP CANNOT READ JAVASCRIPT. Every one of these
    /// is a number a published score depends on, so a drawing built on a
    /// guess would be a picture of a staircase nothing was ever scored
    /// against. `ChallengeSceneTests` pins each of them.
    public enum Harness {

        /// `stairs.js` STAIR_HALF_WIDTH — the flight is 340 mm across.
        public static let stairHalfWidth = 0.17
        /// `stairs.js` STAIR_Y — where the step bodies are COMPILED, so where
        /// they are. Derived there as 1.5 − 0.025 − 0.17 on a belief about the
        /// wall that turned out to be wrong; see `wallHalfThickness`.
        public static let stairY = 1.5 - 0.025 - 0.17
        /// `stairs.js` STEP_HALF_DEPTH — deeper than the deepest run, so the
        /// treads overlap into one solid flight.
        public static let stepHalfDepth = 0.17
        /// `stairs.js` STEP_HALF_HEIGHT.
        public static let stepHalfHeight = 0.10
        /// `climb_score.mjs` RISER_X — the first riser face, and the line the
        /// trunk and a foot have to cross.
        public static let riserX = 0.12
        /// `climb_score.mjs` STAIR_RUN.
        public static let stairRun = 0.28
        /// `climb_score.mjs` STAIR_START.
        public static let stairStart = 0.12
        /// `climb_score.mjs` DEFAULT_STEP_COUNT.
        public static let stepCount = 4
        /// How far behind the riser the duck spawns before `gap` is applied:
        /// `climb_score.mjs` spawns it at `0.12 − 0.07 − gap`.
        public static let spawnStandoff = 0.07

        /// THE CORRECTION `stairs.js` RECORDS AT ITS OWN TOP. `wall_n` is
        /// 50 mm half-thick and centred at y = 1.50, so its inner face is at
        /// 1.45 — and `stairY + stairHalfWidth` is 1.475, which puts the outer
        /// 25 mm of every tread INSIDE the wall. Measured 2026-09-02,
        /// `climb/audit_r2`. It is where the blocks are, not a mistake this app
        /// gets to correct: they are compiled at that y with x and z slides
        /// only, and the lateral gate every score was measured with is
        /// measured from where they are.
        public static let wallCentreY = 1.50
        public static let wallHalfThickness = 0.05
        /// The wall's inner face — 1.45 m.
        public static var wallInnerFaceY: Double { wallCentreY - wallHalfThickness }
        /// How far the outer edge of a tread reaches past that face: 25 mm.
        public static var treadInsideWall: Double {
            (stairY + stairHalfWidth) - wallInnerFaceY
        }

        /// The line under a challenge scene, naming where its blocks came from
        /// and carrying the overlap correction rather than hiding it.
        public static func provenanceSaid(count: Int) -> String {
            "The flight climb_score.mjs lays out: \(count) steps, "
          + "\(Int((stairRun * 1000).rounded())) mm run, first riser "
          + "\(Int((riserX * 1000).rounded())) mm from the spawn, "
          + "\(Int((stairHalfWidth * 2000).rounded())) mm wide, against the north wall whose "
          + "inner face is at \(String(format: "%.2f", wallInnerFaceY)) m — the outer "
          + "\(Int((treadInsideWall * 1000).rounded())) mm of every tread is inside it "
          + "(measured 2026-09-02, climb/audit_r2). Simulation only."
        }
    }

    // MARK: - the sentences that keep it honest

    /// Beside the one button that makes something move. IT PLAYS ON THE
    /// BENCH. The screen has no path to a real Microduck for a harness move
    /// in this build, and a button called "send to the duck" over a /perform
    /// to a bench would have said otherwise.
    public static let realDuckCaveat =
        "This plays the move on the bench, in physics. Playing it on a real Microduck is not "
      + "wired in this build, a score exists only on a bench, and nothing here has been run on "
      + "hardware."

    /// A bench that cannot score this. NAMES THE BENCH AND WHAT TO UPDATE,
    /// because "not supported" sends somebody to look for a setting that does
    /// not exist.
    public static func noClimbHere(bench: String) -> String {
        "No /climb on \(bench). This bench answers /health and /perform but not the stairs "
      + "challenge, so nothing here can be scored on it. Pick a bench that has it — this "
      + "iPhone's own bench does, once the app is updated — or update the Pi bench from "
      + "github.com/craigm26/duck-sounds and restart it with "
      + "`systemctl --user restart duckbench`."
    }

    /// What the app is claiming when it shows a score: not a new measurement,
    /// the audit's own one, re-run here.
    public static func sameCriterion(plantDigest digest: String?) -> String {
        let plant = digest.map { "plant \($0.prefix(DuckBench.digestShown))" }
                    ?? "plant, which it did not identify"
        return "This is the audit's criterion and grid, scored on this bench's \(plant)."
    }

    /// The word beside a leaderboard row whose landing law read the tread
    /// straight out of the plant: an upper bound, not a move a robot could run.
    public static let oracleWord = "Oracle"
    public static let oracleNote =
        "This entry's landing law reads the step's height and edge from the simulator, which "
      + "no robot can. It is an upper bound on a landing, not a move a Microduck could run."

    /// Under "Open in the editor".
    public static let editorNote =
        "It becomes a motion in Studio, with the challenge and this move's hash written into "
      + "its provenance. Change any keyframe's servo values there, then score your edited "
      + "version here."

    /// The edit-score-keep loop, said where the edited version is scored.
    public static let editedVersionNote =
        "Your edited version, scored on the same fourteen cells as the published move. Keep "
      + "what scores better; put back what scores worse. There is no reward model in this "
      + "loop — you are the judge, and the bench is the measurement."
    public static let editedNotFoundNote =
        "Open the move in the editor first. The edited version is looked up by the draft the "
      + "editor saved; there is none yet."

    /// The 14 joints of a harness pose are the policy's action space, and the
    /// mouth is the joint it skips. Said only when an edit actually moved it.
    public static let mouthDroppedNote =
        "The mouth moves in this draft and the challenge format has no room for it: a harness "
      + "pose is the 14 joints a policy commands, and the mouth is the one they all skip. "
      + "Everything else goes across unchanged."

    // MARK: - the leaderboard

    /// One published row.
    ///
    /// `kCoreStable` IS THE COLUMN THE TABLE IS ORDERED BY and the only one a
    /// rank means anything about. `kCore` counts the same cells without the
    /// standing requirement, and the two differ — a move can reach the tread
    /// and topple inside the tail — so both travel, and a screen that showed
    /// one of them alone would be quoting a number the leaderboard does not
    /// rank by.
    ///
    /// A rank is NIL on purpose for three kinds of row: the same vector
    /// published again at a second rise (a lower rise is a strictly easier
    /// task, so the ranks are not comparable across them), the two ORACLE
    /// rows whose servo law reads the tread height straight out of the plant,
    /// and the three controls, which are not entries at all.
    public struct Row: Equatable, Sendable, Identifiable {
        public let rank: Int?
        /// `intentHash` truncated to twelve, exactly as the table prints it.
        public let hash: String
        /// The file in `intents/`, which is also this row's identity here.
        public let file: String
        /// The `name` inside that file. Not unique — three round-6 chains
        /// share one — which is why `id` is the filename.
        public let moveName: String
        /// The `family` field inside that file, VERBATIM — the search that
        /// produced this vector, in its author's own words, or nil where the
        /// file has none (the three controls).
        ///
        /// KEPT AS IT WAS WRITTEN rather than tidied into a code, because it
        /// is the only record of which search a row came out of and two of
        /// them begin with the same letter and are not the same thing:
        /// "C beak-strut vault" and "C_whole_body_corner_climb_r3" share a "C"
        /// and share nothing else. `Strategy.of` reads the WHOLE string.
        public let family: String?
        public let riseMillimetres: Int
        /// What the rise column says. Usually one rise; the do-nothing control
        /// was scored at three.
        public let riseSaid: String
        public let kCore: Int
        public let kCoreStable: Int
        public let kExt: Int
        public let kExtStable: Int
        /// How many of the nine core cells the trunk's PEAK ever got over the
        /// bar in. Nil where it was not measured at that rise — the ceiling
        /// screen ran at 60 mm only — and a screen must print that as "not
        /// measured", never as zero.
        public let ceilingCore: Int?
        public let who: String
        public let scored: String
        public let note: String
        public let isRecord: Bool
        /// Its score was produced by a law that reads the plant. Real, useful,
        /// and NOT a submission anybody could reproduce blind.
        public let isOracle: Bool
        /// A reference row, not an entry.
        public let isControl: Bool

        public var id: String { file }

        public var rankSaid: String { rank.map(String.init) ?? "—" }

        /// The rise this row was scored at, in metres — the unit a scene is
        /// built in. THE ROW'S, NOT A PICKER'S: a scene attached to a
        /// published move has to be the flight the published number came from,
        /// and the conversion belongs here rather than at every call site that
        /// needs it.
        public var riseMetres: Double { Double(riseMillimetres) / 1000 }

        public var headline: String { "\(who) — \(riseSaid)" }

        public var scoreSaid: String { "\(kCoreStable) of 9 stable" }

        /// The ceiling column, in words rather than a hole.
        public var ceilingSaid: String {
            guard let ceilingCore else { return "not measured at this rise" }
            return "\(ceilingCore) of 9 over the bar"
        }
    }

    /// EVERY ROW OF `challenge/leaderboard.md`, IN ITS ORDER — entries first,
    /// then the reference controls. `StairsChallengeLeaderboardTests` parses
    /// the shipped markdown and asserts this list against it column by column,
    /// so the table and the app cannot drift apart silently.
    public static let leaderboard: [Row] = [
        Row(rank: 1, hash: "a56d459fb649", file: "best_r6_ceilvaultC_60mm.json",
            moveName: "beak_strut_vault_r6_ceiling_60mm",
            family: "R6 ceiling — beak-strut vault launch",
            riseMillimetres: 60, riseSaid: "60 mm",
            kCore: 5, kCoreStable: 5, kExt: 5, kExtStable: 5, ceilingCore: 5,
            who: "round-6 ceiling CEM", scored: "2026-09-02",
            note: "The beak-strut vault: the beak is planted on the tread, the neck locks as a "
                + "strut, the hips extend, and the trunk pivots over the duck's own head. Floor "
                + "spawn, no servo, no event. The only vector where kCore equals the ceiling.",
            isRecord: true, isOracle: false, isControl: false),
        Row(rank: 2, hash: "4b9110c448ec", file: "best_r3_vault_60mm.json",
            moveName: "beak_strut_vault_r3_60mm",
            family: "A beak-strut vault (round 3)",
            riseMillimetres: 60, riseSaid: "60 mm",
            kCore: 4, kCoreStable: 4, kExt: 4, kExtStable: 4, ceilingCore: 5,
            who: "round-3 family A", scored: "2026-09-02",
            note: "The beak-strut vault this whole family descends from, and the record through "
                + "round five.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: nil, hash: "4b9110c448ec", file: "best_r3_vault_70mm.json",
            moveName: "beak_strut_vault_r3_70mm",
            family: "A beak-strut vault (round 3)",
            riseMillimetres: 70, riseSaid: "70 mm",
            kCore: 2, kCoreStable: 2, kExt: 2, kExtStable: 2, ceilingCore: nil,
            who: "round-3 family A", scored: "2026-09-02",
            note: "The same vector as rank 2, scored at a 70 mm rise. Unranked: a lower rise is "
                + "a strictly easier task.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: nil, hash: "4b9110c448ec", file: "best_r3_vault_80mm.json",
            moveName: "beak_strut_vault_r3_80mm",
            family: "A beak-strut vault (round 3)",
            riseMillimetres: 80, riseSaid: "80 mm",
            kCore: 1, kCoreStable: 1, kExt: 1, kExtStable: 1, ceilingCore: nil,
            who: "round-3 family A", scored: "2026-09-02",
            note: "The same vector as rank 2 at an 80 mm rise; its one clear is that grid's "
                + "70 mm cell.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: 3, hash: "7b790070b010", file: "best_r4_famA_60mm.json",
            moveName: "beak_strut_vault_event_r4_60mm",
            family: "A beak-strut vault, event-triggered landing (round 4)",
            riseMillimetres: 60, riseSaid: "60 mm",
            kCore: 4, kCoreStable: 4, kExt: 4, kExtStable: 4, ceilingCore: 5,
            who: "round-4 family A", scored: "2026-09-02",
            note: "An event-triggered landing on the rank-2 launch, and behaviourally identical "
                + "to it: 0 mm of trunk difference in all fourteen cells.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: 4, hash: "29c97398fe13", file: "best_r6_ceilvaultB_60mm.json",
            moveName: "beak_strut_vault_r6_ceiling_60mm",
            family: "R6 ceiling — beak-strut vault launch",
            riseMillimetres: 60, riseSaid: "60 mm",
            kCore: 3, kCoreStable: 2, kExt: 3, kExtStable: 2, ceilingCore: 5,
            who: "round-6 ceiling CEM", scored: "2026-09-02",
            note: "Chain B of the round-6 ceiling search. One of its three clears topples inside "
                + "the tail.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: 5, hash: "7904bf3363c5", file: "best_r3_vault_50mm.json",
            moveName: "beak_strut_vault_r3_50mm",
            family: "A beak-strut vault (round 3)",
            riseMillimetres: 50, riseSaid: "50 mm",
            kCore: 2, kCoreStable: 2, kExt: 2, kExtStable: 2, ceilingCore: 2,
            who: "round-3 family A", scored: "2026-09-02",
            note: "The vault at a 50 mm rise.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: 6, hash: "dff01b0a1906", file: "best_r3_vault_40mm.json",
            moveName: "beak_strut_vault_r3_40mm",
            family: "A beak-strut vault (round 3)",
            riseMillimetres: 40, riseSaid: "40 mm",
            kCore: 2, kCoreStable: 1, kExt: 2, kExtStable: 1, ceilingCore: 3,
            who: "round-3 family A", scored: "2026-09-02",
            note: "Two honest clears at 40 mm, one of which topples inside the tail.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: 7, hash: "8c57838ee9d0", file: "best_r6_ceilvault_60mm.json",
            moveName: "beak_strut_vault_r6_ceiling_60mm",
            family: "R6 ceiling — beak-strut vault launch",
            riseMillimetres: 60, riseSaid: "60 mm",
            kCore: 1, kCoreStable: 1, kExt: 1, kExtStable: 1, ceilingCore: 5,
            who: "round-6 ceiling CEM", scored: "2026-09-02",
            note: "The best ceiling objective in the corpus: five cells over the bar, one of "
                + "them landed.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: 8, hash: "74d35b21ac80", file: "best_r2_vault_60mm.json",
            moveName: "beak_strut_vault_60mm",
            family: "C beak-strut vault",
            riseMillimetres: 60, riseSaid: "60 mm",
            kCore: 2, kCoreStable: 1, kExt: 2, kExtStable: 1, ceilingCore: 3,
            who: "round-2 vault", scored: "2026-09-02",
            note: "The round-2 vault at 60 mm.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: 9, hash: "86813f9c1ad4", file: "best_r2_vault_40mm.json",
            moveName: "beak_strut_vault_40mm",
            family: "C beak-strut vault",
            riseMillimetres: 40, riseSaid: "40 mm",
            kCore: 1, kCoreStable: 1, kExt: 1, kExtStable: 1, ceilingCore: 4,
            who: "round-2 vault", scored: "2026-09-02",
            note: "The round-2 vault at 40 mm.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: nil, hash: "e0434c2c90da", file: "best_r5_servo_60mm.json",
            moveName: "best_r5_servo_60mm",
            family: "r5_servo",
            riseMillimetres: 60, riseSaid: "60 mm",
            kCore: 4, kCoreStable: 0, kExt: 5, kExtStable: 0, ceilingCore: 4,
            who: "round-5 servo", scored: "2026-09-02",
            note: "ORACLE. Its landing law reads the tread's height and edge straight out of the "
                + "plant, which no robot could, so it is published as a measurement and not as "
                + "an entry. Every one of its clears topples inside the tail.",
            isRecord: false, isOracle: true, isControl: false),
        Row(rank: nil, hash: "880a120ef649", file: "best_r5_servoland_kcore_60mm.json",
            moveName: "servoed_landing_r5_kcore_60mm",
            family: "Round 5: the round-3 beak-strut LAUNCH + a per-tick servoed landing (climb/servo.mjs)",
            riseMillimetres: 60, riseSaid: "60 mm",
            kCore: 3, kCoreStable: 0, kExt: 4, kExtStable: 0, ceilingCore: 3,
            who: "round-5 servo", scored: "2026-09-02",
            note: "ORACLE, as above.",
            isRecord: false, isOracle: true, isControl: false),
        Row(rank: nil, hash: "2524a35672b4", file: "best_r4_famB_beat1_90mm.json",
            moveName: "famB_b1_90",
            family: "B two-beat (round 4) — beat 1, from the floor",
            riseMillimetres: 90, riseSaid: "90 mm",
            kCore: 0, kCoreStable: 0, kExt: 0, kExtStable: 0, ceilingCore: nil,
            who: "round-4 family B", scored: "2026-09-02",
            note: "The best 90 mm move in the corpus, and it clears nothing.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: nil, hash: "7c52acef4acf", file: "best_r4_famB_beat1_120mm.json",
            moveName: "famB_b1_120",
            family: "B two-beat (round 4) — beat 1, from the floor",
            riseMillimetres: 120, riseSaid: "120 mm",
            kCore: 0, kCoreStable: 0, kExt: 0, kExtStable: 0, ceilingCore: nil,
            who: "round-4 family B", scored: "2026-09-02",
            note: "The best 120 mm move in the corpus, and it clears nothing.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: nil, hash: "725674c1b517", file: "best_r3_cornerclimb_180mm.json",
            moveName: "cornerclimb",
            family: "C_whole_body_corner_climb_r3",
            riseMillimetres: 180, riseSaid: "180 mm",
            kCore: 0, kCoreStable: 0, kExt: 0, kExtStable: 0, ceilingCore: nil,
            who: "round-3 corner climb", scored: "2026-09-02",
            note: "The best 180 mm move in the corpus, and it clears nothing.",
            isRecord: false, isOracle: false, isControl: false),
        Row(rank: nil, hash: "d99589396fcb", file: "r4_ctrl_on_tread_60mm.json",
            moveName: "r4_control_on_tread_60mm",
            family: nil,
            riseMillimetres: 60, riseSaid: "60 mm",
            kCore: 9, kCoreStable: 9, kExt: 14, kExtStable: 14, ceilingCore: 9,
            who: "control", scored: "2026-09-02",
            note: "PLACED SPAWN — NOT A CLIMB. A duck spawned already standing on the tread. It "
                + "is here to prove the criterion can be passed at all.",
            isRecord: false, isOracle: false, isControl: true),
        Row(rank: nil, hash: "f5bb2f0476c1", file: "r4_ctrl_on_tread_90mm.json",
            moveName: "r4_control_on_tread_90mm",
            family: nil,
            riseMillimetres: 90, riseSaid: "90 mm",
            kCore: 9, kCoreStable: 9, kExt: 14, kExtStable: 14, ceilingCore: 9,
            who: "control", scored: "2026-09-02",
            note: "The placed spawn again, at 90 mm.",
            isRecord: false, isOracle: false, isControl: true),
        Row(rank: nil, hash: "c703ee6f5a14", file: "ctrl_do_nothing.json",
            moveName: "control_do_nothing",
            family: nil,
            riseMillimetres: 60, riseSaid: "40/60/90 mm",
            kCore: 0, kCoreStable: 0, kExt: 0, kExtStable: 0, ceilingCore: 0,
            who: "control", scored: "2026-09-02",
            note: "A duck that stands still. It is here to prove the criterion cannot be passed "
                + "for free.",
            isRecord: false, isOracle: false, isControl: true),
    ]

    /// The entries, without the three reference controls.
    public static var entries: [Row] { leaderboard.filter { !$0.isControl } }

    /// The three controls, which are the other half of what makes the
    /// criterion believable and belong on the screen beside the entries.
    public static var controls: [Row] { leaderboard.filter(\.isControl) }

    /// The row the round-6 judge records as the holder.
    public static var record: Row { leaderboard.first(where: \.isRecord)! }

    public static func row(file: String) -> Row? {
        leaderboard.first { $0.file == file }
    }

    // MARK: - the files

    public enum ResourceError: Error, Equatable {
        case missing(String)

        public var message: String {
            switch self {
            case .missing(let name):
                return "\(name) is not in this build. The challenge files ship with the app; a "
                     + "missing one is a broken build rather than something you can fix here."
            }
        }
    }

    /// Everything the app carries, by name, so a test can walk it.
    public static var bundledFiles: [String] { leaderboard.map(\.file) }

    static let folder = "StairsChallenge"

    /// The bytes of one intent file, exactly as the dataset publishes them.
    public static func intentData(named file: String) throws -> Data {
        let stem = file.hasSuffix(".json") ? String(file.dropLast(5)) : file
        guard let url = Bundle.module.url(forResource: "\(folder)/intents/\(stem)",
                                          withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw ResourceError.missing(file)
        }
        return data
    }

    /// The leaderboard markdown, verbatim. Shipped as the receipt for the
    /// typed `leaderboard` above rather than parsed at runtime.
    public static func leaderboardMarkdown() throws -> Data {
        guard let url = Bundle.module.url(forResource: "\(folder)/leaderboard",
                                          withExtension: "md"),
              let data = try? Data(contentsOf: url) else {
            throw ResourceError.missing("leaderboard.md")
        }
        return data
    }

    /// One move, parsed.
    public static func move(named file: String) throws -> Move {
        try Move.decode(intentData(named: file))
    }

    public static func move(for row: Row) throws -> Move {
        try move(named: row.file)
    }

    /// The editable draft a row opens as.
    public static func draft(for row: Row) throws -> IntentDraft {
        try move(for: row).toDraft(hash: row.hash, rank: row.rank)
    }
}
