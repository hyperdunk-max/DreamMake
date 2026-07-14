"""Copy the curated, playable role assets out of the full Flash extraction.

The full extraction is intentionally ignored by Godot.  This script is the
repeatable bridge from that archive into assets/selected, which is imported
and committed with the project.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "extracted" / "full" / "zmxiyou3" / "characters"
DESTINATION = ROOT / "assets" / "selected" / "zmxiyou3"


ROLE_ATLASES = {
    "tangseng": {
        "body/showid_1/source_atlas.png": SOURCE / "tangseng/body/1/ROLE2_1/images/1_ROLE2_1.png",
        "weapon/showid_0/source_atlas.png": SOURCE / "tangseng/weapon/0/ROLE2_EQUIP_0/images/1_ROLE2_EQUIP_0.png",
        "weapon/showid_1/source_atlas.png": SOURCE / "tangseng/weapon/1/ROLE2_EQUIP_1/images/1_ROLE2_EQUIP_1.png",
    },
    "bajie": {
        "body/showid_1/source_atlas.png": SOURCE / "bajie/body/1/ROLE3_1/images/1_ROLE3_1.png",
        "weapon/showid_0/source_atlas.png": SOURCE / "bajie/weapon/0/ROLE3_EQUIP_0/images/1_ROLE3_EQUIP_0.png",
        "weapon/showid_1/source_atlas.png": SOURCE / "bajie/weapon/1/ROLE3_EQUIP_1/images/1_ROLE3_EQUIP_1.png",
    },
    "shaseng": {
        "body/showid_1/source_atlas.png": SOURCE / "shaseng/body_shovel/1/ROLE4_SHOVEL_1/images/1_ROLE4_SHOVEL_1.png",
        "weapon/showid_0/source_atlas.png": SOURCE / "shaseng/weapon/0/ROLE4_EQUIP_0/images/1_ROLE4_EQUIP_0.png",
        "weapon/showid_1/source_atlas.png": SOURCE / "shaseng/weapon/1/ROLE4_EQUIP_1/images/1_ROLE4_EQUIP_1.png",
    },
}


WUKONG_EFFECTS = {
    "hit1": "DefineSprite_5_Role1Bullet1",
    "hit3": "DefineSprite_22_Role1Bullet3",
    "hit4": "DefineSprite_15_Role1Bullet4",
    "hit5": "DefineSprite_9_Role1Bullet5",
}


def copy_file(source: Path, destination: Path) -> dict[str, object]:
    if not source.is_file():
        raise FileNotFoundError(f"Missing extracted asset: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    return {
        "source": source.relative_to(ROOT).as_posix(),
        "destination": destination.relative_to(ROOT).as_posix(),
        "bytes": destination.stat().st_size,
    }


def prepare_role_atlases() -> list[dict[str, object]]:
    copied = []
    for role_key, assets in ROLE_ATLASES.items():
        for relative_destination, source in assets.items():
            copied.append(copy_file(source, DESTINATION / role_key / relative_destination))
    return copied


def prepare_wukong_effects() -> list[dict[str, object]]:
    copied = []
    sprite_root = SOURCE / "mixed_packages" / "Role1v690" / "sprites"
    effect_root = DESTINATION / "wukong" / "effects" / "normal_attack"
    for action, symbol in WUKONG_EFFECTS.items():
        source_directory = sprite_root / symbol
        frames = sorted(source_directory.glob("*.png"), key=lambda path: int(path.stem))
        if not frames:
            raise FileNotFoundError(f"Missing extracted effect frames: {source_directory}")
        for frame_index, source in enumerate(frames):
            destination = effect_root / action / f"frame_{frame_index:02d}.png"
            record = copy_file(source, destination)
            record["action"] = action
            record["frame"] = frame_index
            copied.append(record)
    return copied


def main() -> None:
    manifest = {
        "purpose": "Playable role atlases and Wukong normal-attack effects",
        "policy": "Byte-for-byte copies of extracted PNG files; no repainting or resampling",
        "files": prepare_role_atlases() + prepare_wukong_effects(),
    }
    manifest_path = DESTINATION / "playable_roles_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Prepared {len(manifest['files'])} files")
    print(manifest_path)


if __name__ == "__main__":
    main()
