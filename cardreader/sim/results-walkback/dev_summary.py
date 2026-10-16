"""The development runs (seeds 101 to 104 only), candidate beside candidate.

    python3 cardreader/sim/results-walkback/dev_summary.py cardreader/sim/results-walkback/dev

Per candidate directory and condition: rows, position and heading within the Acceptance bounds
(Wilson 95%), the median and p95 position error, and the overshoot along the last Walk card's
line (positive is past the square) for rows that finished.
"""
import glob
import json
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mc"))
import mc_summary as ms  # noqa: E402


def over(r):
    bx, by, bh = r["board_end"]
    ex, ey, _ = r["truth_end"]
    last = [c for c in r["card_log"] if c["card"].startswith("walk")]
    if not last:
        return None
    s = 1.0 if last[-1]["card"] == "walk_forward" else -1.0
    h = math.radians(bh)
    return s * ((ex - bx) * math.cos(h) + (ey - by) * math.sin(h))


def main():
    root = sys.argv[1]
    print("| run | condition | rows | position | heading | position err median / p95 (cm) | last walk overshoot median / p95 (cm) | measured coasts back (cm, median) |")
    print("|---|---|---|---|---|---|---|---|")
    for d in sorted(glob.glob(os.path.join(root, "*/"))):
        for p in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
            rows = [json.loads(l) for l in open(p)]
            j = ms.judge(rows)
            n = j["n"]
            fin = [r for r in rows if r["result"] == "finished"]
            ov = [100 * o for o in (over(r) for r in fin) if o is not None]
            co = [100 * c["coast_m"] for r in rows for c in r["card_log"] if c["card"] == "walk_backward" and "coast_m" in c]

            def sh(k):
                lo, hi = ms.wilson(k, n)
                return f"{100 * k / n:.1f}% [{100 * lo:.1f}, {100 * hi:.1f}]"
            print(f"| {os.path.basename(d.rstrip('/'))} | {os.path.basename(p)[:-6]} | {n} | {sh(j['pos_ok'])} | {sh(j['head_ok'])} | "
                  f"{ms.q(j['pos'], .5):.1f} / {ms.q(j['pos'], .95):.1f} | {ms.q(ov, .5):.1f} / {ms.q(ov, .95):.1f} | "
                  f"{ms.q(co, .5):.1f} |" if co else
                  f"| {os.path.basename(d.rstrip('/'))} | {os.path.basename(p)[:-6]} | {n} | {sh(j['pos_ok'])} | {sh(j['head_ok'])} | "
                  f"{ms.q(j['pos'], .5):.1f} / {ms.q(j['pos'], .95):.1f} | {ms.q(ov, .5):.1f} / {ms.q(ov, .95):.1f} | n/a |")


if __name__ == "__main__":
    main()
