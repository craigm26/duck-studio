"""A copy of Pollen's duck-sim scene with Duck Cards in it, in front of the duck.

    $MICRODUCK_RL/.venv/bin/python cardreader/sim/scene.py --from-duck card.xml kick_right.png --dist 0.30
    $MICRODUCK_RL/.venv/bin/python cardreader/sim/scene.py --from-duck row.xml \\
            start.png,greet.png,walk_forward.png,turn_left.png,kick_right.png,end.png --dist 0.35
    $MICRODUCK_RL/.venv/bin/python cardreader/sim/scene.py --from-duck floor.xml \\
            start.png,roll.png,end.png --floor --dist 0.22
    python3 cardreader/sim/scene.py held.xml kick_right.png --dist 0.30 --yaw -15.7 --origin 0.089,-0.010

Writes a copy of microduck_rl's `scene.xml` (its `develop` branch, where the
head camera is) with each card a plate 63.5 x 88.9 mm, textured with its
picture (`card_png.py`), laid left to right as the duck sees them. Standing
(the default): upright and facing the duck like a card held up or a row in a
rail, centred `--z` above the floor, its middle `--dist` ahead of the head
camera. `--floor`: lying flat with its top away from the duck, the way a class
lays a row on the floor. The plates touch nothing, so the duck cannot trip on
them. Pollen's files are not changed; pass the copy to duck-sim as
`DUCK_SIM_SCENE`.

WHERE THE DUCK REALLY STANDS. The defaults put the row in front of the head
camera at the scene's STAND pose, but the duck does not end up there: across
seven bring-ups on 2026-10-14 it settled facing anywhere from -16.6 to +19.5
degrees, its head camera 3 to 6 cm further forward than at STAND. So bring the
duck up first (`up.sh` with no scene), then `--from-duck` reads where its head
camera is and which way it faces from duck-body, the way duck-sim's own
`upright_at` reads a duck, and lays the cards in front of that; `look.sh`
shows the duck the new scene without stopping it. `--from-duck` needs mujoco
and microduck_rl: run it with `$MICRODUCK_RL/.venv/bin/python`. `--yaw` and
`--origin` place the row by hand instead.

WITHOUT A GPU THE SCENE IS LIGHTER BY DEFAULT: no shadow, no floor reflection, no
multisampling (`--full-quality` keeps them). Software rendering of this duck
(431,802 triangles) costs about 566 ms a frame with them and 114 ms without.
"""

from __future__ import annotations

import argparse
import math
import os
import pathlib
import sys

CAM_X = 0.0643                  # the head camera's x at the scene's STAND keyframe, metres
W, H = 0.0635, 0.0889           # a card, metres


def camera_now(robot: pathlib.Path, rl: str, address: str):
    """Where the running duck's head camera is, and which way it faces (radians), from duck-body.

    duck-body is asked the way duck-sim's `upright_at` asks it (a read-only hello and read), and
    the scene's own model is posed from the answer, as `eye.py` poses it. The model's head camera
    faces backwards (microduck_rl's `Camera` turns it round to render it), so it is turned the same
    half turn about its own right axis here before its direction is read."""
    import json
    import socket
    sys.path.insert(0, str(pathlib.Path(rl).expanduser().resolve() / "src"))
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import mujoco
    import numpy as np
    from eye import Mirror
    mirror = Mirror(robot / "scene.xml")
    cam = mujoco.mj_name2id(mirror.model, mujoco.mjtObj.mjOBJ_CAMERA, "head_camera")
    turned = np.zeros(4)
    mujoco.mju_mulQuat(turned, mirror.model.cam_quat[cam], np.array([0.0, 1.0, 0.0, 0.0]))
    mirror.model.cam_quat[cam] = turned
    host, port = address.rsplit(":", 1)
    with socket.create_connection((host, int(port)), timeout=5) as body:
        f = body.makefile("rw")
        f.write(json.dumps({"op": "hello", "protocol": 1, "joints": 15}) + "\n")
        f.flush()
        f.readline()
        f.write('{"op":"read"}\n')
        f.flush()
        mirror.pose(json.loads(f.readline()))
    pos = mirror.data.cam_xpos[cam]
    ahead = -mirror.data.cam_xmat[cam].reshape(3, 3)[:, 2]        # a MuJoCo camera looks down its -z
    return (float(pos[0]), float(pos[1]), float(pos[2])), math.atan2(float(ahead[1]), float(ahead[0]))


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("out", help="the scene to write")
    p.add_argument("cards", nargs="?", default="",
                   help="card pictures, comma-separated, left to right as the duck sees them (none: no cards)")
    p.add_argument("--rl", default=os.environ.get("MICRODUCK_RL"),
                   help="a checkout of pollen-robotics/microduck_rl (develop); default $MICRODUCK_RL")
    p.add_argument("--dist", type=float, default=0.30, help="metres from the head camera to the row's middle")
    p.add_argument("--z", type=float, default=0.248, help="standing: the cards' centre height, metres")
    p.add_argument("--y", type=float, default=0.0, help="the row's middle to the duck's left, metres")
    p.add_argument("--gap", type=float, default=0.010, help="metres between cards")
    p.add_argument("--yaw", type=float, default=0.0, help="degrees: face a duck heading this way")
    p.add_argument("--origin", default=None, help="x,y of the head camera the row faces (default: at STAND)")
    p.add_argument("--from-duck", action="store_true",
                   help="face the row to the running duck's head camera, read from duck-body; "
                        "standing cards go at its height")
    p.add_argument("--body", default="127.0.0.1:7801", metavar="HOST:PORT",
                   help="duck-body, for --from-duck (duck-sim's first duck: 127.0.0.1:7801)")
    p.add_argument("--floor", action="store_true", help="lay the cards flat on the floor")
    p.add_argument("--emission", type=float, default=0.25)
    p.add_argument("--full-quality", action="store_true",
                   help="keep shadows, floor reflection and multisampling (about 5x slower in software GL)")
    a = p.parse_args()
    if not a.rl:
        p.error("say where microduck_rl is: --rl or $MICRODUCK_RL")
    robot = pathlib.Path(a.rl).expanduser().resolve() / "src/mjlab_microduck/robot/microduck"
    cards = [pathlib.Path(c).resolve() for c in a.cards.split(",") if c]
    n = len(cards)
    row_w = n * W + (n - 1) * a.gap
    ox, oy = (map(float, a.origin.split(",")) if a.origin else (CAM_X, 0.0))
    psi = math.radians(a.yaw)
    if a.from_duck:
        (ox, oy, cz), psi = camera_now(robot, a.rl, a.body)
        if not a.floor:
            a.z = cz
        print(f"the duck's head camera is at ({ox:.4f}, {oy:.4f}, {cz:.4f}), facing {math.degrees(psi):.1f} degrees")
    assets, geoms = [], []
    for i, c in enumerate(cards):
        lat = a.y + row_w / 2 - W / 2 - i * (W + a.gap)          # + is the duck's left
        x = ox + a.dist * math.cos(psi) - lat * math.sin(psi)
        y = oy + a.dist * math.sin(psi) + lat * math.cos(psi)
        rx, ry = math.sin(psi), -math.cos(psi)                     # the duck's right
        if a.floor:
            # Flat, its top away from the duck: the plate's y axis points ahead, its normal up.
            pos, axes = f"{x:.4f} {y:.4f} 0.0010", f"{rx:.5f} {ry:.5f} 0 {math.cos(psi):.5f} {math.sin(psi):.5f} 0"
        else:
            pos, axes = f"{x:.4f} {y:.4f} {a.z:.4f}", f"{rx:.5f} {ry:.5f} 0 0 0 1"
        assets.append(f'    <texture name="card{i}" type="2d" file="{c}"/>\n'
                      f'    <material name="card{i}" texture="card{i}" texrepeat="1 1" texuniform="false" '
                      f'emission="{a.emission}" specular="0" shininess="0" reflectance="0"/>')
        geoms.append(f'    <geom name="duck_card{i}" type="plane" size="{W / 2:.5f} {H / 2:.5f} 0.01" '
                     f'pos="{pos}" xyaxes="{axes}" material="card{i}" contype="0" conaffinity="0" group="1"/>')
    src = (robot / "scene.xml").read_text()
    for old, new in [
        ('<include file="robot_groundcontact.xml" />',
         f'<include file="{robot / "robot_groundcontact.xml"}" />\n    <compiler meshdir="{robot / "assets"}"/>'),
        ("    </asset>", "\n".join(assets) + "\n    </asset>"),
        ('        <geom name="floor"', "\n".join("    " + g for g in geoms) + '\n        <geom name="floor"'),
    ]:
        if old not in src:
            sys.exit(f"microduck_rl's scene.xml has changed: cannot find {old!r}")
        src = src.replace(old, new, 1)
    if not a.full_quality:
        src = src.replace('directional="true" />', 'directional="true" castshadow="false" />', 1)
        src = src.replace('reflectance="0.2" />', 'reflectance="0" />', 1)
        src = src.replace("<visual>", '<visual>\n        <quality offsamples="0" />', 1)
    pathlib.Path(a.out).write_text(src)
    print(f"wrote {a.out}: {n} card(s) {'on the floor' if a.floor else 'standing'}, "
          f"{a.dist:.3f} m ahead of the head camera")
    return 0


if __name__ == "__main__":
    sys.exit(main())
