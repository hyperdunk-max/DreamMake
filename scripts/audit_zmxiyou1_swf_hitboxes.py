"""Audit Flash `body.stick` geometry from FFDec SWF XML exports.

The output is a source-coordinate manifest; it never derives attack geometry
from rendered/packed frame pixels. Generate XML with FFDec `-swf2xml`, then:

    python scripts/audit_zmxiyou1_swf_hitboxes.py \
      --selection sources/manifests/zmxiyou1_all_monster_animations_selected.json \
      --xml-root .tools/zmxiyou1_swf_xml
"""

from __future__ import annotations

import argparse
import json
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


TWIPS_PER_PIXEL = 20.0


@dataclass(frozen=True)
class Matrix:
    a: float = 1.0
    b: float = 0.0
    c: float = 0.0
    d: float = 1.0
    tx: float = 0.0
    ty: float = 0.0

    def then(self, child: "Matrix") -> "Matrix":
        return Matrix(
            self.a * child.a + self.c * child.b,
            self.b * child.a + self.d * child.b,
            self.a * child.c + self.c * child.d,
            self.b * child.c + self.d * child.d,
            self.a * child.tx + self.c * child.ty + self.tx,
            self.b * child.tx + self.d * child.ty + self.ty,
        )

    def point(self, x: float, y: float) -> tuple[float, float]:
        return self.a * x + self.c * y + self.tx, self.b * x + self.d * y + self.ty


@dataclass
class Instance:
    character_id: int
    name: str = ""
    matrix: Matrix = Matrix()
    age: int = 0


@dataclass
class TimelineOp:
    kind: str
    depth: int
    character_id: int | None = None
    name: str | None = None
    matrix: Matrix | None = None
    move: bool = False


@dataclass
class Sprite:
    frame_count: int
    frame_ops: list[list[TimelineOp]]
    states: list[dict[int, Instance]] = field(default_factory=list)
    stop_frames: tuple[int, ...] = ()


@dataclass
class SwfModel:
    shapes: dict[int, tuple[float, float, float, float]] = field(default_factory=dict)
    sprites: dict[int, Sprite] = field(default_factory=dict)
    symbol_classes: dict[int, str] = field(default_factory=dict)


def matrix_from(element: ET.Element | None) -> Matrix | None:
    if element is None:
        return None
    return Matrix(
        float(element.get("scaleX", "1")),
        float(element.get("rotateSkew0", "0")),
        float(element.get("rotateSkew1", "0")),
        float(element.get("scaleY", "1")),
        float(element.get("translateX", "0")),
        float(element.get("translateY", "0")),
    )


def rect_from(element: ET.Element) -> tuple[float, float, float, float]:
    return (
        float(element.get("Xmin", "0")),
        float(element.get("Ymin", "0")),
        float(element.get("Xmax", "0")),
        float(element.get("Ymax", "0")),
    )


def union_rects(rects: list[tuple[float, float, float, float]]) -> tuple[float, float, float, float] | None:
    if not rects:
        return None
    return (
        min(rect[0] for rect in rects),
        min(rect[1] for rect in rects),
        max(rect[2] for rect in rects),
        max(rect[3] for rect in rects),
    )


def parse_definition(item: ET.Element, model: SwfModel) -> None:
    tag_type = item.get("type", "")
    if tag_type == "SymbolClassTag":
        tags = item.find("tags")
        names = item.find("names")
        if tags is not None and names is not None:
            character_ids = [int(child.text or "0") for child in tags.findall("item")]
            class_names = [child.text or "" for child in names.findall("item")]
            model.symbol_classes.update(
                {
                    character_id: class_name
                    for character_id, class_name in zip(character_ids, class_names)
                    if character_id and class_name
                }
            )
        return
    if tag_type.startswith("DefineShape"):
        shape_id = int(item.get("shapeId", "0"))
        bounds = item.find("shapeBounds")
        if shape_id and bounds is not None:
            model.shapes[shape_id] = rect_from(bounds)
        return
    if tag_type.startswith("DefineMorphShape"):
        shape_id = int(item.get("characterId", item.get("shapeId", "0")))
        candidates = [
            rect_from(bounds)
            for name in ("startBounds", "endBounds")
            if (bounds := item.find(name)) is not None
        ]
        merged = union_rects(candidates)
        if shape_id and merged is not None:
            model.shapes[shape_id] = merged
        return
    if tag_type != "DefineSpriteTag":
        return
    sprite_id = int(item.get("spriteId", "0"))
    expected_frames = int(item.get("frameCount", "1"))
    frames: list[list[TimelineOp]] = []
    current: list[TimelineOp] = []
    subtags = item.find("subTags")
    if subtags is not None:
        for child in subtags.findall("item"):
            child_type = child.get("type", "")
            if child_type == "ShowFrameTag":
                frames.append(current)
                current = []
            elif child_type == "RemoveObject2Tag":
                current.append(TimelineOp("remove", int(child.get("depth", "0"))))
            elif child_type.startswith("PlaceObject"):
                character = child.get("characterId")
                current.append(
                    TimelineOp(
                        "place",
                        int(child.get("depth", "0")),
                        int(character) if character else None,
                        child.get("name"),
                        matrix_from(child.find("matrix")),
                        child.get("placeFlagMove", "false") == "true",
                    )
                )
    while len(frames) < expected_frames:
        frames.append(current if len(frames) == expected_frames - 1 else [])
        current = []
    model.sprites[sprite_id] = Sprite(expected_frames, frames[:expected_frames])


def parse_swf_xml(path: Path) -> SwfModel:
    model = SwfModel()
    stack: list[ET.Element] = []
    for event, element in ET.iterparse(path, events=("start", "end")):
        if event == "start":
            stack.append(element)
            continue
        if element.tag == "item" and len(stack) == 3 and stack[-2].tag == "tags":
            parse_definition(element, model)
            element.clear()
        stack.pop()
    for sprite in model.sprites.values():
        build_states(sprite)
    return model


def build_states(sprite: Sprite) -> None:
    display: dict[int, Instance] = {}
    for ops in sprite.frame_ops:
        for op in ops:
            if op.kind == "remove":
                display.pop(op.depth, None)
                continue
            previous = display.get(op.depth)
            if op.move and previous is not None:
                display[op.depth] = Instance(
                    op.character_id if op.character_id is not None else previous.character_id,
                    op.name if op.name is not None else previous.name,
                    op.matrix if op.matrix is not None else previous.matrix,
                    0 if op.character_id is not None else previous.age,
                )
            elif op.character_id is not None:
                display[op.depth] = Instance(
                    op.character_id,
                    op.name or "",
                    op.matrix or Matrix(),
                    0,
                )
        sprite.states.append(
            {
                depth: Instance(instance.character_id, instance.name, instance.matrix, instance.age)
                for depth, instance in display.items()
            }
        )
        for instance in display.values():
            instance.age += 1


def apply_frame_script_stops(model: SwfModel, scripts_root: Path) -> None:
    """Apply the simple nested MovieClip stop() calls used by hit providers.

    AS3 frame scripts are stored in ABC rather than DefineSprite tags, so the
    XML alone cannot express a stopped nested playhead. FFDec's script export
    gives us the SymbolClass source needed to clamp those playheads. The
    audited source only uses direct ``stop()`` calls here; goto/rewind control
    is intentionally not guessed.
    """

    for character_id, class_name in model.symbol_classes.items():
        sprite = model.sprites.get(character_id)
        if sprite is None:
            continue
        script_path = scripts_root.joinpath(*class_name.split(".")).with_suffix(".as")
        if not script_path.exists():
            continue
        source = script_path.read_text(encoding="utf-8")
        functions = list(re.finditer(r"\bfunction\s+frame(\d+)\s*\(", source))
        stops: list[int] = []
        for index, match in enumerate(functions):
            end = functions[index + 1].start() if index + 1 < len(functions) else len(source)
            if re.search(r"\bstop\s*\(\s*\)\s*;", source[match.end() : end]):
                stops.append(int(match.group(1)) - 1)
        sprite.stop_frames = tuple(sorted(set(frame for frame in stops if frame >= 0)))


def timeline_frame(sprite: Sprite, age: int) -> int:
    if not sprite.states:
        return 0
    if sprite.stop_frames:
        first_stop = sprite.stop_frames[0]
        if age >= first_stop:
            return min(first_stop, len(sprite.states) - 1)
    return age % len(sprite.states)


def transformed_rect(
    rect: tuple[float, float, float, float], matrix: Matrix
) -> tuple[float, float, float, float]:
    x0, y0, x1, y1 = rect
    points = [matrix.point(x, y) for x, y in ((x0, y0), (x1, y0), (x0, y1), (x1, y1))]
    return (
        min(point[0] for point in points),
        min(point[1] for point in points),
        max(point[0] for point in points),
        max(point[1] for point in points),
    )


def character_bounds(
    model: SwfModel,
    character_id: int,
    frame: int,
    matrix: Matrix,
    recursion: tuple[int, ...] = (),
) -> tuple[float, float, float, float] | None:
    if character_id in model.shapes:
        return transformed_rect(model.shapes[character_id], matrix)
    sprite = model.sprites.get(character_id)
    if sprite is None or not sprite.states or character_id in recursion:
        return None
    state = sprite.states[timeline_frame(sprite, frame)]
    rects: list[tuple[float, float, float, float]] = []
    for instance in state.values():
        bounds = character_bounds(
            model,
            instance.character_id,
            instance.age,
            matrix.then(instance.matrix),
            recursion + (character_id,),
        )
        if bounds is not None:
            rects.append(bounds)
    return union_rects(rects)


def stick_boxes(model: SwfModel, sprite_id: int) -> list[list[list[float]]]:
    sprite = model.sprites.get(sprite_id)
    if sprite is None:
        return []
    result: list[list[list[float]]] = []
    for state in sprite.states:
        frame_boxes: list[list[float]] = []
        for instance in state.values():
            if instance.name != "stick":
                continue
            rect = character_bounds(model, instance.character_id, instance.age, instance.matrix)
            if rect is None:
                continue
            x0, y0, x1, y1 = rect
            frame_boxes.append(
                [
                    round(x0 / TWIPS_PER_PIXEL, 4),
                    round(y0 / TWIPS_PER_PIXEL, 4),
                    round((x1 - x0) / TWIPS_PER_PIXEL, 4),
                    round((y1 - y0) / TWIPS_PER_PIXEL, 4),
                ]
            )
        result.append(frame_boxes)
    return result


def stick_provider_ids(model: SwfModel, sprite_id: int) -> list[int]:
    sprite = model.sprites.get(sprite_id)
    if sprite is None:
        return []
    return sorted(
        {
            instance.character_id
            for state in sprite.states
            for instance in state.values()
            if instance.name == "stick"
        }
    )


def _parse_svg_number(value: str) -> float:
    match = re.match(r"\s*(-?(?:\d+(?:\.\d*)?|\.\d+))", value)
    if match is None:
        raise ValueError(f"Cannot parse SVG number: {value!r}")
    return float(match.group(1))


def svg_export_geometry(svg_root: Path, package: str, sprite_id: int) -> dict[str, list[float]]:
    package_root = svg_root / package
    directories = sorted(package_root.glob(f"DefineSprite_{sprite_id}*"))
    if len(directories) != 1:
        raise FileNotFoundError(
            f"Expected one FFDec SVG directory for {package} sprite {sprite_id}, got {directories}"
        )
    svg_files = sorted(
        directories[0].glob("*.svg"),
        key=lambda path: int(path.stem) if path.stem.isdigit() else path.stem,
    )
    if not svg_files:
        raise FileNotFoundError(f"No FFDec SVG frames found in {directories[0]}")
    geometries: set[tuple[float, float, float, float]] = set()
    # FFDec writes one SVG per frame but uses one fixed export canvas for the
    # whole sprite. Sampling the first/middle/last frame verifies that contract
    # without reparsing several gigabytes of repeated embedded SVG definitions.
    sample_indices = sorted({0, len(svg_files) // 2, len(svg_files) - 1})
    for index in sample_indices:
        svg_path = svg_files[index]
        root = ET.parse(svg_path).getroot()
        group = next((child for child in root if child.tag.endswith("}g") or child.tag == "g"), None)
        if group is None:
            raise ValueError(f"SVG frame has no root group: {svg_path}")
        matrix_match = re.fullmatch(r"matrix\(([^)]+)\)", group.get("transform", ""))
        if matrix_match is None:
            raise ValueError(f"SVG frame has no root matrix: {svg_path}")
        matrix_values = [float(value.strip()) for value in matrix_match.group(1).split(",")]
        if len(matrix_values) != 6:
            raise ValueError(f"Unexpected SVG root matrix: {svg_path}")
        geometries.add(
            (
                _parse_svg_number(root.get("width", "0")),
                _parse_svg_number(root.get("height", "0")),
                matrix_values[4],
                matrix_values[5],
            )
        )
    if len(geometries) != 1:
        raise ValueError(
            f"FFDec SVG registration changed between frames for {package} sprite {sprite_id}: "
            f"{sorted(geometries)}"
        )
    width, height, origin_x, origin_y = next(iter(geometries))
    return {
        "export_bounds": [
            round(-origin_x, 4),
            round(-origin_y, 4),
            round(width, 4),
            round(height, 4),
        ],
        "registration_to_atlas_center": [
            round(origin_x - width * 0.5, 4),
            round(origin_y - height * 0.5, 4),
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--xml-root", type=Path, required=True)
    parser.add_argument("--svg-root", type=Path)
    parser.add_argument("--scripts-root", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    selection: dict[str, Any] = json.loads(args.selection.read_text(encoding="utf-8"))
    packages = sorted({monster["package"] for monster in selection["monsters"].values()})
    models: dict[str, SwfModel] = {}
    for package in packages:
        xml_path = args.xml_root / f"{package}.xml"
        if xml_path.exists():
            models[package] = parse_swf_xml(xml_path)
            if args.scripts_root is not None:
                apply_frame_script_stops(
                    models[package], args.scripts_root / package / "scripts"
                )

    output: dict[str, Any] = {
        "schema_version": 1,
        "game": "zmxiyou1",
        "audit_status": "reviewed_source_geometry",
        "format": "[x_px, y_px, width_px, height_px] in source action-symbol coordinates",
        "source_tick_rate": 24,
        "runtime_mapping": {
            "left_facing_unflipped": True,
            "box_center_before_facing": (
                "sprite_offset + (source_box_center + registration_to_atlas_center) "
                "* definition.visual_scale"
            ),
            "box_size": "source_box_size * abs(definition.visual_scale)",
            "right_facing": "mirror the scaled box center around AnimatedSprite2D.position",
            "visual_offset": "definition.visual_offset is included with sprite_offset",
        },
        "evidence": {
            "geometry": "PlaceObject2/3 name=stick, recursive DefineSprite/DefineShape bounds and SWF MATRIX",
            "registration": "FFDec sprite SVG root bounds and root group translation",
            "timeline": "DefineSprite display lists plus direct AS3 frame-script stop() clamps",
            "not_used": [
                "sprite PNG visible-pixel bounds",
                "whole animation canvas bounds as attack geometry",
                "PlaceObject ratio on Sprite providers",
            ],
            "provider_rule": "All audited named stick providers resolve to DefineSpriteTag; ratio is not a Sprite playhead selector.",
        },
        "exceptions": {
            "M14": "projectile collision; no melee stick",
            "M21": "non-combat timeline",
            "M24": "independent hand/fire controller geometry",
            "M27": "non-combat chest timeline",
        },
        "monsters": {},
    }
    for monster_id, monster in selection["monsters"].items():
        model = models.get(monster["package"])
        if model is None:
            continue
        actions: dict[str, Any] = {}
        for action in monster["actions"]:
            sprite_id = int(action.get("source_symbol_id", 0))
            boxes = stick_boxes(model, sprite_id)
            if any(boxes):
                nonempty_frames = [index for index, frame_boxes in enumerate(boxes) if frame_boxes]
                providers = stick_provider_ids(model, sprite_id)
                action_output: dict[str, Any] = {
                    "source_action_label": action.get("source_action_label", ""),
                    "source_symbol_id": sprite_id,
                    "frame_count": len(boxes),
                    "source_canvas": action.get("source_canvas", []),
                    "active_frame_range": [nonempty_frames[0], nonempty_frames[-1]],
                    "box_count": sum(len(frame_boxes) for frame_boxes in boxes),
                    "multi_box_frames": [
                        index for index, frame_boxes in enumerate(boxes) if len(frame_boxes) > 1
                    ],
                    "stick_providers": [
                        {
                            "source_symbol_id": provider_id,
                            "symbol_type": "DefineSpriteTag",
                            "frame_count": model.sprites[provider_id].frame_count,
                            "symbol_class": model.symbol_classes.get(provider_id, ""),
                            "stop_frames": list(model.sprites[provider_id].stop_frames),
                            "place_object_ratio": "ignored_for_sprite",
                        }
                        for provider_id in providers
                    ],
                    "frames": boxes,
                }
                if args.svg_root is not None:
                    action_output.update(
                        svg_export_geometry(args.svg_root, monster["package"], sprite_id)
                    )
                actions[action["runtime_action"]] = action_output
        if actions:
            output["monsters"][monster_id] = {
                "package": monster["package"],
                "root_symbol_id": monster["root_symbol_id"],
                "actions": actions,
            }
    rendered = json.dumps(output, ensure_ascii=False, indent=2) + "\n"
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
