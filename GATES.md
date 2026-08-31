_Duck Studio — pre-registered decision gates_

Written before launch, on purpose. Duck Studio is a free developer tool for a
narrow audience, and "the RL crowd would love this" is a feeling, not evidence.
These thresholds are fixed **now** so the decision later is a lookup rather than
an argument with myself. Clocks start at **App Store approval** — the downloads
numerator does not exist until the app is live.

**Hard rule: Duck Studio ships no in-app analytics.** No first-party endpoint,
no SDK, no event stream, no per-user telemetry. The App Privacy label is **Data
Not Collected** and the Privacy Manifest declares an empty
`NSPrivacyCollectedDataTypes`. This is easier to mean here than anywhere else in
the family: the app has no account and no server of its own. What it used to
claim beside that — "exactly one outbound request in the whole binary" — stopped
being true and is corrected here rather than left standing. There are five kinds
of outbound request, and the property that matters is not that there is one, it
is that **every one of them goes to an address the person typed or a service
they signed into, and none of them is ours**:

- a language model endpoint, at a URL the person entered (on-device and
  local-network models make no request leave the house at all),
- a policy `.onnx`, at a URL the person entered,
- Hugging Face — **unauthenticated** when the hub is searched or a community
  policy or manifest is fetched: `CommunityPoliciesView` and `CatalogueView` set
  no `Authorization` header on any of those requests, which is why a private
  repository fails there with a plain 401 (checked 2026-08-30: an unauthenticated
  GET of a repository this account cannot see answers 401, not 404 — the hub does
  not leak existence). The person's own **write token** is
  attached on exactly one path, publishing, by
  `HuggingFacePublish.urlRequest(for:token:)`. This line used to say the token
  went out on search as well; it does not,
- GitHub, unauthenticated, when the scan button is pressed: `api.github.com` for
  the catalogue listing and `raw.githubusercontent.com` for a file it offers.
  This line was missing while the paragraph above claimed to enumerate
  everything, and two hosts absent from a list of hosts is the kind of omission
  this document exists to not make,
- a physics bench on the local network, at an address the person entered, which
  `DuckBench.Address` refuses to send anywhere that is not obviously local.

No analytics, no SDK, no event stream, no per-user telemetry, and no endpoint
this project controls — that is the claim, and it is still true. Every number
below is a **$0 side-channel proxy** measured *outside* the app.

---

## PASS — keep investing (evaluated at **60 days** post-approval)

**ALL THREE** must hold:

- **≥ 250 first-time downloads** — App Store Connect App Analytics, cumulative
  over the 60 days. Lower than OpenCastor's 300 because the audience is
  genuinely narrower; a policy debugger is not for everyone who owns a robot.
  Set at the level where continued work is obviously justified rather than at a
  forecast.
- **≥ 100 unique visits to the docs page `/bring-your-own-policy`** —
  Cloudflare Web Analytics on the docs Pages site, cross-checked against the
  `golinks.craigm26.workers.dev/duckstudio/byop` counter. This is the **depth**
  signal and the one that actually matters: nobody reaches that page by
  accident. They reach it because they have an `.onnx` of their own and want to
  get it onto their phone. Downloads say people were curious; this says people
  had a policy.
- **≥ 40 trailing-30-day downloads of the Hugging Face dataset
  `craigm26/microduck-policy-golden-vectors`** *(read from
  `https://huggingface.co/api/datasets/craigm26/microduck-policy-golden-vectors`
  → `downloads`)*, **OR ≥ 25 stars on the public `duck-studio-zoo` repo**.
  Golden observation→action vectors are not a casual download. Anybody who takes
  them is verifying an implementation, which is the exact person this app is
  for. The stars alternative exists so a single HF outage or a renamed repo does
  not decide the question.

  **The dataset went live 2026-08-30 and read `downloads: 0` on its first
  query**, so the clock on this criterion starts from a real zero rather than
  from a repository that did not exist — which is what it was measuring until
  now: the URL above returned 401 for as long as this gate has been written
  down, so this criterion has never been measurable and neither has the PASS it
  is part of.

  **NOTHING WE CONTROL MAY LINK TO IT.** Hugging Face counts a download per file
  GET or HEAD, deduplicated per IP per five minutes — so a link from the app, a
  Space, the docs site or a README turns some fraction of this number into our
  own traffic measuring itself. That would not be a small distortion of a
  40-download threshold, it would be the whole threshold. Either no surface we
  own links to this dataset, or this line gets amended to name every link that
  exists before the count is read. A pre-registered gate and a funnel pointing
  at it cannot both be had.

A PASS means the tool reached practitioners and practitioners pointed it at
their own networks. Build M6 (diff), M7 (AR) and the v1.1 geom ghost.

## KILL — stop and archive (evaluated at **90 days** post-approval)

**EITHER** triggers a kill:

- **< 80 first-time downloads** over the 90 days (App Store Connect App
  Analytics), **OR**
- **Zero evidence anyone loaded a policy that was not bundled** — all three of:
  `/bring-your-own-policy` under 20 visits, the HF dataset under 10 trailing
  30-day downloads, and zero GitHub issues or discussions on `duck-studio-zoo`
  mentioning a user's own checkpoint. An inspector nobody points at their own
  network is a demo of seven files I did not train.

A KILL means archive the repo, keep the write-up, publish the refusal-corpus
generator as a standalone gist because it is useful on its own, and move on.

Between PASS and KILL — say, downloads fine but nobody brings their own
policy — is a **pivot** signal, not a continue. The correct pivot in that case
is to stop treating it as a debugger and treat it as a *teaching* app about how
a 61→14 locomotion policy works, which is a different app with a different
first screen.

---

## REVIEW — mandatory re-decision at **first Microduck delivery, or 2027-02-01,
whichever comes first**

Not pass/kill. A required re-run of every number above, because the audience
changes shape the day hardware ships. Before delivery, everyone using this app
is training policies. After delivery, most people holding a duck are not, and
the app either grows a bridge to the robot (it currently has none, deliberately)
or accepts a smaller permanent audience. That decision is not being made now on
guesses; it is being scheduled now so it gets made at all.

Pollen's stated first deliveries are "around Christmas 2026." 2027-02-01 is the
backstop so a slipped ship date cannot quietly cancel the review.

## Engineering gates — measured on device, never shipped

Pre-registered so the decision is not made under deadline pressure:

- **Full 14×61 analytic Jacobian in under 16 ms on an iPhone 12.** Measured with
  `os_signpost` on a debug build, by hand, on one device. If it misses, the
  sensitivity heat map becomes on-demand (tap to compute) rather than live under
  a moving finger, and that is a documented downgrade rather than a bug.
- **Forward pass agreement with onnxruntime stays within 1e-4** on the golden
  vectors, per component. **What that covers today, exactly:** DuckKit's fixture
  `golden_policies.json` holds cases for two files — `alpha_walking.onnx` and
  `ball_kick_left.onnx` — and `DuckPolicyTests` reads one of them, asserting the
  four `alpha_walking` cases per component at `accuracy: 1e-4`. This line used to
  say "on every one of the seven policies", and no such test exists; it also said
  the tolerance is printed on the policy card in the app, and it is printed
  nowhere in the app. One network's evidence is what this gate has, and it is
  named as one network's evidence. Widening the fixture to the rest of the nine
  bundled files is the work the gate is actually asking for.
- **App Review 2.5.2 fallback.** If the URL loader is rejected as executing
  downloaded code and the written argument (see `PLAN.md`) is not accepted,
  ship Files-app-only import within **7 days**. Do not argue it twice.

---

## The $0 proxy sources

Four, all outside the app, all free, none storing anything per-user:

1. **App Store downloads** — App Store Connect → App Analytics, first-time
   downloads. Aggregate, Apple-provided, no SDK. The numerator.
2. **Docs-site visits** — Cloudflare Web Analytics (cookieless) on the docs
   Pages project, cross-checked against the `golinks` D1 rollup at
   `golinks.craigm26.workers.dev/duckstudio/<src>`, which 302-redirects and
   increments a `(app, src, day)` count. Counts only: no cookies, no IPs. The
   `/bring-your-own-policy` page is the depth denominator.
3. **Hugging Face download counts** — `craigm26/microduck-policy-golden-vectors`
   (dataset). Public, returned by the HF API, counted by HF. Reading it is one
   unauthenticated GET.
4. **GitHub stars and clones** — on the *public* `duck-studio-zoo` companion.
   The app repo itself is private, so it has no such signal; the companion
   exists partly to create one honestly.

None of these instruments the app or its users. That is the whole point: a
Data-Not-Collected app can still be measured, as long as you are willing to
count doors instead of people and to accept that the counts are coarse.

### Provenance
- Downloads: App Store Connect App Analytics (post-approval).
- Docs: Cloudflare Web Analytics + `golinks` D1 (`golinks_stats.clicks`,
  app=`duckstudio`). Read:
  `curl -H "Authorization: Bearer <token>" https://golinks.craigm26.workers.dev/stats`.
- HF: `curl -s https://huggingface.co/api/datasets/craigm26/microduck-policy-golden-vectors | jq .downloads`.
- GitHub: `gh api repos/craigm26/duck-studio-zoo --jq '.stargazers_count'`.
- **Evaluate PASS at day 60, KILL at day 90, from the App Store approval date.
  Evaluate REVIEW at first Microduck delivery or 2027-02-01, whichever is
  first.**
