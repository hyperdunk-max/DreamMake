#!/usr/bin/env python3
"""Join naturally numbered PNG frames into one transparent horizontal strip."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from PIL import Image


def natural_key(path: Path) -> list[int | str]:
    return [int(part) if part.isdigit() else part for part in re.split(r"(\d+)", path.stem)]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames-dir", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    paths = sorted(Path(args.frames_dir).glob("*.png"), key=natural_key)
    if not paths:
        raise SystemExit("No PNG frames found")

    images = [Image.open(path).convert("RGBA") for path in paths]
    width = max(image.width for image in images)
    height = max(image.height for image in images)
    strip = Image.new("RGBA", (width * len(images), height), (0, 0, 0, 0))
    for index, image in enumerate(images):
        strip.alpha_composite(image, (index * width, 0))

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    strip.save(out)
    print(f"joined {len(images)} frames into {strip.width}x{strip.height}")


if __name__ == "__main__":
    main()
