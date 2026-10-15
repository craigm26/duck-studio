#!/bin/sh
# One duck in Pollen's duck-sim, standing, with its head camera rendered beside
# it (eye.py) and served by Pollen's own mediad as /frame and media.frame: the
# duck the card reader was proved against on 2026-10-14.
#
#   MICRODUCK=~/microduck MICRODUCK_RL=~/microduck_rl cardreader/sim/up.sh scene_card.xml
#   cd cardreader && python3 -m duckcards watch --frame-url http://127.0.0.1:8080/frame \
#       --robot-socket ~/.cache/duck-sim/duck-a.sock --camera-degrees 72.7
#   cardreader/sim/down.sh
#
# NEEDS, ONCE (the README's "Proving it in duck-sim" has the whole list):
#   - pollen-robotics/microduck, built: cargo build -p robotd -p robotctl -p tof
#     -p sounds -p configd -p updater -p mediad, with GStreamer's dev packages;
#   - GStreamer's webrtcsink, which mediad will not start without and Ubuntu does
#     not package: crates.io gst-plugin-webrtc 0.15.4, built with
#     --no-default-features --features rustls-ring, its .so on GST_PLUGIN_PATH;
#   - pollen-robotics/microduck_rl on its develop branch (the head camera), with a
#     .venv holding mujoco, numpy and onnxruntime (uv.lock's versions);
#   - the policies: microduck's scripts/seed-policies.sh.
#
# DUCK-SIM'S OWN CAMERA IS LEFT OFF ON PURPOSE (DUCK_SIM_CAMERAS unset): without a
# GPU it slows the world to half speed and the duck falls (eye.py says more).
set -eu
SCENE="$(realpath "${1:?usage: up.sh SCENE.xml (cardreader/sim/scene.py writes one)}")"
: "${MICRODUCK:?set MICRODUCK to a built checkout of pollen-robotics/microduck}"
: "${MICRODUCK_RL:?set MICRODUCK_RL to a checkout of pollen-robotics/microduck_rl (develop) with its .venv}"
HERE="$(cd "$(dirname "$0")" && pwd)"
S="${DUCK_SIM_STATE:-$HOME/.cache/duck-sim}"
export DUCK_SIM_RL="$MICRODUCK_RL" DUCK_SIM_VIEWER=0 DUCK_SIM_SCENE="$SCENE" MUJOCO_GL="${MUJOCO_GL:-egl}"
unset DUCK_SIM_CAMERAS
cd "$MICRODUCK"
scripts/duck-sim

MUJOCO_GL="$MUJOCO_GL" setsid nohup "$MICRODUCK_RL/.venv/bin/python" "$HERE/eye.py" "$SCENE" \
    --body-port 7801 --frame-port 7901 --fps 4 > "$S/eye.log" 2>&1 &
echo $! > "$S/eye.pid"
sleep 6

# mediad, with the arguments duck-sim gives it when it starts one for a camera.
printf '[media]\nquality = "360p30"\n' > "$S/mediad-duck-a.toml"
DUCK_RUNTIME_DIR="$S" RUST_LOG=info setsid nohup "$MICRODUCK/target/debug/mediad" \
    --sim-camera 127.0.0.1:7901 --config "$S/mediad-duck-a.toml" \
    --robot-socket "$S/duck-a.sock" --tof-socket "$S/duck-a-tof.sock" \
    --config-socket "$S/duck-a-config.sock" --updater-socket "$S/duck-a-updater.sock" \
    --token "$S/duck-a/hf-token" --frame-socket "$S/duck-a-frame.sock" \
    --port 8443 --web-port 8080 > "$S/duck-a-media.log" 2>&1 &
echo $! > "$S/duck-a-media.pid"
sleep 5

scripts/duck-sim realtime
curl -s -o /dev/null -w "/frame: %{http_code} %{content_type} %{size_download} bytes\n" http://127.0.0.1:8080/frame
