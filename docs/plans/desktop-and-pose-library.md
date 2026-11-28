# Microduck Studio on Windows and Linux, and a pose library the chat can use

Written 2026-11-28 after a TestFlight tester asked for a Windows 11 or browser
version: a bigger monitor, a mouse and a keyboard for making and editing
movements. They use the joint controls and custom movements, and they already
work out poses with a chatbot on the side. Status: plan, nothing built.

## What we already have that carries over

- **The physics already runs in a browser.** `Resources/phonebench` is
  duckbench's `site/`: MuJoCo's WebAssembly build, the scene, and the policy
  forward pass in plain `.mjs`. It was measured at a 2.7 ms tick in Chromium
  on a Pi 5. The phone talks to it over loopback HTTP using the same
  `DuckBench` calls it uses for a desk bench.
- **StudioKit is UI-free and already builds and tests on Linux.** File
  formats (`duck-intent/2`, `duck-sequence/1`), refusal sentences, joint-handle
  maths, hosted planners (Anthropic, OpenAI) and the decider's closed set all
  live there.
- **What does not carry over:** SwiftUI, RealityKit (the stage), ARKit,
  Foundation Models (the on-device chat), Vision, MLX.

## Recommendation: one web front end, two ways to run it

| | Browser | Desktop app |
|---|---|---|
| Where | microduckstudio.com/studio/ | Tauri 2 installer |
| Platforms | any modern browser | Windows x64 + arm64, Linux x86_64 + aarch64 (.deb, .AppImage) |
| Practice duck (sim) | yes | yes |
| Real duck | no (https page cannot reach a LAN `http://` robot) | yes, the Rust side talks to robotd over LAN and BLE |
| Updates | every deploy | Tauri updater, signed `latest.json` on Cloudflare |

- **Front end:** TypeScript + three.js drawing the same MuJoCo scene,
  physics from the vendored duckbench `.mjs` and `.wasm`, checked by digest the
  way `make_phone_bench.sh` already does.
- **Why not native Swift on Windows/Linux:** Swift compiles there, but there is
  no SwiftUI or RealityKit, and the cross-platform Swift UI toolkits cannot
  draw a 3D duck. We would be rewriting the UI anyway.
- **Why not Electron or Flutter:** Tauri is smaller (system WebView: WebView2
  on Windows, WebKitGTK on Linux), it is already in use (Portico Family), and
  its Rust side is where the robot link should live.

## Keeping it in step with the iPhone app

"Stays updated" needs a mechanism, not good intentions. Three layers, cheapest
first:

1. **Shared files, pinned by test.** StudioKit writes golden fixtures (a pose, a
   motion, a sequence, every refusal sentence the desktop shows) into
   `StudioKit/Tests/Fixtures/desktop/`. The desktop test suite reads the same
   files. A new format version in StudioKit with no desktop reader fails the
   desktop gate. Files made on an iPhone open on Windows and back.
2. **Same physics, by digest.** The desktop vendors duckbench's `site/` with the
   same `MANIFEST.json` check the phone uses. One duckbench tag feeds both.
3. **StudioKit compiled to WebAssembly (spike first).** Swift 6 has an official
   Wasm SDK. If StudioKit (plus DuckKit and CAprilTag) builds for
   `wasm32-unknown-wasip1`, the desktop calls the same Swift code for rules and
   sentences, and drift becomes impossible rather than tested-for. Unproven:
   StudioKit is ~80k lines with Foundation and bundled resources. A one-day spike
   decides it; layers 1 and 2 stand either way.

Plus a parity list, `docs/desktop/parity.md`: every iPhone screen and whether
the desktop has it, "not planned", or "later". Reviewed at each iPhone build.

**Builds stay local** (no GitHub Actions): Linux aarch64 on the Pi, Windows and
Linux x86_64 on the Windows 11 machine (WSL for Linux). Windows binaries start
unsigned, so SmartScreen will warn; the download page says so and how to get
past it. A code-signing certificate is a later decision.

## Desktop 0.1 scope

Only what the tester actually uses, done well with a mouse and keyboard:

- Practice duck in the sim, Drive with keyboard (WASD/arrows) or a gamepad.
- Pose with the mouse: the joint handles, plus number fields per joint,
  undo/redo, mirror left/right.
- Pose library (below), motion timeline (keyframes, drag to retime), sequences.
- Chat: bring your own key (Anthropic, OpenAI, Gemini) through StudioKit's
  existing hosted planners, or a local Ollama model. No on-device Apple model
  on Windows/Linux.
- Import/export `.duckpose`, `.duckintent`, `.ducksequence`.

Not in 0.1: RL training, evals, AR, camera mimic, Duck Cards, chess, Dream.

Real duck: after ducks ship (ours early January, the tester's in April), over
LAN WebSocket from the Rust side, same Stop rules as the phone (stop always
local, always visible).

## Pose library (both platforms, StudioKit first)

Today a pose is built in posing mode and either held on the bench or kept as a
two-keyframe motion. It is never a named thing you can reuse.

**The file:** `DuckPose`, format `duck-pose/1`: name, joint angles (the 14
policy joints, same order as `duck-intent`), when, how it was made (posed by
hand / taken from a motion frame / captured from camera), an optional
one-line description.

**Reuse:**
- "Keep it as a pose" beside "Keep it as a motion" in posing mode.
- Hold it on the bench, bind it to a pad button, drop it into the timeline as
  a keyframe.
- Make a motion from poses: pick poses in order, set the time between them, run
  it on the practice duck first. This goes out through the existing
  `duck-intent/2` path, so nothing new reaches the bench.

**Chat (the tester's idea):** saved poses become the chat's vocabulary.
- Tools: `list_poses`, `show_pose`, `save_current_pose`, `motion_from_poses`
  (`[{pose, at, hold}]`), `mirror_pose`, `between(a, b, t)`.
- The model picks pose NAMES from a closed list and sets timing. It does not
  invent joint angles. That is the decider's closed-set rule again, and it is
  why this works with a small on-device model: composing "wing up, wing down,
  wing up" is a choice from a list, which small models get right, while
  writing fourteen sensible angles is not.
- Descriptions make poses teachable: "wave_up: right wing raised, for
  greetings" lets "say hello to the dog" find it.
- A pose pack (a file of poses plus their descriptions) is a skill you can
  share: the same file opens on iPhone and desktop.

## Order

1. **Pose library in StudioKit + iPhone.** One TestFlight build, batched with
   whatever else is queued for Duck Studio.
2. **Desktop spike (2-3 days):** Tauri shell on the Pi loading the vendored
   bench with a three.js stage; StudioKit-to-Wasm attempt; decide layer 3.
3. **Desktop 0.1** for Windows x64 and Linux x86_64/aarch64. Download page at
   microduckstudio.com/desktop/ with install instructions. Email the tester.
4. **Real duck over LAN** once a duck is on the network.

## Open decisions

- Tauri + web front end (recommended) vs. something else.
- Desktop chat: BYOK only, or also local Ollama in 0.1.
- Whether the browser version ships at all, or desktop only.
- Windows code signing now or later.
