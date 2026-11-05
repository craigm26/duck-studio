#!/bin/bash
# Build 91's two controller rules, as greps over the shipping sources only
# (DuckStudio/Sources, never .claude/worktrees):
#
# 1. EVERY SHEET CARRIES THE STOP PILL. A sheet, full-screen cover or popover
#    presented anywhere in the app must apply `.stopPill()` inside its content
#    (or on the presenting view of a whole tab), so no sheet ever covers the
#    only Stop (docs/plans/native-first-redesign.md, "Stop is always reachable").
# 2. THE VENUE SWITCHES ONLY ON AN EXPLICIT CONNECT. `venue = .real` appears
#    nowhere, and the one assignment of a chosen venue is `choose(_:cause:)` in
#    DriveView, which asks the kit's `VenueRule`.
#
# Exits non-zero and names the line on any violation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/DuckStudio/Sources"

python3 -I - "$SRC" <<'PY'
import os, re, sys
src = sys.argv[1]
bad = []
present = re.compile(r'\.(sheet|fullScreenCover|popover)\s*\(')
for name in sorted(os.listdir(src)):
    if not name.endswith('.swift'):
        continue
    text = open(os.path.join(src, name), encoding='utf-8').read()
    for m in present.finditer(text):
        line = text.count('\n', 0, m.start()) + 1
        # Skip comments and documentation that mention a sheet.
        start = text.rfind('\n', 0, m.start()) + 1
        if text[start:m.start()].lstrip().startswith('//'):
            continue
        # The content closure is the first top-level `{` after the call's arguments.
        i = text.index('(', m.start())
        depth = 0
        while True:
            c = text[i]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        j = text.find('{', i)
        if j < 0:
            bad.append(f'{name}:{line}: presentation with no content closure')
            continue
        depth = 0
        k = j
        while True:
            c = text[k]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    break
            k += 1
        body = text[j:k]
        if '.stopPill()' not in body:
            bad.append(f'{name}:{line}: sheet content has no .stopPill()')
for name in sorted(os.listdir(src)):
    if not name.endswith('.swift'):
        continue
    for n, l in enumerate(open(os.path.join(src, name), encoding='utf-8'), 1):
        code = l.split('//', 1)[0]
        if re.search(r'\bvenue\s*=\s*\.real\b', code):
            bad.append(f'{name}:{n}: venue = .real outside the explicit connect path')
        if name == 'DriveView.swift' and re.search(r'^\s*venue\s*=\s*outcome\.venue', code):
            continue
if bad:
    print('check_stop_pill: FAILED')
    print('\n'.join(bad))
    sys.exit(1)
print('check_stop_pill: every sheet carries the Stop pill; no venue = .real.')
PY
