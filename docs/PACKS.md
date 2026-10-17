# Duck Card packs

A pack is a game for Duck Cards, set for a grade band: which cards are in play, the board, a
ramp of challenges from easy to hard, and the teacher's notes. It is one JSON file, shared as
`.duckpack`, and three things read it: microduckstudio.com prints it, Studio plays it, and the
card reader on the duck runs with `--pack`.

The primary activity is modelled on floor-robot coding sets such as Learning Resources' Code & Go
Robot Mouse (LER 2831): a grid, walls, a goal, tunnels to pass through, coding cards laid in a
row, and numbered activity cards that ramp up, each to be solved "in the fewest steps possible".
We take the shape of that activity, not its content: every board and challenge here is our own.

## What is different about a duck

The mouse moves exactly 12.5 cm per Forward and turns exactly 90°. A Microduck walks. In
`DuckIntentPlan`, Walk forward and Turn left are timed (`defaultSeconds`), and a walking duck
drifts. So a pack keeps two things apart:

- **The board rule.** On the board, one Walk card moves one square and one Turn card is a quarter
  turn. This is exact and is what the paper game, Studio's board and every check use.
- **The duck.** How far one Walk forward carries a real or simulated duck is measured, not
  assumed. Closed-loop cards (walk until one duck square on robotd's odometry, turn until a
  quarter turn; "Closed-loop cards", below) exist, but they **ship off for real ducks** until they
  pass "Acceptance", below. Until then a duck runs Walk and Turn as timed cards, two seconds each,
  and every surface says so: "Walk and Turn cards on a duck are timed for now: two seconds each,
  and the duck does not land on board squares. Measured cards are being tested." `duck_square_cm`
  is the square a closed-loop Walk card walks, with `duck_square_source` saying where it was
  measured; no page or screen says a real duck will land on a square.

## The file: `duck-pack/0`

```json
{
  "format": "duck-pack/0",
  "id": "get-to-the-pond",
  "name": "Get to the pond",
  "grades": "PreK to K",
  "grade_from": -1,
  "grade_to": 0,
  "vocabulary": "r001",
  "license": "CC-BY-4.0",
  "credit": "Duck Cards, from microduckstudio.com",
  "about": "One sentence a teacher reads first.",
  "cards": ["start", "end", "walk_forward", "turn_left", "turn_right"],
  "score": "steps",
  "board": { "columns": 3, "rows": 3, "square_cm": 30, "duck_square_cm": 30,
             "duck_square_source": "duckbench simulator, 2026-10-15: ..." },
  "challenges": [ ... ],
  "lessons": [ { "title": "...", "skill": "...", "body": "...", "ask": "..." } ],
  "yours": [ ]
}
```

- `grade_from`, `grade_to`: integers, PreK = -1, K = 0, then 1 to 12. `grades` is how a page
  writes them.
- `vocabulary` must equal the deck's `vocabulary`.
- `cards`: the card codes in play. Every code must be in the deck, `start` and `end` always
  included. A card not in play is not refused by a reader: it runs, and the reader notes "Roll is
  not in Get to the pond." The pack narrows what is printed and offered, not what a duck may do.
- `score`: `steps` (fewest board steps, the mouse's rule) or `cards` (fewest cards in the row,
  which is where Repeat and Your cards pay off).
- `board`: the default board. A challenge may give its own `columns` and `rows`, 1 to 12 each.
  `square_cm` is the printed or taped floor square for people. `duck_square_cm` is the measured
  distance of one Walk forward card, or `null`. `duck_square_source` is one line saying where
  `duck_square_cm` was measured and how far off a duck ended (rows, the error bound, falls, what
  was not measured); it is required with a number and absent or `null` without one. Both readers
  refuse a pack that has one without the other.
- `yours`: Your card entries, exactly as a `.duckcards` deck carries them (`tag`, `code`, `name`,
  `does`, `row`). Opening a pack lends these to the class deck the same way `Deck.lend` does:
  only Your cards, and never replacing one the class already saved without asking: a number the
  class already saved a different row for keeps the class's meaning unless the reader is told to
  replace it, and the numbers that clashed are returned so a screen can ask. A pack's Your card
  is numbered in the Your card range (200 to 299), its `code` is the deck's own for that number
  (`card_1` for 200), and it carries a non-empty `row` and a `name`.
- `lessons`: `{title, skill, body, ask}`, every field words. A reader takes any number; the
  starter packs carry 3 to 6.

### A challenge

```json
{
  "id": "pond-3",
  "name": "Round the reeds",
  "columns": 3, "rows": 3,
  "start": { "at": [0, 2], "facing": "north" },
  "goal": [2, 0],
  "walls": [ { "between": [[0, 1], [1, 1]] } ],
  "gates": [ { "at": [1, 0], "axis": "ew" } ],
  "finish_with": null,
  "par": 5,
  "solution": [ { "card": "walk_forward" }, { "card": "turn_right" } ],
  "buggy": null,
  "hint": "Count the squares before you lay a card.",
  "note": "Room 12 drew this one."
}
```

- Squares are `[x, y]`, `x` from 0 at the left, `y` from 0 at the top, as the board is printed.
  `facing` is `north` (up the page), `east`, `south` or `west`.
- A wall sits `between` two squares that share an edge. The board's edge is a wall too.
- A gate (the tunnel) sits on a square with an `axis`, `ns` or `ew`. It is passed when the duck
  walks into its square moving along that axis, forward or backward. A challenge is solved only
  when every gate has been passed, in any order. A gate may not sit on the start square, which
  can never be walked into. The goal may be the start square, when gates make the duck go round
  and come home.
- `finish_with`: `null`, or a card code that must be the last step (for example `greet`: "say
  hello at the pond"). It must be a card in play that the duck does standing still: not a Walk
  or Turn, and not Start, End, Repeat or End repeat.
- `solution`: one row that solves it, in the deck's `example.row` entry shape, without Start and
  End (`{"card", "under"?, "times"?}`). Repeat carries `times`, 1 to 9, and no other card does.
- `par`: the best score possible under the pack's `score`. For `steps` it is computed: the
  shortest path by breadth-first search over (square, facing, gates passed), counting one step
  per Walk or Turn card, plus one if `finish_with` is set. For `cards` it is the card count of
  the shortest row the author found, and the checks hold `solution` to it.
- `note`: optional; absent, `null`, or one line of words from whoever wrote the challenge, shown
  beside it. It is never a rule and no check reads it.
- `buggy`: `null`, or a row that does not solve the challenge but becomes a solution with one
  card swapped ("Find the bug"). The checks prove both halves. A swap replaces one card that acts
  on its own (a move, a sound, a trick or a Your card) with another such card in play, keeping
  the cards under it; Repeat, End repeat and the Speed and Look cards are not swapped.

### The board rule

A program is the steps a reader already makes from a row (Repeat unrolled, Your cards opened). A
saved row (a `solution`, a `buggy` row, a row a person laid in Studio) is turned into steps the
way a Your card is read back: laid out as Start, the row, End, and read by the reader's own
`read` (`program.table` in Python, `DuckCards.table` in Swift), so it is held to the same rules,
the 40-step limit among them. Each step's `action` label moves the duck on the board:

| action | on the board |
|---|---|
| `walk_forward` | one square the way it faces |
| `walk_backward` | one square the other way, still facing the same way |
| `turn_left`, `turn_right` | a quarter turn in place |
| anything else (`stop`, sounds, tricks) | stays put; counts as a step |

Speed and Look cards ride under a step and change nothing on the board. When it falls rows are
not played on the board.

A walk into a wall or off the board is a **bump**: the duck stays where it was, the play stops
there, and the challenge is not solved. The play result names the step that bumped.

A Repeat with no End repeat after it still runs (the reader repeats to the end of the row and
says so), but on the board it is **not solved**: a loop is Repeat and End repeat, and a `cards`
par that leaving out End repeat could beat would teach leaving it out.

Solved means: at least one step, no bump, every gate passed, the duck ends on the goal, if
`finish_with` is set the last step is that card, and every Repeat is closed. The score is the
number of steps (`steps`) or the number of cards in the row between Start and End, counting
Repeat and End repeat and each under-card (`cards`). A Your card is one card.

### Play result

Both readers produce the same JSON for a challenge and a program; the vectors pin it:

```json
{
  "solved": false,
  "path": [ { "at": [1, 3], "facing": "north" }, { "at": [1, 3], "facing": "east" } ],
  "bumped_at": 2,
  "gates_passed": [],
  "ended": { "at": [1, 3], "facing": "east" },
  "steps": 2,
  "cards": 2,
  "score": 2,
  "par": 5,
  "said": "Bumped into a wall on step 2."
}
```

`path` holds the start and then the place after every step played; the step that bumped is not
in it, so a bumped play's path is `bumped_at` long. `bumped_at` is 1-based, or `null`.
`gates_passed` holds the gates' places in the challenge's list, in order. `steps` is every step
the row makes, played or not; `cards` is the card count; `score` is whichever the pack scores
by, given whether or not the row solved it. `said` is the first of these that holds:

| when | said |
|---|---|
| a bump into a wall | `Bumped into a wall on step N.` |
| a bump off the board | `Bumped into the edge of the board on step N.` |
| no steps | `The row has no steps to play.` |
| not on the goal | `The duck ended N square(s) away from the goal.` (squares counted along the grid) |
| a gate missed | `The duck reached the goal but missed N gate(s).` |
| `finish_with` missed | `The duck reached the goal but did not finish with <card name>.` |
| a Repeat not closed | `The duck reached the goal, but a Repeat has no End repeat. Close every loop.` |
| solved at par | `Solved in N steps, which is par.` (`with N cards` for a `cards` pack) |
| solved over par | `Solved in N steps. Par is P, so a shorter row is out there.` |
| solved under par | `Solved in N steps, under par P. Tell whoever wrote the challenge.` |

## The four starter packs

| id | grades | cards in play | board | score | challenges |
|---|---|---|---|---|---|
| `get-to-the-pond` | PreK to K | Start, End, Walk forward, Turn left, Turn right | 3 x 3, 30 cm squares | steps | 6, no walls in the first 3 |
| `duck-maze` | 1 to 2 | + Walk back, Stop, Hello, Kick, right | 4 x 4 | steps | 10; walls from 3, gates from 6, `finish_with` in 2 |
| `loop-the-course` | 3 to 5 | + Repeat, End repeat, Slow, Fast, Look left, Look right | 5 x 5 | cards | 10; at least 4 where Repeat beats the plain row, 2 Find the bug |
| `design-a-level` | 6 to 8 | every printed card, + When it falls, Your cards | 6 x 6, 30 cm squares | cards | 3 worked examples; the lesson is authoring one for another group |

Each pack carries 3 to 6 lessons in the voice of the cards page's "Lessons to start with": one
class period, paper first, a question to ask at the end.

## Where packs live

- Source: `StudioKit/Sources/StudioKit/Resources/DuckPacks/<id>.duckpack`.
- Copies: `cardreader/duckcards/packs/` and microduck-com `public/cards/packs/`. A copy is a
  thing that drifts, so `scripts/check_duckcards_vectors.sh` compares them byte for byte, as it
  does the deck.
- Vectors: `cardreader/vectors/pack_*.json`, each a challenge, a row, and the play result, written
  by `cardreader/tests/make_vectors.py` beside the card vectors and copied to StudioKit's fixtures.
  A vector carries everything a reader needs to play it: `score`, `cards`, `board`, `yours`,
  `challenge`, `row` and `expect`. Swift and Python must both produce `expect`.
- `scripts/check_duck_packs.py FILE.duckpack` checks a pack from elsewhere, such as a class pack
  Studio wrote, by the same rules except the two about what this repository ships (the file
  named for its id, 3 to 6 lessons).
- `scripts/check_duck_packs.py` checks every pack: schema, cards in the deck, the file named for
  its id, every goal reachable with every gate passed, `par` equal to the search (for `steps`),
  `par` no worse than the shortest plain row (for `cards`), `solution` solves at `par` and
  unrolls to 40 steps or fewer, `buggy` fails and one swap fixes it, solutions and buggy rows use
  only cards in play and the pack's own Your cards, 3 to 6 lessons, and no em or en dash.

## The readers' API

Python, `cardreader/duckcards/packs.py`: `Pack.read(data, deck)` and `Pack.load(path, deck)`
(refusing with `PackError`, a sentence), `Pack.lend(deck, replace=False) -> (deck, clashes)`,
`Pack.not_in_play(codes, deck)`, `bundled(deck)`, `steps_of(row, deck)`, `card_count(row)`,
`open_repeats(row)`, `play(challenge, steps, cards, score, deck, unclosed)`,
`play_entries(challenge, row, score, deck)`, `play_row(pack, challenge, row, deck)`,
`par_steps(challenge, cards)`, `par(pack, challenge)`, `swaps(pack, row, deck)`.

Swift, `StudioKit/Sources/StudioKit/DuckPacks.swift` and `DuckPackBoard.swift`, under
`DuckPacks`: `Pack.read(_:deck:)` (throwing `Refusal.notAPack`, whose `message` is the same
sentence), `bundled`, `Pack.lent(to:replacing:)`, `Pack.notInPlay(_:deck:)`, `steps(of:deck:)`,
`cardCount(_:)`, `openRepeats(_:)`, `play(_:row:score:deck:)`,
`play(_:steps:cards:score:deck:unclosed:)` returning `Play` (whose `json` is the result above),
`parSteps(_:cards:)`, `par(_:in:)`, `swaps(_:in:deck:)`.

## Surfaces

1. **Website.** `/cards/packs/` lists the packs by grade; `/cards/packs/<id>/` shows the board,
   the challenges as printable activity cards (board drawing, start, goal, walls, gates, par),
   the lessons, and a download of the `.duckpack`. Only the cards in play are on that pack's cut
   sheet.
2. **Studio.** A Packs screen: the bundled packs and any opened `.duckpack`. A pack shows its
   challenges in order; a challenge shows the board, lets you lay a row from the pack's cards
   (or take the row the camera read), plays it on the board step by step, and says solved, the
   score and par. "Run on the duck" sends the same row as a plan, as rows already do; its Walk
   and Turn cards are timed on a duck for now, and the screen says so (the off switch, under
   Closed-loop cards). Design a
   level adds a challenge editor (tap squares for start, goal, walls, gates; par is computed)
   and saves challenges into a class pack that shares as `.duckpack`.

   **Which meaning plays.** One rule everywhere: on a clash between a pack's Your card and the
   class deck's card of the same number, the class deck's own meaning wins. The camera reads it,
   the board plays it and Run on the duck runs it; the pack's Your cards are lent only where the
   class has none, unless the person chooses to replace the class's own. The pack screen and the
   challenge screen say so when a clash exists. The card reader with `--pack` does the same.

   **Opened packs, one per id.** An opened pack is kept as `Opened/<id>.duckpack`. Packs with
   different ids sit side by side; one whose id is already open replaces it only after the person
   chooses, with both named. The same bytes again are said to be open already.

   **The class pack.** Each install mints its class pack's id once, `class-` and six small letters
   and numbers (no 0, o, 1 or l), and keeps it in `class-settings.json` beside `class.duckpack`,
   so two classes' packs never share an id. A pack written before this, with the old shared id
   `our-class-pack`, is given a new id when Studio first finds it. The teacher sets, in Class pack
   settings:
   - the name (default "Our class pack");
   - the score, `steps` or `cards`;
   - the cards in play, by default every printed card, Start and End always in.

   New settings recheck every challenge: par is worked out again, and a challenge that cannot be
   solved with the cards chosen (or finishes with a card taken out) refuses the change in a
   sentence, with nothing changed. In the editor:
   - `finish_with` is a picker of the cards in play the duck does standing still (Pack.read's
     rule, and a step on its own: Stop, sounds, tricks), or None; par counts it, live.
   - A note, one optional line.
   - Scored by `steps`, par is the search and the solution its shortest row.
   - Scored by `cards`, par for a new challenge is the card count of the shortest plain row (the
     same number `check_duck_packs.py` holds a `cards` par to). The author may lower it by laying
     a shorter row, usually with Repeat; the editor plays it on the board as it is laid and it
     counts only if it solves the challenge in fewer cards, and then it is the solution.
3. **Card reader.** `python3 -m duckcards watch --pack get-to-the-pond.duckpack [--challenge
   pond-3]`: notes cards not in play, lends the pack's Your cards, and with a challenge prints
   the board play of each row it runs. It still runs what it reads; the board play is a report.

## Not promised

- That a real duck lands on a square. Closed-loop cards are off for real ducks (the off switch,
  under Closed-loop cards); a duck's Walk and Turn are timed. The shipped spec was measured in
  Pollen's duck-sim on 2026-10-15 and did not pass rung 1 of Acceptance (it passes nominal and
  randomized at 20 Hz, fails Walk back at 10 Hz and the stressed condition; Sizing, "Closed-loop
  cards: Pollen's duck-sim"). Testers' ducks are not measured at all.
- Physics-sim goal checks. Placing the board in Studio's simulated world needs the same
  measurement; until then Studio's board is the board rule, and the sim duck runs the row
  beside it.

## Acceptance (pre-registered 2026-10-15, before any result is in)

Closed-loop Walk and Turn cards ship switched off for real ducks (`enabled_on_robot: false` in
`duck-card-loop.json`). They are switched on only when every rung of the ladder below has passed
every criterion below. These criteria were written down before Pollen's duck-sim or any real
duck produced a number, and they are not loosened to fit a result. A change to them is a new
dated paragraph here saying what changed and why, with the old text kept.

### What a row must do

A row is one program of Walk and Turn cards (the rows are listed under "Rows", below), run from a
standing duck. Its error is where the duck ended against the board rule (one square per Walk
card, a quarter turn per Turn card) at 30 cm a square, in the row's own start frame, measured by
ground truth in a simulator and by tape on a floor; never by the duck's own odometry.

| criterion | pass |
|---|---|
| end position | within one third of a square (10 cm at 30 cm) of the board's square, in **at least 95%** of rows in every condition |
| end heading | within **15 degrees** of the board's heading, in **at least 95%** of rows in every condition |
| falls | the **95% Wilson upper bound** (two-sided, z = 1.96) on the fall rate is **at most 1%** in every condition |
| time, Walk card | each Walk card done in **at most 8 s** |
| time, Turn card | each Turn card done in **at most 6 s** |
| ending badly | every row that is stuck, loses its state (stale), falls, or cannot reach (out of time, trimmed out) ends with the duck commanded still and **one sentence** saying which; 100% of such rows |

- The 95% figures are the observed share of rows. Each result also reports its Wilson interval.
- The fall bound needs enough rows: with no falls at all, the upper bound is z^2 / (n + z^2),
  which is 1.9% at 200 rows and first reaches 1% at **381 rows**. One fall needs 563
  rows; two, 726. So 200 rows per condition can pass position and heading but cannot pass
  falls alone; a condition that is to pass falls runs at least 381 rows.
- The time bounds (Walk 8 s, Turn 6 s) are pre-registered as stated. If the data later justify
  another bound, that is a new dated paragraph here with the data cited, not an edit to this one.
  A card past its bound fails its row on time even if it arrives.
- A row that ends badly but safely counts as a failure for position and heading (and for falls,
  if it fell). Ending safely is its own criterion, and it must hold for every such row.

### Rows

The seven rows duckbench ran (F F L F R F; F R F R F R F R; F L L F; F F B; F(slow) F(fast)
L(slow) F R(fast) B(slow); L L R R; F F F F), plus the Measure my duck rows (one, two, three and
four Walk forward cards; four Turn left cards). F is Walk forward, B Walk back, L and R Turn left
and right; a speed in brackets is a Speed card under it. Rows with Walk back are reported
separately and must pass on their own.

### The evidence ladder

1. **Pollen's duck-sim, Monte Carlo.** Pollen's own robotd in duck-sim, computing `odom` itself,
   with its standing policy between cards: at least **200 rows per condition** (381 for falls, as
   above), each row randomized in ground friction, state latency, IMU yaw bias and drift,
   odometry noise, the gait phase the row starts at, and the duck's mass. A condition is one set
   of those ranges and one state rate (Studio subscribes at 10 Hz; the reader reads 20 Hz). The
   ranges are fixed and written into the result before the rows run; at least one condition is
   nominal and at least one is stressed (the far ends of every range together).
2. **Reproduced on a second, clean machine.** The same commit, conditions and seeds, run again
   from a fresh checkout on a different machine, passing the same criteria. A result one machine
   produced is not yet a result.
3. **A real tester duck on a taped 30 cm grid.** The Measure my duck protocol (Studio, below),
   judged by tape-measured end positions and headings and by video of every run, against the
   same position, heading, time and ending-badly criteria. A handful of runs cannot bound falls
   at 1%: on a real duck any fall stops this rung and the work goes back to rung 1.

Only when all three pass does `enabled_on_robot` become `true`, with `validated` set to a line
citing the three results. Until then Studio's board and the paper board are the board rule, and
a duck runs Walk and Turn as timed cards.

## Measure my duck (`duck-measure/0`)

Rung 3 of "Acceptance", in Studio: Packs, then Measure my duck. It is the one screen that runs
closed-loop cards on a robot, and it opens by saying it is a test. It needs a duck connected on
the Robot tab whose `robot.state` carries `odom`; it refuses before anything moves if the duck
reports no odometry, says it is down, or the card spec is past Pollen's envelope.

- **The grid.** Masking tape on a flat, hard floor: 30 cm squares (the spec's `square_m`), five
  long and three wide, a start square in the middle of one short end with an arrow down the long
  side. The duck stands in the middle of the start square facing the arrow before every run.
  Video of each run, from above or the side, if the tester can.
- **The rows.** One, two, three and four Walk forward cards, then four Turn left cards, each a
  `RobotPlan` of closed-loop cards at Normal run by `RobotPlanRunner` (`DuckMeasure.plan`), so it
  is exactly the controller the switch would turn on.
- **Ending.** A Stop button cancels at once (the runner always ends in `robot.stop`). A row also
  ends on its own, the duck commanded still and one sentence said, when a card runs out of time
  or trims out (the controller's exits), when the pose goes stale, or when robotd's
  `safety.fallen` says the duck is down. That is the runner's rule for every closed-loop row, in
  Studio and the card reader alike: a row ends at the first card that does not arrive.
- **The marks.** After each row the tester types three numbers from the tape: forward (cm from
  the middle of the start square to the middle of the duck, along the arrow; behind is
  negative), left (cm left of the arrow's line; right is negative) and heading (degrees turned
  left from the arrow; right is negative).
- **The judgement.** `DuckMeasure.evaluate` holds the marked rows to "Acceptance" (10 cm, 15
  degrees, Walk 8 s and Turn 6 s per card) and says so, sentence by sentence, ending with: one
  duck and a few runs cannot pass Acceptance alone. Unmarked rows are not judged; odometry is
  recorded beside the tape, never instead of it.

The report, shared as `duck-measure-<yyyyMMdd-HHmm>.json` (UTC):

```json
{
  "format": "duck-measure/0",
  "made_at": "2026-10-20T16:04:11Z",
  "app": "1.1 (85)",
  "bridge": "microduck-bridge 0.4.2",
  "robotd": null,
  "policy": "velstand",
  "envelope": { "source": "pollen-robotics/microduck robotd-params/src/lib.rs, ...",
                "commit": "34b6e7dc...", "vx": [-0.4, 0.4], "vy": [-0.3, 0.3], "vyaw": [-1, 1] },
  "spec": { "digest": "sha256:...", "enabled_on_robot": false, "square_m": 0.3 },
  "grid_cm": 30,
  "runs": [ {
    "id": "walk-2", "cards": ["walk_forward", "walk_forward"],
    "expect": { "forward_cm": 60, "left_cm": 0, "heading_deg": 0 },
    "ran_at": "2026-10-20T16:01:02Z",
    "card_log": [ { "card": "walk_forward", "seconds": 2.3, "ended": "reached",
                    "before": { "x_m": 0, "y_m": 0, "yaw_rad": 0 },
                    "after":  { "x_m": 0.29, "y_m": 0.01, "yaw_rad": 0.03 } } ],
    "odom_start": { "x_m": 0, "y_m": 0, "yaw_rad": 0 },
    "odom_end":   { "x_m": 0.59, "y_m": 0.02, "yaw_rad": 0.04 },
    "odometry": { "forward_cm": 59, "left_cm": 2, "heading_deg": 2.3 },
    "ended": "finished", "said": null,
    "tester": { "forward_cm": 63, "left_cm": -4, "heading_deg": 5 }
  } ],
  "evaluation": { "ran": 1, "judged": 1, "position_within": 1, "heading_within": 1, "in_time": 1,
                  "fell": 0, "ended_badly": 0, "ended_badly_said": 0, "said": ["..."] }
}
```

- `app` is the app's version and build; `bridge` the bridge's greeting, when connected through
  one; `robotd` its version, `null` while robotd does not report one; `policy` the last
  `robot.state` `policy`.
- `envelope` is the `pollen-pad-drive.json` the app shipped with; `spec.digest` is the sha256 of
  the `duck-card-loop.json` bytes that ran.
- `card_log[].ended` is `reached`, `lost`, `fell`, `out of time` or `trimmed out`; `before` and
  `after` are robotd's `odom.position` and `odom.yaw` (the trunk IMU's yaw) when the card began and
  when it ended, before the still moment after it; `seconds` is the card's own time.
- `ended` is `finished`, `stopped` (a card did not arrive; `said` says why), `refused` or
  `cancelled` (Stop). `tester` is absent until all three marks are typed.
- `odometry` is `odom_end` in `odom_start`'s frame, for comparing with `tester`.

Code: `StudioKit/Sources/StudioKit/DuckMeasure.swift` (protocol, run, report, evaluation;
`DuckMeasureTests`), `DuckStudio/Sources/MeasureDuckView.swift` (the screen, thin).

## Sizing (2026-10-15: measured in a simulator, not on a duck)

The board rule is exact; the duck is not. What is measured, each as a median with its spread
over many rows, never one run:

1. **One Walk card.** Timed, a Walk card is two seconds of a twist and its distance is whatever
   the gait makes of it (First measurement, below, and its correction). Closed on odometry, it is
   one duck square by construction, and what is measured is how far off the duck ends.
   **Measured in duckbench, then in Pollen's duck-sim on Pollen's robotd and v8 velstand
   ("Closed-loop cards: Pollen's duck-sim", below). Not on a duck.**
2. **One Turn card.** A timed turn is not a quarter turn. Closed on the IMU's yaw it is, within a
   tolerance. On duckbench's canon plant a yaw command of 1.0 with no forward speed turns the
   duck about 12 degrees and stops (this is the 14.4 degree saturation `walk_to.py` saw), and 1.5
   turns it on the spot, about 47 degrees a second, moving it 2 cm: no arc is needed. On Pollen's
   v8 velstand in duck-sim, 1.0 turns it on the spot at about 64 degrees a second and it coasts
   6 to 17 degrees after the zero twist. **Measured in duckbench and Pollen's duck-sim. Not on a
   duck.**
3. **The footprint.** The duck is about 25 cm tall and 737 to 800 g; a square must hold it with
   room to drift. A 30 cm square (every starter pack's printed square) holds it.
4. **Real ducks.** A "Measure my duck" check in Studio: 1 to 4 Walk cards and four Turns, with
   robotd's own odometry and a tape-measured mark, sent back by the tester ("Measure my duck",
   below). **Built; no duck has run it yet.**

`duck_square_cm` is the square a Walk card walks, 30 cm, the same as every starter pack's
printed `square_cm`, so on the floor one card is one taped square. Its `duck_square_source` says
it was measured in a simulator only. Packs played on a real duck still treat the goal as the
square the duck should reach and say the duck is approximate, until testers' ducks are measured.

### Closed-loop cards

A Walk forward, Walk back, Turn left or Turn right card read off Duck Cards (a plan whose model
is `duck-cards/0`, or a row the card reader runs) closes on what robotd's `robot.state` reports:
`odom.position` and `odom.yaw`, Pollen's contact odometry, whose heading is the trunk IMU's yaw.
Every other card is unchanged. One spec, two readers: `duck-card-loop.json` (StudioKit
`Resources/DuckCards/`, copied byte for byte to `cardreader/duckcards/`), stepped by
`DuckCardLoop` (StudioKit) and `cardloop.py` (the reader), held to each other by
`cardreader/vectors/cardloop/*.json`: a card, a trace of odometry samples, and the command or the
stop each sample must produce (`cardreader/tests/make_cardloop_vectors.py` writes them;
`scripts/check_duckcards_vectors.sh` checks the copies and regenerates them).

- **The board.** A row keeps the board pose in odometry's frame: the pose the duck was at when
  the first card began, then one square or one quarter turn per card. Each card aims at the board
  pose, so the next card takes back an overshoot or a turn's drift instead of adding to it. A
  skill (a kick, a roll) moves the duck in ways the board does not count, so after one the board's
  position is put back where the duck stands and its heading is kept.
- **Walk.** Walk at the card's speed along the board heading, steering
  `vyaw = heading_gain x heading error - cross_gain x (distance left of the line)` (the sign of the
  second term flips walking back), clamped to `max_yaw`. Stop when the distance along the board
  heading from the card's board pose reaches `square_m - stop_early_m` (`back_stop_early_m` walking
  back, which coasts further), or after `max_s` ("out of time"). Less than `stall_m` further along
  in `stall_s` is "stuck": the duck cannot do the card at the speeds it may be sent.
- **Turn** (`duck-card-loop/1`, 2026-10-15, from `cardreader/sim/sysid/`). Turn at the card's yaw
  rate toward the board heading plus or minus a quarter turn, and command still `lead` degrees
  short of it, because the duck coasts on: 6 to 17 degrees at 1.0 rad/s in duck-sim, 20 to 31 on
  a slippery floor with a late state. The row's first Turn card knows nothing yet and stops
  `approach_deg` (20) short; every Turn card holds still `settle_s` (0.8 s) after its first stop
  and measures how far it went on (`coast_deg`, clamped to `lead_deg`), and each later Turn card
  in the row leads by the mean of the row's measured coasts. Then done if within `tolerance_deg`
  (14), else up to `trims` trims at `trim_rate`, each stopping the measured coast short but held
  at least `trim_min_s` (0.3 s; a shorter command turns the trunk, which springs back, and never
  gets past the gait's dead band), each followed by a settle. Out of trims is "trimmed out",
  not `stall_deg` closer in `stall_s` is "stuck", and `max_s` is "out of time". Each is said, and
  the row stops there (below: a row ends at the first card that does not arrive; until
  2026-10-15 the row went on).
- **Between cards** the duck holds still for `between_s`. Commands go at `control_hz` (20 Hz); a
  pose older than `stale_s` mid-card stops the card and the row ("The duck stopped reporting
  where it is, so the row stopped there.").
- **Pollen's pad envelope bounds every card.** `pollen-pad-drive.json` (StudioKit
  `Resources/DuckCards/`, copied byte for byte to `cardreader/duckcards/`) is
  `PadDriveParams::default()` in pollen-robotics/microduck `robotd-params/src/lib.rs` (lines 144
  to 158, commit 34b6e7d): vx -0.4 to 0.4 m/s, vy -0.3 to 0.3, vyaw -1.0 to 1.0 rad/s, "what
  [the v8 velstand] follows well on the robot". Its training range for yaw is the same -1.0 to
  1.0. robotd has no velocity clamp of its own (`duck-control/src/safety.rs`: deadman,
  non-finite, travel; the pad is bounded, other clients are not), so this side holds it:
  `DuckCardLoop.envelopeProblems` and `cardloop.envelope_problems` name any number in the spec
  past it, both readers' tests fail on one, and so does `scripts/check_duckcards_vectors.sh`.
  Studio's sticks are held inside it too (`DuckDrive.maxTurn` is 1.0, was 1.5).
- **Speed cards on a distance card** set the speed, not the distance: Walk forward walks at
  0.30, 0.35 or 0.40 (Slow, Normal, Fast). Walk back walks at 0.40 at every speed and a Turn card
  turns at 1.0 at every speed, the envelope's limits. **On Pollen's v8 velstand in duck-sim all of
  them clear the dead band** (`cardreader/sim/sysid/`, steps through `robot.move`): it stands
  still up to 0.20 forward and walks every time from 0.25; stands still up to -0.30 and walks
  back every time from -0.35; turns in place every time from 0.625 rad/s left and 0.5 right, at
  about 64 degrees a second at 1.0. duckbench's canon plant needed more (about 0.45 back, 1.2 to
  turn in place); the duckbench numbers below were measured with the unclamped spec on that
  plant.
- **The off switch.** `duck-card-loop.json` carries `"enabled_on_robot": false` and
  `"validated": null`, read by both StudioKit (`DuckCardLoop.spec.enabledOnRobot`) and the reader
  (`cardloop.ENABLED_ON_ROBOT`). Off, `RobotPlan` turns a Duck Cards plan's Walk and Turn into
  timed moves and the runner says `DuckCardLoop.offNote` once (the reader: `cardloop.OFF_NOTE`,
  the same words), and the board in Studio, on paper and in the reader's `--challenge` report
  stays the board rule beside that sentence. Tests on both sides pin the default to false and the
  sentence. Two ways run them on a robot anyway, both labelled: the reader's developer flag
  `watch --measured-cards` (for duck-sim work; it says "DEVELOPER: --measured-cards is on." when
  it starts), and Studio's "Measure my duck" screen, which is a test and says so.
- **A row ends at the first card that does not arrive**: out of time, trimmed out, a pose gone
  stale (mid-card, or missing when the next card starts), or robotd's `safety.fallen`. The duck
  is commanded still, one sentence says which (`RobotPlanRunner.CardEnd.said`, `runner.ENDED`,
  the same words), and the row stops there (`Outcome.stopped`; the reader returns "stopped at
  ..."). A row on a duck that never reported odometry runs timed from its first card, as below. Studio has no
  developer setting to hang a switch on, so it offers none. The switch turns on only when every
  rung of "Acceptance" passes, with `validated` citing the results.
- **When robotd does not report odometry** (no `odom` in its state, as from a robotd older than
  the estimator, or no state stream at all), Walk and Turn run as the timed cards they were, two
  seconds of Studio's twist, and the runner says once per row: "This duck does not report
  odometry, so Walk and Turn cards run as timed cards, two seconds each, and do not land on board
  squares." Studio subscribes to the state stream before a card plan runs; the card reader keeps
  its fall watch's latest frame at 20 Hz for the same purpose.

### Closed-loop cards: Pollen's duck-sim, 2026-10-15 (Acceptance, rung 1)

**Method.** Pollen's own robotd (pollen-robotics/microduck `d7560ef`) driving Pollen's v8
velstand (the Hub's `microduck-policies` v8) in duck-sim's MuJoCo body (microduck_rl develop
`b02fdea4`), the card reader's runner closing Walk and Turn on the `odom` robotd reports, under
`duck-card-loop/1` (sha256 `96df70b5`); MuJoCo's trunk scores, the controller never sees it.
First, why duck-sim did not walk (docs/POLLEN-ISSUE-duck-sim-walk.md: duck-sim pins the retired
`alpha_walking` + `alpha_stand` pair, and every command tried was under the gait's dead band);
then system identification through `robot.move` only (`cardreader/sim/sysid/`: dead bands,
delays, time constants, gains, coast, the deadman, the state rate a client sees, odometry against
truth); then the controller re-tuned from it (stuck exit, caps inside 8 s and 6 s, a Turn card
that measures its coast and leads by it); then the Monte Carlo, 4,128 rows
(`cardreader/sim/results/`, RESULTS.md has every number and interval; the conditions and how
each knob was applied are in its README). Every command stayed inside Pollen's pad envelope and
v8's training ranges (both vx +-0.4 m/s, vyaw +-1.0 rad/s).

**The pre-registered rows** (duckbench's seven and Measure my duck's five; position and heading
over rows that finished, median / p95 / max; a row that ended early fails both):

| condition | rows | position within 10 cm | position error | heading within 15 degrees | heading error | falls (Wilson upper) | time | ending badly |
|---|---|---|---|---|---|---|---|---|
| nominal, 20 Hz | 455 | **PASS** 98.7% | 2.3 / 4.7 / 6.0 cm | **PASS** 98.7% | 2.5 / 9.8 / 14.0 deg | **PASS** 0 (0.84%) | **PASS** | **PASS** 6 of 6 |
| randomized, 20 Hz | 455 | **PASS** 96.9% | 3.5 / 8.0 / 13.4 cm | **PASS** 96.7% | 3.9 / 12.3 / 35.3 deg | **PASS** 0 (0.84%) | **PASS** | **PASS** 7 of 7 |
| randomized, 10 Hz | 455 | **PASS** 97.1% | 3.4 / 7.5 / 10.7 cm | **PASS** 96.9% | 3.8 / 12.1 / 16.6 deg | **PASS** 0 (0.84%) | **PASS** | **PASS** 8 of 8 |
| stressed, 10 Hz | 455 | **FAIL** 86.8% | 5.3 / 11.2 / 15.7 cm | **FAIL** 87.3% | 6.3 / 16.5 / 23.4 deg | **PASS** 0 (0.84%) | **PASS** | **PASS** 26 of 26 |

**The rows with Walk back, on their own** (403 per condition; F F B and F(slow) F(fast) L(slow)
F R(fast) B(slow)): nominal **PASS** (99.3%, 99.3%, 0 falls, upper 0.94%); randomized **PASS**
(96.8%, 98.3%); randomized at 10 Hz **FAIL** on position (92.8%; heading 96.0%); stressed
**FAIL** (79.9%, 84.1%). Walk back overshoots: it coasts 3 to 4 cm nominal and more with a late
state, so the last Walk back ends 10 to 14 cm off in the failing rows.

**Times.** No card past its bound in any condition: a Walk card p95 3.2 to 3.5 s (max 4.0 s
against 8), a Turn card p95 2.4 to 4.6 s (max 5.4 s against 6), over 13,826 Walk and 6,558 Turn cards.

**Ending badly.** 148 of 4,128 rows ended early, every one with the duck commanded still, one
sentence and a stop: 147 Turn cards trimmed out (most under stress) and one Walk back stuck (it
did not start backing in 2 s on the slippery floor). No row fell, lost its state or ran out of
time, so those three exits are held by unit tests and vectors only, not by the simulator.

**Rung 1 verdict: not passed.** Nominal and randomized (20 Hz) pass every criterion, Walk back
included. Randomized at Studio's 10 Hz fails on Walk back's position (92.8% against 95%), and the
stressed condition (every range at its far end at once) fails position and heading: a 5%
odometry scale error and a 0.5 degree-a-second IMU drift are invisible to a controller that
closes on that odometry, and in-place turns coast 20 to 31 degrees on that floor with that
latency. `enabled_on_robot` stays false and the packs' `duck_square_*` fields are unchanged.

**The packs' own rows** (not pre-registered, reported): every challenge `solution` of the four
starter packs (2 to 28 cards) with the hand rows, about 200 rows per condition. Nominal passes
(99.5%, 99.5%). Under randomization the long rows fail: odometry error grows with the distance
and time of a row (loop-9's 28 cards take about 90 s; 0.5 degrees a second of IMU drift is 45
degrees by its end), so position within a third of a square holds for 79% (20 Hz) and 77%
(10 Hz) of rows, and 44% stressed. Short rows behave like the pre-registered ones (RESULTS.md, by
row).

**The square.** 30 cm stays: a Walk card takes about 2.8 s (median) at 0.35 m/s commanded, well
inside 8 s; the errors that fail rows are proportional to how far and how long a duck goes, so a
smaller square would not shrink them relative to the square, and a larger one would make a card
slower and a board larger than a classroom floor. Nothing in the data argues for changing it.

**Not verified.** A real duck: none has run a closed-loop card (rung 3, Measure my duck). A second
machine (rung 2) ran on 2026-10-16, a fresh checkout on Hugging Face Jobs x86
(`cardreader/sim/results/rung2-hf/`): 38 of 40 verdicts matched; the two that differ are both heading at
randomized 10 Hz (pre-registered rows PASS 96.9% here, FAIL 94.9% there, a same-Pi repeat in
`results/repro/` 93.8%; Walk back rows PASS 96.0% here, FAIL 93.8% there), so that criterion sits
on the line and counts as failing; no falls in 4,128 rows there. duck-sim's body drives the scene's position
servos, which `infer_policy.py` says are not the actuator v8 was trained with; real servos, real
floors, a real IMU's drift and real foot slip are modelled only by the randomized ranges. The
fall, stale-state and out-of-time exits never fired in the simulator. Studio's Swift runner ran
its unit tests and vectors on Linux, not against duck-sim.

### Candidate change: the Walk lead (`duck-card-loop/2`), Pollen's duck-sim, 2026-10-16

**A candidate on branch `duck-packs-walkback`, not adopted (this branch keeps `/1`; the record is in `cardreader/sim/results-walkback/`); `enabled_on_robot` stays false and
"Acceptance" is unchanged.** Walk cards get the lead Turn cards have: the row's first Walk card
each way stops `approach_m` (0.022 forward) or `back_approach_m` (0.052 back) short, plus
`back_slip_m` (0.013) walking back, holds still `settle_s` (0.4) or `back_settle_s` (0.8),
measures its coast on odometry, and later Walk cards the same way lead by the row's mean coast.
Every number is from the system identification (`cardreader/sim/results-walkback/WALK_LEAD.md`:
odometry's coast plus half a frame gap and half a control tick at 10 Hz; the slip is odometry
counting 0.956 of the trunk's distance walking back). Which of them to keep was decided on
development seeds 101 to 104 only; the evaluation ran once, on fresh seeds (211 to 214, 221 to
224, 241 to 244), 400 rows per condition per batch, 4,800 rows
(`cardreader/sim/results-walkback/`, `COMPARE.md` has every criterion with its interval).

| rows, condition | criterion | fcefea3 (`/1`) | candidate (`/2`) |
|---|---|---|---|
| Walk back, randomized 10 Hz | position | **FAIL** 92.8% [89.9, 94.9] | **PASS** 97.0% [95.0, 98.1] |
| Walk back, randomized 10 Hz | heading | **PASS** 96.0% [93.6, 97.5] | **FAIL** 93.5% [91.0, 95.4] |
| Walk back, stressed 10 Hz | position | **FAIL** 79.9% [75.7, 83.5] | **FAIL** 88.4% [85.3, 91.0] |
| Walk back, stressed 10 Hz | heading | **FAIL** 84.1% [80.2, 87.4] | **FAIL** 73.4% [69.4, 77.1] |
| pre-registered, randomized 10 Hz | position | **PASS** 97.1% [95.2, 98.3] | **FAIL** 94.7% [92.4, 96.3] |
| pre-registered, randomized 10 Hz | heading | **PASS** 96.9% [94.9, 98.2] | **FAIL** 93.9% [91.5, 95.7] |
| pre-registered, stressed 10 Hz | position | **FAIL** 86.8% [83.4, 89.6] | **FAIL** 85.7% [82.4, 88.5] |
| pre-registered, every condition | falls | **PASS** 0 in each | **FAIL** 4, 2, 3, 2 (upper 2.00, 1.42, 1.72, 1.42%) |
| packs' rows of 10 cards or more, randomized 10 Hz | position | 41.7% [30.1, 54.3] | 21.7% [15.2, 29.9] |

Walk back now lands (median 3.4 cm off at 10 Hz, was 5.8) but ends further off its heading:
the duck yaws in its coast and settle, and nothing steers then. The falls cluster in rows run
while a reproduction of fcefea3 shared the machine and its bodies fell behind real time (that
reproduction, on `/1`, fell three times in the same hours); they count as measured. The long
rows got worse: each settle makes a row longer and the IMU drift that fails them has longer to
act. **Rung 1 is not passed with this candidate either**, and it is not an improvement overall:
it trades Walk back position for Walk back heading and long rows. Not verified: a quiet machine,
a second machine, a duck.

**Rerun on HF Jobs x86, 2026-10-17** (`cardreader/sim/results-walkback/hf-rerun/`, same commit,
same seeds, idle machine, no frame behind real time): **0 falls in 4,800 rows**, so the falls above
were the loaded Pi. Everything else reproduced. Against `/1` on the same kind of machine (rung 2):
Walk back position at randomized 10 Hz FAIL 93.1% → PASS 96.3%; Walk back heading, randomized,
PASS 98.3% → FAIL 92.5%; long rows' position at randomized 10 Hz 36.7% → 20.0%. Not adopted.

### Closed-loop cards: duckbench, 2026-10-15

**Measured with the first spec, before it was clamped to Pollen's envelope** (Walk forward Fast
0.45, Walk back 0.45, Turn 1.5). The shipped spec is not this one, and nothing below has been
measured with it. Kept as what was measured.

`duckbench/sim/cardloop.mjs` (results and the sweeps that chose the numbers in
`duckbench/sim/cardloop/`): duckbench's canon plant (`scene.mjb`, Pollen's MJCF with their servo
class) under `alpha_walking.onnx`, through the bench's own live lane, running
`duck-card-loop.json` as above. The controller reads only what robotd would report: odometry
computed the way Pollen's `odometry` crate computes it (ALPHA16 sole anchors, forward kinematics
of the reported joints, the trunk orientation as the IMU's), 40 ms old, at 50 Hz and again at
Studio's 10 Hz subscription; ground truth only scores. Seven rows (F F L F R F; F R F R F R F R;
F L L F; F F B; F(slow) F(fast) L(slow) F R(fast) B(slow); L L R R; F F F F), ten starts each at
different gait phases, at both rates. Error is where the duck ended against the board rule at
30 cm a square, in the row's own frame.

| what | measured |
|---|---|
| duck square | **30 cm** |
| rows | **140** (700 cards, every one arrived) |
| falls | **0** |
| position error, rows without Walk back | median **2.5 cm**, max **4.6 cm** (100 rows) |
| position error, rows with Walk back | median **3.8 cm**, max **6.4 cm** (40 rows) |
| heading error, rows without Walk back | median **3.6 degrees**, max **10.3 degrees** |
| heading error, rows with Walk back | median **7.5 degrees**, max **22.9 degrees** |
| one Walk card, ground truth | median 30.6 cm [27.5 to 35.4] at 50 Hz, 32.3 cm [27.8 to 36.3] at 10 Hz |
| one Turn card, from its own start | median 91 degrees [81 to 104] (it also takes back the card before's heading) |
| time | a Walk card median 2.1 s (max 2.6), a Turn card 2.4 s (max 3.8), then 0.5 s still |
| odometry against truth at a row's end | median 1.1 cm, max 2.6 cm |

Square sizes 20, 25, 30 and 40 cm ended rows equally close (no falls in any), so 30 cm was
chosen for the floor: it is every starter pack's printed square, it holds the duck, and a Walk
card takes about two seconds. The 10 Hz state Studio subscribes at ends rows about a centimetre
further off than 50 Hz; the bounds above are the worse of the two.

What this does and does not say. In this simulator, a duck that reports odometry, running these
cards, ended a row within 4.6 cm of the board's square (6.4 cm with Walk back) and within 10.3
degrees of its heading (22.9 with Walk back, which veers). It says nothing yet about Pollen's
duck-sim, where robotd computes `odom` itself and stands the duck on its standing policy between
cards, or about a real duck: the odometry here was fed exact joint angles and an exact trunk
orientation, where a real IMU's yaw drifts and real feet slip on a classroom floor. Packs carry
this as `duck_square_source`, and every page and screen that mentions a duck square says it was
measured in a simulator.

### First measurement: duckbench, 2026-10-15

`duckbench/sim/cardsize.mjs`: this repo's MuJoCo model of the duck with `alpha_walking.onnx`,
rows of four identical cards, 2.0 s each, at Studio's own twists (walk 0.3 m/s x share, turn
1.5 rad/s x share), ten starts at different gait phases. Medians, with the range in brackets.

| card | Slow | Normal | Fast |
|---|---|---|---|
| Walk forward | does not move (0.4 cm) | **14 cm** [11 to 38], veers 11 to 15 degrees per card, never fell | 13 to 31 cm, fell in half the rows |
| Walk back | does not move | does not move (0.1 cm) | 17 to 24 cm, fell in 9 of 40 cards |
| Turn left | 9 degrees, then nothing | first card 81 degrees [55 to 105], later cards anywhere, fell in 8 of 40 | first card 108 degrees, fell in 17 of 40 |
| Turn right | 6 degrees, then nothing | first card 81 degrees [62 to 177], fell in 7 of 40 | first card 112 degrees, fell in 16 of 40 |

What it says, for this model only (not Pollen's duck-sim and not a real duck):

- **Slow is a dead band.** 0.1 m/s and 0.5 rad/s sit under the gait's threshold (duckbench
  measured about 0.25 command before), so a Slow card makes the duck stand still. Speed cards
  should not be in the youngest packs until that changes.
- **Only Normal Walk forward is dependable,** about 14 cm per card, but it turns the duck 11 to
  15 degrees each time. Four cards in a row end well off the line.
- **Walk back at Normal does not move,** so `duck-maze`'s Walk back challenges cannot run on
  this duck as timed cards.
- **Timed turns are not quarter turns and they topple the duck.** The first Normal turn lands
  near 81 degrees; a second one, started from a moving gait, goes anywhere.

So, for a duck, the board rule needs closed-loop cards: Walk forward = walk until odometry says
one square, holding heading on the IMU; Turn = turn until the IMU says 90 degrees, slowly enough
not to fall. That is what "Closed-loop cards" above does.

**Correction, the same day.** `cardsize.mjs` ran on `scene.xml`, the floor-and-box-soles plant
with invented kp 9 servos that duckbench retired as its canon on 2026-08-27, and with DuckKit's
on-robot loop (0.9 action scale, low-pass) rather than the bench's training loop. The same timed
rows on the canon plant (`cardloop.mjs canon`, `duckbench/sim/cardloop/canon-timed.json`): Slow
and Normal move nothing (walks 0 to 1 cm, turns 0 to 52 degrees, median 11 or less); Fast Walk
forward carries the duck 26 cm [22.6 to 26.9]; Fast turns land at 88 and 95 degrees; Walk back
does not move at any of Studio's speeds; nothing fell in 120 rows. The table above is kept as
what was measured; its 14 cm, its falls and its veer belong to the retired plant.
