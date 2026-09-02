#!/usr/bin/env bash
# Assemble DuckStudio/Resources/phonebench — the bench that ships inside the app.
#
# WHY IT IS ASSEMBLED AND NOT AUTHORED HERE. Every file it serves already has a
# home in duck-sounds: the bench core, the plant and the forward pass in sim/,
# the MuJoCo WebAssembly build in site/vendor/. A hand-maintained second copy in
# this repo is a copy that goes stale, and the one that would go stale silently
# is scene.mjb — a phone running a different plant from the desk bench would
# still answer every endpoint and would quietly be measuring a different world.
#
# AND IT IS WHY THE MANIFEST EXISTS. `scripts/check_no_studio_math.sh` cannot
# read JavaScript for the things it forbids in Swift; what it can do is prove
# that every .mjs and .html under this folder is byte-identical to the artefact
# named in MANIFEST.json. That turns "no physics in the app target" from a grep
# over one language into a claim about the whole bundle: a .mjs edited here to
# recompute an observation would change its digest and fail the gate.
#
# WHAT IS DELIBERATELY NOT COPIED: the policies. duck-sounds ships
# site/phonebench/assets/policies/*.bin, and this app does not, because it
# already bundles the .onnx those bins were made from. `PhoneBenchAssets`
# exports DuckPolicy.canonicalParameterBytes from them at runtime, which means
# the phone runs exactly the numbers DuckEvidence fingerprinted rather than a
# second copy that could drift. The server synthesises policies/manifest.json to
# match.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${DUCK_SOUNDS:-$HOME/projects/duck-sounds}"
OUT="$HERE/DuckStudio/Resources/phonebench"

if [ ! -d "$SOURCE/sim" ]; then
  echo "make_phone_bench: no duck-sounds at $SOURCE" >&2
  echo "Set DUCK_SOUNDS to where it is checked out." >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/assets"

# THE SHELL PAGE. It is the probe page from duck-sounds, unchanged, and that is
# on purpose: it installs `globalThis.duckbench` — the whole bridge the app
# talks through — and then measures the phone it is running on and prints what
# it found. Shipping the measurement rather than stripping it means the one
# machine whose numbers matter can be asked for them.
cp "$SOURCE/site/phonebench/index.html" "$OUT/index.html"

# THE BENCH, SPLIT THE WAY THE CORE OWNER SPLIT IT. duckbench-core.mjs is the
# physics with no machine in it; duckbench-web.mjs is this machine's description
# and the `install()` that puts the bench behind one function. duckloop.mjs is
# taken from site/ and not from sim/: in sim/ that name is a re-export of the
# site's file, and a browser has no `../site` to reach into.
cp "$SOURCE/sim/duckbench-core.mjs"     "$OUT/assets/"
cp "$SOURCE/sim/duckbench-web.mjs"      "$OUT/assets/"
cp "$SOURCE/sim/policyforward.mjs"      "$OUT/assets/"
cp "$SOURCE/site/duckloop.mjs"          "$OUT/assets/duckloop.mjs"
cp "$SOURCE/sim/duckkit-constants.json" "$OUT/assets/"

# THE CLIMB SCORER AND THE THREE FILES IT IMPORTS, under the names the core
# imports them by. The bench answers POST /climb — one cell of the stairs
# challenge's fourteen — out of `sim/climb_score.mjs`, which is the SAME episode
# climb/rig3.mjs and climb/robust.mjs run, so a cell scored on the phone is the
# cell the audit published rather than one that resembles it
# (duck-sounds sim/climb_parity.mjs is the gate that says so). It reaches its
# staircase, its event block and its servo law through `./stairs.js`,
# `./climb_event.mjs` and `./climb_servo.mjs`; in sim/ those are re-export shims
# pointing at site/ and climb/, and a WebView has no `../site` or `../climb` to
# reach into, so here they ARE the files — the same reason duckloop.mjs is taken
# from site/. Leave one out and the app boots, /health answers, and the Stairs
# Challenge dies on its first cell with a module-not-found.
cp "$SOURCE/sim/climb_score.mjs"        "$OUT/assets/"
cp "$SOURCE/site/stairs.js"             "$OUT/assets/stairs.js"
cp "$SOURCE/climb/event.mjs"            "$OUT/assets/climb_event.mjs"
cp "$SOURCE/climb/servo.mjs"            "$OUT/assets/climb_servo.mjs"

# THE CHASE SCORER, AND THE ONE FILE IT SHARES WITH THE CORE. The bench also
# answers POST /chase — one cell of the BALL challenge's fourteen — out of
# `sim/chase_score.mjs`, which is the SAME episode `chase/chase_rig.mjs` and
# `chase/chase_robust.mjs` run, so a cell scored on the phone is the cell the
# package published rather than one that resembles it (duck-sounds
# chase/chase_parity.mjs is the gate that says so). It takes the keyframe
# interpolation curve and the 45-of-50 tail bar from `./climb_score.mjs`, copied
# just above, and its quaternion arithmetic from `./reward_math.mjs` — which
# duckbench-core.mjs imports as well, because /tune and /chase transcribe two
# different Pollen configs that share three terms and must not each hold a copy
# of one formula. Leave either out and the app boots, /health answers, and the
# Ball Challenge dies on its first cell with a module-not-found.
cp "$SOURCE/sim/chase_score.mjs"        "$OUT/assets/"
cp "$SOURCE/sim/reward_math.mjs"        "$OUT/assets/"

# THE PLANT, FROM sim/. `site/scene.mjb` and `sim/scene.mjb` share a name and
# differ in bytes (duck-sounds PLANT.md), and it is sim/'s that every clip in
# duckkit is stamped with. Copying the wrong one is the failure this script
# exists to prevent, which is why its digest is printed at the end and can be
# read straight off /health.
cp "$SOURCE/sim/scene.mjb"              "$OUT/assets/"

# THE SAME MuJoCo THE DESK BENCH RUNS, CHECKED RATHER THAN ASSUMED. The claim
# that a number from the phone is comparable with a number from the Pi rests
# entirely on these two files being the build duckbench.mjs imports. `npm
# update` in sim/ would move one and not the other, and the app would then be
# running a different integrator while saying it was running the same one.
for f in mujoco.js mujoco.wasm; do
  vendored="$SOURCE/site/vendor/$f"
  running="$SOURCE/sim/node_modules/mujoco/$f"
  if [ -f "$running" ] && ! cmp -s "$vendored" "$running"; then
    echo "site/vendor/$f differs from sim/node_modules/mujoco/$f." >&2
    echo "The app would not be running the desk bench's physics. Re-vendor first." >&2
    exit 1
  fi
  cp "$vendored" "$OUT/assets/"
done

# THE MANIFEST. Path, size, sha256 and where each file came from, so the gate
# can prove nothing was edited after the copy and a reader can find the origin
# of any byte in the folder.
{
  printf '{\n'
  printf '  "why": "Vendored from duck-sounds by scripts/make_phone_bench.sh. Nothing here is\\nauthored in this repo; check_no_studio_math.sh proves it by digest.",\n'
  printf '  "source": "duck-sounds",\n'
  printf '  "files": [\n'
  first=1
  while IFS= read -r path; do
    rel="${path#$OUT/}"
    sum=$(sha256sum "$path" | cut -d' ' -f1)
    size=$(wc -c < "$path" | tr -d ' ')
    [ $first -eq 1 ] || printf ',\n'; first=0
    printf '    { "path": "%s", "bytes": %s, "sha256": "%s" }' "$rel" "$size" "$sum"
  done < <(find "$OUT" -type f ! -name MANIFEST.json | sort)
  printf '\n  ]\n}\n'
} > "$OUT/MANIFEST.json"

echo "phonebench assembled into DuckStudio/Resources/phonebench"
echo "  plant  scene.mjb $(sha256sum "$OUT/assets/scene.mjb" | cut -d' ' -f1)"
echo "  mujoco mujoco.wasm $(sha256sum "$OUT/assets/mujoco.wasm" | cut -d' ' -f1)"
du -sh "$OUT"
find "$OUT" -type f | sed "s|$HERE/||" | sort
