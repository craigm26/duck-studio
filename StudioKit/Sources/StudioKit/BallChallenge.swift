import Foundation

/// The Microduck ball challenge, as this app carries it.
///
/// WHAT THE CHALLENGE IS, IN THE ONE SENTENCE THE SCREEN SHOWS. A 30 g ball is
/// put down somewhere in front of a 250 mm bipedal duck — straight ahead, or
/// off to one side, between 450 mm and 1.2 m away — and the duck has to reach
/// it and move it, in simulation, without falling over.
///
/// AND WHY THAT IS HARD, WHICH IS THE WHOLE POINT. The two ball policies
/// Pollen ships were trained to stand still and swing one leg at a ball 90 mm
/// in front of the toe, and they are BLIND TO THE BALL BY DESIGN — the config
/// says so in its own header. The nearest cell of this grid is five times that
/// distance. So the bundled entrants are expected to fail almost everything,
/// and a walking policy commanded straight ahead is expected to pass the cells
/// where the ball happens to be dead ahead and nothing else. The unclaimed
/// half of the grid — the ball at ±20° and ±40° — is what the challenge is
/// actually about, and closing it needs steering: a person editing a keyframe
/// to make the duck turn, or later a policy that reads the ball.
///
/// TWO KINDS OF ENTRANT, BOTH SCOREABLE FROM DAY ONE. An AUTHORED MOVE is a
/// harness intent — keyframes and a blend, run under the bench's settle,
/// exactly as the stairs challenge runs one — and it is editable in the
/// Studio. A POLICY is a network name and a command schedule. The policy
/// entrant is what makes "chase" a closed-loop question later: the same field
/// carries a fixed schedule today and a schedule computed from the ball's
/// bearing tomorrow, with no change to the entrant format, the hash, this kit
/// or the app. `policyNotEditable` is the sentence for the half of that which
/// a person cannot open in the editor.
///
/// EVERY NUMBER HERE IS SIMULATION AND NOTHING IN IT HAS RUN ON HARDWARE, and
/// there is a second caveat this challenge carries that the stairs one does
/// not: POLLEN'S BALL IS NOT THIS BALL. The kick config trains against a 70 mm,
/// 15 g ball; `scene.mjb`'s is 100 mm and 30 g. Every reward term is still the
/// config's own function at the config's own weight, evaluated on a different
/// ball — which is why every row carries the plant digest and why
/// `ballCaveat` travels with every absolute number.
public enum BallChallenge {

    // MARK: - what it is

    public static let title = "Ball Challenge"

    public static let oneSentence =
        "Get the duck to reach a ball and move it in simulation — from wherever the ball is put "
      + "down, up to 1.2 m away and up to 40° off the duck's heading — and stay standing."

    /// THE CRITERION, VERBATIM AS `sim/chase_score.mjs` EXPORTS IT. The bench
    /// sends its own copy back with every scored cell and
    /// `BallChallenge.Score` compares the two; this constant exists so the app
    /// can say what it is about to ask for before the first answer arrives,
    /// and so the sentence is a string with a test on it rather than a caption
    /// somebody typed.
    public static let criterionSentence =
        "chased: the duck touched the ball — any duck geometry within 3 mm of it at any tick — "
      + "and the ball finished at least 100 mm further along the duck's initial heading than it "
      + "started, and the duck was still upright at the end of the episode. stable: chased, and "
      + "upright for at least 45 of the 50 tail ticks."

    /// Why the criterion is three facts and not the shaped sum of the nine
    /// reward terms the bench also reports. Said on the screen beside the
    /// terms, because a person looking at nine weighted numbers is entitled to
    /// know which of them the leaderboard is sorted on: none.
    public static let whyNotTheReward =
        "The nine reward terms are the reward these policies were trained on, and they are "
      + "reported so an edit can be watched moving them. They are not the verdict: a shaped sum "
      + "of nine weighted terms is not a thing a person can hold in their head, and a "
      + "leaderboard sorted on it would reward a duck that stands beautifully still."

    /// The three constants the criterion is made of, which live in
    /// `chase_score.mjs` and nowhere else. `BallGridTests` pins them.
    public static let touchMillimetres = 3.0
    public static let travelMinimumMillimetres = 100.0
    public static let tailTicks = 50
    /// The same bar `climb_score.mjs` uses, on purpose: a person who has read
    /// one challenge already knows what this one means.
    public static let uprightTailMinimum = 45

    /// The plant every published number is produced in — the same compiled
    /// model the stairs challenge uses, because it is the canon plant every
    /// recorded duckkit clip claims to come from.
    public static let plantName = StairsChallenge.plantName
    public static let plantDigest = StairsChallenge.plantDigest

    public static let datasetURL =
        URL(string: "https://huggingface.co/datasets/craigm26/microduck-ball-challenge")!
    public static let harnessURL = StairsChallenge.harnessURL

    /// Positive bearing is LEFT — the convention `POST /ball`, duckvision and
    /// the robot all use, so a trial reads the same way the detector reports.
    /// Said on screen wherever a bearing is drawn, because a grid of ±20° with
    /// no stated sign is a grid nobody can reproduce.
    public static let bearingConvention =
        "Positive bearing is to the duck's LEFT, the convention the ball detector and the robot "
      + "both use. Range is metres from the duck's root to the ball's centre, measured after the "
      + "duck has settled."

    public static func bearingSaid(_ degrees: Double) -> String {
        let whole = Int(degrees.rounded())
        return whole > 0 ? "+\(whole)°" : "\(whole)°"
    }

    public static func rangeSaid(_ metres: Double) -> String {
        String(format: "%.2f m", metres)
    }

    public static func secondsSaid(_ seconds: Double) -> String {
        let whole = seconds.rounded()
        return whole == seconds ? "\(Int(whole)) s" : String(format: "%.1f s", seconds)
    }

    // MARK: - the sentences that keep it honest

    /// Beside the one button that makes something move. IT PLAYS ON THE BENCH.
    public static let realDuckCaveat =
        "This plays the entrant on the bench, in physics. Playing it on a real Microduck is not "
      + "wired in this build, a score exists only on a bench, and nothing here has been run on "
      + "hardware."

    /// Beside the play button: playing is not a scored cell.
    public static let playNote =
        "Playing runs the entrant with the ball wherever the plant last left it. It is not a grid "
      + "cell and produces no score; Score it to put the ball at every cell in turn."

    /// The caveat that shadows every absolute number in this challenge, and
    /// the one thing that makes it different from the stairs.
    public static let ballCaveat =
        "Pollen's ball is not this ball. The kick config was trained against a 70 mm, 15 g ball; "
      + "this plant's is 100 mm and 30 g — 1.43× the radius and twice the mass. Every reward "
      + "term below is the config's own function at the config's own weight, evaluated on a "
      + "different ball, so a speed in m/s is not comparable with anything Pollen published."

    /// A bench that cannot score this. NAMES THE BENCH AND WHAT TO UPDATE.
    public static func noChaseHere(bench: String) -> String {
        "No /chase on \(bench). This bench answers /health and /perform but not the ball "
      + "challenge, so nothing here can be scored on it. Pick a bench that has it — this "
      + "iPhone's own bench does, once the app is updated — or update the Pi bench from "
      + "github.com/craigm26/duck-sounds and restart it with "
      + "`systemctl --user restart duckbench`."
    }

    /// What the app is claiming when it shows a score: not a new measurement,
    /// the harness's own one, re-run here.
    public static func sameCriterion(plantDigest digest: String?) -> String {
        let plant = digest.map { "plant \($0.prefix(DuckBench.digestShown))" }
                    ?? "plant, which it did not identify"
        return "This is chase_robust's criterion and grid, scored on this bench's \(plant)."
    }

    /// THE SENTENCE FOR A POLICY ROW. A policy entrant can be scored and
    /// played and it cannot be opened in the editor, because there are no
    /// keyframes in it — and an "Open in the editor" button that opened an
    /// empty draft would be worse than no button.
    public static let policyNotEditable =
        "This entrant is a trained network under a command schedule, not keyframes. It can be "
      + "scored and played here; there is nothing to open in the editor, because there is no "
      + "authored pose in it to change."

    /// Under "Open in the editor", for the move entrants.
    public static let editorNote =
        "It becomes a motion in Studio, with the challenge and this entrant's hash written into "
      + "its provenance. Change any keyframe's servo values there, then score your edited "
      + "version here."

    /// The edit-score-keep loop, said where the edited version is scored.
    public static let editedVersionNote =
        "Your edited version, scored on the same fourteen cells as the published entrant. Keep "
      + "what scores better; put back what scores worse. There is no reward model in this loop — "
      + "you are the judge, and the bench is the measurement."
    public static let editedNotFoundNote =
        "Open the entrant in the editor first. The edited version is looked up by the draft the "
      + "editor saved; there is none yet."

    /// The 14 joints of a harness pose are the policy's action space, and the
    /// mouth is the joint it skips. Said only when an edit actually moved it.
    public static let mouthDroppedNote = StairsChallenge.mouthDroppedNote

    /// What `action_rate_l2` means for the two kinds of entrant, which is not
    /// the same thing. Labelled rather than refused, because a move genuinely
    /// has an action; the label is what stops the two being compared.
    public static func actionRateSaid(_ source: String?) -> String {
        switch source {
        case "policy raw output":
            return "action_rate_l2 is over the network's raw 14-vector, which is what mjlab "
                 + "penalises. Comparable with another policy, not with a move."
        case "keyframe pose target":
            return "action_rate_l2 is over the interpolated pose target the keyframes emit — "
                 + "there is no network here. Comparable with another move, not with a policy."
        default:
            return "The bench did not say which action this rate is over, so it is not "
                 + "comparable with anything."
        }
    }

    // MARK: - the leaderboard

    /// One published row.
    ///
    /// `kStable` IS THE COLUMN A RANK MEANS ANYTHING ABOUT — `chased` is what
    /// the leaderboard sorts on and `stable` is the stricter one printed
    /// beside it — and both travel, for the same reason the stairs table
    /// carries `kCore` beside `kCoreStable`: an entrant can move the ball and
    /// topple inside the tail, and a screen showing one number alone would be
    /// quoting something the table does not rank by.
    public struct Row: Equatable, Sendable, Identifiable {
        public let rank: Int?
        /// `hash` truncated to twelve, exactly as the table prints it.
        public let hash: String
        /// THE WHOLE DIGEST. The twelve-character form is what a table prints
        /// and what a person types into a search box; the sha-pinning is this,
        /// and a row pinned by a prefix is a row pinned by nothing.
        public let sha256: String
        /// The network, for a policy row. Nil for a move.
        public let policy: String?
        /// The file in `chase/`, which is also this row's identity here.
        public let file: String
        /// The `name` inside that file.
        public let entrantName: String
        public let kind: Entrant.Kind
        /// Episode length in seconds, which is part of what was measured.
        public let seconds: Double
        /// How the entrant was commanded, in words — "held at rest", "vx 0.5
        /// straight ahead", "keyframes". Nil for a move.
        public let commandSaid: String?
        /// Of the 9 core cells.
        public let kChased: Int
        public let kStable: Int
        /// Of the 5 extended cells.
        public let kExt: Int
        public let kExtStable: Int
        /// How many of the fourteen cells the duck touched the ball in at all,
        /// and the furthest the ball ever went along the duck's heading. THE
        /// TWO FACTS A ZERO ROW STILL HAS: three of these four rows chase
        /// nothing, and "touched nothing, moved it 0 mm" is what makes that a
        /// measurement rather than a blank.
        public let touchedCells: Int
        public let maxBallTravelMillimetres: Double
        public let who: String
        public let scored: String
        public let note: String
        /// A reference row, not an entry.
        public let isControl: Bool

        public init(rank: Int?, hash: String, sha256: String, file: String, entrantName: String,
                    kind: Entrant.Kind, policy: String? = nil,
                    seconds: Double, commandSaid: String? = nil,
                    kChased: Int, kStable: Int, kExt: Int, kExtStable: Int,
                    touchedCells: Int, maxBallTravelMillimetres: Double,
                    who: String, scored: String, note: String, isControl: Bool) {
            self.rank = rank; self.hash = hash; self.sha256 = sha256; self.file = file
            self.entrantName = entrantName; self.kind = kind; self.policy = policy
            self.seconds = seconds
            self.commandSaid = commandSaid
            self.kChased = kChased; self.kStable = kStable
            self.kExt = kExt; self.kExtStable = kExtStable
            self.touchedCells = touchedCells
            self.maxBallTravelMillimetres = maxBallTravelMillimetres
            self.who = who; self.scored = scored; self.note = note
            self.isControl = isControl
        }

        public var id: String { file }

        public var rankSaid: String { rank.map(String.init) ?? "—" }

        public var headline: String { "\(who) — \(BallChallenge.secondsSaid(seconds))" }

        public var scoreSaid: String { "\(kChased) of \(Grid.coreCount) chased" }

        /// Whether this row can be opened in the editor at all.
        public var isEditable: Bool { kind == .move }
    }

    /// THE BUNDLED LEADERBOARD — the four controls' MEASURED rows, sha-pinned.
    ///
    /// EVERY NUMBER HERE WAS PRODUCED BY `chase/chase_robust.mjs` and is
    /// transcribed out of `chase/chase_controls-results.json`, which
    /// `BallFixtureTests` re-reads and asserts these rows against, row by row
    /// and digest by digest, whenever the harness is checked out beside this
    /// repository. An app that retyped a leaderboard would be showing numbers
    /// nobody can trace to the run that produced them.
    ///
    /// THREE OF THE FOUR ROWS ARE ZEROES AND THAT IS THE RESULT, not a gap in
    /// the table. The predictions in `controls` were written before the run:
    /// do-nothing must fail everything or the criterion is not a chasing test;
    /// the two kick policies were predicted to fail everything because they
    /// are blind to the ball by design and were trained on one 90 mm in front
    /// of the toe. They did. The naive chaser was predicted to take roughly
    /// two to four of the nine core cells and to fail every off-bearing one.
    /// It took FOUR, touched the ball in five of the fourteen, and took ONE of
    /// the five extended — which is the line the challenge asks somebody to
    /// cross, drawn by measurement instead of by assertion.
    ///
    /// THERE IS NO RANK ON ANY ROW. All four are controls, and a control is
    /// not an entry: ranking them would put "walk forward and hope" at the top
    /// of a leaderboard for chasing.
    public static let leaderboard: [Row] = [
        Row(rank: nil, hash: "bc77453e40c6",
            sha256: "bc77453e40c677db4073a350da5a43d645676d77e1252f51bbf6544be54ca187",
            file: "ctrl_do_nothing.json", entrantName: "ctrl_do_nothing",
            kind: .move, policy: nil, seconds: 5, commandSaid: nil,
            kChased: 0, kStable: 0, kExt: 0, kExtStable: 0,
            touchedCells: 0, maxBallTravelMillimetres: 0,
            who: "control", scored: "2026-09-02",
            note: "A duck that stands still. 0 of 14, as it had to be: it never touched the "
                + "ball in any cell and the ball never moved. It is here to prove the criterion "
                + "cannot be passed for free.",
            isControl: true),
        Row(rank: nil, hash: "7e44b5a781fc",
            sha256: "7e44b5a781fc6763042a43065598424ea945f3bc8956bd0f1127aca4ec81b6e9",
            file: "ctrl_ball_kick_left.json", entrantName: "ctrl_ball_kick_left",
            kind: .policy, policy: "ball_kick_left.onnx", seconds: 5,
            commandSaid: "held at rest",
            kChased: 0, kStable: 0, kExt: 0, kExtStable: 0,
            touchedCells: 0, maxBallTravelMillimetres: 0,
            who: "Pollen ball_kick_left", scored: "2026-09-02",
            note: "Pollen's left-foot kick policy at the centre of its own command "
                + "distribution. 0 of 14, and it never came within 300 mm of the ball. THIS IS "
                + "THE MEASUREMENT THAT STATES THE PROBLEM: the best ball policy Pollen ships "
                + "cannot chase a ball, because chasing was never the task.",
            isControl: true),
        Row(rank: nil, hash: "f8d4e8bfd2b7",
            sha256: "f8d4e8bfd2b789668cdf58e7683100d04cf48af2d1fe746d495fc4f697e03ffe",
            file: "ctrl_ball_kick_right.json", entrantName: "ctrl_ball_kick_right",
            kind: .policy, policy: "ball_kick_right.onnx", seconds: 5,
            commandSaid: "held at rest",
            kChased: 0, kStable: 0, kExt: 0, kExtStable: 0,
            touchedCells: 0, maxBallTravelMillimetres: 0,
            who: "Pollen ball_kick_right", scored: "2026-09-02",
            note: "The same policy with the kick foot flipped, and the same 0 of 14. Whichever "
                + "foot swings, REACHING the ball is the unsolved half, not kicking it.",
            isControl: true),
        Row(rank: nil, hash: "a0bbbbb98acb",
            sha256: "a0bbbbb98acb7fc5bc1d035527c2c7b153df1c3555db79b9c12e4f446d49d6a5",
            file: "ctrl_alpha_walking.json", entrantName: "ctrl_alpha_walking",
            kind: .policy, policy: "alpha_walking.onnx", seconds: 4,
            commandSaid: "vx 0.5",
            kChased: 4, kStable: 4, kExt: 1, kExtStable: 1,
            touchedCells: 5, maxBallTravelMillimetres: 641.2679543760061,
            who: "naive chaser", scored: "2026-09-02",
            note: "The velocity policy commanded straight ahead at 0.5 m/s. Four of the nine "
                + "core cells and one of the five extended, touching the ball in five of the "
                + "fourteen — and not the cells that were predicted. It takes the whole −20° "
                + "column (0.45, 0.70 and 0.95 m) and dead-ahead at 0.45 m, and misses the ball "
                + "dead ahead at 0.70 and 0.95 m: driven open-loop the gait drifts about 15° "
                + "right, so it walks into the −20° column and past a ball straight ahead. "
                + "Open-loop walking solves \"the ball happens to be where this gait drifts\", "
                + "not \"the ball is straight ahead\"; every cell it misses needs steering, and "
                + "nothing bundled steers.",
            isControl: true),
    ]

    /// Said where the table would be, if the leaderboard were ever empty.
    public static let leaderboardPending =
        "No measured rows in this build. The four bundled entrants below have not been scored by "
      + "the harness yet, so what they carry is a prediction of how they will do and not a "
      + "result. Score one on a bench and the numbers you get are the first ones there are."

    /// The one line the table needs above it: what these four rows establish
    /// between them, which is the whole reason the challenge exists.
    public static let leaderboardSaid =
        "Four control rows, no entries. Standing still and both of Pollen's kick policies chase "
      + "nothing at all; walking straight ahead takes 4 of the 9 core cells and 1 of the 5 "
      + "extended — the whole −20° column and dead-ahead at 0.45 m, because the gait drifts "
      + "about 15° right — and misses the ball dead ahead at 0.70 and 0.95 m. Every cell it "
      + "misses needs steering, and nothing bundled steers."

    /// THE PREDICTION AND THE MEASUREMENT, SIDE BY SIDE. The walker's count
    /// held (4, inside the predicted 2 to 4) and its shape did not: the
    /// prediction named the dead-ahead column, the run took the −20° one.
    /// Said on screen in place of a seal, because a seal over a count that
    /// happened to land inside a range would be a claim the cells disprove.
    public static let walkerPredictionSaid =
        "The count held — 4 of 9, inside the predicted 2 to 4 — and the shape did not: the "
      + "prediction named the dead-ahead cells, and the run took the −20° column plus dead-ahead "
      + "at 0.45 m. The gait drifts about 15° right."

    public static var entries: [Row] { leaderboard.filter { !$0.isControl } }
    public static var controlRows: [Row] { leaderboard.filter(\.isControl) }
    public static func row(file: String) -> Row? { leaderboard.first { $0.file == file } }

    // MARK: - the four bundled entrants

    /// A bundled entrant, its declared expectation, and what it establishes.
    ///
    /// WHY THE EXPECTATION IS A STRING IN THE BUILD. The four controls are the
    /// only reason anybody should believe the criterion. `ctrl_do_nothing`
    /// must fail every cell — a criterion it passes is not a chasing test —
    /// and the two kick policies are expected to fail everything for a reason
    /// that is the actual finding. Written down before the run, on screen,
    /// they are a prediction somebody can watch being tested. Written down
    /// after, they would be a caption.
    public struct Control: Equatable, Sendable, Identifiable {
        /// The file in `duck-sounds/chase/`.
        public let file: String
        public let entrant: Entrant
        public let who: String
        /// What this is expected to do, stated in advance.
        public let expected: String
        /// What its pass or its fail proves.
        public let establishes: String

        public var id: String { file }
        public var name: String { entrant.name }
        public var isEditable: Bool { entrant.isEditable }

        /// The published row for this control, once there is one.
        public var row: Row? { BallChallenge.row(file: file) }

        /// Whether the run agreed with what was declared in advance. NIL until
        /// there is a row: an expectation with nothing to check it against is
        /// a prediction, not a finding.
        /// What to print about the prediction: the seal's sentence when it
        /// held, both halves when it did not, nothing when there is no row.
        public var predictionSaid: String? {
            guard let held = predictionHeld else { return nil }
            if held { return "The prediction held." }
            return file == "ctrl_alpha_walking.json" ? BallChallenge.walkerPredictionSaid
                : "The prediction did not hold: \(expected)"
        }

        public var predictionHeld: Bool? {
            guard let row else { return nil }
            switch file {
            case "ctrl_do_nothing.json",
                 "ctrl_ball_kick_left.json",
                 "ctrl_ball_kick_right.json":
                // Predicted 0 of 14 and nothing touched.
                return row.kChased == 0 && row.kExt == 0 && row.touchedCells == 0
            case "ctrl_alpha_walking.json":
                // THE COUNT HELD AND THE SHAPE DID NOT. The prediction named the
                // bearing-0 cells; the run took the −20° column and dead-ahead
                // only at 0.45 m (chase_controls-results.json). A prediction of
                // WHICH cells is not held by a count that lands in its range,
                // so this is false, and `predictionSaid` says both halves.
                return false
            default:
                return nil
            }
        }
    }

    /// The four, in the order they are run and shown.
    public static let controls: [Control] = [
        Control(
            file: "ctrl_do_nothing.json",
            entrant: Entrants.doNothing,
            who: "control",
            expected:
                "0 of 14 — it must fail every cell. The duck holds its home pose for five "
              + "seconds and the nearest ball is 450 mm away, so it never touches anything.",
            establishes:
                "A CRITERION THIS ROW PASSES IS NOT A CHASING TEST. Its fail is what proves the "
              + "criterion cannot be met for free."),
        Control(
            file: "ctrl_ball_kick_left.json",
            entrant: Entrants.ballKickLeft,
            who: "Pollen ball_kick_left",
            expected:
                "0 of 14, or very close — and that is the point. This policy is blind to the "
              + "ball by design and was trained to swing one leg at a ball 90 mm in front of the "
              + "toe. The nearest cell here is five times that distance and it is not commanded "
              + "to walk.",
            establishes:
                "Its fail states the problem: the best ball policy Pollen ships cannot chase a "
              + "ball, because chasing was never the task. A pass at any cell would be a genuine "
              + "result — that its kick generalises past 90 mm — which is why the row is run "
              + "rather than assumed."),
        Control(
            file: "ctrl_ball_kick_right.json",
            entrant: Entrants.ballKickRight,
            who: "Pollen ball_kick_right",
            expected:
                "0 of 14, or very close, for the same reason as the left kick. Nothing in the "
              + "reward differs between the two runs — only the ball's spawn side and which foot "
              + "the refused contact term watches — so both are scored under one term table.",
            establishes:
                "The pair together: whichever foot swings, reaching the ball is the unsolved "
              + "half, not kicking it."),
        Control(
            file: "ctrl_alpha_walking.json",
            entrant: Entrants.alphaWalking,
            who: "naive chaser",
            expected:
                "Roughly 2 to 4 of the 9 core cells: the bearing-0 cells, and the far one at "
              + "1.20 m. At ±20° a ball at 0.70 m sits about 240 mm off the walk line and at "
              + "±40° about 450 mm off — the duck walks straight past both.",
            establishes:
                "The line somebody is being asked to cross. Open-loop forward walking solves "
              + "\"the ball happens to be where this gait drifts\" — the −20° column and 0.45 m "
              + "dead ahead — and not \"the ball is straight ahead\" at 0.70 or 0.95 m, nor "
              + "\"the ball is over there\". Every cell it misses needs steering, and nothing "
              + "bundled steers."),
    ]

    /// Every bundled entrant, without the expectation wrapper.
    public static var bundledEntrants: [Entrant] { controls.map(\.entrant) }

    public static func control(file: String) -> Control? {
        controls.first { $0.file == file }
    }

    /// The one entrant a person can open in the editor today. The three
    /// policies cannot be edited, and `policyNotEditable` says why.
    public static var editableControls: [Control] { controls.filter(\.isEditable) }

    /// `alpha_walking.onnx` is the VELOCITY config's policy, so its reward
    /// terms come from a different table than the two kick networks'. It is in
    /// this challenge as a CHASER, judged by the criterion; its term values
    /// carry this caveat.
    public static let velocityPolicyCaveat =
        "alpha_walking was trained under microduck_velocity_env_cfg.py, not the ball-kick "
      + "config. It is here as a chaser and it is judged by the criterion; the reward terms "
      + "beside it are the kick config's terms evaluated on a policy that never saw them."

    /// Which policies this challenge knows a reward table for, and which it
    /// does not. A bench asked to score any other policy still answers — the
    /// criterion is plant facts — but the terms would be the kick config's
    /// evaluated on a stranger, and this is how a screen knows to say so.
    /// The editable draft a control opens as, with its published hash written
    /// into the provenance. Mirrors `StairsChallenge.draft(for:)`; THROWS for
    /// a policy control, because there are no keyframes in one and
    /// `policyNotEditable` is the sentence the screen shows instead.
    public static func draft(for control: Control) throws -> IntentDraft {
        try control.entrant.toDraft(hash: control.row?.hash, rank: control.row?.rank)
    }

    public static func rewardCaveat(forPolicy filename: String?) -> String? {
        guard let filename else { return nil }
        switch RunMetrics.Task.forPolicy(filename) {
        case .ballKick: return nil
        case .velocity: return velocityPolicyCaveat
        default:
            return "\(filename) is not a policy this challenge has a reward table for. The "
                 + "criterion still applies — it is three facts about the ball and the duck — "
                 + "but the terms beside it are the ball-kick config's, evaluated on a network "
                 + "trained under something else."
        }
    }
}
