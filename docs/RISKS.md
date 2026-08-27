# Known risks

Written before the first line of app code, most severe first.

1. App Review 2.5.2 / 4.7 on the URL loader. Fetching a user-supplied .onnx and running it is defensible — the app has no interpreter and refuses any graph that is not the exact nine-op 61-512-256-128-14 architecture — but a reviewer skimming will see 'downloads a model and executes it.' The URL path is also the differentiating feature versus a Files-only importer. The written argument goes in the review notes before submission, and the pre-registered fallback (Files-only within 7 days) is in GATES.md so this gets decided once, not twice.

2. The audience may simply be too small. I do not know the Microduck pre-order count and will not guess it. The intersection of 'trains RL locomotion policies' and 'wants to debug them on a phone' could be a few hundred people worldwide. Duck Studio can be excellent, ship on time, and still miss 250 downloads — that is not a build failure, and the gates are written so I do not talk myself out of reading the number.

3. The 61-slider UI is the hardest interface problem in this family and every mitigation is unvalidated. Sticky outputs over scrolling inputs, collapsed blocks with informative headers, phone-IMU-driven gyro/gravity, loop-driven joint blocks, and per-slot pinning are five good ideas that have never been in front of a user together. If the Inspect screen is bad, M3 through M6 are all bad, because they inherit its layout. Mitigation: build M2 and M3 before M4/M5/M6 and be willing to throw the layout away once.

4. The DuckKit refactors touch the load path that 848 tests currently pin, and CastorKit/OpenCastor depend on the same code. Extraction order is load-bearing: extract DuckKit into its own repo FIRST, refactor there, then point CastorKit at the package. Refactoring in both places simultaneously is how the observation layout — the highest-risk file in the family — quietly acquires two versions.

5. The AR ghost has no physics, no mesh, and no ground contact. A kinematic skeleton on a floor plane with a 'no contact forces' label is honest, and honesty is the house style, but it may read as unfinished to a reviewer looking for polish and to a user expecting a duck. v1.1's DuckKinematics.geoms fixes the look; nothing fixes the physics, and nothing should pretend to.

6. Float determinism versus onnxruntime. The pure-Swift forward pass agrees to 1e-4, not exactly, because accumulation order differs. A practitioner will compare a Duck Studio number to their notebook and find the fifth decimal off. If that surprises them, the app loses credibility instantly. Mitigation: the tolerance is printed on the policy card in the app, not buried in a README, and the golden-vector dataset is published so anyone can check the claim themselves.

7. Bundling the seven upstream Apache-2.0 policies (~5.6 MB) is legally fine but operationally manual: NOTICE, in-app attribution, and a re-vendor step every time upstream retrains. Six of the seven are not yet in the tree — only alpha_walking.onnx (793,705 bytes) is vendored today — so T-010 depends on fetching from a repo that is still moving.

8. Overclaiming what the recurrence and limit-cycle results mean. They are properties of the network iterated in isolation with frozen inputs, not predictions about a robot standing on a floor. The gait period read off a limit cycle is a real number about the policy and not a promise about hardware. Stating that clearly costs some of the demo's punch, and saying it anyway is the only version of this app worth shipping.
