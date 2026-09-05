#!/usr/bin/env python3
"""Read this app's evaluation logs with inspect-robots, in inspect-robots' own Python.

WHAT THIS ANSWERS THAT NO SWIFT TEST CAN. StudioKit already proves its writer
re-encodes upstream's own log byte for byte, on every commit, with no Python and
no network. That is a strong claim and it is still a claim made in the language
that wrote the file. This one is made in the language that reads it: the corpus
goes through `read_eval_log`, back out through `json.dumps` with upstream's own
`_sanitize`, and into `inspect-robots view`, which is the command a person who
was handed one of these files will actually type. If those three agree, the file
is not merely well formed, it is theirs.

WHY IT NEVER PASSES WHEN IT CANNOT RUN. A missing venv, a missing corpus, an
empty corpus and a fixture list that does not match the directory are all
failures with a non-zero exit, never a skip. This repository has already shipped
a gate that reported success because the thing it checked was absent, and the
comment at check_no_studio_math.sh:44-52 is what that cost.

WHAT IS NOT REIMPLEMENTED HERE. `_sanitize` is imported from
inspect_robots.logging.json_log and `reduce_scores` from inspect_robots.scorer,
because a second implementation of either would let this file agree with itself
about something upstream does differently. The producer clauses and the scorer
roles are read out of the Swift sources for the same reason: this script holds
no copy of a sentence or a table that lives in the kit.

Usage (normally through scripts/check_evallog_parity.sh, which builds the
corpus and resolves the venv first):

    <venv>/bin/python scripts/evallog_parity.py \
        --fixtures DIR --venv VENVROOT --html-out DIR [--report FILE]

Exit 0 every check passed. Exit 1 a check failed. Exit 2 the corpus and the
pinned list disagree, or the run could not be set up at all.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
KIT = REPO / "StudioKit" / "Sources" / "StudioKit"

# The six capability flags an embodiment may advertise, transcribed from
# inspect_robots/embodiment.py:33-40. Typed out rather than imported so that a
# capability this app invents, or one upstream quietly drops, is a red gate
# instead of a tautology.
CAPABILITIES = {
    "seedable",
    "resettable",
    "auto_reset",
    "privileged_success",
    "renderable",
    "self_paced",
}

# The keys in policy_config whose values are sentences this app authored, and
# which must never appear in embodiment_info. embodiment_info is what upstream's
# report renders as machine facts about the body; a paragraph of this app's
# prose in there would be read as a property of the robot.
HONESTY_NOTES = {
    "bench_host",
    "bench_world",
    "epoch_axis",
    "horizon_note",
    "identity_note",
    "refused_terms",
    "residual",
    "seed_note",
    "step_counts",
    "trace_note",
}


class Failure(Exception):
    """A check that did not hold. The message is what gets printed."""


# --------------------------------------------------------------------------
# what the kit says, read out of the kit


def swift_string(path: Path, name: str) -> str:
    """The value of a `static let NAME = "..."` in a Swift file, joined across
    any `+ "..."` continuation lines.

    Reading it rather than repeating it is the rule the kit itself states beside
    these constants: a parser holding its own copy of the words it is looking
    for goes on finding nothing after somebody improves the sentence.
    """
    text = path.read_text(encoding="utf-8")
    match = re.search(
        r"static\s+let\s+" + re.escape(name) + r"\s*=\s*((?:\s*\+?\s*\"(?:[^\"\\]|\\.)*\")+)",
        text,
    )
    if not match:
        raise Failure(f"{path.name} has no static let {name}; this gate reads it from there")
    pieces = re.findall(r"\"((?:[^\"\\]|\\.)*)\"", match.group(1))
    return "".join(json.loads('"' + piece + '"') for piece in pieces)


def scorer_roles() -> dict[str, str]:
    """Every scorer this app can emit, and its role, out of EvalScorer.swift."""
    text = (KIT / "EvalScorer.swift").read_text(encoding="utf-8")
    roles = {
        name: role
        for name, role in re.findall(
            r"name:\s*\"([a-z0-9_]+)\"[\s\S]{0,600}?role:\s*\.([A-Za-z]+)", text
        )
    }
    # A parse that finds nothing must not read as a table with no rules in it.
    if len(roles) < 8 or roles.get("success_at_end") != "success":
        raise Failure(
            f"EvalScorer.swift parsed to {len(roles)} scorers "
            f"({sorted(roles)}); the shape of that file changed and this reader "
            "did not, so the motion evidence rule below is not being checked"
        )
    return roles


# --------------------------------------------------------------------------
# the corpus and the pinned list


def read_list(path: Path) -> list[str]:
    names: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        names.append(line.split("\t")[0].strip())
    return names


def manifest_names(path: Path) -> list[str]:
    names: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        name = line.split("\t")[0].strip()
        if name.endswith(".json"):
            names.append(name)
    return names


def agree(what: str, listed: list[str], found: list[str], where: str) -> None:
    missing = sorted(set(listed) - set(found))
    extra = sorted(set(found) - set(listed))
    if missing or extra:
        lines = [f"the pinned list and {where} disagree about the corpus"]
        for name in missing:
            lines.append(f"  in {what} and not in {where}: {name}")
        for name in extra:
            lines.append(f"  in {where} and not in {what}: {name}")
        lines.append("  Add it to scripts/evallog_fixtures.txt, or take it out of the kit.")
        raise SystemExit2("\n".join(lines))


class SystemExit2(Exception):
    """A setup disagreement, which exits 2 rather than 1."""


# --------------------------------------------------------------------------
# the checks over one log


def written_here(log_dict: dict, lead: str, tail: str) -> bool:
    """Did this app write this log, as the log itself says."""
    version = log_dict["eval"].get("inspect_robots_version") or ""
    return version.startswith(lead) and version.endswith(tail)


def close_enough(a: float, b: float) -> bool:
    # Not zero, deliberately. statistics.mean sums exactly with rationals before
    # converting, so it can differ from any running sum in the last unit in the
    # last place. This is the arithmetic sanity check; the byte comparison above
    # is the fidelity check, and it is exact.
    return math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-12)


def check_one(name: str, path: Path, log, roles: dict[str, str], ours: bool) -> list[str]:
    """Every invariant over one log. Returns the failures, so one bad fixture
    reports everything wrong with it rather than the first thing."""
    from inspect_robots.scorer import Score, reduce_scores

    bad: list[str] = []

    def want(condition: bool, said: str) -> None:
        if not condition:
            bad.append(f"{name}: {said}")

    data = json.loads(path.read_text(encoding="utf-8"))

    want(data["version"] == 1, "version is not 1, and read_eval_log rejects anything else")

    samples = data["samples"]
    results = data["results"]
    stats = data["stats"]

    # The eight parallel arrays. Their reader zips them, so a short one silently
    # drops trials off the end of whichever list ran out first.
    for sample in samples:
        width = len(sample["epochs"])
        for key in (
            "operator_judgements",
            "judgement_sources",
            "operator_notes",
            "operator_messages",
            "trial_metadata",
            "termination_reasons",
            "policy_transcripts",
        ):
            want(
                len(sample[key]) == width,
                f"scene {sample['scene_id']} has {width} epochs and "
                f"{len(sample[key])} {key}",
            )

    # An errored trial is recorded and never scored: an empty epoch dict beside
    # a null termination reason, counted into errored_trials.
    empties = sum(1 for s in samples for e in s["epochs"] if e == {})
    nulls = sum(1 for s in samples for r in s["termination_reasons"] if r is None)
    want(empties == nulls, f"{empties} empty epochs against {nulls} null termination reasons")
    if data["status"] != "cancelled":
        want(
            empties == results["errored_trials"],
            f"{empties} empty epochs against errored_trials {results['errored_trials']}",
        )

    # A run where everything errored cannot be a success, which is upstream's
    # own rule at eval.py:715-720 and the reason all_errored.json is here.
    if results["total_trials"] > 0 and results["errored_trials"] == results["total_trials"]:
        want(data["status"] != "success", "every trial errored and the status is still success")

    # success_at_end and the termination reason are two spellings of one fact.
    for sample in samples:
        for index, epoch in enumerate(sample["epochs"]):
            if "success_at_end" not in epoch:
                continue
            reason = sample["termination_reasons"][index]
            want(
                (epoch["success_at_end"] == 1.0) == (reason == "success"),
                f"scene {sample['scene_id']} trial {index} scores "
                f"success_at_end {epoch['success_at_end']} and terminated {reason!r}",
            )

    # No operator scorer. A watched verdict is recorded and is not a number in
    # the metrics, because one person watching three of twenty-four trials is
    # not a rate.
    want("operator" not in results["metrics"], "an operator scorer reached results.metrics")
    for sample in samples:
        for epoch in sample["epochs"]:
            want("operator" not in epoch, f"scene {sample['scene_id']} scores an operator key")

    # Every scene reduces the way its own metadata says it reduces, through
    # upstream's reducer and not through ours.
    for sample in samples:
        reducer = sample["scene_metadata"].get("reducer")
        if not reducer:
            continue
        scored = [e for e in sample["epochs"] if e != {}]
        for scorer_name, value in sample["reduced"].items():
            raw = [e[scorer_name] for e in scored if scorer_name in e]
            # A score that was not a number is null in the file, the way
            # _sanitize writes one, and their reducers take real numbers only.
            # A reading that is null everywhere reduces to null and that is the
            # whole check for it.
            values = [v for v in raw if v is not None]
            if value is None:
                want(
                    not values,
                    f"scene {sample['scene_id']} reduced {scorer_name} to null "
                    f"over the numbers {values}",
                )
                continue
            if not values:
                continue
            theirs = reduce_scores(reducer, [Score(value=v) for v in values]).value
            want(
                close_enough(float(theirs), float(value)),
                f"scene {sample['scene_id']} reduced {scorer_name} to {value} "
                f"and {reducer} of {values} is {theirs}",
            )

    # Every metric is the mean over the scenes that carry it, which is
    # eval.py:722-726.
    for scorer_name, value in results["metrics"].items():
        values = [s["reduced"][scorer_name] for s in samples if scorer_name in s["reduced"]]
        if value is None:
            want(
                any(v is None for v in values) or not values,
                f"metric {scorer_name} is null over {values}",
            )
            continue
        if not values or any(v is None for v in values):
            continue
        want(
            close_enough(statistics.mean(values), float(value)),
            f"metric {scorer_name} is {value} and the mean over its scenes is "
            f"{statistics.mean(values)}",
        )

    if not ours:
        # Everything below is a promise this app makes about its own files. An
        # imported log is somebody else's and is not held to them; it is here to
        # prove it survives the round trip untouched.
        return bad

    # A success rate never travels alone. Checked here, on the wire, in the
    # other language, because it is the claim the whole feature rests on. It is
    # a rule about the scorer sets this app offers, so an imported log, whose
    # scorers were chosen by somebody else and may not be in our table at all,
    # is not held to it.
    success_names = {n for n, role in roles.items() if role == "success"}
    motion_names = {n for n, role in roles.items() if role == "motionEvidence"}
    if set(results["metrics"]) & success_names:
        want(
            bool(set(results["metrics"]) & motion_names),
            "a success scorer is in the metrics with no motion evidence beside it",
        )

    want(data["eval"]["seed"] is None, "a seed was written into a log no route seeded")
    want(
        stats["mean_inference_latency_s"] is None,
        "an inference latency was written, and nothing here timed a policy",
    )
    want(stats["frames_dir"] is None, "a frames directory was written, and no frames were stored")

    info = data["eval"]["embodiment_info"]
    declared = set(info.get("capabilities", []))
    want("seedable" not in declared, "the embodiment declares seedable")
    unknown = sorted(declared - CAPABILITIES)
    want(not unknown, f"the embodiment declares capabilities upstream has no name for: {unknown}")

    strayed = sorted(set(info) & HONESTY_NOTES)
    want(not strayed, f"an honesty note is in embodiment_info rather than policy_config: {strayed}")
    config = data["eval"]["policy_config"]

    # A PAIR OF NULLS WHERE THEIR OWN RUNNER COULD NOT HAVE WRITTEN ONE.
    # `Task.resolve_envelope` requires max_steps or max_seconds, so a log with
    # neither is a log a reader who knows this schema will stop at. That is
    # honest for a grid, where the harness owns how long a cell runs and this
    # app has no number of its own, and it is only honest while the file says
    # so in the block their viewer renders.
    spec = data["eval"]
    if spec["max_steps"] is None and spec["max_seconds"] is None:
        want(
            "horizon_note" in config,
            "neither max_steps nor max_seconds is set and nothing in policy_config says whose "
            "horizon it was",
        )
    want(
        "criterion" in config,
        "the bench's own criterion is not in policy_config, so the file does not say "
        "what these numbers were a measure of",
    )

    return bad


# --------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", required=True, type=Path)
    parser.add_argument("--venv", required=True, type=Path, help="venv root, for its CLI")
    parser.add_argument("--html-out", required=True, type=Path)
    parser.add_argument("--list", type=Path, default=REPO / "scripts" / "evallog_fixtures.txt")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    report: list[str] = []

    def say(line: str = "") -> None:
        report.append(line)
        print(line, flush=True)

    try:
        from inspect_robots import read_eval_log
        from inspect_robots.logging.json_log import _sanitize
    except ImportError as exc:
        print(f"evallog_parity: inspect-robots is not importable here: {exc}", file=sys.stderr)
        print("  Run this through scripts/check_evallog_parity.sh, which makes the venv.",
              file=sys.stderr)
        return 2

    try:
        from importlib.metadata import version as installed_version

        library = installed_version("inspect-robots")
    except Exception:  # noqa: BLE001 - a version we cannot name is a failure, not a crash
        print("evallog_parity: cannot name the installed inspect-robots version", file=sys.stderr)
        print("  A parity result against an unnamed version is not a parity result.",
              file=sys.stderr)
        return 2

    say("evallog_parity")
    say(f"  inspect-robots {library}")
    say(f"  python {sys.version.split()[0]}")
    say(f"  fixtures {args.fixtures}")
    say()

    if not args.fixtures.is_dir():
        print(f"evallog_parity: no corpus at {args.fixtures}", file=sys.stderr)
        return 2

    try:
        listed = read_list(args.list)
        found = sorted(p.name for p in args.fixtures.glob("*.json"))
        if not listed:
            print(f"evallog_parity: {args.list} names no fixtures", file=sys.stderr)
            return 2
        if not found:
            print(f"evallog_parity: {args.fixtures} holds no logs", file=sys.stderr)
            print("  The kit's fixture writer did not run, and a gate over nothing is not a gate.",
                  file=sys.stderr)
            return 2
        agree("the list", listed, found, "the corpus on disk")
        manifest = args.fixtures / "manifest.txt"
        if not manifest.is_file():
            print(f"evallog_parity: no manifest.txt beside the corpus", file=sys.stderr)
            return 2
        agree("the list", listed, manifest_names(manifest), "the kit's manifest")

        roles = scorer_roles()
        lead = swift_string(KIT / "EvalRun.swift", "producerLead")
        tail = swift_string(KIT / "EvalRun.swift", "producerTail")
    except SystemExit2 as exc:
        print(f"evallog_parity: {exc}", file=sys.stderr)
        return 2
    except Failure as exc:
        print(f"evallog_parity: {exc}", file=sys.stderr)
        return 2

    args.html_out.mkdir(parents=True, exist_ok=True)
    cli = args.venv / "bin" / "inspect-robots"
    if not cli.is_file():
        print(f"evallog_parity: no inspect-robots command at {cli}", file=sys.stderr)
        return 2

    failures: list[str] = []
    for name in listed:
        path = args.fixtures / name
        line = f"  {name:<26}"

        try:
            log = read_eval_log(path)
        except Exception as exc:  # noqa: BLE001 - their reader refusing IS the result
            failures.append(f"{name}: read_eval_log refused it: {exc}")
            say(line + "read_eval_log FAILED")
            continue

        redumped = json.dumps(_sanitize(log.to_dict()), indent=2, sort_keys=True, allow_nan=False)
        original = path.read_text(encoding="utf-8")
        if redumped != original:
            failures.append(
                f"{name}: their own writer does not reproduce this file "
                f"({len(original)} bytes in, {len(redumped)} out)"
            )
            say(line + "re-dump DIFFERS")
            continue

        rendered = args.html_out / f"{path.stem}.html"
        view = subprocess.run(
            [str(cli), "view", str(path), "-o", str(rendered)],
            capture_output=True,
            text=True,
        )
        if view.returncode != 0 or not rendered.is_file() or rendered.stat().st_size == 0:
            failures.append(f"{name}: inspect-robots view failed: {view.stderr.strip()}")
            say(line + "view FAILED")
            continue

        data = json.loads(original)
        ours = written_here(data, lead, tail)
        try:
            bad = check_one(name, path, log, roles, ours)
        except Failure as exc:
            bad = [f"{name}: {exc}"]
        failures.extend(bad)

        mark = "ok" if not bad else f"{len(bad)} FAILED"
        origin = "written here" if ours else "imported"
        say(f"{line}{len(original):>7} bytes  {origin:<12} read, re-dumped, viewed  {mark}")

    say()

    # The command a person will type on a directory of these, once. Their index
    # is how a shelf of logs is read, and it is a different code path from the
    # single-file view above.
    index = args.html_out / "index"
    run = subprocess.run(
        [str(cli), "view", str(args.fixtures), "-o", str(index)],
        capture_output=True,
        text=True,
    )
    if run.returncode != 0 or not (index / "index.html").is_file():
        failures.append(f"the directory index failed: {run.stderr.strip()}")
        say("  inspect-robots view <dir>     FAILED")
    else:
        say(f"  inspect-robots view <dir>     index at {index / 'index.html'}")

    say()
    if failures:
        say(f"FAILED: {len(failures)} check(s) over {len(listed)} logs, against {library}")
        for failure in failures:
            say(f"  {failure}")
    else:
        say(f"PASSED: {len(listed)} logs read, re-dumped byte for byte and rendered by {library}")

    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text("\n".join(report) + "\n", encoding="utf-8")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
