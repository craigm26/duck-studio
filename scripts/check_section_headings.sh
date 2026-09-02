#!/bin/bash
# THE PLATFORM'S SECTION HEADER IS A CONTRAST FAILURE NO TEST CAN SEE, so this
# guard counts the places that still ask for it.
#
# A bare `Text` in a grouped list header takes the system's secondary label —
# about 3.18:1 on the ground a list sits on, short of the 4.5:1 SC 1.4.3 asks of
# body text — and the colour comes from UIKit rather than from a token, so
# `PaletteTests` never had a chance to run the formula over it. `SectionHeading`
# is the design system's own heading and it is set in `Theme.textTertiary`,
# which the palette measures at 4.59:1 on `backgroundSecondary`. The fix is not
# a colour argued about per screen; it is one component, used everywhere.
#
# It counts two spellings of the same mistake:
#
#   1. `Section("Name")` — the string-title initialiser. SwiftUI builds the
#      header itself, so there is no view to restyle. The migration is
#      `Section { … } header: { SectionHeading(text: "Name") }`.
#   2. `header: { Text(…) }` — a bare `Text` as the whole header, one line or
#      three. The migration is `SectionHeading(text: …)`.
#
# WHAT IT DELIBERATELY DOES NOT COUNT. A header that is an `HStack`, a `VStack`,
# an `if`, a badge or a count is a header carrying something a plain heading
# cannot hold, and rewriting it blind would drop the thing it carries. Those are
# printed under REVIEW so a person decides; they are not failures. A `Text` in a
# `footer:` is not a heading and is out of scope entirely.
#
# THIS GUARD CAN FAIL, AND THAT WAS PROVEN RATHER THAN ASSUMED: run against the
# tree before the migration it counted 91 and exited 1.
#
# Usage:  scripts/check_section_headings.sh          fail if the count is not 0
#         scripts/check_section_headings.sh --count  print the count, exit 0
# Run from anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/DuckStudio/Sources"

if [ ! -d "$APP" ]; then
  echo "check_section_headings: no app sources yet ($APP) — nothing to check."
  exit 0
fi

MODE="${1:-check}"

python3 - "$APP" "$MODE" <<'PY'
import os, re, sys

root, mode = sys.argv[1], sys.argv[2]

# A `Section(` whose FIRST argument is unlabelled is a title expression —
# `Section("Name")`, and equally `Section(block.title)`, where the string is a
# variable. Both hand SwiftUI a string and get the platform's own header, so
# both are counted; matching only the quote would let a variable slip past.
# `Section(header: Text(…))` is the old spelling of the same mistake.
SECTION_OPEN = re.compile(r'\bSection\(')
LABELLED     = re.compile(r'^\s*\w+\s*:(?!:)')
HEADER_TEXT  = re.compile(r'^\s*header:\s*Text\(')
HEADER_OPEN  = re.compile(r'header:\s*\{')
BARE_TEXT    = re.compile(r'^Text\(')

def closure_body(lines, i, col):
    """The text inside a `header: {` closure that opens on line i at column col.

    Brace-counted rather than indentation-counted, because a header body may
    hold a `Text("a \\(b)")` whose interpolation has braces in it and because
    `} footer: {` closes on a line that also opens another closure."""
    depth = 0
    out = []
    first = True
    for n in range(i, len(lines)):
        line = lines[n]
        start = col if first else 0
        for ch in line[start:]:
            if ch == '{':
                depth += 1
                if depth == 1:
                    continue
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    return out, n
            if depth >= 1:
                out.append(ch)
        out.append('\n')
        first = False
    return out, len(lines) - 1

def significant(body):
    """The body with comments and blank lines dropped."""
    keep = []
    for line in body.split('\n'):
        s = line.strip()
        if not s or s.startswith('//'):
            continue
        keep.append(s)
    return keep

bare, titles, review = [], [], []

for name in sorted(os.listdir(root)):
    if not name.endswith('.swift'):
        continue
    path = os.path.join(root, name)
    lines = open(path, encoding='utf-8').read().split('\n')
    for i, line in enumerate(lines):
        if line.lstrip().startswith('//'):
            continue
        for m in SECTION_OPEN.finditer(line):
            rest = line[m.end():]
            if rest.strip().startswith(')'):
                continue
            if HEADER_TEXT.match(rest):
                titles.append((name, i + 1, line.strip()))
            elif not LABELLED.match(rest):
                titles.append((name, i + 1, line.strip()))
        for m in HEADER_OPEN.finditer(line):
            raw, _ = closure_body(lines, i, m.end() - 1)
            body = significant(''.join(raw))
            if not body:
                continue
            joined = ' '.join(body)
            if BARE_TEXT.match(joined) and 'SectionHeading' not in joined:
                bare.append((name, i + 1, joined[:70]))
            elif 'SectionHeading' not in joined:
                review.append((name, i + 1, joined[:70]))

count = len(bare) + len(titles)

if mode == '--count':
    print(count)
    sys.exit(0)

for f, n, t in titles:
    print(f"  Section(string) {f}:{n}: {t}")
for f, n, t in bare:
    print(f"  bare Text header {f}:{n}: {t}")

if review:
    print()
    print(f"REVIEW ({len(review)}) — headers that are not a plain string; a person decides:")
    for f, n, t in review:
        print(f"  {f}:{n}: {t}")

print()
if count == 0:
    print("check_section_headings: clean — every section heading is SectionHeading.")
    sys.exit(0)

print(f"check_section_headings: {count} heading(s) still use the platform's own.")
print("Migrate to SectionHeading(text:) — Section { … } header: { SectionHeading(text: \"X\") }.")
sys.exit(1)
PY
