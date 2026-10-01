"""Import every Microduck Studio training config into microduck_rl and check its terms bind.

See README.md beside this file. Prints one JSON line per config; exits 1 on any failure
that is not a deliberate missing-sensor refusal."""
import importlib.util, json, sys, traceback, pathlib
out = pathlib.Path(sys.argv[1])
VOCAB = set(json.loads((out / 'vocabulary.json').read_text()))
results = []
for m in json.loads((out / "manifest.json").read_text()):
    row = {"file": m["file"]}
    try:
        spec = importlib.util.spec_from_file_location(m["file"][:-3], out / m["file"])
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        row["import"] = "ok"
        cfg = getattr(mod, m["factory"])(play=False)
        row["factory"] = "ok"
        row["rewards"] = len(cfg.rewards)
        import inspect
        bad = []
        for key, term in cfg.rewards.items():
            if not key.startswith(tuple(VOCAB)):
                continue  # upstream's own terms; many are classes, not functions
            try:
                inspect.signature(term.func).bind(None, **(term.params or {}))
            except TypeError as e:
                bad.append(f"{key}: {e}")
        row["unbound"] = bad
    except Exception as e:
        row["error"] = f"{type(e).__name__}: {e}"
        row["where"] = traceback.format_exc().strip().splitlines()[-3][:200]
    results.append(row)
    print(json.dumps(row))

failed = [r for r in results if r.get("unbound") or ("error" in r and "contact sensor" not in r["error"])]
sys.exit(1 if failed else 0)
