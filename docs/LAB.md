# The Lab tab — consolidating the duck apps into one

Written before any code, in the house pattern. This is the merge plan for
folding the other Microduck apps into Duck Studio as a fifth tab, **Lab**.

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

**And the sim2real argument is the real one.** Duck Studio can already inspect a
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

## What the Lab tab holds

Ordered by how much of it exists, not by how it demos.

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
`duckboard-ios`'s six fat buttons and STOP bar. Worth folding in as a Lab screen
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
gates must be re-pre-registered before the Lab tab ships, not after**, or they
stop being a lookup and become an argument.

**2. The app's claim about itself gets harder to keep.**
Duck Studio's value is that it refuses to overclaim: it says what is measured,
what is assumed, and what is not real. A Lab tab is where overclaiming would be
easiest — a ghost in your room and a duck chasing a ball both *look* like
capability. Every Lab screen needs the same discipline as the rest: the criterion
beside the number, and "this is a simulation" where it is one.

**3. Five tabs is the ceiling.**
iPhone shows five before it collapses the rest into "More". Policies, Intents,
Scenes, Draft, Lab is exactly five. There is no sixth, so anything else that
arrives has to live inside one of them.

## Order of work

1. **Re-pre-register the gates.** Cheapest, and it gates everything else.
2. **Lab tab shell + Bench moved into it.** No new capability; proves the shape.
3. **Trials over `/ball` + `/measure`.** Small code, real experiment, the first
   thing in the tab that did not exist before.
4. **Ghost (AR).** The largest new surface, and the one worth a milestone of its
   own.
5. **Deck and Diary as documented, unbuilt screens** — visible in the plan, absent
   from the binary, in the pattern `README.md`'s "Not built yet" already uses.

## What stays in its own repository

`duck-sounds/sim/` — the bench is a Node service that runs on a machine with
physics, and it does not belong in an iOS app bundle. What merges is the
*client*, which is already here. The repository stays; the app that never got
written is what folds in.
