"""python3 -m duckcards read PICTURE...        what the cards in a picture say, and the plan
   python3 -m duckcards watch [options]         the duck reads cards and does them

watch, on the robot:      python3 -m duckcards watch
watch, beside duck-sim:   python3 -m duckcards watch --frame-url http://127.0.0.1:8080/frame \\
                              --robot-socket ~/.cache/duck-sim/duck-a.sock
watch, from a laptop:     python3 -m duckcards watch --frame-url http://duck.local:8080/frame \\
                              --bridge duck.local:7788 --token-file ~/.microduck-bridge-token
Add --dry-run to read and say what would be sent without sending it, and --deck class.duckcards
to read a class's own deck, with the Your cards it saved. A row longer than the picture is read
by turning the head along it (`[scan]` lines say how); --no-scan keeps the head still.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time

from . import pan
from .cards import Deck
from .layout import arrange
from .program import check_plan, plan, read
from .see import see


def _deck(path: str | None) -> Deck:
    """The starter deck, with a class's Your cards laid over it: a `.duckcards` file Studio
    exported, or any `duck-cards/0` deck file. Refused by name if it says something the reader
    cannot follow; anything it says about a printed card is left as the starter deck has it."""
    starter = Deck.load()
    if not path:
        return starter
    try:
        deck, ignored = starter.lend(json.loads(open(os.path.expanduser(path), "rb").read()))
    except (OSError, ValueError, KeyError, TypeError) as e:
        raise SystemExit(f"cannot read the deck {path}: {e}")
    if ignored:
        print(f"{path} also says something about card{'s' if len(ignored) > 1 else ''} "
              f"{', '.join(map(str, ignored))}; a number never changes what it means, so "
              f"{'they keep their' if len(ignored) > 1 else 'it keeps its'} own meaning.")
    return deck


def cmd_read(args) -> int:
    from PIL import Image
    import numpy as np
    deck = _deck(args.deck)
    status = 0
    for path in args.pictures:
        gray = np.asarray(Image.open(path).convert("L"))
        look = see(gray, deck, numbers=not args.no_numbers)
        layout = arrange(look.seen)
        program = read(layout, deck)
        print(f"{path}: {len(look.seen)} cards, rows {layout.describe()}")
        if look.foreign:
            print(f"  {look.foreign} code(s) that are not Duck Cards")
        for note in program.notes:
            print(f"  note: {note}")
        if program.steps:
            print(f"  reads: {program.words}")
            if args.plan:
                print(json.dumps(check_plan(plan(program)), indent=2))
        else:
            status = 1
    return status


class DryRobot:
    def call(self, method, params=None):
        print(f"    -> {method} {json.dumps(params) if params else ''}")
        if method == "robot.skills":
            return {"skills": [], "built_in": ["kick_left", "kick_right", "sit_toggle", "roulade", "ground_pick"]}
        if method == "robot.look":
            return {"head": {"neck_pitch": 0.0, "head_pitch": 0.0, "head_yaw": 0.0, "head_roll": 0.0},
                    "clamped": False}
        return {"accepted": True}

    def notify(self, method, params=None):
        pass


def cmd_watch(args) -> int:
    from . import duck, runner
    deck = _deck(args.deck)
    # How a card's place in the picture becomes an angle, for joining looks: the real camera's,
    # unless this is a camera with another lens (duck-sim's renders 72.7° along its long side).
    pan.LONG_SIDE_DEG = args.camera_degrees
    frames = duck.FrameURL(args.frame_url) if args.frame_url else duck.FrameSocket(args.frame_socket)
    if args.dry_run:
        robot, connect = DryRobot(), None
    elif args.bridge:
        host, port = args.bridge.rsplit(":", 1)
        token = open(os.path.expanduser(args.token_file)).read().strip()
        connect = lambda: duck.Robot.bridge(host, int(port), token)   # noqa: E731
        robot = connect()
    else:
        connect = lambda: duck.Robot.unix(os.path.expanduser(args.robot_socket))   # noqa: E731
        robot = connect()
    falls = duck.FallWatch(connect).start() if connect else None
    say = lambda s: print(s, flush=True)   # noqa: E731

    def voice(tag):
        try:
            robot.call("robot.sound", {"tag": tag})
        except Exception:
            pass

    gaze = None if args.let_head_wander else runner.Gaze(robot, runner.FLOOR_AT if args.floor else None)

    def look_again():
        try:
            if gaze:
                gaze.aim(time.time())
            elif args.floor:
                x, y, z = runner.FLOOR_AT
                robot.call("robot.look", {"x": x, "y": y, "z": z})
        except Exception as e:
            say(f"  (could not point the head: {e})")

    look_again()
    watcher = runner.Watcher(need=args.need)

    def take():
        """One picture's cards, for a scan: read the way the watcher reads, twice the size with
        --upscale because a scan's looks are few."""
        gray = frames.grab().gray
        if args.upscale:
            import cv2
            gray = cv2.resize(gray, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
        return see(gray, deck, numbers=not args.no_numbers).seen, (gray.shape[1], gray.shape[0])

    # Turning the head along a row needs the head steered, so --let-head-wander turns it off too.
    scanner = None if args.no_scan or gaze is None else runner.Scanner(
        gaze, take, deck, need=args.need, dry=args.dry_run, say=say)
    on_fall = []
    frame_n = 0
    say("watching for cards; Ctrl-C to stop")
    try:
        while True:
            t0 = time.time()
            try:
                frame = frames.grab()
            except Exception as e:
                say(f"no picture: {e}")
                time.sleep(1.0)
                continue
            frame_n += 1
            gray = frame.gray
            if args.upscale and frame_n % 2 == 0:       # every other look, twice the pixels
                import cv2
                gray = cv2.resize(gray, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
            seen = see(gray, deck, numbers=not args.no_numbers).seen
            layout = arrange(seen)
            program = read(layout, deck)
            if scanner:
                try:
                    program = scanner.read(pan.Look(seen=seen, yaw=gaze.yaw, size=(gray.shape[1], gray.shape[0])),
                                           layout, program)
                except Exception as e:      # a scan that fails leaves the duck reading what it sees
                    say(f"  (could not scan: {e})")
                    look_again()
            event = watcher.feed(program, time.time())
            if event:
                say(f"[{event.kind}] {event.program.words or '(nothing to run)'}")
                for note in event.program.notes:
                    say(f"  note: {note}")
                if event.kind == "unfinished":
                    voice("inquire")
                else:
                    voice("chirp" if event.kind == "card" else "greet")
                    on_fall = event.program.on_fall or on_fall
                    if event.kind == "row":
                        time.sleep(args.hands_off)
                    try:
                        # A row cannot walk a duck whose policy is off. The pad's Start turns it on;
                        # so does this, and only when there is something to run, never at startup.
                        robot.call("robot.enable", {"on": True})
                        outcome = runner.run(runner.beats(event.program.steps), robot, heads=args.heads, say=say)
                    except runner.Refusal as r:
                        outcome = str(r)
                        voice("alarm")
                    say(f"  {outcome}")
                    look_again()
            if falls and falls.recovered.is_set():
                falls.recovered.clear()
                if on_fall:
                    say("[fell] running the When it falls row")
                    runner.run(runner.beats(on_fall), robot, heads=args.heads, say=say)
                    look_again()
            if gaze:
                try:
                    gaze.tick(time.time())
                except Exception:
                    pass
            time.sleep(max(0.0, 1.0 / args.hz - (time.time() - t0)))
    except KeyboardInterrupt:
        pass
    finally:
        try:
            robot.call("robot.stop")
        except Exception:
            pass
        if falls:
            falls.stop()
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="python3 -m duckcards", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("read", help="read the cards in pictures")
    r.add_argument("pictures", nargs="+")
    r.add_argument("--plan", action="store_true", help="print the duck-intent-plan/0 too")
    r.add_argument("--deck", help="a class's deck file (.duckcards), with its Your cards")
    r.add_argument("--no-numbers", action="store_true", help="do not read the number written on Repeat; ask for it")
    r.set_defaults(fn=cmd_read)
    w = sub.add_parser("watch", help="the duck reads cards and does them")
    w.add_argument("--frame-socket", default="/run/mediad/media.sock")
    w.add_argument("--frame-url", help="http://host:8080/frame instead of the socket")
    w.add_argument("--robot-socket", default="/run/robotd.sock")
    w.add_argument("--bridge", help="host:port of microduck-bridge instead of robotd's socket")
    w.add_argument("--token-file", default="~/.microduck-bridge-token")
    w.add_argument("--floor", action="store_true", help="look down at a row on the floor")
    w.add_argument("--heads", action="store_true", help="send Look cards as robot.look (Studio does not yet)")
    w.add_argument("--let-head-wander", action="store_true",
                   help="do not hold the head still while watching; robotd's idle look-around then "
                        "takes a held card out of the picture and it is read again (and nothing is scanned)")
    w.add_argument("--no-scan", action="store_true",
                   help="do not turn the head along a row that runs off the picture; read what one look sees")
    w.add_argument("--camera-degrees", type=float, default=pan.LONG_SIDE_DEG,
                   help="the camera's view along the picture's long side, degrees: 62 on a Microduck "
                        "(the default); 72.7 for duck-sim's head camera, which joining looks needs")
    w.add_argument("--hz", type=float, default=4.0, help="pictures a second (default 4)")
    w.add_argument("--need", type=int, default=3, help="pictures in a row that must agree (default 3)")
    w.add_argument("--hands-off", type=float, default=1.5, help="seconds between reading a row and running it")
    w.add_argument("--upscale", action="store_true", help="every other picture at twice the size: farther cards, more CPU")
    w.add_argument("--deck", help="a class's deck file (.duckcards), with its Your cards")
    w.add_argument("--dry-run", action="store_true", help="read and say, send nothing")
    w.add_argument("--no-numbers", action="store_true", help="do not read the number written on Repeat; ask for it")
    w.set_defaults(fn=cmd_watch)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
