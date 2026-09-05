# tune-trace-probe.json

What it is: one `/tune` answer, captured verbatim from the bench at
`http://100.122.199.6:8770` on 2026-09-05, asked for **with** `"trace": true`.
Nothing about the response was edited, reformatted or pretty printed. The bytes
in the file are the bytes the bench sent.

Why it exists: `DuckBench.Tuned` gained a `trace` field and `Tuned.Episode`
gained `endHeight`, and both are read by `DuckBench.readTuned`. The sibling
capture `tune-identity-probe.json` was taken on 2026-09-02 without a trace, so
its top level keys are `criterion, duck, engine, episodes, perDrop, plantDigest,
plantName, policy, refused, seconds, standing, terms, termsWhy, travelled,
travelledWhy`: there is no `trace` and no `traceWhy` in it, and the new read
path would otherwise have shipped with no captured answer behind it. That is
exactly the failure `BenchTuneParityTests` was written to prevent, one field
later.

The request, which is the body `DuckBench.tune` builds:

```json
{
  "policy": "alpha_walking.onnx",
  "gain":   [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  "offset": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  "seconds": 2.0,
  "drops": [0.12, 0.13],
  "schedule": [[0.0, {"vx": 0.0, "vy": 0.0, "vyaw": 0.0}],
               [0.5, {"vx": 0.5, "vy": 0.0, "vyaw": 0.0}]],
  "terms": ["upright", "track_linear_velocity", "track_angular_velocity",
            "pose", "body_ang_vel", "action_rate_l2"],
  "trace": true
}
```

That is `alpha_walking.onnx` at the identity residual, `DuckBench.walkingCommand`
as the schedule, two seconds, and the two drop heights the parity test asserts
against. Two seconds at 50 Hz is 100 ticks, which is what the trace carries: the
FIRST drop only, capped by the bench at 500.

What the answer says, and what the test pins:

- 22 top level keys, `trace` and `traceWhy` among them.
- `trace` is 100 ticks, each `{root: 7, qvel: 6, twist: 6, joints: 14,
  action: 14, command: 3}`.
- `perDrop` is two episodes at 0.12 m and 0.13 m, both standing, with
  `endHeight` 0.1212 m and 0.1217 m. The `endHeight` half of the change was
  already gateable from the 2026-09-02 capture; this one gates it again on a
  bench that also sends a trace.
- `plantName` `scene.mjb`, `plantDigest` beginning `3f8c9ab9b409`.
- `config` `microduck_velocity_env_cfg`, `refused` empty.

The bench was reachable, so this is a real capture and not a reconstruction from
the vendored core. If it ever has to be retaken, take it the same way: the
request above, against a bench whose `/health` names `scene.mjb` at the same
digest, and replace the whole file rather than editing a field.
