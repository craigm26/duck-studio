#!/bin/sh
# Show the running sim duck a scene: (re)start the eye and mediad on it.
#
#   cardreader/sim/look.sh row.xml
#
# duck-body keeps the scene it was started with. That is safe because the card
# plates scene.py writes touch nothing (contype and conaffinity 0): only what the
# camera sees changes, so cards can be laid out after the duck has stood up and
# shown where it actually stands (scene.py --from-duck).
set -eu
SCENE="$(realpath "${1:?usage: look.sh SCENE.xml (cardreader/sim/scene.py writes one)}")"
: "${MICRODUCK:?set MICRODUCK to a built checkout of pollen-robotics/microduck}"
: "${MICRODUCK_RL:?set MICRODUCK_RL to a checkout of pollen-robotics/microduck_rl (develop) with its .venv}"
HERE="$(cd "$(dirname "$0")" && pwd)"
S="${DUCK_SIM_STATE:-$HOME/.cache/duck-sim}"
stop() {        # a pid file, and the word its process must have in its command line
    [ -f "$S/$1" ] || return 0
    pid="$(cat "$S/$1")"
    rm -f "$S/$1"
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "$2" && kill "$pid"
    sleep 1
    return 0
}
stop eye.pid eye.py
stop duck-a-media.pid mediad

MUJOCO_GL="${MUJOCO_GL:-egl}" setsid nohup "$MICRODUCK_RL/.venv/bin/python" "$HERE/eye.py" "$SCENE" \
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
curl -s -o /dev/null -w "/frame: %{http_code} %{content_type} %{size_download} bytes\n" http://127.0.0.1:8080/frame
