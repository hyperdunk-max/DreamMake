"""Validate ZMX1 pickup sprite packs and finalize their provenance manifest."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "sources/manifests/zmxiyou1_world_pickup_assets.json"
RUNTIME_ROOT = ROOT / "assets/selected/zmxiyou1/monsters/shared/pickups"
MEDICINE_NAMES = ("big_hp", "small_hp", "small_mp")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    equipment_names = tuple(sorted(data["equipment"]["source_names"]))
    actual_medicine = tuple(sorted(path.name for path in (RUNTIME_ROOT / "medicine").iterdir() if path.is_dir()))
    actual_equipment = tuple(sorted(path.name for path in (RUNTIME_ROOT / "equipment").iterdir() if path.is_dir()))
    if actual_medicine != MEDICINE_NAMES:
        raise ValueError(f"Medicine selection mismatch: {actual_medicine}")
    if actual_equipment != equipment_names:
        raise ValueError(f"Equipment selection mismatch: {actual_equipment}")

    generated: list[dict[str, object]] = []
    aggregate_lines: list[str] = []
    for kind, names in (("medicine", actual_medicine), ("equipment", actual_equipment)):
        for source_name in names:
            directory = RUNTIME_ROOT / kind / source_name
            png_path = directory / "sprite.png"
            json_path = directory / "sprite.json"
            atlas = json.loads(json_path.read_text(encoding="utf-8"))
            frame_count = int(atlas["meta"]["frameCount"])
            if frame_count != 1 or len(atlas["frames"]) != 1:
                raise ValueError(f"Pickup atlas must contain exactly one frame: {json_path}")
            relative = directory.relative_to(ROOT).as_posix()
            hashes = {"sprite.png": sha256(png_path), "sprite.json": sha256(json_path)}
            generated.append(
                {
                    "kind": kind,
                    "source_name": source_name,
                    "path": relative,
                    "frame_count": frame_count,
                    "sha256": hashes,
                }
            )
            aggregate_lines.extend(
                f"{relative}/{filename}:{digest}" for filename, digest in sorted(hashes.items())
            )

    aggregate = hashlib.sha256("\n".join(sorted(aggregate_lines)).encode("utf-8")).hexdigest()
    data["purpose"] = "Completed migration and verification record for source-accurate medicine and equipment pickup visuals."
    data["migration_status"] = "completed_and_verified"
    data["generated_assets"] = generated
    data["validation"] = {
        "status": "passed_2026-07-24",
        "atlas_count": len(generated),
        "medicine_count": len(actual_medicine),
        "equipment_count": len(actual_equipment),
        "frame_count_per_atlas": 1,
        "aggregate_sha256": aggregate,
        "checks": [
            "Every runtime directory contains sprite.png and sprite.json.",
            "Every JSON contains exactly one named frame and meta.frameCount=1.",
            "All expected source names are present and no unexpected runtime directories exist.",
        ],
    }
    MANIFEST.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Finalized {len(generated)} pickup atlases: {aggregate}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
