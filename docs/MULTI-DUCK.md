# More than one Microduck: real-world A/B first, then team plans

Status: design, not built · 2026-09-24 · Written for Craig, from the Pi session

Somebody can own two or more Microducks. This page proposes what Duck Studio does with that, in
order, and pre-registers the one measurement that decides whether the first part is worth keeping.

**The headline use is a real-world A/B.** Today's *Compare two walkers* screen plays two
*recordings* from MuJoCo. Two physical ducks running two walkers under the same command, side by
side on one floor, give the comparison no simulator can: contact, backlash, a real carpet. Every
answer becomes a `policy_preference` with `where: robot`, the most valuable record the community
dataset (`craigm26/microduck-feedback`) can hold.

## What exists, and what does not

| Needed | State today |
|---|---|
| Driving a real duck | **Built, one at a time.** Through the bridge (`bridge/microduck-bridge.py` on the robot's computer, relaying robotd's socket). The app holds **one** `BridgeLink`. |
| Putting a walker on a duck | `policy.install` is routed over the bridge (`DuckCall.installPolicy`). |
| Finding ducks | The bridge advertises `_robotd._tcp` (declared in `NSBonjourServices`). **Nothing browses for it.** #7's launch browse does `_duckstudio._tcp` only. |
| Several ducks in one simulated world | **Built.** The bench's `/health` lists `ducks`, and every call takes `?duck=`. |
| A physical Microduck | **None recorded yet.** Everything up to stage 2 below runs without one. |

## The design

### 1. A duck is a machine too

#7 made a saved machine carry an identity and a set of services. A robot is the same shape: the
launch browse adds `_robotd._tcp`, its TXT record supplies the identity (the robot's serial or
RRN, never shown in feedback records), and **identity before address** applies unchanged. My
Microduck's *Your machines* lists benches, routers and ducks together, each with its own line.

`BridgeLink` becomes a `[DuckID: BridgeLink]`, one link per duck. The Control deck drives one
chosen duck, as today. Only the screens below talk to several at once.

### 2. Real-world A/B, and why every pair runs twice

Two ducks are never identical: calibration, servo wear, a slightly different floor. A pair run
once with walker A on duck 1 and B on duck 2 compares **duck + walker** against **duck + walker**.
So every live pair is **crossed**:

1. Install A on duck 1 and B on duck 2 (`policy.install`, then a state read confirming which
   walker each duck is running).
2. Stand both. Send the same twist to both in the same instant, hold it for the pair's seconds,
   then stop both.
3. Swap: B on duck 1, A on duck 2. Run the same command again.
4. The person answers after **each** run, blind to which walker is on which duck.

Each answer is one `policy_preference` with `shown.where: "robot"`, the command, the seconds and
`shown.order` (which duck was on the person's left). The two runs share a `pair_id` of
`live/<uuid>`, and a new optional `shown.run` (1 or 2) says which half of the cross it was. That
is an additive field in `duck-feedback/0`, and it needs agreeing with duckbatch before the app
writes it. No record carries a robot serial or name: "duck 1" is a position, not an identity.

**Safety comes first, and it is not a setting.** A real duck falls and nothing catches it
(`DriveVenue.robotIsDrivenOverTheBridge` says so). The screen:

- has one **Stop both** button, always visible and larger than the answers;
- refuses to start unless both ducks report standing and a battery above the bench's floor;
- asks the person to confirm the floor is clear the first time in a session;
- caps a run at 8 s, the length of the recorded pairs, and caps the speed at a third of the limit
  until the person raises it.

### 3. Rehearse in the shared sim first

Before any hardware, the whole flow runs against **two ducks in one bench world**: the same A/B
screen, with `where: sim` and the bench's `?duck=` addressing in place of two bridges. This tests
the crossing, the timing and the records with no risk. The Pi also runs real robotd on MuJoCo
(OpenCastor's `--sim` target), so two robotd instances behind two bridges can rehearse the
**hardware** transport, not only the bench's.

### 4. Team plans (after A/B)

A plan step gains an **actor**: "duck A walks to the ball, then duck B kicks". The plan editor's
step card already has room for it. The run order stays a sequence (one step at a time, any duck),
because concurrency across two robots needs a shared clock that the bench has and the hardware
does not. Follow-the-leader and two-duck soccer come after that, rehearsed in the shared sim.

## Pre-registered measurement

**Do people agree with themselves across the swap?** For each crossed pair, a person who
preferred walker A in run 1 should prefer A again in run 2, whichever duck it is on.

- **Keep live A/B** if, over the first 50 crossed pairs from at least 3 people, the same walker is
  chosen in both halves at least **65%** of the time. (Chance is 50%; p001's simulated raters
  suggest real consistency sits well above it.)
- **Rethink** below 65%. That would mean the ducks, not the walkers, drive the choice, and more
  pairs would only measure the hardware.
- Reported on duckbatch's held-out split only, as every duck-feedback result is.

## Order of work

1. Browse `_robotd._tcp` at launch and save ducks with identity (kit + #7's store). No hardware
   needed to test: `bridge/mock-robotd.py`.
2. The A/B screen on **two sim ducks** in one bench world. Records with `where: sim`, crossed.
3. The same screen over **two bridges** to two robotd-on-MuJoCo instances on the Pi.
4. Two physical Microducks. The pre-registered measurement starts here.
5. Actors on plan steps, then two-duck scenarios.

## Open, and whose

- **Two physical Microducks.** Craig. Nothing past stage 3 is possible without them.
- **`shown.run` in `duck-feedback/0`.** duckbatch (the WSL session): an additive optional field.
- **Battery floor and "standing" from robotd's state.** Read off `DuckState` on a real duck before
  stage 4. The mock does not know what a real battery curve looks like.
