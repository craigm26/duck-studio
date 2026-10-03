# Upstream gate: do the configs this app writes train in microduck_rl?

`TrainingRequest.envConfig()` writes a Python env config for Pollen's
[microduck_rl](https://github.com/pollen-robotics/microduck_rl). Until 2026-09-30
nothing had ever imported one. This gate does, on a CPU (no GPU needed), and it is free.

What it caught the first time (microduck_rl `cfe1c2a`, mjlab 1.3.0):
- two import lines that do not exist in mjlab 1.3.0, so **every** emitted file failed to import;
- five reward terms written with `params={}` that require arguments, which would only fail
  once training had started;
- `body_impact_cost` needs a head contact sensor only the ground-pick task defines.

## Run it

```bash
# 1. A CPU environment for microduck_rl (Python 3.12 via uv; torch from PyPI's CPU wheel).
git clone https://github.com/pollen-robotics/microduck_rl && cd microduck_rl
uv venv --python 3.12 .venv-cpu && . .venv-cpu/bin/activate
uv pip install "mjlab==1.3.0" "warp-lang==1.12.0" "torch==2.9.1" "onnxruntime>=1.24.4" \
  "huggingface_hub>=0.27.0" "matplotlib>=3.10.9" "scipy>=1.16" "rustypot>=1.4.2" pytest \
  "better-actuator-models @ git+https://github.com/Rhoban/bam.git@<the commit in uv.lock>"
uv pip install --no-deps -e .
python -m pytest tests/ -q          # upstream's own suite: 234 passed, 1 skipped on a Pi 5

# 2. Write one config per base, every vocabulary term on each (from this repo).
cd <duck-studio>/scripts/upstream_gate/trgen && swift run -q trgen /tmp/tr-out

# 3. Import, build, and bind every term.
python <duck-studio>/scripts/upstream_gate/gate.py /tmp/tr-out
```

Expected: ground pick and `walk_on` build with `"unbound": []`; the other four bases stop
with the deliberate missing-sensor sentence for `body_impact_cost`. Pin the bam commit from
microduck_rl's `uv.lock`: PyPI's latest renamed a kwarg and the task package fails to load.

## The manifests a real duck will load (added 2026-10-02)

Before 2026-10-02 every manifest Duck Studio published said `kind: "alpha_walking"` and the like,
which Pollen's `validate_manifest` refuses, so nothing published from the app could be installed
on a physical Microduck. `PolicyManifest.forPublishing` now writes Pollen's `kind`, `slot`,
`command.encoding`, `duration_s` and robot block. To re-check against Pollen's own validator:

```bash
cd <duck-studio>/scripts/upstream_gate/manifests && swift run -q manifests > /tmp/m.jsonl
python <duck-studio>/scripts/upstream_gate/manifest_gate.py /tmp/m.jsonl   # all seven kinds: PASS
```
