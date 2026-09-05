#!/usr/bin/env bash
# Does inspect-robots read what this phone writes, in inspect-robots' own Python?
#
# THE FAILURE THIS EXISTS TO CATCH IS A LOG THAT IS ONLY VALID IN SWIFT.
# StudioKit's own tests prove the writer re-encodes upstream's reference log
# byte for byte, and that is the check that runs on every commit because it
# needs no Python and no network. It is still one language grading its own
# homework. This gate writes the whole fixture corpus out of the shipping
# writer, hands it to the real library at a pinned version, and requires three
# things of every file: read_eval_log opens it, their own json.dumps of their
# own _sanitize of their own parse reproduces the bytes exactly, and
# `inspect-robots view` renders it. A person handed one of these files types
# that last command, so that last command is in the gate.
#
# AND IT IS A SEPARATE SCRIPT FROM check_evallog_schema.sh. That one is a grep
# over the tree answering "is the schema spelled once"; this one runs a Swift
# build and a Python library answering "does the other project agree". One red
# light must not mean two unrelated things, which is the argument
# check_phonebench_fresh.sh:19-23 already makes in this repository.
#
# IT NEVER EXITS 0 WHEN IT COULD NOT RUN. No toolchain, no venv, no network to
# build one, an empty corpus, or a corpus that does not match
# scripts/evallog_fixtures.txt are all non-zero exits with the command to fix
# them printed. A gate that passes when the thing it checks is absent is the
# failure check_no_studio_math.sh:44-52 records having shipped once.
#
# PROVED ABLE TO FAIL. On 2026-09-05 the corpus was copied aside and three
# things were done to the copy, one at a time: one space added inside
# walk_clean.json (exit 1, "their own writer does not reproduce this file,
# 25149 bytes in, 25148 out"), walk_clean.json deleted (exit 2, "in the list
# and not in the corpus on disk"), and an unlisted surprise.json added (exit 2,
# "in the corpus on disk and not in the list"). The real corpus was untouched
# and the gate stayed green over it.
#
# WHICH VENV. Set INSPECT_ROBOTS_VENV to reuse one that already exists, which
# is the fast path on a machine that has run this before. Otherwise one is
# built at StudioKit/.build/evallog-parity/venv and inspect-robots is pinned
# into it at the version below. Pinned, because a parity result against
# whatever happened to be on PyPI this morning is not a parity result.
#
# Usage:  scripts/check_evallog_parity.sh
#         INSPECT_ROBOTS_VENV=/path/to/venv scripts/check_evallog_parity.sh
# Run from anywhere. Exit 0 = every fixture is a file inspect-robots can read.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.58.0"
SWIFT_HOME="${SWIFT_TOOLCHAIN:-$HOME/swift-6.3.3}"
WORK="$HERE/StudioKit/.build/evallog-parity"
CORPUS="$HERE/StudioKit/.build/evallog-fixtures"
VENV="${INSPECT_ROBOTS_VENV:-$WORK/venv}"

# ONLY 6.3.3. A run under 6.1.2 poisons StudioKit/.build until the debug
# directory is deleted, so this refuses rather than falling back to whichever
# swift is on PATH.
if [ ! -x "$SWIFT_HOME/usr/bin/swift" ]; then
  echo "check_evallog_parity: no swift at $SWIFT_HOME/usr/bin/swift" >&2
  echo "  This package builds with 6.3.3 and nothing else. Set SWIFT_TOOLCHAIN" >&2
  echo "  if it lives somewhere other than \$HOME/swift-6.3.3." >&2
  exit 2
fi

if [ ! -f "$HERE/scripts/evallog_fixtures.txt" ]; then
  echo "check_evallog_parity: no scripts/evallog_fixtures.txt" >&2
  echo "  That file is the pinned corpus. Without it this gate has no expectation." >&2
  exit 2
fi

# 1. Write the corpus, out of the shipping writer.
#
# The generator is a test that skips itself unless EVALLOG_FIXTURE_DIR is set,
# so a plain `swift test` writes no files anywhere. The directory is emptied
# first: a stale fixture left behind by an older kit would be read here as
# today's output and would pass.
echo "check_evallog_parity: writing the corpus with swift 6.3.3"
rm -rf "$CORPUS"
mkdir -p "$CORPUS"
if ! PATH="$SWIFT_HOME/usr/bin:$PATH" SWIFT_BACKTRACE=enable=no \
     EVALLOG_FIXTURE_DIR="$CORPUS" \
     swift test --package-path "$HERE/StudioKit" --filter WriteEvalLogFixtures \
     > "$CORPUS/../evallog-fixtures.log" 2>&1; then
  echo "check_evallog_parity: the fixture writer did not run" >&2
  tail -40 "$CORPUS/../evallog-fixtures.log" >&2
  exit 1
fi

written=$(find "$CORPUS" -maxdepth 1 -name '*.json' | wc -l)
if [ "$written" -eq 0 ]; then
  echo "check_evallog_parity: the fixture writer wrote no logs" >&2
  echo "  It skips unless EVALLOG_FIXTURE_DIR is set, and it was set to" >&2
  echo "  $CORPUS. Check WriteEvalLogFixtures still reads that name." >&2
  exit 2
fi
echo "check_evallog_parity: $written logs written"

# 2. Resolve the venv, building one if there is none.
if [ ! -x "$VENV/bin/python" ]; then
  if [ -n "${INSPECT_ROBOTS_VENV:-}" ]; then
    echo "check_evallog_parity: INSPECT_ROBOTS_VENV=$VENV has no bin/python" >&2
    echo "  Point it at a venv that exists, or unset it and let this build one." >&2
    exit 2
  fi
  echo "check_evallog_parity: building a venv at $VENV"
  mkdir -p "$WORK"
  if ! python3 -m venv "$VENV" >/dev/null 2>&1; then
    echo "check_evallog_parity: python3 -m venv failed" >&2
    echo "  Needed: python3 -m venv $VENV" >&2
    echo "          $VENV/bin/pip install inspect-robots==$VERSION" >&2
    exit 2
  fi
  if ! "$VENV/bin/pip" install --quiet "inspect-robots==$VERSION" >/dev/null 2>&1; then
    echo "check_evallog_parity: could not install inspect-robots==$VERSION" >&2
    echo "  This gate needs the real library and will not pretend otherwise." >&2
    echo "  Needed: $VENV/bin/pip install inspect-robots==$VERSION" >&2
    echo "  Or point INSPECT_ROBOTS_VENV at a venv that already has it." >&2
    rm -rf "$VENV"
    exit 2
  fi
fi

installed=$("$VENV/bin/python" -c \
  'from importlib.metadata import version; print(version("inspect-robots"))' 2>/dev/null || true)
if [ -z "$installed" ]; then
  echo "check_evallog_parity: $VENV has no inspect-robots" >&2
  exit 2
fi
if [ "$installed" != "$VERSION" ]; then
  # Not a failure. A deliberate run against a newer library is how upstream
  # moving is discovered, and the report names what actually ran either way.
  echo "check_evallog_parity: NOTE this venv has inspect-robots $installed, not $VERSION"
fi

# 3. Read it all back, in their Python.
mkdir -p "$WORK"
"$VENV/bin/python" "$HERE/scripts/evallog_parity.py" \
  --fixtures "$CORPUS" \
  --venv "$VENV" \
  --html-out "$WORK/html" \
  --list "$HERE/scripts/evallog_fixtures.txt" \
  --report "$WORK/report.txt"
