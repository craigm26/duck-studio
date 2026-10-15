#!/bin/sh
# Stop what up.sh started: the eye, the mediad it started by hand, and duck-sim.
#
#   MICRODUCK=~/microduck MICRODUCK_RL=~/microduck_rl cardreader/sim/down.sh
S="${DUCK_SIM_STATE:-$HOME/.cache/duck-sim}"
stop() {        # a pid file, and the word its process must have in its command line
    [ -f "$S/$1" ] || return 0
    pid="$(cat "$S/$1")"
    rm -f "$S/$1"
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "$2" && kill "$pid"
    return 0
}
stop eye.pid eye.py
stop duck-a-media.pid mediad
: "${MICRODUCK:?set MICRODUCK to the checkout of pollen-robotics/microduck up.sh used}"
cd "$MICRODUCK" && DUCK_SIM_RL="${MICRODUCK_RL:-}" scripts/duck-sim down
