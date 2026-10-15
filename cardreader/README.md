# cardreader: the duck reads Duck Cards

Show a Microduck a Duck Card and it does what the card says. Show it a row, Start to End, and it
reads the row and runs it, turning its head along a row too long for one look. This is the reader
for the robot itself; StudioKit's `DuckCards` is the same reader for Studio reading the duck's
camera. One deck, one set of answers, two readers.

```sh
pip install -r cardreader/requirements.txt         # numpy, pupil-apriltags, pillow (+ opencv for tests)
cd cardreader
python3 -m duckcards read picture.png --plan       # what a picture's cards say, and the plan
python3 -m duckcards watch                         # on the robot: frames from mediad, moves to robotd
python3 -m duckcards watch --floor                 # look down at a row on the floor first
python3 -m duckcards watch --deck class.duckcards  # with a class's own Your cards
python3 -m duckcards watch --dry-run               # read and say what would be sent, send nothing
python3 -m duckcards watch --pack get-to-the-pond  # play a pack: a starter pack's id, or a .duckpack file
python3 -m duckcards watch --pack get-to-the-pond --challenge pond-3   # and hear each row on its board
```

From a laptop to a real duck, through this repository's `bridge/`:

```sh
python3 -m duckcards watch --frame-url http://duck.local:8080/frame \
        --bridge duck.local:7788 --token-file ~/.microduck-bridge-token
```

Beside Pollen's simulator, see [Proving it in duck-sim](#proving-it-in-duck-sim).

## What it does

1. **Finds the codes.** `pupil_apriltags`, which is the AprilRobotics C library, the same C
   StudioKit vendors. A code counts if at most one bit was corrected and the library's own
   decision margin is confident: a false card is a duck doing something nobody asked for.
2. **Reads the number written on Repeat** (`digits.py`). The box is found near where the code says
   it is, the ink in it goes to a small network trained on MNIST (numpy only on the duck, 430 KB),
   and a number is kept only when the network is sure, the figure is not cut by the box's border and
   the box is big enough in the picture. A wrong number makes the duck do the wrong thing and say it
   did the right one, so it would rather ask.
3. **Puts the cards back into rows.** Each code says where its card is and which way is up on it
   (the black square is 19.2% of the card's width, at a fixed place in its corner). Rows run along
   the cards' own "right", so a row seen from the far side reads the same; a Speed or Look card
   about one card below another is under it; a card turned round is set aside and named.
4. **Turns the head along a row too long for one look** (`pan.py`, `runner.Scanner`). When a Start
   has no End and the row runs off the picture (or an End has no Start), the duck turns its head a
   step at a time, keeping a card in common between looks, and joins the looks into one row:
   every card is put where a camera on the head's yaw axis would have seen it, so the same card in
   two looks is one card and three Walk forward cards stay three. A join that does not line up is
   refused, not read.
5. **Reads the program.** Start to End, left to right. Repeat repeats the number written on it: a
   number read off the card is said back ("Repeat says 3 times."); one nobody could read is asked
   about (`Program.asks`) and the row waits, as the cards page's spec says a reader that cannot read
   handwriting must. A row starting When it falls is kept apart and run after the duck has got
   itself back up. A Your card runs the row its deck saved for it, and may hold Your cards of its
   own, four deep; a loop is cut and both cards named. One card on its own is a program of one
   step. Every card the reader did not use is named in a note.
6. **Makes Studio's plan.** `duck-intent-plan/0`, `model: "duck-cards/0"`, every label at
   confidence 1.0, checked against every rule `DuckIntentPlan.read` enforces.
7. **Runs it the way Studio does.** `RobotPlan` and `RobotPlanRunner` in Python, number for number:
   Pollen's pad limits (0.3 m/s, 1.5 rad/s), slow/normal/fast at a third, two thirds and all of
   them, two seconds a step, `robot.move` at 20 Hz, the skill list checked before anything moves,
   a stop at the end. The policy is switched on (`robot.enable`) only when there is something to
   run. Look cards are sent as `robot.look` only with `--heads`, because Studio does not send heads
   yet and the two should not differ.
8. **Answers, and looks at the cards.** A chirp for a card, a hello before a row, the rising
   "inquire" for a row that waits (no End yet, or a Repeat number nobody could read). While it
   watches, the duck holds its head still (`runner.Gaze`): robotd's idle look-around otherwise
   takes a held card out of the picture and back, and the card is acted on again each time.

## Your cards and the deck file

A Your card means what its deck file says, as the cards page's spec has it: the card gains a
`row`, in the deck's own `example.row` shape, beside a name and a `does` sentence.

```json
{"tag": 201, "code": "card_2", "name": "Victory dance", "category": "yours", "kind": "yours", "plan": null,
 "row": [{"card": "walk_forward", "under": ["fast"]}, {"card": "repeat", "times": 2},
         {"card": "roll"}, {"card": "end_repeat"}],
 "does": "Walk forward fast, then roll twice."}
```

Studio writes these (Save as a card, on the camera card) and shares the deck as a `.duckcards`
file; `--deck class.duckcards` gives it to the duck. **A deck file lends only its Your cards.** A
number never changes meaning, so whatever a file says about a printed card is left as the starter
deck has it, and said; a file saved under an older starter deck still reads every card this one
has. A deck that says something the reader cannot follow (a card that is not a card, a Repeat
with no number) is refused by name.

## Packs

A pack is a game for the cards, set for a grade band ([docs/PACKS.md](../docs/PACKS.md)). `--pack`
takes a `.duckpack` file, or the id of a starter pack in `duckcards/packs/` (`get-to-the-pond`,
`duck-maze`, `loop-the-course`, `design-a-level`), and works on `watch` and `read`.

- **It lends the pack's Your cards**, the way `--deck` lends a class's. With `--deck` too, a
  number the class already saved a different row for keeps the class's meaning, as in Studio,
  and the reader says which numbers clashed.
- **It narrows, it does not refuse.** A card the pack does not play still runs, and the reader
  says so beside the row's other notes: `note: Roll is not in Get to the pond.`
- **`--challenge pond-3`** plays each row the duck runs on that challenge's board, after it has
  run, and prints what the board says, solved or not, and the score against par:

  ```
    [board] Corner pond (pond-3): Solved in 5 steps, which is par.
    [board] solved, score 5 steps, par 5.
    [board] This is the board's answer for the row (one Walk card, one square), not where the duck stopped. One Walk card has not been measured on a duck yet.
  ```

  That is a report on the row, not on the duck. The board rule moves one square per Walk card and
  turns a quarter per Turn card; nothing here watches where the duck stopped, and a Walk card on
  a duck is not yet a square (docs/PACKS.md, Sizing: in duckbench a Normal Walk forward carries
  the duck about 14 cm and turns it 11 to 15 degrees, and a timed Turn is not a quarter turn). So
  the reader never says the duck reached the goal, only that the row does on the board.

A pack that cannot be found or read, and a challenge the pack does not have, are refused with a
sentence before the duck reads anything.

## What the duck's camera can read

Measured on simulated frames from the real camera geometry (`tests/scenes.py`): Pollen's IMX219,
the full ~62° width delivered at 1280x720 and turned upright, so the reader gets 720x1280, about
37° across; the head about 24 cm up. "Soft" is a blur of 1 px, "sharp" 0.6 px. Nothing here is a
photograph of a classroom.

| how the cards are shown | one look reads reliably | notes |
|---|---|---|
| One card held up | to ~50 cm soft, ~70 cm sharp | the solid mode; every pose tried, ±30° |
| A row in a rail, 4 cards | 40–50 cm, soft or sharp | |
| A row in a rail, 6 cards | 60–80 cm, sharp only | a row this long only fits the picture from ~65 cm |
| A row on the floor, near side | 25–40 cm | the duck sits where a person reads the row from |
| A row on the floor, far side | ≤ 25–30 cm | the codes are at each card's far edge; `--upscale` helps |

So about four cards a look. **Turning the head along the row**, the longest row read (and how many
looks it took), every shorter row read too (`tools/pan_envelope.py`):

| how the row is shown | soft, duck facing the row's middle | soft, Start a little left of the middle | sharp, facing the middle | sharp, Start left |
|---|---|---|---|---|
| Rail, 35 cm | 11 cards (5 looks) | 6 (3) | 12 (6) | 8 (4) |
| Rail, 45 cm | 10 (3) | 6 (2) | 14 (5) | 7 (3) |
| Rail, 60 cm | 5 (1) | 4 (1) | 13 (3) | 9 (2) |
| Floor, 32 cm, near side | 8 (4) | 5 (2) | 10 (5) | 8 (3) |
| Floor, 26 cm, far side, `--upscale` | 7 (3) | 5 (3) | 11 (5) | 8 (4) |

What limits a row is not the turning: a card more than about 35° (soft) to 45° (sharp) off the
duck's axis is turned too far from the camera to be found, so where the duck faces matters. Three
looks take about 2 s and five 3.5 to 4.5 s (0.6 s to settle after each turn).

**The number on Repeat**, a Repeat card held up, yaw up to 30°, 108 handwritten digits from MNIST's
test split (never trained on), read right / read wrong / asked (`tools/digits_envelope.py`):

| distance | soft | sharp |
|---|---|---|
| 15 to 25 cm | 68 to 69% / 0 / 31 to 32% | 57 to 65% / 0 / 35 to 43% |
| 30 cm | 55% / 0 / 45% | 44% / 0 / 56% |
| 40 cm | 19% / 0 / 81% | 24% / 0 / 76% |
| 50 cm | 0 / 0 / 100% (the box is too small) | 0 / 0 / 100% |

It never gave a wrong number in 2,592 reads of these pictures, by design: a confident read needs
the network at 0.995 and 0.995 ahead of its next answer. The cost is that it asks for about a
third of numbers even up close. Real handwriting under a classroom's light is still to be seen.

## Proving it in duck-sim

Run twice on 2026-10-14 in Pollen's simulator, with robotd, mediad and the MuJoCo body built from
pollen-robotics/microduck 648bf22 and microduck_rl's develop b02fdea4:

| | result |
|---|---|
| A card held up, 30 cm | Kick, right read through mediad's `/frame`, `robot.do kick_right` accepted, `skill started skill=kick_right`, the right leg swung (hip pitch +0.5 rad) and the duck stayed up. Before the reader held the head: three kicks in 26 s for one card. Holding it: one kick in 45 s (and five with `--let-head-wander`). |
| Six cards in a rail, 35 cm | The duck looked right and left 19° (the head turned within 1.5° of what was sent), joined 6 cards, said hello and ran the row once. With the row off to one side it ran 2 and 3 times; fixed in 726b673, not yet run again in the simulator. |
| A Your card (card 201 = Kick, left; Kick, right) | `--deck`: both kicks, in order, 1.5 s apart, once. |
| Repeat with a 3 written on it | Read at 10 cm (6 frames of 7); at 15 cm 2 of 7, never a wrong number. The simulator's camera has 0.41 of the robot's pixels, so 10 cm there is about 25 cm on the robot. |
| A row on the floor, 32 cm | No code found: too few pixels in the simulator's camera. At 22 cm the row read except its End. |
| Walking | Rows send `robot.move` and robotd applies it, but the simulated duck takes no steps; Pollen's own `duck-sim drive` does the same with the v8 policies. A simulator and policy matter, worth raising with Pollen. |

To run it again (`cardreader/sim/`, Ubuntu 24.04 without a GPU):

1. **Pollen's code.** Clone pollen-robotics/microduck and pollen-robotics/microduck_rl (develop).
   In microduck: `cargo build -p robotd -p robotctl -p tof -p sounds -p configd -p updater -p mediad`
   (apt: `libudev-dev pkg-config libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
   libgstreamer-plugins-bad1.0-dev gstreamer1.0-tools gstreamer1.0-nice gstreamer1.0-plugins-ugly
   libosmesa6 libgl1-mesa-dri libegl1`), then `scripts/seed-policies.sh ~/.cache/duck-sim/policies`.
2. **mediad's webrtcsink.** Ubuntu does not package it and mediad will not start without it: build
   crates.io's `gst-plugin-webrtc` 0.15.4 with `cargo build --release --locked --no-default-features
   --features rustls-ring --lib` and put `libgstrswebrtc.so` on `GST_PLUGIN_PATH`.
3. **The body's venv**, without torch: in microduck_rl, `uv venv .venv && uv pip install --python .venv
   mujoco==3.10.0 numpy==2.4.1 onnxruntime==1.24.4 pillow && uv pip install --python .venv --no-deps -e .`
4. **Up, cards, read:**
   ```sh
   export MICRODUCK=~/microduck MICRODUCK_RL=~/microduck_rl MUJOCO_GL=egl
   cardreader/sim/up.sh                                  # one duck, standing, no cards
   python3 cardreader/sim/card_png.py kick_right kick_right.png
   $MICRODUCK_RL/.venv/bin/python cardreader/sim/scene.py --from-duck card.xml kick_right.png --dist 0.30
   cardreader/sim/look.sh card.xml                       # the duck sees it
   cd cardreader && python3 -m duckcards watch --frame-url http://127.0.0.1:8080/frame \
       --robot-socket ~/.cache/duck-sim/duck-a.sock --camera-degrees 72.7
   cardreader/sim/down.sh
   ```

Why it is put together this way: duck-sim's own camera (`DUCK_SIM_CAMERAS=a`) renders on the
body's physics thread, and without a GPU that slowed the world to half speed and the duck fell over,
so `eye.py` renders the same camera beside it from the duck's pose and Pollen's mediad serves it;
the duck settles anywhere from -17° to +20° after standing up, so `scene.py --from-duck` lays the
cards in front of where it actually stands; the simulator's camera sees 72.7° along the picture's
long side, the robot's 62°, which `--camera-degrees` tells the joins.

## Found on the way

- **The cards print every code turned half round from the AprilTag library's own drawing.** The
  site took its codes from OpenCV's tag36h11 dictionary, which draws them rotated 180° from
  `apriltag_to_image`. The ids decode the same either way, and both libraries name the corners of a
  code *as printed* in the same order (top right, top left, bottom left, bottom right), which is the
  order the reader assumes. Anyone computing a card's pose from its code must start from that.
- **robotd's idle look-around** starts two seconds after nobody steered the head and swings it
  about 18° each way; a reader that watches must hold the head. A zero `robot.head` command is
  robotd's rest pose, not zero joints (in duck-sim, neck 12.5°, head pitch 26°).
- **The pictures the AprilTag library reports** put a pixel's centre at its index plus a half;
  `digits.py` samples at the index and corrects for it.

## Tests

```sh
python3 -m unittest discover -s cardreader/tests -v     # 136 tests, about 35 s
scripts/check_duckcards_vectors.sh                       # the two readers' contract
python3 scripts/check_duck_packs.py                      # every pack's pars and rows
```

`tests/make_vectors.py` writes `vectors/`: twenty-eight cases, three of them the library's own
answers to simulated frames, each with the rows, words, notes, questions, When it falls steps and
plan the reader must produce, and some with a class's own cards or answers to Repeat questions.
StudioKit's `DuckCardsTests` reads every one; the gate keeps the copies identical. The bridge test
runs a row's calls through this repository's own `microduck-bridge` and `mock-robotd`; the scan
tests turn a simulated camera with the head and hold a row read once to running once.

The same script writes the pack vectors, `vectors/pack_*.json`: a challenge from one of the
starter packs in `duckcards/packs/`, a row, and the board play `duckcards/packs.py` makes of it
(docs/PACKS.md). StudioKit's `DuckPacksTests` plays every one to the same JSON.

## Not done

- Running on a real duck, real printed cards, real handwriting. Everything here was run against
  simulated frames, the mock robotd, the bridge, and duck-sim.
- Getting a class's deck onto the duck is a copy (`scp`); Studio cannot send it there yet.
- Teaching a Your card by laying it before Start, on the duck alone. Not built on purpose: the
  cards page says nothing before Start is read, and a duck that saved a meaning from a card left
  lying there would replace a class's card without anybody confirming it. Studio saves cards, and
  asks before replacing one.
- Studio does not read handwriting; it asks for every Repeat number.
