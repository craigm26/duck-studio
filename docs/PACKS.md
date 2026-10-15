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
  assumed. Until it is measured, `duck_square_cm` is `null`, and no page or screen says a duck
  will land on a square.

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
  "board": { "columns": 3, "rows": 3, "square_cm": 30, "duck_square_cm": null },
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
  distance of one Walk forward card, or `null`.
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
  "hint": "Count the squares before you lay a card."
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
   score and par. "Run on the duck" sends the same row as a plan, as rows already do. Design a
   level adds a challenge editor (tap squares for start, goal, walls, gates; par is computed)
   and saves challenges into a class pack that shares as `.duckpack`.
3. **Card reader.** `python3 -m duckcards watch --pack get-to-the-pond.duckpack [--challenge
   pond-3]`: notes cards not in play, lends the pack's Your cards, and with a challenge prints
   the board play of each row it runs. It still runs what it reads; the board play is a report.

## Not promised

- That a duck lands on a square. Not until `duck_square_cm` is measured, and then only as a
  measurement with its spread.
- Physics-sim goal checks. Placing the board in Studio's simulated world needs the same
  measurement; until then Studio's board is the board rule, and the sim duck runs the row
  beside it.

## Sizing (open, 2026-10-15)

The board rule is exact; the duck is not. Before any pack prints a board for a duck, these are
measured, each as a median with its spread, never one run:

1. **One Walk card.** Walk forward and Walk back at slow, normal and fast for `defaultSeconds`
   (2.0 s): distance along the heading, drift across it, heading change. In duckbench (this
   repo's MuJoCo model of Pollen's duck), then in Pollen's duck-sim, then on testers' ducks.
   Known before measuring: walking speeds of 0.078 to 0.23 m/s across policies, so 16 to 46 cm
   per card.
2. **One Turn card.** duckbench found that commanded yaw with no forward speed saturates at
   about 14.4 degrees (`duckbench/sim/walk_to.py`). A timed Turn card is therefore not a quarter
   turn. The question is whether a Turn card can be closed on the IMU's yaw ("turn until 90
   degrees, arcing if it must") and what square that arc needs.
3. **The footprint.** The duck is about 25 cm tall and 737 to 800 g; a square must hold it
   with room to drift.
4. **Real ducks.** A "Measure my duck" check in Studio: 1 to 4 Walk cards and four Turns, with
   robotd's own odometry and a tape-measured mark, sent back by the tester.

Then `duck_square_cm` = the median distance of one Walk card, the goal becomes a zone wide
enough for the measured spread, and the site prints the board at that size with the spread
beside it. If the Turn card cannot be made a quarter turn, packs for a real duck treat turns
and goals as zones and say so.

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
not to fall. Until robotd or the reader can do that, a pack played on a duck uses big goal zones
and says the duck is approximate. A 14 cm square is also smaller than the duck itself, so a
duck square will be several Walk cards' worth or a different card length, chosen after the same
measurement in Pollen's duck-sim and on testers' ducks.
