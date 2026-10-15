#!/bin/sh
# One duck in Pollen's duck-sim, standing, with its head camera rendered beside
# it (eye.py) and served by Pollen's own mediad as /frame and media.frame: the
# duck the card reader was proved against on 2026-10-14.
#
#   export MICRODUCK=~/microduck MICRODUCK_RL=~/microduck_rl
#   cardreader/sim/up.sh                                  # the duck, no cards yet
#   $MICRODUCK_RL/.venv/bin/python cardreader/sim/scene.py --from-duck row.xml start.png,roll.png,end.png
#   cardreader/sim/look.sh row.xml                        # the duck sees them
#   cd cardreader && python3 -m duckcards watch --frame-url http://127.0.0.1:8080/frame \
#       --robot-socket ~/.cache/duck-sim/duck-a.sock --camera-degrees 72.7
#   cardreader/sim/down.sh
#
# `up.sh SCENE.xml` starts with cards already in place instead, where scene.py
# put them; the duck seldom stands where a scene made in advance expects it.
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
: "${MICRODUCK:?set MICRODUCK to a built checkout of pollen-robotics/microduck}"
: "${MICRODUCK_RL:?set MICRODUCK_RL to a checkout of pollen-robotics/microduck_rl (develop) with its .venv}"
HERE="$(cd "$(dirname "$0")" && pwd)"
S="${DUCK_SIM_STATE:-$HOME/.cache/duck-sim}"
mkdir -p "$S"
if [ $# -ge 1 ]; then
    SCENE="$(realpath "$1")"
else
    SCENE="$S/scene-no-cards.xml"
    python3 "$HERE/scene.py" --rl "$MICRODUCK_RL" "$SCENE"
fi
export DUCK_SIM_RL="$MICRODUCK_RL" DUCK_SIM_VIEWER=0 DUCK_SIM_SCENE="$SCENE" MUJOCO_GL="${MUJOCO_GL:-egl}"
unset DUCK_SIM_CAMERAS
(cd "$MICRODUCK" && scripts/duck-sim)
"$HERE/look.sh" "$SCENE"
(cd "$MICRODUCK" && scripts/duck-sim realtime)
