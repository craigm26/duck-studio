# Vendored policies

Copied verbatim from `pollen-robotics/microduck` by way of the duck simulator in
`duck-sounds/site`. Apache-2.0, same as upstream. These are the real trained
networks, not stand-ins: the point of an inspector is that it inspects the thing
that actually drives the robot.

Sizes and digests are recorded so a file that changes underneath this repo is
noticed rather than silently inspected. The digest here is over the FILE; note
that `DuckPolicy.fingerprint` deliberately digests the parameters instead, so
these two numbers answer different questions and are expected to differ.

| File | Bytes | SHA-256 (file) |
|---|---|---|
| `alpha_sitstand.onnx` | 793,695 | `c6c40e35e726eabd803d633e090d1129…` |
| `alpha_stand.onnx` | 793,705 | `1569268713e40deea795dd2922dba50d…` |
| `roller.onnx` | 793,685 | `cf05651d2708a2f9364212e86b866c97…` |
| `roller_crouch.onnx` | 793,685 | `a1a084be240469c76ac9d3fa44d4792f…` |
| `alpha_ground_pick.onnx` | 793,685 | `ffbf5109982ff999b0ba53afe86b9ae7…` |
| `alpha_walking.onnx` | 793,705 | `e36332d383997d51401897734cd3e79c…` |
| `ball_kick_left.onnx` | 793,685 | `d6928284dccd3dd61e08bf2f760effa7…` |
| `ball_kick_right.onnx` | 793,685 | `147a32c388c6b19111b3ac3b550a9a6d…` |
| `roulade.onnx` | 793,685 | `3d60da08fc13f29c1b57f41977aa8981…` |
