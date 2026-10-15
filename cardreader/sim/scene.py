"""A copy of Pollen's duck-sim scene with Duck Cards in it, in front of the duck.

    python3 cardreader/sim/scene.py --rl ~/microduck_rl scene_card.xml kick_right.png --dist 0.30
    python3 cardreader/sim/scene.py --rl ~/microduck_rl scene_row.xml start.png,walk_forward.png,end.png \\
            --dist 0.35 --yaw -15.7 --origin 0.089,-0.010
    python3 cardreader/sim/scene.py --rl ~/microduck_rl scene_floor.xml start.png,roll.png,end.png \\
            --floor --dist 0.32

Writes a copy of microduck_rl's `scene.xml` (its `develop` branch, where the
head camera is) with each card a plate 63.5 x 88.9 mm, textured with its
picture (`card_png.py`), laid left to right as the duck sees them. Standing
(the default): upright and facing the duck like a card held up or a row in a
rail, centred `--z` above the floor, its middle `--dist` ahead of the head
camera. `--floor`: lying flat with its top away from the duck, the way a class
lays a row on the floor. The plates touch nothing, so the duck cannot trip on
them. Pollen's files are not changed; pass the copy to duck-sim as
`DUCK_SIM_SCENE`.

FOUND ON 2026-10-14. The duck settles at a yaw of about -15.7 degrees after
standing up in this scene, with its head camera near (0.089, -0.010); a row put
straight ahead at the origin is then cut off on one side. `--yaw` and
`--origin` turn the row to face the duck where it actually stands.

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

CAM_X = 0.0643                  # the head camera's x at the standing pose, metres
W, H = 0.0635, 0.0889           # a card, metres


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("out", help="the scene to write")
    p.add_argument("cards", help="card pictures, comma-separated, left to right as the duck sees them")
    p.add_argument("--rl", default=os.environ.get("MICRODUCK_RL"),
                   help="a checkout of pollen-robotics/microduck_rl (develop); default $MICRODUCK_RL")
    p.add_argument("--dist", type=float, default=0.30, help="metres from the head camera to the row's middle")
    p.add_argument("--z", type=float, default=0.248, help="standing: the cards' centre height, metres")
    p.add_argument("--y", type=float, default=0.0, help="the row's middle to the duck's left, metres")
    p.add_argument("--gap", type=float, default=0.010, help="metres between cards")
    p.add_argument("--yaw", type=float, default=0.0, help="degrees: face a duck heading this way")
    p.add_argument("--origin", default=None, help="x,y of the head camera the row faces (default: at STAND)")
    p.add_argument("--floor", action="store_true", help="lay the cards flat on the floor")
    p.add_argument("--emission", type=float, default=0.25)
    p.add_argument("--full-quality", action="store_true",
                   help="keep shadows, floor reflection and multisampling (about 5x slower in software GL)")
    a = p.parse_args()
    if not a.rl:
        p.error("say where microduck_rl is: --rl or $MICRODUCK_RL")
    robot = pathlib.Path(a.rl).expanduser().resolve() / "src/mjlab_microduck/robot/microduck"
    cards = [pathlib.Path(c).resolve() for c in a.cards.split(",")]
    n = len(cards)
    row_w = n * W + (n - 1) * a.gap
    ox, oy = (map(float, a.origin.split(",")) if a.origin else (CAM_X, 0.0))
    psi = math.radians(a.yaw)
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
