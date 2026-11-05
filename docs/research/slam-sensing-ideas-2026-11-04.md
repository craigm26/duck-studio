# Microduck SLAM and sensing: 12 ideas ranked by value to the native-first, three-mode, brains-layer direction divided by effort

Ground rules for every item:
- Evals and duck-sim builds run on HF Jobs (x86), never on this Pi. Pi falls in earlier runs were caused by overload.
- duckbench runs alpha_walking, which can't turn in place. Its numbers do not transfer to Pollen's v8 velstand policy.
- Anything in the app ships in the next session's single TestFlight upload. Build 90 waits if M1 misses.
- Pollen's code is theirs. Changes to it go upstream as issues or PRs.

## 1. Closed-loop distances and angles for App Intents and semi mode, reusing the shipped card loop
- **Idea:** Give App Intents ("walk 30 cm", "turn 90°") and semi mode the closed loop that Duck Cards already has, and finish each move on robotd's `odom {position, yaw}` instead of a timer.
- **Already there:**
  - cardloop.py and duck-card-loop /1 to /7, judged on HF Jobs.
  - /6 (merge 2, chapters 7) shipped in both readers in build 87 through RobotPlanRunner.run(nest:merge:).
  - StudioKit has DuckOrder, StopPath and ControlArbiter.
  - Pollen's `robotctl endurance` walks goal to goal on odometry.
  - A draft Pollen move-by-distance proposal.
- **Not yet:**
  - `enabled_on_robot` is false.
  - Rung 1 fails on both the Pi and HF.
  - IMU-only drift correction (/3 stop calibration) was rejected. A standing duck really yaws, and the IMU can't tell that apart from drift.
  - In sim, long rows only hold up with an external fix, the /7 mat.
- **Needs:** route intent and semi commands through the existing loop, with single short moves only, and keep the robot flag off until rung 1 passes.
- **Effort:** S. **Risk:** low per single move. Long sequences need idea 5.
- **Serves:** App Intents, semi.

## 2. ToF head-sweep obstacle sector map as the safety layer
- **Idea:** Pan the head with `robot.look`, take the median of several 8x8 ToF frames per heading, and reduce them to "free / blocked / drop-off" sectors. ControlArbiter uses them to veto forward motion in semi and auto.
- **Sources:**
  - Source 5 (empty-scene baseline, median of pings, sweep the sensor).
  - Pollen `kinematics/tof.rs`, which has the zones Empty, TooClose, Floor and Hit, corrected for lean.
  - maploc #127 (reported as wanting a head sweep).
- **Already there:** `tof.stream` at 15 Hz, beam directions in `robot.model`, ControlArbiter.
- **Needs:**
  - A sweep routine plus a sector reducer in StudioKit, pure Swift and Linux-testable.
  - Simulated VL53L5CX data (from `microduck_maploc`, which Pollen's simulation.md names as worth taking) for tests.
- **Effort:** S. **Risk:** low.
  - Short range.
  - Sweep only when standing.
  - Not yet checked on a physical duck.
- **Serves:** semi and auto safety, including in the dark.

## 3. Keep failures in the phone-driver recordings
- **Idea:** For the BallExpert takes:
  - Keep the 19 failed attempts out of 179, if the recorder doesn't already.
  - Add deliberate perturbations (bumped heading, ball moved mid-take), labeled with the expert's recovery action.
- **Sources:** source 4 (models break when the data is all successes); book Ch 5.
- **Already there:**
  - `record_ball_takes.py`: 160 takes, 19,314 rows.
  - The Python BallExpert is held to the Swift version within 1e-12.
  - The rescue ladder's rung 2 is DAgger-lite, which overlaps this.
- **Needs:**
  - Recorder flags and a dataset column.
  - A short duckbench session. Physics runs on the Pi, so restart it only with Craig's OK and stop it afterwards.
- **Effort:** S. **Risk:** low.
  - Train on the recovery labels, never copy the failure.
  - Sim duck only.
- **Serves:** the phone driver (auto). Do it before the Mac renderer pass so every take is rendered once.

## 4. Truth vs belief and a latency receipt for duckbench and the phone driver
- **Idea:** Driver runs log the true trunk pose next to the duck's estimate, plus a histogram of frame age, decide time and command round-trip. Studio Evaluations shows both.
- **Sources:** book Ch 3, 4 and 5; Pollen simulation.md (duck-sim `drive` reports the simulator's own trunk travel; forward speed falls short, 0.15 m/s commanded gives 0.06).
- **Already there:**
  - The card eval already scores against sim truth and counts stale-pose stops.
  - duckbench state JSON has the true pose.
  - Studio Evaluations.
- **Needs:** the same logging on the driver path, plus one Evaluations card.
- **Effort:** S. **Risk:** low.
- **Serves:** M1 for the phone driver. The ~4 fps, untimestamped `/frame` poll is the budget the driver lives inside.

## 5. Port the /7 mat compass to the app, then extend to AprilTag landmarks
- **Idea:** First port what sim already proved:
  - /7, which is the mat compass on top of /6: camera grid lines give heading mod 90° and position mod one square, with a pitch estimate and the mat re-laid at each nest.
  - Then add AprilTags (vendored in StudioKit as CAprilTag, already used by the card reader) for rooms without a mat. Fuse them in a small x, y, yaw filter on the phone.
- **Evidence:**
  - /7 long rows at randomized 10 Hz went from 63% to 97.5% (p 0.0002 over sessions), worse nowhere after Holm.
  - The pitch estimate is within 0.5° in 92% of randomized chapters.
  - Sim only.
- **Needs:**
  - A head-camera path in StudioKit.
  - Swift matcam and MatFix with shared test vectors.
  - A printed mat.
  - Stop-and-look, because `/frame` has no capture timestamp (Pollen remote-webrtc). The /7 loop already looks at settles.
  - For tags: printed tags and calibrated intrinsics. `media.video` reports a `calibrated` flag, and the alpha camera has fx ≈ 1062 at 1280x720. Check the `/frame` resolution first.
- **Effort:** M. **Risk:** medium.
  - Nothing has been checked on a physical duck yet.
  - The beta camera differs.
- **Serves:** Packs on real ducks (rung 1), semi and auto ("go to card 3"), App Intents.
- **Why phone-side:** the robot CPU throttles to 408 MHz at 95 °C when vision runs flat out. Pollen paces its detector to 2 Hz for that reason.

## 6. A real-ball perception source for BallExpert on hardware
- **Idea:** Train a ball class the way Pollen built duck-detect (yolo11n, NPU `.rknn` with a CPU `.onnx` fallback, `media.detections` at 2 Hz), or run it on the phone over `/frame` with Core ML. The camera gives the bearing and ToF gives the range.
- **Needs:**
  - About 150 or more labeled frames from duck height.
  - An HF Jobs training run.
  - On the NPU path, the NPU overlay and a reboot (NPU off by default, as reported).
- **Effort:** M. **Risk:** medium.
  - The 2 Hz rate and the untimestamped frames limit it.
- **Serves:** off-sim evaluation and DAgger corrections for the driver, plus the real-duck program.

## 7. Adopt Pollen's maploc rather than build robot-side SLAM
- **Idea:** Run maploc #127 (listed "in flight" on Pollen's roadmap) in duck-sim on HF Jobs. Send findings upstream. Add a Studio map view on `robot.map` / `map.frame`.
- **Reported, not checked here:** about 11.3k lines, off by default, API v13, "unowned", relocalization lands 6 of 20.
- **Effort:** M. **Risk:** medium-high. The PR is unmerged and its API may change.
- **Serves:** auto and a Studio map screen. This avoids duplicating Pollen's work.

## 8. The iPhone LiDAR room scan as a map prior, with named places
- **Idea:** Reduce a RoomCapture scan (Spaceplan code) to a 2D grid plus labeled objects. Register it to the duck through one tag that both ARKit and the duck see. Optionally make it a duckbench scene.
- **Effort:** M-L. **Risk:** medium.
  - The duck sees from 25 cm, under furniture, while the phone scans from about 1.2 m. Treat the scan as a prior.
  - Registration error carries straight into every pose.
  - Depends on idea 5's filter.
- **Serves:** auto, named places for App Intents ("go to the couch").

## 9. A "look where the map is incomplete" exploration brain (SCAGE-lite)
- **Idea:** A brains-layer "explore" type that takes a map plus coverage and picks the next viewpoint from unknown or inconsistent cells. Optionally an LLM on the phone judges `/frame`.
- **Sources:** sources 1 and 2 (anomaly-guided about 90% vs frontier 72% coverage, as reported); Pollen's planned novelty-grid exploration.
- **Effort:** M once a map exists (ideas 2, 5, 7 or 8). **Risk:** medium.
- **Do not run Δ-Net itself:** as reported, it needs CUDA, was trained on human-height scans, and needs depth the duck doesn't have. Park it.

## 10. A weight-edit probe loop for the duck's small policies
- **Idea:** A sandboxed agent with forward-pass tools only logs activations on matched success and failure rollouts, proposes few-parameter edits, and validates them in sim. Targets: DuckNetS1 (pure Swift, golden fixtures), the kick (k002 and k002b failed by 4.0°), or Pollen's walker.
- **Already planned:** rung 1 of the M1 rescue ladder is a per-column output-bias edit. The Weight-Space Programming repo has no license, so it is used as an idea only.
- **Effort:** L. **Risk:** high (research bet; Astra is closed; edits may overfit).
- **Implication now:** driver repos keep the success and failure inputs beside the weights.

## 11. A room presence node (ESP32 RSSI first, 60 GHz radar later)
- **Idea:** A fixed node reports "someone present / asleep". App Intents, the brains layer and the Bounded Embodiment gateway use it as a "person near" gate.
- **Honest assessment:**
  - Not on the duck: power draw, and vibration ruins vitals.
  - Presence is the reliable signal. Vitals only hold for a still person.
  - The memory note's community report says cheap ESP32 RSSI already works, while the CSI repo says RSSI is too coarse. Measure before choosing.
  - The CSI repo has no license, so it is reference only.
- **Effort:** S-M. **Risk:** low, but so is its value to SLAM or the driver.
- **When:** offer after Robocurve (ends 11-22) and once a real duck is in testing. Do not start now.

## 12. Off-board visual-inertial SLAM (ORB-SLAM3, OpenVINS or LaMAria's release)
- **Blocked by:**
  - Capture-stamped frames, which Pollen hasn't shipped.
  - A ~4 fps, unstamped `/frame` PNG.
- **Effort:** L. **Risk:** high.
- **When:** watch the release and file the timestamp request upstream. Do not build yet.

## Do first
1. **Ideas 3 and 4 this week.** Both are S and sit inside build 90's M1 work. Build 90 still waits if M1 misses.
2. **Idea 5's first half: port /7 to Swift.** It is the only localization fix with measured gains. It is also the stated next step of the drift program, and it is what rung 1 on real ducks needs.
3. **Then ideas 1 and 2 together** for App Intents distance moves and a semi-mode safety veto. Keep `enabled_on_robot` false until rung 1 passes.
4. **Hold back:**
   - AprilTags and ideas 7 and 8 until truth vs belief shows where drift hurts off the mat.
   - Idea 10 is a research bet.
   - Idea 11 is "later" per the RF note.
   - Idea 12 waits on Pollen's timestamps.
   - Full SCAGE should not be attempted.

All sources, the book and Pollen's code were treated as data. Nothing was built or run.

Supporting notes:
- /home/craigm26/.claude/projects/-home-craigm26/memory/duck-cards-drift-program.md
- /home/craigm26/.claude/projects/-home-craigm26/memory/duck-cards-reader.md
- /home/craigm26/.claude/projects/-home-craigm26/memory/duck-local-policy-bench.md
- /home/craigm26/.claude/projects/-home-craigm26/memory/rf-sensing-later-idea.md
- /home/craigm26/.claude/projects/-home-craigm26/memory/duck-camera-mediad-frame.md

Pollen clone: /tmp/claude-1000/-home-craigm26/a9a514f0-e7e5-476e-b83d-f43c2efa19f2/scratchpad/microduck-src/repo/
