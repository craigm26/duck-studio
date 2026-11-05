# Build 90 plan: Duck Driver S1, a driver that runs on the phone

Read-only at duck-studio main a322b4e, 2026-11-04. Nothing in this plan has been built or run, and nothing has run on a real duck. Every latency, size and accuracy figure below is an estimate until a task measures it.

## Goal

Let the simulated duck walk to the ball using a small policy that runs on the phone, with no Dream key, no bridge and no bench machine. The policy is trained off the phone on Hugging Face Jobs, using the app's own LeRobot v2.1 recordings. It plugs into the existing `DreamRows` seam, so `DreamPilot` keeps its clamping, easing, warming waits and stop-then-end without any change.

For build 90, success means M1 passes: on a phone-run driver the sim duck reaches the ball in at least 6 of 10 runs from varied starts, where a zero-twist driver manages 0 to 1 of 10. Every run must end with stop and then end, and the measured infer p50 must be under 20 ms on the device.

Not in build 90:
- the real duck (phone drivers are sim only)
- multi-task or free-text conditioning
- MLX or Core ML for the driver (pending the owner's sign-off, see Open questions)
- training in the app

## Decisions (Craig, 2026-11-04)

1. **Runtime: plain Swift with Accelerate** (the judged design). `PolicyNet` stays a protocol, so a Core ML or MLX version can drop in later.
2. **Publishing: public driver repos, plus one pinned public demo driver** in the app, so testers can try it without recording. Public repos hold weights only, never a dataset of anyone's room.
3. **Recording: scripted.** A scripted expert drives the simulated duck to the ball and records the takes, instead of a person. This replaces T8 (below). The honest cost: the driver learns the script's way of driving, and the model card and the app say so.
4. **If M1 misses: wait.** Build 90 is not uploaded until the driver passes M1.

Head (open question 2) defaults to flatten with spatial softmax as the fallback; in-app training (6) stays at the command line until 91; drivers stay sim-only (7). Those were recommendations not overruled.

**T8 (replaced). Scripted expert recording. [Linux for the expert, Mac for the pictures]**
- `StudioKit/Sources/StudioKit/BallExpert.swift`: a pure function from the sim duck's pose and the ball's position (both known in BenchPeer) to a twist. Turn toward the ball, walk when roughly facing it, slow on approach, stop inside the reach radius, with seeded noise in start pose, heading and gains so the takes vary.
- Drive it through the same recorder path the app uses (`DreamDataset.Take` at 10 Hz, `SimHeadCameraRenderer` pictures, face blur no-op on renders), headless in the native macOS app on MacInCloud, where headless RealityRenderer is known to work.
- Acceptance: on Linux, BallExpertTests show the expert reaches the ball in at least 95% of 200 seeded sim starts (physics only, no pictures). On the Mac, 40 takes export and pass `dreamlabs-client` 1.0.14's `validate_dataset`, then upload with `hf upload` at a pinned commit.
- M1's zero-twist baseline is unchanged, and the expert's own success rate is logged beside the driver's as the ceiling.

## What the person sees

1. **Phone models screen (PhoneModelPickerView), new "Drivers" section.** It has a field for a Hugging Face repo id and an Add button. After Add, the steps show in order: resolving the commit, downloading (about 6 MB), checking the file hash, checking the shapes, replaying the test inputs on this phone, and Installed. If any step fails, plain words say which check refused and why, and nothing gets installed. Each installed driver shows its label, the task it knows, the pinned commit, its size on disk, the replay result, the first-inference ms, and a Delete button.
2. **Sim duck Dream sheet (SimHeadCameraFeed / DriveView).** This now shows a model picker and Run even with no Dream key. Phone drivers come first in the list, for example "On this phone · walk to the ball". The real duck's camera view (DuckCameraView) never lists phone drivers in build 90.
3. **When a phone driver is chosen:**
   - The prompt field is locked to the driver's task.
   - A caption reads "This driver knows one job: walk to the ball. It does not read what you type."
   - A line under Run reads "Driving as: walk to the ball".
4. **Run** drives the duck exactly as Dream-1 does: 20 rows at 10 Hz per ask, then stop and end. After the run, the summary shows act p50 and p95 in ms.
5. **Refusals the person can see:**
   - "too hot to drive" (thermal state .serious at start, or .critical during a run)
   - "the driver took too long" (any act over 1 s)
   - "this driver was trained on the simulated duck"
   - "no picture from the head camera yet"

## Architecture

### The model: ducknet-s1 (revised from the judged design)

- **Input:** the newest head frame and the frame 0.4 s earlier (DreamFrameWindow entries [-1] and [-3]; if the window holds fewer than 3, the newest is repeated). Each frame is 320x176 RGB, 2x2 average-pooled to 160x88 and normalised with the manifest's per-channel mean and std. The two frames are stacked into a 6x88x160 tensor.
- **Trunk:**
  - conv5x5 s2 p2, 6 to 16, ReLU (16x44x80)
  - conv5x5 s2 p2, 16 to 32, ReLU (32x22x40)
  - conv3x3 s2 p1, 32 to 64, ReLU (64x11x20)
  - conv3x3 s2 p1, 64 to 64, ReLU (64x6x10)
- **Head (the pooling fix):** flatten 64x6x10 to 3840, then Linear 3840 to 256, ReLU, then Linear 256 to 144. The 144 outputs are reshaped to 48x3 normalised actions. Flattening keeps left versus right, which global average pooling threw away.
  - About 1.1M parameters, about 4.4 MB in fp32, about 26M MACs per call.
  - If M1 shows circling or overshoot, the fallback head is spatial softmax keypoints (64 x,y pairs, Linear 128 to 256 to 144). It is a manifest arch bump ("ducknet-s1k"), not a new runtime.
- **Output:** 48 rows of [vx, vy, vyaw], un-normalised with the manifest's action mean and std.
- **No state input** in v1. The pilot's state is the last command (DuckDream.swift:403), and feeding it invites copy-forward. The manifest says `uses_state: false`.

### StudioKit (Linux-buildable; no CoreML, MLX, UIKit or ImageIO)

| File | Contents |
|---|---|
| `DuckDream.swift` (edit) | `Model` gains a public init and `public enum Kind: Sendable { case cloud, phone }`, defaulting to `.cloud` so existing call sites and tests are unchanged. `label` reads "On this phone · <label>" for `.phone`. `Chunk` gains `public init(rows:sessionID:)`. New `Words`: onPhone, oneJobCaption(task), drivingAs(task), tooSlow(ms), tooHot, simOnly, noPicture, notThisDriver, and the install refusals (arch, format, sha, shape, golden, task, path, size). DreamPilot itself is unchanged. |
| `SafeTensors.swift` (new) | Parses an 8-byte little-endian header length, then the JSON header, then raw F32. Refuses a bad length, an unknown dtype, overlapping or truncated ranges, and a header over 1 MB. |
| `PolicyManifest.swift` (new) | `PolicyManifest: Decodable`. Fields: arch, format, task, label, input [6,88,160], frame_offsets [0,-4], chunk 48, uses_state false, trained_on "sim", img_mean/std, act_mean/std, files {path: {sha256, bytes}}, dataset {repo, commit}, val_l1, baseline_zero_l1, baseline_repeat_l1, duckbatch_commit. `problem` refuses: an unknown arch or format, chunk not 48, uses_state true, trained_on other than "sim", a path containing ".." or starting with "/", any file over 16 MB, and a task failing `DreamDataset.taskProblem`. |
| `PolicyPrep.swift` (new) | Picks frames from the window by offset, pools 2x2, normalises, stacks into CHW, and un-normalises actions. `chunk(flat:rows:cols:)` refuses a wrong count, NaN or inf. |
| `DuckNetS1.swift` (new) | `protocol PolicyNet: Sendable { func infer(_ input: PolicyInput) throws -> [Float] }`. `DuckNetS1.load(SafeTensors)` checks every tensor name and shape. The forward pass runs each conv as im2col then GEMM, using `cblas_sgemm` under `#if canImport(Accelerate)` and a naive loop otherwise. |
| `DriverGolden.swift` (new) | `check(net:golden:tolerance:) -> Problem?`. On failure it names the worst row, column and error. |
| `LocalDreamRows.swift` (new) | `public actor LocalDreamRows: DreamRows`, initialised with `(net:, manifest:, modelID: "repo@commit", decode: @Sendable (String) -> [UInt8]?, now: @Sendable () -> Double, deadline: 1.0, thermal: @Sendable () -> Bool)`. Detailed below. |
| `DreamSourceChoice.swift` (new) | A pure function `pick(chosen:hasKey:bridgeAnswersDream:isSimDuck:) -> .phone / .direct / .bridge / .none`, plus `merge(cloud:phone:isSimDuck:)`, which lists phone models first and only on the sim duck, and never empties the list when there is no key. |
| `HubTraining.swift` (edit, optional for 90) | `DriveRecipe` and `requestBody(drive:)` mirroring `requestBody(skill:)`. `duckbatchCommit` (:38) is bumped only if this ships. |

**What `LocalDreamRows.act` does, in order:**
1. Refuse when the checkpoint is not the modelID.
2. Refuse when the thermal flag is set.
3. Refuse with noPicture when the head window is empty or does not decode.
4. Prep the frames, then infer.
5. Refuse with tooSlow when the call ran past the deadline.
6. Pass the output through `PolicyPrep.chunk`, then un-normalise.
7. Return `Chunk(rows:, sessionID: nil)` and record the timing.

The prompt is ignored, because the panel locks it to the task. `end()` does nothing, and `timings()` returns p50 and p95.

### DuckStudio app (no arithmetic, so `scripts/check_no_studio_math.sh` stays green)

| File | Contents |
|---|---|
| `PolicyFrames.swift` (new) | The decode closure: base64 JPEG to 320x176x3 RGB bytes, using ImageIO and CGContext. |
| `PhoneDriverStore.swift` (new, `@MainActor ObservableObject`) | Lists the installed drivers by reading disk every time; install state is never stored. Its methods are `add(repo:)`, `remove(_:)` and `loadNet(for:)`. |
| `PhoneModelPickerView.swift` (:55-88, edit) | The "Drivers" section. |
| `DreamRunView.swift` (edit) | `check` (:36-65) merges drivers through `DreamSourceChoice.merge`. `run` (:74) routes through `DreamSourceChoice.pick`; for `.phone` it builds `LocalDreamRows`. The thermal pre-check runs before `run`. The prompt locks when kind is .phone. The p50/p95 line shows after the run. keepsDreamFrames and the 1.2 s fill are unchanged. |
| `DuckStudioApp.swift` (:389-393, edit) | Next to `stopDownloadForSuspension`, cancel any driver download and delete its staging folder when the app goes to the background. |
| `DuckStudio/project.yml` | Build number 90, bumped by hand because the script does not bump it. No new packages. |

### Runtime

Inference runs on the CPU inside the actor, off the main actor.
- With Accelerate, the estimate is 2 to 5 ms per call on A17/A18. The naive loop is tens of ms. Both are unmeasured.
- The weights are 4.4 MB of CPU memory and never touch the MLX GPU cache, so PhoneModelRuntime's one-resident-model rule is not involved and no LLM unload is needed.
- It runs on iPhone, on the native macOS app and in the iOS Simulator, so the free compile gate covers the real code path.
- The pilot still asks every 20 rows, so the duck reacts on a 2 s loop. A pilot `horizon` parameter is a build-91 knob.

### Model store and integrity check

1. **Resolve.** `GET https://huggingface.co/api/models/<repo>` returns the commit sha (`sha`). The stored HF token goes as a Bearer header when one exists. The driver is always pinned to that sha, never to `main`.
2. **Download.** Fetch `policy.json`, `golden.json` and `model.safetensors` from `/<repo>/resolve/<sha>/...` with plain URLSession into a staging folder in tmp. The download streams with a byte counter and aborts any file that exceeds its declared bytes. It runs inside a background-task assertion. There is no swift-huggingface downloader and no `.lock` flock, so the 0xdead10cc kill cannot occur.
3. **Verify, in order, refusing at the first failure with plain words.** Any failure deletes staging.
   1. `PolicyManifest.problem` is nil (arch, format, chunk, paths, sizes, trained_on, task).
   2. The SHA-256 of every file matches the manifest. The hashing uses CryptoKit, and StudioKit compares the hex strings.
   3. The safetensors names and shapes match DuckNetS1 exactly.
   4. The golden replay: 3 fixed inputs run through the on-device DuckNetS1 must match golden.json within 1e-3 absolute (normalised units). The first-inference ms is recorded at the same time.
   5. The task passes `DreamDataset.taskProblem` (also covered in step 1; kept here as the last check before install).
4. **Install.** Move the files atomically to `Application Support/Drivers/<owner>__<name>@<sha>/`, marked isExcludedFromBackup. Application Support is used rather than Caches, so iOS cannot reclaim the files. Installing a newer commit of the same repo deletes the old folder.
5. **Remove.** Delete the folder. The size shown in the list is always measured from disk.

## Fit with Pollen's own policy stack (checked 2026-11-04)

Read from `pollen-robotics/microduck_rl` (AGENTS.md, develop) and `pollen-robotics/microduck` (`docs/policy-manifest.md`, main), both pushed on 2026-11-04.

- **Two layers, and we only build the top one.** Pollen's policies are joint-level: trained in mjlab with PPO at 50 Hz, 61 observations (48 proprioception plus a 13-value command block `[twist(3), head_pose(4), body_pose(6)]`), 14 joint actions, exported to ONNX with the normalizer baked in, and run on the robot by `robotd`. Duck Driver S1 is a high-level driver: camera in, a twist out at 10 Hz, which the robot's walker turns into steps. Nothing here retrains or replaces the walker.
- **Keep the manifests apart.** Pollen's schema-2 `manifest.json` describes a joint policy, and `robotctl policy add` refuses one whose `obs_len` is not 61 or whose `action_len` is not 14. A driver must never be published as `<user>/microduck-<name>` with a `manifest.json`, or a robot could try to load it. Drivers use `duck-driver-*` repos and `policy.json`, as planned above.
- **Zero is a trained command.** The walker is trained on the exact all-zero twist (`zero_command_prob`), which is the robot's idle. So a driver that outputs zeros when it is unsure gets a trained standing behaviour, and the pilot's stop at the end lands on that same idle state.
- **Our easing does not break their "unfiltered" rule.** Pollen trains without an action low-pass and warns against adding one at run time. DreamPilot's 3-row easing smooths the twist command, which is the walker's input, not its joint actions, so the walker sees ordinary command changes. Say this in the PR so nobody "fixes" it at the joint level.
- **Head pose is the obvious next output.** The walker already takes `head_pose(4)`. A later driver could look as well as walk, once the recorder saves head commands. Not in build 90.
- **Provenance the way Pollen now does it** (`microduck_rl` 3b8759e, "Training bundles"). `bc_ducknet.py` writes, beside the driver, a training bundle: the full PyTorch checkpoint, the duckbatch commit, any uncommitted diff, the exact command line, the dataset repo and commit, the parent checkpoint if warm-started, and the SHA-256 of `model.safetensors` and `ducknet-s1.onnx` after a weight-for-weight check that both came from that checkpoint. `policy.json` names the bundle. Retraining after a DAgger-lite round warm-starts from an `hf://<owner>/<repo>@<sha>/<path>` checkpoint spec, the same form Pollen uses. Since driver repos are public, the bundle holds no recorded pictures, only weights and provenance.
- **Export ONNX too.** The training job should also write `ducknet-s1.onnx` beside the safetensors (a few lines in `bc_ducknet.py`). It costs nothing now, and it is Pollen's deployment format, so the same driver could later run on the robot's own computer next to the walker, with no phone in the loop.

## Training recipe

Training never runs on the phone or on the Pi.

### Dataset prep (from the app's exports)

1. In the native macOS app or on an iPhone, open the sim duck. Start DreamRecorder under the task "walk to the ball" and drive to the ball with the Drive sheet joystick. DreamRecorder saves `peer.lastCommand()` at 10 Hz beside each face-blurred frame (DreamRecorder.swift:72, 97, 211).
   - Record 30 to 40 takes from varied start positions and headings, for 20 to 40 minutes in all.
   - End each take when the duck reaches the ball.
2. Export. `DreamRecorder.export()` (:123) writes a LeRobot v2.1 zip.
   - The layout comes from DreamDataset: `meta/info.json`, `meta/episodes.jsonl`, `meta/tasks.jsonl`, `data/chunk-000/episode_NNNNNN.parquet`, and `videos/chunk-000/observation.images.head/episode_NNNNNN.mp4`.
   - Read-only check: the Dream export is offered as a file (DreamRecorder.swift:278-283) and is not wired to HuggingFacePublish. HuggingFacePublish can create dataset repos, but no call site sends this zip. Plan on the Mac upload in step 3.
3. On the Mac, upload it:
   ```
   unzip dream-export.zip -d ~/duck-drive/walk-to-ball
   hf repo create craigm26/duck-drive-walk-to-ball --repo-type dataset --private
   hf upload craigm26/duck-drive-walk-to-ball ~/duck-drive/walk-to-ball . --repo-type dataset
   ```
   Record the commit sha the upload prints. The training job pins to it.

### Script

`duckbatch/scripts/bc_ducknet.py` is a uv script with inline dependencies: torch, torchvision, av, pyarrow, safetensors, huggingface_hub, numpy. It does not use lerobot.

- **Reading.** It reads the v2.1 files directly and keeps only episodes whose task equals `--task`. It decodes each mp4 with PyAV at 320x176 and asserts that the frame count equals the parquet row count, failing loudly otherwise.
- **Sample.** Input frames t and t-4 (the start of an episode clamps to frame 0). The target is actions t through t+47, padded at the end of an episode by repeating the last row, with a mask.
- **Augmentation:**
  - JPEG re-encode at quality 85, to match `DuckCameraFeed.dreamJPEG`
  - brightness and contrast jitter of plus or minus 10%
  - random shifts of up to 4 px
  - no horizontal flip, because it would flip the vyaw sign
- **Loss and schedule.** Masked L1 on normalised actions; AdamW at 3e-4 with a cosine schedule; 20k steps at batch 64. Split 90/10 by episode.
- **Honest numbers.** It reports validation L1 for the model, for a zero-action baseline and for a repeat-last-action baseline.
- **Golden-only mode.** `--golden-only --out-dir DIR` writes tiny random weights, policy.json and golden.json for the StudioKit test fixture, with no dataset and no GPU.
- **Outputs**, pushed to the model repo `craigm26/duck-driver-walk-to-ball` (private):
  - `model.safetensors` (fp32)
  - `policy.json` (the manifest fields above, including all three L1 numbers and the dataset repo and commit)
  - `golden.json` (3 fixed inputs and their PyTorch fp32 outputs)
  - `record.json`
  - `README.md` (a model card stating it was trained on the simulated duck's camera only and never checked on a real duck)

### Commands

Run these from the Mac, never the Pi. Pin the script at the duckbatch commit that adds it. Check the flags against `hf jobs uv run --help` before the first run.

```
# Free fixture, on the Mac CPU:
uv run duckbatch/scripts/bc_ducknet.py --golden-only --out-dir StudioKit/Tests/StudioKitTests/Fixtures/ducknet-s1

# Smoke run on HF, about $0.05: 200 steps, proves reading, decoding and the push.
hf jobs uv run --flavor t4-small --timeout 30m --secrets HF_TOKEN \
  https://raw.githubusercontent.com/craigm26/duckbatch/<COMMIT>/scripts/bc_ducknet.py \
  --dataset craigm26/duck-drive-walk-to-ball --dataset-revision <DATASET_SHA> \
  --task "walk to the ball" --steps 200 --out craigm26/duck-driver-smoke

# Real run, about 15 to 30 min and about $0.25 to $0.50 (estimate):
hf jobs uv run --flavor t4-small --timeout 1h --secrets HF_TOKEN \
  https://raw.githubusercontent.com/craigm26/duckbatch/<COMMIT>/scripts/bc_ducknet.py \
  --dataset craigm26/duck-drive-walk-to-ball --dataset-revision <DATASET_SHA> \
  --task "walk to the ball" --label "walk to the ball" --steps 20000 --batch 64 \
  --out craigm26/duck-driver-walk-to-ball

hf jobs logs <JOB_ID>
```

Use l4x1 (already `HubTraining.flavor`) if t4-small is unavailable. Add a `records/d001-walk-to-ball/` entry to duckbatch with the job id, the commits and the three L1 numbers.

## Ordered tasks

The labels say where each task runs:
- **[Linux]**: StudioKit `swift test`. Targeted filters only on the Pi (`--filter`, under a memory cap, one job at a time); the full suite on the Mac or MacInCloud
- **[Mac gate]**: `xcodebuild archive ... CODE_SIGNING_ALLOWED=NO` for the iOS and macOS slices
- **[Device]**: an iPhone or the native macOS app
- **[HF]**: Hugging Face Jobs

Every task ends with all existing StudioKit tests still green.

**T0. Owner sign-off (no code).**
- Answer Open questions 1 and 2.
- Acceptance: the decision is written into memory duck-studio-phone-driver.md.

**T1. SafeTensors parser. [Linux]**
- Acceptance: SafeTensorsTests pass. They cover a hand-built buffer that parses, and refusals for a bad header length, an unknown dtype, truncated data, overlapping offsets and an oversized header.

**T2. PolicyManifest and PolicyPrep. [Linux]**
- Acceptance: PolicyManifestTests refuse each bad field (arch, format, chunk 47, uses_state true, trained_on "real", "../x", an absolute path, an oversized file, a task with a tab).
- Acceptance: PolicyPrepTests cover frame choice for windows of 1, 2, 3 and 9 frames; 2x2 pooling and normalising on known pixels; the un-normalise round trip; and `chunk(flat:)` refusing NaN, inf, 143 and 145 values.

**T3. bc_ducknet.py golden-only mode, and the fixture. [Mac CPU]**
- Add the script to duckbatch and run `--golden-only` to make `Fixtures/ducknet-s1/`.
- Acceptance: the fixture folder holds model.safetensors, policy.json and golden.json, and the script's own self-check (load the safetensors, re-run, compare) passes.

**T4. DuckNetS1 forward and DriverGolden. [Linux, then Mac]**
- Acceptance: DuckNetS1Tests refuse a missing tensor and a wrong shape, and the forward pass matches the T3 fixture within 1e-4 on Linux (naive loop).
- Acceptance: on the Mac, the Accelerate and naive paths agree within 1e-5.
- Acceptance: DriverGoldenTests pass at the tolerance and refuse a 1e-2 perturbation, naming the row and column.

**T5. LocalDreamRows, DreamSourceChoice and the DuckDream edits. [Linux]**

Acceptance: these tests pass, using FakeNet with PlainLink and Clock (DreamDirectTests :133, :141) and modelled on `testThePilotDrivesALinkWithNoDreamVerbsAtAll` (:160-165):
- 20 clamped, eased moves per chunk, then stop, then end.
- One infer per 20 rows.
- The net throwing still ends with stop and end.
- A decode failure and an empty window each refuse with noPicture.
- A checkpoint mismatch refuses with the net's call count at 0.
- A 1.2 s fake infer refuses with tooSlow.
- The thermal flag refuses.
- The prompt is ignored.
- `timings()` p50 and p95.
- DreamSourceChoice gives .phone with no key and no bridge on the sim duck, never offers phone models on the real duck, gives .direct with a key and .bridge with only the bridge, and merge keeps phone models first.
- Model(kind: .phone) has the right label, the `Chunk` public init works, the Words contain no em-dashes, and the completeness grep still passes.

**T6. App wiring: PolicyFrames, PhoneDriverStore, picker section, DreamRunView routing, suspension hook. [Mac gate]**
- Acceptance: the iOS and macOS archives build with `CODE_SIGNING_ALLOWED=NO`.
- Acceptance: `scripts/check_no_studio_math.sh` passes.
- Acceptance: project.yml shows build 90.

**T7. Install path against the fixture repo. [HF, then Device]**
- Push the T3 fixture to a throwaway private model repo, `craigm26/duck-driver-fixture`.
- Install it on the macOS app and on an iPhone.
- Acceptance: all five checks pass, and the first-inference ms is shown.
- Acceptance: corrupting one byte of the safetensors (by pushing a second commit) refuses at the sha256 step with the right words.
- Acceptance: backgrounding during the download leaves nothing installed.

**T8. Record the dataset. [Device]**
- Record 30 to 40 takes of "walk to the ball" on the sim duck, export, and upload with `hf upload`.
- Acceptance: the dataset repo exists at a pinned commit, and its `meta/episodes.jsonl` lists every take under that task.

**T9. Smoke job, then the real training job. [HF]**
- Acceptance: the smoke job reaches COMPLETED and pushes duck-driver-smoke.
- Acceptance: the real job reaches COMPLETED, and its record.json shows a validation L1 below both the zero baseline and the repeat-last baseline. If it does not beat both, stop and see the kill criteria.

**T10. M1 on the device. [Device]**
- Install duck-driver-walk-to-ball, then open the sim sheet with no Dream key and no bridge.
- Acceptance:
  - at least 6 of 10 runs from varied starts reach the ball within the soccer reach radius
  - a zero-twist driver run under the same starts manages 0 to 1 of 10
  - all 20 runs end with stop then end in the event log
  - p50 under 20 ms on the iPhone
  - the same driver also runs in the iOS Simulator (correctness only)
- Log the results in duckbatch records/d001.

**T11. The build-90 upload. [Mac, one TestFlight upload]**
- Only after T1 to T10 are green. First ask "what else is queued for Duck Studio?" and batch it in.
- Acceptance: one upload, ASC shows build 90 VALID, and memory records it.

T7 and the HubTraining DriveRecipe (in-app training launch) are the parts that can be cut if the session runs long. The recipe is optional for 90, and T7 can fold into T10.

## Rescue ladder if M1 misses

Cheapest first. Each rung is judged by the same M1 test (10 seeded sim starts, the same seeds every time), and the next rung starts only if this one misses.

**Rung 1. Diagnose, then edit the output bias (no training).** After the idea in Weight-Space Programming for VLAs (github.com/Geeksongs/Weight-Space-Programming-VLA, 2026-11-04). There, one number added to SmolVLA's output bias took one LIBERO task from 42 to 64 of 100. That is one task, one model and no peer review, so it is a cheap thing to try, not a promise. The repo has no license, so only the idea is used, not its code.

- **Diagnose from what the driver did, not from guesses.** Each M1 run logs its rows (the twists the driver asked for), the duck's pose and the ball's position at 10 Hz. A failure counts as systematic when at least 3 of the failed runs share one signature: a steady sideways drift (mean vy or vyaw offset while the ball is dead ahead), turning too little (heading error to the ball that shrinks slower than the expert's), or overshoot (still walking inside the reach radius).
- **Write the edit.** The last layer is `Linear 256 → 144`, reshaped to 48 rows × [vx, vy, vyaw]. An edit adds one constant per column to that layer's bias, the same constant to all 48 rows, in normalised action units: for example `vyaw += c` for drift, or `vx -= c` for overshoot. Try at most two magnitudes per signature, chosen from the logged error, never by sweeping against the M1 seeds.
- **Store it as a patch, not new weights.** `edit.json` names the base driver (repo and commit), the tensor, the column, the constant and the reason in one sentence. A patched driver is its base plus the edit: the store applies it after the base passes its SHA-256 and golden checks, then replays golden inputs with the edit applied against golden outputs the edit script writes. The patch has its own SHA-256 in policy.json, so it can be reviewed, reverted or stacked.
- **Do not overfit the test.** The diagnosis uses the logs of the failed M1 runs. The check that counts is M1 on a fresh set of 10 seeds the diagnosis never saw, and its result is reported beside the original.
- **Code.** `DriverEdit` in StudioKit (parse, apply to `DuckNetS1`'s output bias, refuse an unknown tensor, a column out of range or a non-finite constant), with Linux tests. `bc_ducknet.py --edit` writes `edit.json` and the edited golden outputs. About half a session.

**Rung 2. One round of DAgger-lite and a retrain**, warm-started from the driver's checkpoint (`hf://` spec, per the provenance bundle). The scripted expert labels the states the driver actually visited, which suits a scripted expert well: it can label any state.

**Rung 3. The spatial-softmax head** (`ducknet-s1k`), retrained.

**Then K2:** build 90 waits.

### Round 3 expert (2026-11-04)

Round 2's driver (`craigm26/duck-driver-walk-to-ball-v3`) reached 10 of 20 balls and stopped at none. Both causes were the expert's, so round 3 changes the expert before any DAgger round:

- **The stop line is inside the picture.** `BallExpert.reach` is 0.35 m (was 0.20). Measured by projecting the ball through `SimHeadCamera.pose` for 6,388 recorded rows and checking against the Mac's rendered frames (centre row within 0.3 px on average): the ball's last pixels leave the bottom of the head picture at 0.29 to 0.30 m; at 0.34 to 0.36 m its top half shows (median 715 to 996 of 320 by 176 pixels). The duck stands only with the ball in the 30 degree cone, so no standing row is a picture of bare floor.
- **No command in the walker's dead band.** Measured from rest on duckbench: vx 0.20 moves 0.003 m/s, 0.22 moves 0.038, 0.25 moves 0.086; vx 0 with vyaw 1.0 turns 12 degrees in 3 s. Forward is now 0 or at least 0.25 (`walkStart`), never eased; no sideways weave; a steer under 0.1 rad/s is 0.
- **M1 logs keep the bench's full state per tick**, so the DAgger round can draw the driver's own pictures.
- **takes-v4:** 240 takes, seeds 20001 to 20242 (2 dropped: a ball the bench set rolling ended under a standing duck's camera), 25,531 rows, 3,840 standing rows (16 a take, all 0.32 to 0.35 m from the ball), mean 10.6 s. Expert on M1 seeds 5001 to 5010: 10 of 10 reached and stopped, mean 6.9 s to reach.

### Round 3 result (2026-11-04)

- **Data.** dataset-v4 rendered on the Mac (240 episodes, 25,531 frames, Dream validator ok, video frames = take rows in every episode), private `craigm26/duck-drive-walk-to-ball-v4`. A standing frame at 0.337 m shows the top half of the ball, as measured.
- **Training.** t4-small now fits (pictures 2.16 GB with duckbatch #22's uint16 store). Driver public `craigm26/duck-driver-walk-to-ball-v4`: val L1 0.139 (zero 0.963, repeat-first 0.341). Round 2 was 0.358.
- **M1, seeds 5001 to 5010 and 6001 to 6010:**

| who | reached | stopped | parked | reached and parked | time to reach (mean) | first seen (mean) |
|---|---|---|---|---|---|---|
| driver v4 | 12 | 0 | 14 | 7 | 21.3 s | 12.5 s |
| zero | 1 (6007, the ball rolls in) | 1 | 1 | 1 | 0.1 s | |
| expert | 20 | 20 | 20 | 20 | 8.5 s | 2.7 s |

- **PASS, narrowly** (rule: reached at least 12 and stopped or parked in most of those; 7 of 12). No DAgger round was run.
- **What the misses are.** All 8 misses parked 0.36 to 0.41 m from the ball, 1 to 6 cm short of the 0.35 m line. No run froze away from the ball (round 2: 14 of 20). The driver's stand is small, not zero (last commands vx 0.00 to 0.05), so "stopped" scores 0 though the duck is still.
- **What the walk-throughs are.** 5 reached runs ended walking (5006, 5008, 5009, 6002, 6007). Most of them had the ball in view under 15% of the time: the search arc carried the duck onto a ball it never saw. The search turn is still softened (toward the hidden ball 0.2 to 0.5 of the expert's full turn).
- **Ready for the next round:** `scripts/dagger_relabel.py` turns M1 driver logs into takes with expert labels (rows with the ball under the camera dropped, standing capped at 16 rows).

### Output snap (2026-11-04)

`DriverSnap` puts each row back on the expert's commands: forward under 0.12 is 0, 0.12 to 0.25 is 0.25, a turn under 0.1 is 0, sideways is 0. `DriverPrep.rows` applies it, so the phone and M1 play the same rows. v4 has no `snap` block in its policy.json, so its numbers are pinned by the SHA-256 of its weights; a later driver carries a block. `-driver-raw` (`m1_trial.py --raw`) plays the rows as answered, so one build judges both arms. `scripts/m1_table.py` prints the table from the logs.

Confirmed from the run logs, not the code: every row of every snapped ask (1,200 chunks over the 40 runs) is on the expert's command set (100.0%); unsnapped 0.0%. The trial prints which snap it loaded. The pilot's 3-row blend into each new chunk still runs after the snap; those rows are not on the set, and that is the pilot's job.

| who | seeds | reached | parked | reached and parked | stopped | time to reach (mean) | first seen (mean) | search turn |
|---|---|---|---|---|---|---|---|---|
| v4 unsnapped | fresh 7001-7020 | 9 | 17 | 7 | 0 | 15.3 s | 9.8 s | 0.33 |
| v4 snapped | fresh 7001-7020 | 13 | 17 | 10 | 4 | 20.4 s | 13.5 s | 0.31 |
| v4 unsnapped | standard 5001-5010, 6001-6010 | 12 | 14 | 7 | 0 | 21.3 s | 12.5 s | 0.33 |
| v4 snapped | standard | 17 | 15 | 12 | 6 | 21.5 s | 15.4 s | 0.30 |
| zero | fresh | 0 | 0 | 0 | 0 | | | 0 |
| expert | fresh | 20 | 20 | 20 | 20 | 8.8 s | 2.5 s | 1 |

The snap reaches more balls and stops some. It does not touch the search turn, which is a share of the expert's full turn while the ball is hidden, so a DAgger round follows.

### DAgger round and the stand latch (2026-11-05)

- **Runs.** v4 snapped on seeds 30001 to 30040 (28 reached). `dagger_relabel.py`: 40 takes, 18,329 rows (9,925 search, 8,069 approach, 335 stand).
- **Data.** takes-v5 = takes-v4 + those, 280 episodes, 43,860 frames, Dream validator ok. Private `craigm26/duck-drive-walk-to-ball-v5`@8767a57.
- **Training.** t4-small, 30,000 steps, 17 minutes, about $0.12. Public `craigm26/duck-driver-walk-to-ball-v5`: val L1 0.125 (zero 1.249, repeat 0.284). Weights commit 306f2a6, snap block in policy.json at fe94d4a (the revision to pin).
- **First M1 on v5.** Search fixed: turn 0.82 of the expert's, first sight 2.8 s (v4 13.5 s), reached 20 of 20. But parked 1 of 20: at the line it said stand on row 0 and walk by row 19, and the pilot plays 20 rows of each chunk.
- **The latch.** `DriverSnap.chunk`: from the first row whose forward snaps to 0, every row is still. BallExpert's stand is latched and never turns, so this is its command set too. The next ask looks again.
- **Because seeds 7001-7020 showed the fault,** the latch was also judged on seeds 8001-8020, used by nothing before it.

| who | seeds | reached | parked | reached and parked | stopped | time to reach (mean) | first seen (mean) | search turn |
|---|---|---|---|---|---|---|---|---|
| expert | 7001-7020 | 20 | 20 | 20 | 20 | 8.8 s | 2.5 s | 1 |
| v4 snap + latch | 7001-7020 | 13 | 18 | 11 | 18 | 18.9 s | 13.5 s | 0.31 |
| v5 snap, no latch | 7001-7020 | 20 | 1 | 1 | 0 | 10.9 s | 2.8 s | 0.82 |
| **v5 snap + latch** | 7001-7020 | 19 | 13 | 12 | 13 | 12.6 s | 2.8 s | 0.82 |
| v5 snap, no latch | standard | 20 | 2 | 2 | 0 | 9.9 s | 3.2 s | 0.82 |
| **v5 snap + latch** | standard | 20 | 14 | 14 | 14 | 9.9 s | 3.2 s | 0.82 |
| expert | 8001-8020 | 20 | 20 | 20 | 20 | 8.5 s | 2.3 s | 1 |
| zero | 8001-8020 | 0 | 0 | 0 | 0 | | | 0 |
| v4 snap + latch | 8001-8020 | 15 | 16 | 11 | 16 | 17.5 s | 10.1 s | 0.30 |
| **v5 snap + latch** | 8001-8020 | 20 | 14 | 14 | 14 | 12.7 s | 2.7 s | 0.78 |

**Pick: v5 with snap and latch.** On both sets it finds the ball in the expert's time and reaches nearly every one, where v4 reaches 13 to 15.

**What is still wrong.** v5 arrives too hard: the root came within 0.2 m of the ball in 13 of 20 runs on 8001-8020, so it often pushes the ball (0.21 m on average) before standing, and 6 of 20 were still walking at the end. "Parked" there means parked after the push. Likely cause, not yet tested: the DAgger takes keep only 335 stand rows, and a stand label is followed by whatever the driver did next, so the chunks teach "stand now, walk later". The next relabel should end a take at each stand with a full standing tail.

## Risks and kill criteria

**Risks**
1. **Behaviour cloning from 30 to 40 takes may not generalise.** The duck may overshoot or circle. Mitigations: varied starts, the 2-frame input, the flatten head, then the rescue ladder below (a bias edit first, then one round of DAgger-lite) before any bigger model.
2. **Train/serve pixel mismatch.** Training sees H.264 frames and the phone sees JPEG q0.85. Both are face-blurred (verified in DreamRecorder). The JPEG augmentation covers the remaining gap.
3. **The golden tolerance (1e-3) between Accelerate and PyTorch is unverified.** T4 measures it on the Mac first.
4. **The 2 s reaction loop.** This is acceptable for walking to a ball. A `horizon` parameter on DreamPilot changes tested behaviour and is a build-91 item.
5. **This departs from the letter of "MLX or Core ML".** The `PolicyNet` protocol lets an MLXNN or Core ML version of the same weights drop in without touching the pilot or the panel.
6. **Private repos need the HF token.** Without a token, the add is refused with clear words.
7. **The real duck is out of scope.** A sim-trained driver on a real duck could be unsafe. Build 90 gates drivers to the sim duck by manifest (`trained_on`) and by frame source.
8. **TestFlight budget.** Build 90 gets one upload, and only after M1.

**Kill criteria** (stop and report rather than push on)
- **K1.** After T9, the validation L1 does not beat both baselines. If a spatial-softmax head plus one DAgger-lite round also fails to beat them, drop S1 and reopen ACT on Core ML for build 91.
- **K2.** At T10, fewer than 6 of 10 runs succeed after the whole rescue ladder (a bias edit, then one DAgger-lite round and one retrain). Then build 90 waits (Craig's decision: no upload until M1 passes), and the result is recorded honestly.
- **K3.** The golden replay cannot be brought under 1e-3 on the device after checking the layout and summation order. That is a correctness bug, and no driver ships until it is fixed.
- **K4.** Device infer p50 is over 50 ms, or any act goes over 1 s. Profile it before shipping. Do not raise the deadline to pass.
- **K5.** Any task needs the Pi for more than targeted StudioKit tests. Stop and move the work to the Mac.

## Open questions for the owner

1. **Runtime.** Is pure Swift with Accelerate (CPU, on the phone, Linux-testable, runs in the Simulator) acceptable for build 90, given your decision said "MLX or Core ML"?
   - If not, the fallback is the same CNN exported to Core ML in the training job. The forward pass then cannot be checked on Linux, but the on-device golden replay stays.
2. **Head.** Is flatten (about 1.1M params, about 4.4 MB) acceptable as the default, with spatial softmax as the fallback? Or do you want spatial softmax first?
3. **Publishing.** Should driver repos be private, which needs the HF token in the app, or public, which holds weights only and no user data? Should the app pin one public demo driver for testers without a dataset?
4. **Recording.** Will you record the 30 to 40 takes yourself on the macOS app, or should a tester do it?
5. **If M1 misses.** Should build 90 ship with the Drivers section hidden, or wait?
6. **In-app training.** Should the in-app "Train a driver" button (`HubTraining.requestBody(drive:)`) be in build 90, or should training stay at the Mac command line until 91?
7. **The real duck.** Confirm that phone drivers stay sim-only until a separate, gated decision, in line with `enabled_on_robot = false`.

Files read: `/home/craigm26/projects/duck-studio/StudioKit/Sources/StudioKit/DreamDataset.swift`, `/home/craigm26/projects/duck-studio/StudioKit/Sources/StudioKit/HubTraining.swift`, `/home/craigm26/projects/duck-studio/StudioKit/Sources/StudioKit/HuggingFacePublish.swift`, `/home/craigm26/projects/duck-studio/DuckStudio/Sources/DreamRecorder.swift`, `/home/craigm26/projects/duck-studio/DuckStudio/project.yml` (location only).

## In the app (2026-11-05)

The Auto card is live on the practice duck: Get (4.4 MB), then Go, then the one Stop and the 60 s Auto cap.

**Install.** `DriverRelease.walkToBall` pins `craigm26/duck-driver-walk-to-ball-v6` at `5985110` (it was v5 at `fe94d4a` when this was written and measured; see the v6 section at the end), plus the SHA-256 of `policy.json` and of the weights. `DriverInstaller` fetches the three files over plain URLSession from public resolve URLs, with no token and no lock. It checks sizes and hashes, writes a side folder, runs `DriverTrial.load` on it (the golden replay included) and only then renames it into Application Support. `status()` re-reads the disk at launch and removes a damaged driver. Mac, real download with `DuckStudio -driver-get-check`: installed in 1.2 s, Cancel left nothing, delete left nothing.

**Three things found while wiring it.**
1. `/ball` was not in `DuckBench.routes`, so the phone's bench would have answered 404. It is now, with a factory (`DuckDrive.placeBall`) and the factory test.
2. Nothing put the walker on the servos. `/reset` leaves the standing policy, and the driver's commands would have moved nothing. `BenchPeer.layOut` is now M1's start: reset, `alpha_walking.onnx`, the ball, and the 1.2 s pre-roll as one `/stop`, whose answer the peer keeps, so the head camera has the placed ball from its first picture.
3. `DreamRunModel.run` called the Stop (`halt()`) as `stopDriving`, and `halt()` stops a running Dream run, so a goal started from Play cancelled itself. Both Play panels now use `stepAside()`.

**The ball.** The head camera draws `live.ball` at the bench's radius. The stage draws its ball prop (100 mm across) and moves it to the same `live.ball` each frame. `DreamPracticeWorld`'s fixed ball is only for a bench with none, so the app never shows it. A world with stairs is refused in words: the head camera does not draw them.

**Is it reachable from where the app starts?** Yes for reaching, and it stops less often. `--app-start` was parsed and never read until the round 1 review, so the first table written here was a rerun of the M1 start, not the app's. Fixed and rerun on seeds 8001-8020 (`~/scratch/ball-takes/m1-app2`):

| Arm | Reached | Parked | Stopped | Reach s | First sight s | Ball push m |
|---|---|---|---|---|---|---|
| expert | 20 | 20 | 20 | 8.5 | 2.4 | 0 |
| v5 snap+latch | 20 | 12 | 12 | 13.1 | 2.7 | 0.29 |

The start is the same calls as `layOut`, with the 1.2 s pre-roll as one `/stop`. The driver arm then also stands through `DriverTrial`'s own pre-roll, because the lockstep trial needs those ticks to draw its window, so its first ask is near t=2.9 where the app's comes just after 1.2. That is the closest this harness comes, and it is not the wall-clock path. The card takes the lower number: reached 20 of 20, stopped there 12 of 20. The root came within 0.2 m of the ball in 15 of 20, and 8 of 20 were still walking when the 60 s ended.

**A run ends when the duck parks.** `BallRunWatch` reads the bench's ground truth for the sentence afterwards and to end the run; it never steers. The rule is M1's parked (within 0.40 m, root moved at most 0.02 m in a second), checked at every moment rather than at the end. Replaying the 20 `m1-app2` logs through it: 16 runs park at some moment, all 16 had reached the ball by then, and 12 had not moved it. The other 4 never park, and go to the time limit. That is a replay, and the app has not run it.

**The real duck stays out.** `mediad`'s `/frame` is wired for Dream-1, but this driver has only seen the drawn stage. The card says "Practice duck only for now" and has no Go there (risk 7 above).

**Not run:** any of this on a phone. The Mac runs are the shipped pilot, driver and renderer in lockstep with the bench; the wall-clock path (`SimHeadCameraFeed` at 5 fps with the phone's own bench) has compiled and has not been driven.

## The hard arrival: driver v6 (2026-11-05)

**The change.** `dagger_relabel.py` now ends a take at the expert's first stand: that row and the next 15 are stand (16 in all, as a recorded take does), on the pictures the driver really saw, and every later tick is dropped. The model trains on 48 rows from each picture, and a v5 stand label was followed by whatever the driver did next.

**Data.** The same 40 v4 runs (seeds 30001 to 30040): 15,684 rows (8,795 search, 6,521 approach, 368 stand). Only 23 of the 40 ever reach a stand, so the stand rows rose from 335 to 368; what changed is that they now sit in unbroken tails. 2,645 rows after a stand are gone. The `m1-app2` v5 runs were not added.

**Not rendered again.** The Mac was held by the build 93 upload when the data was cut, expected for 20 more minutes, and waiting for it would have left no time for both arms. It came free sooner, about 04:11. Every kept row already had its picture in `dataset-v5`, matched by sim time (none missing, no held frames), so `dataset-v6` is v5 with the 40 DAgger episodes cut and copied as YUV into a new H.264 at crf 12 (mean pixel change 0.05 to 0.43 of 255 on the two episodes sampled). 280 episodes, 41,215 frames, Dream validator ok. Private `craigm26/duck-drive-walk-to-ball-v6`@7c84d1f. Tool: `~/scratch/round2/make_v6.py`, not in this repo. takes-v6 = takes-v4 + those 40.

**Training.** t4-small, 30,000 steps, 990 s, about $0.11, duckbatch 2dfec0b. Public `craigm26/duck-driver-walk-to-ball-v6`: val L1 0.118 (zero 1.221, repeat 0.279). Snap block in policy.json at 5985110, the revision pinned.

**Judged on seeds 9001-9020, in no training take (seed 9001 alone had one earlier smoke run), from the app's start (`--app-start`), both with snap and latch.** Same app build. Logs `~/scratch/ball-takes/m1-9001`.

| Arm | Reached | Parked | Reached and parked | Stopped | Reach s | First sight s | Ball push m | Pushed over 5 cm | Within 0.2 m | Walking at end |
|---|---|---|---|---|---|---|---|---|---|---|
| expert | 20 | 20 | 20 | 20 | 8.7 | 2.3 | 0 | 0 | 0 | 0 |
| v5 snap+latch | 20 | 14 | 14 | 14 | 14.4 | 2.5 | 0.23 | 8 | 14 | 6 |
| **v6 snap+latch** | 19 | 18 | 17 | 18 | 11.7 | 2.5 | 0.17 | 9 | 10 | 2 |

**Pick: v6.** The rule was parked clearly higher, ball push lower, reached at least 19. Parked 18 is above all five v5 scores with the latch (12 to 14), and it parks 6 seeds v5 does not, against 2 the other way. On the 19 seeds both reached it gets there 2.6 s sooner on average (11.7 s against 14.3 s), though it is quicker on only 10 of them, slower on 7 and level on 2. It ends walking in 2 runs, not 6.

**How much this proves.** Less than the means say. The lower push leans on one v5 run that shoved the ball 1.18 m; seed by seed v6 pushes less on 7 and more on 6, the median is 0 for both, and it still moves the ball over 5 cm in 9 of 20. It bumps as often as v5. It stops better and walks off less. So the hard arrival is reduced, not fixed, and the card keeps "It often bumps the ball first." Seed 9015 is the one miss on reach: it parked at 0.355 m, 5 mm short of the line.

**The card** says reached 19 of 20, stopped there 17 of 20: the 17 that did both, the lower number, because the 9015 run parked without reaching.

**An old pin is cleared.** A new pin is a new folder, and nothing reached the old one, Delete included, so `status()` now removes any other `duck-driver-` folder when the app starts. Unit test only; a phone upgrading from v5 has not been tried.

**Not run:** `-driver-get-check` on the v6 pin. The three public files were fetched and match the hashes and sizes; the trial loaded the same policy.json and weights, golden replay included. Next for the push: DAgger on v5 or v6 runs, which arrive hard where v4's did not (no v4 tail ran out of picture).
