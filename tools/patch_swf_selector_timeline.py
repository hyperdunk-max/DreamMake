#!/usr/bin/env python3
"""Freeze or blank selected DefineSprite timelines in an FFDec SWF XML dump.

This is intentionally an offline conversion helper.  It lets the ZMX1 probe
hold armor selectors on one showid while rendering weapon variants, without
adding any Flash-specific behavior to the Godot runtime.
"""

from __future__ import annotations

import argparse
import copy
import re
import xml.etree.ElementTree as ET
from pathlib import Path


SPRITE_BLOCK = re.compile(
    r'(?ms)^    <item type="DefineSpriteTag"(?=[^>]*\bspriteId="(?P<id>\d+)")[^>]*>.*?^    </item>\r?\n?'
)


def _merge_place(previous: ET.Element | None, update: ET.Element) -> ET.Element:
    result = copy.deepcopy(previous if previous is not None else update)
    for key in ("characterId", "ratio", "name", "clipDepth"):
        if key in update.attrib:
            result.set(key, update.attrib[key])

    children_by_type = {child.get("type"): child for child in result}
    for child in update:
        child_type = child.get("type")
        old_child = children_by_type.get(child_type)
        if old_child is not None:
            result.remove(old_child)
        result.append(copy.deepcopy(child))

    result.set("placeFlagMove", "false")
    result.set("placeFlagHasCharacter", "true" if result.get("characterId") else "false")
    child_types = {child.get("type") for child in result}
    result.set("placeFlagHasMatrix", "true" if "MATRIX" in child_types else "false")
    result.set(
        "placeFlagHasColorTransform",
        "true" if "CXFORMWITHALPHA" in child_types else "false",
    )
    return result


def _freeze_sprite(block: str, frame: int | None) -> str:
    outer = ET.fromstring(block.strip())
    outer.set("frameCount", "1")
    sub_tags = outer.find("subTags")
    if sub_tags is None:
        raise ValueError("DefineSpriteTag is missing subTags")

    display: dict[int, ET.Element] = {}
    selected: dict[int, ET.Element] = {}
    current_frame = 1
    if frame is not None:
        for tag in list(sub_tags):
            tag_type = tag.get("type", "")
            if tag_type.startswith("PlaceObject"):
                depth = int(tag.get("depth", "0"))
                display[depth] = _merge_place(display.get(depth), tag)
            elif tag_type.startswith("RemoveObject"):
                display.pop(int(tag.get("depth", "0")), None)
            elif tag_type == "ShowFrameTag":
                if current_frame == frame:
                    selected = {depth: copy.deepcopy(tag) for depth, tag in display.items()}
                    break
                current_frame += 1
        else:
            raise ValueError(f"Timeline has no frame {frame}")

    sub_tags.clear()
    for depth in sorted(selected):
        sub_tags.append(selected[depth])
    sub_tags.append(ET.Element("item", {"type": "ShowFrameTag", "forceWriteAsLong": "false"}))

    rendered = ET.tostring(outer, encoding="unicode", short_empty_elements=True)
    lines = rendered.splitlines()
    return "\n".join("    " + line for line in lines) + "\n"


def _keep_characters(block: str, character_ids: set[int], preserve_timeline: bool = False) -> str:
    outer = ET.fromstring(block.strip())
    if preserve_timeline:
        return _keep_characters_timeline(outer, character_ids)
    outer.set("frameCount", "1")
    sub_tags = outer.find("subTags")
    if sub_tags is None:
        raise ValueError("DefineSpriteTag is missing subTags")
    kept: list[ET.Element] = []
    for tag in list(sub_tags):
        tag_type = tag.get("type", "")
        if tag_type.startswith("PlaceObject") and int(tag.get("characterId", "-1")) in character_ids:
            kept.append(copy.deepcopy(tag))
        elif tag_type == "ShowFrameTag":
            break
    sub_tags.clear()
    for tag in kept:
        sub_tags.append(tag)
    sub_tags.append(ET.Element("item", {"type": "ShowFrameTag", "forceWriteAsLong": "false"}))
    rendered = ET.tostring(outer, encoding="unicode", short_empty_elements=True)
    return "\n".join("    " + line for line in rendered.splitlines()) + "\n"


def _keep_characters_timeline(outer: ET.Element, character_ids: set[int]) -> str:
    """Keep selected direct placements while preserving every ShowFrameTag.

    A PlaceObject update without a characterId continues the placement at the
    same depth, so it must be retained while that depth is occupied by a kept
    character.  This is the difference between a one-pose probe and a full
    action timeline.
    """
    sub_tags = outer.find("subTags")
    if sub_tags is None:
        raise ValueError("DefineSpriteTag is missing subTags")
    active_depths: set[int] = set()
    kept: list[ET.Element] = []
    for tag in list(sub_tags):
        tag_type = tag.get("type", "")
        if tag_type.startswith("PlaceObject"):
            depth = int(tag.get("depth", "0"))
            raw_character = tag.get("characterId")
            if raw_character is not None:
                if int(raw_character) in character_ids:
                    kept.append(copy.deepcopy(tag))
                    active_depths.add(depth)
                else:
                    active_depths.discard(depth)
            elif depth in active_depths:
                kept.append(copy.deepcopy(tag))
        elif tag_type.startswith("RemoveObject"):
            depth = int(tag.get("depth", "0"))
            if depth in active_depths:
                kept.append(copy.deepcopy(tag))
                active_depths.discard(depth)
        elif tag_type == "ShowFrameTag":
            kept.append(copy.deepcopy(tag))
    sub_tags.clear()
    for tag in kept:
        sub_tags.append(tag)
    rendered = ET.tostring(outer, encoding="unicode", short_empty_elements=True)
    return "\n".join("    " + line for line in rendered.splitlines()) + "\n"


def patch_xml(
    source: Path,
    destination: Path,
    operations: dict[int, int | None],
    filters: dict[int, set[int]],
    timeline_filters: dict[int, set[int]] | None = None,
) -> None:
    text = source.read_text(encoding="utf-8")
    found: set[int] = set()

    def replace(match: re.Match[str]) -> str:
        sprite_id = int(match.group("id"))
        if sprite_id not in operations and sprite_id not in filters and sprite_id not in (timeline_filters or {}):
            return match.group(0)
        found.add(sprite_id)
        if timeline_filters is not None and sprite_id in timeline_filters:
            return _keep_characters(match.group(0), timeline_filters[sprite_id], True)
        if sprite_id in filters:
            return _keep_characters(match.group(0), filters[sprite_id])
        return _freeze_sprite(match.group(0), operations[sprite_id])

    patched = SPRITE_BLOCK.sub(replace, text)
    missing = sorted((set(operations) | set(filters) | set(timeline_filters or {})) - found)
    if missing:
        raise ValueError(f"Selector sprites not found: {missing}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(patched, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--freeze",
        action="append",
        default=[],
        metavar="SPRITE_ID:FRAME",
        help="Freeze a selector at a one-based frame.",
    )
    parser.add_argument(
        "--blank",
        action="append",
        default=[],
        type=int,
        metavar="SPRITE_ID",
        help="Replace a selector with one empty frame.",
    )
    parser.add_argument(
        "--keep-character",
        action="append",
        default=[],
        metavar="SPRITE_ID:CHARACTER_ID[,CHARACTER_ID...]",
        help="Keep only direct placements of the listed characters in a sprite.",
    )
    parser.add_argument(
        "--keep-character-all",
        action="append",
        default=[],
        metavar="SPRITE_ID:CHARACTER_ID[,CHARACTER_ID...]",
        help="Keep selected direct placements while preserving the full timeline.",
    )
    args = parser.parse_args()

    operations: dict[int, int | None] = {sprite_id: None for sprite_id in args.blank}
    for spec in args.freeze:
        sprite_id, frame = (int(part) for part in spec.split(":", 1))
        operations[sprite_id] = frame
    filters: dict[int, set[int]] = {}
    for spec in args.keep_character:
        sprite_text, characters_text = spec.split(":", 1)
        filters[int(sprite_text)] = {int(value) for value in characters_text.split(",")}
    timeline_filters: dict[int, set[int]] = {}
    for spec in args.keep_character_all:
        sprite_text, characters_text = spec.split(":", 1)
        timeline_filters[int(sprite_text)] = {int(value) for value in characters_text.split(",")}
    if not operations and not filters and not timeline_filters:
        raise SystemExit("At least one patch operation is required")
    patch_xml(args.input, args.output, operations, filters, timeline_filters)
    print(f"patched {len(operations) + len(filters) + len(timeline_filters)} timelines -> {args.output}")


if __name__ == "__main__":
    main()
