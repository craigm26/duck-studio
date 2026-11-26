#!/usr/bin/env python3
"""LAN JSON-RPC <-> HTTP bridge for MicroDuck Monocular Ground-Segmentation Mapping.

Bridges DuckStudio (`StudioKit` / iOS / macOS) over `microduck-bridge.py` TCP JSON-RPC
to `robot-gate`'s `microduck_mapper.py` service running on the MicroDuck Raspberry Pi
companion (stdlib only, Python 3.9+, zero pip dependencies).

Supported JSON-RPC methods:
  - `studio.mapper.status`  -> returns mode, trust tier, keep-outs, health & chain head
  - `studio.mapper.ingest`  -> validates finite pose/intrinsics/confidence & forwards frame
  - `studio.mapper.plan`    -> evaluates conversational goal / segmented frontier via Envelope 0.2
  - `studio.mapper.hold`    -> latches software HOLD (and triggers `robot.stop` on `robotd`)
  - `studio.mapper.receipt` -> returns deterministic SHA-256 session bundle summary

SAFETY BOUNDARY:
  Software HOLD, bridge deadman, and SHA-256 receipts pair with — and NEVER replace —
  a hardwired power cutoff or ISO 13850 emergency stop switch.
"""

from __future__ import annotations

import hashlib
import ipaddress
import json
import math
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

MAPPER_METHOD_PREFIX = "studio.mapper."
SUPPORTED_METHODS = frozenset({
    "studio.mapper.status",
    "studio.mapper.ingest",
    "studio.mapper.plan",
    "studio.mapper.hold",
    "studio.mapper.receipt",
})

GENESIS_HASH = "0" * 64
SAFETY_BOUNDARY_STATEMENT = (
    "Software gates, HOLD buttons, and SHA-256 receipts pair with — and NEVER replace — "
    "a hardwired power cutoff or ISO 13850 emergency stop switch."
)

DEFAULT_MIN_BATTERY_V = 7.0
DEFAULT_MAX_TILT_DEG = 22.0
DEFAULT_MAX_CAMERA_AGE_S = 1.5
DEFAULT_MIN_CONFIDENCE = 0.65


class MapperBridgeRefusal(Exception):
    """Refusal in plain words when a request violates safety or local-only rules."""


def _is_finite(value: Any) -> bool:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    return math.isfinite(float(value))


def _canonical_sha256(obj: Any) -> str:
    payload = json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def is_local_mapper_url(url: str) -> bool:
    """Only allow loopback, RFC1918 LAN, `.local`, `.ts.net`, or `.internal` hosts."""
    try:
        parsed = urllib.parse.urlparse(url)
    except ValueError:
        return False
    if parsed.scheme not in ("http", "https"):
        return False
    host = (parsed.hostname or "").lower()
    if not host:
        return False
    if host in ("localhost", "127.0.0.1", "::1"):
        return True
    if host.endswith(".local") or host.endswith(".ts.net") or host.endswith(".internal"):
        return True
    try:
        ip = ipaddress.ip_address(host)
        return ip.is_private or ip.is_loopback or ip.is_link_local
    except ValueError:
        return False


def _check_biped_health_dict(health: dict[str, Any] | None) -> dict[str, Any]:
    """Fail-closed bipedal health check aligned 1:1 with `microduck_mapper.py`."""
    if not isinstance(health, dict):
        return {
            "ok": False,
            "decision": "HOLD",
            "fault_codes": ["NON_FINITE_TELEMETRY"],
            "reasons": ["Missing biped health telemetry"],
        }
    faults: list[str] = []
    reasons: list[str] = []
    if health.get("estop_ok", True) is not True:
        faults.append("HARDWARE_ESTOP_ENGAGED")
        reasons.append("Hardware E-stop / cutoff state is not clear (estop_ok=False)")
    for key in ("battery_v", "imu_roll_deg", "imu_pitch_deg", "camera_age_s"):
        if not _is_finite(health.get(key)):
            if "NON_FINITE_TELEMETRY" not in faults:
                faults.append("NON_FINITE_TELEMETRY")
            reasons.append(f"Required telemetry '{key}' is missing or non-finite")
    if _is_finite(health.get("battery_v")) and float(health["battery_v"]) < DEFAULT_MIN_BATTERY_V:
        faults.append("LOW_BATTERY_SAG")
        reasons.append(f"2S LiPo voltage {float(health['battery_v']):.2f}V < {DEFAULT_MIN_BATTERY_V:.2f}V")
    if _is_finite(health.get("imu_roll_deg")) and abs(float(health["imu_roll_deg"])) > DEFAULT_MAX_TILT_DEG:
        faults.append("EXCESSIVE_IMU_TILT")
        reasons.append(f"IMU roll {float(health['imu_roll_deg']):+.1f} deg exceeds +/-{DEFAULT_MAX_TILT_DEG:.1f} deg")
    if _is_finite(health.get("imu_pitch_deg")) and abs(float(health["imu_pitch_deg"])) > DEFAULT_MAX_TILT_DEG:
        if "EXCESSIVE_IMU_TILT" not in faults:
            faults.append("EXCESSIVE_IMU_TILT")
        reasons.append(f"IMU pitch {float(health['imu_pitch_deg']):+.1f} deg exceeds +/-{DEFAULT_MAX_TILT_DEG:.1f} deg")
    if _is_finite(health.get("camera_age_s")):
        age = float(health["camera_age_s"])
        if age < 0.0 or age > DEFAULT_MAX_CAMERA_AGE_S:
            faults.append("STALE_CAMERA_FEED")
            reasons.append(f"Camera age {age:.2f}s violates TTL [0.0, {DEFAULT_MAX_CAMERA_AGE_S:.2f}]s")
    ok = len(faults) == 0
    return {
        "ok": ok,
        "decision": "ALLOW" if ok else "HOLD",
        "fault_codes": faults,
        "reasons": reasons,
    }


def _check_swept_path_2d(
    start_xy: tuple[float, float],
    end_xy: tuple[float, float],
    keepouts: list[dict[str, Any]],
    samples: int = 12,
) -> tuple[bool, str | None]:
    """Deterministic Envelope 0.2 2D keep-out check along a straight swept segment."""
    for s in range(samples + 1):
        frac = s / float(samples)
        px = start_xy[0] + (end_xy[0] - start_xy[0]) * frac
        py = start_xy[1] + (end_xy[1] - start_xy[1]) * frac
        for kz in keepouts:
            if kz["min_x"] <= px <= kz["max_x"] and kz["min_y"] <= py <= kz["max_y"]:
                return False, str(kz.get("name", "keepout"))
    return True, None


class MapperRelay:
    """JSON-RPC handler for `studio.mapper.*` inside `microduck-bridge.py`."""

    def __init__(
        self,
        mapper_url: str | None = None,
        *,
        local_mode: bool = False,
        provenance_mode: str = "simulation",
        log=print,
    ) -> None:
        if mapper_url is not None and not is_local_mapper_url(mapper_url):
            raise MapperBridgeRefusal(
                f"refused non-local --mapper-url {mapper_url!r}; only loopback, RFC1918 LAN, "
                ".local, .ts.net, or .internal addresses are permitted"
            )
        self.mapper_url = mapper_url.rstrip("/") if mapper_url else None
        self.local_mode = bool(local_mode)
        self.provenance_mode = provenance_mode if provenance_mode in ("simulation", "physical_hardware") else "simulation"
        self.log = log

        self.software_hold = False
        self.trust_tier = "L0_OBSERVE"
        self.keepout_zones: list[dict[str, Any]] = [
            {"name": "stairwell_dropoff", "min_x": 3.2, "min_y": 4.1, "max_x": 5.0, "max_y": 5.8}
        ]
        self.records: list[dict[str, Any]] = []
        self.head_hash = GENESIS_HASH

    @property
    def enabled(self) -> bool:
        return self.mapper_url is not None or self.local_mode

    @staticmethod
    def wants(line: bytes) -> bool:
        return b'"studio.mapper.' in line

    @staticmethod
    def is_hold_line(line: bytes) -> bool:
        return b'"studio.mapper.hold"' in line

    def _record(self, event: str, decision: str, details: dict[str, Any]) -> dict[str, Any]:
        body = {
            "seq": len(self.records) + 1,
            "ts": round(time.time(), 3),
            "mode": self.provenance_mode,
            "trust_tier": self.trust_tier,
            "event": event,
            "decision": decision,
            "details": details,
            "prev_hash": self.head_hash,
        }
        digest = _canonical_sha256(body)
        rec = {**body, "hash": digest}
        self.records.append(rec)
        self.head_hash = digest
        return rec

    def _post_upstream(self, endpoint: str, payload: dict[str, Any]) -> dict[str, Any]:
        assert self.mapper_url is not None
        url = f"{self.mapper_url}{endpoint}"
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        # Never route LAN/loopback robot traffic through an HTTP proxy.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            with opener.open(req, timeout=3.0) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise MapperBridgeRefusal(f"upstream robot-gate mapper unreachable at {url}: {exc}") from exc

    def handle(self, line: bytes) -> bytes:
        rpc_id = None
        try:
            message = json.loads(line.decode("utf-8"))
            rpc_id = message.get("id") if isinstance(message, dict) else None
            method = message.get("method") if isinstance(message, dict) else None
            if method not in SUPPORTED_METHODS:
                raise MapperBridgeRefusal(f"unsupported mapper method {method!r}")
            if not self.enabled:
                raise MapperBridgeRefusal(
                    "this bridge was started without --mapper-url or --mapper-local; "
                    "pass --mapper-url http://127.0.0.1:8788 (robot-gate) or --mapper-local"
                )
            params = message.get("params") or {}
            if not isinstance(params, dict):
                raise MapperBridgeRefusal("params must be a JSON object")
            result = self._dispatch(method, params)
            reply: dict[str, Any] = {"jsonrpc": "2.0", "id": rpc_id, "result": result}
        except MapperBridgeRefusal as why:
            reply = {"jsonrpc": "2.0", "id": rpc_id, "error": {"code": -32602, "message": str(why)}}
        except (ValueError, UnicodeDecodeError) as why:
            reply = {"jsonrpc": "2.0", "id": rpc_id, "error": {"code": -32700, "message": f"invalid JSON: {why}"}}
        return json.dumps(reply, separators=(",", ":")).encode("utf-8") + b"\n"

    def _dispatch(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        if method == "studio.mapper.status":
            if self.mapper_url:
                upstream = self._post_upstream("/api/microduck/mapper/status", params)
                return {**upstream, "bridge_hold": self.software_hold, "safety_boundary_statement": SAFETY_BOUNDARY_STATEMENT}
            return {
                "mode": self.provenance_mode,
                "trust_tier": self.trust_tier,
                "software_hold": self.software_hold,
                "keepout_zones": self.keepout_zones,
                "record_count": len(self.records),
                "chain_head_hash": self.head_hash,
                "safety_boundary_statement": SAFETY_BOUNDARY_STATEMENT,
            }

        if method == "studio.mapper.hold":
            self.software_hold = True
            rec = self._record("software_hold", "HOLD", {"reason": str(params.get("reason", "operator_hold"))})
            if self.mapper_url:
                try:
                    self._post_upstream("/api/microduck/mapper/hold", params)
                except MapperBridgeRefusal:
                    # Fail-closed: local HOLD stays latched and robot.stop is still emitted by Relay.
                    pass
            return {
                "decision": "HOLD",
                "software_hold": True,
                "robot_stop_forwarded": True,
                "receipt_hash": rec["hash"],
                "safety_boundary_statement": SAFETY_BOUNDARY_STATEMENT,
            }

        if method == "studio.mapper.ingest":
            pose = params.get("pose_xytheta")
            if not isinstance(pose, list) or len(pose) != 3 or not all(_is_finite(v) for v in pose):
                rec = self._record("ingest", "HOLD", {"reason": "NON_FINITE_POSE"})
                return {"accepted": False, "decision": "HOLD", "reason": "NON_FINITE_POSE", "receipt_hash": rec["hash"]}
            conf = params.get("mean_confidence", 1.0)
            min_conf = params.get("min_confidence", DEFAULT_MIN_CONFIDENCE)
            if not _is_finite(conf) or not _is_finite(min_conf) or float(conf) < float(min_conf):
                rec = self._record("ingest", "HOLD", {"reason": "LOW_SEGMENTATION_CONFIDENCE"})
                return {
                    "accepted": False,
                    "decision": "HOLD",
                    "reason": "LOW_SEGMENTATION_CONFIDENCE",
                    "receipt_hash": rec["hash"],
                }
            if self.mapper_url:
                return self._post_upstream("/api/microduck/mapper/ingest", params)
            rec = self._record("ingest", "ALLOW", {"pose_xytheta": pose, "mean_confidence": float(conf)})
            return {"accepted": True, "decision": "ALLOW", "reason": "ok", "receipt_hash": rec["hash"]}

        if method == "studio.mapper.plan":
            if self.software_hold:
                rec = self._record("plan", "HOLD", {"reason": "SOFTWARE_HOLD_LATCHED"})
                return {"decision": "HOLD", "reason": "SOFTWARE_HOLD_LATCHED", "receipt_hash": rec["hash"]}
            health = _check_biped_health_dict(params.get("health"))
            if not health["ok"]:
                rec = self._record("plan", "HOLD", {"faults": health["fault_codes"]})
                return {
                    "decision": "HOLD",
                    "reason": f"BIPED_HEALTH_HOLD: {'; '.join(health['reasons'])}",
                    "health_verdict": health,
                    "receipt_hash": rec["hash"],
                }
            if self.mapper_url:
                return self._post_upstream("/api/microduck/mapper/plan", params)

            pose = params.get("pose_xytheta")
            target = params.get("target_xy")
            if (
                not isinstance(pose, list) or len(pose) < 2 or not all(_is_finite(v) for v in pose[:2])
                or not isinstance(target, list) or len(target) < 2 or not all(_is_finite(v) for v in target[:2])
            ):
                rec = self._record("plan", "HOLD", {"reason": "NON_FINITE_PLAN_COORDS"})
                return {"decision": "HOLD", "reason": "NON_FINITE_PLAN_COORDS", "receipt_hash": rec["hash"]}

            keepouts = params.get("keepout_zones") or self.keepout_zones
            allowed, violator = _check_swept_path_2d(
                (float(pose[0]), float(pose[1])),
                (float(target[0]), float(target[1])),
                keepouts,
            )
            if not allowed:
                rec = self._record("plan", "DENY", {"violator": violator})
                return {
                    "decision": "DENY",
                    "reason": f"Swept path enters Envelope 0.2 keep-out '{violator}'",
                    "gate_violator": violator,
                    "health_verdict": health,
                    "receipt_hash": rec["hash"],
                }
            tier = str(params.get("trust_tier") or self.trust_tier)
            if tier == "L0_OBSERVE":
                rec = self._record("plan", "HOLD", {"reason": "TRUST_TIER_L0_OBSERVE"})
                return {
                    "decision": "HOLD",
                    "reason": "L0_OBSERVE permits zero motion; switch to L1_ATOMIC to approve a bounded step",
                    "gate_violator": "TRUST_TIER_L0_OBSERVE",
                    "health_verdict": health,
                    "receipt_hash": rec["hash"],
                }
            rec = self._record("plan", "ALLOW", {"target_xy": target, "trust_tier": tier})
            return {
                "decision": "ALLOW",
                "reason": "Swept path cleared Envelope 0.2 keep-outs",
                "target_xy": target,
                "gate_violator": None,
                "health_verdict": health,
                "receipt_hash": rec["hash"],
            }

        if method == "studio.mapper.receipt":
            if self.mapper_url:
                return self._post_upstream("/api/microduck/mapper/receipt", params)
            payload = {
                "schema": "graft-microduck-dual-demo-bundle/1.0",
                "mode": self.provenance_mode,
                "record_count": len(self.records),
                "chain_head_hash": self.head_hash,
                "safety_boundary_statement": SAFETY_BOUNDARY_STATEMENT,
            }
            return {**payload, "bundle_sha256": f"sha256:{_canonical_sha256(payload)}"}

        raise MapperBridgeRefusal(f"unhandled mapper method {method!r}")
