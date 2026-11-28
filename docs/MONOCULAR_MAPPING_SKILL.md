# Monocular Ground-Segmentation Autonomous Mapping & Conversational Exploration Skill

This document describes the cross-developed **Monocular Ground-Segmentation Autonomous Building Mapping, Segmented Frontier Search & Conversational Exploration Skill** in **Microduck Studio** (`StudioKit` + `DuckStudio` iOS/macOS SwiftUI app + `bridge/`), aligned 1:1 with `robot-gate`'s `microduck_mapper.py` on the MicroDuck Raspberry Pi companion.

## Architecture & Privacy Contract

- **StudioKit computes; DuckStudio displays.** All calibrated pinhole ground-plane projection, 2D occupancy grid updates, doorway-aware room segmentation, Envelope 0.2 keep-out swept-path gating, bipedal safety interlocks, conversational intent parsing, and SHA-256 receipt hashing live in `StudioKit` and are tested directly with `swift test`.
- **Single onboard RGB camera, zero extra LiDAR.** `MonocularGroundMapper.projectMonocularGroundMask(...)` projects floor segmentation mask pixels `(u, v)` onto the flat ground plane `z = 0` using calibrated pinhole intrinsics (`fx, fy, cx, cy, cameraHeightM, cameraPitchRad`). Non-finite intrinsics, non-finite poses, stale frames (`> 1.5 s`), or low ground-segmentation confidence (`< minConfidence`, default `0.65`) fail closed into `HOLD` before mutating the map.
- **Local-network-only bridge (GATES.md compliant).** `bridge/mapper_bridge.py` refuses any non-local `--mapper-url` (permitting only loopback, RFC 1918 LAN, `.local`, `.ts.net`, and `.internal` hosts) and collects zero telemetry or analytics.

## Core Modules

| Layer | File | Responsibility |
| --- | --- | --- |
| Swift Core | `StudioKit/Sources/StudioKit/MonocularGroundMapper.swift` | Calibrated pinhole `z=0` ray projector, 2D occupancy grid (`unknown`/`free`/`obstacle`/`keepout`/`frontier`), doorway-aware zone segmentation (`zone_01..N`), frontier clustering, Envelope 0.2 swept-path keep-out gate, bipedal safety interlocks, Trust Ladder (`L0_OBSERVE` / `L1_ATOMIC` / `L2_SUPERVISED`), `DualDemoMode`, SHA-256 hash-chained receipts, and `MonocularMappingSimPreset`. |
| Swift Skill | `StudioKit/Sources/StudioKit/ConversationalExplorationSkill.swift` | Natural-language goal parser (*"discover the world"*, *"explore the hallway"*, *"go to lab"*, *"go to stairwell"*, *"stop/hold"*), Trust Ladder + keep-out routing, and tested plain-English UI strings (`AutonomousMappingWords`). |
| SwiftUI App | `DuckStudio/Sources/AutonomousMappingSkillView.swift` | Native iOS 17+ / macOS 14+ UI: onboard camera panel with toggleable `MONOCULAR GROUND-SEG · NO EXTRA LIDAR` mask overlay, live 2D `Canvas` segmented building map, conversational goal bar, Trust Ladder, prominent `SOFTWARE HOLD`, dual recording & SHA-256 receipt inspector, Safe Sim Preview fault drills, and `?` plain-English info sheet. Wired into **Studio → Make** and **Moves → Goals**. |
| LAN Bridge | `bridge/mapper_bridge.py` + `bridge/microduck-bridge.py` | JSON-RPC `studio.mapper.*` relay over TCP 7788 bridging DuckStudio to `robot-gate`'s `microduck_mapper.py` HTTP endpoints on the Pi companion (or `--mapper-local` embedded fail-closed handler). |

## 1:1 Safety Thresholds & Fault Codes

Shared identically between `StudioKit/Sources/StudioKit/MonocularGroundMapper.swift`, `bridge/mapper_bridge.py`, and `robot-gate/src/robot_gate/microduck_mapper.py`:

| Safety Check | Threshold | Verdict | Fault Code |
| --- | --- | --- | --- |
| 2S LiPo Battery Sag | `< 7.0 V` | `HOLD` | `LOW_BATTERY_SAG` |
| IMU Roll / Pitch Tilt | `> 22.0°` | `HOLD` | `EXCESSIVE_IMU_TILT` |
| Camera Freshness TTL | `> 1.5 s` or `< 0 s` | `HOLD` | `STALE_CAMERA_FEED` |
| Human Proximity Radius | `< 0.65 m` | `HOLD` | `HUMAN_PROXIMITY_HOLD` |
| Feetech Servo Temp | `>= 65.0 °C` | `HOLD` | `SERVO_OVERTEMP_HOLD` |
| Hardware E-Stop State | `estop_ok == false` | `HOLD` | `HARDWARE_ESTOP_ENGAGED` |
| Non-Finite Telemetry / Intrinsics | `NaN` / `Inf` | `HOLD` | `NON_FINITE_TELEMETRY` / `NON_FINITE_INTRINSICS` |
| Low Ground-Seg Confidence | `< 0.65` | `HOLD` | `LOW_SEGMENTATION_CONFIDENCE` |
| Envelope 0.2 Keep-Out Box | Swept path enters stairwell / drop-off | `DENY` | Keep-out name (e.g. `stairwell_dropoff`) |

## Trust Ladder

1. **`L0_OBSERVE` (Default — Zero Motion):** Maps the environment, segments rooms, and displays frontier candidates and keep-out verdicts without sending motion. Switching to `physical_hardware` resets the UI to `L0_OBSERVE`.
2. **`L1_ATOMIC` (Human-Approved Single Step):** Computes one bounded frontier or room step and holds until the operator taps **Approve Bounded L1 Step**.
3. **`L2_SUPERVISED` (Supervised Bounded Exploration):** Advances across Envelope 0.2–cleared frontiers while supervised under active bipedal interlocks, deadman timeout, and HOLD.

> **Physical Safety Boundary:** Software `HOLD` buttons, bridge deadman timers, and SHA-256 receipts pair with — and **NEVER replace** — a hardwired battery/power cutoff or ISO 13850 emergency stop switch.

## LAN JSON-RPC Bridge Protocol (`microduck-bridge.py`)

Start the bridge pointing at `robot-gate` on the MicroDuck Pi companion:

```sh
python3 bridge/microduck-bridge.py \
  --socket /run/robotd.sock \
  --port 7788 \
  --token-file ~/.microduck-bridge-token \
  --mapper-url http://127.0.0.1:8788
```

Or run with the embedded fail-closed mapper handler for bench testing without an HTTP upstream:

```sh
python3 bridge/microduck-bridge.py \
  --socket /tmp/duck.sock \
  --port 7788 \
  --token-file /tmp/token \
  --mapper-local
```

### Greeting Capability Flag

After the `{"microduck":"v1","token":"..."}` hello line, the bridge announces mapper support:

```json
{"microduck":"v1","bridge":"microduck-bridge/2","deadman_ms":700,"policy_install":false,"mapper_bridge":true}
```

### JSON-RPC Methods

| JSON-RPC Method | Upstream `robot-gate` Endpoint | Behavior |
| --- | --- | --- |
| `studio.mapper.status` | `POST /api/microduck/mapper/status` | Returns active `mode`, `trust_tier`, `software_hold`, `keepout_zones`, `chain_head_hash`, and `safety_boundary_statement`. |
| `studio.mapper.ingest` | `POST /api/microduck/mapper/ingest` | Validates finite `pose_xytheta` and `mean_confidence >= min_confidence` fail-closed before forwarding. |
| `studio.mapper.plan` | `POST /api/microduck/mapper/plan` | Checks `software_hold`, `health` (`check_biped_health`), Envelope 0.2 keep-outs, and `trust_tier`. |
| `studio.mapper.hold` | `POST /api/microduck/mapper/hold` | Immediately sends `robot.stop` to `robotd`, disarms the motion deadman, latches software HOLD, and records a SHA-256 receipt. |
| `studio.mapper.receipt` | `POST /api/microduck/mapper/receipt` | Exports a `graft-microduck-dual-demo-bundle/1.0` summary with `bundle_sha256`. |
