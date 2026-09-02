# The Lab tab — consolidating the duck apps into one

**THE LAB TAB NO LONGER EXISTS, AND THIS DOCUMENT IS KEPT ANYWAY (2026-09-01).**
The Lab folded into **Studio > Modes** on this date, when the app was
restructured around the robot rather than around the file types it edits. The
five tabs are now My Microduck, Control, Behaviours, Studio and Robot; every
mode described below except the bench is reachable at Studio > Modes, and the
physics bench is reachable at Studio > Measure, as "Run on your network". Nothing was deleted and no mode
changed what it does — only where it is drawn and what the sentence above it
names. `LabCatalogue` keeps its type name; its `preamble` became
`modesPreamble` and stopped naming a tab, because a sentence that names a
container goes false the next time the shell is rearranged.

Two things below are still live and are the reason this file is not archived:
the gate warning in "Three things this must not break", which is *more* true
after a second restructuring, not less; and the open loop at "Order of work"
item 3, which nobody has closed.

Written before any code, in the house pattern. This is the merge plan for
folding the other Microduck apps into Microduck Studio as a fifth tab, **Lab**.
Read it as history from here down.

## Why this is worth doing, stated honestly

There are five duck repositories and **four of them have no code in them.**
Measured 2026-08-30:

| Repo | Swift files | What is actually there |
|---|---|---|
| `duck-studio` | 27 + StudioKit | The shipping app. Build 27 on TestFlight. |
| `duck-sounds` | **0** | Docs — *and* `sim/`, which is real and substantial |
| `duckboard-ios` | **0** | Docs only: 7 markdown files |
| `duck-diary` | **0** | Docs only: 7 markdown files |
| `duckkit` | shared | The kit all of them were going to depend on |

Three apps were planned, gated, given bundle identifiers, and never written.
Each one needs a shell, a settings screen, an icon, a privacy label, a review
cycle and an App Store listing before it can show anybody a single duck. Duck
Studio already has all of that. Consolidation is not a tidy-up; it is the
difference between three apps that do not exist and three screens that could.

**And the sim2real argument is the real one.** Microduck Studio can already inspect a
policy and author a motion, but it cannot run either — an iPhone has no physics.
`duck-sounds/sim/` has physics. Put them in one app and the loop closes: author a
motion, run it in MuJoCo on a machine on your desk, watch what physics did to it,
and then — when hardware exists — send the same thing to a robot. That loop is
the whole point, and today it is split across a shipping app and a directory of
Node scripts in a repository with no app in it.

## What already connects, which is more than it looks

`StudioKit/Sources/StudioKit/DuckBench.swift` **already names
`sim/duckbench.mjs` in duck-sounds** and speaks to it over the LAN.
`RemoteRunView`, `BenchView` and `PipelineView` are already clients of it. The
bench serves eleven endpoints:

```
/health  /state  /ball  /reset  /now  /intent  /stop  /policy  /record  /perform  /measure
```

So "merge the simulator" is mostly **surfacing what is already wired**, not
building it. Two of those endpoints are richer than the app currently admits:

- **`/measure`** runs randomised rollouts — drop height varied over Pollen's own
  0.12–0.13 m range — and answers with a success count against a stated
  criterion ("ends standing, trunk at least 100 mm up"). That is an experiment,
  not a demo, and the criterion travels with the number.
- **`/ball`** places a ball at a bearing and range **computed from the robot's
  own yaw**, in duckvision's convention (positive bearing is left) so a trial
  reads the same way the detector reports. That is the seed of every game
  anybody would want, and it is already correct about the thing games get wrong.

## What the modes hold (written as "the Lab tab holds")

Ordered by how much of it exists, not by how it demos. These are the rows in
`LabCatalogue.modes`, drawn today at Studio > Modes.

### 1. Bench — real, mostly surfacing
The simulator, promoted from a setting to a place. Health, the world, the
policy under test, and `/measure` as a first-class experiment with its
criterion printed beside its number. This is where "run it in physics" stops
being a button on another screen and becomes a room.

### 2. Trials — small new code over an existing endpoint
`/ball` plus `/measure` is a trial harness: place the object, run the policy N
times, report what fraction achieved the criterion. Everything a "game" needs is
here, and framing it as a **trial** rather than a game keeps the app honest —
the number that comes out is a success rate with a stated criterion, which is
exactly what this app already refuses to fake elsewhere.

### 3. Ghost (AR) — new, and the substrate exists
`PLAN.md` M7, unbuilt. `DuckStage` is already a RealityKit `ARView` used as a 3D
renderer, so the renderer, the kinematics and the pose pipeline are done; what is
missing is plane detection, the foot-to-plane anchor and true scale. The
two-ghost diff (T-072, per-site millimetre separation) is the one that earns its
place: authored motion against recorded motion, in the room, at 25 cm.

### 4. Deck — paper, and blocked on hardware anyway
`duckboard-ios`'s six fat buttons and STOP bar. Worth folding in as a screen
rather than an app, but **it cannot be tested without a duck**, and its whole
design is about latency to a real robot. Fold in the plan, build it when
hardware lands.

### 5. Diary — paper, and blocked on a transport nobody has
`duck-diary`'s signed `robot.state` ledger. Its own plan opens with "the
transport problem — read this first": Pollen ships no official TCP or WebSocket
endpoint, and the plan's own fallback is a `socat` page it wants to delete. The
ledger idea is good and the Ed25519 hash chain is the interesting part. It is
also the piece with the least to stand on today.

## Three things this must not break

**1. The gates stop measuring what they were written to measure.**
`GATES.md` pre-registers a KILL at "zero evidence anyone loaded a policy that
was not bundled" and a PASS on ≥100 visits to `/bring-your-own-policy`. Those
numbers are about *one* question: does a practitioner point this at their own
network? A tab full of trials and AR moves the download number without moving
that question, and a mega-app makes the download count uninterpretable. **The
gates must be re-pre-registered before this ships, not after**, or they stop
being a lookup and become an argument. Still open, and now twice over: the Lab
tab shipped without it, and the five-tab restructuring moved the surfaces again.

**2. The app's claim about itself gets harder to keep.**
Microduck Studio's value is that it refuses to overclaim: it says what is measured,
what is assumed, and what is not real. These modes are where overclaiming would be
easiest — a ghost in your room and a duck chasing a ball both *look* like
capability. Every one of these screens needs the same discipline as the rest: the criterion
beside the number, and "this is a simulation" where it is one.

**3. Five tabs is the ceiling.**
iPhone shows five before it collapses the rest into "More". At the time this was
written the five were Policies, Intents, Scenes, Draft and Lab. They are now **My
Microduck, Control, Behaviours, Studio and Robot** — the same ceiling, reached a
different way: Motions, Scenes, Draft and the Lab's modes all fit inside Studio,
which bought room for a tab about the duck you own and a tab about its hardware.
There is still no sixth, so anything else that arrives has to live inside one of
these five.

## Order of work

1. ~~Lab tab shell + Bench moved into it.~~ **Done.**
2. ~~Port the OpenCastor lab.~~ **Done** — see below.
3. **Re-pre-register the gates.** STILL OPEN, and now the most urgent item by a
   wider margin than when this was written: the app that the gates in
   `GATES.md` describe no longer exists, and neither does the app that replaced
   it — `/bring-your-own-policy` is a path under Behaviours now.
4. **Trials over `/ball` + `/measure`.** Small code, real experiment, the first
   thing in the tab that did not exist in either app.
5. **Deck and Diary** stay documented and unbuilt until there is a robot.

## What the port actually moved (2026-08-30)

Eight game models went from `CastorKit` into **StudioKit**, with their tests —
`SoccerEngine`, `Slalom`, `DuckGolf`, `FetchRun`, `BridgeCrossing`, `TrickRun`,
`FlamingoHold`, `FollowMe`. Every one is `import Foundation` only, so they are
duck arithmetic that had been living in a rover's kit: 596 StudioKit tests now,
up from 520.

Fifteen view files came into the app target. There were **no type-name
collisions at all** between the two apps, and `Theme` — OpenCastor's design
system, the thing that looked like the expensive part — turned out to be used
in exactly one duck file.

Seven of the games hang off `GhostDuckView` rather than sitting in the modes list,
which is how OpenCastor arranged them and is right: each one is the same ghost
duck doing something else, so seven rows would be seven doors into one room.

## Ideas, not yet designed

Kept apart from `LabCatalogue` on purpose. That table's `.planned` means
"designed, not written"; these are not designed, and putting them in the table
would be the app claiming more than it has — which is the one thing these modes
are most able to do.

- **Bobsled, rebuilt rather than ported.** OpenCastor's is a rover game wearing a
  duck: it steers a sled, and the thing that makes every other game a *duck* game
  — the 14-degree yaw saturation, the 0.31 m arc a walk cannot beat — has nothing
  to do with it. A real one would be built against the duck's own turn radius.
  This is why the port deliberately left `BobsledView`, `BobsledScene` and
  `CastorKit.BobsledRun` behind.
- **A hamster ball.** Put the duck inside a sphere and let it drive the sphere by
  walking. It is a genuinely different control problem from everything else here:
  the duck's own gait becomes the actuator, the ball's roll is the dynamics, and
  the 14-degree yaw limit that constrains every other game stops mattering in the
  same way — a ball does not have a turn radius, it has momentum. Worth thinking
  about whether the bench can simulate it before any of it is drawn, because if
  MuJoCo can roll the sphere then this is the first mode whose difficulty would
  be *measured* rather than authored.

## What stays in its own repository

`duck-sounds/sim/` — the bench is a Node service that runs on a machine with
physics, and it does not belong in an iOS app bundle. What merges is the
*client*, which is already here. The repository stays; the app that never got
written is what folds in.

## Whole-body step climbing: four rounds, 2026-09-01 to 2026-09-02

**Result.** In simulation only, on the browser simulator's four-step flight, the tallest
step the Microduck can get onto is unreliable at every height. Judged by the `honest`
criterion (upright, within the 340 mm-wide flight, trunk past the riser face and more
than 95 mm above the tread, both feet resting on the tread, scored a second after the
move ends) on a grid of the rise 10 mm either side crossed with three spawn-height and
foot-friction plants, the best open-loop move — a beak-strut vault: beak planted on the
tread, neck locked as a strut, hips extend, the trunk pivots over the head, the feet
land on the tread — clears 2 of 9 cells at 40 mm, 2 of 9 at 50, 4 of 9 at 60, 2 of 9 at
70 and 1 of 9 at 80 (one vector, sha256 4b9110c448ec, scored at three heights), and 0 of
9 at 90 mm or taller, against 9 of 9 for a duck placed on the tread and 0 of 9 for doing
nothing. Ten of the eleven clears are still upright fifty ticks later. Roughly 48,000
searched attempts over four rounds; every claim re-scored from its saved file by an
adversarial audit (duck-sounds `climb/r4_judge-results.json`).

**The instrument was broken first.** The harness's flight is built from 200 mm-tall step
blocks whose top is the tread, so at any rise under 200 mm adjacent blocks interpenetrate
in z. They shipped on the same collision bit, on frictionless slides, and the solver
shoved them apart: up to 20 mm of tread drift inside one control tick. Below about 150 mm
a duck simply standing on the first tread was thrown to the floor within ten ticks. The
first audit's "0 of 54 replays cleared 20–180 mm" measured that staircase, not the robot.
The repair (`site/stairs.js isolateSteps`, commit 279b016) zeroes each step geom's
conaffinity: step-step stops colliding, step-duck, step-wall and step-prop do not change.
Re-baselined, a placed duck passes at 40, 60, 90, 120 and 180 mm where before only 180 did.

**Why the clears are not a climb.** They are isolated points, not a basin: one control
tick (5.66 ms) of shift in the landing takes the 60 mm move from 4 of 9 to 1 of 9 and moves
the trunk 304 mm; a 5 mm change of rise either side of 60 reads no. Every measurable
event that could trigger the landing (beak contact, trunk pitch, trunk height) fires on
the same 0.74 s tick in every plant, so an event carries no information the clock does
not, and the axis that decides the verdict — the rise — is not observable at the event.

**Above 80 mm it is a lift budget.** A standing trunk sits at 116 mm; the criterion needs
185 mm at a 90 mm rise. The beak strut buys 13–21 mm of peak lift; a beak plant plus a
riser foot plus a trailing-leg push buys about 38 mm, where 59 mm is needed at 80, 69 at
90 and 99 at 120. In 69 cells of two-beat attempts the number of feet ever resting on a
tread was zero, and at 120 mm the failure is a geometric stall — upright, motionless,
trunk 4–14 mm below the tread top. Every row saturates the plant's 0.6405 N·m servo
ceiling, so there is no headroom left to spend. The 80–120 mm band is closed on that
measurement; 180 mm produced zero tread contact in 2,829 episodes and is closed.

**Round five closed the 40–80 mm band.** The last lever — a landing servoed onto the tread
from measured trunk state every tick instead of a single throw — was built as an optional
intent field, proved inert on every existing file, and searched over 235 distinct vectors
at 60 mm. Every servoed move cleared 0 of 9 stably; the record stayed at 4 of 9 against a
bar of 7. The law did one new thing: its clears lined up along the plant axis (all three
plants at exactly 60 mm) instead of scattering across rises, and it paid for that with
uprightness through the tail. The finding that matters is why 7 was never reachable: the
criterion needs the trunk 95 mm above the tread, and no launch searched got it there in
more than 5 of 9 cells. Both servoed bests already converted every cell where the height
existed. At 60 mm the binding constraint is lift, not landing, and lift is the saturated
servo. Two caveats travel with the negative: the servo law reads tread height and edge
from the plant, so it is an oracle upper bound and not a move the robot could run (its
policy sees 61 proprioceptive numbers); and every clear passes through the step block by
7–9 mm on the way up, soft contact rather than tunnelling. Roughly 50,000 attempts over
five rounds. What is left is a different actuator or a different move class — a second
duck, a wall, a lever — not more search of this one.

**Instrument lessons, reusable.** Score only saved files, never in-memory candidates
(export rounding moved one "best" 90 mm in x). Put robustness inside the objective, not
in the post-mortem. Hash intents so one vector is never published under three rise
labels. Gate a stability bonus on reaching the flight, or a do-nothing control farms it.
A do-nothing control must fail and a placed duck must pass on the same plant, or the
criterion is not a climbing test. And rig3 standalone prints to stdout only: the log a
workflow agent tee'd is not the log the next run wrote.
