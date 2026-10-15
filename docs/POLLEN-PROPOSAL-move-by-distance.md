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

To be filled from the duck-sim run before this is sent: rows per condition, end position and
heading errors (median, 95th percentile, the share inside a third of a square and 15 degrees),
falls with their Wilson bound, per-card times, and the same client loop at 10 Hz and 20 Hz
against robotd's 50 Hz estimate, so the case for moving the loop into robotd is measured rather
than argued.

| condition | rows | position within 10 cm | heading within 15 degrees | falls (Wilson upper) | Walk card time p95 | Turn card time p95 |
|---|---|---|---|---|---|---|
| (pending) | | | | | | |
