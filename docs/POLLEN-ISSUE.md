*Craig posts this, not the tool that drafted it. Nothing below is sent by any
automation: it is a comment for a person to read, edit and paste under
[pollen-robotics/microduck#107](https://github.com/pollen-robotics/microduck/issues/107)
himself, or to decide not to.*

---

# The phone spike, built and ready, from an owner outside the project

WHY THIS COMMENT EXISTS. #107 says the app needs a phone spike before its first
line, and M6 in `docs/project/roadmap.md` names the same thing as the blocker:
"scan, connect, `hello`, authenticate, `system.info` with `--require-pairing`
on, on a real iPhone and a real Android — because §5.5 is currently a fact about
CoreBluetooth on a laptop." I have built the iPhone half of that. It is written,
tested and shipped in an app that is on TestFlight today. **It has never been
run against a duck, because I do not have one.**

So this is not a result. It is a harness, an offer, and a question about whether
you want it.

## Who I am, and who I am not

**Microduck Studio is an independent project. It is not made by, endorsed by, or
affiliated with Pollen Robotics. Microduck is their robot; this is an
independent owner's app for it.**

I say that first because everything after it looks like the opposite. The app
harmonises with Microduck's palette, transcribes `gatt.rs`'s UUIDs verbatim,
speaks `framing.rs`'s NDJSON, quotes `app-path-design.md` in its own source
comments, and is now filing something in your issue tracker. Any one of those
would let a stranger assume you made it. You did not, you have not seen it, and
you are not answerable for anything in it. If it is wrong, that is mine.

That sentence is not only in this comment. It ships in the app as a tested
string — `Provenance.swift` in its kit, with a shorter form for a screen footer,
and a test that fails if any of the three denials goes missing. It is written
that way because the claim previously lived in a source comment and nowhere
else, which is the same as not making it.

## What the app is

An iPhone app for somebody who owns a Microduck: a policy library, a bench for
measuring gaits, a drive pad, some teaching screens. Most of it talks to a
simulator, not to hardware.

One screen in it does not: a Bluetooth screen that runs your handshake — scan,
connect, discover, read the API version, subscribe, `hello`,
`system.authenticate`, `system.info` — against a real robot and produces a
plain-text report to paste somewhere. That screen is the spike. It drives
nothing and it will not: the BLE surface is the documented subset —
provisioning, status, update trigger and progress — and payloads never cross it.

The protocol logic lives in a UI-free Swift package where the tests run on
Linux; the view chooses icons and nothing else. Every UUID, byte layout and step
order was transcribed from `btd`'s own source rather than from a summary of it,
because BLE constants copied out of a web mirror are how an app ships a scanner
that finds nothing. `gatt.rs` asks that a grep for a UUID find its comment; this
is the other end of that grep.

## The eight steps, their budgets, and what each one establishes

Every budget below is a deliberate number, and the report prints the reason for
each one alongside the result, so a reader can judge whether a reported hang was
really a hang. The sentences are quoted from the harness itself — they are what
it prints, not a gloss written for this comment.

| # | Step | Budget | What reaching it establishes |
|---|------|--------|------------------------------|
| 1 | Scan | 40 s | "That this iPhone can see this robot at all. The scan is given no service filter — CoreBluetooth honours one strictly and a bonded peripheral often advertises an empty service list — so every device in range is reported to the app and ranked here in software, by the three tiers in `DuckLink.Tier`." |
| 2 | Connect | 15 s | "That a link opens — which needs no encryption, and so proves nothing yet about pairing." |
| 3 | Discover the RPC characteristic | 10 s | "That the one characteristic carrying read, write and notify is present on the service this app was written against." |
| 4 | **Read the API version** | **60 s** | "**THE ONE THAT MATTERS**: that an authenticated encrypted link can be established between an iPhone and a robot serving `encrypt_read`, which is the fact §5.5 is missing." |
| 5 | Subscribe for answers | 10 s | "That answers can arrive, on the same characteristic the requests leave on." |
| 6 | `hello` | 15 s | "That NDJSON JSON-RPC crosses a bonded link and the robot names its own API version back." |
| 7 | `system.authenticate` | 15 s | "That the PIN method works over the same link — the step that has to work before a PIN is worth having." |
| 8 | `system.info` | 15 s | "That an authenticated call comes back with the robot's own name, SoC serial and uptime — all three of which this report prints — which is the end of the sequence the roadmap asks for." |

Two of those budgets are worth defending here.

**Scan, 40 s.** Because §3.4 measured the longest advertising silence on the old
1.28 s default at 31 s, with 9, 14 and 17 also seen. Current firmware advertises
every 100–150 ms and will never need it, but a shorter budget would report "no
duck" for a duck that was there on an older release.

**Read, 60 s, deliberately the largest.** On a Mac this read never returns, so a
short timeout would report a hang the robot might simply have been slow to
answer. This step also has a human in it: somebody has to notice the iOS pairing
sheet, read it and tap Pair, possibly after unlocking the phone first. A minute
is far longer than any of that needs, and still finite.

The read is step 4 and the reason for the other seven. `gatt.rs` is explicit
that it requires an authenticated encrypted link and so is what makes a central
pair before it writes — everything before it exists to get it issued, and
everything after it exists to show that a bonded link then carries the traffic
an app would actually need.

## Four endings, because "failed" would make the whole thing worthless

This is the design decision the harness turns on, and it comes straight out of
§5.5: **the symptom is a hang, not an error.** "CoreBluetooth issues the Read
Request, BlueZ refuses it for insufficient encryption, and nothing resolves it —
no prompt, no error, no retry."

A harness that reported "step 4 failed" would collapse the two answers this
spike exists to tell apart. So every step carries a hard timeout and ends in
exactly one of four states, kept apart in words in the report:

- **ok** — it worked, in this many seconds.
- **REFUSED** — the platform or the robot said no, in this many seconds, *in
  these words*. Somebody can be shown this.
- **TIMED OUT** — "the budget ran out with nothing coming back at all: no
  answer, no error, no callback. This is the macOS §5.5 symptom, and it is
  indistinguishable, from inside a client, from a robot that is switched off."
  Nobody can be shown a silence.
- **not reached** — "an earlier step stopped the run before this one was
  attempted. Not a failure of this step and never reported as one."

Failing at a different step means a different thing, so the report prints a
different sentence under each. At the read: *"The §5.5 question, answered. A
TIMEOUT here reproduces the macOS hang on iOS; a REFUSAL means iOS surfaced an
error where macOS surfaced silence, and those two want different next moves."*
At `system.authenticate`: *"Either the PIN is wrong or the robot predates API
version 4, which is a robot-age answer and not a pairing answer"* — and because
the read four steps earlier printed the robot's API version at the top of the
same report, the run resolves that ambiguity itself rather than leaving it to
the reader.

The run **does not stop at the hung read.** It carries on, so a robot that
answers late or answers only some calls is still described. But every step after
an unfinished read is then reported with one sentence and only that sentence:

> "Downstream of a read that did not complete, so this says nothing on its own.
> The sentence this step would normally earn presupposes a bond proven by the
> read, and no such thing was proven here. The run carries on past the read on
> purpose — so that a robot which answers late, or answers only some calls, is
> still described — and in the §5.5 outcome every step after the read is
> expected to end this way. The finding is the read, above."

There is also no encouraging reading available for a run that established
nothing. A run stopped at connect, or a read served with `--require-pairing`
off, reads as "this establishes nothing about §5.5" and says why. The flag is
the experimental condition, so it is checked in every branch: a read that hangs
with the flag **off** is reported as *not* §5.5's hang, because with the flag
off `btd` serves that read unencrypted and the operation §5.5 is about never
happened.

## What a run looks like

Neither of the two blocks below is a measurement. Both were rendered by
`scripts/print_spike_report.swift`, a small `swiftc` driver that feeds obviously
fake fixtures — serial `SYNTHETIC-0000`, name `example-duck`, an IP in RFC 5737's
documentation range, a phone model that is not a phone — through the same public
`Run` initialiser the app uses. They are here so you can see the shape of the
deliverable before deciding whether you want it.

<details>
<summary><b>SYNTHESISED report 1 of 2 — what §5.5's hang would look like on iOS (not a measurement)</b></summary>

```text
##############################################################################
# SYNTHESISED — NOTHING HERE HAS MET A DUCK.
# Report 1 of 2 — what §5.5's hang would look like, reproduced on iOS.
# Fixture values throughout: serial SYNTHETIC-0000, name example-duck,
# a phone model that is not a phone. Not a measurement of anything.
##############################################################################

Microduck phone pairing spike — app-path-design.md §5.5
=======================================================

This is not a feature. It runs one experiment that Pollen Robotics' own roadmap says is blocking their phone app: scan, connect, read, hello, authenticate and system.info against a real robot with --require-pairing on, from a real iPhone. §5.5 of their app-path design records the encrypted read HANGING on macOS — no prompt, no error, no retry — and says that flag has to be flipped and defaulted on before a duck is handed to anyone. Nobody has yet run it on a phone.

Both answers are worth having. If the read completes, the flag can default on and their blocker clears. If it hangs here too, that is strong evidence the cause is an absent bond rather than the platform — which is the more useful finding of the two. A step that times out is a result, not a mistake: do not retry it quietly, report it.

Setup
-----
Run started: 2026-01-01T00:00:00Z
Run count: this is run 1 from this phone against this peripheral. The count is kept against the identifier iOS gives the peripheral, which survives a rename and does not survive a change of Bluetooth address — so a duck that changed address starts again at 1.
Phone: SYNTHETIC-PHONE (no device ran this), iOS 0.0 (SYNTHETIC)
Robot: btd started with --require-pairing ON — as answered by whoever launched it. Nothing in the advertisement, the GATT table or the RPC surface says which way, so this line is a person's answer and not a measurement.
iOS pairing prompt: shown
PIN never put on the wire — system.authenticate ended before its write was confirmed. It would have used 000000 — the factory PIN, published in Pollen's own repository, which is exactly why §5.5 calls a robot with the flag off "readable by a bystander". Printing it here leaks nothing.
Robot API version: unknown — the read never returned one
Service 6F5D2A10-3B47-4C8E-9A1F-2D7E8C4B6019, characteristic 6F5D2A11-3B47-4C8E-9A1F-2D7E8C4B6019

What the scan saw
-----------------
Tested: example-duck, -54 dBm — advertises the robot's service UUID
Also heard in the same window:
  - example-duckling, -88 dBm — a duck-ish name and nothing else
This is a list of CANDIDATES, not a census of the room: the scan is given no service filter, and a device matching none of the three tiers is never recorded. "Serves our characteristic" is the only authoritative identity test and it is knowable solely after connecting.

Steps
-----
1. Scan [budget 40.00 s]: ok — 2.41 s
2. Connect [budget 15.00 s]: ok — 0.88 s
3. Discover the RPC characteristic [budget 10.00 s]: ok — 0.31 s
4. Read the API version [budget 60.00 s]: TIMED OUT after 60.00 s — no answer and no error
   The §5.5 question, answered. A TIMEOUT here reproduces the macOS hang on iOS; a REFUSAL means iOS surfaced an error where macOS surfaced silence, and those two want different next moves.
   Budget: 60 s, deliberately the largest budget here, and it is the point of the exercise. On a Mac this read NEVER returns, so a short timeout would report a hang the robot might simply have been slow to answer — and this step has a human in it: somebody has to notice the iOS pairing prompt, read it and tap Pair, possibly after unlocking the phone. A minute is far longer than any of that needs and still finite.
5. Subscribe for answers [budget 10.00 s]: TIMED OUT after 10.00 s — no answer and no error
   Downstream of a read that did not complete, so this says nothing on its own. The sentence this step would normally earn presupposes a bond proven by the read, and no such thing was proven here. The run carries on past the read on purpose — so that a robot which answers late, or answers only some calls, is still described — and in the §5.5 outcome every step after the read is expected to end this way. The finding is the read, above.
   Budget: 10 s. A local descriptor write on an established link.
6. hello [budget 15.00 s]: TIMED OUT after 15.00 s — no answer and no error
   Downstream of a read that did not complete, so this says nothing on its own. The sentence this step would normally earn presupposes a bond proven by the read, and no such thing was proven here. The run carries on past the read on purpose — so that a robot which answers late, or answers only some calls, is still described — and in the §5.5 outcome every step after the read is expected to end this way. The finding is the read, above.
   Budget: 15 s. One small NDJSON round trip, chunked at the MTU.
7. system.authenticate [budget 15.00 s]: TIMED OUT after 15.00 s — no answer and no error
   Downstream of a read that did not complete, so this says nothing on its own. The sentence this step would normally earn presupposes a bond proven by the read, and no such thing was proven here. The run carries on past the read on purpose — so that a robot which answers late, or answers only some calls, is still described — and in the §5.5 outcome every step after the read is expected to end this way. The finding is the read, above.
   Budget: 15 s. One round trip, same as hello.
8. system.info [budget 15.00 s]: TIMED OUT after 15.00 s — no answer and no error
   Downstream of a read that did not complete, so this says nothing on its own. The sentence this step would normally earn presupposes a bond proven by the read, and no such thing was proven here. The run carries on past the read on purpose — so that a robot which answers late, or answers only some calls, is still described — and in the §5.5 outcome every step after the read is expected to end this way. The finding is the read, above.
   Budget: 15 s. One round trip, same as hello.

What the robot said
-------------------
hello: no answer at all inside 15.00 s.
system.info: no answer at all inside 15.00 s. Nothing here names the robot.

Reading
-------
The read hung on a real iPhone, exactly as §5.5 records it hanging on macOS. --require-pairing must not be defaulted on off the back of this.

The read was issued against a robot started with --require-pairing on, and after 60.00 s nothing came back at all — no answer, no error, no retry. That is §5.5's symptom reproduced on the platform the roadmap says it has never been observed on, and it is the answer that moves the question: the cause is then not CoreBluetooth-on-a-laptop. §5.5 already names the next move — "whether a bond exists at all — bluetoothctl info <mac> reporting Paired: no would mean no encryption can ever be established and the flag is a symptom rather than the cause". Run that on the robot next. iOS DID show a pairing prompt and the read still never returned, so the phone tried to bond and the bond did not complete; whatever refused it is on the robot's side.

One run is one observation. This is one phone, one robot, one room and one moment — and both of the answers this spike can produce are things a radio will do by accident once. Run it again before anybody acts on it, and if you can, vary the two things that matter most: a different iPhone model, and a run after Settings › Bluetooth › Forget This Device, which is the only way to see the first-run pairing prompt a second time. Send every run, including the ones that disagree with this one — a disagreement between two runs is a finding, and quietly keeping the tidier of the two is how a real one gets lost.
```

</details>

**That report is SYNTHESISED.** No robot produced it.

<details>
<summary><b>SYNTHESISED report 2 of 2 — what a clean pass would look like (not a measurement)</b></summary>

```text
##############################################################################
# SYNTHESISED — NOTHING HERE HAS MET A DUCK.
# Report 2 of 2 — what a clean pass would look like.
# Fixture values throughout: serial SYNTHETIC-0000, name example-duck,
# a phone model that is not a phone. Not a measurement of anything.
##############################################################################

Microduck phone pairing spike — app-path-design.md §5.5
=======================================================

This is not a feature. It runs one experiment that Pollen Robotics' own roadmap says is blocking their phone app: scan, connect, read, hello, authenticate and system.info against a real robot with --require-pairing on, from a real iPhone. §5.5 of their app-path design records the encrypted read HANGING on macOS — no prompt, no error, no retry — and says that flag has to be flipped and defaulted on before a duck is handed to anyone. Nobody has yet run it on a phone.

Both answers are worth having. If the read completes, the flag can default on and their blocker clears. If it hangs here too, that is strong evidence the cause is an absent bond rather than the platform — which is the more useful finding of the two. A step that times out is a result, not a mistake: do not retry it quietly, report it.

Setup
-----
Run started: 2026-01-01T00:10:00Z
Run count: this is run 2 from this phone against this peripheral. The count is kept against the identifier iOS gives the peripheral, which survives a rename and does not survive a change of Bluetooth address — so a duck that changed address starts again at 1.
Phone: SYNTHETIC-PHONE (no device ran this), iOS 0.0 (SYNTHETIC)
Robot: btd started with --require-pairing ON — as answered by whoever launched it. Nothing in the advertisement, the GATT table or the RPC surface says which way, so this line is a person's answer and not a measurement.
iOS pairing prompt: shown
PIN tried: 000000 — the factory PIN, published in Pollen's own repository, which is exactly why §5.5 calls a robot with the flag off "readable by a bystander". Printing it here leaks nothing.
Robot API version: 16, read as one byte off the RPC characteristic
Service 6F5D2A10-3B47-4C8E-9A1F-2D7E8C4B6019, characteristic 6F5D2A11-3B47-4C8E-9A1F-2D7E8C4B6019

What the scan saw
-----------------
Tested: example-duck, -54 dBm — advertises the robot's service UUID
Also heard in the same window:
  - example-duckling, -88 dBm — a duck-ish name and nothing else
This is a list of CANDIDATES, not a census of the room: the scan is given no service filter, and a device matching none of the three tiers is never recorded. "Serves our characteristic" is the only authoritative identity test and it is knowable solely after connecting.

Steps
-----
1. Scan [budget 40.00 s]: ok — 1.92 s
2. Connect [budget 15.00 s]: ok — 0.74 s
3. Discover the RPC characteristic [budget 10.00 s]: ok — 0.28 s
4. Read the API version [budget 60.00 s]: ok — 7.63 s
5. Subscribe for answers [budget 10.00 s]: ok — 0.19 s
6. hello [budget 15.00 s]: ok — 0.42 s
7. system.authenticate [budget 15.00 s]: ok — 0.37 s
8. system.info [budget 15.00 s]: ok — 0.44 s

What the robot said
-------------------
hello: btd 0.0.0-SYNTHETIC, revision 0000000synthetic, API version 16
system.info: name "example-duck", serial "SYNTHETIC-0000", up 3725 s (1 h 2 m 5 s)
The serial is the durable identity of this duck — it outlives a rename and a change of Bluetooth address, neither of which the peripheral identifier this app keys on survives.

Reading
-------
The encrypted read completed on iOS. This supports flipping --require-pairing on by default.

The read was issued against a robot started with --require-pairing on, so the characteristic required an authenticated encrypted link, and it returned in 7.63 s. An encrypted link was therefore established between this iPhone and this robot. §5.5's hang did not happen here, which is evidence that it is a fact about CoreBluetooth on macOS rather than about the protocol: on this hardware and this iOS version, the flag can be flipped and defaulted on. iOS showed the pairing prompt and the read completed once it was accepted, which is the first-run path a new owner takes.

One run is one observation. This is one phone, one robot, one room and one moment — and both of the answers this spike can produce are things a radio will do by accident once. Run it again before anybody acts on it, and if you can, vary the two things that matter most: a different iPhone model, and a run after Settings › Bluetooth › Forget This Device, which is the only way to see the first-run pairing prompt a second time. Send every run, including the ones that disagree with this one — a disagreement between two runs is a finding, and quietly keeping the tidier of the two is how a real one gets lost.
```

</details>

**That report is SYNTHESISED too.** No robot produced it either. The only thing
either block demonstrates is what the harness writes down.

## What a duck owner has to do before a run counts

**Start `btd` with `--require-pairing` ON.** This is the whole experiment. §5.5
records that the flag exists and is off, and that "a board installed from a
release therefore serves an unencrypted link and works out of the box" — so a
duck that has not been deliberately started with the flag on serves the version
read unencrypted, and a read that sails through proves the pipe works and
nothing whatsoever about pairing.

Then, in order:

1. **Start `btd` with `--require-pairing` on.** Saying it twice is not a
   typographical accident — it is the single step that decides whether a run is
   worth anything, and it is the one nothing on the phone can check.
2. On the phone, forget the duck first if it is already bonded: Settings →
   Bluetooth → Forget This Device. That is the only way to see the first-run
   pairing sheet a second time.
3. Open the spike screen, tell it the flag is on, tell it the PIN if it is not
   the factory `000000`, and run it.
4. **Watch the screen while step 4 runs.** Whether iOS raised a pairing sheet is
   the single most informative thing anybody can record on a hang — a sheet
   means the phone tried to bond, no sheet means it never did — and no API tells
   an app it appeared. The harness records "not observed" as a third answer
   rather than as a `false`, so a run where nobody watched is never written up as
   a run where no sheet appeared.
5. Paste the report. Including, and especially, the ones that disagree with an
   earlier run.

## What is not claimed

- **Nothing here has met a duck.** Not one line of this has run against real
  hardware. The first person to point it at a robot is the first person to find
  out whether the transcription was right.
- **Both reports above are synthesised**, from fixtures, on purpose.
- **The identifier is not the identity.** The app keys a remembered duck on the
  peripheral identifier iOS gives it, which survives a rename and does not
  survive a change of Bluetooth address. §8.6 says exactly this about exactly
  this shortcut: "an app that remembers a robot by its peripheral identifier
  alone will lose it." The SoC serial is the durable handle, and outside this
  spike the app does not yet ask for it. It is written down rather than fixed.
- **The BLE surface is the documented subset.** Provisioning, status, update
  trigger and progress. It cannot drive a duck and does not pretend it can.
- **The app's own default for the flag is OFF**, matching what §5.5 says ships,
  precisely so that a tester who never touched it cannot file a report claiming
  the blocker was cleared.
- **One run is one observation.** Every report ends by saying so and asking for
  another, from a different phone if possible. Both of the answers this spike can
  produce are things a radio will do by accident once.
- **The Android half does not exist.** M6 asks for both; I can only offer one.

## The ask, and it is a genuine either/or

Two options, and I have no preference between them:

**Take the harness.** If any of this is useful, take it in whatever shape suits
you — as a Rust port inside `duck-btctl` or the Tauri client #107 describes, as
a spec to reimplement, or as prose in `app-path-design.md`. It is Apache-2.0,
matching upstream. The parts most likely to be worth lifting are not the Swift:
they are the eight budgets and their justifications, the four-ending rule, and
the reading logic that refuses to be encouraging about a run with the flag off.
I will open a PR in whatever form you say, or none.

**Or leave it here and I just send runs.** Equally fine, and possibly better —
the client stays out of your tree, and what you get is reports. If a duck ever
reaches me, or if somebody who has one wants to run it, you get the paste. No
obligation either way, and no follow-up from me if the answer is neither.

If it helps to look first: the app is on TestFlight at
<https://testflight.apple.com/join/S36AnsKr>. The spike screen runs with no duck
present — it will simply report a scan that saw nothing, which is itself an
honest outcome.

Thanks for writing #107 and §5.5 the way you did. The reason a stranger could
build this at all is that the design documents state the measurements, name what
is not known, and say which way the flag ships and why.
