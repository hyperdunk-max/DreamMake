"""Trim sprite sheet: crop each frame to content bbox, pad to uniform size, repack.

Strategy:
  - Compute per-frame content bbox (non-transparent pixel bounds)
  - Determine uniform padded size = max(bbox_w) x max(bbox_h) across all frames
  - Each frame gets trimmed, then centered/padded to uniform size
  - Repack into new grid + update JSON with per-frame offsets

This gives Godot-compatible uniform-sized sprite sheets with 80-99% less wasted space.
"""

import json
import math
import sys
from pathlib import Path
from PIL import Image
Image.MAX_IMAGE_PIXELS = None


def trim_and_repack(sprite_dir: str, dry_run: bool = True):
    d = Path(sprite_dir)
    png_path = d / "sprite.png"
    json_path = d / "sprite.json"

    if not png_path.exists() or not json_path.exists():
        print(f"  SKIP: no sprite sheet found")
        return

    with open(json_path) as f:
        meta = json.load(f)

    fw = meta["meta"]["frameSize"]["w"]
    fh = meta["meta"]["frameSize"]["h"]
    cols = meta["meta"]["columns"]
    count = meta["meta"]["frameCount"]
    frame_names = list(meta["frames"].keys())

    img = Image.open(png_path)

    # === Pass 1: Find per-frame bboxes ===
    bboxes = []
    for fi in range(count):
        row, col = divmod(fi, cols)
        x, y = col * fw, row * fh
        frame = img.crop((x, y, x + fw, y + fh))
        alpha = frame.getchannel("A")
        bbox = alpha.getbbox()
        if bbox is None:
            bbox = (0, 0, 1, 1)  # fully transparent -> 1x1
        bboxes.append(bbox)

    # Max bbox dimensions (with 1px padding)
    max_w = max(b[2] - b[0] for b in bboxes) + 2
    max_h = max(b[3] - b[1] for b in bboxes) + 2

    # Check if trimming is worthwhile
    original_px = fw * fh * count
    trimmed_px = max_w * max_h * count
    saving = 1 - trimmed_px / original_px

    if saving < 0.05:
        if not dry_run:
            print(f"  SKIP: only {saving:.1%} saving, not worth it")
        return

    rel = d.relative_to(Path("D:/DreamMake/assets/extracted/classified/zmxiyou1/怪物"))
    if dry_run:
        print(f"  {rel}: {fw}x{fh} -> {max_w}x{max_h} per frame ({saving:.1%} saving, {count}fr)")
        return

    # === Pass 2: Build new sprite sheet ===
    new_cols = math.ceil(math.sqrt(count))
    new_rows = math.ceil(count / new_cols)
    new_sheet = Image.new("RGBA", (new_cols * max_w, new_rows * max_h), (0, 0, 0, 0))
    new_frames = {}

    for fi in range(count):
        # Extract original frame
        row, col = divmod(fi, cols)
        ox, oy = col * fw, row * fh
        frame = img.crop((ox, oy, ox + fw, oy + fh))

        # Trim to bbox
        b = bboxes[fi]
        content = frame.crop(b)

        # Place in new sheet at (0,0) in each frame slot
        nr, nc = divmod(fi, new_cols)
        nx, ny = nc * max_w, nr * max_h

        # Center or left-top? Left-top preserves relative position awareness
        # Actually paste at (1,1) with 1px padding
        new_sheet.paste(content, (nx + 1, ny + 1), content)

        # Store frame info with original offset
        name = frame_names[fi]
        new_frames[name] = {
            "x": nx,
            "y": ny,
            "w": max_w,
            "h": max_h,
            "ox": b[0],  # original offset within the old frame
            "oy": b[1],
            "cw": b[2] - b[0],  # content size
            "ch": b[3] - b[1],
        }

    # Save
    new_png = d / "sprite_trimmed.png"
    new_json = d / "sprite_trimmed.json"
    new_sheet.save(new_png, optimize=True)

    new_meta = {
        "frames": new_frames,
        "meta": {
            "image": "sprite_trimmed.png",
            "size": {"w": new_cols * max_w, "h": new_rows * max_h},
            "frameSize": {"w": max_w, "h": max_h},
            "columns": new_cols,
            "rows": new_rows,
            "frameCount": count,
            "trimmed": True,
            "originalFrameSize": {"w": fw, "h": fh},
        },
    }
    with open(new_json, "w", encoding="utf-8") as f:
        json.dump(new_meta, f, ensure_ascii=False, indent=2)

    print(f"  {rel}: {fw}x{fh} -> {max_w}x{max_h} ({saving:.1%} saved, {original_px:,} -> {trimmed_px:,} px)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python trim_sprites.py <sprite_dir> [--execute]")
        print("   or: python trim_sprites.py --all [--execute]")
        sys.exit(1)

    if sys.argv[1] == "--all":
        base = Path("D:/DreamMake/assets/extracted/classified/zmxiyou1/怪物")
        dry = "--execute" not in sys.argv
        targets = sorted(p for p in base.rglob("sprite.png") if p.parent.name not in ("",))
        print(f"Found {len(targets)} sprite sheets")
        print(f"Mode: {'DRY RUN' if dry else '*** EXECUTE ***'}")
        print("-" * 70)
        for sp in targets:
            trim_and_repack(str(sp.parent), dry_run=dry)
        if dry:
            print("-" * 70)
            print("Run with --execute to apply")
    else:
        dry = "--execute" not in sys.argv
        trim_and_repack(sys.argv[1], dry_run=dry)
