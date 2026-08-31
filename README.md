# Duck Studio

A bench for Microduck reinforcement-learning policies and the motions they
produce, on a phone.

Open a policy and take it apart: sixty-one observation inputs grouped into eight
blocks, fourteen actions on bars drawn against the travel stops the robot
actually has, a z-score per input saying how far out of the training
distribution you have wandered, and an exact Jacobian ranking which inputs the
network is actually listening to. Watch the motions those policies produced when
they drove a robot through MuJoCo on a bigger machine. Build a place to play
them in. Write a new motion by posing the robot, or by typing a sentence and
letting a model draft the keyframes for you to fix.

And when a file will not load, find out why — with the op sequence, the
parameter count, the layer widths and the input and output tensor names of what
*was* in the file sitting underneath the refusal. `DuckPolicy.load` accepts
exactly
`Sub → Div → Gemm → Elu → Gemm → Elu → Gemm → Elu → Gemm` at 61→512→256→128→14
with `transB=1` and refuses everything else with a reason. Duck Studio shows the
reason and the structure together, which is the screen an RL person installs
this app for.

Bundle id `com.duckstudio.ios` · team `WYGG3JXWMG` · iPhone and iPad, iOS 17+.
Three orientations on iPhone and four on iPad — iPad multitasking demands all
four or App Store Connect refuses the upload.

---

## What this app cannot do, said before anything else

**A phone has no physics engine.** Nothing here runs MuJoCo. That single fact
shapes every screen:

- The **bench is one honest step of the network**, not a loop. Feed it an
  observation and you see the fourteen numbers, the joint targets `DuckGait`
  derives from them, and the robot standing in that pose. Closing the loop —
  feeding the resulting pose back in — is not offered and cannot be made to
  work: the policy locks its gait phase to *contact*, read through the gyro,
  projected gravity and joint velocities, and on a bench all three are whatever
  you last typed. Measured, that loop gives a 25 Hz flip-flop or a slam into the
  travel stops.
- A **preview is not a run.** An authored motion is poses and times,
  interpolated. What the stage draws is what you *asked* the robot for, never
  what it would do. All four authored stair motions in the corpus get up their
  flight 0 times in 16, and no preview on this phone would ever have told you
  that.
- The **recorded intents are recordings.** Playing one shows what a policy did
  in MuJoCo on a bigger machine when the app was built. It does not re-run the
  network.
- **Nothing here trains anything.** The training screen writes and checks a
  *request* — "lift two kilos" is refused in a second by arithmetic rather than
  after a day of training that was never going to converge. There is no Python,
  no mjlab and no GPU on a phone.
- **Drafted rules do not fire.** `DuckToF` and `DuckState` are inbound decoders
  with no output channel, so a when/then is a checkable specification and the
  screen says so.
- **The forward pass matches onnxruntime to 1e-4, not exactly.** Same weights,
  same input bytes, different accumulation order; DuckKit's own tests assert that
  tolerance against golden vectors. A debugger that quietly disagreed with the
  reference implementation in the fifth decimal would be worse than no debugger —
  so it is written down here, and **it is not yet shown on the policy card**,
  which is where `GATES.md` says it belongs.

The one way to get real physics is to point the app at a machine that has some —
see "Run it somewhere with physics," below.

---

## The five tabs

The app opens on **Policies**, and every tab is useful with no network, no
account and no robot.

The fifth is **Lab**, and it is where three other apps went. Duck Soccer,
Duckboard and Duck Diary each had their own repository, bundle identifier and
pre-registered gates; two of them contained no code at all. A person who buys a
Microduck should not have to find four apps to use one robot. Five is also the
ceiling: iPhone folds a sixth tab into "More", where a tab is somewhere people
do not go, so anything arriving after this lives inside one of the five.

**Policies.** The library, organised by *provenance* rather than by folder: two
sections, "Released by Pollen Robotics" and "From elsewhere", and which one a
policy lands in is decided by its parameter fingerprint, not by whether it
shipped in the bundle. Nine policies ship (Apache-2.0, upstream), plus whatever
you import. Each row carries the display name, a sixteen-character identity and
where the file arrived from; the toolbar says how many of them run.

Files that *fail* to load stay in the list, and that is the most important design
decision in the app. The detail screen shows the refusal reason, a remedy where
there is one, and the structure table — operations, parameter count, layer
widths, input and output names — for what *was* found. If you just exported a net
from your own PPO run and it will not load, this screen tells you why in one
glance instead of sending you to Netron on a laptop you do not have with you.

From a policy that runs, **Probe this network** opens the bench: a 3D stage on
top wearing the pose the policy just asked for, and a segmented control
underneath — **Inputs / Actions / Sensitivity**.

**Intents.** The motions. Clips recorded from Pollen's policies in physics,
authored moves written here, motions somebody sent you as `.duckintent`, and the
drafts you are working on. Playing one draws the robot walking its recorded path
against whichever scene you choose. Each draft also carries a **Sim to real**
pipeline row: what has actually happened to it — written, previewed, run on a
bench — so a motion opened a week later is not just keyframes and a name.

**Fetch something** lives here too, and it writes no poses at all. It composes
skills the robot already has — walking is `alpha_walking`, reaching down is
`alpha_ground_pick`, and the grasp is the fifteenth servo, which no policy
drives — so a sentence becomes a plan rather than a keyframe track. The refusals
are the lesson: ask for a pencil and it says no, because the jaw closes 20 mm
above the floor and a 7 mm pencil passes underneath. Somebody who reads two
refusals knows more about this robot than somebody who watched a demo work.

**Scenes.** The world a motion is judged against: the floor, a flight of steps,
a corridor, props the duck could take hold of. Build one here and play any intent
in it rather than only where it was recorded. The staircase starts at the step
height the robot has actually been measured to clear, and the editor says so when
you raise it past that.

**Draft.** Say what you want in a sentence and watch what your words became.
Four modes — **Motion**, **Rule**, **Fetch**, **Train** — all going through the
same model of your choosing, and all landing in the same tested resolver a
hand-made draft goes through. A model that invents a joint gets a person's
refusal. A drafted motion opens immediately in the 3D editor with every keyframe
where the sentence put it, which is how somebody learns this robot's joints
without reading a manual.

---

## The observation editor

Sixty-one sliders on one screen is unusable. Three things fix it today:

1. **You start from a preset, not from zero.** *Standing still*, *Walking
   forward* (0.15 m/s, inside the trained range), *Turning left* (1.0 rad/s
   yaw), or *All zeros* — which is deliberately kept and labelled as not a robot
   state at all, since an all-zero gravity vector describes free fall and sits
   about 32 training standard deviations out.

2. **Eight blocks with a section each.** Angular velocity (3) · projected
   gravity (3) · joint positions (14) · joint velocities (14) · previous action
   (14) · twist command (3) · head command (4) · body command (6). The thirteen
   command slots are three blocks rather than one, because vx/vy/vyaw, the four
   head angles and the six body deltas are three different things a person
   drives for three different reasons.

3. **Every slot says what it is and how far out it is.** Label, unit, a slider
   bounded by the range training actually sampled where such a range exists, the
   value, and the z-score beside it — flagged past |z| > 3. Slots the app's own
   observation builder never writes into (55, 56 and 60) are marked *unused*, so
   a sensitivity ranking cannot put a slot you cannot vary near the top and
   nobody files a "your observation builder has a bug" report about it. Joint
   position labels say `rel. home` in as many words, because everybody forgets
   the observation is home-relative exactly once and it costs them an afternoon
   — though the absolute joint angle beside it, in radians and degrees, is still
   owed.

   The bounds are not all the same kind of thing, and `ObservationSlot`
   distinguishes them: where training sampled a command from a range, the range
   means something; where nothing bounds a value — the gyro, the joint
   velocities and the previous action are all unclipped in training — the bound
   is a sane editing range and nothing more.

Every label, unit and bound is read out of `pollen-robotics/microduck_rl`, not
guessed by watching a running policy.

Pinning, the `.loop` and `.device` observation sources, and the CoreMotion feed
are **not built** — see "Not built yet."

## The two things you cannot get from `print(actions)`

**Z-scores.** The first two ops of every alpha policy are `Sub(mean)` and
`Div(std)` — trained statistics baked into the file. Reading `(obs − mean) / std`
per slot tells you *how many training standard deviations out of distribution
your current observation is.* "This network was never asked this question" is the
single most useful sentence a policy debugger can say, and the answer is sitting
in the file already, unused by every other tool.

**The exact Jacobian.** ∂action/∂z, 14 × 61, computed analytically by reverse
mode through the ELU stack — not finite differences. ELU′ is 1 for x > 0 and
eˣ for x ≤ 0, so the whole thing is fourteen backward passes over a network whose
forward pass measures about 40 microseconds. Because the derivative is taken with
respect to the *normalized* input, the 61 columns are directly comparable despite
the underlying units spanning rad, rad/s and dimensionless. Finite differences
survive only as the test oracle that proves the analytic version.

The bench presents it as a ranked list — what this policy listens to, and, in its
own section, what it **ignores entirely**. A policy that ignores the yaw command
shows up as a name in a list rather than as a mystery in behaviour.

The action bars draw the raw action against the clamped joint target, so the gap
between them *is* the travel limit, and every joint the clamp caught is named
under "At the travel stops" — `DuckGait` already knows which ones those are. The
gait scale applied is the one `robotd` would use for *that* policy: roulade,
ground-pick and the sit/rise cycle run at 1.0, and only walking and the kicks are
de-rated to 0.9, so a bench that applied the walking scale to a roulade policy
would show targets 10% short of what the robot is actually sent.

---

## Loading a policy

- **Bundled.** Nine upstream policies ship in the app (about 6.9 MB,
  Apache-2.0). The app is fully useful with zero user files on first launch,
  which also settles App Review's minimum-functionality question.
- **Files, AirDrop and Open With.** This is the workflow that makes the app real:
  your training run finishes on the Mac, you AirDrop the `.onnx`, it lands in
  Duck Studio. It only works because the app *declares the type* — there is no
  system UTType for ONNX, so `project.yml` carries a `UTImportedTypeDeclarations`
  entry for `org.onnx.model` conforming to `public.data` with extension `onnx`,
  plus a matching `CFBundleDocumentTypes` row. Without both, iOS treats `.onnx`
  as generic data and never offers Duck Studio in the share sheet. Silent
  failure, far-away symptom — the same shape of bug as the entitlements trap in
  OpenCastor.
- **URL.** Paste an `https://` model URL, or give `owner/repo` + filename and
  Duck Studio builds the Hugging Face resolve URL for you. `resolve/` and not
  `blob/`, which fetches the HTML page around the file and fails as a confusing
  protobuf error. https only, public repos only, 8 MB cap, and the whole URL is
  shown before anything leaves the device. **No token field on this path** — a
  credential for reading someone's private checkpoint is a liability this app
  does not want, and the audience mirrors public checkpoints anyway.
- **Browse what exists.** The app's own list of official policies is frozen at
  build time and Pollen keep training, so a release newer than this build shows
  up as "unrecognised" — honest, and unhelpful. The catalogue screen goes and
  looks at what Pollen currently publish, and a second screen browses what other
  people have trained, leading with the manifest rather than the weights, because
  an `.onnx` states its input and output widths and nothing else. Nothing is
  fetched until you press the button, and the address is printed first.

**Identity is by weight fingerprint, not filename.** SHA-256 over the parameters
in canonical order — mean, std, then each layer's weights and biases as
little-endian Float32 — so two files that differ only in metadata or opset are
recognized as the same network, and two files with the same name and different
weights are not. The bytes come from `DuckPolicy.canonicalParameterBytes` in
DuckKit and the digest from `DuckEvidence`, because DuckKit having no
dependencies is what lets the real network run under `swift test` on a Pi.

Identity needs **two** rules, not one, and they cannot be merged: a policy that
loads is identified by its parameter fingerprint, so one network under two
filenames is one entry — but a file that does not load has no parameters to
digest, and the refusal screen is the whole point, so those fall back to a digest
of the file, and the screen says that is the weaker kind of identity.

## Run it somewhere with physics

You can import a policy and then find there is nothing to press, because this
device cannot run one forward in a world. **Run on your network** points the app
at a machine that can: a box on your own network running `duckbench.mjs` from the
duck-sounds repository. It reports what plant it is simulating, at what rate, on
how many cores, and what is in that world; a run comes back as a real result the
draft keeps. Plain http, and only a private address or a `.local` name is
accepted, because a Pi on a desk has no certificate.

## Where a draft comes from

Apple's on-device model, a box on your own network, or another app on this
phone — anything speaking `/v1/chat/completions` (Ollama, LM Studio,
llama.cpp's server, vLLM, an OpenAI-compatible proxy). `tools/claudebridge.mjs`
puts a Claude Code subscription behind that same interface in forty lines.

Every endpoint carries a one-sentence note saying *where what you type will end
up*, shown before you type it, because "drafted by AI" says nothing about whether
the sentence left the building. Bearer tokens for these go in the Keychain, never
in the plist a backup carries.

The default timeout is enormous on purpose: a 7.5B Gemma at Q4 on a CPU-only
Raspberry Pi 5 took 766 seconds to write one 200-token motion draft. The remedy
for the wait is a smaller model, not a shorter timeout, and the screen says so
after a test run.

## What the app writes

| Extension | What | Read back? |
|---|---|---|
| `.duckintent` | A recorded or shared motion. Exported type, `com.duckstudio.intent`. | Yes — the app opens these. |
| `.duckmove` | A motion you authored here. Exported type, `com.duckstudio.move`, with a document type row. | Yes — `LibraryModel.open` decodes it and files it in your drafts. The row went in with the branch that files the draft, which is the order that matters: a door has to lead somewhere before iOS is told it exists. |
| `.duck` | A task brief for quackd (`rokbenko/quackd`, spec `duck: 0`). Imported type — this app implements the spec, it does not own it. | No, on purpose. There is no task store and no task screen, so a decode whose success showed up in no list would be a false "Added" banner. |
| `.onnx` | The policy file itself, handed on with a message that leads with the digest. | Yes — this is the import path. |

## Not built yet

Kept here rather than deleted, because they are scheduled work in `PLAN.md` and
not features that were removed. Nothing below exists in the shipping app.

- **The rest of M2 — observation sources.** Pinning a slot so it holds its manual
  value while everything else moves, the `.loop` and `.device` block sources, and
  the CoreMotion feed for gyro and gravity. The app requests no motion permission
  today.
- **The rest of M3 — saturation.** The rolling |a| window and the per-joint clip
  rate ("left_knee clipped 41% of the last 250 ticks"), and the low-pass toggle
  and α sweep with the not-the-robot banner. The bench applies the trained
  filter; it does not let you sweep it.
- **The rest of M4 — the heat map.** The bench ranks the Jacobian's columns and
  names the ignored ones; it does not draw the 14 × 61 matrix. The pre-registered
  16 ms engineering gate in `GATES.md` is a COMPUTE gate, and the bench does
  compute the full Jacobian on every edit — so what is missing is the
  measurement on an iPhone 12 with `os_signpost`, not the arithmetic.
- **M5 — Recurrence.** Iterating the previous-action loop and classifying it as
  converged / periodic / unbounded. `StudioKit/Sources/StudioKit/Recurrence.swift`
  does not exist.
- **M6 — Diff.** Two networks on one observation: paired bars, ‖Δa‖₂, cosine
  similarity, argmax joint, and closed-loop divergence over time. `PolicyDiff` was
  never written.
- ~~**M7 — AR.**~~ **Built, in the Lab.** This entry used to say "there is no AR
  in this app and no camera use of any kind", and that stopped being true the
  day the Lab arrived: nine files run an `ARSession`, and every Lab mode offers
  "Your floor" beside its rendered stage. The plist now declares
  `NSCameraUsageDescription` to match, which it did not for one build — see the
  note beside that key, because the gap crashed the app and no compile-time
  check could see it.

  The argument was always that 25 cm is smaller than everyone who pre-ordered
  thinks, and that putting the pose on a real floor with the head camera site at
  244 mm — because that is where `robot_walk.xml` says it is — corrects that in
  one second. What is still unbuilt is the part M7 was really about: the
  two-ghost diff, authored against recorded, with per-site millimetre
  separation.

## Layout

| Path | What |
|---|---|
| `StudioKit/` | Pure-Swift, UI-free core. Builds and `swift test`s on Linux aarch64. Every number the app displays is computed here, and so is every sentence that makes a claim about a policy, a motion or a refusal — the ones a test has to be able to assert letter by letter. Ordinary screen furniture (section headers, footers, button titles) is still written in the views. |
| `StudioKit/Tests/StudioKitTests/Fixtures/policies/` | The nine real upstream `.onnx` files. |
| `StudioKit/Tests/StudioKitTests/Fixtures/refusals/` | The refusal corpus: eleven ONNX files — one per distinct rejection reason, plus a synthetic control that must load, without which the corpus would only prove the generator emits unusable bytes. |
| `DuckStudio/project.yml` | xcodegen manifest, and the source of truth for `Info.plist` — which is generated, not committed, along with the whole `.xcodeproj`. Carries the type declarations, the document types, and `ITSAppUsesNonExemptEncryption=false`. It declares `NSCameraUsageDescription` (the Lab's AR modes), `NSLocalNetworkUsageDescription` and an `NSAllowsLocalNetworking` ATS exception (the physics bench, at an address you type). It declares **no** motion, microphone, location, Bluetooth or **Bonjour** key — nothing here listens for a machine it was not pointed at. |
| `DuckStudio/Resources/` | The nine bundled policies and `PrivacyInfo.xcprivacy`, which flattens to the app-bundle root. |
| `DuckStudio/Sources/` | SwiftUI only. No arithmetic lives here; `scripts/check_no_studio_math.sh` enforces that. |
| `scripts/check_no_studio_math.sh` | The guard. Run it before you finish. |
| `scripts/make_refusal_corpus.py` | Generates the refusal fixtures. They are **synthesized, not mutated**: renaming an op is four bytes where there were three, so every enclosing length prefix has to be recomputed, and writing that is writing a protobuf encoder anyway. Building each file from nothing also means it carries exactly one defect, which is what makes it fair to assert the message names that defect. |
| `scripts/mac_compile_check.py` | The FREE gate. Tars the tree, ships it to the build Mac over SFTP, generates the project and runs `xcodebuild ... CODE_SIGNING_ALLOWED=NO`. Unlimited, so never spend a TestFlight upload finding out whether something builds. |
| `scripts/archive_upload.sh` | Runs on the Mac: archive, sign with an App Store Connect API key, upload to TestFlight. No Apple ID login on the machine. |
| `tools/claudebridge.mjs` | A Claude Code subscription behind an OpenAI-compatible endpoint, for the Draft tab. |
| `PLAN.md` · `GATES.md` · `docs/` | The plan, the pre-registered decision gates, and the working notes. |

Depends on `github.com/craigm26/duckkit` for everything Microduck-shaped —
`DuckModel`, `DuckObservation`, `DuckPolicy`, `DuckGait`, `DuckKinematics`,
`DuckSimulation`, plus `DuckEvidence` for the fingerprint and the official-policy
manifest and `DuckVisual`/`DuckRender` for the geometry the stage draws. By tag,
never by path: an inspector that reports which network it loaded must be built
against a pinned reader, or its report describes a parser nobody can identify
later. Duck Studio adds no robot knowledge of its own and reimplements nothing.

## Build and test

```bash
# The core — runs anywhere, no Mac and no device needed. This is where the work is.
cd StudioKit && /home/craigm26/swift-6.3.3/usr/bin/swift test

# The rule, before anything else:
bash scripts/check_no_studio_math.sh

# The app — needs a Mac:
cd DuckStudio && xcodegen generate
xcodebuild -scheme DuckStudio -destination 'generic/platform=iOS Simulator' build

# TestFlight, from the Mac:
./scripts/archive_upload.sh <KEY_ID> <ISSUER_ID>
```

No GitHub Actions. The `.xcodeproj` and `Info.plist` are generated and never
committed.

## Privacy

**Data Not Collected.** There is no account, no server of ours, no analytics
endpoint, no SDK and no event stream, and `PrivacyInfo.xcprivacy` declares an
empty `NSPrivacyCollectedDataTypes`. Nothing about what you do in this app is
reported anywhere.

That is not the same as "the app makes no network calls", and the difference
matters enough to enumerate. Every outbound request in the binary is one you
started, to a host you chose:

- A policy fetched from a URL you typed or built from `owner/repo` — shown in
  full first.
- A catalogue scan of `huggingface.co`, `api.github.com` or
  `raw.githubusercontent.com`, when you press the scan button. The address is
  printed before the button.
- Publishing a motion to Hugging Face, which needs a write token. That token
  lives in the Keychain, is read only at the moment a request is signed, and the
  screen shows which account, which address and every file with its size before
  anything is sent. The default is a private repository.
- A draft request to whichever model you chose — Apple's on-device model makes no
  request at all; anything else goes where its privacy note says it goes.
- A run on a bench at a private address on your own network.

`GATES.md`'s hard rule — no in-app analytics, Data Not Collected — still holds
exactly. Its supporting sentence "exactly one outbound request in the whole
binary" predates the catalogue, publish, bench and drafting screens, and the list
above is the current answer.

Which means there is still no way to watch this app work from the inside, on
purpose. Every success metric in `GATES.md` is a $0 side channel measured outside
the app — App Store Connect downloads, Cloudflare Web Analytics on the docs site,
Hugging Face download counts, GitHub stars. Count the doors people walk through,
never the people.

## Attribution

The nine policies, the observation layout, the control constants and the MuJoCo
model are from `pollen-robotics/microduck` and `pollen-robotics/microduck_rl`,
Apache-2.0. Every number Duck Studio displays about the robot is upstream's
number, and the Policies screen says of each file whether it is one of Pollen's
releases. The `.duck` task format is `rokbenko/quackd`'s.

A top-level `NOTICE` file carrying the Apache-2.0 attribution is still owed and
is not in the tree; it is required before the first App Store submission.
