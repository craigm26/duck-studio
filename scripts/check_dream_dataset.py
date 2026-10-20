#!/usr/bin/env python3
"""Hold a dataset this app writes to Dream Labs' own checks.

The app writes every file but the videos in StudioKit (DreamDatasetTests, with DREAM_DATASET_OUT set) and the
videos with AVAssetWriter on a device. This gives a StudioKit-written dataset videos of the right count, size and
rate with ffmpeg (unless it already has them), then runs `dream.datasets.validate_dataset` from dreamlabs-client
1.0.1, the check Dream Labs' Upload page runs, against the duck's embodiment config.

    DREAM_DATASET_OUT=/tmp/ds swift test --filter DreamDatasetTests      # in StudioKit
    ~/venvs/dreamval/bin/python scripts/check_dream_dataset.py /tmp/ds/microduck-test

Needs: pip install "dreamlabs-client[datasets]==1.0.1", and ffmpeg on PATH.
"""
import json
import pathlib
import subprocess
import sys

# castor.dream.MICRODUCK_EMBODIMENT and DuckDream.microduck
DUCK = {"state": {"velocity": [0, 3]}, "action": {"velocity": [0, 3]}, "video": {"head": "observation.images.head"}}


def main(root: pathlib.Path) -> int:
    from dream import datasets
    import pyarrow.parquet as pq

    info = json.loads((root / "meta/info.json").read_text())
    for line in (root / "meta/episodes.jsonl").read_text().splitlines():
        ep = json.loads(line)
        i, n = ep["episode_index"], ep["length"]
        table = pq.read_table(root / f"data/chunk-000/episode_{i:06d}.parquet")
        assert table.num_rows == n, (i, table.num_rows, n)
        assert str(table.schema.field("action").type).startswith("list<"), table.schema
        mp4 = root / f"videos/chunk-000/observation.images.head/episode_{i:06d}.mp4"
        if not mp4.exists():
            mp4.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                            f"testsrc=size=320x176:rate={info['fps']}", "-frames:v", str(n),
                            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(info["fps"]), str(mp4)], check=True)
    report = datasets.validate_dataset(root, DUCK)
    print(report)
    return 0 if report.ok else 1


if __name__ == "__main__":
    raise SystemExit(main(pathlib.Path(sys.argv[1])))
