"""Verify selected PNG fidelity and shared foot anchors.

Run with ``.tools/python-portable/python.exe`` because it bundles Pillow.
"""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SELECTED = ROOT / "assets" / "selected" / "zmxiyou3"
ROLE_ANCHORS = {
    "wukong": (
        ROOT / "resources/roles/role_1_wukong.tres",
        SELECTED / "wukong/body_candidates/showid_1/source_atlas.png",
        (200, 200),
    ),
    "tangseng": (
        ROOT / "resources/roles/role_2_tangseng.tres",
        SELECTED / "tangseng/body_candidates/showid_1/source_atlas.png",
        (200, 200),
    ),
    "bajie": (
        ROOT / "resources/roles/role_3_bajie.tres",
        SELECTED / "bajie/body_candidates/showid_1/source_atlas.png",
        (300, 200),
    ),
    "shaseng": (
        ROOT / "resources/roles/role_4_shaseng.tres",
        SELECTED / "shaseng/body_candidates/shovel/showid_1/source_atlas.png",
        (200, 200),
    ),
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_visual_offset(profile_path: Path) -> tuple[float, float]:
    text = profile_path.read_text(encoding="utf-8")
    match = re.search(r"visual_offset\s*=\s*Vector2\(([-\d.]+),\s*([-\d.]+)\)", text)
    if match is None:
        raise AssertionError(f"Missing visual_offset in {profile_path}")
    return float(match.group(1)), float(match.group(2))


def parse_visual_nudge(profile_path: Path) -> tuple[float, float]:
    text = profile_path.read_text(encoding="utf-8")
    match = re.search(r"visual_nudge\s*=\s*Vector2\(([-\d.]+),\s*([-\d.]+)\)", text)
    if match is None:
        raise AssertionError(f"Missing visual_nudge in {profile_path}")
    return float(match.group(1)), float(match.group(2))


def verify_fidelity() -> int:
    manifest = json.loads((SELECTED / "playable_roles_manifest.json").read_text(encoding="utf-8"))
    for record in manifest["files"]:
        canonical = ROOT / record["canonical"]
        assert canonical.is_file(), f"Missing canonical selected file: {canonical}"
        assert sha256(canonical) == record["sha256"], f"Selected PNG changed: {canonical}"
    return len(manifest["files"])


def verify_anchors() -> dict[str, dict[str, object]]:
    report: dict[str, dict[str, object]] = {}
    for role_key, (profile_path, atlas_path, frame_size) in ROLE_ANCHORS.items():
        frame = Image.open(atlas_path).convert("RGBA").crop((0, 0, *frame_size))
        alpha = frame.getchannel("A")
        # The Shaseng export contains a uniform alpha=2 background.  Alpha > 2
        # consistently isolates actual source artwork for every role.
        bounds = alpha.point(lambda value: 255 if value > 2 else 0).getbbox()
        assert bounds is not None, f"No visible idle pixels for {role_key}"
        visual_offset = parse_visual_offset(profile_path)
        visual_nudge = parse_visual_nudge(profile_path)
        foot_edge = visual_offset[1] + visual_nudge[1] + bounds[3] - frame_size[1] / 2
        assert abs(foot_edge - 5.0) < 0.01, (
            f"{role_key} foot edge is {foot_edge}px from actor ground, expected 5px; "
            f"bounds={bounds}, visual_offset={visual_offset}, visual_nudge={visual_nudge}"
        )
        report[role_key] = {
            "idle_alpha_bounds": bounds,
            "visual_offset": visual_offset,
            "visual_nudge": visual_nudge,
            "foot_edge_from_ground": foot_edge,
        }
    return report


def main() -> None:
    file_count = verify_fidelity()
    anchors = verify_anchors()
    print(json.dumps({"byte_identical_pngs": file_count, "anchors": anchors}, indent=2))


if __name__ == "__main__":
    main()
