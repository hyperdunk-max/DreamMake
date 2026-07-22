#!/usr/bin/env python3
"""Prepare the reviewed ZMX1 Peng Demon King timelines for Godot runtime use."""

from __future__ import annotations

import hashlib
import json
import shutil
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLASSIFIED = ROOT / "assets/extracted/classified/zmxiyou1/怪物/M09_彭魔王"
SELECTED = ROOT / "assets/selected/zmxiyou1/monsters/m09_peng_demon_king"
MANIFEST = ROOT / "sources/manifests/zmxiyou1_m09_peng_demon_king_selected.json"

# Use only the outermost dynamic provider for each root action.  Nested
# providers are already rendered by their parent and must not be stacked a
# second time in Godot.
ACTIONS = {
    "move": ("移动/完整时间轴/character_514", 16),
    "fly": ("共享动作时间轴/character_519", 9),
    "attack1": ("攻击1/完整时间轴/Timeline_92", 24),
    "attack2": ("攻击2/完整时间轴/Timeline_97", 41),
    "attack3": ("攻击3/完整时间轴/Timeline_99", 25),
    "attack4": ("攻击4/完整时间轴/Timeline_108", 15),
    "egg": ("变蛋/完整时间轴/Timeline_101", 25),
    "reburn": ("重燃/完整时间轴/Timeline_104", 30),
    "hurt": ("受伤/完整时间轴/Timeline_106", 6),
    "idle": ("待机/完整时间轴/character_632", 15),
    "death": ("死亡/完整时间轴/Timeline_111", 25),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_frames(folder: Path) -> list[Path]:
    frames = [path for path in folder.glob("*.png") if path.is_file()]
    return sorted(frames, key=lambda path: int(path.stem.rsplit("_", 1)[-1]))


def main() -> None:
    records: list[dict[str, object]] = []
    for action, (relative_source, expected_count) in ACTIONS.items():
        source_dir = CLASSIFIED / relative_source
        frames = source_frames(source_dir)
        if len(frames) != expected_count:
            raise RuntimeError(
                f"{action}: expected {expected_count} source frames, found {len(frames)} in {source_dir}"
            )
        destination_dir = SELECTED / action
        destination_dir.mkdir(parents=True, exist_ok=True)
        existing = set(destination_dir.glob("frame_*.png"))
        expected_destinations: set[Path] = set()
        for index, source in enumerate(frames, start=1):
            destination = destination_dir / f"frame_{index:03d}.png"
            expected_destinations.add(destination)
            shutil.copy2(source, destination)
            source_hash = sha256(source)
            destination_hash = sha256(destination)
            if source_hash != destination_hash:
                raise RuntimeError(f"Copy verification failed: {source} -> {destination}")
            records.append(
                {
                    "action": action,
                    "frame": index,
                    "source": source.relative_to(ROOT).as_posix(),
                    "destination": destination.relative_to(ROOT).as_posix(),
                    "sha256": source_hash,
                }
            )
        stale = existing - expected_destinations
        if stale:
            raise RuntimeError(f"Refusing to overwrite a selected folder with stale frames: {sorted(stale)}")

    manifest = {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "game": "zmxiyou1",
        "monster": "Monster9",
        "display_name": "彭魔王",
        "classified_source": CLASSIFIED.relative_to(ROOT).as_posix(),
        "selected_root": SELECTED.relative_to(ROOT).as_posix(),
        "policy": (
            "The outermost complete dynamic provider is selected for each root action; "
            "nested providers are not duplicated in the Godot animation."
        ),
        "actions": {
            action: {"source": source, "frame_count": count}
            for action, (source, count) in ACTIONS.items()
        },
        "files": records,
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"actions": len(ACTIONS), "frames": len(records)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
