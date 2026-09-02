#!/bin/bash
# The rule: StudioKit computes, DuckStudio displays.
#
# This greps the shipping SwiftUI sources for tokens that could only appear if
# somebody recomputed something the kit already knows. It exists because the
# failure it prevents is silent: the moment two places know the observation
# layout, or the action scale, or which joints the low-pass treats as head
# joints, they disagree — and the disagreement shows up as a plot that is subtly
# wrong rather than as a crash. A wrong number in a debugger is worse than no
# debugger, because it is believed.
#
# Same guard shape as OpenCastor's check_no_policy_reimpl.sh, for the same
# reason. Run from anywhere; wired into the Mac build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/DuckStudio"

if [ ! -d "$APP" ]; then
  echo "check_no_studio_math: no app target yet ($APP) — nothing to check."
  exit 0
fi

# Each pattern is a thing only the kit is allowed to know.
#   homePose/actionScale/lowpass/jointRanges — robot constants, DuckKit's
#   mean[/std[/exp(                          — the normalizer and ELU, redone
#   \b61\b / \b197 774\b                     — the observation width as a literal
PATTERNS=(
  'homePose'
  'actionScale'
  'lowpass'
  'lowPass'
  'jointRanges'
  'mean\['
  'std\['
  'exp[(]'
  '\b61\b'
)

status=0
for pattern in "${PATTERNS[@]}"; do
  # --include limits this to shipping sources; previews and tests are exempt
  # because a preview inventing a number harms nobody.
  # `|| true` on the pipeline would swallow a BROKEN PATTERN as a pass. It did:
  # `exp(` is an unmatched group in ERE, grep exited 2, and the guard cheerfully
  # reported the app target clean. Exit 1 means "no matches" and is fine; exit 2
  # means grep could not run the pattern and must fail the check loudly.
  # errexit has to come OFF around this: grep exits 1 for "no matches", which
  # is the SUCCESS case here, and `set -e` would kill the script on the first
  # clean pattern — the guard would then pass by dying quietly, which is the
  # same false pass in a different costume.
  # `rc` is grep's exit for THIS pattern; `status` accumulates across all of
  # them. They were one variable, so each iteration clobbered the verdict — and
  # since the last pattern normally finds nothing, grep's exit 1 became a
  # permanent false FAILURE regardless of what any earlier pattern had found.
  set +e
  hits=$(grep -rnE "$pattern" "$APP" --include='*.swift' 2>&1)
  rc=$?
  set -e
  if [ $rc -gt 1 ]; then
    echo "BROKEN PATTERN '$pattern': $hits"
    exit 2
  fi
  hits=$(printf '%s' "$hits" | grep -v '_Preview' | grep -v '// math-ok:' || true)
  if [ -n "$hits" ]; then
    echo "FORBIDDEN: '$pattern' in the app target — this belongs in StudioKit."
    echo "$hits"
    status=1
  fi
done

# ── the second language ──────────────────────────────────────────────────────
#
# THE GREP ABOVE READS SWIFT AND THE APP NOW SHIPS JAVASCRIPT. Everything under
# DuckStudio/Resources/phonebench is the bench: MuJoCo's WebAssembly build, the
# bench core, duckloop.mjs and the policy's forward pass. Every one of those
# files knows exactly the things the patterns above forbid — the observation
# width, the action scale, the normalizer, the ELU — so a pattern pass over them
# would fail on the first line and could never be made to pass. Grepping them
# for forbidden tokens is the wrong question.
#
# THE RIGHT QUESTION IS WHETHER THEY ARE THE FILES THEY CLAIM TO BE. They are
# vendored, byte for byte, from duck-sounds by scripts/make_phone_bench.sh,
# which writes MANIFEST.json with a sha256 per file. So this pass proves two
# things: nothing in the folder is missing from the manifest, and nothing in the
# folder differs from what the manifest says it is. A .mjs edited in this repo
# to recompute something the kit already knows — the exact failure the Swift
# patterns exist to catch, in the language they cannot read — changes a digest
# and fails here.
#
# AN ABSENT FOLDER IS NOT A FAILURE. A fresh checkout has not run the assembly
# script yet, and a gate that failed on that would be a gate people learn to
# skip. It says so and moves on; the build is what needs the folder, and the
# build is what will say so.
PHONE_BENCH="$APP/Resources/phonebench"
MANIFEST="$PHONE_BENCH/MANIFEST.json"

digest() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

if [ ! -d "$PHONE_BENCH" ]; then
  echo "check_no_studio_math: no phone bench assembled yet ($PHONE_BENCH)."
  echo "  Run scripts/make_phone_bench.sh before building."
elif [ ! -f "$MANIFEST" ]; then
  echo "FORBIDDEN: $PHONE_BENCH exists with no MANIFEST.json."
  echo "  Vendored physics with no digests is physics nobody can check. Re-run"
  echo "  scripts/make_phone_bench.sh rather than adding files by hand."
  status=1
else
  vendored=0
  # Every file in the folder must be named by the manifest, and match it.
  while IFS= read -r file; do
    rel="${file#$PHONE_BENCH/}"
    [ "$rel" = "MANIFEST.json" ] && continue
    vendored=$((vendored + 1))
    # ONE MANIFEST ROW, MATCHED AS A FIXED STRING. `grep -F` and not a pattern
    # for two reasons, both of which bit on the way here. A path is full of
    # regex metacharacters — `duckloop.mjs` as a pattern also matches
    # `duckloopXmjs` — and the quotes either side of the path are what stop a
    # row for `assets/x.mjs` from satisfying a file called `x.mjs`.
    #
    # AND ERREXIT COMES OFF AROUND IT. `claimed=$(grep …)` takes grep's exit
    # status as the assignment's, and grep exits 1 for "no match" — which is
    # precisely the case this check exists to report. With `set -e` on, the
    # script died at that line and printed nothing at all: an unlisted .mjs made
    # the guard exit non-zero with no message, which is the same false pass in a
    # different costume as the one documented above. Exit 2 means grep itself
    # could not run and must still be loud.
    set +e
    row=$(grep -F "\"path\": \"$rel\", \"bytes\": " "$MANIFEST")
    rc=$?
    set -e
    if [ $rc -gt 1 ]; then
      echo "BROKEN MANIFEST READ for '$rel': grep exited $rc"
      exit 2
    fi
    claimed=$(printf '%s' "$row" | sed 's/.*"sha256": "//; s/".*//')
    if [ -z "$claimed" ]; then
      echo "FORBIDDEN: $rel is in the phone bench and not in MANIFEST.json."
      echo "  Nothing under Resources/phonebench may be authored in this repo."
      status=1
      continue
    fi
    actual=$(digest "$file")
    if [ "$claimed" != "$actual" ]; then
      echo "FORBIDDEN: $rel does not match MANIFEST.json."
      echo "  manifest $claimed"
      echo "  on disk  $actual"
      echo "  A vendored artefact was edited here. Change it in duck-sounds and"
      echo "  re-run scripts/make_phone_bench.sh."
      status=1
    fi
  done < <(find "$PHONE_BENCH" -type f | sort)

  # And every file the manifest names must be there — a deleted asset is a page
  # that 404s at runtime and nowhere else.
  while IFS= read -r rel; do
    [ -f "$PHONE_BENCH/$rel" ] && continue
    echo "FORBIDDEN: MANIFEST.json names $rel and it is not there."
    status=1
  done < <(grep -o '"path": "[^"]*"' "$MANIFEST" | sed 's/"path": "//; s/"$//')

  # THE COUNT IS PRINTED SO A PASS CANNOT BE A PASS OVER NOTHING. A find that
  # matched no files would otherwise report the same clean line as a folder that
  # was fully checked.
  if [ $status -eq 0 ]; then
    echo "check_no_studio_math: $vendored vendored files under Resources/phonebench"
    echo "  match MANIFEST.json byte for byte."
  fi
fi

if [ $status -eq 0 ]; then
  echo "check_no_studio_math: clean — the app target draws and does not compute."
else
  echo
  echo "If a line is genuinely presentational, append '// math-ok:' and say why."
fi
exit $status
