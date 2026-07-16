#!/usr/bin/env python3
"""Prepare source-faithful Tangseng skill effects and calibration metadata."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "assets/extracted/full/zmxiyou3/characters/mixed_packages/Role2v3550"
SOURCE = PACKAGE / "sprites"
DESTINATION = ROOT / "assets/selected/zmxiyou3/tangseng/effects/skills"
SHADOW_DESTINATION = ROOT / "assets/selected/zmxiyou3/tangseng/shadow/source_atlas.png"
SHADOW_FRAMES = ROOT / "assets/selected/zmxiyou3/tangseng/shadow/walk"

EFFECTS = {
    "binglong_bo": "DefineSprite_107_Role2Bullet2",
    "xuanbing_zhen": "DefineSprite_243_Role2Bullet3",
    "shuimo_bao_marker": "DefineSprite_100_Role2Bullet4_1",
    "shuimo_bao_blast": "DefineSprite_93_Role2Bullet4_2",
    "shengguang_qiu": "DefineSprite_219_Role2Bullet5",
    "muyu_huichun": "DefineSprite_197_Role2Bullet6",
    "jingu_zhou": "DefineSprite_170_Role2Bullet7",
    "tianjiang_ganlu": "DefineSprite_47_Role2Bullet8",
    "jiuhuan_aura": "DefineSprite_126_Role2Bullet9_1",
    "jiuhuan_strike": "DefineSprite_167_Role2Bullet9_2",
}

SOURCE_BLEND_MODES = {
    # SWF PlaceObject3 blendMode 8 is Flash's SUBTRACT mode. Its opaque black
    # pixels intentionally leave the destination unchanged under subtraction.
    "tianjiang_ganlu": {"flash_value": 8, "flash_mode": "subtract", "godot_value": 2},
}

# Flash MovieClip registration points in the shared raster canvases. These are
# derived from each exported SVG frame's local bounds, plus FFDec's symmetric
# raster padding for filters/glows. Keeping them explicit makes PNG cropping
# preserve the original x=0/y=0 used by Role2.as when it positions bullets.
SOURCE_REGISTRATIONS = {
    "binglong_bo": (965.975, 30.0),
    "xuanbing_zhen": (243.0, 94.15),
    "shuimo_bao_marker": (16.15, 16.375),
    "shuimo_bao_blast": (102.375, 36.4),
    "shengguang_qiu": (0.0, 0.0),
    "muyu_huichun": (106.525, 168.875),
    "jingu_zhou": (247.925, 58.525),
    "tianjiang_ganlu": (245.5, 163.0),
    "jiuhuan_aura": (62.7, 43.05),
    "jiuhuan_strike": (0.0, 0.0),
}

SOURCE_CALIBRATION = {
    "shengguang_qiu": {"source_action": "hit5", "gameplay_tick": 51, "source_delta": [175, -110], "placement": "actor_mirrored"},
    "muyu_huichun": {"source_action": "hit6", "gameplay_tick": 5, "source_delta": [0, -25], "placement": "actor_mirrored"},
    "jingu_zhou": {"source_action": "hit7", "gameplay_tick": 5, "source_delta": [210, 30], "placement": "actor_mirrored"},
    "tianjiang_ganlu": {"source_action": "hit8", "gameplay_tick": 1, "source_delta": [-5, -60], "placement": "actor_mirrored"},
    "jiuhuan_shengjing": {"source_action": "hit9", "phases": [
        {"id": "aura", "gameplay_tick": 1, "source_delta": [20, -20], "placement": "actor_mirrored"},
        {"id": "strike", "gameplay_tick": 11, "source_delta": [150, -150], "placement": "actor_mirrored"},
    ]},
    "binglong_bo": {"source_action": "charged hit1", "charge_ticks": 48, "source_delta": [50, 10], "placement": "actor_mirrored"},
    "xuanbing_zhen": {"source_action": "hit3", "gameplay_tick": 13, "source_delta": [0, 10], "placement": "actor_mirrored"},
    "shuihuanying": {"source_action": "hit10", "placement": "actor_origin_then_shadow_origin"},
    "shuimo_bao": {"source_action": "hit4_1/hit4_2", "phases": [
        {"id": "marker", "gameplay_tick": 2, "source_delta": [130, 10], "placement": "actor_mirrored"},
        {"id": "blast", "gameplay_tick": 5, "source_delta": [30, -320], "placement": "moving_marker_mirrored"},
    ]},
}


def natural_frames(directory: Path) -> list[Path]:
    return sorted(directory.glob("*.png"), key=lambda path: int(path.stem))


def union_alpha_bounds(images: list[Image.Image]) -> tuple[int, int, int, int]:
    visible = [box for image in images if (box := image.getchannel("A").getbbox())]
    if not visible:
        raise ValueError("Effect contains no visible pixels")
    return (
        min(box[0] for box in visible), min(box[1] for box in visible),
        max(box[2] for box in visible), max(box[3] for box in visible),
    )


def prepare_effect(effect_id: str, symbol: str) -> dict[str, object]:
    paths = natural_frames(SOURCE / symbol)
    if not paths:
        raise FileNotFoundError(f"Missing extracted effect frames: {symbol}")
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
        image.crop(crop).save(output_directory / f"frame_{index:03d}.png")
    record = {
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
    if effect_id in SOURCE_BLEND_MODES:
        record["source_blend_mode"] = SOURCE_BLEND_MODES[effect_id]
    return record


def main() -> None:
    records = [prepare_effect(effect_id, symbol) for effect_id, symbol in EFFECTS.items()]
    SHADOW_DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PACKAGE / "images/1_ROLE2_SHALLDOW.png", SHADOW_DESTINATION)
    shadow_atlas = Image.open(SHADOW_DESTINATION).convert("RGBA")
    SHADOW_FRAMES.mkdir(parents=True, exist_ok=True)
    for column in range(4):
        shadow_atlas.crop((column * 200, 0, (column + 1) * 200, 200)).save(
            SHADOW_FRAMES / f"frame_{column:02d}.png"
        )
    manifest = {
        "purpose": "Tangseng complete skill effects and Flash coordinate calibration",
        "source": "zmxiyou3 Role2v3550",
        "flash_actor_origin_y": -50,
        "shadow_source_atlas": "res://assets/selected/zmxiyou3/tangseng/shadow/source_atlas.png",
        "source_calibration": SOURCE_CALIBRATION,
        "effects": records,
    }
    manifest_path = DESTINATION / "manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(records)} Tangseng skill effects")
    print(manifest_path)


if __name__ == "__main__":
    main()
