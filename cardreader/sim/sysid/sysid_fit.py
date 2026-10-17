"""Fit what sysid_run.py logged: per axis and direction, the dead band, the delay, a first-order
time constant, the steady-state gain and where it saturates; the stop; the deadman; the state
rate a client sees; odometry against MuJoCo's truth. Needs numpy, scipy, matplotlib.

    python cardreader/sim/sysid/sysid_fit.py cardreader/sim/sysid/raw cardreader/sim/sysid

Method, so the numbers can be checked:

- Response is measured on MuJoCo's trunk, never on odometry: forward displacement along the
  heading the duck had when the step began (vx), or the unwrapped yaw change (vyaw).
- A step is fitted as first order plus dead time on its *integral*, which needs no
  differentiating of a walking duck's swaying trunk: for a step of size u from t = 0,
  s(t) = K u [ (t - L) - tau (1 - exp(-(t - L) / tau)) ] for t >= L, 0 before; K the
  steady-state gain, L the delay, tau the time constant. Fitted by least squares over the hold.
- Steady state is the mean speed over the last 2.5 s of the hold. A trial "moved" when that is
  above 0.02 m/s or 5 deg/s; the dead band of a direction is the largest level that never moved
  in any repetition, and the onset the smallest level that moved in every one.
- Coast is how far the trunk travels after the first zero command (until it is still).
- The deadman is the time from the last robot.move to the first state frame whose
  `move.limited_by` says `deadman`; robotd then slews the twist to zero with its `cmd_alpha`.
- Odometry error per trial: |odom displacement| - |truth displacement| and the odom yaw change
  minus the truth yaw change, over the whole trial.
"""

from __future__ import annotations

import glob
import gzip
import json
import math
import os
import re
import sys

import numpy as np
from scipy.optimize import curve_fit

MOVED_MPS, MOVED_DPS = 0.02, 5.0


def load(path):
    out = {"cmd": [], "state": [], "truth": [], "silence": []}
    with gzip.open(path, "rt") as f:
        for line in f:
            d = json.loads(line)
            out.setdefault(d["k"], []).append(d)
    return out


def unwrap(a):
    return np.unwrap(np.asarray(a, dtype=float))


def fopdt_int(t, K, L, tau, u=1.0):
    s = np.zeros_like(t)
    m = t > L
    tt = t[m] - L
    s[m] = K * u * (tt - tau * (1 - np.exp(-tt / max(tau, 1e-3))))
    return s


def step_trial(d):
    cmd = d["cmd"]
    axis = "vx" if any(abs(c["vx"]) > 0 for c in cmd) else "vyaw"
    nz = [c for c in cmd if abs(c[axis]) > 0]
    if not nz:
        return None
    u = nz[0][axis]
    w0 = nz[0]["w"]
    w1 = next((c["w"] for c in cmd if c["w"] > w0 and abs(c[axis]) == 0), cmd[-1]["w"])
    tr = d["truth"]
    w = np.array([p["w"] for p in tr])
    x = np.array([p["x"] for p in tr])
    y = np.array([p["y"] for p in tr])
    yaw = unwrap([p["yaw"] for p in tr])
    i0 = int(np.searchsorted(w, w0))
    h0 = yaw[i0]
    along = (x - x[i0]) * math.cos(h0) + (y - y[i0]) * math.sin(h0)
    turned = yaw - yaw[i0]
    resp = along if axis == "vx" else np.degrees(turned)
    t = w - w0
    hold = (t >= 0) & (w <= w1)
    last = (w > w1 - 2.5) & (w <= w1)
    ss = float(np.polyfit(t[last], resp[last], 1)[0]) if last.sum() > 5 else float("nan")
    moved = abs(ss) > (MOVED_MPS if axis == "vx" else MOVED_DPS)
    K = L = tau = float("nan")
    if moved and hold.sum() > 20:
        tt, rr = t[hold], resp[hold]
        unit = u if axis == "vx" else math.degrees(u)
        try:
            (K, L, tau), _ = curve_fit(lambda tq, K, L, tau: fopdt_int(tq, K, L, tau, unit), tt, rr,
                                       p0=[ss / unit, 0.3, 0.3],
                                       bounds=([-5, 0.0, 0.02], [5, 3.0, 4.0]))
        except Exception:
            pass
    after = w > w1
    coast = float("nan")
    if after.sum() > 10:
        i1 = int(np.searchsorted(w, w1))
        if axis == "vx":
            coast = float(abs(along[-1] - along[i1]))
        else:
            coast = float(abs(math.degrees(turned[-1] - turned[i1])))
    st = d["state"]
    odom = [s["odom"] for s in st if s.get("odom")]
    oerr_pos = oerr_yaw = float("nan")
    if len(odom) > 2:
        po0, po1 = odom[0]["position"], odom[-1]["position"]
        od = math.hypot(po1[0] - po0[0], po1[1] - po0[1])
        td = math.hypot(x[-1] - x[0], y[-1] - y[0])
        oerr_pos = od - td
        oyaw = unwrap([o["yaw"] for o in odom])
        oerr_yaw = math.degrees((oyaw[-1] - oyaw[0]) - (yaw[-1] - yaw[0]))
    # robotd's own view of the command: first state frame whose requested twist is the step
    req = [s for s in st if s.get("move") and abs(s["move"]["requested"][0 if axis == "vx" else 2] - u) < 1e-6]
    seen = (req[0]["w"] - w0) if req else float("nan")
    return {"axis": axis, "u": u, "ss": ss, "moved": moved, "K": float(K), "L": float(L),
            "tau": float(tau), "coast": coast, "odom_err_m": oerr_pos, "odom_err_deg": oerr_yaw,
            "fell": any(s.get("fallen") for s in st), "policies": sorted({s.get("policy") for s in st}),
            "request_seen_s": seen, "t": t.tolist(), "resp": resp.tolist(), "hold_s": w1 - w0}


def ramp_trial(d):
    cmd = d["cmd"]
    axis = "vx" if any(abs(c["vx"]) > 0 for c in cmd) else "vyaw"
    tr = d["truth"]
    w = np.array([p["w"] for p in tr])
    x = np.array([p["x"] for p in tr])
    y = np.array([p["y"] for p in tr])
    yaw = unwrap([p["yaw"] for p in tr])
    cw = np.array([c["w"] for c in cmd])
    cu = np.array([c[axis] for c in cmd])
    # speed over a 0.6 s window, along the trunk's own heading (vx) or about the vertical (vyaw)
    half = 15
    sp = np.full(len(w), np.nan)
    for i in range(half, len(w) - half):
        dt = w[i + half] - w[i - half]
        if axis == "vx":
            h = yaw[i]
            sp[i] = ((x[i + half] - x[i - half]) * math.cos(h) + (y[i + half] - y[i - half]) * math.sin(h)) / dt
        else:
            sp[i] = math.degrees(yaw[i + half] - yaw[i - half]) / dt
    u_at = np.interp(w, cw, cu)
    thr = MOVED_MPS if axis == "vx" else MOVED_DPS
    peak = int(np.nanargmax(np.abs(u_at)))
    up = [(u_at[i], sp[i]) for i in range(peak) if not np.isnan(sp[i])]
    down = [(u_at[i], sp[i]) for i in range(peak, len(w)) if not np.isnan(sp[i])]
    # onset: the command at which motion starts and stays for 1 s; dropout: where it stops on the way down
    onset = dropout = float("nan")
    for i, (uu, s) in enumerate(up):
        if all(abs(v) > thr for _, v in up[i:i + 50]):
            onset = uu
            break
    for i, (uu, s) in enumerate(down):
        if all(abs(v) <= thr for _, v in down[i:i + 25]):
            dropout = uu
            break
    return {"axis": axis, "top": float(cu[np.argmax(np.abs(cu))]), "onset": float(onset),
            "dropout": float(dropout), "u": u_at.tolist(), "speed": sp.tolist(),
            "t": (w - cw[0]).tolist(), "fell": any(s.get("fallen") for s in d["state"])}


def deadman_trial(d):
    sil = d["silence"][0]["w"]
    last_cmd = max(c["w"] for c in d["cmd"] if c["w"] < sil)
    fire = next((s["w"] for s in d["state"] if s["w"] > last_cmd and "deadman" in (s["move"].get("limited_by") or [])), None)
    near0 = next((s["w"] for s in d["state"] if s["w"] > last_cmd and abs(s["move"]["applied"][0]) < 0.01), None)
    tr = d["truth"]
    w = np.array([p["w"] for p in tr])
    x = np.array([p["x"] for p in tr])
    y = np.array([p["y"] for p in tr])
    i = int(np.searchsorted(w, last_cmd))
    j = int(np.searchsorted(w, sil + 3.0))
    return {"fires_s": (fire - last_cmd) if fire else float("nan"),
            "applied_below_001_s": (near0 - last_cmd) if near0 else float("nan"),
            "travel_after_last_cmd_m": float(math.hypot(x[min(j, len(x) - 1)] - x[i], y[min(j, len(y) - 1)] - y[i]))}


def rate_trial(path):
    with gzip.open(path, "rt") as f:
        w = np.array([json.loads(l)["w"] for l in f])
    gaps = np.diff(w)
    return {"frames_per_s": float((len(w) - 1) / (w[-1] - w[0])), "gap_median_ms": float(np.median(gaps) * 1000),
            "gap_p95_ms": float(np.percentile(gaps, 95) * 1000), "gap_max_ms": float(gaps.max() * 1000)}


def main():
    raw, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    steps, ramps, deadman, rates = [], [], [], {}
    for p in sorted(glob.glob(os.path.join(raw, "*.jsonl.gz"))):
        name = os.path.basename(p)[:-9]
        if name.startswith("step_"):
            r = step_trial(load(p))
            if r:
                r["name"] = name
                steps.append(r)
        elif name.startswith("ramp_"):
            r = ramp_trial(load(p))
            r["name"] = name
            ramps.append(r)
        elif name.startswith("deadman_"):
            deadman.append(deadman_trial(load(p)))
        elif name.startswith("rate_"):
            rates[name[5:]] = rate_trial(p)

    table = []
    for axis in ("vx", "vyaw"):
        for sign in (1, -1):
            rows = [s for s in steps if s["axis"] == axis and math.copysign(1, s["u"]) == sign]
            levels = sorted({abs(s["u"]) for s in rows})
            per = []
            for lv in levels:
                rr = [s for s in rows if abs(s["u"]) == lv]
                mv = [s for s in rr if s["moved"]]
                unit = lv if axis == "vx" else math.degrees(lv)
                per.append({"level": lv, "n": len(rr), "moved": len(mv),
                            "ss": float(np.median([s["ss"] for s in rr])),
                            "gain": float(np.median([s["ss"] / unit for s in rr])),
                            "K": float(np.median([s["K"] for s in mv])) if mv else float("nan"),
                            "L": float(np.median([s["L"] for s in mv])) if mv else float("nan"),
                            "tau": float(np.median([s["tau"] for s in mv])) if mv else float("nan"),
                            "coast": float(np.median([s["coast"] for s in rr])),
                            "fell": sum(s["fell"] for s in rr)})
            never = [p["level"] for p in per if p["moved"] == 0]
            always = [p["level"] for p in per if p["moved"] == p["n"]]
            moving = [p for p in per if p["moved"] == p["n"]]
            table.append({"axis": axis, "sign": sign, "levels": per,
                          "dead_band_upto": max(never) if never else 0.0,
                          "onset_from": min(always) if always else float("nan"),
                          "L_median": float(np.nanmedian([p["L"] for p in moving])) if moving else float("nan"),
                          "tau_median": float(np.nanmedian([p["tau"] for p in moving])) if moving else float("nan"),
                          "ss_at_bound": per[-1]["ss"] if per else float("nan")})
    oe = [s["odom_err_m"] for s in steps if not math.isnan(s["odom_err_m"])]
    oy = [s["odom_err_deg"] for s in steps if not math.isnan(s["odom_err_deg"])]
    summary = {
        "steps": len(steps), "ramps": len(ramps), "falls": sum(s["fell"] for s in steps) + sum(r["fell"] for r in ramps),
        "policies_seen": sorted({p for s in steps for p in s["policies"] if p}),
        "request_seen_ms_median": float(np.nanmedian([s["request_seen_s"] for s in steps]) * 1000),
        "axes": table,
        "ramps_onset_dropout": [{k: r[k] for k in ("name", "top", "onset", "dropout")} for r in ramps],
        "deadman": deadman, "state_rate": rates,
        "odom_vs_truth": {"pos_err_m_median_abs": float(np.median(np.abs(oe))), "pos_err_m_max_abs": float(np.max(np.abs(oe))),
                          "yaw_err_deg_median_abs": float(np.median(np.abs(oy))), "yaw_err_deg_max_abs": float(np.max(np.abs(oy))),
                          "per_trial_seconds": "about 9.5"},
    }
    with open(os.path.join(out, "sysid.json"), "w") as f:
        json.dump(summary, f, indent=1)
    write_md(summary, os.path.join(out, "sysid.md"))
    plots(steps, ramps, out)
    print(open(os.path.join(out, "sysid.md")).read())


def fmt(v, d=2):
    return "n/a" if v is None or (isinstance(v, float) and math.isnan(v)) else f"{v:.{d}f}"


def write_md(s, path):
    L = ["# System identification: v8 velstand under robotd in duck-sim", "",
         "Generated by `sysid_fit.py` from `raw/`. Truth is MuJoCo's trunk; commands only through `robot.move`.", "",
         "## Per axis and direction", "",
         "| axis | dir | dead band (never moved up to) | moves every time from | delay L (s) | time constant tau (s) | steady state at the bound |",
         "|---|---|---|---|---|---|---|"]
    for a in s["axes"]:
        unit = "m/s" if a["axis"] == "vx" else "deg/s"
        L.append(f"| {a['axis']} | {'+' if a['sign'] > 0 else '-'} | {fmt(a['dead_band_upto'], 3)} | {fmt(a['onset_from'], 3)} | "
                 f"{fmt(a['L_median'])} | {fmt(a['tau_median'])} | {fmt(a['ss_at_bound'], 3)} {unit} |")
    L += ["", "## Every level (median over repetitions)", "",
          "| axis | command | moved | steady state | gain | K (fit) | L (s) | tau (s) | coast after stop | falls |",
          "|---|---|---|---|---|---|---|---|---|---|"]
    for a in s["axes"]:
        for p in a["levels"]:
            u = a["sign"] * p["level"]
            unit = "m/s" if a["axis"] == "vx" else "deg/s"
            cu = "m" if a["axis"] == "vx" else "deg"
            L.append(f"| {a['axis']} | {u:+.3f} | {p['moved']}/{p['n']} | {fmt(p['ss'], 3)} {unit} | {fmt(p['gain'])} | "
                     f"{fmt(p['K'])} | {fmt(p['L'])} | {fmt(p['tau'])} | {fmt(p['coast'], 3)} {cu} | {p['fell']} |")
    L += ["", "## Ramps (onset on the way up, drop-out on the way down)", "", "| ramp | onset command | drop-out command |", "|---|---|---|"]
    for r in s["ramps_onset_dropout"]:
        L.append(f"| {r['name']} | {fmt(r['onset'], 3)} | {fmt(r['dropout'], 3)} |")
    L += ["", "## Deadman, state rate, odometry", ""]
    for i, d in enumerate(s["deadman"]):
        L.append(f"- deadman trial {i}: fires {fmt(d['fires_s'])} s after the last robot.move; applied vx below 0.01 at "
                 f"{fmt(d['applied_below_001_s'])} s; the trunk travelled {fmt(d['travel_after_last_cmd_m'], 3)} m after the last command.")
    for hz, r in s["state_rate"].items():
        L.append(f"- robot.subscribe hz={hz}: {fmt(r['frames_per_s'], 1)} frames/s, gap median {fmt(r['gap_median_ms'], 0)} ms, "
                 f"p95 {fmt(r['gap_p95_ms'], 0)} ms, max {fmt(r['gap_max_ms'], 0)} ms.")
    o = s["odom_vs_truth"]
    L.append(f"- odometry against truth over one trial (about 9.5 s): distance error median {fmt(o['pos_err_m_median_abs'], 3)} m, "
             f"max {fmt(o['pos_err_m_max_abs'], 3)} m; yaw error median {fmt(o['yaw_err_deg_median_abs'], 2)} deg, max {fmt(o['yaw_err_deg_max_abs'], 2)} deg.")
    L.append(f"- policies that drove a tick: {', '.join(s['policies_seen'])}; falls: {s['falls']}; "
             f"robotd reported a new request in its state a median {fmt(s['request_seen_ms_median'], 0)} ms after it was sent.")
    open(path, "w").write("\n".join(L) + "\n")


def plots(steps, ramps, out):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    for axis, unit in (("vx", "forward displacement (m)"), ("vyaw", "yaw change (deg)")):
        levels = sorted({s["u"] for s in steps if s["axis"] == axis})
        cols = 4
        rows = math.ceil(len(levels) / cols)
        fig, axs = plt.subplots(rows, cols, figsize=(3.2 * cols, 2.4 * rows), sharex=True)
        for ax, lv in zip(axs.flat, levels):
            for s in steps:
                if s["axis"] == axis and s["u"] == lv:
                    ax.plot(s["t"], s["resp"], lw=1, color="#1f5f99" if s["moved"] else "#999999")
            ax.axvline(0, color="#ccc", lw=0.8)
            ax.set_title(f"{axis} = {lv:+.3f}", fontsize=9)
            ax.tick_params(labelsize=7)
        for ax in list(axs.flat)[len(levels):]:
            ax.axis("off")
        fig.supxlabel("seconds from the step (step held 5 s)")
        fig.supylabel(unit)
        fig.tight_layout()
        fig.savefig(os.path.join(out, f"steps_{axis}.png"), dpi=90)
        plt.close(fig)
    fig, axs = plt.subplots(1, 2, figsize=(9, 3.4))
    for ax, axis, unit in ((axs[0], "vx", "m/s"), (axs[1], "vyaw", "deg/s")):
        pts = [(s["u"], s["ss"]) for s in steps if s["axis"] == axis]
        ax.scatter([p[0] for p in pts], [p[1] for p in pts], s=10, color="#1f5f99")
        lo = min(p[0] for p in pts)
        hi = max(p[0] for p in pts)
        ideal = np.array([lo, hi]) * (1 if axis == "vx" else 180 / math.pi)
        ax.plot([lo, hi], ideal, color="#bbb", lw=1, ls="--", label="achieved = commanded")
        ax.axhline(0, color="#ddd", lw=0.8)
        ax.set_xlabel(f"commanded {axis}")
        ax.set_ylabel(f"steady state ({unit}), MuJoCo truth")
        ax.legend(fontsize=7, frameon=False)
    fig.tight_layout()
    fig.savefig(os.path.join(out, "gain.png"), dpi=90)
    plt.close(fig)
    if ramps:
        fig, axs = plt.subplots(1, 2, figsize=(9, 3.4))
        for r in ramps:
            ax = axs[0] if r["axis"] == "vx" else axs[1]
            ax.plot(r["u"], r["speed"], lw=0.8)
        axs[0].set_xlabel("commanded vx (ramp up then down)")
        axs[0].set_ylabel("trunk speed, 0.6 s window (m/s)")
        axs[1].set_xlabel("commanded vyaw (rad/s)")
        axs[1].set_ylabel("yaw rate, 0.6 s window (deg/s)")
        fig.tight_layout()
        fig.savefig(os.path.join(out, "ramps.png"), dpi=90)
        plt.close(fig)


if __name__ == "__main__":
    main()
