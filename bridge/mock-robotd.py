#!/usr/bin/env python3
"""A robotd-shaped socket for people without a duck.

IT ANSWERS THE SHAPE AND CLAIMS NOTHING ELSE. It speaks JSON-RPC lines, accepts
every method, answers with a plausible result and records what it was asked, so
the bridge and the app can be exercised end to end on a laptop. It is not a
simulator: nothing here has physics, and a state it returns is a constant. Use
the bench for a duck that moves.

FOUR METHODS NOW ANSWER IN THE WIRE'S OWN SHAPE, AND HERE IS WHY. Until
2026-09-08 this file answered `{"ok": true}` to everything. That is honest about
having no duck and it is useless as a fixture, because the one class of bug a
mock robotd could catch is a client reading a key the daemon does not send, and
`{"ok": true}` has no keys to get wrong. OpenCastor shipped four such reads for
weeks — `result["networks"]` from `robot.subscribe`, `res["loop"]` and
`loop["hz"]` from `robot.health`, and `state["battery"]` from a state stream
that carries no battery — on the exact path its hardware guide prints filled-in
example output for, and nothing caught them.

So `hello`, `robot.health`, `robot.subscribe` and `robot.policies` answer with
the real field names. **Every one is transcribed from
`pollen-robotics/microduck` at rev `5620aa2`, never invented, with the source
line beside it.** Anything else still gets `{"ok": true}`: a mock that refuses
an unknown method tests our list of methods rather than the client.

The same four fixtures live in OpenCastor at `castor/bench/mock_robotd.py`, so
`castor bench ten-minutes --ci` can run without this repository checked out.
Both were transcribed from the same lines; change one and change the other.
"""
import argparse, json, os, socket, threading, time

# ── the shaped replies, from duck-ipc-proto/src/lib.rs @ 5620aa2 ────────────

# HelloResult, :2800-2807. `revision` is None for a build that did not come from
# CI, which is what a mock is, and it is always serialised including as null.
HELLO = {
    "api_version": 25,          # :2801, and `pub const API_VERSION: u32 = 25` at :304
    "daemon_version": "0.0.0-mock",  # :2802
    "revision": None,           # :2806
}

# HealthResult, :3089-3147, with LoopHealth :3152-3167, Battery :3263-3265 and
# BusHealth :3174-3184 nested in it.
#
# THE KEY IS `control_loop`, NOT `loop`, AND THERE IS NO SERDE RENAME (:3140).
# `loop` with an `hz` inside it is a *state stream* key (LoopState, :3512-3517),
# and conflating the two is the whole bug.
#
# THE BATTERY IS HERE AND NOWHERE ELSE. `RobotState` (:3317-3365) carries no
# battery at all, which is why a battery guard written against the state stream
# has never fired.
HEALTH = {
    "healthy": True,            # :3090
    "degraded": False,          # :3103
    "control_loop": {           # :3140
        "target_hz": 50.0,      # :3155
        "achieved_hz": 49.8,    # :3159 — Option; a real one is null until the first window
        "ticks": 124000,        # :3160
        "missed": 0,            # :3164 — and there is no `hz` in here
        "last_tick_age_ms": 12, # :3166
    },
    "battery": {                # :3118
        "volts": 7.9,           # :3264
        "percent": 64.0,        # :3265
    },
    "bus": {                    # :3144 — present on every answer; the zeros mean "no failures"
        "consecutive_errors": 0,  # :3179
        "startup_failures": 0,    # :3183
    },
}

# SubscribeResult, :2519-2546. THERE IS NO `networks` KEY. The policy a client
# wants is `walk`, and the skills are a list rather than a field per skill.
SUBSCRIBE = {
    "accepted": True,                       # :2520 — `accepted`, not `status`
    "walk": "alpha_walking.onnx",           # :2525
    "stand": "alpha_stand.onnx",            # :2529
    "sitstand": "alpha_sitstand.onnx",      # :2539
    "ground_pick": "alpha_ground_pick.onnx",# :2541
    "skills": ["ground_pick", "kick_left", "kick_right", "sit_toggle", "roulade"],  # :2546
}

# PoliciesResult, :2218-2248, with PolicySlot :2253-2269. `origin` is
# "official", "community" or "local", and is absent when the slot is empty.
POLICIES = {
    "mode": "walk",       # :2220
    "enabled": True,      # :2224
    "slots": [            # :2226
        {"slot": "walk", "path": "alpha_walking.onnx", "origin": "official",
         "overridden": False, "error": None},   # :2255, :2258, :2263, :2265, :2268
        {"slot": "stand", "path": "alpha_stand.onnx", "origin": "official",
         "overridden": False, "error": None},
    ],
    "skills": list(SUBSCRIBE["skills"]),  # :2235
}

SHAPED = {
    "hello": HELLO,                 # :417
    "robot.health": HEALTH,         # :442
    "robot.subscribe": SUBSCRIBE,   # :640
    "robot.policies": POLICIES,     # :582
}

def serve(path):
    if os.path.exists(path):
        os.unlink(path)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(4)
    print(f"mock robotd on {path} — every method accepted, nothing simulated")
    while True:
        conn, _ = server.accept()
        threading.Thread(target=talk, args=(conn,), daemon=True).start()

def talk(conn):
    buf = b""
    while True:
        chunk = conn.recv(4096)
        if not chunk:
            return
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            try:
                call = json.loads(line)
            except json.JSONDecodeError:
                continue
            method = call.get("method", "?")
            print(f"  <- {method} {json.dumps(call.get('params', {}))[:80]}")
            if call.get("id") is None:
                continue
            shaped = SHAPED.get(method)
            result = (json.loads(json.dumps(shaped)) if shaped is not None
                      else {"ok": True, "method": method, "t": round(time.time(), 3)})
            conn.sendall(json.dumps({
                "jsonrpc": "2.0", "id": call["id"], "result": result,
            }).encode() + b"\n")

if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--socket", default="/tmp/mock-robotd.sock")
    serve(p.parse_args().socket)
