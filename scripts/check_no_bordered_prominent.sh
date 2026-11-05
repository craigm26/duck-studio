#!/bin/bash
# Pond Day's button rule (build 93), as a grep over the shipping sources only.
#
# NO `.borderedProminent` IN CODE. The system prominent style sets a WHITE label
# on the app's tint, and the tint is orange ink: 5.72:1 by day, 2.02:1 at night
# (PaletteTests.testWhiteOnTheTintFailsAtNightSoProminentButtonsWearInk). The
# app's own `.primaryAction` puts an ink label on Beak Orange in both schemes.
# Comments that mention the old style are allowed.
#
# Exits non-zero and names the line on any violation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/DuckStudio/Sources"

bad=$(grep -n 'borderedProminent' "$SRC"/*.swift | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*//' || true)
if [ -n "$bad" ]; then
    echo "check_no_bordered_prominent: use .primaryAction (ink on orange), not the system style:"
    echo "$bad"
    exit 1
fi
echo "check_no_bordered_prominent: OK"
