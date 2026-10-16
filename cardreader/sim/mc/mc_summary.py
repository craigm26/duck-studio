"""Hold the Monte Carlo rows to docs/PACKS.md, "Acceptance", per condition. Standard library only.

    python3 cardreader/sim/mc/mc_summary.py cardreader/sim/results/raw > cardreader/sim/results/RESULTS.md

Criteria, as pre-registered: end position within one third of a square (10 cm at 30 cm) in at
least 95% of rows; end heading within 15 degrees in at least 95%; the 95% Wilson upper bound
(two-sided, z = 1.96) on the fall rate at most 1%; each Walk card done in at most 8 s and each
Turn card in at most 6 s (a card past its bound fails its row on time); every row that ends
badly (stuck, stale, fell, out of time, trimmed out) ends with the duck commanded still and one
sentence. A row that ends badly fails position and heading. Rows with Walk back are reported
separately and must pass on their own.

Confidence intervals: Wilson for proportions; for the median, p95 and max of the errors a
bootstrap (2000 resamples, seed 1) gives a 95% interval for the median and p95; the max is
reported as observed.
"""

from __future__ import annotations

import glob
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rows as rowlist  # noqa: E402

# Which rows have a Walk back card anywhere in them (whether or not the row got that far).
WITH_BACK = {r["name"] for r in rowlist.all_rows()
             if any(s.action == "walk_backward" for s in rowlist.steps(r))}
Z = 1.96
SQUARE_M = 0.30
POS_M, HEAD_DEG, WALK_S, TURN_S = SQUARE_M / 3, 15.0, 8.0, 6.0


def wilson(k, n):
    if n == 0:
        return (float("nan"), float("nan"))
    p = k / n
    d = 1 + Z * Z / n
    c = (p + Z * Z / (2 * n)) / d
    h = Z * math.sqrt(p * (1 - p) / n + Z * Z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def q(xs, p):
    xs = sorted(xs)
    if not xs:
        return float("nan")
    i = (len(xs) - 1) * p
    lo, hi = math.floor(i), math.ceil(i)
    return xs[lo] + (xs[hi] - xs[lo]) * (i - lo)


def boot(xs, p, n=2000):
    rng = random.Random(1)
    if not xs:
        return (float("nan"), float("nan"))
    vals = sorted(q([rng.choice(xs) for _ in xs], p) for _ in range(n))
    return (vals[int(0.025 * n)], vals[int(0.975 * n) - 1])


def judge(rows):
    n = len(rows)
    ok_end = [r for r in rows if r["result"] == "finished"]
    pos = [r["pos_err_m"] * 100 for r in ok_end]
    head = [r["head_err_deg"] for r in ok_end]
    pos_ok = sum(1 for r in rows if r["result"] == "finished" and r["pos_err_m"] <= POS_M)
    head_ok = sum(1 for r in rows if r["result"] == "finished" and r["head_err_deg"] <= HEAD_DEG)
    falls = sum(1 for r in rows if r["fell"])
    walk_t = [c["s"] for r in rows for c in r.get("card_log", []) if c["card"].startswith("walk")]
    turn_t = [c["s"] for r in rows for c in r.get("card_log", []) if c["card"].startswith("turn")]
    late = sum(1 for r in rows if any((c["s"] > (WALK_S if c["card"].startswith("walk") else TURN_S))
                                      for c in r.get("card_log", [])))
    bad = [r for r in rows if r["result"] != "finished"]
    # Ending safely: the runner says exactly one ending sentence and returns "stopped at ...";
    # it then sends robot.stop (its `finally`). A row counts when one sentence was said.
    bad_said = sum(1 for r in bad if r["result"].startswith("stopped at ")
                   and sum(1 for s in r["said"] if s.endswith("so the row stopped there.")) == 1)
    endings = {}
    for r in bad:
        key = r["result"].split(": ", 1)[-1]
        endings[key] = endings.get(key, 0) + 1
    out = {"n": n, "pos_ok": pos_ok, "head_ok": head_ok, "falls": falls, "late": late,
           "bad": len(bad), "bad_said": bad_said, "endings": endings,
           "pos": pos, "head": head, "walk_t": walk_t, "turn_t": turn_t}
    out["pass"] = {
        "position": n > 0 and pos_ok / n >= 0.95,
        "heading": n > 0 and head_ok / n >= 0.95,
        "falls": wilson(falls, n)[1] <= 0.01,
        "time": late == 0,
        "ending badly": bad_said == len(bad),
    }
    return out


def f(v, d=1):
    return "n/a" if v is None or (isinstance(v, float) and math.isnan(v)) else f"{v:.{d}f}"


def dist(xs, unit, d=1):
    if not xs:
        return "n/a"
    m, p95 = q(xs, 0.5), q(xs, 0.95)
    mlo, mhi = boot(xs, 0.5)
    plo, phi = boot(xs, 0.95)
    return (f"median {f(m, d)} [{f(mlo, d)}, {f(mhi, d)}], p95 {f(p95, d)} [{f(plo, d)}, {f(phi, d)}], "
            f"max {f(max(xs), d)} {unit}")


def pf(b):
    return "**PASS**" if b else "**FAIL**"


def section(name, rows, lines):
    j = judge(rows)
    n = j["n"]
    lines.append(f"### {name}: {n} rows")
    lines.append("")
    if n == 0:
        lines.append("No rows.")
        lines.append("")
        return j
    lo, hi = wilson(j["pos_ok"], n)
    hlo, hhi = wilson(j["head_ok"], n)
    flo, fhi = wilson(j["falls"], n)
    lines += ["| criterion | measured | pass |", "|---|---|---|",
              f"| end position within 10 cm, at least 95% of rows | {j['pos_ok']}/{n} = {100*j['pos_ok']/n:.1f}% "
              f"(Wilson {100*lo:.1f} to {100*hi:.1f}%); error {dist(j['pos'], 'cm')} | {pf(j['pass']['position'])} |",
              f"| end heading within 15 degrees, at least 95% | {j['head_ok']}/{n} = {100*j['head_ok']/n:.1f}% "
              f"(Wilson {100*hlo:.1f} to {100*hhi:.1f}%); error {dist(j['head'], 'deg')} | {pf(j['pass']['heading'])} |",
              f"| falls, Wilson 95% upper bound at most 1% | {j['falls']}/{n}, upper bound {100*fhi:.2f}% | {pf(j['pass']['falls'])} |",
              f"| each Walk card at most 8 s, each Turn card at most 6 s | rows with a late card: {j['late']}; "
              f"Walk {dist(j['walk_t'], 's', 2)}; Turn {dist(j['turn_t'], 's', 2)} | {pf(j['pass']['time'])} |",
              f"| every row that ends badly ends still with one sentence | {j['bad_said']}/{j['bad']} "
              f"({', '.join(f'{v} x {k}' for k, v in sorted(j['endings'].items())) or 'none ended badly'}) "
              f"| {pf(j['pass']['ending badly'])} |", ""]
    lines.append("Position and heading errors are over rows that finished; a row that ended badly "
                 "counts as failing both.")
    lines.append("")
    return j


def load(dirs):
    """Every row of every condition, from every raw directory given."""
    out = {}
    for raw in dirs:
        for path in sorted(glob.glob(os.path.join(raw, "*.jsonl"))):
            cond = os.path.basename(path)[:-6]
            out.setdefault(cond, []).extend(dict(json.loads(l), _from=os.path.basename(raw.rstrip("/")))
                                            for l in open(path))
    return out


def table(title, judged, lines):
    lines += [title, "", "| condition | rows | position | heading | falls (upper bound) | time | ending badly |",
              "|---|---|---|---|---|---|---|"]
    for cond, j in judged.items():
        if j["n"] == 0:
            continue
        p = j["pass"]
        lines.append(f"| {cond} | {j['n']} | {pf(p['position'])} {100*j['pos_ok']/j['n']:.1f}% | "
                     f"{pf(p['heading'])} {100*j['head_ok']/j['n']:.1f}% | {pf(p['falls'])} {j['falls']} "
                     f"({100*wilson(j['falls'], j['n'])[1]:.2f}%) | {pf(p['time'])} | {pf(p['ending badly'])} |")
    lines.append("")


def main():
    """mc_summary.py RAW [RAW ...]: the first directory holds the runs over every row (pack
    solutions and the hand rows); every directory's pre-registered rows count toward
    "Acceptance"."""
    dirs = sys.argv[1:]
    every = load(dirs[:1])
    allrows = load(dirs)
    acc = {c: [r for r in rs if r["row"] in rowlist.ACCEPTANCE] for c, rs in allrows.items()}
    head = ["# Monte Carlo: Duck Cards rows on Pollen's robotd and v8 velstand, in duck-sim", "",
            "Generated by `cardreader/sim/mc/mc_summary.py` from " + ", ".join(f"`{os.path.basename(d.rstrip('/'))}/`" for d in dirs)
            + " (one JSON line per row). Criteria: docs/PACKS.md, \"Acceptance\", pre-registered; method: "
            "`cardreader/sim/mc/mc_run.py`'s docstring. Conditions are ordered as run.", ""]
    body = []
    j_acc, j_acc_b, j_acc_nb, j_all, j_all_b = {}, {}, {}, {}, {}
    for cond in sorted(acc, key=lambda c: ["nominal", "randomized", "randomized-10hz", "stressed-10hz"].index(c)
                       if c in ("nominal", "randomized", "randomized-10hz", "stressed-10hz") else 9):
        rows = acc[cond]
        body.append(f"## {cond}")
        body.append("")
        body.append(f"State subscribed at {rows[0]['hz'] if rows else '?'} Hz; spec sha256 "
                    f"{', '.join(sorted({r.get('spec_sha256', '?')[:12] for r in allrows[cond]}))}; "
                    f"{len({json.dumps(r.get('knobs'), sort_keys=True) for r in allrows[cond]})} stack session(s).")
        body.append("")
        # A batch of Walk back rows only (raw-back) counts toward the Walk back rows judged on their
        # own, never toward the mix of all pre-registered rows, which it would tilt.
        mix = [r for r in rows if r["_from"] != "raw-back"]
        j_acc[cond] = section(f"{cond}: the pre-registered rows", mix, body)
        j_acc_nb[cond] = judge([r for r in mix if r["row"] not in WITH_BACK])
        j_acc_b[cond] = section(f"{cond}: the pre-registered rows with Walk back, on their own",
                                [r for r in rows if r["row"] in WITH_BACK], body)
        if cond in every:
            j_all[cond] = section(f"{cond}: every row, the packs' challenge solutions included", every[cond], body)
            j_all_b[cond] = judge([r for r in every[cond] if r["row"] in WITH_BACK])
            per = {}
            for r in every[cond]:
                d = per.setdefault(r["row"], [0, 0, 0, []])
                d[0] += 1
                d[1] += r["result"] == "finished" and r["pos_err_m"] <= POS_M and r["head_err_deg"] <= HEAD_DEG
                d[2] += r["fell"]
                d[3].append(r["cards"])
            body += [f"#### {cond}: by row", "", "| row | cards | rows | within 10 cm and 15 degrees | fell |",
                     "|---|---|---|---|---|"]
            for name, (n, ok, fell, cards) in sorted(per.items()):
                body.append(f"| {name} | {max(cards)} | {n} | {ok}/{n} | {fell} |")
            body.append("")
    table("## Acceptance: the pre-registered rows", j_acc, head)
    table("Of those, the rows with Walk back, judged on their own:", j_acc_b, head)
    table("Of those, the rows without Walk back:", j_acc_nb, head)
    table("## Every row, the packs' challenge solutions included (not pre-registered; reported)", j_all, head)
    print("\n".join(head + body))


if __name__ == "__main__":
    main()
