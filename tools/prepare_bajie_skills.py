#!/usr/bin/env python3
"""Prepare source-faithful Bajie skill effects and Flash calibration metadata."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "assets/extracted/full/zmxiyou3/characters/mixed_packages/Role3v690"
SOURCE = PACKAGE / "sprites"
DESTINATION = ROOT / "assets/selected/zmxiyou3/bajie/effects/skills"

EFFECTS = {
    "dunji": "DefineSprite_156_Role3Bullet4",
    "shengdun_cast": "DefineSprite_149_Role3Bullet5",
    "shengdun_buff": "DefineSprite_124_Role3Bullet5Buff",
    "zhanzheng_nuhou": "DefineSprite_169_Role3Bullet6",
    "shengyu_charge": "DefineSprite_85_Role3Bullet7_1",
    "shengyu_wall": "DefineSprite_66_Role3Bullet7_2",
    "suishi_impact": "DefineSprite_62_Role3Bullet8_1",
    "suishi_spikes": "DefineSprite_52_Role3Bullet8_2",
    "jushi": "DefineSprite_120_Role3Bullet9",
    "digun": "DefineSprite_165_Role3Bullet10",
    "xuangun": "DefineSprite_20_Role3Bullet11",
    "tumo_guard": "DefineSprite_33_Role3Bullet12_1",
    "tumo_stab": "DefineSprite_43_Role3Bullet12_2",
}

# Registration points in FFDec's shared PNG canvases, derived from all SVG
# frame bounds and symmetric raster filter padding.
SOURCE_REGISTRATIONS = {
    "dunji": (90.85, -12.8),
    "shengdun_cast": (77.1, 11.35),
    "shengdun_buff": (0.0, 0.0),
    "zhanzheng_nuhou": (768.0, 192.0),
    "shengyu_charge": (0.0, -14.8),
    "shengyu_wall": (350.0, 0.0),
    "suishi_impact": (7.4, 0.075),
    "suishi_spikes": (619.15, 16.575),
    "jushi": (49.7, 38.875),
    "digun": (54.55, 53.8),
    "xuangun": (75.05, 169.025),
    "tumo_guard": (83.15, 87.725),
    "tumo_stab": (16.9, 11.825),
}

SOURCE_CALIBRATION = {
    "dunji": {"source_action": "hit4", "gameplay_tick": 1, "source_delta": [35, -55]},
    "shengdun": {
        "source_action": "hit5", "gameplay_tick": 1,
        "source_delta": [70, -110], "buff_local_delta": [-20, -80], "buff_seconds": 10,
    },
    "renjia": {"passive_defense": 30, "heal_chance": 0.1, "heal_amount": "attack"},
    "zhanzheng_nuhou": {
        "source_action": "hit6", "gameplay_tick": 1, "source_delta": [120, -115],
        "pull_destination": [0, -100], "next_attack_multiplier": 1.3,
    },
    "shengyu_zhiqiang": {
        "source_action": "hit7", "phases": [
            {"id": "charge", "gameplay_tick": 5, "source_delta": [140, -160]},
            {"id": "wall", "gameplay_tick": 17, "source_delta": [135, -145]},
        ],
    },
    "suishi_po": {
        "source_action": "hit8", "gameplay_tick": 7,
        "phases": [{"id": "impact", "source_delta": [95, 0]}, {"id": "spikes", "source_delta": [-20, -20]}],
    },
    "jushi_po": {"source_action": "hit9", "gameplay_tick": 7, "source_delta": [195, -160]},
    "digun_qiu": {
        "source_action": "hit10", "gameplay_tick": 8, "source_delta": [55, -25],
        "movement_ticks": 25, "movement_per_tick": 15,
    },
    "xuangun_qiu": {"source_action": "hit11/hit11Frame2", "gameplay_tick": 3, "source_delta": [135, -90]},
    "tumo_ci": {
        "source_action": "hit12", "guard_tick": 1, "guard_source_delta": [0, 0],
        "hide_tick": 11, "reactivate_from_tick": 31, "reactivate_cost": 30,
        "stab_count": 10, "stab_radius": 100,
    },
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
        "purpose": "Bajie complete skill effects and Flash coordinate calibration",
        "source": "zmxiyou3 Role3v690",
        "flash_actor_origin_y": -50,
        "source_calibration": SOURCE_CALIBRATION,
        "effects": records,
    }
    manifest_path = DESTINATION / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(records)} Bajie skill effects")
    print(manifest_path)


if __name__ == "__main__":
    main()
