# Proposal to Pollen: move by distance, turn by angle, inside robotd

DRAFT, NOT FILED. Written 2026-10-15 for pollen-robotics/microduck. The "Data" section is empty
on purpose: it is filled from the duck-sim results (docs/PACKS.md, "Acceptance", rung 1) before
anything is sent.

## The ask

Two discrete intents in robotd, closed on robotd's own 50 Hz contact odometry and IMU yaw:

- `robot.walkBy`: walk a signed distance along the heading the robot has when the request
  arrives, holding that heading.
- `robot.turnBy`: turn in place by a signed angle.

Each is answered at once (accepted, or refused with a reason, like every discrete intent), runs
inside the control loop, reports its progress in `robot.state`, and ends in a zero twist with a
reason: reached, out of time, fell, stopped, or preempted.

## Why it belongs in robotd and not in a client

Microduck Studio and the Duck Cards reader both close Walk and Turn cards on `robot.state`'s
`odom` today (`DuckCardLoop` in Studio, `cardloop.py` on the duck: one spec, one set of test
vectors). It works in a simulator. It is the wrong place for it, for reasons that are all about
where the loop runs:

1. **The loop runs at the client's rate, over a socket.** The client sees `robot.state` at its
   subscription rate (Studio subscribes at 10 Hz, the reader at 20) and answers with
   `robot.move` at 20 Hz. robotd's estimator runs at 50 Hz. Every decision is made on a pose one
   to five control ticks old, and the stop lands one more tick after that. In duckbench, closing
   on a 10 Hz state ended rows about a centimetre further off than 50 Hz.
2. **Staleness has to be guessed.** `robot.state` carries no timestamp, so a client stamps
   frames on arrival and treats a gap as "stopped reporting". Over Wi-Fi and the bridge, jitter
   sits inside every duration it computes. robotd knows exactly how old its own estimate is.
3. **The deadman fights the loop.** `robot.move` expires, correctly. A client loop that stalls
   (a phone backgrounded, a GC pause, the bridge reconnecting) is stopped by the deadman
   mid-card, and the client cannot tell a deadman stop from a slow duck. A goal inside robotd
   has no deadman to race: it owns its own timeout and says which one ended it.
4. **Policy switches are invisible to the client.** robotd swaps policies (walk, standing,
   skills, sit) and stands the duck between commands. A client walking "until 30 cm" cannot see
   that the standing policy took over at a low twist, or that a skill holds the robot, except by
   inference. robotd can refuse a goal while a skill holds the robot, and end one when the
   policy changes, with the reason.
5. **Every client would write it again.** The pad, Studio, the card reader, a classroom web page:
   each would carry its own controller, gains and stop rules, each tested against nothing on the
   robot. One in robotd is tested once, against the robot it runs on.

## Proposed API, in duck-ipc-proto's style

Discrete, so requests, answered with `IntentResult`. Units and frame as `MoveParams`: metres,
radians, trunk frame, `x` forward, `y` left, positive yaw turns left.

```rust
/// Walk a signed distance along the heading held when the request arrived. Discrete; send as a
/// request. Answered at once; progress is `robot.state`'s `goal` block; it ends in a zero twist.
pub const ROBOT_WALK_BY: &str = "robot.walkBy";
/// Turn in place by a signed angle. Discrete; send as a request. As `robot.walkBy`.
pub const ROBOT_TURN_BY: &str = "robot.turnBy";

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalkByParams {
    /// Metres along the start heading; negative walks backward.
    pub distance: f64,
    /// Walking speed, m/s, positive. Clamped to `[pad_drive]`'s vx bound for the direction.
    pub speed: f64,
    /// Give up after this long. Default: robotd's own, from distance and speed.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timeout_s: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TurnByParams {
    /// Radians, positive turns left.
    pub angle: f64,
    /// Turn rate, rad/s, positive. Clamped to `[pad_drive]`'s vyaw bound.
    pub rate: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timeout_s: Option<f64>,
}

/// In `robot.state` while a goal runs and for one frame after it ends; absent otherwise, and
/// absent from a robotd predating it (the rule `odom` set).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GoalState {
    /// "walkBy" or "turnBy".
    pub kind: String,
    /// The request's distance (m) or angle (rad).
    pub target: f64,
    /// How much is left, same units, from robotd's own estimate.
    pub remaining: f64,
    pub elapsed_s: f64,
    /// "running", "reached", "timedOut", "fell", "stopped" (robot.stop), "preempted" (a
    /// robot.move, robot.do or another goal), "lost" (the estimator went invalid).
    pub status: String,
}
```

Refusals, as `IntentResult { accepted: false, reason }`: no policy driving, a skill holding the
robot, the robot fallen, an estimator not ready, a non-finite or zero target.

Ordering, as everything else in the command slot: last writer wins. A `robot.move` during a goal
preempts it (the pad always wins); `robot.stop` ends it with `stopped`.

## Safety envelope

- **Speeds** are clamped to `[pad_drive]` (`PadDriveParams`, today vx -0.4 to 0.4, vyaw -1.0 to
  1.0), the range the v8 velstand "follows well on the robot". A goal never asks the policy for
  more than the pad can. Clients already hold themselves to it (Studio's `pollen-pad-drive.json`
  is that `Default`, cited by commit), but robotd does not clamp `robot.move`, and a goal is a
  good place to start.
- **Distance and angle** are bounded per request (proposal: 2 m, one full turn), so a typo is
  not a walk across the room.
- **Every exit is a zero twist with a reason**, and the reason is in the `goal` block a client
  already reads. The existing guards (deadman for `robot.move`, non-finite, travel, fall) stay
  as they are; a fall ends a goal with `fell`.
- **No silent fallback.** If the estimator is not valid, the request is refused; it never
  degrades to a timed walk.

## What it replaces on our side

Studio's `DuckCardLoop` and the reader's `cardloop.py` become a call and a wait. The card spec
keeps only the per-card speeds and the board's square. Studio keeps its off switch until this
API's results pass the same Acceptance bar a client loop is held to.

## Data

Filled 2026-10-15 from duck-studio's `cardreader/sim/results/` (RESULTS.md has every interval):
Pollen's robotd (`d7560ef`) and the v8 velstand in duck-sim's MuJoCo body, the client loop
(`duck-card-loop/1`) closing Walk and Turn cards on robotd's `odom`, MuJoCo's trunk as truth.
The pre-registered rows only (seven duckbench rows and Measure my duck's five), each row from a
standing duck at a random moment of its sway; 30 cm squares. Errors are median / 95th
percentile over the rows that finished; a row that ended early counts against both shares.

| condition | client state rate | rows | position within 10 cm | position error | heading within 15 degrees | heading error | falls (Wilson upper) | Walk card p95 | Turn card p95 | rows ended early |
|---|---|---|---|---|---|---|---|---|---|---|
| nominal | 50 Hz (every tick robotd sends) | 200 | 99.5% | 2.3 / 4.4 cm | 99.5% | 2.4 / 9.6 deg | 0 (1.88%) | 3.22 s | 2.71 s | 1 |
| nominal | 20 Hz (the card reader) | 455 | 98.7% | 2.3 / 4.7 cm | 98.7% | 2.5 / 9.8 deg | 0 (0.84%) | 3.22 s | 2.76 s | 6 |
| nominal | 10 Hz (Studio) | 200 | 99.0% | 2.5 / 5.2 cm | 99.0% | 2.3 / 10.1 deg | 0 (1.88%) | 3.27 s | 2.78 s | 2 |
| randomized | 20 Hz | 455 | 96.9% | 3.5 / 8.0 cm | 96.7% | 3.9 / 12.3 deg | 0 (0.84%) | 3.31 s | 2.61 s | 7 |
| randomized | 10 Hz | 455 | 97.1% | 3.4 / 7.5 cm | 96.9% | 3.8 / 12.1 deg | 0 (0.84%) | 3.37 s | 2.63 s | 8 |
| stressed | 10 Hz | 455 | 86.8% | 5.3 / 11.2 cm | 87.3% | 6.3 / 16.5 deg | 0 (0.84%) | 3.32 s | 3.52 s | 26 |

Randomized: floor friction x 0.5 to 1.2, mass x 0.95 to 1.05, IMU heading bias up to 5 degrees
and drift up to 0.5 degrees a second, state latency up to 0.15 s, odometry noise and a 5% scale
error. Stressed: all at their far ends together. The state rates are what robotd delivered for
`hz` 50, 20 and 10 (40, 16.7 and 9.2 frames a second; see below).

What it says about where the loop should run:

- **The client's state rate costs little at nominal** (p95 position 4.4 cm at 50 Hz, 4.7 at 20,
  5.2 at 10). What costs is everything a client cannot see: latency it cannot measure, a floor
  that changes the coast, odometry drift. A loop in robotd sees the first two at 50 Hz with no
  socket in between.
- **Every row but one that ended early ended at a Turn card that could not be trimmed into tolerance**
  (trimmed out), most in the stressed condition. In place, v8 velstand coasts 6 to 17 degrees
  after a zero twist at 1.0 rad/s (20 to 31 on a slippery floor with a late state), and a short
  corrective twist turns the trunk, which springs back, instead of the feet. The client now
  measures the coast and leads by it (`approach_deg`, `lead_deg` in the spec); robotd could
  instead slew the command down near the target, which a client cannot do through a deadman
  and a 20 Hz socket.
- **The dead band is the other thing a client has to know** (stands still up to 0.20 m/s
  forward, -0.30 back, 0.5 to 0.6 rad/s turning in place; `cardreader/sim/sysid/`). A
  `walkBy`/`turnBy` that owns its speed can never be asked for a speed the gait will not take.
- **robotd's `robot.subscribe` decimation drops ticks** (40 frames a second for `hz` 50, 16.7
  for 20, 9.2 for 10), which is one more reason the loop belongs on the robot.
- **Walk back, judged on its own** (403 rows each): within 10 cm in 99.3% nominal, 96.8%
  randomized at 20 Hz, but 92.8% at 10 Hz and 79.9% stressed: it coasts 3 to 4 cm, more with a
  late state, and the client stops it on a pose that is already old. A `walkBy` stopping on
  robotd's own estimate would not be late.
- No falls in 4,128 rows across all conditions (13,826 Walk and 6,558 Turn cards). Of the 148
  rows that ended early, 147 were Turn cards that trimmed out and one a Walk back that did not
  start backing in 2 s on the slippery floor.
