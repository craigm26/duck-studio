# Brains layer for Microduck Studio

Status: plan only. Nothing here was built, run or measured for this document. "(unverified)" marks a claim that comes from a single source or from inference. Robocurve numbers are cited to the memory file `robocurve-benchmark-program.md`, with dated entries.

## 1. Direction

Craig, 2026-11-04:

> "dreamlabs.ai is just one api. we could offer other api's and/or a mcp connector or all kinds of patterns to a LLM/VLA to help make more autonomous like commands or decisions (reference the robocurve chat conversation for a lot of testing going on over there)."

Earlier the same day he set the frame for the app:

- Studio complements Pollen's own app. It does not replace it.
- The simplest actions go through Siri, App Intents, Apple Intelligence and buttons.
- There are three control modes: manual, semi-manual and autonomous. These are Drive, Tell and Auto in the native-first redesign (`/home/craigm26/scratch/native-redesign-plan.md`).
- Advanced features sit one level down.
- The UI is native and polished.

This plan's reading of that direction:

- Dream Labs becomes one provider among several, behind two seams (action sources and planners).
- One deterministic gate sits under every brain.
- Stop sits outside the whole layer.
- The app offers a provider only once that provider has a measured number on the practice duck.

## 2. What Robocurve taught us

All of these are arm results from the Robocurve program (Isaac Lab-Arena, YAM arms). None of them is duck evidence. They shape the design, and none of them appears in Studio copy.

| Finding | Number | Source (memory entry) | What it means here |
|---|---|---|---|
| Plain Dream-1 on apple-to-bowl | 0/6 | 11-03 ~22:30Z GRASP FIX | A raw VLA should not be offered as autonomy without its own number. |
| Dream-1 + assist (v2: calibration offset of about (+1.2, -1.9, +2.9) cm corrected, close-on-intent, own gripper fed back) | 3/3, 28-35 s | same entry | The deterministic layer around the model did the work. n=3, arm only, and it depends on a measured grasp offset. |
| Assist v3 (per-arm WAIT/REACH/GRASP/CARRY/RELEASE/RETREAT decision model, ACT-style chunk blending, goal-only prompt) | stacking task 0.5 with the *old* assist; v3 has no separate published score | 11-03 entry, gate repo 4b04940 | The phase machine and blending are promising but **unmeasured**. They are not proven gains. |
| Team task PRs where Dream-1 scored 0 | 61 of 62 | 11-03 probe entry (one line) | Single source. Internal context only. |
| Envelope gate on task 1 (keep-estop-zone-clear v3) | gated Dream-1 scored 0.0 with 1,546 holds or cuts; the arm never crossed | 11-03 08:30Z entry | The gate held. It did not help the task get done. |
| Small local planners on arm episodes | oracle 20/20, do-nothing 0/20, qwen3.5:4b 2, gemma3:4b 0, qwen3.5:2b 0 | 10-27 entry | Small models are weak open-ended planners. The memory has **pass counts only**. It does not show that they proposed out-of-envelope commands, so this plan makes no such claim. |
| Running parallel Dream-1 jobs | each was about 3x slower | 11-03 entry | Hosted latency is not something we control. Waiting happens off the clock, and the duck holds still. |

Lessons carried into the design:

1. **The assist and the gate are the product.** A model is one replaceable input to them.
2. **Small models only pick from a closed set.** They do not author motion.
3. **Every claim gets a number from the duck itself:** sim first, real duck separately.
4. **Labels are exact.** "Dream-1 + assist" is used only when the assist is on and its row exists. Otherwise the label is "Dream-1 (plain)".

Code to borrow from (read only for this plan):

- `~/projects/craigm26/bounded-embodiment-bench` (public; has a Microduck envelope and the C1/D3 duck twins)
- `~/projects/craigm26/bounded-embodiment-bench-gate` (`be_yam_gate/assist.py`, `gate.py`, `tests/test_invariants.py`)
- `~/projects/craigm26/robocurve-notes` (lessons, autopilot)

## 3. The two kinds of brain

### 3.1 Action sources: chunks of twists

`DreamRows` (`StudioKit/Sources/StudioKit/DreamDirect.swift:22-26`) stays exactly as it is, so its three conformers do not change:

- `BridgeDreamRows`
- `DreamDirect`
- `LocalDreamRows` (on feat/phone-driver)

A descriptor is added beside it:

```swift
public struct ActionSourceInfo: Sendable, Codable, Hashable {
    public let id: String              // "phone.ducknet-s1", "dreamlabs.dream-1", "bridge.dream-1"
    public let modelVersion: String    // checkpoint hash or vendor model id; pins the EvidenceRow
    public let label: String           // "Dream-1 + assist" only when assist is on and evaluated
    public let runsOn: RunsOn          // .thisPhone, .robotComputer, .hosted(vendor)
    public let key: KeyNeed            // .none, .byok(provider), .onBridge
    public let trainedOn: Set<Venue>   // [.practice] for ducknet-s1 (manifest trained_on)
    public let chunkDeadline: Duration // a later answer is refused (held), never replayed
    public let framesSent: FramePolicy // e.g. 9-frame window about every 2 s for Dream-1
    public let evidence: EvidenceRow?  // nil => not offered (section 7)
    public let terms: TermsRow?        // nil => not offered (section 7)
}
public protocol ActionSource: DreamRows { var info: ActionSourceInfo { get } }
```

Later conformers are bridge-side adapters that `BridgeDreamRows` reaches through `dream.act` with a `provider` field:

- openpi (websocket)
- GR00T (ZMQ)
- SmolVLA/LeRobot (gRPC)

None of these has a Swift client. All of them need fine-tuning on duck teleop data first, so none of them is a launch item.

### 3.2 Planners: one typed decision from a closed set

```swift
@Generable public enum DuckDecision: Sendable, Codable {
    // v1
    case skill(name: SkillName)                  // closed set from robot.skills, per-venue allowlist
    case walk(forwardM: Double, sideM: Double)   // kit-clamped, at most 5 s
    case turn(degrees: Double)
    case sound(name: SoundName)
    case ask(question: String)                   // human in the loop; at most one open
    case done(reason: String)
    case stop(reason: String)                    // calls StopPath; never required for a stop
    // later (not in v1)
    case lookAt(point: ImagePoint)               // needs head envelope rows first
    case walkTo(point: ImagePoint)               // needs observation-age gating first
    case drive(source: ActionSourceID, goal: GoalText, seconds: Double)
    case plan(RobotPlanProposal)                 // at most 6 beats, walk at most 5 s
}
public struct Decided: Sendable {
    let decision: DuckDecision; let why: String
    let confidence: Double?                      // may only ADD confirmations, never remove one
    let provider: PlannerInfo; let latency: Duration
}
public protocol Planner: Sendable {
    var info: PlannerInfo { get }                // same fields as ActionSourceInfo
    func decide(_ ask: PlannerAsk) async throws -> Decided
}
public struct PlannerAsk: Sendable {
    let goal: String                             // from the human turn only; tools never set it
    let utterance: String?
    let frame: JPEGData?                         // only if the provider takes images and camera consent was given
    let frameTimestamp: ContinuousClock.Instant?
    let state: DuckStateSnapshot                 // odom and its age, standing, last skill, envelope margins
    let allowed: AllowedDecisions                // per mode, venue and brain kind; decoding is constrained to it
    let history: [Decided]                       // last N decisions in this run
}
```

**How each kind of planner gets the closed set.**

- Apple Foundation Models gets it as guided generation with `.anyOf` over skill names, the existing pattern at `AutomationChatView.swift:687`.
- BYOK LLMs get it as tool definitions. Answers are validated against the same set. Anything outside it is rejected, or becomes `.ask`.
- Ollama and other small models see only the enum with a short list.

**Conversion goes one way.** `DuckTalk`, `ModelIntentPlanner` and `HTTPIntentRouter` keep their current outputs, and a thin adapter maps them to `DuckDecision`. When `.plan` arrives, it wraps `RobotPlan(DuckIntentPlan)` (`RobotPlan.swift:102`), so the refusal in `RobotPlanRunner.run` before anything moves (`:333`) still applies.

**Prompt injection.** The goal text comes only from the human turn. Tool results and anything the model read from the camera never set `goal`. The closed set, the gate and the confirm-on-new rule apply no matter what the model saw. A sign or a screen in the duck's view can steer a vision model, and that is why these rules do not depend on the model's judgement.

### 3.3 How a planner reaches motion

A planner calls nothing. A deterministic `BrainRunner` in StudioKit, owned by `ControlArbiter`, carries out each decision. Before any decision runs, the arbiter clamps every duration and count to the run caps, and the decision's own values are never trusted.

| Decision | Executed by |
|---|---|
| `.skill` | `robot.do` with the existing prerequisites (enable `{on:true}`, standing). Checked against the skill allowlist, the skills-per-minute cap and first-use confirmation. The run summary marks it "skill in progress, finishes after Stop". |
| `.walk`, `.turn` | Kit twist profile through the gate. Distance comes from odometry when it is fresh and from time otherwise, and the label says which. |
| `.sound` | `robot.sound`. |
| `.ask` | In-app sheet. At most one open at a time. |
| `.done` | Ends the run and calls StopPath. |
| `.stop` | StopPath. |
| later: `.lookAt`, `.walkTo` | Kit servo at 10 Hz with clamped twists. The pointer is re-asked every N seconds, and no model runs per tick. Head pitch and yaw use their own envelope rows. A target older than its limit is held, then re-asked. |
| later: `.drive` | `DreamPilot` with the named source. Seconds are clamped by the arbiter, and the gate plus assist are bound. Control returns to the planner on done, timeout or a gate cut. |
| later: `.plan` | `RobotPlanRunner`, with the beat count and walk seconds clamped by the arbiter. |

**Per-run limits.** Planner thinking time is off the clock, as Dream waiting already is (`DuckDream.swift:384-388`), so these limits are what stops a run that would otherwise go on without end:

- wall-clock 3 minutes
- 20 decisions
- 20 hosted calls
- 3 repeats of an identical decision
- one open `.ask`
- for Dream, a cap on asks per run on top of the existing `waitLimit`

There is also a per-day spend cap per key, with the counter shown on screen. When a hosted run fails for lack of credit, Craig is told.

## 4. Providers

Status meanings:

- **launch**: in the first builds below.
- **later**: build 95 or after, one batch per build, with its rows checked in.
- **research**: not available, or needs data we do not have.

| Name | Kind | Runs where | Key | Latency budget | Label on the card | Status |
|---|---|---|---|---|---|---|
| DuckTalk + DuckCommandMatcher | planner (deterministic) | phone | none | under 50 ms | "Understood on this phone" | launch (exists; Tell at 91) |
| Phone driver ducknet-s1 (`LocalDreamRows`) | action source | phone (Accelerate) | none | infer p50 under 20 ms; chunk deadline 1.0 s | "Practice duck only. Runs on this phone, no key." plus its M1 number and date | launch (90, gated on M1) |
| Dream-1 via DreamDirect | action source | Dream Labs (hosted) | BYOK in the Keychain (`WhenUnlockedThisDeviceOnly`, not synced). This is the default way to hold the key. | waits off the clock while the duck holds zero twist; run cap applies | "Dream-1 (plain). Hosted by Dream Labs, your key." plus its number. "Dream-1 + assist" only once a duck row exists. | launch (plain, 91) |
| Dream-1 via bridge | action source | Dream Labs, called from the robot's computer | on the bridge, entered with `castor dream key set` on the bridge host or through TLS pairing | same | same, plus "Key kept on your duck's computer" | later (after the key-transfer fix in section 6.6) |
| Apple Foundation Models | planner (closed set) | phone | none | under 3 s to preview (redesign target); about 200 ms first token (unverified) | "Picks from your duck's moves, on this phone" | launch (91 typed Tell; 93 voice and Tools) |
| MLX `PhoneModelRuntime` | planner (closed set; text parsed and validated) | phone | none | under 5 s, labelled slower | "Local model on this phone" | later |
| Claude / GPT / Gemini (BYOK) | planner (tools = the closed set) | vendor cloud | BYOK in the Keychain | under 8 s per decision; Tell and Auto only, never Drive | "Hosted by [vendor], your key" | later |
| Gemini Robotics-ER 2 | planner (points for `walkTo`/`lookAt`, task steps) | Google (hosted) | BYOK. The key must be restricted (unrestricted keys get 403, unverified) and the setup sheet says so. | under 3 s per point (unverified) while the duck holds zero twist | "Hosted by Google, your key. Points; your duck walks." | later (price $2/$10 per M tokens unverified; check it before any cost figure is shown) |
| LAN Ollama / MLX on a Mac | planner (closed set) | Mac on the LAN | optional bearer | under 15 s, labelled slow | "On your Mac. Slower, weaker on our tests." plus its number | later (plaintext caveat, section 6.6) |
| openpi / GR00T / SmolVLA via bridge | action source | bridge or GPU box | held on the bridge | per adapter | "+ assist", "fine-tuned on [dataset]" | research (needs duck teleop data and fine-tuning) |
| Pi API, Gemini Robotics VLA / On-Device | action source | n/a | n/a | n/a | not offered | research (waitlist or trusted testers only) |

Rules for every provider:

- **Keys.** A key is entered once, in Studio > Settings > Models. "Forget key" deletes it from the Keychain, calls `dream.key.clear` on the bridge when one was set there, and revokes any MCP tokens minted for that provider.
- **Provenance and Pollen.** The provenance line is always on the card, and "Not Pollen's" stays on every surface. No copy implies that Dream Labs, Google or any other vendor endorses anything.
- **What leaves the phone.** The card states, per provider, what is sent and how often. Dream-1 sends a window of 9 frames (`DreamPilot.window`) about every 2 s, not "one picture". Before the first frame goes to any vendor, a camera-consent sheet appears.
- **Retention.** The card states each vendor's retention for robot camera frames. Dream Labs retention is unknown, and the Claude MCP connector is not ZDR-eligible. If retention cannot be stated, the provider is not offered.
- **Children.** Hosted vision providers are off by default in any child-oriented mode.

## 5. MCP both ways

### 5.1 What v1 ships

v1 ships at most a **local stdio** `castor mcp` with read-only `duck_state` and `duck_skills` against the practice duck. v1 does not include:

- a tunnel or Streamable HTTP
- OAuth or ChatGPT
- bridge-side runs
- the app as an MCP client
- the Claude MCP-connector shortcut

Without bridge-side motion, the stop-latch and consent problems below cannot arise yet. The rest of this section is the design for when those pieces ship, and it ships only with every fix listed.

### 5.2 The duck as an MCP server (later; on the robot's computer, never in the app)

**Where it runs.** It extends `castor mcp` on the bridge host. It does not run in the app, because iOS does not keep an in-app server reachable in the background (inference, unverified as a stated Apple rule).

**What the tunnel reaches.** It reaches only the MCP process. That process binds to loopback and talks to the bridge or robotd locally. Port 7788 and the relay are never exposed. The bridge's own docstring says its token "is not a security boundary... Bind to the LAN, never to the world" (`bridge/microduck-bridge.py:28-31`). The MCP process holds no Dream key.

**Tools.**

| Tool | LoA | Effect |
|---|---|---|
| `duck_state` | 0 (OAuth) | standing, odometry and its age, current run, who holds control |
| `duck_skills` | 0 (OAuth) | closed set from `robot.skills` |
| `duck_frame` | 0 (OAuth) **plus per-session camera consent in Studio** | one head-cam JPEG from mediad `/frame` |
| `duck_stop` | 0 (OAuth) | `robot.stop` on the bridge, then it sets the stop latch |
| `duck_propose` | 1 | takes a `DuckDecision` (JSON schema generated from the same source as the Swift enum). Returns a single-use proposal id that expires after 10 s and is bound to the state snapshot it was judged on, plus the gate's verdict. **Moves nothing.** |
| `duck_run` | 1 | runs a proposal id. It re-runs the gate on fresh state, and refuses if the verdict changed or if the odometry or frame used is older than its limit. |
| `duck_plan_save` | 1 | writes to the plan store. Moves nothing. |

**Rules for motion over MCP.**

- **Rate limits.** `duck_propose` and `duck_run` are limited per client to 1 per second and 30 per run. The run limits from section 3.3 also apply.
- **No twist streams.** Bridge deadman is 700 ms and cloud decisions take seconds, so motion is always a bounded decision carried out on the bridge.
- **No phone, no motion.** `duck_run` is refused when no Studio controller is connected, because nobody would have a Stop on the phone.
- **Real duck needs a Go at the phone.** On the real duck, `duck_run` needs a Go tap in Studio on the phone that holds the control lease. Elicitation in a claude.ai or ChatGPT tab is not the owner's consent at the duck, because the person clicking may be away from it or may not be the owner. Elicitation alone is allowed only on the practice duck.
- **Remote brains and skills.** Remote and hosted planners may not start skills on the real duck in v1 of this server.
- **Thumbs win.** Any stick touch takes control back.
- **Last writer wins outside Studio.** For clients that do not go through Studio, last writer still wins at robotd, and the copy says so.

**Auth.**

- **Per request on HTTP.** Today `_CLIENT_LOA` is a module global decided once per process (`castor/mcp_server.py:114-120`, set at `:610`). That is fine for stdio but wrong for HTTP, where one client's LoA would apply to every caller.
- **Dev mode.** The server refuses to start HTTP transport when `CASTOR_MCP_DEV` is set, because `CASTOR_MCP_DEV=1` with token "dev" gives LoA 3 (`castor/mcp_auth.py:33-55`).
- **LoA 3** tools (`system_upgrade`, `harness_set`, `loa_enable`) are never exposed over the tunnel.
- **No authless mode.** If Craig later wants an authless stop, it is a separate endpoint that exposes `duck_stop` only, with nothing readable.
- **Signing.** Mutating calls stay RCAN-signed downstream, as today.
- **Test.** Two concurrent sessions with LoA 0 and LoA 1 tokens; the LoA 0 session's `duck_run` is refused.

**How Claude and ChatGPT reach it.**

- Claude: a custom connector through Cloudflare Tunnel, the same pattern as the "bob robot-md v0.4.0 dev tunnel" connector in this account.
- ChatGPT: Developer Mode, with its prompt-injection warning reproduced in our setup doc.
- Both are documented as "your duck's computer, your tunnel".

**How `duck_stop` is described.** It is described only as "a remote brain can also ask for a stop". It depends on Cloudflare, on the vendor's model choosing to call it, and on the chat UI. It is never presented as a way to stop the duck. The local Stop paths are the stop.

### 5.3 The app as an MCP client (later)

- **Client.** `modelcontextprotocol/swift-sdk` with `HTTPClientTransport`, connecting to the bridge's duck server, robot-md-gateway or another robot MCP server. Listed tools join `AllowedDecisions` for Foundation Models (iOS 27 tool calling) or BYOK sessions.
- **No second motion path.** For the duck, the app prefers its own `DuckPeer` path and uses MCP only for tools it does not have natively.
- **Claude BYOK shortcut.** This is the Messages API MCP connector, `mcp_servers` with beta header `mcp-client-2025-11-20`. It needs a scoped token minted for that use: LoA 0 plus `duck_propose` only, short-lived, and revocable from Studio. It can never run anything. The setup sheet says the connector is not ZDR-eligible.

### 5.4 What never goes over MCP

- **Stop.** App Stop, voice "stop", Controls, Live Activity and the pad all go straight to `robot.stop` over the existing connection.
- **Per-tick control.** The stick, pad, head and pose streams, and any other per-tick control.
- **Limits.** Gate, caps and envelope settings. These are kit arithmetic on the app and config on the bridge, editable only locally.
- **Keys.** No key of any kind, and no key appears in any MCP reply.

## 6. The gate and the assist layer

### 6.1 Stop sits outside the layer

StopPath never imports brain code. It never waits on a model, the network or MCP. A model may *ask* for a stop, and that request calls StopPath like any other entry point. The redesign's StopPath order is reworked so that nothing in it is awaited before the stop goes out:

1. Send `robot.stop` on the peer first, synchronously.
2. Set the in-app stop latch. After `.stop`, `ControlArbiter` and `LinePeer` refuse `.move` from any pilot or runner until an explicit re-arm by a person in Studio.
3. Block queued steps.
4. Cancel the pilot and runner tasks **without awaiting them**.

These fixes come from code read this session:

- **A1, verified.** Today Stop on the Dream run screen only cancels the task (`DuckStudio/Sources/DreamRunView.swift:89`). `robot.stop` goes out only at the end of `DreamPilot.run` (`DuckDream.swift:450`). Inside `source.act` (`:401`) on the bridge path, `LinePeer.call` parks in a continuation with no cancellation handler (`LinePeer.swift:268-313`), and the bridge allows `dream.act` up to 15 s (`castor/dream.py:174`, rel370 worktree). During that wait only the deadmans can stop the duck, and the bridge deadman resets on any client line (`bridge/microduck-bridge.py:323-331`).
  - Fix: add `withTaskCancellationHandler` to `LinePeer.answer` so a cancelled call resumes at once.
  - Test (Linux): a stub `DreamRows` that never returns, then Stop, then `robot.stop` is on the wire within 50 ms.
- **A2, verified.** After 20 rows (2 s at 10 Hz) the loop asks again (`DuckDream.swift:395-401`) without zeroing, so the last nonzero twist stays commanded until robotd's deadman fires. The redesign plan gives that deadman as 500 ms (unverified).
  - Fix: the WAIT phase sends an explicit zero twist before every `act`. This is written into the gate, not left to the deadman.
  - Test: zero twist is on the wire before each act call.
- **A3, design hole; applies when bridge-side runs exist.** A Studio, Siri or Live Activity `robot.stop` zeroes robotd once. A bridge runner then sends its next `.move` 100 ms later and the duck walks again.
  - Fix: a **bridge stop latch**. The bridge sees every client line, so it detects `robot.stop` from any client, plus `duck_stop` and its own deadman. The latch cancels every bridge-side run and refuses all non-stick motion until a person re-arms from Studio on the phone. Re-arming over MCP is not allowed.
  - Golden case: stop during an active `duck_run`, then zero twist for at least 2 s with no new moves.
- **A4.** StopDuckIntent at "under 100 ms warm" holds only when the app is warm. Cold, it needs the reconnect of up to 3 s.
  - Copy: "Siri Stop needs to reach the duck; if the app was closed it can take a few seconds."
  - Measure cold stop-to-zero as well as warm, and print both numbers.
- **Skills.** Stop zeroes walking, but a started skill finishes. The copy says this plainly.

### 6.2 `DuckEnvelopeGate` (StudioKit, Linux-tested)

**Where it sits.**

- Inside `DreamPilot`, right after the stick clamp (`DuckDream.swift:351`) and before `peer.notify(.move)` (`:434`).
- Inside BrainRunner's twist profiles and servo.
- In `RobotPlanRunner` as a pre-check on discrete beats.
- Around every skill request, through the allowlist checks.

**Binding.** It is bound before the first act. As in `be_yam_gate`, `act()` refuses to run before `bind()`, so no row can skip the gate.

**Checks per row, in order.** Every failure resolves to a fixed verdict:

1. **Finite numbers.** All three values must be finite. Otherwise **invalid**: zero twist, then StopPath.
2. **Stick envelope.** 0.3 m/s forward and back, 0.3 m/s sideways, 1.0 rad/s turn (`DuckDrive.swift`). This is below the envelope's sourced 0.4 m/s and 1.0 rad/s. Over the limit gives **clamped**.
3. **Rate.** A limit on the change in twist per row, generalising the 3-row ease. Over the limit gives **slowed**.
4. **Staleness.**
   - Odometry older than `max_state_age_ms` (100, placeholder) gives **held** (zero twist) for up to 1 s. If it is still stale after that, **cut** and StopPath.
   - A chunk later than the source's deadline gives **held**, never a replay of old rows.
   - **Observation age.** Each row carries `observationAge = now - frameTimestamp`. Above the limit (1.0 s to start) the verdict is **held**. The same rule applies to pointer targets later.
5. **Keep-in.** The 2 x 2 m mat (placeholder), checked on robotd odometry. The stopping margin is speed times stop time, swept along the turning arc rather than a straight line. This closes the documented hole in `reference_gates/rover.py`. Exceeding it gives **slowed**, then **cut**. On the real duck, odometry drift is unmeasured, so keep-in is labelled "approximate".
6. **Tilt or fall.** IMU tilt over the limit gives **cut** and StopPath.
7. **Run cap and authority.** 30 s on the real duck and 60 s on the practice duck (ControlArbiter), plus the per-run limits in section 3.3. A cap hit gives **cut**. Motion requires an unlocked phone, except the Stop, Sit, rest and sound exemptions.
8. **Skills.** A skill allowlist per venue and per brain kind, plus a skills-per-minute cap. Hosted and remote planners get no skills on the real duck in v1.
9. **Head (later).** Head pitch and yaw get their own envelope rows (limits and rate) before `.lookAt` ships. Until then, head motion is not a planner output.
10. **Confirmation for anything new.** The first time in a session that a decision kind, skill name or action source is used, the run pauses on a Go/Cancel card. So do:
    - any later `.walkTo` beyond 1.5 m,
    - any confidence below a floor,
    - any decision the gate would clamp by more than 20%.

    Self-reported confidence can only add confirmations. Tell always shows the countdown card. Auto asks once per new kind, then runs within the envelope.
11. **Proximity.** Always reported as **unmet**, never passed. The run summary says "No obstacle sensing."

**Logs.**

- Every row writes a `GateEvent`: time, provider id and model version, phase, requested twist, sent twist, verdict (pass, clamped, slowed, held, cut, invalid), rule id, odom age, observation age, and margin to keep-in.
- `GateStats` counts interventions per rule.
- The run summary chip reads, for example, "Gate stepped in 14 times (keep-in 9, rate 5)". Details are exportable from Studio > Measure.
- Keys never appear in GateEvent exports, run summaries, crash logs or MCP replies. A test greps every export for key patterns, using the existing `DuckDream.hint` masking.

**Copy.** The gate is called "the limits" or "the envelope", never "safety". It makes no claim that any provider or model is safe.

### 6.3 The bridge gate (later, with bridge-side runs)

- **One source.** There is one Python gate, imported from bounded-embodiment-bench, the public repo. It is not a second hand-written copy in castor.
- **Golden cases.** The Swift and Python gates both read `embodiments/microduck/envelope.json` and must pass one shared golden-case JSON file in the bench repo.
- **One write path.** Every bridge motion verb goes through one `gated_move()`, the only function in the runner module that writes `robot.move`. A grep or AST test enforces this, like the StopDuckIntent import test.

### 6.4 Assist, generalised from Robocurve `dream_assist`

`DuckAssist` wraps any `ActionSource`, and it is what turns a source into "+ assist". Each part is a switch. Each switch is recorded in the run log, so the label is always exact.

- **Goal-only prompt.** The source receives only the goal ("walk to the red ball"). Rules and limits live in the gate, not in the prompt (`assist.py:300-301`).
- **Phase machine.** WAIT, SEEK, APPROACH, ALIGN, ACT, RECOVER, DONE.
  - Every transition is logged with its reason, for example "ball lost for 1.2 s, back to SEEK".
  - WAIT sends zero twist before every act (fix A2).
  - ACT hands over to an allowlisted skill, so a VLA run can end in a kick instead of walking into the ball.
- **Not in v1:**
  - ACT-style temporal ensembling (`replan=k`, weights `exp(-m*i)`, `assist.py:375`). v1 keeps the 3-row linear ease until BrainBench shows a gain.
  - Steady-bias calibration, a constant twist bias per source and venue, never fitted on the seeds it is scored on.
- **Invariants carried over as tests.** Every layer writes before `gate.filter`, and every intervention is counted (`tests/test_invariants.py`).
- **Not carried over.** IK, gripper, depth and hold voting, and the R3 perception stack. The assist does not perceive. Perception is a planner input: the existing Duck Cards and ball detector, and ER-2 later.

### 6.5 What can bypass the gate, and the answer to each

| Path | Answer |
|---|---|
| Skills via `robot.do` | allowlist, first-use confirmation, skills-per-minute cap, no hosted or remote skills on the real duck in v1 |
| Head pose and look-at | own envelope rows before `.lookAt` ships; out of v1 |
| Rows computed on old frames | observation-age check (rule 4) |
| A second gate on the bridge | one imported gate, golden cases, single `gated_move()` with an AST test |
| Model-supplied durations | arbiter clamps `seconds`, beats and walk time before running |

### 6.6 Keys and data on the wire

- **Dream key over the bridge line (verified).** `dream.key.set` sends the raw key over the bridge's plaintext TCP line. The protocol is at `DuckDream.swift:12,24`, and the bridge side is `castor/microduck_bridge.py:688` (rel370).
  - Fix: DreamDirect is the default.
  - For the bridge, the key is entered on the bridge host (`castor dream key set`) or sent through a one-time pairing over TLS.
  - Until either exists, the setup sheet says "sent unencrypted over your Wi-Fi to your duck's computer".
- **LAN Ollama/MLX.** The bearer and the camera frames travel over plain HTTP. Either use TLS, or the setup sheet says so in plain words.

## 7. How a provider earns a place in the app

**Harness.** A `DuckBrainBench` runs on duckbench (tailnet 100.122.199.6:8770) or the Mac against duck-sim robotd. It never runs on the Pi.

**Tasks.**

- **M1** (walk to the ball, 10 seeded starts), plus a fresh 10-seed holdout reported beside it.
- **bounded-embodiment-bench Microduck tasks** A1, A2, A4, B1-B3, C1, C3, C4, D1-D4, including the C1 and D3 twins. A twin pair passes only if both episodes pass.
- **Planner gold.** PlannerCheck p002 (30 prompts), extended with `DuckDecision` gold for Tell utterances.

**Baselines on every table.**

- oracle: the scripted expert, the ceiling.
- do-nothing: zero twist or `.done`, the floor. M1's floor is 0-1/10.

**Measured for each provider, in each mode (plain, + assist, gated, ungated):**

- success n/N on the training seeds and on the holdout
- envelope crossings proposed before the gate, and after the gate (must be 0)
- gate interventions by rule
- decision latency p50/p95, and act p50/p95
- cost per run for hosted providers
- stop-to-zero-twist time on the kit path with no model involved, measured warm and cold

**`EvidenceRow`** is pinned to provider id, model version or checkpoint, and date. A server-side model change, such as a Dream-1 update or a moved Claude or GPT alias, hides the card or relabels it "untested version" until it is re-run.

**`TermsRow`** sits beside it. It records:

- whether control of physical devices is allowed
- image retention and training use
- age limits (the Gemini API terms in particular need checking, unverified)
- whether BYOK use in a third-party app is allowed

**Offer rule** (a kit table, Linux-tested):

- A card shows only if **both** rows exist.
- The provider must beat do-nothing on the holdout by at least 4/10 for Tell and by more for Auto (proposed 6/10), with zero post-gate crossings.
- The card prints the number and date, for example "6/10 on the practice duck, 11-20".
- Real-duck availability is a separate row. It needs a tester's run and stays off by manifest (`trained_on`, `enabled_on_robot = false`) until then.
- A planner under 80% closed-set accuracy on gold is offered only in Tell with confirmation, never in Auto.
- Sim-only margins on 10 seeds are thin, and every card says "practice duck".

**Copy.** No Robocurve or arm number appears in Studio copy. That covers the 3/3, the 1,546 holds and the 61 of 62.

**Cost.** Hosted runs cost credits. Runs are batched per evaluation session, and Craig is told when a run fails for lack of credit.

## 8. Fit with the native-first redesign and with build 90

| Brain piece | Mode | App Intent | Screen |
|---|---|---|---|
| StopPath and the stop latch | all modes | `StopDuckIntent` (also a `LiveActivityIntent`); a Linux import test proves it imports no brain code | red Stop on Play, the second Stop in the thumb zone during Auto, the floating Stop pill over every sheet, the Live Activity |
| DuckTalk + DuckCommandMatcher | Tell | `TellTheDuckIntent` (deterministic path only in the background) | Tell field on Play; preview strip for compound sentences |
| Apple FM planner (closed set) | Tell (91), Auto goal pick later | `TellTheDuckIntent` asks to continue in the foreground when a model is needed. Intents never call a planner in the background. | Tell preview card with countdown and Cancel |
| Phone driver ducknet-s1 | Tell (moved from Auto after build 94) | none yet (`WalkToBallIntent` was planned and has not been built) | Tell's Walk to the ball card with its number, on the practice duck and a real one |
| Dream-1 (plain) via DreamDirect | Auto | none in v1 | Auto goal card with a prompt field, provenance and its number; Studio > Settings > Models for the key |
| Gate counts and run summary | Tell, Auto | none | run summary chip; Studio > Measure for the export |
| Wander (rule-based, no model; `wander.md`) | Auto | none | Auto card "Wander" with its number, on the practice duck and a real one |
| Provider settings, consent, Forget key | n/a | none | Studio > Settings > Models, one level down |
| Later BYOK planners and ER-2 | Tell and Auto, never Drive | none | Auto cards "Go to the [thing]" with the pointed dot drawn before moving |

Drive stays model-free: the stick, pad and move buttons go through the gate only. The person's thumbs win, so any stick touch, pad input or move press cancels Tell and Auto and switches to Drive ("You took over"). Autonomy never re-arms itself. When the app leaves the foreground, StopPath runs for every chain, plan and goal, as the redesign specifies.

**Build 90** (`docs/plans/build-90-phone-driver.md`) is the phone driver and does not grow. The brains work rides along as kit-only Linux-tested code with no new UI. The M1 runs become the first `EvidenceRow`: phone driver against oracle against do-nothing.

## 9. Phases

Each build is one TestFlight upload. Kit work rides along, and nothing is uploaded to find out whether it compiles. Every build has the same three acceptance tiers:

- **Linux.** StudioKit tests pass on Linux, run on duckbench or the Mac, not on the Pi.
- **Mac compile gate.** `xcodebuild archive … CODE_SIGNING_ALLOWED=NO`, both platforms.
- **Device.** The listed checks on a phone.

**Build 90 (phone driver, no new UI).**

- Kit: `DuckDecision` (v1 cases) with its JSON schema, `ActionSourceInfo` with `modelVersion`, `EvidenceRow` and `TermsRow`, the offer rule, and `DuckEnvelopeGate` with the shared golden cases. The gate runs in shadow mode in BrainBench only.
- StopPath fixes A1 and A2 land in the kit now, because they are bugs in today's Dream run:
  - `robot.stop` sent first
  - cancellation handler in `LinePeer`
  - zero twist before every act
- Linux tests:
  - never-returning `DreamRows` stub, then Stop, then `robot.stop` within 50 ms
  - zero twist before each act
  - golden cases pass
  - the offer rule hides a source with no row or no terms
  - the key-pattern grep over exports
- Device: M1 numbers recorded; Stop during a slow Dream ask stops at once.

**Build 91 (controller).**

- The gate is bound in DreamPilot and enforced on both venues. The in-app stop latch and re-arm, the skill allowlist with first-use confirmation, the per-run limits and the arbiter's duration clamps all ship.
- Auto cards show provenance and their number, and run summaries show gate counts.
- Typed Tell runs DuckTalk first, then the Apple FM planner, constrained to `DuckDecision`, with a confirm card.
- Dream-1 ships as "Dream-1 (plain)" with its number, likely 0/10. "+ assist" ships only if its duck row exists.
- The camera-consent sheet and per-provider frame copy ship.
- Linux tests:
  - `act()` before `bind()` throws
  - `.move` is refused after `.stop` until re-arm
  - `seconds` from a decision is clamped
  - confidence never removes a confirmation
- Device:
  - warm and cold stop-to-zero measured and printed
  - stick touch cancels Auto

**Build 92 (front door).**

- Intents never call a planner in the background. `TellTheDuckIntent` stays deterministic there.
- A Linux import test proves `StopDuckIntent` imports no brain code.
- Device: cold Siri Stop timing recorded, and its copy shows.

**Build 93 (voice).**

- A FoundationModels `Tool` layer over kit actions. Tools return `DuckDecision` or `RobotPlanProposal`, never rows.
- Voice stop stays keyword-only on volatile results.
- Device: "stop" fires StopPath before the final transcript.

**Build 94 (real-duck feel).**

- Keep-in, staleness and observation age are checked against real-duck odometry on a tester's duck.
- Envelope placeholders are replaced with sourced numbers, or stay labelled "placeholder".
- Real-duck `EvidenceRow`s begin here.

**Build 95 and later (one batch per build, each with its BrainBench row, TermsRow and `ScreenHierarchy` row checked in before upload).**

1. BYOK planners (Claude, GPT, Gemini), then ER-2 pointing. ER-2 needs head envelope rows for `.lookAt` and observation-age gating for `.walkTo`, and its price is checked before any cost figure appears.
2. MLX on the phone, then LAN Ollama/MLX on a Mac, with TLS or the plaintext caveat.
3. The app as an MCP client, with the scoped token for the Claude shortcut.
4. `.drive`-from-planner and `.plan`-from-planner, with arbiter clamps.
5. ACT ensembling and bias calibration, only if BrainBench shows a gain.
6. Bridge-hosted VLA adapters, only after duck teleop data and fine-tuning exist.
7. Wander (`docs/plans/wander.md`): edge stop, BrainBench task W1 and golden traces first, then the Swift port behind the gate once a real or tester's duck has measured it.

**Outside TestFlight (OpenCastor via PyPI, no TestFlight slot).**

- **Stage 1.** Local stdio `duck_state` and `duck_skills` against the practice duck.
- **Stage 2.** It can land only after build 91's golden cases exist, and only with every item below:
  - bridge-side runs
  - the bridge stop latch
  - the single `gated_move()` with its AST test
  - the imported Python gate
  - per-request auth
  - the refusal to start HTTP under `CASTOR_MCP_DEV`
  - the two-session LoA test
  - loopback-only MCP behind the tunnel
  - OAuth with no authless mode
  - camera consent for `duck_frame`
  - single-use expiring proposals
  - "Go at the phone" for the real duck
  - refusal when no controller is connected
  - rate limits

  The tunnel setup is a doc, not an app feature.

## 10. Risks and kill criteria

| Risk | Signal | Kill or change |
|---|---|---|
| Stop latency regresses through a model or network path | any test or device run where `robot.stop` is not on the wire within 50 ms of Stop on the kit path; cold Stop over the printed number | block the upload; no brain feature ships ahead of the fix |
| No provider beats do-nothing on the duck | phone driver and Dream-1 both under the offer bar on the holdout | Auto shows only the scripted oracle goals; brains stay in Studio > Measure as research |
| "+ assist" cannot be shown to help on the duck | assist row not above plain by a clear margin | ship plain only; drop the assist label |
| The gate cuts so often that runs are useless | most runs end in a cut, or interventions per run keep rising | tune the source or its assist, never the envelope limits from a model's demand |
| Swift and Python gates drift | a golden case fails on either side | bridge motion is disabled until both pass |
| Vendor terms forbid robot control, minors or BYOK in third-party apps | a TermsRow cannot be filled in | provider not offered |
| Vendor retention unknown for camera frames | cannot state it on the card | provider not offered |
| Hosted costs or credit failures confuse people | spend cap hit often; credit failures | hosted providers go back to Studio-only |
| MCP tunnel exposure | any path from the tunnel to port 7788, any LoA mix-up in the two-session test, any run without a Go at the phone on the real duck | MCP over HTTP is withdrawn and stdio-only remains |
| Prompt injection steers a hosted planner | a gold case with an adversarial sign in frame produces a non-allowlisted or unconfirmed action | provider limited to Tell with confirmation, or removed |
| Claims outrun evidence | any copy citing an arm number, an unverified latency or price, or a model as safe | copy is reverted before upload |
| Pi instability | any bench or build run on the Pi | runs move to duckbench or the Mac only |

## 11. Open questions for Craig

1. **Authless stop.** The recommendation is no authless mode at all. If you want one later, it would be a separate stop-only endpoint with nothing readable. Is that acceptable?
2. **Bridge gate source.** The recommendation is one Python gate imported from bounded-embodiment-bench (public), not a copy in castor. Agree?
3. **MCP when the app is closed.** The recommendation is to refuse MCP motion when no Studio controller is connected, and on the real duck to require a Go tap at the phone. Agree?
4. **Offer bar.** Is "beats do-nothing by 4/10 on the holdout with zero post-gate crossings" right for Tell, with a higher bar (proposed 6/10) for Auto, and every row pinned to a model version?
5. **ER-2 price.** $2/$10 per M tokens is unverified. It gets checked before any cost-per-run figure appears. Is that fine, and should ER-2 be the first later provider or after the BYOK LLMs?
6. **Dream key on the bridge.** Until TLS pairing exists, should the bridge path be offered at all, given the "sent unencrypted over your Wi-Fi" sheet, or should DreamDirect be the only way for now?
7. **Child-oriented mode.** Should hosted vision providers be off by default for every install, or only in a family or kids mode?

Source files read for this plan:

- `/home/craigm26/scratch/native-redesign-plan.md`
- `/home/craigm26/projects/duck-studio/docs/plans/build-90-phone-driver.md`
- `/home/craigm26/projects/duck-studio/StudioKit/Sources/StudioKit/DreamDirect.swift`
- `/home/craigm26/.claude/projects/-home-craigm26/memory/robocurve-benchmark-program.md`
- the code locations cited inline in the adversary review (`DuckDream.swift`, `LinePeer.swift`, `DreamRunView.swift`, `castor/mcp_server.py`, `castor/mcp_auth.py`, `castor/dream.py`, `castor/microduck_bridge.py`, `bridge/microduck-bridge.py`)
