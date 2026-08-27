# What this app needs from DuckKit

[DuckKit](https://github.com/craigm26/duckkit) is the shared pure-Swift core:
the joint tables, the 61-float observation contract, a hand-written ONNX reader
and MLP, the gait pipeline, forward kinematics and the 50 Hz loop. It has zero
package dependencies so it tests on Linux, and that claim is load-bearing.

This app needs the following. Each item is an API to add or a type to move --
resolve them in duckkit first, then depend on a tag.

1. D-1 DuckPolicy.describe(from:) -> Description — an always-succeeding structural read (op sequence, initializer names + dims, graph input/output names + shapes, parameter count), with load() refactored to describe + validate. This is the single most important ask: the app's best screen shows WHY a user's own ONNX export was refused alongside a full dump of what was actually found, and a thrown error carries a sentence, not a structure.

2. D-2 Make the trained normalization public — `normalization: (mean: [Float], std: [Float])`, plus `layerWidths` and `parameterCount`. The z-score strip ('this observation is 4.2 training std out of distribution on slot 27') is built entirely from numbers already sitting in the file and currently unreachable because mean/std are internal.

3. D-3 DuckPolicy.inferTrace(_:) -> Trace returning normalized input, h1(512), h2(256), h3(128) and actions(14). Free — those arrays already exist inside infer(). Enables per-layer dead-unit counts (ELU units sitting at x <= 0, in the exponential regime).

4. D-4 DuckPolicy.jacobian(at:) -> [[Float]] — the exact 14x61 d(action)/d(normalized input) by reverse mode through the ELU stack (ELU' = 1 for x>0, e^x for x<=0). Must be analytic, not finite-differenced: epsilon selection across slots whose units span rad, rad/s and dimensionless is exactly the choice that yields a plausible wrong answer. Test it against central differences to 1e-3 at ten observations. ~14 backward passes, well under a frame.

5. D-5 DuckPolicy.fingerprint — SHA-256 over parameters in canonical order (mean, std, then per-layer weights then biases, little-endian Float32). Identity by weights, not filename, so metadata-only differences collapse and a one-weight change does not. Brings swift-crypto into DuckKit, which D-8 needs anyway.

6. D-6 DuckGait.stages(action:previousTargets:kind:mouth:alphas:) -> Stages carrying scaled / filtered / clamped / limitedBy separately, with frame() reimplemented on top so there is one pipeline. Low-pass alphas become a parameter defaulting to (head 0.5, legs 0.7) so the alpha sweep does not require a second copy of the filter.

7. D-7 DuckSimulation.State — a readable and writable struct (jointPositions, previousTargets, lastAction, tickCount) plus init(walk:stand:state:). Everything is private today, so Duck Studio cannot inject a state, cannot pin an observation slot mid-loop, and cannot restart two policies from an identical initial condition for the closed-loop divergence diff.

8. D-8 MOVE from CastorKit into DuckKit: CanonicalJSON + CanonicalValue (rcan-canonical-json-v1), Ed25519 signing via swift-crypto, SigningKeyStore (Keychain on device, in-memory on Linux), and the hash-chained NDJSON Journal. Constraint: Journal is currently typed to OpenCastor's Receipt — it must be GENERALIZED over a CanonicalValue payload during the move, not copied, or the two will drift. Needed so StudioReport turns a screenshot into a verifiable, reproducible bug report.

9. D-9 (optional, v1.1) DuckKinematics.geoms — the MJCF geom primitives (type, size, pos, quat, parent body) from robot_walk.xml, so the AR ghost draws the robot's real shapes instead of a stick figure. v1.0 ships segments-between-body-origins plus named site markers, which is honest and needs nothing new.

10. NOT needed, stated so it does not get dragged in: PhoneSight. Duck Studio's AR needs a horizontal plane and nothing more; LiDAR capability tiering would add an ARKit dependency to a package whose entire value is that it builds and tests on Linux aarch64.
