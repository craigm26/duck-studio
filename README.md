# Duck Studio

A debugger for Microduck reinforcement-learning policies that fits in a pocket.

Load any alpha-family ONNX policy — the seven that ship with
`pollen-robotics/microduck`, or the one you exported from your own training run
twenty minutes ago — and take it apart. Sixty-one observation inputs grouped by
block. Fourteen actions on live bars. An exact Jacobian showing which inputs the
network actually listens to. A recurrence probe that finds the limit cycle the
last-action feedback loop settles into. And, when you want to believe the
numbers, the resulting pose standing on your real floor at true 25 cm scale.

**Duck Studio never talks to a robot.** No Bonjour, no local network, no
Bluetooth, no pairing. The only network call in the app is a model URL you typed
yourself. This is a tool for the part of the work that happens *before* hardware
exists, which — with first Microduck deliveries around Christmas 2026 — is all of
the work anyone is doing right now.

Bundle id `com.opencastor.duckstudio` · team `WYGG3JXWMG` · iPhone-only,
portrait, iOS 17+.

---

## The hero is the numbers. AR is the proof of scale.

This decision drives the whole layout, so it is written down first.

An RL practitioner opens a policy debugger because something is wrong and they
are not at their desk. What they need in the first five seconds is *what does
this net do* — the action vector, how saturated it is, which joints are riding
their travel stops, how far out of the training distribution the current
observation sits. None of that needs a camera, a floor, or standing up. The app
therefore **opens on the numeric view and is completely useful with the camera
never granted.**

AR earns exactly one job, and it is a job nothing else can do: **25 cm is
smaller than you think.** Everybody who pre-ordered has a wrong mental model of
this robot's size. Putting the kinematic pose on your actual floor with the head
camera site at 244 mm — because that is where `robot_walk.xml` says it is, not
because an artist eyeballed it — corrects that in one second. And for a two-net
diff, two ghosts at a shared origin with a millimetre readout at the feet is
genuinely the clearest way to see that two checkpoints disagree.

So: four tabs, AR is the fourth, and the app ships fully functional if a
reviewer never taps it.

---

## The four screens

**Policies.** The library. Seven bundled (Apache-2.0, upstream, attributed),
plus whatever you import. Each row carries name, weight fingerprint, parameter
count, and load state. Tap for the architecture table, the normalization
statistics, and the source.

Files that *fail* to load stay in the list. This is the most important design
decision in the app. `DuckPolicy.load` refuses anything that is not exactly
`Sub → Div → Gemm → Elu → Gemm → Elu → Gemm → Elu → Gemm` at
61→512→256→128→14 with `transB=1`, and refuses it at load with a reason. Duck
Studio shows that reason next to a full structural dump of what *was* found —
the op sequence, the initializer names and dims, the input and output tensor
names. If you just exported a net from your own PPO run and it will not load,
this screen tells you why in one glance instead of sending you to Netron on a
laptop you do not have with you. That single screen is the reason an RL person
installs this app.

**Inspect.** Actions sticky at the top, observation scrolling underneath —
because you are watching the outputs while your thumb is on an input. Under the
action bars, a segmented control: Observation / Sensitivity / Recurrence.

**Diff.** Same observation, two networks, paired bars with signed deltas, plus
the scalars that matter (‖Δa‖₂, cosine similarity, max |Δ| and which joint).
Then the part people do not expect: run both closed-loop from an identical
initial state and plot the divergence over time. Two nets that agree to 1e-3 at
t=0 can be 8 cm apart at t=100, because the observation carries the previous
action and that makes the policy a dynamical system rather than a function.

**AR.** True scale, floor-anchored, honest. See "What is not real," below.

---

## Solving the 61-slider problem

Sixty-one sliders on one screen is unusable, and shipping it would be the
failure mode of this app. Five things fix it, in order of how much they help:

1. **Most slots are not driven by hand.** The observation has three sources and
   you pick per block. `.loop` — a `DuckSimulation` is running and the 42 slots
   of joint position, joint velocity and previous action are whatever the closed
   loop produced; sliders become read-outs and you scrub *time* instead.
   `.device` — the iPhone's own gyroscope and gravity vector feed slots 0..6
   live over CoreMotion, so you tilt the phone and watch the policy react, and
   six slots need no UI at all. `.manual` — the sliders, which are then a
   deliberate override rather than the primary input.

2. **Pinning is the actual debugging primitive.** Any slot can be pinned: it
   holds its manual value while everything else keeps running. That is how you
   ask *what does this policy do if the left knee encoder is stuck reading
   3 rad/s forever* — a question you cannot ask in a notebook without writing a
   harness, and can ask here in two taps. Pinned slots are the difference
   between a viewer and a debugger.

3. **Six collapsed blocks with informative headers.** gyro(3) · gravity(3) ·
   joint position(14) · joint velocity(14) · previous action(14) · command(13).
   Each header shows the block's L2 norm, its worst z-score, and a value strip.
   You expand the one you care about.

4. **The command block is the only one expanded by default,** because it is the
   only block a human semantically drives: vx, vy, vyaw, four head angles, body
   z/roll/pitch. Three of its thirteen slots — body x, body y, body yaw — are
   rendered locked at zero and labelled *unbound in training*. They are the
   nominal encoding, not placeholders. Showing them greyed and explained kills a
   whole class of "your observation builder has a bug" reports before they exist.

5. **Units, everywhere, correctly.** Joint position slots show both the raw
   observation value (delta from home pose, radians — which is what the policy
   sees) and the absolute joint angle in radians and degrees. Everybody forgets
   the observation is home-relative exactly once, and it costs them an afternoon.

---

## The three things you cannot get from `print(actions)`

**Z-scores.** The first two ops of every alpha policy are `Sub(mean)` and
`Div(std)` — trained statistics baked into the file. Reading `(obs − mean) / std`
per slot tells you *how many training standard deviations out of distribution
your current observation is.* Slots past |z| > 3 get flagged. "This network was
never asked this question" is the single most useful sentence a policy debugger
can say, and the answer is sitting in the file already, unused by every other
tool.

**The exact Jacobian.** ∂action/∂z, 14 × 61, computed analytically by reverse
mode through the ELU stack — not finite differences. ELU′ is 1 for x > 0 and
eˣ for x ≤ 0, so the whole thing is fourteen backward passes over a network
whose forward pass measures 40 microseconds. It renders as a heat map that
updates while you drag. A policy that ignores the yaw command entirely shows a
zero column at slot 50, and that is a training bug you can *see*. Because the
derivative is taken with respect to the *normalized* input, the 61 columns are
directly comparable despite the underlying units spanning rad, rad/s, and
dimensionless. Finite differences survive only as the test oracle that proves
the analytic version.

**Recurrence.** Observation slots 34..48 are the previous raw action. Hold
everything else frozen and iterate: does the action converge to a fixed point,
settle into a limit cycle, or run away? Under a nonzero vx you should find a
cycle at the gait period, and you can read the gait frequency straight off it.
Duck Studio reports *converged* (‖Δa‖ < ε for K ticks), *periodic, P ticks
(P × 20 ms)*, or *unbounded*. No other tool on any platform gives you this in
four taps.

Plus the two things you can get elsewhere but always want here: **action
saturation** (rolling |a| distribution per slot — a policy living at ±3 has a
broken normalization or an out-of-distribution input) and **clip rate**
(`DuckGait` already names every joint held at a travel stop; Duck Studio counts
them, so "left_knee clipped 41% of the last 250 ticks" is a number on screen).

And a toggle for the trained low-pass. `DuckGait` applies the first-order filter
the policies were *trained with* — head α = 0.5, legs α = 0.7. Duck Studio draws
the filtered and unfiltered joint target on the same bar so the gap between them
is visible, and lets you sweep α to feel the lag. Any α other than 0.5/0.7 keeps
a permanent banner saying you are no longer looking at the robot.

---

## Loading a policy

Four doors, and all four matter:

- **Bundled.** All seven upstream alpha policies ship in the app (~5.6 MB,
  Apache-2.0, `NOTICE` in the bundle and on the Policies screen). The app is
  fully useful with zero user files on first launch, which also settles App
  Review's minimum-functionality question.
- **Files.** `.fileImporter`, user-initiated, unambiguous.
- **AirDrop and Open With.** This is the workflow that makes the app real: your
  training run finishes on the Mac, you AirDrop the `.onnx`, it lands in Duck
  Studio. It only works if the app *declares the type* — there is no system
  UTType for ONNX, so `Info.plist` carries a `UTImportedTypeDeclarations` entry
  for `org.onnx.model` conforming to `public.data` with extension `onnx`, plus a
  matching `CFBundleDocumentTypes`. Without both, iOS treats `.onnx` as generic
  data and never offers Duck Studio in the share sheet. Silent failure, far-away
  symptom — the same shape of bug as the entitlements trap in OpenCastor.
- **URL.** Paste an `https://` model URL, or give `owner/repo` + filename and
  Duck Studio builds the Hugging Face resolve URL for you. Public repos only.
  **No token field, ever** — a credential in a Data-Not-Collected app is a
  liability I am not taking on, and the audience mirrors public checkpoints
  anyway.

**Identity is by weight fingerprint, not filename.** SHA-256 over the parameters
in canonical order — mean, std, then each layer's weights and biases as
little-endian Float32 — so two files that differ only in metadata or opset are
recognized as the same network, and two files with the same name and different
weights are not. This settles "did I actually load the new checkpoint," which is
the most common self-inflicted bug in this entire field.

---

## What is not real, said out loud

- **There is no physics.** `DuckSimulation` says so itself: `isGrounded` is a
  constant `true`, joint velocity is estimated by differencing targets, and
  gravity is assumed to point down at whatever pose the policy is holding. The
  legs move the way the network says to. That is correct as a gait and wrong as
  a fall. The AR ghost carries a permanent *kinematic only — no contact forces*
  label, and the recurrence result is a property of the network in isolation,
  not a prediction about hardware. Overclaiming here would be the intellectual
  failure of the whole app.
- **The AR ghost is anchored, not simulated.** The trunk's world position is not
  computed by anything, so the ghost is placed such that the lower foot touches
  the detected floor plane each frame. The duck's height therefore changes as
  its legs bend, which is the truthful rendering of "no ground contact."
- **The forward pass matches onnxruntime to 1e-4, not exactly.** Same weights,
  same input bytes, different accumulation order. That tolerance is printed on
  the policy card, not buried in this file. A debugger that quietly disagrees
  with the reference implementation in the fifth decimal is worse than no
  debugger, so it disagrees loudly.

---

## Layout

| Path | What |
|---|---|
| `StudioKit/` | Pure-Swift, UI-free core. Builds and `swift test`s on Linux aarch64. Every number the app displays is computed here. |
| `StudioKit/Tests/StudioKitTests/Fixtures/policies/` | The seven real upstream `.onnx` files. |
| `StudioKit/Tests/StudioKitTests/Fixtures/refusals/` | The refusal corpus: hand-mutated ONNX files, one per distinct rejection reason. |
| `DuckStudio/project.yml` | xcodegen manifest (source of truth; `.xcodeproj` is generated and gitignored). |
| `DuckStudio/Info.plist` | Camera (AR), motion (IMU-driven gyro/gravity), the `org.onnx.model` type declarations, `ITSAppUsesNonExemptEncryption=false`. Deliberately **no** local-network, Bonjour, Bluetooth, microphone, or location keys. |
| `DuckStudio/Resources/PrivacyInfo.xcprivacy` | The Data-Not-Collected manifest. Flattens to the app-bundle root. |
| `DuckStudio/Sources/` | SwiftUI only. No arithmetic lives here; `scripts/check_no_studio_math.sh` enforces that. |
| `zoo/` | What gets published to Hugging Face and the public companion repo. |
| `scripts/mac_build.py` | MacInCloud driver: tar the tree, SFTP up, `xcodegen generate`, `xcodebuild`. |
| `scripts/make_refusal_corpus.py` | Generates the mutated ONNX fixtures from the vendored `alpha_walking.onnx`. |
| `NOTICE` | Apache-2.0 attribution for the vendored policies and the MJCF model. |

Depends on `github.com/craigm26/duckkit` for everything Microduck-shaped:
`DuckModel`, `DuckObservation`, `DuckPolicy`, `DuckGait`, `DuckKinematics`,
`DuckSimulation`. That package is already written and tested (848 tests). Duck
Studio adds no robot knowledge of its own and reimplements nothing — see
`PLAN.md` for the small, specific list of things DuckKit has to grow.

## Build and test

```bash
# The core — runs anywhere, no Mac and no device needed. This is where the work is.
cd StudioKit && /home/craigm26/swift-6.3.3/usr/bin/swift test

# The app — needs a Mac. Locally, or via the MacInCloud driver:
cd DuckStudio && xcodegen generate
xcodebuild -scheme DuckStudio -destination 'generic/platform=iOS Simulator' build

# Or, from the Pi:
MAC_PASS=... python3 scripts/mac_build.py
```

No GitHub Actions. The `.xcodeproj` is generated and never committed.

## Privacy

**Data Not Collected**, and unusually easy to mean it here: the app has no
account, no server, no analytics endpoint, no SDK, no event stream. Camera
frames for AR are processed on device by ARKit and never leave it. Motion
readings feed six floats of an observation vector and are never stored. The one
outbound request in the entire binary is a model URL the user typed, shown in
full before the fetch, going to a host the user chose.

Which means there is no way to watch this app work from the inside, on purpose.
Every success metric in `GATES.md` is a $0 side channel measured outside the
app — App Store Connect downloads, Cloudflare Web Analytics on the docs site,
Hugging Face download counts, GitHub stars. Count the doors people walk through,
never the people.

## Attribution

The seven policies, the observation layout, the control constants and the MuJoCo
model are from `pollen-robotics/microduck`, Apache-2.0. Every number Duck Studio
displays about the robot is upstream's number. See `NOTICE`.
