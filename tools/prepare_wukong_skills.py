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
    "shenglong_zhan": "DefineSprite_56_Role1Bullet6",
    "huoyan_tuji": "DefineSprite_67_Role1Bullet7",
    "lieyan_fengbao": "DefineSprite_43_Role1Bullet8",
    "lieyan_shan": "DefineSprite_78_Role1Bullet9",
    "huomo_hover": "DefineSprite_201_Role1Bullet10_2",
    "huomo_fall": "DefineSprite_156_Role1Bullet10_3",
    "huomo_land": "DefineSprite_151_Role1Bullet10_4",
    "jindou_horizontal": "DefineSprite_100_Role1Bullet11_1",
    "jindou_vertical": "DefineSprite_101_Role1Bullet11_2",
    "huoyan_cast_eye": "DefineSprite_136_Role1Bullet12_1_1",
    "huoyan_cast_flare": "DefineSprite_106_Role1Bullet12_1_2",
    "huoyan_explosion": "DefineSprite_140_Role1Bullet12",
    "qishier_zhan": "DefineSprite_218_Role1Bullet13",
    "zhongzhan_charge": "DefineSprite_206_Role1Bullet14_1",
    "zhongzhan_slash": "DefineSprite_210_Role1Bullet14_2",
}

# MovieClip registration points in FFDec's shared raster canvases.  These are
# derived from every exported SVG frame bound plus symmetric raster filter
# padding.  They intentionally are not inferred from the PNG canvas centre.
SOURCE_REGISTRATIONS = {
    "shenglong_zhan": (64.9, 180.0),
    "huoyan_tuji": (1.675, -8.85),
    "lieyan_fengbao": (177.65, 106.15),
    "lieyan_shan": (0.0, -12.65),
    "huomo_hover": (220.775, 121.825),
    "huomo_fall": (183.75, 4.475),
    "huomo_land": (108.525, 139.725),
    "jindou_horizontal": (49.4, -23.775),
    "jindou_vertical": (122.825, 53.0),
    "huoyan_cast_eye": (16.375, 14.6),
    "huoyan_cast_flare": (596.9, 233.6),
    "huoyan_explosion": (864.0, 480.0),
    "qishier_zhan": (855.0, 925.35),
    "zhongzhan_charge": (674.15, 374.15),
    "zhongzhan_slash": (0.475, 0.05),
}

SOURCE_CALIBRATION = {
    "shenglong_zhan": {
        "source_action": "hit6", "gameplay_tick": 3,
        "source_delta": [30, 40], "placement": "actor_mirrored",
    },
    "huoyan_tuji": {
        "source_action": "hit7", "gameplay_tick": 1,
        "source_delta": [175, -30], "placement": "actor_mirrored",
    },
    "lieyan_fengbao": {
        "source_action": "hit8", "gameplay_tick": 1,
        "source_delta": [20, 30], "placement": "actor_mirrored",
    },
    "lieyan_shan": {
        "source_action": "hit9", "gameplay_tick": 1,
        "source_delta": [120, -50], "placement": "actor_mirrored",
    },
    "huomo_zhan": {
        "source_action": "hit10", "gameplay_tick": 1,
        "phases": [
            {"id": "hover", "gameplay_tick": 6, "source_delta": [-10, 0], "placement": "actor_absolute_x"},
            {"id": "fall", "source_delta": [0, -40], "placement": "actor_mirrored"},
            {"id": "land", "source_delta": [0, 40], "placement": "actor_mirrored"},
        ],
    },
    "jindou_yun": {
        "source_action": "hit11_1/hit11_2", "gameplay_tick": 1,
        "phases": [
            {"id": "horizontal", "source_delta": [50, -50], "placement": "actor_mirrored"},
            {"id": "vertical", "source_delta": [0, -50], "placement": "actor_mirrored"},
        ],
    },
    "huoyan_jinjing": {
        "source_action": "hit12", "gameplay_tick": 1, "target_tick": 17,
        "placement": "asymmetric_actor_cast_then_target_origin",
    },
    "qishier_zhan": {
        "source_action": "hit13", "gameplay_tick": 1,
        "source_delta": [0, 0], "placement": "contact_target_origin",
    },
    "zhongzhan": {
        "source_action": "hit14",
        "phases": [
            {"id": "charge", "gameplay_tick": 1, "source_delta": [-15, -85], "placement": "actor_mirrored"},
            {"id": "slash", "gameplay_tick": 15, "source_delta": [145, -60], "placement": "actor_mirrored"},
        ],
    },
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
    registration = SOURCE_REGISTRATIONS[effect_id]
    sprite_offset = (
        (crop[0] + crop[2]) / 2.0 - registration[0],
        (crop[1] + crop[3]) / 2.0 - registration[1],
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
        "source_registration": list(registration),
        "union_crop": list(crop),
        "output_size": [crop[2] - crop[0], crop[3] - crop[1]],
        "sprite_offset": list(sprite_offset),
        "policy": "shared union crop; restore SWF registration; no resize or repaint",
    }


def main() -> None:
    records = [prepare_effect(effect_id, symbol) for effect_id, symbol in EFFECTS.items()]
    manifest = {
        "purpose": "Wukong complete skill effects and Flash coordinate calibration",
        "source": "zmxiyou3 Role1v690",
        "flash_actor_origin_y": -50,
        "source_calibration": SOURCE_CALIBRATION,
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
