#!/bin/bash
# THE TITLE DECIDES NOTHING.
#
# A policy has two names and they do different jobs. `fileName` is what the
# bytes arrived under and is the only string anything MATCHES on — the bundle
# lookup in `PolicyStore`, the action-scale kind in `BenchView`, the clip link
# in `PolicyListView`, the name a copy leaves under. `title` is what a person
# reads and changes, and it is never a key: not the bundle lookup, not the
# action scale, not the clip match, not dedupe, not sort stability, not removal,
# and not what bytes leave the phone.
#
# The old `Entry.displayName` was both at once, which is why it had to be
# DELETED rather than aliased: alias it to the title and `TuneView`'s tuned
# export writes somebody's nickname into the ONNX's `microduck_studio.base_policy`
# metadata — an unresolvable provenance claim on another machine; alias it to
# the file name and the "Fold into" picker goes back to showing 64 hex.
#
# This guard is what stops the two growing back together. It is
# `check_no_studio_math.sh`'s shape — `set +e` per grep, `rc > 1` is a BROKEN
# PATTERN and a hard exit 2, `status` accumulates across patterns — because a
# guard that passes by dying quietly is worse than no guard.
#
# THE POSITIVE HALF MATTERS AS MUCH AS THE FORBIDDEN HALF. Deleting
# `displayName` turns 29 sites into compile errors, and a compile error can be
# answered wrongly as easily as rightly: `entry.title` compiles everywhere
# `entry.fileName` does. So the four sites where the FILE name is the answer are
# asserted by name, and their absence is a failure.
#
# BASELINE, PROVEN RATHER THAN ASSUMED: run against the pre-change tree
# (duck-studio at e90a814, before build 47's rename) this counts 29
# `displayName` occurrences across `DuckStudio/Sources` and
# `StudioKit/Sources`, fails all five positive checks, and exits 1.
#
# TWO DEVIATIONS FROM THE BUILD-47 PLAN'S §D.9, BOTH BECAUSE THE PLAN CONTRADICTS
# ITSELF, both recorded here rather than silently resolved:
#
#   1. §D.9 forbids `entry.report.headline` ANYWHERE in `DuckStudio/Sources`
#      while §D.6 says `PolicyListView.swift:935` — `Text(entry.report.headline)`,
#      the Verdict section — is unchanged. Both cannot hold. The rule's target is
#      the ACCESSIBILITY use (§D.3: "Seal accessibility label →
#      `entry.runnabilityLabel` (not `report.headline`)"), because that one reads
#      "This file is a Microduck policy" for every digest-named row and identifies
#      nothing. So the forbidden pattern is scoped to a line that also carries
#      `accessibilityLabel`, and a fifth positive check — `PolicyListView.swift`
#      contains `entry.runnabilityLabel` — makes the intent enforceable rather
#      than merely unviolated.
#   2. §D.9 asserts `BenchView.swift`'s `DuckPolicyKind.allCases.first` line
#      contains `fileName`, but §D.6 moves that match into the kit as
#      `PolicyNaming.kind(forFileName:)`, after which BenchView has no
#      `DuckPolicyKind.allCases.first` line at all. The check asserts the call
#      that replaced it.
#
# Usage:  scripts/check_no_policy_name_keys.sh          fail on any violation
#         scripts/check_no_policy_name_keys.sh --count  print the displayName count, exit 0
# Run from anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/DuckStudio/Sources"
KIT="$ROOT/StudioKit/Sources"

if [ ! -d "$APP" ] || [ ! -d "$KIT" ]; then
  echo "check_no_policy_name_keys: no sources yet ($APP / $KIT) — nothing to check."
  exit 0
fi

count_display_names() {
  set +e
  local n
  n=$(grep -rEoh 'displayName' "$APP" "$KIT" --include='*.swift' 2>/dev/null | wc -l | tr -d ' ')
  set -e
  printf '%s' "$n"
}

if [ "${1:-}" = "--count" ]; then
  count_display_names
  echo
  exit 0
fi

status=0

# ── forbidden 1: the field itself ────────────────────────────────────────────
#
# It is gone from the kit, and a new one anywhere is the two names growing back
# into one.
set +e
hits=$(grep -rn 'displayName' "$APP" "$KIT" --include='*.swift' 2>&1)
rc=$?
set -e
if [ $rc -gt 1 ]; then
  echo "BROKEN PATTERN 'displayName': $hits"
  exit 2
fi
if [ -n "$hits" ]; then
  echo "FORBIDDEN: 'displayName' is deleted. A name is either the FILE's (entry.fileName)"
  echo "or the PERSON's (entry.title), and every site has to say which."
  echo "$hits"
  echo "count: $(count_display_names) occurrence(s)"
  status=1
fi

# ── forbidden 2: the title used as a key ─────────────────────────────────────
#
# Each of these is a place where a string is MATCHED, KEYED or WRITTEN OUT, and
# a person's nickname must reach none of them. The list is the eight tokens that
# mark those sites in this tree.
KEY_CONTEXTS='Bundle\.main|forResource|appendingPathComponent|ExportFile\.write|DuckPolicyKind|\.policy ==|persist\(|remove\('
set +e
hits=$(grep -rnE '\.title\b' "$APP" "$KIT" --include='*.swift' 2>&1)
rc=$?
set -e
if [ $rc -gt 1 ]; then
  echo "BROKEN PATTERN '\\.title': $hits"
  exit 2
fi
set +e
keyed=$(printf '%s' "$hits" | grep -E "$KEY_CONTEXTS")
rc=$?
set -e
if [ $rc -gt 1 ]; then
  echo "BROKEN PATTERN '$KEY_CONTEXTS': $keyed"
  exit 2
fi
if [ -n "$keyed" ]; then
  echo "FORBIDDEN: a title is being used where a FILE NAME is the answer."
  echo "The title decides nothing: not the bundle lookup, not the action scale,"
  echo "not the clip match, and not what bytes leave the phone."
  echo "$keyed"
  status=1
fi

# ── forbidden 3: the report's headline as an accessibility label ─────────────
#
# `report.headline` names the FILE. For a digest-named policy it says "This file
# is a Microduck policy", which on a row seal identifies nothing. See the
# deviation note at the top of this file for why this is scoped rather than
# blanket.
set +e
hits=$(grep -rnE 'entry\.report\.headline' "$APP" --include='*.swift' 2>&1)
rc=$?
set -e
if [ $rc -gt 1 ]; then
  echo "BROKEN PATTERN 'entry\\.report\\.headline': $hits"
  exit 2
fi
set +e
labelled=$(printf '%s' "$hits" | grep -E 'accessibilityLabel')
rc=$?
set -e
if [ $rc -gt 1 ]; then
  echo "BROKEN PATTERN 'accessibilityLabel': $labelled"
  exit 2
fi
if [ -n "$labelled" ]; then
  echo "FORBIDDEN: report.headline as an accessibility label — it names the file,"
  echo "and for a digest-named policy it names nothing. Use entry.runnabilityLabel."
  echo "$labelled"
  status=1
fi

# ── the positive half ────────────────────────────────────────────────────────
#
# Five sites where the FILE name is the only right answer. Absence is a failure:
# a rename that reached one of these would break a match silently.
require() {
  local file="$1" pattern="$2" why="$3"
  if [ ! -f "$file" ]; then
    echo "MISSING FILE: $file — $why"
    status=1
    return
  fi
  set +e
  grep -qE "$pattern" "$file"
  local rc=$?
  set -e
  if [ $rc -gt 1 ]; then
    echo "BROKEN PATTERN '$pattern' against $file"
    exit 2
  fi
  if [ $rc -ne 0 ]; then
    echo "MISSING: $(basename "$file") no longer matches /$pattern/ — $why"
    status=1
  fi
}

require "$APP/PolicyStore.swift" 'entry\.fileName' \
  "the bundled-seed lookup takes the file's own name; a nickname finds nothing and Probe stops working"
require "$APP/BenchView.swift" 'PolicyNaming\.kind\(forFileName: entry\.fileName\)' \
  "the action scale is matched on the file name, including the older BEST_ spelling"
require "$APP/PolicyListView.swift" 'clips\.values\.filter.*fileName' \
  "a recording links to a policy by the FILE name it was recorded from"
require "$APP/PolicyListView.swift" 'ExportFile\.write\(data, named: entry\.exportFileName\)' \
  "a copy leaves under the file's name, never under a nickname"
require "$APP/PolicyListView.swift" 'entry\.runnabilityLabel' \
  "the row seal's accessibility label names the POLICY; report.headline names the file"

if [ $status -eq 0 ]; then
  echo "check_no_policy_name_keys: clean — 0 displayName, no title used as a key, 5/5 file-name sites present."
fi
exit $status
