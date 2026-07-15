"""Prepare selected role atlases and source-anchored normal-attack effects.

The full Flash extraction stays behind ``.gdignore``.  This script copies the
small, reviewable subset used by the Godot prototype into ``assets/selected``
without repainting, cropping, or resampling any PNG.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "extracted" / "full" / "zmxiyou3" / "characters"
DESTINATION = ROOT / "assets" / "selected" / "zmxiyou3"


EQUIPMENT = {
    "wukong": {
        "body": ("body", (0, 1, 2, 3, 4, 9), "ROLE1"),
        "weapon": ("weapon", tuple(range(0, 9)), "ROLE1_EQUIP"),
    },
    "tangseng": {
        "body": ("body", (0, 1, 2, 3, 4, 5, 9), "ROLE2"),
        "weapon": ("weapon", (0, 1, 2, 3, 5, 7, 8), "ROLE2_EQUIP"),
    },
    "bajie": {
        "body": ("body", (0, 1, 2, 4, 5, 9), "ROLE3"),
        "weapon": ("weapon", tuple(range(0, 9)), "ROLE3_EQUIP"),
    },
    "shaseng": {
        "body/shovel": ("body_shovel", (0, 1, 2, 3, 4, 5, 9), "ROLE4_SHOVEL"),
        "body/arrow": ("body_arrow", (0, 1, 2, 3, 4, 5, 9), "ROLE4_ARROW"),
        "weapon": ("weapon", (0, 1, 2, 3, 4, 6, 7, 8, 9), "ROLE4_EQUIP"),
    },
}


# sprite_offset is the exported PNG centre relative to the Flash registration
# point.  Values come from FFDec sprite SVG bounds and remain constant across
# every frame of each source MovieClip.
EFFECTS = {
    "wukong": {
        "hit1": ("Role1v690", "DefineSprite_5_Role1Bullet1", (57.9, 16.6)),
        "hit3": ("Role1v690", "DefineSprite_22_Role1Bullet3", (-5.3, 87.575)),
        "hit4": ("Role1v690", "DefineSprite_15_Role1Bullet4", (152.85, 18.125)),
        "hit5": ("Role1v690", "DefineSprite_9_Role1Bullet5", (115.875, 29.425)),
    },
    "tangseng": {
        "hit1": ("Role2v3550", "DefineSprite_103_Role2Bullet1", (-203.975, 0.0)),
    },
    "bajie": {
        "hit1": ("Role3v690", "DefineSprite_4_Role3Bullet1", (64.5, 60.5)),
        "hit2": ("Role3v690", "DefineSprite_12_Role3Bullet2", (60.5, 39.5)),
        "hit3": ("Role3v690", "DefineSprite_8_Role3Bullet3", (73.725, 130.075)),
    },
    "shaseng": {
        "hit1": ("Role4v3550", "DefineSprite_137_Role4Bullet1", (-5.5, 6.2)),
        "hit2": ("Role4v3550", "DefineSprite_150_Role4Bullet2", (-38.35, -26.7)),
        "hit3": ("Role4v3550", "DefineSprite_146_Role4Bullet3", (5.15, -4.45)),
        "arrow_hit1": ("Role4v3550", "DefineSprite_5_Role4BulletArrow1", (-145.2, 10.5)),
        "arrow_hit2": ("Role4v3550", "DefineSprite_8_Role4BulletArrow2", (-139.1, 0.6)),
    },
}


def copy_file(source: Path, destination: Path, **metadata: object) -> dict[str, object]:
    if not source.is_file():
        raise FileNotFoundError(f"Missing extracted asset: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    return {
        "source": source.relative_to(ROOT).as_posix(),
        "destination": destination.relative_to(ROOT).as_posix(),
        "bytes": destination.stat().st_size,
        **metadata,
    }


def find_atlas(role_key: str, source_kind: str, prefix: str, showid: int) -> Path:
    image_directory = SOURCE / role_key / source_kind / str(showid) / f"{prefix}_{showid}" / "images"
    matches = sorted(image_directory.glob("1_*.png"))
    if len(matches) != 1:
        raise FileNotFoundError(f"Expected one bitmap atlas in {image_directory}, found {len(matches)}")
    return matches[0]


def prepare_equipment() -> list[dict[str, object]]:
    copied: list[dict[str, object]] = []
    for role_key, categories in EQUIPMENT.items():
        role_catalog: dict[str, object] = {"role": role_key, "categories": {}}
        for destination_kind, (source_kind, showids, prefix) in categories.items():
            category = "weapon_candidates" if destination_kind == "weapon" else "body_candidates"
            mode = destination_kind.split("/", 1)[1] if "/" in destination_kind else "default"
            entries = []
            for showid in showids:
                source = find_atlas(role_key, source_kind, prefix, showid)
                destination = DESTINATION / role_key / category
                if mode != "default":
                    destination /= mode
                destination = destination / f"showid_{showid}" / "source_atlas.png"
                record = copy_file(
                    source,
                    destination,
                    kind="weapon" if destination_kind == "weapon" else "body",
                    mode=mode,
                    role=role_key,
                    showid=showid,
                )
                copied.append(record)
                entries.append({"showid": showid, "file": record["destination"]})
            role_catalog["categories"][destination_kind] = entries
        catalog_path = DESTINATION / role_key / "equipment_catalog.json"
        catalog_path.parent.mkdir(parents=True, exist_ok=True)
        catalog_path.write_text(
            json.dumps(role_catalog, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )
    return copied


def prepare_effects() -> list[dict[str, object]]:
    copied: list[dict[str, object]] = []
    for role_key, effects in EFFECTS.items():
        for action, (package, symbol, sprite_offset) in effects.items():
            source_directory = SOURCE / "mixed_packages" / package / "sprites" / symbol
            frames = sorted(source_directory.glob("*.png"), key=lambda path: int(path.stem))
            if not frames:
                raise FileNotFoundError(f"Missing extracted effect frames: {source_directory}")
            for frame_index, source in enumerate(frames):
                destination = (
                    DESTINATION / role_key / "effects" / "normal_attack" / action / f"frame_{frame_index:02d}.png"
                )
                copied.append(
                    copy_file(
                        source,
                        destination,
                        action=action,
                        frame=frame_index,
                        role=role_key,
                        source_symbol=symbol,
                        sprite_offset=list(sprite_offset),
                    )
                )
    return copied


def main() -> None:
    files = prepare_equipment() + prepare_effects()
    manifest = {
        "purpose": "Playable equipment variants and source-anchored normal-attack effects",
        "policy": "Byte-for-byte copies of extracted PNG files; no repainting, cropping, or resampling",
        "files": files,
    }
    manifest_path = DESTINATION / "playable_roles_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(f"Prepared {len(files)} source PNG files")
    print(manifest_path)


if __name__ == "__main__":
    main()
