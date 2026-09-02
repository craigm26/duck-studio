import Foundation

extension BallChallenge {

    /// THE FOUR BUNDLED ENTRANT FILES, AS THEIR OWN BYTES.
    ///
    /// COPIED OUT OF `duck-sounds/chase` WITHOUT A BYTE CHANGED, which is the
    /// same discipline the stairs challenge keeps for its nineteen intent
    /// files and it exists for the same reason: the bench hashes the entrant
    /// object it receives, and `chase_controls-results.json` publishes each of
    /// these four under a sha256 of exactly these bytes. An app that retyped
    /// one would be scoring a different entrant under a published row's name.
    ///
    /// THEY ARE LITERALS RATHER THAN RESOURCES only because they are four
    /// small files and a Swift literal can be diffed against the harness's own
    /// in one test. `BallFixtureTests.testTheBundledEntrantsAreTheHarnessesOwnFiles`
    /// reads `duck-sounds/chase/<file>` when the harness is checked out beside
    /// this repository and compares the bytes; when it is not, it SKIPS BY
    /// NAME. THE FILE WINS: a disagreement is fixed here, never there.
    ///
    /// THE FORMATTING IS THE HARNESS'S AND NOT `JSON.stringify`'s. These files
    /// are hand-authored, with the pose arrays and the schedule pairs on one
    /// line, so `Entrant.encoded()` — which writes the canonical two-space
    /// shape — does NOT reproduce them. `text(_:)` is what carries the bytes;
    /// `encoded()` is for a bundle and a request body, where the bench
    /// normalises before it hashes.
    public enum Entrants {

        /// A bundled file's bytes, exactly as `duck-sounds/chase` holds them.
        public static func text(_ file: String) -> String? { texts[file] }

        /// The same, as the bytes a byte comparison needs.
        public static func data(_ file: String) -> Data? { texts[file].map { Data($0.utf8) } }

        /// The file names, in the order the controls are run.
        public static var files: [String] { BallChallenge.controls.map(\.file) }

        /// Parsed, or a crash at first use — these are the app's own bytes and
        /// a build that ships an unparseable one is broken, not recoverable.
        static func pinned(_ file: String) -> Entrant {
            // swiftlint:disable:next force_try
            try! Entrant.decode(Data(texts[file]!.utf8))
        }

        public static var doNothing: Entrant { pinned("ctrl_do_nothing.json") }
        public static var ballKickLeft: Entrant { pinned("ctrl_ball_kick_left.json") }
        public static var ballKickRight: Entrant { pinned("ctrl_ball_kick_right.json") }
        public static var alphaWalking: Entrant { pinned("ctrl_alpha_walking.json") }

        static let texts: [String: String] = [
            "ctrl_do_nothing.json": #"""
                {
                  "name": "ctrl_do_nothing",
                  "kind": "move",
                  "seconds": 5,
                  "intent": {
                    "name": "ctrl_do_nothing",
                    "keyframes": [
                      { "t": 1.0, "pose": [0, -0.0873, -0.4579, -0.0049, 0.453, 0.3491, 0.3491, 0, 0, 0, 0.0873, 0.4579, 0.0049, -0.453] },
                      { "t": 4.9, "pose": [0, -0.0873, -0.4579, -0.0049, 0.453, 0.3491, 0.3491, 0, 0, 0, 0.0873, 0.4579, 0.0049, -0.453] }
                    ],
                    "blend": 1
                  },
                  "note": "DO-NOTHING CONTROL. HOME held for the whole track, no command. EXPECTED 0 of 14: the nearest ball is 450 mm away and the duck never leaves the spot. A CRITERION THIS ROW PASSES IS NOT A CHASING TEST — the same guard climb/ctrl_do_nothing.json is, in the same words, and the first thing chase_parity.mjs checks."
                }
                """# + "\n",

            "ctrl_ball_kick_left.json": #"""
                {
                  "name": "ctrl_ball_kick_left",
                  "kind": "policy",
                  "seconds": 5,
                  "policy": "ball_kick_left.onnx",
                  "schedule": [[0, { "vx": 0, "vy": 0, "vyaw": 0 }]],
                  "note": "POLLEN'S KICK POLICY AT THE CONFIG'S OWN COMMAND. The schedule is read out of microduck_ball_kick_env_cfg.py, not chosen by taste: the twist command slot is kept only for observation-shape parity (cfg 406-408 lin_vel_x (-0.01, 0.01), lin_vel_y (-0.01, 0.01), ang_vel_z (-0.05, 0.05), rel_standing_envs 0.0, heading_command False, resampled once per episode), and zero is the centre of all three ranges. seconds 5 is EPISODE_LENGTH_S (cfg 74). EXPECTED 0 of 14, and that is the point: this policy is BLIND to the ball by design (cfg 11-15) and swings at one 90 mm in front of the toe. Commanding it to walk would be commanding it 50x outside its own range and calling the result a measurement of Pollen's policy."
                }
                """# + "\n",

            "ctrl_ball_kick_right.json": #"""
                {
                  "name": "ctrl_ball_kick_right",
                  "kind": "policy",
                  "seconds": 5,
                  "policy": "ball_kick_right.onnx",
                  "schedule": [[0, { "vx": 0, "vy": 0, "vyaw": 0 }]],
                  "note": "THE SAME POLICY WITH KICK_FOOT FLIPPED. KICK_FOOT (cfg 41) is a module-level flag, not a per-policy field, and nothing in the reward differs between the two runs — only the ball spawn side and which foot the (refused) support_foot_grounded sensor watches. So both bundled kick policies are correctly scored under ONE term table. Same schedule, same seconds, same expectation as ctrl_ball_kick_left."
                }
                """# + "\n",

            "ctrl_alpha_walking.json": #"""
                {
                  "name": "ctrl_alpha_walking",
                  "kind": "policy",
                  "seconds": 4,
                  "policy": "alpha_walking.onnx",
                  "schedule": [[0, { "vx": 0.5, "vy": 0, "vyaw": 0 }]],
                  "note": "THE NAIVE CHASER. Straight ahead at 0.5 m/s for four seconds — a nominal reach of about 2 m, so a ball at 0.45, 0.70, 0.95 or even 1.20 m is inside the walk IF IT IS DEAD AHEAD. At +/-20 degrees a ball at 0.70 m sits about 240 mm off the walk line and at +/-40 about 450 mm off, and the duck walks straight past both. alpha_walking.onnx is the VELOCITY config's policy, so the nine terms reported for it are the ball-kick config's terms evaluated on a policy trained under microduck_velocity_env_cfg.py; it is here as a CHASER, judged by the criterion. This is the control that draws the line the challenge asks someone to cross: open-loop forward walking already solves 'the ball is straight ahead', and nothing bundled solves 'the ball is over there'."
                }
                """# + "\n",
        ]
    }
}
