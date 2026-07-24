"""Promote the original ZMX1 Ending into sprite-pack runtime assets.

The Flash Ending uses a static 940x590 background plus three single-frame
credit sprites moved inside one mask for 1205 source frames.  Keeping those
four visuals as sprite.png + sprite.json packs avoids baking 1205 mostly
duplicate full-screen frames while preserving the exact 24 Hz positions in
timeline.json.
"""

from __future__ import annotations

from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
AUDIT_ROOT = ROOT / ".tools" / "ending_audit"
XML_PATH = AUDIT_ROOT / "OtherMat_v9.xml"
SVG_PATH = AUDIT_ROOT / "svg" / "DefineSprite_702_export.scene.Ending" / "1.svg"
TIMELINE_SCRIPT_ROOT = AUDIT_ROOT / "timeline_scripts"
SOURCE_COMPOSITE = (
    ROOT
    / "assets"
    / "extracted"
    / "classified"
    / "zmxiyou1"
    / "UI"
    / "公共素材"
    / "过场动画"
    / "片尾"
    / "Ending"
    / "ui_0001.png"
)
CLASSIFIED_ROOT = SOURCE_COMPOSITE.parent
SELECTED_ROOT = ROOT / "assets" / "selected" / "zmxiyou1" / "ui" / "ending"
MANIFEST_PATH = ROOT / "sources" / "manifests" / "zmxiyou1_ending_assets.json"

TRACKS = {
    696: ("title", 695),
    698: ("story", 697),
    700: ("credits", 699),
}
CLASSIFIED_NAMES = {
    "background": "背景",
    "title": "标题",
    "story": "剧情文字",
    "credits": "制作名单",
}


def _require(path: Path) -> Path:
    if not path.is_file():
        raise FileNotFoundError(path)
    return path


def _write_pack(image: Image.Image, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    sheet_path = output_dir / "sprite.png"
    json_path = output_dir / "sprite.json"
    image.save(sheet_path, optimize=True)
    width, height = image.size
    data = {
        "frames": {
            "frame_001": {"x": 0, "y": 0, "w": width, "h": height},
        },
        "meta": {
            "image": "sprite.png",
            "size": {"w": width, "h": height},
            "frameSize": {"w": width, "h": height},
            "columns": 1,
            "rows": 1,
            "frameCount": 1,
        },
    }
    json_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _int_attr(node: ET.Element | None, name: str, default: int = 0) -> int:
    if node is None:
        return default
    value = node.get(name)
    return int(value) if value not in (None, "") else default


def _parse_flash_timeline() -> tuple[ET.Element, list[dict[int, dict[str, int | None]]]]:
    root = ET.parse(_require(XML_PATH)).getroot()
    tags = root.find("tags")
    if tags is None:
        raise ValueError("FFDec XML has no tags collection")
    sprite = next(
        node
        for node in tags
        if node.get("type") == "DefineSpriteTag" and node.get("spriteId") == "701"
    )
    subtags = sprite.find("subTags")
    if subtags is None:
        raise ValueError("Ending sprite 701 has no timeline")

    state: dict[int, dict[str, int | None]] = {}
    frames: list[dict[int, dict[str, int | None]]] = []
    for tag in subtags:
        tag_type = tag.get("type")
        if tag_type == "ShowFrameTag":
            frames.append({depth: values.copy() for depth, values in state.items()})
            continue
        if tag_type == "RemoveObject2Tag":
            state.pop(_int_attr(tag, "depth"), None)
            continue
        if tag_type != "PlaceObject2Tag":
            raise ValueError(f"Unexpected Ending timeline tag: {tag_type}")
        depth = _int_attr(tag, "depth")
        current = state.get(
            depth,
            {"character": None, "x_twips": 0, "y_twips": 0, "clip_depth": None},
        ).copy()
        if tag.get("placeFlagHasCharacter") == "true":
            current["character"] = _int_attr(tag, "characterId")
        if tag.get("placeFlagHasMatrix") == "true":
            matrix = tag.find("matrix")
            current["x_twips"] = _int_attr(matrix, "translateX")
            current["y_twips"] = _int_attr(matrix, "translateY")
        if tag.get("placeFlagHasClipDepth") == "true":
            current["clip_depth"] = _int_attr(tag, "clipDepth")
        state[depth] = current

    declared = _int_attr(sprite, "frameCount")
    if declared != 1205 or len(frames) != declared:
        raise ValueError(f"Expected Ending 701 to have 1205 frames, got {declared}/{len(frames)}")
    return root, frames


def _shape_bounds(root: ET.Element, shape_id: int) -> dict[str, float]:
    tags = root.find("tags")
    assert tags is not None
    shape = next(node for node in tags if node.get("shapeId") == str(shape_id))
    bounds = shape.find("shapeBounds")
    if bounds is None:
        raise ValueError(f"Shape {shape_id} has no bounds")
    xmin = _int_attr(bounds, "Xmin") / 20.0
    ymin = _int_attr(bounds, "Ymin") / 20.0
    xmax = _int_attr(bounds, "Xmax") / 20.0
    ymax = _int_attr(bounds, "Ymax") / 20.0
    return {"x": xmin, "y": ymin, "w": xmax - xmin, "h": ymax - ymin}


def _parse_svg_geometry() -> tuple[dict[str, float], dict[str, float]]:
    tree = ET.parse(_require(SVG_PATH))
    root = tree.getroot()
    ffdec_character = "{https://www.free-decompiler.com/flash}characterId"
    ending_child = next(node for node in root.iter() if node.get(ffdec_character) == "701")
    matrix_values = [float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", ending_child.get("transform", ""))]
    if len(matrix_values) != 6:
        raise ValueError("Cannot parse Ending child transform")
    child_position = {"x": matrix_values[4], "y": matrix_values[5]}

    clip_path = next(node for node in root.iter() if node.get("id") == "clipPath0")
    path = next(iter(clip_path))
    coords = [float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", path.get("d", ""))]
    xs = coords[0::2]
    ys = coords[1::2]
    mask = {
        "x": min(xs),
        "y": min(ys),
        "w": max(xs) - min(xs),
        "h": max(ys) - min(ys),
    }
    canvas_clip = {
        "x": child_position["x"] + mask["x"],
        "y": child_position["y"] + mask["y"],
        "w": mask["w"],
        "h": mask["h"],
    }
    return mask, canvas_clip


def _destroy_frame() -> int:
    script_path = next(TIMELINE_SCRIPT_ROOT.rglob("*.as"))
    source = script_path.read_text(encoding="utf-8")
    match = re.search(r"addFrameScript\((\d+),this\.frame(\d+)\)", source)
    if match is None or "Ending(this.parent).destroy()" not in source:
        raise ValueError("Cannot find the Ending destroy frame script")
    zero_based = int(match.group(1))
    named_frame = int(match.group(2))
    if named_frame != zero_based + 1:
        raise ValueError("Ending frame-script indices disagree")
    return named_frame


def _track_data(
    root: ET.Element,
    frames: list[dict[int, dict[str, int | None]]],
    source_sprite_id: int,
    name: str,
    source_shape_id: int,
) -> dict:
    samples: list[tuple[int, int, int]] = []
    for frame_number, snapshot in enumerate(frames, start=1):
        matches = [values for values in snapshot.values() if values.get("character") == source_sprite_id]
        if len(matches) > 1:
            raise ValueError(f"Sprite {source_sprite_id} appears more than once on frame {frame_number}")
        if matches:
            samples.append(
                (
                    frame_number,
                    int(matches[0].get("x_twips") or 0),
                    int(matches[0].get("y_twips") or 0),
                )
            )
    expected_frames = list(range(samples[0][0], samples[-1][0] + 1))
    if [sample[0] for sample in samples] != expected_frames:
        raise ValueError(f"Sprite {source_sprite_id} has a discontinuous active range")
    x_values = {sample[1] for sample in samples}
    if len(x_values) != 1:
        raise ValueError(f"Sprite {source_sprite_id} changes X unexpectedly")
    return {
        "name": name,
        "source_sprite_id": source_sprite_id,
        "source_shape_id": source_shape_id,
        "sheet_path": f"res://assets/selected/zmxiyou1/ui/ending/{name}/sprite.png",
        "json_path": f"res://assets/selected/zmxiyou1/ui/ending/{name}/sprite.json",
        "first_frame": samples[0][0],
        "last_frame": samples[-1][0],
        "registration_x_twips": samples[0][1],
        "registration_y_twips": [sample[2] for sample in samples],
        "shape_bounds_px": _shape_bounds(root, source_shape_id),
    }


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def main() -> None:
    root, frames = _parse_flash_timeline()
    mask_rect, canvas_clip_rect = _parse_svg_geometry()
    destroy_frame = _destroy_frame()

    composite = Image.open(_require(SOURCE_COMPOSITE)).convert("RGBA")
    alpha_bounds = composite.getbbox()
    if alpha_bounds != (0, 1171, 940, 1761):
        raise ValueError(f"Unexpected Ending composite alpha bounds: {alpha_bounds}")
    visuals: dict[str, Image.Image] = {"background": composite.crop(alpha_bounds)}
    for sprite_id, (name, _shape_id) in TRACKS.items():
        source = AUDIT_ROOT / "parts" / f"DefineSprite_{sprite_id}" / "1.png"
        visuals[name] = Image.open(_require(source)).convert("RGBA")

    for name, image in visuals.items():
        _write_pack(image, CLASSIFIED_ROOT / CLASSIFIED_NAMES[name])
        _write_pack(image, SELECTED_ROOT / name)

    timeline = {
        "source_game": "zmxiyou1",
        "source_swf": "sources/decoded/zmxiyou1/OtherMat_v9.swf",
        "source_root_symbol": 702,
        "source_timeline_symbol": 701,
        "source_fps": 24.0,
        "source_frame_count": len(frames),
        "destroy_frame": destroy_frame,
        "duration_seconds": (destroy_frame - 1) / 24.0,
        "canvas_size": {"w": 940, "h": 590},
        "mask_rect_in_symbol_px": mask_rect,
        "clip_rect_in_canvas_px": canvas_clip_rect,
        "background": {
            "sheet_path": "res://assets/selected/zmxiyou1/ui/ending/background/sprite.png",
            "json_path": "res://assets/selected/zmxiyou1/ui/ending/background/sprite.json",
        },
        "tracks": [
            _track_data(root, frames, sprite_id, name, shape_id)
            for sprite_id, (name, shape_id) in TRACKS.items()
        ],
    }
    timeline_text = json.dumps(timeline, ensure_ascii=False, indent=2) + "\n"
    (SELECTED_ROOT / "timeline.json").write_text(timeline_text, encoding="utf-8")
    classified_timeline = json.loads(json.dumps(timeline))
    classified_base = "res://assets/extracted/classified/zmxiyou1/UI/公共素材/过场动画/片尾/Ending"
    classified_timeline["background"] = {
        "sheet_path": f"{classified_base}/{CLASSIFIED_NAMES['background']}/sprite.png",
        "json_path": f"{classified_base}/{CLASSIFIED_NAMES['background']}/sprite.json",
    }
    for track in classified_timeline["tracks"]:
        classified_name = CLASSIFIED_NAMES[track["name"]]
        track["sheet_path"] = f"{classified_base}/{classified_name}/sprite.png"
        track["json_path"] = f"{classified_base}/{classified_name}/sprite.json"
    classified_timeline_text = json.dumps(classified_timeline, ensure_ascii=False, indent=2) + "\n"
    (CLASSIFIED_ROOT / "timeline.json").write_text(classified_timeline_text, encoding="utf-8")

    artifact_paths = sorted(
        [path for path in CLASSIFIED_ROOT.rglob("sprite.*") if path.is_file()]
        + [CLASSIFIED_ROOT / "timeline.json"]
        + [path for path in SELECTED_ROOT.rglob("sprite.*") if path.is_file()]
        + [SELECTED_ROOT / "timeline.json"]
    )
    file_hashes = {_relative(path): _sha256(path) for path in artifact_paths}
    selected_hash_input = "\n".join(
        f"{path}\0{digest}"
        for path, digest in file_hashes.items()
        if path.startswith("assets/selected/")
    ).encode("utf-8")
    manifest = {
        "game": "zmxiyou1",
        "date": "2026-07-24",
        "status": "completed_and_verified",
        "purpose": "Original M24 ending presentation without baking 1205 redundant full-screen frames.",
        "source_evidence": [
            "sources/decoded/zmxiyou1/OtherMat_v9.swf",
            "assets/extracted/classified/zmxiyou1/UI/公共素材/过场动画/片尾/Ending/ui_0001.png",
            ".tools/ending_audit/OtherMat_v9.xml",
            ".tools/ending_audit/svg/DefineSprite_702_export.scene.Ending/1.svg",
            ".tools/ending_audit/timeline_scripts/scripts/OtherMat_fla/元件2_9.as",
        ],
        "review": {
            "root_symbol": 702,
            "timeline_symbol": 701,
            "source_fps": 24,
            "source_frame_count": 1205,
            "destroy_frame": destroy_frame,
            "duration_seconds": timeline["duration_seconds"],
            "visual_strategy": "Keep the 940x590 background and three vector-derived credit layers as one-frame sprite packs; replay exact per-frame SWF Y positions inside the original mask.",
            "why_not_full_frame_bake": "A 1205-frame 940x590 bake would duplicate the same background and text pixels while discarding the source timeline structure.",
            "source_composite_retained": True,
            "classified_additions": [CLASSIFIED_NAMES[name] for name in visuals],
            "selected_modules": list(visuals),
        },
        "runtime_timeline": _relative(SELECTED_ROOT / "timeline.json"),
        "files": file_hashes,
        "selected_aggregate_sha256": hashlib.sha256(selected_hash_input).hexdigest(),
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
