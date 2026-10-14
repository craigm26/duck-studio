# cardreader: the duck reads Duck Cards

Show a Microduck a Duck Card and it does what the card says. Show it a row, Start to End, and it
reads the row and runs it. This is the reader, for the robot itself; StudioKit's `DuckCards` is
the same reader for Studio reading the duck's camera. One deck, one set of answers, two readers.

```sh
pip install -r cardreader/requirements.txt         # numpy, pupil-apriltags, pillow (+ opencv for tests)
cd cardreader
python3 -m duckcards read picture.png --plan       # what a picture's cards say, and the plan
python3 -m duckcards watch                         # on the robot: frames from mediad, moves to robotd
python3 -m duckcards watch --floor                 # look down at a row on the floor first
python3 -m duckcards watch --dry-run               # read and say what would be sent, send nothing
```

Beside duck-sim on a laptop (`DUCK_SIM_CAMERAS=a` gives the sim duck a camera and a `/frame`):

```sh
python3 -m duckcards watch --frame-url http://127.0.0.1:8080/frame \
        --robot-socket ~/.cache/duck-sim/duck-a.sock
```

From a laptop to a real duck, through this repository's `bridge/`:

```sh
python3 -m duckcards watch --frame-url http://duck.local:8080/frame \
        --bridge duck.local:7788 --token-file ~/.microduck-bridge-token
```

## What it does

1. **Finds the codes.** `pupil_apriltags`, which is the AprilRobotics C library, the same C
   StudioKit vendors. A code counts if at most one bit was corrected and the library's own
   decision margin is confident: a false card is a duck doing something nobody asked for.
2. **Puts the cards back into rows.** Each code says where its card is and which way is up on it
   (the black square is 19.2% of the card's width, at a fixed place in its corner). Rows run along
   the cards' own "right", so a row seen from the far side reads the same; a Speed or Look card
   about one card below another is under it; a card turned round is set aside and named.
3. **Reads the program.** Start to End, left to right. Repeat is unrolled (twice: nothing reads
   the number written on it yet). A row starting When it falls is kept apart and run after the
   duck has got itself back up. A Your card runs what the class saved for it (`--yours`). One card
   on its own is a program of one step. Every card the reader did not use is named in a note.
4. **Makes Studio's plan.** `duck-intent-plan/0`, `model: "duck-cards/0"`, every label at
   confidence 1.0, checked against every rule `DuckIntentPlan.read` enforces.
5. **Runs it the way Studio does.** `RobotPlan` and `RobotPlanRunner` in Python, number for number:
   Pollen's pad limits (0.3 m/s, 1.5 rad/s), slow/normal/fast at a third, two thirds and all of
   them, two seconds a step, `robot.move` at 20 Hz, the skill list checked before anything moves,
   a stop at the end. The policy is switched on (`robot.enable`) only when there is something to
   run. Look cards are sent as `robot.look` only with `--heads`, because Studio does not send heads
   yet and the two should not differ.
6. **Answers.** A chirp for a card, a hello before a row, the rising "inquire" for a Start with no
   End held up for four seconds.

## What the duck's camera can read

Measured on simulated frames from the real camera geometry (`tests/scenes.py`): Pollen's IMX219,
the full ~62° width delivered at 1280x720 and turned upright, so the reader gets 720x1280, about
37° across; the head about 24 cm up. "Soft" is a blur of 1 px, "sharp" 0.6 px. Nothing here is a
photograph of a classroom.

| how the cards are shown | reads reliably | notes |
|---|---|---|
| One card held up | to ~50 cm soft, ~70 cm sharp | the solid mode; every pose tried, ±30° |
| A row in a rail, 4 cards | 40–50 cm, soft or sharp | |
| A row in a rail, 6 cards | 60–80 cm, sharp only | a row this long only fits the picture from ~65 cm |
| A row on the floor, near side | 25–40 cm | the duck sits where a person reads the row from |
| A row on the floor, far side | ≤ 25–30 cm | the codes are at each card's far edge; `--upscale` helps |

So: about four cards a look. A longer row wants the head turned along it, which is not built.

## One thing found on the way

**The cards print every code turned half round from the AprilTag library's own drawing.** The site
took its codes from OpenCV's tag36h11 dictionary, which draws them rotated 180° from
`apriltag_to_image`. The ids decode the same either way, and both libraries name the corners of a
code *as printed* in the same order (top right, top left, bottom left, bottom right), which is the
order the reader assumes. Anyone computing a card's pose from its code must start from that.

## Tests

```sh
python3 -m unittest discover -s cardreader/tests -v     # 38 tests
scripts/check_duckcards_vectors.sh                       # the two readers' contract
```

`tests/make_vectors.py` writes `vectors/`: eighteen cases, three of them the library's own answers
to simulated frames, each with the rows, words, notes, When it falls steps and plan the reader
must produce. StudioKit's `DuckCardsTests` reads every one; the gate keeps the copies identical.
The bridge test runs a row's calls through this repository's own `microduck-bridge` and
`mock-robotd`.

## Not done

- Reading a row longer than one look (turning the head along it and joining the looks).
- Reading the number written on Repeat.
- Saving what a Your card means from Studio (here it is a JSON file passed with `--yours`).
- Running on a real duck. Everything here was run against simulated frames, the mock robotd and
  the bridge; duck-sim with a camera is the next proof, then a robot.
