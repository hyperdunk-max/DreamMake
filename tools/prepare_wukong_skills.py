#!/usr/bin/env python3
"""Prepare source-faithful Wukong skill effects for the Godot runtime.

FFDec exports several skill MovieClips on very large, fixed transparent
canvases.  Every frame in one effect is cropped by the same union alpha bounds,
which preserves the original registration point while avoiding huge imported
textures.  Pixels are never resized or repainted.

Run with ``.tools/python-portable/python.exe`` because it bundles Pillow.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (
    ROOT
    / "assets/extracted/full/zmxiyou3/characters/mixed_packages/Role1v690/sprites"
)
DESTINATION = ROOT / "assets/selected/zmxiyou3/wukong/effects/skills"

EFFECTS = {
    "lieyan_shan": "DefineSprite_78_Role1Bullet9",
    "huoyan_cast_eye": "DefineSprite_136_Role1Bullet12_1_1",
    "huoyan_cast_flare": "DefineSprite_106_Role1Bullet12_1_2",
    "huoyan_explosion": "DefineSprite_140_Role1Bullet12",
    "qishier_zhan": "DefineSprite_218_Role1Bullet13",
    "zhongzhan_charge": "DefineSprite_206_Role1Bullet14_1",
    "zhongzhan_slash": "DefineSprite_210_Role1Bullet14_2",
}


def natural_frames(directory: Path) -> list[Path]:
    return sorted(directory.glob("*.png"), key=lambda path: int(path.stem))


def union_alpha_bounds(images: list[Image.Image]) -> tuple[int, int, int, int]:
    bounds = [image.getchannel("A").getbbox() for image in images]
    visible = [box for box in bounds if box is not None]
    if not visible:
        raise ValueError("Effect contains no visible pixels")
    return (
        min(box[0] for box in visible),
        min(box[1] for box in visible),
        max(box[2] for box in visible),
        max(box[3] for box in visible),
    )


def prepare_effect(effect_id: str, symbol: str) -> dict[str, object]:
    source_directory = SOURCE / symbol
    paths = natural_frames(source_directory)
    if not paths:
        raise FileNotFoundError(f"Missing extracted effect frames: {source_directory}")
    images = [Image.open(path).convert("RGBA") for path in paths]
    canvas_size = images[0].size
    if any(image.size != canvas_size for image in images):
        raise ValueError(f"Effect frames do not share a canvas: {symbol}")
    crop = union_alpha_bounds(images)
    sprite_offset = (
        (crop[0] + crop[2] - canvas_size[0]) / 2.0,
        (crop[1] + crop[3] - canvas_size[1]) / 2.0,
    )
    output_directory = DESTINATION / effect_id
    output_directory.mkdir(parents=True, exist_ok=True)
    for index, image in enumerate(images):
        image.crop(crop).save(output_directory / f"frame_{index:02d}.png")
    return {
        "effect_id": effect_id,
        "source_symbol": symbol,
        "frame_count": len(images),
        "source_canvas": list(canvas_size),
        "union_crop": list(crop),
        "output_size": [crop[2] - crop[0], crop[3] - crop[1]],
        "sprite_offset": list(sprite_offset),
        "policy": "shared union crop; no resize or repaint",
    }


def main() -> None:
    records = [prepare_effect(effect_id, symbol) for effect_id, symbol in EFFECTS.items()]
    manifest = {
        "purpose": "Wukong classic skill effects",
        "source": "zmxiyou3 Role1v690",
        "effects": records,
    }
    manifest_path = DESTINATION / "manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(f"Prepared {len(records)} Wukong skill effects")
    print(manifest_path)


if __name__ == "__main__":
    main()
