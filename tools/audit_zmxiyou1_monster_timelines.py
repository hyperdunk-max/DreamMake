#!/usr/bin/env python3
"""Audit ZMX1 monster actions through nested SWF timelines.

The previous compact view only mapped exported monster *root* frames to
FrameLabel ranges.  Flash keeps child MovieClips playing when a parent is
stopped on a label, so the visual action can instead live in a nested sprite.
This script reads the original FFDec XML and records every dynamic child
timeline reachable from each exported monster action label.  It never edits
assets; its JSON output is the evidence input for the reclassification step.
"""

from __future__ import annotations

import json
import re
import xml.sax
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_MANIFEST = ROOT / "sources" / "manifests" / "zmxiyou1_image_classification.json"
OUTPUT = ROOT / "sources" / "manifests" / "zmxiyou1_monster_timeline_audit.json"
XML_ROOT = ROOT / ".tools" / "zmxiyou1_xml"
PACKAGES = ("Monster_v1", "Monster2_v4", "Monster3_v3")


@dataclass
class Placement:
    frame: int
    depth: int
    character_id: int | None
    name: str
    remove: bool = False


@dataclass
class SpriteTimeline:
    sprite_id: int
    frame_count: int
    labels: list[tuple[str, int]] = field(default_factory=list)
    placements: list[Placement] = field(default_factory=list)
    _frame: int = 1
    _item_depth: int = 0

    def add_item(self, item_type: str, attrs: Any) -> None:
        if item_type == "FrameLabelTag":
            self.labels.append((attrs.get("name", "other"), self._frame))
        elif item_type == "ShowFrameTag":
            self._frame += 1
        elif item_type.startswith("PlaceObject"):
            character = attrs.get("characterId", "")
            self.placements.append(
                Placement(
                    frame=self._frame,
                    depth=int(attrs.get("depth", "0") or 0),
                    character_id=int(character) if character.isdigit() else None,
                    name=attrs.get("name", ""),
                )
            )
        elif item_type.startswith("RemoveObject"):
            self.placements.append(
                Placement(
                    frame=self._frame,
                    depth=int(attrs.get("depth", "0") or 0),
                    character_id=None,
                    name="",
                    remove=True,
                )
            )

    def frame_labels(self) -> list[dict[str, int | str]]:
        result: list[dict[str, int | str]] = []
        for index, (name, start) in enumerate(self.labels):
            next_start = self.labels[index + 1][1] if index + 1 < len(self.labels) else self.frame_count + 1
            result.append({"name": name, "start": start, "end": max(start, next_start - 1)})
        return result

    def display_list_at(self, target_frame: int) -> dict[int, Placement]:
        display: dict[int, Placement] = {}
        for placement in self.placements:
            if placement.frame > target_frame:
                break
            if placement.remove:
                display.pop(placement.depth, None)
            elif placement.character_id is not None:
                display[placement.depth] = placement
        return display

    def referenced_ids(self) -> set[int]:
        return {item.character_id for item in self.placements if item.character_id is not None}


class TimelineHandler(xml.sax.ContentHandler):
    """SAX parser that preserves a sprite's labels and display-list changes."""

    def __init__(self) -> None:
        self.depth = 0
        self.sprites: dict[int, SpriteTimeline] = {}
        self.stack: list[tuple[int, SpriteTimeline]] = []

    def startElement(self, name: str, attrs: Any) -> None:  # noqa: N802
        if name != "item":
            return
        self.depth += 1
        item_type = attrs.get("type", "")
        if item_type == "DefineSpriteTag":
            sprite = SpriteTimeline(int(attrs["spriteId"]), int(attrs.get("frameCount", "0")))
            self.stack.append((self.depth, sprite))
            return
        if self.stack:
            self.stack[-1][1].add_item(item_type, attrs)

    def endElement(self, name: str) -> None:  # noqa: N802
        if name != "item":
            return
        if self.stack and self.stack[-1][0] == self.depth:
            _depth, sprite = self.stack.pop()
            self.sprites[sprite.sprite_id] = sprite
        self.depth -= 1


def parse_timelines(path: Path) -> dict[int, SpriteTimeline]:
    handler = TimelineHandler()
    xml.sax.parse(str(path), handler)
    return handler.sprites


def symbol_map(package_root: Path) -> dict[int, str]:
    result: dict[int, str] = {}
    for line in (package_root / "symbolClass" / "symbols.csv").read_text(encoding="utf-8-sig").splitlines():
        match = re.fullmatch(r'(\d+);"(.*)"', line)
        if match:
            result[int(match.group(1))] = match.group(2)
    return result


def dynamic_descendants(sprite_id: int, sprites: dict[int, SpriteTimeline]) -> list[int]:
    """Return all non-static nested timelines, root first, with cycle safety."""
    pending = [sprite_id]
    visited: set[int] = set()
    dynamic: list[int] = []
    while pending:
        current = pending.pop()
        if current in visited:
            continue
        visited.add(current)
        sprite = sprites.get(current)
        if sprite is None:
            continue
        if sprite.frame_count > 1:
            dynamic.append(current)
        pending.extend(sorted(sprite.referenced_ids(), reverse=True))
    return dynamic


def friendly_action(label: str) -> str:
    lower = label.lower()
    if lower in {"wait", "idle", "stand"}:
        return "待机"
    if lower == "walk":
        return "移动"
    if lower == "run":
        return "奔跑"
    if lower == "hurt":
        return "受伤"
    if lower in {"dead", "death"}:
        return "死亡"
    hit = re.fullmatch(r"hit[_-]?(\d+)(?:[_-](\d+))?", lower)
    if hit:
        return f"攻击{hit.group(1)}" + (f"_阶段{hit.group(2)}" if hit.group(2) else "")
    return label


def main() -> None:
    source = json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))
    roots = {int(row["id"]): row for row in source["monsters"]}
    rows: list[dict[str, Any]] = []
    per_monster: dict[str, dict[str, Any]] = {}

    for package in PACKAGES:
        package_root = ROOT / "assets" / "extracted" / "full" / "zmxiyou1" / "monsters" / package
        symbols = symbol_map(package_root)
        timelines = parse_timelines(XML_ROOT / f"{package}.xml")
        monster_roots = {
            symbol_id: symbol_name
            for symbol_id, symbol_name in symbols.items()
            if symbol_name.startswith("export.monster.Monster") and "." not in symbol_name.removeprefix("export.monster.")
        }
        for root_id, class_name in sorted(monster_roots.items()):
            monster = roots.get(root_id)
            root_sprite = timelines.get(root_id)
            if monster is None or root_sprite is None:
                continue
            monster_number = int(class_name.rsplit("Monster", 1)[1])
            monster_key = f"M{monster_number:02d}"
            monster_row = per_monster.setdefault(
                monster_key,
                {
                    "package": package,
                    "root_symbol_id": root_id,
                    "root_symbol": class_name,
                    "source_folder": monster["folder"],
                    "actions": [],
                },
            )
            for label in root_sprite.frame_labels():
                display = root_sprite.display_list_at(int(label["start"]))
                direct = [item for _depth, item in sorted(display.items()) if item.character_id is not None]
                providers: list[dict[str, Any]] = []
                seen: set[int] = set()
                for item in direct:
                    for provider_id in dynamic_descendants(item.character_id, timelines):
                        if provider_id == root_id or provider_id in seen:
                            continue
                        seen.add(provider_id)
                        provider = timelines[provider_id]
                        providers.append(
                            {
                                "symbol_id": provider_id,
                                "symbol_name": symbols.get(provider_id, f"character_{provider_id}"),
                                "frame_count": provider.frame_count,
                                "root_depth": item.depth,
                                "root_instance": item.name,
                                "has_labels": bool(provider.labels),
                            }
                        )
                action = {
                    "label": label["name"],
                    "folder": friendly_action(str(label["name"])),
                    "root_frame_start": label["start"],
                    "root_frame_end": label["end"],
                    "providers": providers,
                }
                monster_row["actions"].append(action)
                for provider in providers:
                    rows.append({"monster": monster_key, "action": label["name"], **provider})

    payload = {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "purpose": "Source-of-truth audit of nested dynamic MovieClip timelines reachable from each exported ZMX1 monster action label.",
        "rule": "A provider is retained as a complete action timeline when a root action label places it (directly or through a static wrapper) and its SWF DefineSprite frameCount is greater than one.",
        "packages": list(PACKAGES),
        "monsters": dict(sorted(per_monster.items())),
        "provider_rows": rows,
        "counts": {
            "monsters": len(per_monster),
            "actions": sum(len(item["actions"]) for item in per_monster.values()),
            "provider_assignments": len(rows),
            "unique_provider_symbols": len({(item["monster"], item["symbol_id"]) for item in rows}),
        },
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload["counts"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
