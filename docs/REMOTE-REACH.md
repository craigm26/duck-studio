# Reaching a duck from anywhere: sign in with Hugging Face, talk through Pollen's rendezvous

Status: stage 1 built (sign in and list, 2026-09-24) · stages 2-5 design · Written for Craig, from the Pi session

Today Duck Studio reaches a duck only on the same network, through the bridge. Pollen's
[`microduck-console`](https://huggingface.co/spaces/pollen-robotics/microduck-console) already
does the other thing: sign in with Hugging Face, and the ducks your account owns appear wherever
you are. This page proposes Duck Studio as a second client of the same service, and says exactly
how much of it is already built on the robot's side.

Everything factual below comes from Pollen's `docs/design/remote-access-design.md` (in
`pollen-robotics/microduck`, draft of 2026-09-02) and the console's own page, not from guesses.
The kit has waited for this on purpose: `DuckWebRTC` holds the shape of a signalling client that
nothing conforms to, "because a client written against a guessed contract is worse than none". The
contract is now written down.

## What Pollen has built, and what that leaves for us

Their order of work has five slices. Four are **done** on the robot:

1. **Account.** `account login` runs Hugging Face's OAuth device flow on the duck. The token lands
   in `/etc/robot/hf-token` and renews itself (30 days, rotating refresh).
2. **Relay, registering.** `mediad::relay` registers the duck with the rendezvous
   (`pollen-robotics-reachy-mini-central.hf.space`, which Pollen maintains) as `kind: microduck`.
3. **The client.** `microduck-console`, a Space with a Hugging Face sign-in.
4. **Sessions.** A remote consumer is bridged to the duck's own signalling.
5. **NAT.** STUN on both ends; the robot offers a TURN relay.

That leaves us one job: **a client in Duck Studio**. No server of ours, no change on the robot.

## The design: HTTP only, no WebRTC library

Pollen's §3.8 describes a **control lane that needs no candidate pair**. A JSON-RPC call rides the
rendezvous itself as a `peer` envelope:

```
Duck Studio ──POST /send {type: peer, sessionId, rpc: {…}}──► rendezvous ──SSE──► duck's relay
            ◄──────────── SSE {type: peer, sessionId, rpc: {…}} ◄──POST /send───────┘
```

That is `URLSession` and a server-sent event stream: no WebRTC framework in the app, and nothing
new for App Review. The duck answers with the **same routing table** a LAN peer gets (their §3.6),
so the app's existing `DuckCall` vocabulary carries over.

It comes with two limits, both from the service:

- **No video.** Frames need WebRTC or `media.stream`. Remote in this design is control and state,
  not a camera.
- **The rate of a behaviour, not of a joystick.** 1,200 requests per minute per peer, and going
  over earns a `429` on the whole peer. So remote is for **plans, walker installs, state reads and
  A/B runs**, not for sticks. The Control deck's sticks stay LAN-only, and the screen says why.

### The pieces in the app

1. **Sign in with Hugging Face.** `ASWebAuthenticationSession`, OAuth with PKCE, scopes
   **`openid profile` only**. Pollen's §2.4 names over-broad scopes as the one thing to fix before
   shipping, and the console asks for exactly these two. This is **not** the write token Settings
   already holds for publishing, which stays separate.
2. **List your ducks.** `GET /api/robot-status` with the bearer token. It opens no session, which
   matters: peers are keyed by token, so listing via `/events` would drop a session riding on it
   (their §5.2). Filter to `kind: microduck`.
3. **A `RendezvousPeer`** conforming to `DuckPeer`, with its own row in the routing table
   (`DuckMethod.reach(for: .rendezvous)`). Its column follows §3.6 minus anything rate-sensitive.
   It is kit code, tested on Linux against recorded SSE transcripts.
4. **Where it shows.** A duck reached this way appears in *Your machines* as "Yoshi: reachable
   from anywhere", and the plan editor and walker install work against it.

### Benches and routers don't need this

Remote reach for **benches and routers** is already solved and costs nothing: they are ordinary
computers, and `DuckBench.address` accepts tailnet addresses (100.64/10) by design. A phone on
Tailscale reaches the Pi's bench and router from anywhere today. The rendezvous is for **ducks**,
which run Pollen's software and can't join a tailnet.

## Privacy and GATES.md

The rendezvous is Pollen's service, reached with the person's own Hugging Face sign-in. That is "a
service they signed into", the same category GATES.md already allows for publishing, and still
**none of it is ours**. The sign-in carries identity only. Nothing is sent to this project, so the
label stays **Data Not Collected**. GATES.md and the README gain one line naming the rendezvous
host, as they did for the router.

## Risks

- **It is somebody else's service.** Pollen maintains it for the Reachy Mini fleet too, and "a
  change made there for the mini can break ducks" (their §4). Remote is therefore an extra, never
  a dependency: LAN mode must not need it, the same invariant Pollen holds.
- **Tokens are per peer.** The app must use its own sign-in token, never the robot's, or listing
  takes the duck off the rendezvous.
- **A `401` is the token and nothing else** (their hard-won §5.2). The screen says "sign in
  again", not "your duck is not there". That's the console's rule again.

## Order of work

1. **Sign in and list.** Verifiable end to end the day a duck has run `account login`: the app
   shows that duck. It doubles as the first proof the whole path is real.
2. **Read-only control.** `robot.state` over the control lane, shown on My Microduck.
3. **Run a plan remotely.** The plan editor's run path over `RendezvousPeer`, which is exactly the
   "rate of a behaviour" the lane is built for.
4. **Install a walker remotely.** `policy.fetch` / `robot.setSkill`, with the robot's own refusals
   shown as the robot wrote them (Pollen's `policy-playground` does the same).
5. **Live A/B remotely** (`MULTI-DUCK.md`), once two ducks exist.

## Open, and whose

- **A physical Microduck that has run `account login`.** Craig. Stage 1 cannot be verified
  without one; everything before that is kit code with recorded transcripts.
- ~~An OAuth app for Duck Studio's sign-in.~~ **Done 2026-09-24**: client id
  `fa895e94-2e3c-464c-9c98-73f250e16c98`, redirect `duckstudio://oauth/callback`, scopes
  `openid profile` (checked against Hugging Face's authorise endpoint).
- **Whether Pollen is content for a third-party client on their rendezvous.** Asked in
  pollen-robotics/microduck#329. Listing (stage 1) is read-only and opens no session; stage 2
  (sending calls) waits for the answer.
