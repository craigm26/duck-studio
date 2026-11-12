# Wander: an Auto skill that walks, keeps clear and greets

Written at duck-studio main `4bb1ee9`, 2026-11-12. A Python reference exists and runs, both as a
public Space and as code. **Nothing has run on a physical duck.** Every number below comes from a
kinematic practice room or the Arena's simulator until a phase here measures it on hardware.

## Goal

Studio gets one Auto skill that needs no model, no key and no camera: the duck walks about on its
own, keeps clear of what is in its way, stops at an edge, and greets something that comes close
with its own emotions (`robot.do curious`, then `yes`). It is the first Auto card that can earn its
row without a provider, and the base other autonomy builds on: room-memory, stuck recovery and edge
stops are what any goal-seeking brain needs underneath it.

It ships only by the brains layer's rules (`brains-layer.md`): through `DuckEnvelopeGate`, behind
StopPath, cancelled by any thumb, never re-arming itself, and offered only with a measured
`EvidenceRow`.

## What exists

| Piece | Where | State |
|---|---|---|
| Brain: Chill, LookAround, Wander, TurnInPlace, Greet, Dance (states from Pollen's `docs/ideas/autonomous_behavior.md`) | `craigm26/duckbatch` `wander/brain.py` | ran closed loop in the Arena's simulator for the Got a Talent act; replays within 3.9 cm |
| Senses: room ahead in a corridor one duck wide, floor set aside by geometry, obstacle points kept 8 s in odometry, a visitor as something that arrives while the duck holds still | `wander/senses.py` | unit-tested; tuned only in the practice room |
| Runner over a JSON-RPC lane: twist every tick, stands still on stale depth or stale state | `wander/runner.py` | 11 tests; 16 three-minute practice sessions with no fall |
| Practice duck: kinematic room, a cat, the 8x8 ToF raycast, the lane's 400-a-minute budget | `wander/practice.py` | the only "duck" it has met |
| Space | `huggingface.co/spaces/craigm26/microduck-wander` | live; drives a duck through Pollen's rendezvous, or the practice duck |

## What the reference already taught us

- **The rendezvous lane cannot carry it.** The robot forwards at most 400 notifications a minute on a
  control lane (`mediad/src/relay.rs`, a fixed window), and `tof.stream` sends 15 frames a second
  with no rate setting. Through the Space the duck sees for about 25 s and is blind for the rest of
  each minute, so it walks about half the time. Studio's own link has no such budget. **Wander runs
  on the phone over the local link, not in the cloud.**
- **The sensor sees 45 degrees.** Furniture beside the duck leaves the view while it is still beside
  it; weaving past a corner is how the practice duck first fell. Obstacle memory in odometry fixed it.
- **The Arena's walker needed forward speed to turn; a robot's walk does not.** Turning in place with
  forward speed clips corners. TurnInPlace sends zero `vx`.
- **A sweeping head cannot tell an arrival from its own turn.** LookAround now holds each glance.
- **Not knowing is not fine.** Codex found that a stale `fallen: true` read as recovered (duckbatch
  #23). No fresh `robot.state` now holds the duck still.
- **Open, and the most important: edges.** The senses set the floor aside but do not yet notice the
  floor *missing*. On a table the duck would walk off. Phase W0 closes this before anything else.

## Phases

### W0: no duck needed (kit work, Linux-tested)

1. **Edge stop.** The bottom rows' floor return jumping far or vanishing means an edge ahead: stop,
   back off, turn away. A table and a stair in the practice room; a test per case. Gate: no
   practice session or BrainBench run ever crosses an edge.
2. **Stuck recovery.** Twist commanded, odometry not moving for 1.5 s: back off and turn.
3. **Session log.** One JSONL line per tick: senses, brain state, the twist and head sent, gate
   verdict, and the raw depth frame. Same schema from the Space, the practice duck, duck-sim and a
   real duck, so every run is a replay fixture.
4. **BrainBench task W1, wander.** Run on duckbench against duck-sim robotd with `tofd --sim`, never
   on the Pi. Five fixed rooms (open floor, chair legs, corridor, a table top, a visitor walking up),
   ten seeded starts each, three minutes each. Measured per run:
   - edge crossings and falls (must be zero)
   - contacts per hour
   - share of time moving, and area covered
   - stuck events and recoveries
   - greeting precision (visitors greeted / greetings) and recall
   - gate cuts
   Baselines on the same table: do-nothing (zero contacts, zero coverage) and a straight-line walker
   (coverage, and the contacts that come with it). Wander has to cover ground *and* keep contacts at
   or near do-nothing's.
5. **Golden traces.** The Python reference writes senses to command traces for every W1 run; these
   become the conformance fixtures for the Swift port.

### W1: measured on a real duck (Craig's, or a tester's)

Nothing in W2 ships on a real duck until this exists. The measurement can be ours or someone
else's; the protocol is the same, so a tester's run counts.

**The tester protocol** (one page, linked from the Space and the Discord ask):

1. Clear a patch of floor, about 2 m by 2 m, away from stairs and table edges. Stay in the room.
2. In the Space: sign in, find your duck, connect, tick "record this session", top speed 0.12.
3. Five sessions of three minutes: open floor; two chairs in the patch; along a wall; with a person
   walking up twice; on a rug or dark floor.
4. The Space uploads each log to a dataset in *your* account (private by default); you share the
   link. Depth frames are 8x8 distances, not pictures, and the card says so.
5. Note anything the log cannot show: a bump, a near-miss, a greeting that looked wrong.

From those logs, retune against reality, not the practice room:
- head height and pitch for the floor geometry
- the speed the walking policy actually reaches at 0.12 m/s
- odometry drift over 8 s of memory
- false visitors

Then W1's numbers become the first real-duck `EvidenceRow` for wander.

### W2: Wander in Studio (Swift)

- `DuckWander` (pure state machine), `WanderSenses` and `WanderRunner` in StudioKit, Linux-tested,
  with the W0 golden traces as conformance tests: the Swift and Python versions must produce the
  same commands from the same senses, or bridge motion is off (the brains layer's drift rule).
- Depth over Studio's link: a bridge relay of `tof.stream` (`/run/tofd/tof.sock`), which today
  Studio does not reach. That is a bridge change and its own PR.
- The runner sends through `DuckEnvelopeGate`; StopPath, the stop latch and "You took over" apply
  unchanged.
- An Auto card, "Wander", with its number, on the practice duck and a real one, exactly as Walk to
  the ball is in Tell.

### W3: Presets and knobs

- **Knobs:** top speed, roam radius from the start, sociability (greet or not, dance or not),
  curiosity (how long it looks before walking).
- **Presets, each its own BrainBench row before it gets a card:**
  - **Explore:** walks toward floor the memory has not covered yet.
  - **Patrol:** a loop.
  - **Nap spot:** goes back to where it started.
  - **Companion:** keeps a person in view. It needs the camera and the camera-consent sheet, so it
    is the last preset.
  - **Social:** ducks recognised by a stable id, Bluetooth beacon or otherwise, so "we have met"
    is real rather than guessed.

### W4: Upstream, as a complement to Pollen

- Issue: a `hz` on `tof.stream`, as `robot.subscribe` has, with the Space's session logs as the
  evidence. It makes every remote client better and costs Pollen one parameter.
- Proposal: a way for an app to claim "a brain is driving", so the pad, a Space and Studio do not
  fight over the last-writer-wins twist.
- Later, once W1's numbers hold, offer wander as an on-robot skill (`robot.do wander`).

## Offer bar (proposed)

- **Every scenario:** zero edge crossings and zero falls in W1 BrainBench.
- **Contacts:** at most 1 per hour across the suite.
- **Coverage:** at least 60 % of the straight-line walker's.
- **Greetings:** precision at least 0.8.
- **Card:** pinned to the wander version and date, as every row is.
- **Real duck:** the same bars on W1's five tester sessions before the card turns on.

## Risks and kill criteria

| Risk | Signal | Change |
|---|---|---|
| Edge detection misses a real edge | any W1 crossing, sim or real | wander is off on real ducks until fixed; tester protocol keeps floors only |
| Floor geometry differs per duck | false edges or false obstacles in tester logs | calibrate head height at start, from the first frames on known floor |
| Odometry drift poisons memory | phantom obstacles in logs | shorten memory, or forget points the sensor no longer confirms |
| The real walk is slower or sloppier than the practice duck | coverage far below sim | tune on W1 logs; never raise the speed cap to compensate |
| No one tests on hardware | no W1 logs after the Discord ask | it stays a practice-duck card and a Space; W2 waits |

## Open questions for Craig

1. Is the offer bar above right, or should Auto's bar be higher for an unattended skill?
2. Session logs from testers: dataset in their account and shared by link (proposed), or a shared
   community dataset they push to?
3. Should edge stop also refuse to start when the first frames show no floor (a duck placed on a
   table)?
