#!/bin/bash
# The stage-overlay rule on Play, as a grep over the shipping sources.
#
# An overlay on a live picture ships COLLAPSED: one row, 60 points at most, the rest on a tap
# (build 42, the legend that hid the duck; build 96, a run's report drawn in full twice, once
# across the top half of the picture and once as a card over the sticks). Every line Play floats
# over the picture goes through `StageLineView`, which holds a `StageLine` to
# `StageLine.collapsedMaxHeight` and expands it inside `StageLine.expandedMaxHeight(stage:)`.
# `StageLineTests` pins the numbers; this pins that DriveView uses the door.
#
# Fails, naming the line, when:
# 1. DriveView draws the press readout or the controller caption with a bare `Text(...)`.
# 2. StageLineView stops holding the collapsed line to one row and the budget.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/DuckStudio/Sources"

python3 -I - "$SRC" <<'PY'
import os, re, sys
src = sys.argv[1]
bad = []

drive = open(os.path.join(src, 'DriveView.swift'), encoding='utf-8').read()
bare = re.compile(r'\bText\(\s*(lastAction|caption\b|caption\?\.text)')
for m in bare.finditer(drive):
    start = drive.rfind('\n', 0, m.start()) + 1
    if drive[start:m.start()].lstrip().startswith('//'):
        continue
    line = drive.count('\n', 0, m.start()) + 1
    bad.append(f'DriveView.swift:{line}: a stage line drawn with a bare Text; use StageLineView')
if drive.count('StageLineView(') < 3:
    bad.append('DriveView.swift: the caption, the readout line and the camera refusal must all '
               'go through StageLineView')

view = open(os.path.join(src, 'StageLineView.swift'), encoding='utf-8').read()
for needed in ('StageLine.collapsedMaxHeight', 'StageLine.expandedMaxHeight', '.lineLimit(1)'):
    if needed not in view:
        bad.append(f'StageLineView.swift: missing {needed}')

if bad:
    print('\n'.join(bad))
    print('check_stage_lines: FAILED')
    sys.exit(1)
print('check_stage_lines: every line on the Play picture is one collapsed row, the rest on a tap.')
PY
