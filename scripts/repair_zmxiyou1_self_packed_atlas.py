"""Remove a historical self-packed ``sprite`` frame from a sprite atlas.

The old packer could include its previous ``sprite.png`` output as one extra
input frame. This repair only accepts that exact, reviewable condition and
rebuilds the atlas from the remaining frame regions without touching the
source animation pixels.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image


def repair(atlas_json: Path, expected_frames: int) -> None:
    data = json.loads(atlas_json.read_text(encoding="utf-8"))
    frames: dict[str, dict[str, int]] = data["frames"]
    meta: dict[str, object] = data["meta"]
    if "sprite" not in frames:
        raise ValueError(f"Atlas has no self-packed 'sprite' frame: {atlas_json}")
    names = sorted(name for name in frames if name != "sprite")
    if len(names) != expected_frames:
        raise ValueError(
            f"Expected {expected_frames} retained frames in {atlas_json}, got {len(names)}"
        )
    if bool(meta.get("trimmed", False)):
        raise ValueError(f"Trimmed atlas repair is intentionally unsupported: {atlas_json}")

    atlas_png = atlas_json.with_name(str(meta.get("image", "sprite.png")))
    source = Image.open(atlas_png).convert("RGBA")
    retained: list[tuple[str, Image.Image]] = []
    sizes: set[tuple[int, int]] = set()
    for name in names:
        frame = frames[name]
        width = int(frame["w"])
        height = int(frame["h"])
        sizes.add((width, height))
        retained.append(
            (
                name,
                source.crop(
                    (
                        int(frame["x"]),
                        int(frame["y"]),
                        int(frame["x"]) + width,
                        int(frame["y"]) + height,
                    )
                ),
            )
        )
    source.close()
    if len(sizes) != 1:
        raise ValueError(f"Atlas frames are not equal-sized: {atlas_json}")
    frame_width, frame_height = next(iter(sizes))
    columns = math.ceil(math.sqrt(expected_frames))
    rows = math.ceil(expected_frames / columns)
    output = Image.new("RGBA", (columns * frame_width, rows * frame_height), (0, 0, 0, 0))
    rebuilt_frames: dict[str, dict[str, int]] = {}
    for index, (name, image) in enumerate(retained):
        x = index % columns * frame_width
        y = index // columns * frame_height
        output.paste(image, (x, y))
        rebuilt_frames[name] = {"x": x, "y": y, "w": frame_width, "h": frame_height}
        image.close()
    output.save(atlas_png, optimize=True)
    output.close()

    data["frames"] = rebuilt_frames
    data["meta"].update(
        {
            "size": {"w": columns * frame_width, "h": rows * frame_height},
            "frameSize": {"w": frame_width, "h": frame_height},
            "columns": columns,
            "rows": rows,
            "frameCount": expected_frames,
        }
    )
    atlas_json.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("atlas_json", type=Path, nargs="+")
    parser.add_argument("--expected-frames", type=int, required=True)
    args = parser.parse_args()
    for atlas_json in args.atlas_json:
        repair(atlas_json, args.expected_frames)
        print(f"Repaired {atlas_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
