# Native-first redesign: the controller is the app

Status: plan, 2026-11-04. Nothing in this document has been built, run or measured. The latency numbers are targets until someone measures them on a device. API names marked "unverified" have not been checked against shipping SDKs. The groundwork was a read-only survey of `/home/craigm26/projects/duck-studio/DuckStudio/Sources` and StudioKit, a research pass on iOS 26/27 surfaces, a read of Pollen's public Microduck repos and design docs, and the robotd facts recorded from duck-sim 0.15.1. Three designs were compared. "Controller-first" won and is written up here, along with the four fixes the review required, the completeness critic's fixes and the best ideas from the two runners-up.

## Direction

Craig, 2026-11-04:

> "the Microduck Studio app is a complement to whatever Pollen Studios' puts out as their ios/ipad/mac app. For us, we want users to be able to make the simplest actions possible with our ios app. using apple intelligence/siri and whatever native tools are already available to us in ios. that way, latency is driven down and it might feel more natural. on the other end of the spectrum, we already have a ton of advanced options and features for customizations. all of this has to be wrapped up in a gorgeous UI and UX. we have a great start where a lot pieces are built, but they need to be presented first as if it is a native ios app with a real microduck that someone wants to control (manually (posing/buttons like a controller), semi-manually, autonomously) via buttons/voice commands."

What that means for the app:

- **The home is the controller.** Open the app and you see the duck full-bleed with your thumbs already on it. That is the real duck's camera when one is connected, otherwise the simulated duck labelled "Practice duck".
- **Three modes on one screen.** Drive (manual), Tell (semi-manual) and Auto (autonomous). A Stop button is always present on Play.
- **The simplest actions cost zero screens.** Siri, the Action button, Control Center, the Lock Screen and Spotlight each map one App Intent to one robot call over the home network.
- **Nothing advanced is deleted.** It moves one tab down into Studio, a real hub (Make, Behaviours, Train, Measure, Learn).
- **We complement Pollen.** Pollen's app owns setup, Wi-Fi, updates, sign-in and health, and we link out to it. Studio owns what Pollen does not build: native voice and Siri, system surfaces, sequencing, autonomy above the robot's control loop, and depth. Studio keeps saying it is not the official app (Pollen #329).

Two rules shape everything:

1. **Stop is local, deterministic and idempotent.** It never waits on a model, the UI, an unlock or a cloud round trip. It is instant for walking, chains, plans and goals. A skill the robot has already started finishes, because `robot.stop` zeroes the twist but does not cancel a running skill (robotd, duck-sim 0.15.1). The copy says so honestly.
2. **The person's thumbs win.** Any stick touch, pad input or move-button press cancels Tell and Auto.

## What a person does in the first five minutes with a real duck

Today the app greets a real-duck owner as someone without a duck. It opens on the simulator, makes them type an address and token (and the camera address again), and puts the sticks four sections down a list. The new flow:

**Minute 0: the welcome sheet.**
- It replaces FirstRun's three cards. The sentences move to a new `StudioKit/Onboarding.swift`.
- Page 1 asks: "Do you have a Microduck with you?"
- Three buttons (build 93, so the Wi-Fi question costs no tap of its own): "Yes, it's here and on my Wi-Fi" goes straight to finding the duck, "It's here, but not on Wi-Fi yet" goes to the Wi-Fi help, and "Not yet, let me practise".
- Small print: "Microduck Studio is a companion app, not Pollen's official app."
- "Not yet" goes straight to the controller in Drive mode with the Practice duck. The Duck sheet's "Add your duck" row re-enters at page 2 later.

**Minute 0 to 1: Wi-Fi check.**
- Page 2 is where "Add your duck" starts (a fresh install answers this on page 1). It asks: "Is your duck on your Wi-Fi?"
- "Yes" continues.
- "Not yet, or I don't know" explains that Pollen's Microduck app does Wi-Fi, updates and sign-in, and offers "Open Pollen's app" and "I've done that". Studio does not rebuild provisioning.

**Minute 1 to 2: find the duck without typing.**
- Page 3 is titled "Let Studio find your duck on this network".
- One sentence explains why the network is needed. A button press then triggers the iOS Local Network prompt in the foreground. This is the only safe moment: a background intent that hits an undetermined permission is silently denied (TN3179).
- If the person declines, show a Settings deep link and continue on the Practice duck.
- Discovery order:
  1. A Bluetooth scan (FindDuckView logic) lists nearby ducks by name. Picking one reads the duck's home-network address over Bluetooth. **Unverified:** confirm which `system.info` or `net.*` calls Pollen routes over BLE before promising this.
  2. Bonjour discovery of an OpenCastor bridge (MachineDiscovery).
  3. "Scan the code on your bridge" (a QR code holding host and token).
  4. "Type it", collapsed, last: today's RobotBridgeView fields.
- One `DuckConnection` (new, in StudioKit) stores host and token. The token goes in the keychain under a shared access group, and the host and last known state go in an App Group, so the build-92 extension can read them. The camera address is derived from the connection, so DuckCameraView never asks again.

**Minute 2 to 3: say hi.**
- Studio sends `robot.sound` (quack), plus `robot.flashlight` if the robot supports it, and asks "Did your duck just quack?" [Yes] / [That's not mine]. This doubles as Pollen's unbuilt "identify".
- Features are gated on `system.info`. Unknown fields are tolerated. API version 31 or later is accepted. Pollen is at 49 today, and duck-sim 0.15.1 reports 37.

**Minute 3: stand up.**
- One large "Stand up" button. It chains `robot.init`, `robot.enable {on: true}` (a bare enable is refused), start driving (`robot.do` is refused unless the policy is driving), and `robot.do stand`. A refusal comes back as the robot's named reason in plain words, for example "Your duck is sitting; it can only stand up from here."
- The sheet closes onto the controller with the venue on the real duck. Onboarding is an explicit connect action, so this venue switch is allowed (see Rules under the three control modes).

**Minutes 3 to 5: drive.**
- Three one-time coach marks, each a collapsed chip of 60 pt or less: "Press Stand", "Push the stick a little", "Tap the red disc any time to stop".
- After the first successful stand, a SiriTipView slides in once: "Say: Duck Studio, stop the duck."
- While the person drives, the speech model downloads in the background (AssetInventory), so the first mic press does not wait.
- After about 30 seconds of successful driving, a skippable "Make it yours" card shows how to add Stop to Control Center, how to put it on the Action button, and how to try Siri. The app cannot place a Control or set the Action button itself. The card shows the steps and opens the relevant Settings screen where iOS allows it, and never claims to have done it.

Onboarding never mentions benches, models, Hugging Face, detail levels, MuJoCo, deadman or policy.

**Returning launches.** The app reconnects silently to the last duck, and the duck pill shows "Connecting", then the duck's name. If the duck does not answer within 1.5 s, the app stays on the Practice duck with a "Reconnect" chip. It never switches venue by itself and never opens on a settings list.

**Exit check (build 91):** from a fresh install with a real duck (or the duck-sim robotd standing in), the duck stands in at most 4 taps with zero typing.

## The screen hierarchy

On iPhone there are three tabs (Play, Moves, Studio) and one Duck sheet that opens from the duck pill on every tab. The app opens on Play. Tags:

- [KEEP] stays where it is, possibly rebuilt in place.
- [MERGE] joins another surface.
- [DOWN] moves one level down.
- [CUT] is removed.
- [NEW] is new.

A file name means the existing view keeps its code unless the line says otherwise.

```
App
├── Welcome sheet (first install only)                          [NEW, replaces FirstRunView 3 cards; FirstRun.swift -> Onboarding.swift]
│   ├── Page 1 Do you have a Microduck?                          [NEW]
│   ├── Page 2 Is it on your Wi-Fi? (Open Pollen's app)          [NEW]
│   ├── Page 3 Find it: Local Network prompt, BLE (FindDuckView logic) [MERGE],
│   │         Bonjour (MachineDiscovery) [KEEP], QR [NEW], Type it (RobotBridgeView fields) [MERGE]
│   ├── Say hi (quack + "Did your duck just quack?")             [NEW]
│   └── Stand up, then coach marks                               [NEW]
│
├── Imports (onOpenURL -> Imports.open, DuckStudioApp.swift:379)  [KEEP, landing changed]
│   sequences, plans, packs land in Moves with an "Added" chip; drafts open in Studio > Make
│
├── Tab 1: Play  (DriveView rebuilt as ControllerView; -tab play, -tab control, index 0)
│   ├── Stage, full-bleed on every venue
│   │   ├── Sim stage (DriveView stage :785)                     [KEEP]
│   │   ├── Your floor (ARDriveStage)                            [KEEP, venue chosen in Duck sheet]
│   │   ├── Real duck: DuckCameraCard picture as the stage       [MERGE, the Robot venue List DriveView:2393-2521 is CUT]
│   │   └── No picture yet: illustrated poster + state sentence  [NEW]
│   ├── Top-left: duck pill (name, live dot, "Practice duck")    [NEW, opens Duck sheet;
│   │         live dot MERGES the toolbar LensIndicator, DriveView:490-499, :1847-1857]
│   ├── Top-centre: mode switch Drive | Tell | Auto              [NEW, replaces ControlShelfChips and PadChrome chip rows]
│   ├── Top-right: Stop, solid red disc, always shown            [NEW, every venue and mode]
│   ├── Bottom-left: floating stick (ThumbPad rebuilt)           [KEEP]
│   ├── Bottom-right: four move buttons + mic                    [NEW, face-button motions DriveView:3160 MERGE here]
│   ├── Head: two-finger drag / double-tap on the picture        [MERGE from Robot head mode DriveView:2440]
│   ├── Second Stop in the thumb zone while Auto runs            [NEW]
│   ├── Readout chip (state, last said, latency), <=60 pt        [NEW, replaces "Last said" list; telemetry text
│   │                                                             MERGES here (state) and into Robot details (numbers)]
│   ├── Pull-up Moves sheet (same tiles as the Moves tab)        [NEW, ControlMotionsSheet MERGE here]
│   ├── Pose (practice duck: JointHandleOverlay + pose bar)      [KEEP, no longer Full-only]
│   ├── Tell: typed field (TalkToTheDuckView) on every venue     [KEEP, PadChrome.swift:67 Robot removal CUT]
│   ├── Tell: Walk to the ball (phone driver card, either duck)  [MERGE, build 95, was an Auto card]
│   ├── Tell: Plan (PlanEditorView as a sheet)                   [KEEP]
│   ├── Tell: Watch for cards (DuckCardsViews toggle)            [MERGE from DuckCameraView]
│   ├── Auto: Ask the duck, Dream-1 beside it                    [MERGE, Dream chip DriveView:1203 + DreamSimSheet]
│   └── "More" sheet
│       ├── Scene (ControlSceneSheet), sim only                  [DOWN]
│       ├── Record a sequence (SequenceKeepSheet)                [DOWN from PadChrome Record]
│       ├── Pad map (PadMapSection)                              [DOWN from Play drawer]
│       └── Camera view, orbit and zoom (sim)                    [DOWN, camera column DriveView:1267 CUT]
│   CUT from Play: venue segmented control (DriveView:655-668), Play drawer (:1286-1325),
│     Mimic chip and Mimic bar on the phone, bench picker in the drawer (moves to Measure), Settings gear,
│     toolbar lens (merged into the pill)
│
├── Tab 2: Moves  (the toy box; -tab moves, index 1)
│   ├── Skills: robot slots + installed Hub skills + Pollen emotions (#384)   [NEW, reads robot.skills]
│   ├── Sounds (DuckSoundsView playback)                         [MERGE]
│   ├── My sequences (SequenceListView)                          [MERGE from PadChrome Sequences]
│   ├── My plans                                                 [MERGE from PadChrome Plan]
│   ├── Cards and Packs (DuckCardsViews, DuckPacksViews)         [MERGE from camera card]
│   ├── Games (sim shelf, "Practice duck only" badges):
│   │   Duck soccer (DuckSoccerView), Golf, Fetch, Follow me, Slalom,
│   │   Flamingo, Bow bridge, Trick run (GhostDuckView games)    [MERGE, from Studio "Play" 2 to 3 taps deep]
│   │   A game opens its own practice screen; it never moves the real duck and never switches venue
│   ├── Goals: Walk to the ball (opens Tell), Dream-1 (opens Auto)  [NEW]
│   └── Tile long-press: Put on a button, Add to Siri (ShortcutsLink), Details, Open in Studio  [NEW]
│   A tap on a skill, sound, sequence or plan runs on the current duck with the persistent Stop pill shown
│
├── Tab 3: Studio  (the workshop, inset-grouped List; -tab studio, index 2)
│   ├── "Show expert tools" row, visible at the top              [NEW, replaces DetailLevel]
│   ├── Make
│   │   ├── Motions (IntentListView -> IntentAuthorView -> PipelineView)  [KEEP; UI word "Motions", never "intent"]
│   │   ├── Plan editor (PlanEditorView)                         [KEEP]
│   │   ├── Draft with words (AutomationChatView)                [KEEP]
│   │   ├── Scenes                                               [KEEP]
│   │   ├── Sequences management (SequenceListView)              [KEEP]
│   │   ├── Duck sounds editor (DuckSoundsView)                  [KEEP]
│   │   └── Mimic (PoseCaptureView), Mac only                    [KEEP on Mac; CUT on iPhone and iPad]
│   ├── Behaviours  (was the Behaviours tab)
│   │   ├── Library (PolicyListView installed shelf), PolicyDetailView, Retrain  [DOWN]
│   │   ├── Catalogue, Community                                 [DOWN]
│   │   ├── Blend                                                [DOWN]
│   │   ├── Publish and Share (PublishPolicyView, Pollen manifest format) [DOWN]
│   │   └── Links out: Pollen Arena, policy-playground, vetbook  [NEW]
│   ├── Train  (expert)
│   │   ├── Hugging Face training (HubTrainingView, TrainingRequestView) [DOWN]
│   │   ├── Compare (human feedback, RLHF) (CompareViews)        [DOWN; shown even with expert tools off]
│   │   ├── Train a duck to shoot (ShootLabView)                 [DOWN from Studio "Play"]
│   │   ├── Tune (TuneView), Weight search, Move search          [DOWN]
│   │   └── Drivers (phone driver install list)                  [NEW]
│   ├── Measure  (expert)
│   │   ├── Challenges (ChallengeListView, Ball, Stairs)         [DOWN; Behaviours links PolicyListView:453-491 MERGE here]
│   │   ├── Evaluations (EvalListView, EvalSetupView, EvalRunView) [DOWN; same merge]
│   │   ├── Benches and Run on your network (BenchSettingsView, RemoteRunView) [DOWN, the ONE place, was in 3]
│   │   ├── Load a behaviour on a bench (was My Microduck Quick actions) [DOWN]
│   │   ├── Multi-duck (MultiDuckView)                           [DOWN]
│   │   └── Ghost duck (GhostDuckView hub and replays)           [DOWN]
│   ├── Learn: ten lessons (LearnView), deep routes              [DOWN from Learn tab]
│   └── Settings (SettingsView): Appearance, Models (ModelSettingsView,
│       PhoneModelPickerView, endpoints, Dream key), Speech, Feedback, About, Hugging Face  [KEEP, one gear;
│       Dream key field RobotBridgeView.swift:117 MERGES into Models]
│   CUT: Studio's section named "Play", and the Simple "tools" row that went to Learn
│
└── Duck sheet  (from the duck pill on any tab; -tab duck opens Play with this sheet up)
    ├── Your duck: name, live dot, Drive on: Puddle / Practice duck / On your floor (AR)  [MERGE, MyMicroduckView banner + device]
    ├── Camera (DuckCameraCard), address derived from the connection [MERGE; duplicate card in My Microduck CUT]
    ├── Open Pollen's app (health, updates, Wi-Fi)               [NEW]
    ├── Connection: bridge (RobotBridgeView as fallback), Find a duck (FindDuckView) [MERGE]
    ├── Robot details (RobotView, plus the telemetry numbers)    [MERGE]
    ├── Your room: Room capture (RoomCaptureView, iOS)           [DOWN from Studio "Play"]
    ├── Siri and Shortcuts: phrase list, ShortcutsLink, Action button and Controls help [NEW]
    ├── Add your duck (re-enters onboarding page 2)              [NEW]
    └── Expert: Machines, Remote (HF), Diagnostics (PairingSpikeView, transports, Bluetooth card,
        console warning), link to Studio > Measure > Benches    [DOWN]
    CUT: My Microduck as a tab; Quick actions as a front surface; Bluetooth card and console warning on Play (moved to Diagnostics)
```

**iPad.** The same three destinations sit in a sidebar, with the controller as the detail view. In landscape, the Moves shelf docks as a right column beside the picture.

**Mac.**
- The controller is the main window, and Studio opens in a second window.
- Keyboard: WASD or the arrow keys walk, Q and E turn, Space or Escape stops, 1 to 4 trigger the move buttons, and Return opens the mic.
- The Go menu becomes ⌘1 Play, ⌘2 Moves, ⌘3 Studio and ⌘D Duck sheet. This replaces today's ⌘1 to ⌘5.

**Router.** AppTab gets three cases. The raw value `control` stays as an alias of play, and `-tab N` maps by both index and name, so `-tab control` keeps working. AppRouter gains push-capable routes, for example `router.go(to: .studio(.train(.compare)))`. Learn lessons and Retrain then land on the screen itself, not the tab root, which closes the build-41 gap. The old names `learn` and `behaviours` route to their new Studio sections.

**Detail level.** Simple vs Everything stops gating the controller entirely: Pose, Tell, Plan and Scene are part of the toy. It becomes one "Show expert tools" switch, off by default. That switch shows Studio's Train and Measure groups (except Compare) and the Duck sheet's Expert group. Installs that already chose Everything migrate to "on".

**Exit check (build 91):** a StudioKit `ScreenHierarchy` table names each tab's sections in order, and a Linux test pins it to this tree. A second Linux test pins that every row of the feature inventory (including the lens, Imports, head mode and the Dream key) maps to exactly one home in `ScreenHierarchy`, except Bench, whose only home is Measure. A tap-count table, re-measured against the inventory, is checked in with the plan:

| Task | Today | Target |
|---|---|---|
| Drive the real duck | 4+ taps plus typing | 0 taps after onboarding |
| A game | 3 taps | 1 tap (Moves, then tile) |
| Say it on the real duck | impossible | 1 press |
| A skill on the real duck | not offered | 1 tap |
| Walk to the ball, driver already on the device | Auto, then Go (2 taps) | Tell, then Go (2 taps) |
| Fresh install to a standing duck | 5 taps | 4 taps plus the bridge code |

## The three control modes

### Drive (manual)

Your thumbs move the duck. Driving is a continuous `robot.move`, `robot.head` and `robot.pose` stream over the home network (our bridge, or Pollen's WebRTC control datachannel). It never goes through the rendezvous lane, which costs 350 to 510 ms and is rate-capped.

**Walk stick (left thumb).**
- It floats and appears where the thumb lands in the left half of the screen.
- vx and vy come from the stick. Twist comes from a horizontal drag on the right half, or from the stick's outer ring in the pad map's one-stick option.
- It auto-engages, as today (DriveView:852).
- On release it eases to zero. The robot's 500 ms deadman is the backstop.

**Four move buttons (right thumb).**
- 64 pt circles with SF Symbols, never A/B/X/Y.
- Default set:
  - Stand/Sit toggle.
  - Kick: tap for one side, press and hold for the other. On the real duck only kicks that `robot.skills` reports are offered, labelled unverified until a tester passes them (the left kick failed its real-duck test, k002/k002b).
  - Happy, an emotion skill once #384 lands, otherwise wave.
  - Quack (`robot.sound`).
- Remap any button from Moves with "Put on a button". The on-screen buttons and a physical pad share one DuckPadMap.
- A refusal shows as a one-line chip in kit words, for example "Sitting ducks can only stand up."

**Head.** A two-finger drag on the picture aims the head (`robot.head` / `robot.look`). A double-tap means "look here". This replaces today's Robot head mode.

**Pose.**
- On the Practice duck, the Pose button opens JointHandleOverlay, and the pose bar replaces the move buttons.
- On the real duck, press and hold, then tilt the phone to lean the body. This sends `robot.pose` z/roll/pitch, clamped in the kit (build 94).

**Physical pads.**
- PadReader and GamepadInput stay as they are, and on-screen glyphs switch to the connected pad's own symbols.
- The pad's Select stays Pollen's rest and power button.
- Pad input in Tell or Auto cancels whatever is running, then drives.

**Haptics.** Core Haptics patterns are defined as data in StudioKit:
- a soft tick at gait cadence;
- a thud on a kick;
- a firm double tap on a refusal;
- a long buzz on Stop.

Pad rumble mirrors them. DuckSoccerView's direct generator calls fold into `Haptic`.

### Tell (semi-manual)

One press or one sentence runs a whole move or a short chain. The stick stays live, so you can always nudge or take over.

**Layout.** The mic grows into the primary button: 76 pt, push and hold. Above it sits a strip of tiles: recent and favourite skills, sounds, sequences, plans and cards. The keyboard glyph on the mic opens today's TalkToTheDuckView field, which now works on every venue.

**Voice path, in order.**
1. Mic press starts SpeechAnalyzer, falling back to DictationTranscriber on older devices. `contextualStrings` carries the skill names, "Microduck", the duck's name, "kick", "quack" and "roulade". In parallel, Foundation Models `prewarm(promptPrefix:)` runs.
2. Every volatile result goes to the kit's `StopWords`. "Stop", "freeze" or "no" fires StopPath immediately, before the final transcript. This is keyword matching on speech-recognizer output. No language model is involved.
3. On release, the final text goes to `DuckTalk.read` (the existing deterministic parser) and the new `DuckCommandMatcher` (skills, sounds, look, sit/stand). If the reading is "understood", it runs with no model involved.
4. Only compound or unparsed sentences go to on-device Foundation Models: a `@Generable DuckPlanDraft` (at most 6 steps, short `@Guide` notes) with Tools wrapping kit actions (doSkill, walk(direction, seconds at most 5), sound, look, wait). The output is a SequenceProposal.
5. A single understood command runs at once with a one-line caption. A model-built plan shows as a preview strip of tiles with a 1.5 s "Running in..." countdown and Cancel, and it never runs without that beat. Settings has "Run model plans without asking", off by default.
6. If neither the parser nor the model understands, the kit's "I heard: ..." sentence offers the three closest tiles. If the model is unavailable, the caption reads "Short commands only on this phone."

**Other inputs.**
- Tiles from the strip or the pull-up Moves sheet.
- Record (in the "more" sheet: the next 20 s of stick and buttons becomes a sequence tile).
- "Watch for cards": Duck Cards seen by the camera light up a tile, and the move runs. No typed address.
- Plans from the Plan editor.

**The robot's rules.** Every chain respects them, and the kit enforces them:
- One move at a time. The kit waits for each to end.
- A sitting duck accepts only stand, so the kit inserts a visible "Stand up" step.
- `robot.init` and `robot.enable {on: true}` come before `robot.do`. A bare enable is refused.
- `robot.do` is refused unless the policy is driving, so the kit starts driving before any skill.
- `robot.stop` does not cancel a running skill. Stop blocks every queued step at once, and a started skill runs to its end with the caption "Stopping after this move."
- Refusals are the robot's named reasons, translated.
- "Duck talks back" (AVSpeechSynthesizer) is off by default.

### Auto (autonomous)

The duck pursues a goal and you supervise. Choosing Auto shows a carousel of goal cards over the picture, collapsed to one row.

**Goal cards.**
1. **Dream-1 (your key)**, on the Practice duck and the real duck. The prompt field is on the card, and the key lives in Studio > Settings > Models.
2. **Later:** Follow me, Explore the room, and the brains layer (hosted VLAs, MCP).

**Walk to the ball is not here since build 95.** The owner, after trying build 94: "that seems more like a semi-auto/manual step - not a real auto/autonomous type of interaction with the duck." It is a tile in Tell, on both ducks. See "Walk to the ball on a real duck (build 95)".

Each card has a provenance line ("Runs on this iPhone", "Hosted by Dream Labs, your key") and is marked as not Pollen's.

**Running a goal.**
- Press Go. A thin progress ring wraps the duck pill, with a caption such as "Driving: walk to the ball · 4.2 s".
- Stop stays top right, and a second Stop appears in the right-thumb zone.
- The run ends with a summary chip: reached or not, time, and act p50/p95 behind "details".
- DreamPilot's clamping, easing, warm-up waits and stop-then-end are unchanged.

**Takeover rules.** These live in a new deterministic, Linux-tested `ControlArbiter` in StudioKit.
- Any of these ends the goal: a stick touch, pad input, a move-button press, Stop, a heard "stop", a lost connection, the Live Activity Stop, or the app leaving the foreground (see Rules across all modes).
- Hand-back is **stop only**: the pilot is cancelled, the move is zeroed and `robot.stop` is sent. It never sends an automatic stand or any other motion after Stop.
- The switch snaps to Drive with the caption "You took over."
- Autonomy never re-arms itself.
- Default run caps: 30 s on the real duck, 60 s on the Practice duck. They can be extended in Studio.
- Auto never trains. Training stays in Studio and on Hugging Face Jobs.

### Rules across all modes

**Stop is always reachable.**
- Play always shows the solid red Stop disc.
- While a move, chain, plan or goal runs on any duck, a floating red Stop pill shows on Moves, on Studio and on top of every sheet (Duck sheet, More, Plan editor, pull-up Moves sheet, Tell preview), so no sheet ever covers the only Stop. This is the review's required fix 1, extended to sheets.
- Tiles in the Moves tab and the pull-up Moves sheet run on the current duck. The pull-up sheet is the main path, so most runs happen with the picture in view.

**StopPath is one static, idempotent sequence:** block queued steps, cancel the pilot, zero the move, send `robot.stop`. Every entry point calls it:
- the red disc and the Stop pill;
- magic tap;
- Space or Escape on the Mac;
- the pad's B-hold;
- a heard "stop";
- Siri, the Control, the Lock Screen, the Live Activity and the Action button.

It has no await on a model or the UI. It cannot cancel a skill the robot has already started (see the robot's rules), and no surface may describe it as cancelling one. The question of a cancel call goes to Pollen.

**Leaving the foreground.** When the app moves to the background, StopPath runs for every chain, plan and goal. The Practice duck's simulation cannot run while the app is suspended, and a real-duck connection is not kept alive in the background. The only exception is a run started by an intent that holds a Live Activity, which keeps running while the app process runs and ends with StopPath as soon as the connection drops. Stick streams stop with the app, and the robot's 500 ms deadman is the backstop.

**The venue switch is explicit and input-safe** (required fix 2).
- The venue changes only on an explicit connect action: onboarding, or "Drive on: Puddle" in the Duck sheet. Reconnecting in the background never moves the venue. Opening a game from Moves never moves it either.
- On a switch, the stick zeroes and ignores input until the finger lifts.
- A chip reads "Now driving Puddle."

**Mode switching.**
- The top switch has a haptic detent.
- Touching the stick in Auto takes over a running goal and drops to Drive. With nothing running it does nothing and says "The sticks rest in Auto. Tap Drive to steer." (build 93: a resting game controller used to flip the switch).
- Holding the mic in Drive does a one-shot Tell without switching.
- Saying "go get the ball" in Tell offers the Auto goal card.
- The switch position is remembered per duck.

## Voice and system surfaces

**One kit layer under everything.** `StudioKit/DuckCommand.swift` is new and Linux-tested. It defines:

```
enum DuckCommand { stop, stand, sit, walk(direction, seconds), skill(name), sound(name), look(target), goal(name), runMine(id) }
```

- Each case has a pure mapping to DuckMethod calls and their prerequisites (`robot.init`, `robot.enable {on: true}`, start driving before `robot.do`).
- App Intents, buttons, Speech and Foundation Models tools all produce a DuckCommand.
- Nothing else talks to the transport, which keeps `check_no_studio_math.sh` green.
- The intent structs live in the app target. Their `perform` bodies are a single call into the kit.

**Execution.**
- Every motion intent should run in the main app, because the bridge connection and the simulated duck live there.
  - On iOS 27 this uses `executionTargets` (API name unverified).
  - On iOS 26, App Shortcuts and Siri intents compiled into the app target run in the app process, launched in the background if needed.
  - A Control's intent is **not** guaranteed to run in the app process on iOS 26. Build 92's first spike decides it.
- The Live Activity Stop button uses `StopDuckIntent` conforming to `LiveActivityIntent`, which runs in the app's process. If the app was terminated, that means a cold reconnect.
- Background intents reconnect in at most 3 s. If they cannot, they answer "Open Duck Studio to reconnect" instead of burning the 30 s budget.
- `.localNetworkDenied` maps to "Open Duck Studio once to allow the network."
- Any extension that touches the duck reads DuckConnection through the App Group and the shared keychain access group. Whether the app's Local Network permission covers the extension process is unverified, and the spike tests it.

**Locked phone.** Intents that start motion use `authenticationPolicy = .requiresAuthentication` when the phone is locked. Stop, Sit, rest and sound do not.

**Latency budgets.** These are targets, measured from the system handing us the intent to the robot call leaving the phone, with the connection already alive. A cold reconnect, including any relaunch of a terminated app, adds up to 3 s and is shown honestly. Siri's own speech recognition time is outside these budgets and is never quoted as ours.

The ten App Shortcuts are the cap. Each phrase contains `${applicationName}`, and `INAlternativeAppNames` adds "Duck Studio" (unverified, to be checked on a device in build 92).

| # | Intent | Phrases | Parameters | Calls | Modes | Budget |
|---|---|---|---|---|---|---|
| 1 | StopDuckIntent (also a LiveActivityIntent) | "Stop the duck in ${applicationName}", "${applicationName}, stop" (test on device: Siri's own "stop" may take it), "Freeze the duck in ${applicationName}" | none | StopPath (block queue, pilot cancel, zero move, `robot.stop`; a started skill finishes) | `[.background]`, no auth | under 100 ms warm |
| 2 | StandUpIntent | "Stand the duck up in ${applicationName}", "Wake up the duck in ${applicationName}" | none | `robot.init`, `robot.enable {on: true}`, start driving, `robot.do stand` | `[.background, .foreground(.dynamic)]`, auth when locked | under 300 ms to first call |
| 3 | SitDownIntent | "Sit the duck down in ${applicationName}" | none | prerequisites, then `robot.do` sit | same, no auth | under 300 ms |
| 4 | DoMoveIntent | "Make the duck ${move} in ${applicationName}", "${applicationName}, ${move}" | move: DuckMove AppEnum (kick left, kick right, roulade, pick up, happy, sad, dance) plus DuckMoveEntity from `robot.skills`, refreshed by `updateAppShortcutParameters()` after each connect | prerequisites, then `robot.do` | `[.background, .foreground(.dynamic)]`, auth when locked | under 300 ms |
| 5 | WalkIntent | "Walk the duck ${direction} in ${applicationName}" | direction: AppEnum (forward, back, left, right, turn left, turn right); duration: Duration, default 1 s, kit-clamped to at most 5 s | streamed `robot.move`, then zero; if the app is suspended mid-walk the deadman stops it within 500 ms | `[.background, .foreground(.dynamic)]`, auth when locked | under 300 ms to first move |
| 6 | WalkToBallIntent | "Send the duck to the ball in ${applicationName}", "Go get the ball in ${applicationName}" | none | phone driver via DreamPilot; progress each pilot ask; onCancel goes to StopPath; ends with StopPath if the app leaves the foreground (the simulation cannot run suspended) | `.foreground(.immediate)` while the driver is Practice-duck only. iOS 27: LongRunningIntent with a system Live Activity (unverified). iOS 26: LiveActivityIntent plus our ActivityKit card | app open under 1 s; answers "Running on the practice duck" |
| 7 | PlaySoundIntent | "Make the duck ${sound} in ${applicationName}", "Quack in ${applicationName}" | sound: AppEnum from the robot's sound list, default quack | `robot.sound` | `[.background]`, no auth | under 300 ms |
| 8 | LookAtMeIntent | "Make the duck look at me in ${applicationName}" | none | v1 `robot.look` at a fixed point ahead at adult face height (copy says "looks up and ahead"); v2 a face from the duck camera | `[.background]` v1; `.foreground(.immediate)` v2 | under 300 ms |
| 9 | TellTheDuckIntent | "Tell the duck in ${applicationName}" (Siri asks "What should it do?") | sentence: String | DuckTalk and DuckCommandMatcher only in the background. If the model is needed, it asks to continue in the foreground and shows the preview strip there | `[.background, .foreground(.dynamic)]` | fast path under 400 ms; model path under 3 s to preview |
| 10 | OpenControllerIntent | "Drive the duck with ${applicationName}" | mode: Drive, Tell, Auto | opens Play in that mode | `.foreground(.immediate)` | app open under 1 s |

Shortcuts-only, with no phrase:
- RunMyMoveIntent(MyMoveEntity) for saved sequences and plans.
- RestDuckIntent, which sends `robot.rest`, never `robot.relax` (that collapses the duck).

**Other surfaces.**
- **Controls** (Control Center, Lock Screen, Action button; a ControlWidget in a widget extension). Which process runs their intents on iOS 26 is decided by the build-92 spike.
  - Stop duck: ControlWidgetButton, with `controlWidgetActionHint` "Stop the duck". The person chooses it for the Action button in Settings. The app can suggest that but cannot set it.
  - Duck awake: ControlWidgetToggle. On sends the stand chain; off sends `robot.rest`. It uses an awake/asleep symbol pair, animated while the call is in flight. Its displayed state is the last known state from the App Group, never a live claim.
  - Walk to the ball: ControlWidgetButton (opens the app).
- **Live Activity.** One design covers goals, sequences, plans and timed walks.
  - Compact: duck glyph and time, inside the 28 pt circle.
  - Expanded: for example "Walking to the ball · 4.2 s · Stop" or "Step 2 of 4". Stop is a `Button(intent: StopDuckIntent())`, which runs in the app's process.
  - Updates come from the app, because the activity cannot reach the network. It ends within a minute of the run, and at once when the run ends by StopPath.
- **SnippetIntent mini remote** in Siri and Spotlight: Stand, Sit, Quack and Stop, re-rendered after each tap.
- **Discovery and suggestions.**
  - DuckMoveEntity is an IndexedEntity, so typing "kick" in Spotlight shows the move, and a tap runs it, subject to the locked-phone auth rule.
  - IntentDonationManager donates every move run by hand.
  - RelevantEntities (iOS 27, unverified) surfaces favourites.
  - `.appEntityIdentifier` on Moves tiles lets "do that one" resolve.
- **In-app hints.** A SiriTipView appears once on the controller. ShortcutsLink sits in the Duck sheet > Siri and Shortcuts and in tile long-press "Add to Siri".
- **Widgets** (build 95+): status as "Last answered 12:04" and the current activity, with no battery (`DuckBattery.noneToRead`, no transport carries it). A medium widget adds four move buttons, and a Lock Screen accessory gives Stop.
- **Apple Watch** (later): the same Controls on watchOS 26, the Live Activity mirrored in the Smart Stack, and the Ultra Action button set to Stop by the wearer. A wrist remote waits until its latency is measured.

## Where on-device intelligence is used and where it is forbidden

**Used** (always gated on `SystemLanguageModel.availability`; when it is not available, only the deterministic path runs and the mic still works):
- Tell: compound or unparsed sentences become a SequenceProposal through Tools that wrap kit actions. It is shown as a preview strip with a countdown.
- Draft with words and Plan authoring (AutomationChatView, DraftEngine), as today.
- Suggesting a name for a recorded sequence.
- Moves search ("something happy").
- Tell reads "walk to the ball", "go get the ball" and a few like them with no model (`BallWalk.heard`), after every stop word, and starts the Walk to the ball card with its own refusals. Ask the duck and Siri do not start it.
- Summarising a run's result in plain words.
- Siri AI conversation reaching our App Intents and entities. That is the system's model, not ours.
- The MLX PhoneModelRuntime can be chosen as an alternative planner in Settings > Models, through the iOS 27 LanguageModel protocol (unverified).

**Forbidden:**
- Stop in any form: button, voice (caught by keyword on volatile results), Siri, Control, Island, pad.
- The stick, the move buttons, the pad, head and pose streams.
- Any per-tick control. The phone driver is ducknet-s1 on Accelerate, not a language model, and DreamPilot owns the timing.
- Background Siri, Control and widget intents. On battery, background work is rate-limited (`GenerationError.rateLimited`), and inside extensions that limit can surface disguised as a guardrail error.
- Single words or commands the parser already understands. That is the latency win.
- Safety decisions: clamps, speed and duration limits, refusals, run caps, control priority, and the real-vs-simulated choice. All of these are kit arithmetic.
- Running a model-built plan without the visible countdown and Cancel.
- Mimic, or any training, on a phone.

Before relying on the model at all, test "kick", "shoot" and "attack" against the guardrails on a device, through XCTest calling `perform()` (and AppIntentsTesting if that framework exists; unverified).

## Visual language

**Content first, glass floating over it.**
- The live duck (camera, stage or AR) is always edge to edge, and it is the only large surface.
- Chrome is Liquid Glass (`glassEffect`, `GlassEffectContainer`) in small clusters at the corners and the bottom edge.
- No card covers more than a quarter of the picture.
- Every overlay on the live picture ships collapsed at 60 pt or less, with its expanded state remembered in `@AppStorage` (the stage-overlay lesson).

**Legibility.** iOS 27 adds a user transparency slider, so legibility cannot come from the glass tint:
- Text on the stage sits on a scrim gradient.
- A StudioKit token check enforces 4.5:1 contrast.
- Stop is a **solid** red disc, not glass.

**Colour carries meaning.**
- One duck-yellow accent means "the duck is moving or running a goal": the active stick ring, the progress ring and the running tile.
- Red is Stop and nothing else.
- The modes use symbols, not colour: `gamecontroller.fill` for Drive, `waveform` for Tell, `sparkles` for Auto.
- The live dot (which replaces the toolbar lens) is green when the last request was answered, amber while waiting and grey when offline. It means "the last thing we asked was answered", never a heartbeat claim. A Stop counts as a request.

**Shape and type.**
- Toy-like rounded shapes: 64 pt move buttons with pressed depth and a haptic, a 76 pt mic, and a 120 pt translucent stick base.
- Frequent targets are at least 44 pt and secondary ones at least 28 pt, clear of the Dynamic Island and the Home indicator.
- SF Pro Rounded for the duck's name, mode labels and captions; SF Pro for body text.
- Dynamic Type grows chips, not the stick.

**Orientation.** On iPhone the primary layout is landscape, thumbs at the bottom corners and the picture between them. Portrait puts the picture on top (about 60%) and the controls below.

**Practice duck vs real duck.**
- The Practice duck has its pill and a subtle checkerboard floor.
- The real duck shows its camera and its name.
- Before a picture arrives, a calm illustrated poster shows the duck's state sentence, never an empty list.

**Motion.**
- The mode switch moves with springs.
- Refusal chips slide out of the duck pill.
- Stop gives a hard flash of at most 150 ms (reduced under Reduce Motion) plus a buzz.

**Copy.**
- Short, warm, second person.
- No engineering words on the front door: MuJoCo, robot.move, deadman, bench, policy, intent, repo. Those live in Duck sheet > Expert > Diagnostics.
- "Motions" is the authoring word, "Moves" is the toy box, and "Play" names exactly one tab.
- "RLHF" appears only beside "human feedback".
- No em-dashes anywhere. A kit test fails if any user-facing table contains U+2014. The sweep covers the 24+ strings in DriveVenue, FirstRun and the *Words files.
- No surface says Stop is instant for a skill, or that voice Stop is instant, unless measured numbers support it. A kit test pins the Stop captions.
- Every SwiftUI string either goes through LocalizedStringKey or is explicitly verbatim.

**Accessibility.**
- Magic tap is Stop.
- Every symbol button has a VoiceOver label.
- The mic works fully without vision.
- Mac and iPad have full keyboard control.

**Studio may look like Settings,** an inset-grouped List, because it is the lab.

## How build 90's phone driver fits

Build 90 stays exactly as `docs/plans/build-90-phone-driver.md` describes it:
- The phone driver runs "walk to the ball" on the Practice duck (ducknet-s1 via LocalDreamRows into DreamPilot).
- It is gated on M1: at least 6/10 reaches and infer p50 under 20 ms.
- If M1 misses, build 90 waits.
- This redesign adds no app work and no upload to build 90.

**In build 90.** The phone driver appears where the build-90 plan puts it, in the Dream sheet. DreamSourceChoice already lists phone drivers first.

**Kit-only groundwork alongside build 90** (Linux tests, no upload):
- `DuckCommand`, `StopPath`, `StopWords`, `DuckCommandMatcher`, `ControlArbiter` (stop-only hand-back, run caps, no re-arming, background ends runs).
- `DuckConnection` (one address feeds the camera; keychain access group and App Group layout).
- `Onboarding` sentences.
- `ScreenHierarchy`.
- The em-dash sweep with its pinning test.

**In build 91.** The Dream sheet becomes the Auto goal card "Walk to the ball, on this phone", badged Practice duck only. On the real duck the card is disabled with "This driver was trained on the simulated duck."

**In build 92.** WalkToBallIntent and the Walk to the ball Control expose the same driver. Until a real-duck gate passes, they answer "Running on the practice duck". (Neither has been built. Build 95 did not add them.)

**If M1 never passes.** Auto ships in 91 with Dream-1 only (key required), and the Walk to the ball card, intent and Control are hidden.

**On the real duck.** This plan held the phone driver back for a separate real-duck gate. The owner replaced that on 2026-11-05 after trying build 94: "walk to the ball should stay on the real duck." Build 95 turns it on, with no gate passed. See below.

### Walk to the ball on a real duck (build 95)

**It has never run on a real duck, and the driver learned only on the drawn stage.** Everything below is reasoned from Pollen's sources and tested on Linux and in the compile gate, not on a floor.

- **Where.** A card in Tell (`WalkBallCard`, the kit's `DriverCard`): Get, progress, Cancel, Go, Delete. Saying or typing it in Tell starts it too. While it runs, Tell shows the same status line and Take over as Auto, and the arbiter books it as `.walk`: capped like a goal, a stick takes over, and the switch stays on Tell.
- **Pictures.** `DuckCameraFeed`, mediad `/frame`. While the driver steers, stills are asked for every `DriverTrial.cameraPeriod` (0.2 s, not 0.25), so its two pictures are the 0.4 s apart it learned. Seven pictures must arrive within 3 s or it refuses in words.
- **The cameras differ.** The driver learned on a landscape picture, 320 by 176, 45 degrees tall and about 74 wide. An alpha duck's upright `/frame` is portrait, 720 by 1280, about 37 degrees wide and 62 tall, with its optical axis off centre. Dream-1's framing squashes that into 320 by 176, which makes a ball about three times wider than tall, so the driver does not use it. `BallWalk.Framing` keeps the drawn stage's scale (a degree covers the same pixels), centres on the real axis and crops top and bottom. The real view fills about 144 of the 320 pixels, and the rest is the driver's mean colour. The driver has never seen those side bars, and a ball outside that narrow view is not seen at all.
- **Stale pictures.** `DreamPilot` takes an optional `watch`, asked before every ask and every row. A real run stops when no picture has come for 1 s. Without it, a pilot would play a chunk of up to 2 s from an old picture, and would keep asking from the last window for ever.
- **Ready.** `robot.policies` says only sitting and homed. Sitting or homing is told what to do. Anything else gets `robot.init` and `robot.enable`, as a Tell walk does, and the settle. No bench call goes to a real duck.
- **Ending.** No ground truth, so `BallWalk.Watch` ends a run on 2 s of still rows from the driver, or `Caps.standard` ends it at 30 s. The line says it stopped by itself or hit the limit, and never that it reached the ball.
- **Safety.** One Stop, the pill and `DuckRuns`, the real cap, the foreground rule, `makeWay` and `stepAside`, as Dream-1. The first run on each driver asks first, in a dialog with no destructive role, because that draws red.
- **iOS 18.** Only the practice camera needs it. A real run draws nothing, so it needs only the app's iOS 17.
- **Practice duck.** Unchanged: the same `walkToBall`, so the M1 numbers stand. Only the run's booking changed.

**Next, with a duck.** A person on a floor with the duck tethered or spotted: first whether side bars or a plain crop steer better, then whether 2 s of still rows ever means anything on a real floor.

## Phased builds

Every phase is one TestFlight upload. Before each real archive, ask "what else is queued for this app?". Checks run in three places:

- **Linux** means StudioKit tests, run off this Pi, never on it.
- **Mac gate** means `xcodebuild archive ... CODE_SIGNING_ALLOWED=NO` for iOS plus the `--platform macos` gate. Watch for the stale-tail and keychain traps.
- **Device** means a tester's iPhone, with a real duck where the check says so.

Every phase's acceptance includes a **structure** check, not only tokens (the build-40 lesson). No phase uploads without one.

### Build 90: phone driver (already planned, not grown)
- Scope: the build-90 plan only. Ships only if M1 passes.
- In parallel, kit-only: the groundwork listed above.
- Acceptance:
  - Linux: tests for:
    - DuckCommand mapping and prerequisites, including enable `{on: true}` and driving before `robot.do`;
    - StopPath idempotence (called twice equals called once; no model dependency in its imports; queued steps blocked);
    - StopWords firing on a volatile partial;
    - ControlArbiter (stick touch cancels a goal; hand-back emits no motion after stop; caps of 30 s real and 60 s practice; no re-arm; background ends runs);
    - the U+2014 test over all user-facing tables.
  - Device: M1 as defined in the build-90 plan.
  - Structure: a screenshot of the Dream sheet shows the phone driver listed first, where the build-90 plan puts it, with no other screen changed. The first `ScreenHierarchy` draft records today's tree as the baseline that build 91 diffs against.

### Build 91: the controller is the app (structure first, then tokens)
- Marketing version bump at this build (see the open questions). A new version train also gives a fresh upload budget.
- Scope:
  - ControllerView on every venue, including the real duck's full-bleed camera. The Robot venue List is deleted.
  - Drive | Tell | Auto switch. Auto hosts the build-90 driver card and Dream-1. Tell is typed-only for now, on every venue, plus tiles, Plan and Watch for cards.
  - Stop: the solid red disc always on Play, the second Stop while Auto runs, and the floating Stop pill on every tab and every sheet while anything runs. Takeover cancels goals. Backgrounding ends runs.
  - Three tabs, the Duck sheet (with the lens merged into the live dot), the pull-up Moves sheet, and Studio as the hub with the "Show expert tools" row.
  - Imports land in Moves or Studio > Make.
  - The welcome flow: the Local Network prompt in the foreground, discovery by BLE, Bonjour or typed address (QR if it is ready), Say hi, and Stand up. The venue switches only on an explicit connect and is input-safe. One address feeds the camera.
  - Router: push routes, the `-tab control` alias, and mapping by index and name.
- Acceptance:
  - Linux:
    - The `ScreenHierarchy` test matches the tree above.
    - The inventory-coverage test passes: every inventory row has exactly one home.
    - The checked-in tap-count table shows the targets.
    - LabCatalogueTests, UXSurfaceTests and the `-tab` contract are updated, and the alias test passes.
    - The venue-switch rule test passes (input is ignored until the finger lifts).
  - Mac gate:
    - The iOS and macOS archives compile, and the no-studio-math gate is green.
    - A grep of `DuckStudio/Sources` only (never `.claude/worktrees`) finds no `venue = .real` outside the explicit connect path, and no view that runs a move without the Stop pill condition.
    - Every sheet presented from Play, Moves or Studio carries the Stop pill modifier.
  - Device, structure:
    - A structure lens walks the live screen tree against this document.
    - Screenshots of all three tabs, the Duck sheet and each Play sheet during a run confirm placement and the visible Stop.
    - An occlusion check rates as HIGH any overlay above a quarter of the picture, or above 60 pt collapsed.
  - Device, real duck (tester):
    - A fresh install stands the duck in at most 4 taps with zero typing.
    - Starting a move from Moves shows the Stop pill, and the pill stops it (a started skill finishes with "Stopping after this move").

### Build 92: native front door
- **First, before anything else** (required fix 3), spike the background Stop path. Test the Stop Control, StopDuckIntent from Siri and the Live Activity Stop on iOS 26 and iOS 27, with the app suspended and with the app terminated. Record:
  - which process runs `perform`;
  - whether the extension process has Local Network access under the app's permission;
  - the time to reconnect;
  - the press-to-`robot.stop` time;
  - whether "${applicationName}, stop" reaches our intent or Siri's own stop.
- If the extension cannot reach the duck, the design changes before the other nine shortcuts are built. Either the extension opens its own short connection using the App Group and keychain group, or Stop from the Lock Screen falls back to an honest "Open Duck Studio" plus the robot's deadman.
- Then:
  - the ten App Shortcuts, RunMyMove and RestDuck;
  - the three Controls and the SnippetIntent remote;
  - the Live Activity (LongRunningIntent on 27 if it exists, LiveActivityIntent on 26);
  - SiriTipView, ShortcutsLink, donations and IndexedEntity;
  - `INAlternativeAppNames`.
- **Widget extension work** (required fix 4):
  - a new target and bundle id, and a provisioning profile minted through the ASC API (the HeatCompass signing-split lesson);
  - the iOS entitlements file, including the App Group and the keychain access group for both the app and the extension;
  - `NSLocalNetworkUsageDescription` and `NSBonjourServices` reviewed in the app's Info.plist;
  - `CFBundleIconName` and the extension plist checked at a real **signed** archive before the upload slot (icon and plist failures show up only at upload).
- Acceptance:
  - Linux: each intent's kit mapping is tested. Background-mode intents import no model code.
  - Mac gate: the app and the extension compile for iOS and macOS.
  - Device:
    - XCTest calling `perform()` on each intent (AppIntentsTesting if it exists; unverified).
    - Stop from the Island, the Control and a stick touch each end a Practice-duck run within one frame.
    - A tester verifies Stop from the Lock Screen on a real duck, and the spike's numbers are written into this document.
    - "Duck Studio" is verified as a spoken name.
  - Structure:
    - The Duck sheet's Siri and Shortcuts section lists exactly the shipped phrases.
    - The Controls gallery shows exactly the three Controls.
    - The Live Activity compact and expanded layouts are screenshotted against this document.
    - `ScreenHierarchy` gains the system surfaces.

### Build 93: voice
- Scope:
  - the push-to-talk mic with SpeechAnalyzer volatile results into StopWords, then the DuckTalk and matcher fast path, then Foundation Models tools with prewarm and the countdown preview;
  - the speech model pre-downloaded during onboarding;
  - the "Short commands only on this phone" fallback;
  - the guardrail pass on kick, shoot and attack.
- Acceptance:
  - Linux: matcher coverage tests and the plan validator's limits (at most 6 steps, walk at most 5 s).
  - Device: press-to-motion latency for "stop", "sit" and a compound sentence, for both transcribers, with the numbers written into this document. Copy never says voice Stop is instant unless the numbers support it.
  - Structure:
    - The mic sits bottom-right as the primary button in Tell and as a one-shot in Drive.
    - The preview strip sits directly above it, under the quarter-picture cap, with the Stop disc uncovered.
    - Settings > Speech exists.
    - `ScreenHierarchy` is updated and screenshots are taken in both orientations.

### Build 94: real-duck feel
- Scope:
  - No-typing connect: a BLE address read if Pollen confirms the calls are routed over BLE, otherwise a QR code from the bridge.
  - WebRTC video in place of the roughly 4 fps `/frame` poll, once DuckWebRTC's open items are closed.
  - Emotion tiles (#384) and tilt-to-lean `robot.pose`.
  - The Core Haptics set and pad rumble.
  - The iPad docked Moves column and the Mac keyboard map.
- Acceptance:
  - Linux: haptic pattern data tests and pose clamp tests.
  - Device: a tester measures picture latency, and the camera chip states it honestly.
  - Structure:
    - The iPad landscape docked column and the Mac main window plus Studio window match `ScreenHierarchy`, with screenshots.
    - The Mac keyboard map is listed in the Pad map screen.
    - Onboarding page 3's discovery order matches what shipped (QR or BLE).

### Build 95 and later
- Learn rewritten around the controller.
- Widgets and the Watch.
- The brains layer as more Auto cards.
- LookAtMe v2.
- Games wired to a bridge (Fetch and Soccer first).
- A measured real-duck gate for the phone driver (on since build 95, ungated, by the owner's call).
- Acceptance for each item: its `ScreenHierarchy` row and a screenshot are checked in before the upload, alongside its Linux and device checks.

## Risks

1. **Nobody on the team has a real duck yet.** Every real-duck claim in builds 91 to 94 needs a tester's verification or an "unverified" label.
2. **The real-duck picture is a roughly 4 fps PNG poll.** A laggy picture feels worse than the sim. Lead with buttons that do not need the picture, and show latency honestly until WebRTC lands.
3. **No-typing connect is not proven.** BLE cannot carry driving, and reading the home address over BLE is unverified. QR or typing may remain.
4. **Local network permission is silently denied in the background** if it was never answered in the foreground. Onboarding must trigger it, and intents must fail fast with a clear sentence. Coverage for the extension process is unverified.
5. **The background Stop path is unproven.** That covers suspended sockets, cold relaunch after termination, the 30 s budget and which process runs a Control's intent on iOS 26. The build-92 spike decides it. Do not claim instant Stop from Siri, a Control or the Lock Screen until it is measured.
6. **`robot.stop` does not cancel a running skill** (duck-sim robotd 0.15.1). Stop blocks queued steps and zeroes walking, but a started kick or roulade finishes. Ask Pollen for a cancel call. Until then, keep skill copy honest.
7. **Control priority is unsolved on the robot: last writer wins.** ControlArbiter enforces "your thumbs win" only inside Studio. A pad paired directly to the robot, Pollen's app or a remote peer can still fight a Studio goal. Show "Your controller took over" where `robot.subscribe` reveals it.
8. **Nothing authenticates the caller to the robot.** Motion intents require an unlock when the phone is locked. Only Stop, Sit, rest and sound are exempt.
9. **Siri AI is limited at launch:** English only, not in the EU or China, iPhone 15 Pro or later, and still labelled beta. There is no robot schema domain. Phrases must work as plain App Shortcuts, and the deterministic path must be complete on its own.
10. **Foundation Models can feel flaky:** background rate limits, guardrail false positives on kick and shoot, and no published latency. Keep the model off single commands.
11. **Speech latency for short commands is unmeasured,** and SpeechTranscriber is tuned for long-form audio. The Stop button, the Control and the pad remain the primary Stop.
12. **The phone driver is on the real duck with no real-duck measurement** (the owner's call, build 95). It learned only on the drawn stage, and the real camera is a different shape. The first-run dialog, the 30 s cap and the stop on stale pictures are what stands between that and a table edge.
13. **The 10-shortcut cap and the long app name** make phrases clumsy. INAlternativeAppNames is unverified, and "${applicationName}, stop" may collide with Siri's own stop.
14. **The restructure breaks pinned contracts:** LabCatalogueTests, UXSurfaceTests, the `-tab N` contract, the NSCameraUsageDescription wording, README "five tabs", ASC-only App Store copy, the shared EndpointStore (the build-41 duplicate-store bug) and lastLoadedPolicy semantics.
15. **Repeating build 40: new tokens without new structure.** The ScreenHierarchy test, the inventory-coverage test, the tap-count table and the structure lens are the guard.
16. **The widget extension adds a target, a bundle id, a profile, an App Group, a keychain group and an upload-only failure class.** It is planned into build 92 with a signed-archive check.
17. **Overlap with Pollen.** Pollen will improve its drive screen, may add cloud voice, and will likely own pad binding. Keep the "not official" line, link out for setup and health, gate features on `system.info`, and never drive over the rendezvous lane.
18. **Word collisions.** "Intent" means three things across the projects, and "Play" names two tabs today. The UI says Motions, Moves and Play exactly once each.
19. **TouchController is meant for Metal games** and may not fit the SwiftUI/RealityKit stage, so the floating stick may stay custom.
20. **Several iOS 27 API names are unverified** (`executionTargets`, LongRunningIntent, RelevantEntities, the LanguageModel protocol, AppIntentsTesting). Each has an iOS 26 fallback in this plan.
21. **Process limits.** One upload per session. The Pi cannot build or test (it reboots under load). The Mac compile gate has known traps. Plan Mac time for every phase.

## Open questions for the owner

1. **Version bump.** Bump the marketing version at build 91 (the structure release, for example to 2.0) as a feature release with a fresh train, or at 92 (Siri)?
2. **Mimic on iPad.** Is Mimic allowed on iPad, or Mac only as written? The rule says "never on a phone", and this plan takes the stricter reading.
3. **Moves tab on the real duck.** A tap runs on the real duck with the floating Stop pill (as written). Or should a tap on the real duck first switch to Play and then run?
4. **Learn as a tab.** Folding Learn into Studio removes a tab that new users see today. Is that acceptable, given coach marks and the welcome flow replace its onboarding job?
5. **Expert tools default.** Should "Show expert tools" default to off for new installs, with Everything installs migrating to on? Compare stays visible either way.
6. **Asking Pollen.** Do we ask Pierre:
   - which `system.info` and `net.*` calls are routed over BLE (for no-typing connect);
   - whether M6 control priority has a date;
   - whether a call that cancels a running skill exists or is planned?

   The answers change builds 94, 92 and the Stop copy.
7. **Dream-1 on the real duck in 91.** Allowed with the 30 s cap, or Practice duck only until a tester has run it?
8. **The default four move buttons.** Stand/Sit, Kick (only robot-reported kicks, unverified on the real duck), Happy and Quack as written, or something else?
9. **Spoken app name.** "Duck Studio", or something shorter, as the alternate name?
10. **Watch timing.** Should the Watch Controls and Ultra Action button Stop move up from 95+ to ride with build 92's Controls?