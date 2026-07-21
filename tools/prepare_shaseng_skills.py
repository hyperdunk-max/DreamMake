#!/usr/bin/env python3
"""Prepare source-faithful Shaseng skill effects and Flash calibration metadata."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "assets/extracted/classified/zmxiyou3/人物/沙僧/技能与动作/Role4v3550"
SOURCE = PACKAGE / "sprites"
DESTINATION = ROOT / "assets/selected/zmxiyou3/shaseng/effects/skills"

EFFECTS = {
    "zq_shovel": "DefineSprite_192_Role4Bullet4",
    "zq_arrow": "DefineSprite_12_Role4BulletArrow4",
    "wdww_cast": "DefineSprite_196_Role4Bullet5",
    "mbyj": "DefineSprite_246_Role4Bullet6",
    "jdz_array": "DefineSprite_253_Role4Bullet7_1",
    "jdz_burst": "DefineSprite_258_Role4Bullet7_2",
    "qlj_shovel": "DefineSprite_237_Role4Bullet8",
    "qlj_arrow_charge": "DefineSprite_54_Role4BulletArrow8_1",
    "qlj_arrow_impact": "DefineSprite_50_Role4BulletArrow8_2",
    "tkj_shovel_charge": "DefineSprite_230_Role4Bullet9_1",
    "tkj_shovel_impact": "DefineSprite_211_Role4Bullet9_2",
    "tkj_arrow_charge": "DefineSprite_34_Role4BulletArrow9_1",
    "tkj_arrow_impact": "DefineSprite_20_Role4BulletArrow9_2",
    "dzj_shovel": "DefineSprite_307_Role4Bullet10",
    "dzj_arrow_charge": "DefineSprite_128_Role4BulletArrow10_1",
    "dzj_arrow_impact": "DefineSprite_101_Role4BulletArrow10_2",
    "lvbj": "DefineSprite_249_Role4Bullet11",
    "mmw_shovel": "DefineSprite_271_Role4Bullet12",
    "mmw_arrow_aura": "DefineSprite_88_Role4BulletArrow12_1",
    "mmw_arrow_body": "DefineSprite_68_Role4BulletArrow12_2",
    "mmw_arrow_leaf": "DefineSprite_73_Role4BulletArrow12_3",
    "mds": "DefineSprite_243_Role4MDS",
}

# MovieClip registration points in FFDec's shared raster canvases.  Each value
# is derived from the union of every SVG frame bound plus symmetric raster
# filter padding; it is not the centre of the exported PNG.
SOURCE_REGISTRATIONS = {
    "zq_shovel": (-12.975, -10.875),
    "zq_arrow": (543.8, 31.075),
    "wdww_cast": (648.725, 874.975),
    "mbyj": (0.0, 0.0),
    "jdz_array": (41.825, -71.25),
    "jdz_burst": (768.0, 384.0),
    "qlj_shovel": (69.075, 8.825),
    "qlj_arrow_charge": (0.4, 0.45),
    "qlj_arrow_impact": (91.55, 22.4),
    "tkj_shovel_charge": (52.675, 22.975),
    "tkj_shovel_impact": (48.325, 143.3),
    "tkj_arrow_charge": (1.7, 2.15),
    "tkj_arrow_impact": (4.975, 29.85),
    "dzj_shovel": (131.075, 35.45),
    "dzj_arrow_charge": (145.4, 73.0),
    "dzj_arrow_impact": (84.9, -15.35),
    "lvbj": (48.225, 22.2),
    "mmw_shovel": (475.3, 31.675),
    "mmw_arrow_aura": (0.25, -10.825),
    "mmw_arrow_body": (87.2, 65.225),
    "mmw_arrow_leaf": (347.35, 0.325),
    "mds": (519.05, 503.1),
}

SOURCE_CALIBRATION = {
    "zq": {
        "source_action": "hit4", "shovel_tick": 20, "arrow_tick": 7,
        "shovel_delta": [125, -30], "arrow_delta": [30, 0],
        "poison_seconds": 8, "poison_damage_per_second": 10,
    },
    "wdww": {
        "source_action": "hit5", "shovel_cast_tick": 3, "arrow_cast_tick": 1,
        "shovel_bind_tick": 8, "arrow_bind_tick": 7, "duration_seconds": 10,
    },
    "mbyj": {
        "source_action": "hit6", "cast_tick": 1, "range": 500,
        "max_jumps": 8, "travel_speed": 500 / 1.2, "poison_stack_seconds": 7,
        "stun_seconds": 0.5,
    },
    "jdz": {
        "source_action": "hit7", "array_tick": 15, "burst_tick": 27,
        "burst_count": 3, "poison_seconds": 4,
        "poison_damage": "0.5 * attack",
    },
    "mds": {
        "play_action": False, "level_1_stack_cap": 6,
        "damage": "stacks^2 * attack * 0.25", "clears_stacks": True,
    },
    "qlj": {
        "source_action": "hit8", "shovel_tick": 5, "arrow_tick": 1,
        "arrow_velocity_per_tick": [-25, -25],
    },
    "tkj": {
        "source_action": "hit9", "shovel_tick": 8, "arrow_tick": 3,
        "shovel_vertical_per_tick": -10, "arrow_vertical_per_tick": -35,
    },
    "dzj": {
        "source_action": "hit10", "shovel_tick": 1, "arrow_tick": 13,
        "shovel_horizontal_per_tick": 20,
    },
    "lvbj": {
        "source_action": "hit11", "mark_tick": 1, "mark_seconds": 10,
        "second_cast_teleports": True, "second_cast_keeps_mark": True,
    },
    "mmw": {
        "source_action": "hit12", "shovel_tick": 5, "shovel_seconds": 10,
        "arrow_body_ticks": [1, 25], "arrow_leaf_ticks": [4, 9, 15, 34, 39, 45],
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


def write_cropped_frames(
    effect_id: str, images: list[Image.Image], registration: tuple[float, float]
) -> dict[str, object]:
    canvas_size = images[0].size
    if any(image.size != canvas_size for image in images):
        raise ValueError(f"Effect frames do not share a canvas: {effect_id}")
    crop = union_alpha_bounds(images)
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
        "frame_count": len(images),
        "source_canvas": list(canvas_size),
        "source_registration": list(registration),
        "union_crop": list(crop),
        "output_size": [crop[2] - crop[0], crop[3] - crop[1]],
        "sprite_offset": list(sprite_offset),
        "policy": "shared union crop; restore SWF registration; no resize or repaint",
    }


def prepare_effect(effect_id: str, symbol: str) -> dict[str, object]:
    paths = natural_frames(SOURCE / symbol)
    if not paths:
        raise FileNotFoundError(f"Missing extracted effect frames: {symbol}")
    images = [Image.open(path).convert("RGBA") for path in paths]
    record = write_cropped_frames(effect_id, images, SOURCE_REGISTRATIONS[effect_id])
    record["source_symbol"] = symbol
    return record


def prepare_voodoo_doll() -> dict[str, object]:
    atlas_path = PACKAGE / "images/1_Role4Hit5.png"
    atlas = Image.open(atlas_path).convert("RGBA")
    frame_size = (116, 120)
    source_images = [atlas.crop((index * 116, 0, (index + 1) * 116, 120)) for index in range(6)]
    holds = [2, 2, 2, 3, 2, 4]
    images = [image for image, hold in zip(source_images, holds) for _ in range(hold)]
    record = write_cropped_frames("wdww_doll", images, (58.0, 60.0))
    record["source_symbol"] = "Role4Hit5 BitmapData"
    record["source_frame_size"] = list(frame_size)
    record["source_frame_count"] = len(source_images)
    record["source_holds"] = holds
    return record


def main() -> None:
    records = [prepare_effect(effect_id, symbol) for effect_id, symbol in EFFECTS.items()]
    records.append(prepare_voodoo_doll())
    manifest = {
        "purpose": "Shaseng complete shovel/arrow skill effects and Flash coordinate calibration",
        "source": "zmxiyou3 Role4v3550",
        "flash_actor_origin_y": -50,
        "weapon_modes": {"shovel": [0, 1, 2, 3, 6], "arrow": [4, 5, 7, 8, 9]},
        "source_calibration": SOURCE_CALIBRATION,
        "effects": records,
    }
    manifest_path = DESTINATION / "manifest.json"
    with manifest_path.open("w", encoding="utf-8", newline="\n") as manifest_file:
        manifest_file.write(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Prepared {len(records)} Shaseng skill effects")
    print(manifest_path)


if __name__ == "__main__":
    main()
