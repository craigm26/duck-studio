# Duck Studio — plan

## The bet

An ONNX policy inspector is a tool for the phase of work that happens *before*
hardware. Microduck deliveries are around Christmas 2026; today is 2026-08-27;
the only Microduck work anybody can do right now is train and inspect policies.
Duck Studio is the app in this family with the least dependency on the duck
existing, which makes it the one worth building first.

The audience is narrow and precisely reachable: people who train these policies.
They live on Hugging Face and in the upstream GitHub repo. They are also, almost
by definition, the people who pre-ordered the robot. There is no second audience
and the app should not pretend otherwise.

## Architecture

Two targets and one rule.

```
duck-studio/
├── StudioKit/            pure Swift, no UIKit, no ARKit, no CryptoKit
│   ├── Package.swift     swift-tools-version:5.9, [.iOS(.v17), .macOS(.v13)]
│   ├── Sources/StudioKit/
│   │   ├── PolicyLibrary.swift       bundled + imported + URL; identity by fingerprint
│   │   ├── PolicyReport.swift        describe + load outcome -> the exact text on screen
│   │   ├── ObservationSlot.swift     61 slots: block, label, unit, sane range, locked-ness
│   │   ├── ObservationEditor.swift   slot values, pins, three sources, -> DuckObservation
│   │   ├── ZScoreStrip.swift         (obs - mean)/std per slot; flags |z| > 3; no-variation
│   │   ├── ActionReadout.swift       raw action -> gait stages -> per-joint bar model
│   │   ├── SaturationWindow.swift    rolling |a| quantiles + clip rate over N ticks
│   │   ├── Sensitivity.swift         14x61 Jacobian presentation, column/row norms, ranking
│   │   ├── Recurrence.swift          iterate last-action; fixed point / period / unbounded
│   │   ├── PolicyDiff.swift          A vs B: deltas, cosine, closed-loop divergence series
│   │   ├── GhostPose.swift           DuckKinematics -> segments, site markers, floor anchor
│   │   └── StudioReport.swift        canonical-JSON, hash-chained, signable export
│   └── Tests/StudioKitTests/
│       └── Fixtures/{policies,refusals,golden}/
├── DuckStudio/           SwiftUI app target, xcodegen-generated project
└── scripts/
```

**The rule: StudioKit computes, DuckStudio displays.** No arithmetic in the app
target. `scripts/check_no_studio_math.sh` greps the shipping SwiftUI sources for
the tokens that could only appear if someone recomputed something — `homePose`,
`actionScale`, `lowpass`, `61`, `mean[`, `std[`, `exp(`, `jointRanges` — and
fails the build. This is the same guard shape as OpenCastor's
`check_no_policy_reimpl.sh`, and it exists for the same reason: the moment two
places know the observation layout, they disagree, and the disagreement is
silent. DuckKit is the single source of robot truth; StudioKit is the single
source of *presentation* truth; the app target only draws.

### The three data flows

**Observation assembly.** `ObservationEditor` holds 61 slot values, 61 pin
flags, and a per-block source (`.manual` / `.loop` / `.device`). Each tick it
resolves every slot — pinned wins, else the block's source — and hands the
result to `DuckObservation.build`. It never assembles the flat array itself;
that would duplicate the highest-risk file in DuckKit. The zeroed body axes stay
zero because `DuckObservation.build` writes them, and the editor simply renders
those three slots as locked.

**Inference and staging.** `DuckPolicy.inferTrace` gives normalized input,
three hidden activations and actions in one pass. `DuckGait.stages` gives
scaled / filtered / clamped targets and the `limitedBy` names separately, so the
action bar can draw all three stages. Both are DuckKit additions (below).

**Rendering.** `DuckKinematics.bodyPoses` gives every body's pose in the trunk
frame. `GhostPose` turns that into drawable segments plus site markers, and
computes the floor anchor as `-min(z of left_foot, z of right_foot)`. The app
target places that at the ARKit plane and applies no scale factor, because the
model is already in metres.

### Performance budget

Forward pass ~40 µs. Analytic Jacobian is fourteen reverse passes, so on the
order of 560 µs — comfortably live at 60 fps while a slider is moving. The
closed loop is 50 Hz, which is 2% of a frame budget. The only thing that could
be slow is the ARKit view, which is ARKit's problem. Pre-registered threshold in
`GATES.md`: full Jacobian under 16 ms on an iPhone 12 or the heat map becomes
on-demand.

## What DuckKit has to grow

All pure Swift, all `swift test`-able on the Pi, all small. **Land these in the
duckkit repo first and let CastorKit pick them up from there.** Never refactor
the same logic in two places — 848 tests currently pin the load path and
OpenCastor depends on it.

- **D-1 `DuckPolicy.describe(from:) -> Description`.** Always-succeeding
  structural read: op sequence, initializer names and dims, graph input/output
  names and shapes, parameter count. `load` becomes `describe` + validate.
  Without this the refusal screen — the app's single best feature — cannot
  exist, because a thrown error carries a sentence and not a structure.
- **D-2 Expose the normalization.** `mean` and `std` are currently internal.
  Make them public as `normalization: (mean: [Float], std: [Float])`, plus
  `layerWidths` and `parameterCount`. The z-score strip is entirely built on
  numbers already sitting in the file.
- **D-3 `DuckPolicy.inferTrace(_:) -> Trace`.** Returns normalized input, h1
  (512), h2 (256), h3 (128), actions (14). Free — those arrays already exist
  inside `infer`. Enables dead-unit counts (how many ELU units sit at x ≤ 0, in
  the exponential regime).
- **D-4 `DuckPolicy.jacobian(at:) -> [[Float]]`.** Exact 14×61 ∂action/∂z by
  reverse mode; ELU′ = 1 for x > 0, eˣ for x ≤ 0. Tested against central
  differences to 1e-3. This is the flagship feature and it must be exact, not
  finite-differenced, because ε selection across slots whose units span rad,
  rad/s and dimensionless is exactly the kind of choice that produces a
  plausible-looking wrong answer.
- **D-5 `DuckPolicy.fingerprint`.** SHA-256 over parameters in canonical order
  (mean, std, then per layer weights then biases, little-endian Float32). Brings
  swift-crypto into DuckKit, which D-8 needs anyway.
- **D-6 `DuckGait.stages(action:previousTargets:kind:mouth:alphas:) -> Stages`**
  carrying `scaled`, `filtered`, `clamped`, `limitedBy`. Reimplement `frame` on
  top of it so there is one pipeline. Low-pass alphas become a parameter
  defaulting to (head 0.5, legs 0.7) so the sweep does not require a copy of the
  filter.
- **D-7 `DuckSimulation.State`** — readable and writable (`jointPositions`,
  `previousTargets`, `lastAction`, `tickCount`). Everything is private today, so
  Duck Studio cannot inject a state, cannot pin a slot mid-loop, and cannot
  restart two policies from an identical initial condition for the diff. Add a
  `State` struct plus `init(walk:stand:state:)` and `var state`.
- **D-8 Move CanonicalJSON + CanonicalValue, Ed25519 signing, and the
  hash-chained Journal from CastorKit into DuckKit.** `StudioReport` needs
  canonical JSON and a chain to make an exported finding into an artifact
  somebody can verify. **Constraint:** `Journal` is currently typed to
  OpenCastor's `Receipt`. It has to be generalized over a `CanonicalValue`
  payload during the move, not copied. `SigningKeyStore` moves too (Keychain on
  device, in-memory on Linux). `PhoneSight` does **not** move — Duck Studio's AR
  needs a horizontal plane and nothing else, and dragging LiDAR capability
  tiering in would add an ARKit dependency to a package whose whole value is
  that it builds on Linux.
- **D-9 (optional, M6) `DuckKinematics.geoms`.** The MJCF geom primitives (type,
  size, pos, quat, parent body) so the ghost draws the robot's real shapes
  instead of a stick figure. Requires re-parsing `robot_walk.xml`. v1.0 ships
  the skeleton; this is what makes v1.1 look like a duck.

## Milestones

**M0 — DuckKit grows (D-1..D-8). DONE, 2026-08-28, duckkit v1.4.0.** D-1 to
D-4, D-6 and D-7 had already landed in earlier duckkit work; D-8 shipped as the
`DuckEvidence` product. D-5 shipped last, and NOT as written: this plan said the
fingerprint "brings swift-crypto into DuckKit", which had already been asked for
once and refused, because DuckKit having no dependencies is what lets the real
network run under `swift test` on the Pi. It split instead —
`DuckPolicy.canonicalParameterBytes` in DuckKit (the byte order is robot truth
and belongs beside the parser), `fingerprint` / `shortFingerprint` /
`fingerprintRecord` as a `DuckEvidence` extension. D-9 remains optional.

**M1 — Load and refuse.** `PolicyLibrary` + `PolicyReport`. Seven real policies
load. The refusal corpus produces seven distinct, specific, quotable reasons.
Fingerprints are stable across a byte-identical copy and differ on a single
flipped weight. This milestone alone is a shippable app.

**M2 — Observation editor.** Six blocks, three sources, pinning, correct units,
locked body axes, z-score strip.

**M3 — Actions.** Sticky bars, three gait stages drawn together, saturation
window, clip rate, low-pass toggle and α sweep with the not-the-robot banner.

**M4 — Sensitivity.** Jacobian heat map, per-slot ranking, "this policy ignores
slot N" callout, the no-training-variation handling for the three zero-std
command slots.

**M5 — Recurrence.** Iterate the last-action loop, classify converged /
periodic / unbounded, report period in ticks and milliseconds.

**M6 — Diff.** Paired bars, scalars, closed-loop divergence over time.

**M7 — AR.** True-scale ghost, foot-to-plane anchor, two-ghost diff with
millimetre site separation, the permanent kinematic-only label.

**M8 — Share and ship.** `StudioReport` export, PNG card, docs site on
Cloudflare Pages, the HF zoo, privacy manifest, icon, screenshots, App Review
notes, TestFlight, submit.

## Tasks

### M0 — DuckKit (in `craigm26/duckkit`)
- **T-001** D-1 `describe`; `load` refactored to describe + validate. Existing
  `DuckPolicyTests` must stay green unchanged — that is the regression proof.
- **T-002** D-2 expose normalization, layer widths, parameter count.
- **T-003** D-3 `inferTrace`; assert its `actions` equals `infer`'s bit for bit.
- **T-004** D-4 `jacobian`, tested against central differences to 1e-3 on the
  vendored `alpha_walking.onnx` at ten different observations.
- **T-005** D-5 `fingerprint`; stable across a re-serialized copy, different
  after one weight is perturbed by 1e-6.
- **T-006** D-6 `DuckGait.stages`; `frame` reimplemented on it; every existing
  `DuckGaitTests` case unchanged and green.
- **T-007** D-7 `DuckSimulation.State`; prove two simulations seeded with an
  identical state produce identical ticks for 500 steps.
- **T-008** D-8 move CanonicalJSON, Ed25519, `SigningKeyStore`, and a
  `CanonicalValue`-generic `Journal` into DuckKit; point CastorKit at it.

### M1 — Load and refuse
*T-010, T-011, T-012, T-013, T-014 and T-016 done 2026-08-28. 32 tests green on
the Pi against duckkit v1.4.0. Only T-015, the app target, is left — it needs
the Mac.*
- **T-010 DONE** Nine policies vendored, not seven — they were already sitting
  in `duck-sounds/site` from the simulator work, so nothing had to be fetched.
  Sizes and SHA-256 recorded. Note the README says plainly that the file digest
  and `DuckPolicy.fingerprint` answer different questions and are expected to
  differ. A test asserts all nine load: an inspector that cannot open the
  policies it ships with is not shippable.
- **T-011 DONE** `scripts/make_refusal_corpus.py`. Files are SYNTHESIZED, not
  mutated: renaming an op is four bytes where there were three, so every
  enclosing length prefix has to be recomputed, and writing that is writing a
  protobuf encoder anyway. Building each file from nothing also means it carries
  exactly ONE defect, which is what makes it fair to assert that the message
  names that defect. Eleven files, including a synthetic control that must load
  — without it the corpus would only prove the generator emits unusable bytes.
- **T-012 DONE** `PolicyReport` — describe + load outcome into the exact strings
  the app shows, with a third outcome the plan did not have: `.unreadable`, for
  bytes that cannot be walked at all and therefore have no structure to display
  beside the refusal. Tests assert the literal text, that every reason is
  distinct, and that every refusal carries the ops/params/widths it objected to.
- **T-013 DONE** `PolicyLibrary`. Identity turned out to need TWO rules, not
  one: a policy that loads is identified by its parameter fingerprint, so one
  network under two filenames is one entry — but a file that does NOT load has
  no parameters to digest, and the refusal screen is the whole point, so those
  fall back to a digest of the file. The rules cannot be merged. Ordering breaks
  ties on identity, because two different networks exported under one filename
  happens constantly during a run and the list would otherwise reshuffle between
  launches. Stored files are named by identity, so two people sending you
  `policy.onnx` do not collide.
- **T-014 DONE** `PolicySource`. `resolve/` and not `blob/` — the latter fetches
  the HTML page around the file and fails as a confusing protobuf error. https
  only. 8 MB cap, ten times a real policy. The full URL is a named field on the
  request so a screen has to have something to show before anything leaves the
  device. No token field, and a test asserts the surface contains no such word,
  so if one is ever wanted the argument happens there.
- **T-015** App target scaffold — `project.yml`, `Info.plist` with the
  `org.onnx.model` `UTImportedTypeDeclarations` **and** `CFBundleDocumentTypes`,
  `PrivacyInfo.xcprivacy`, Policies screen. First MacInCloud build.
- **T-016 DONE** `scripts/check_no_studio_math.sh`. Exits 0 while there is no
  app target. Still to wire into the Mac build with T-015.

### M2 — Observation editor
- **T-020** `ObservationSlot` — the 61-slot table: block, index, label, unit,
  display range, locked flag. Test that it agrees with `DuckObservation`'s
  layout for all 61 slots and that exactly slots 55, 56 and 60 are locked.
- **T-021** `ObservationEditor` — values, pins, per-block source, resolution
  order, emit via `DuckObservation.build`. Test that a pin survives 100 loop
  ticks unchanged and that unpinning restores loop control on the next tick.
- **T-022** `ZScoreStrip` — per-slot z, flagged set at |z| > 3, and the
  no-training-variation case where std ≈ 0.
- **T-023** SwiftUI: collapsed blocks with header summaries, command block
  expanded, rad/deg toggle, locked-slot rendering with the explanation.
- **T-024** CoreMotion source for gyro and gravity, `NSMotionUsageDescription`,
  graceful degrade to manual when motion is denied.

### M3 — Actions
- **T-030** `ActionReadout` — per-joint bar model carrying raw action, scaled,
  filtered, clamped, the travel limit expressed back in action units, and the
  limited flag.
- **T-031** `SaturationWindow` — ring buffer of N ticks; per-slot |a| median and
  p95; per-joint clip rate.
- **T-032** SwiftUI sticky action panel over the scrolling observation.
- **T-033** Low-pass toggle and α sweep with the not-the-robot banner.

### M4 — Sensitivity
- **T-040** `Sensitivity` — Jacobian presentation: column norms (per input),
  row norms (per action), the ranked "loudest inputs" list, the ignored-input
  callout at column norm below threshold.
- **T-041** Heat-map view, 61 wide by 14 tall, live while dragging.

### M5 — Recurrence
- **T-050** `Recurrence` — iterate, classify, report period. Tests: an
  artificial constant-output net converges in one step; a hand-built two-cycle
  is detected as period 2; a divergent case is reported unbounded rather than
  looping forever.
- **T-051** Trace view, 14 series, period annotated in ticks and ms.

### M6 — Diff
- **T-060** `PolicyDiff` — per-slot delta, ‖Δa‖₂, cosine similarity, argmax
  joint; closed-loop divergence series from a shared `DuckSimulation.State`.
- **T-061** Paired-bar view and the divergence chart.

### M7 — AR
- **T-070** `GhostPose` — segments, site markers, floor anchor from the lower
  foot. Test the anchor against the known home-pose numbers: feet at
  z ≈ 0.003 m, `head_camera` at z ≈ 0.244 m.
- **T-071** ARKit view: horizontal plane, single ghost at true scale, permanent
  kinematic-only label, `NSCameraUsageDescription`.
- **T-072** Two-ghost diff with per-site millimetre separation readout.

### M8 — Share and ship
- **T-080** `StudioReport` — canonical JSON carrying the policy fingerprint, the
  61 observation floats, the 14 actions, the pinned set, and the app version;
  hash-chained; optionally Ed25519-signed. A screenshot becomes a reproducible
  bug report.
- **T-081** PNG share card rendered from a report.
- **T-082** Docs site (Cloudflare Pages, `duck-studio.pages.dev`) with
  Cloudflare Web Analytics. Pages: home, **Bring your own policy** (the depth
  page the gates count), Why your export was refused, What is not real.
- **T-083** Hugging Face: `craigm26/microduck-policy-golden-vectors` (dataset,
  the observation→action pairs the tests use — mine, generated with
  onnxruntime) and a mirror card pointing at upstream for the policies
  themselves. Public GitHub companion `duck-studio-zoo`.
- **T-084** `golinks.craigm26.workers.dev/duckstudio/<src>` counters wired into
  every outbound link.
- **T-085** Icon, screenshots, App Review notes (see below), TestFlight.
- **T-086** ASC submit via `scripts/asc_submit.py` and the `appstore-submit`
  skill. App Privacy is UI-only; set Data Not Collected by hand.

## App Review notes (write these before submitting, not after rejection)

Reviewers will ask whether loading a `.onnx` from a URL is executing downloaded
code under 2.5.2. The answer, which goes in the notes verbatim:

> Duck Studio does not execute downloaded code. It reads a fixed set of
> numeric weights out of a file and multiplies them, using a forward pass
> compiled into the binary. The app refuses to load any file whose structure is
> not exactly the one architecture it supports — nine operations in a fixed
> order at fixed widths (61→512→256→128→14). Any other graph, including one
> differing by a single operation, is rejected at load with a message; there is
> no interpreter and no code path that can run an arbitrary computation. The
> file is data, and the app's most-used feature is the screen that explains why
> a file was rejected.

Pre-registered fallback, so this is a lookup and not a scramble: if the argument
is not accepted, ship Files-app import only (an unambiguous user-initiated
document open) within seven days and keep the URL loader out until it can be
argued separately.
