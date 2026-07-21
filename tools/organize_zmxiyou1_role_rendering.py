#!/usr/bin/env python3
"""Audit and organize ZMX1 role equipment selector frames by actor/slot/showid."""

from __future__ import annotations

import json
import filecmp
import os
import re
import xml.sax
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ROLE_ROOT = ROOT / "assets" / "extracted" / "full" / "zmxiyou1" / "characters" / "mixed_packages" / "Role_v7"
SCRIPT_ROOT = ROLE_ROOT / "scripts"
ROLE_FLA_ROOT = SCRIPT_ROOT / "Role_fla"
SPRITE_ROOT = ROLE_ROOT / "sprites"
XML_PATH = ROOT / ".tools" / "zmxiyou1_xml" / "Role_v7.xml"
EQUIPMENT_PATH = SCRIPT_ROOT / "my" / "AllEquipment.as"
CLASSIFIED_ROOT = ROOT / "assets" / "extracted" / "classified" / "zmxiyou1"
COMPACT_MANIFEST_PATH = ROOT / "sources" / "manifests" / "zmxiyou1_compact_classification.json"
MANIFEST_PATH = ROOT / "sources" / "manifests" / "zmxiyou1_role_rendering.json"
REPORT_PATH = ROOT / "sources" / "ZMXIYOU1_ROLE_RENDERING.md"

ROOT_ACTORS = {
    575: "悟空",
    1045: "唐僧",
}
JOB_ACTORS = {
    "战士": "悟空",
    "法师": "唐僧",
}
SLOT_NAMES = {
    "zbwq": "武器",
    "zbfj": "防具",
}


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


class SpriteReferenceHandler(xml.sax.ContentHandler):
    """Collect direct display-list references for every DefineSprite."""

    def __init__(self) -> None:
        super().__init__()
        self.edges: dict[int, set[int]] = defaultdict(set)
        self._sprite_id: int | None = None
        self._item_depth = 0

    def startElement(self, name: str, attrs: Any) -> None:  # noqa: N802 - SAX API
        if name != "item":
            return
        item_type = attrs.get("type", "")
        if self._sprite_id is None and item_type == "DefineSpriteTag":
            self._sprite_id = int(attrs["spriteId"])
            self._item_depth = 1
            return
        if self._sprite_id is None:
            return
        self._item_depth += 1
        if item_type.startswith("PlaceObject") and attrs.get("characterId"):
            self.edges[self._sprite_id].add(int(attrs["characterId"]))

    def endElement(self, name: str) -> None:  # noqa: N802 - SAX API
        if name != "item" or self._sprite_id is None:
            return
        self._item_depth -= 1
        if self._item_depth == 0:
            self._sprite_id = None


def parse_reference_graph() -> dict[int, set[int]]:
    handler = SpriteReferenceHandler()
    xml.sax.parse(str(XML_PATH), handler)
    return handler.edges


def reachable(graph: dict[int, set[int]], root: int) -> set[int]:
    result: set[int] = set()
    pending = [root]
    while pending:
        current = pending.pop()
        if current in result:
            continue
        result.add(current)
        pending.extend(graph.get(current, ()))
    return result


def sprite_directory(symbol_id: int) -> Path:
    matches = sorted(SPRITE_ROOT.glob(f"DefineSprite_{symbol_id}_*"))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one sprite directory for symbol {symbol_id}, found {len(matches)}")
    return matches[0]


def parse_selectors(graph: dict[int, set[int]]) -> list[dict[str, Any]]:
    actor_reachability = {actor: reachable(graph, root) for root, actor in ROOT_ACTORS.items()}
    selectors: list[dict[str, Any]] = []
    for script_path in sorted(ROLE_FLA_ROOT.glob("*.as")):
        text = script_path.read_text(encoding="utf-8", errors="ignore")
        if "curWeaponId" not in text and "curClothId" not in text:
            continue
        symbol_match = re.search(r'symbol="symbol(\d+)"', text)
        class_match = re.search(r"public dynamic class\s+([^\s]+)", text)
        if symbol_match is None or class_match is None:
            raise RuntimeError(f"Cannot parse equipment selector metadata: {script_path}")
        symbol_id = int(symbol_match.group(1))
        slot = "武器" if "curWeaponId" in text else "防具"
        actors = [actor for actor, ids in actor_reachability.items() if symbol_id in ids]
        if len(actors) != 1:
            raise RuntimeError(f"Selector {symbol_id} has ambiguous actor reachability: {actors}")
        offset_match = re.search(r"curClothId\s*-\s*(\d+)", text)
        offset = int(offset_match.group(1)) if offset_match else 0
        folder = sprite_directory(symbol_id)
        frame_paths = sorted(
            folder.glob("*.png"),
            key=lambda path: int(path.stem) if path.stem.isdigit() else path.name,
        )
        selectors.append(
            {
                "actor": actors[0],
                "slot": slot,
                "symbol_id": symbol_id,
                "symbol_name": folder.name.split("_", 2)[-1],
                "class_name": class_match.group(1),
                "source_script": relative(script_path),
                "selection_rule": "showid" if offset == 0 else f"showid-{offset}",
                "showid_offset": offset,
                "frame_paths": frame_paths,
            }
        )
    actor_order = {"悟空": 0, "唐僧": 1}
    slot_order = {"武器": 0, "防具": 1}
    return sorted(
        selectors,
        key=lambda row: (actor_order[str(row["actor"])], slot_order[str(row["slot"])], int(row["symbol_id"])),
    )


def parse_equipment() -> list[dict[str, Any]]:
    text = EQUIPMENT_PATH.read_text(encoding="utf-8", errors="ignore")
    pattern = re.compile(
        r'new\s+MyEquipObj\(\s*(\d+)\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"(zbfj|zbwq)"\s*,\s*"([^"]*)"'
    )
    equipment: list[dict[str, Any]] = []
    seen: set[tuple[str, str, int, str]] = set()
    for match in pattern.finditer(text):
        showid, name, code, raw_slot, job = match.groups()
        actor = JOB_ACTORS.get(job)
        if actor is None:
            continue
        row = {
            "actor": actor,
            "slot": SLOT_NAMES[raw_slot],
            "showid": int(showid),
            "name": name,
            "code": code,
        }
        key = (actor, row["slot"], row["showid"], code)
        if key not in seen:
            equipment.append(row)
            seen.add(key)
    return equipment


def remove_empty_parents(path: Path) -> None:
    current = path
    while current != CLASSIFIED_ROOT and CLASSIFIED_ROOT in current.parents:
        try:
            current.rmdir()
        except OSError:
            break
        current = current.parent


def organize_file(source: Path, old_destination: Path, new_destination: Path) -> None:
    new_destination.parent.mkdir(parents=True, exist_ok=True)
    if old_destination == new_destination:
        if not new_destination.exists():
            os.link(source, new_destination)
        elif not filecmp.cmp(source, new_destination, shallow=False):
            raise RuntimeError(f"Organized file differs from its original selector frame: {new_destination}")
        return
    if new_destination.exists():
        if not filecmp.cmp(source, new_destination, shallow=False):
            raise RuntimeError(f"Destination exists with different content: {new_destination}")
        if old_destination.exists() and filecmp.cmp(source, old_destination, shallow=False):
            old_destination.unlink()
    elif old_destination.exists():
        if not filecmp.cmp(source, old_destination, shallow=False):
            raise RuntimeError(f"Classified source differs from the original selector frame: {old_destination}")
        old_destination.replace(new_destination)
    else:
        os.link(source, new_destination)
    remove_empty_parents(old_destination.parent)


def main() -> None:
    compact = json.loads(COMPACT_MANIFEST_PATH.read_text(encoding="utf-8"))
    compact_by_source = {str(row["source"]): row for row in compact["files"]}
    graph = parse_reference_graph()
    selectors = parse_selectors(graph)
    equipment = parse_equipment()
    equipment_by_key: dict[tuple[str, str, int], list[dict[str, str]]] = defaultdict(list)
    for item in equipment:
        equipment_by_key[(item["actor"], item["slot"], item["showid"])].append(
            {"name": item["name"], "code": item["code"]}
        )

    manifest_selectors: list[dict[str, Any]] = []
    organized_files: list[dict[str, Any]] = []
    for selector in selectors:
        actor = str(selector["actor"])
        slot = str(selector["slot"])
        symbol_id = int(selector["symbol_id"])
        selector_frames: list[dict[str, Any]] = []
        for frame_path in selector.pop("frame_paths"):
            frame = int(frame_path.stem)
            showid = frame + int(selector["showid_offset"])
            source_key = relative(frame_path)
            compact_row = compact_by_source.get(source_key)
            if compact_row is None:
                raise RuntimeError(f"Selector frame is absent from compact manifest: {source_key}")
            relative_folder = Path("人物") / actor / "换装渲染" / slot / f"showid_{showid:02d}"
            file_name = f"part_{symbol_id}.png"
            new_destination = CLASSIFIED_ROOT / relative_folder / file_name
            old_destination = ROOT / str(compact_row["destination"])
            organize_file(frame_path, old_destination, new_destination)

            compact_row.update(
                {
                    "destination": relative(new_destination),
                    "category": relative_folder.as_posix(),
                    "file": file_name,
                    "role_rendering": True,
                    "actor": actor,
                    "slot": slot,
                    "showid": showid,
                    "selector_symbol_id": symbol_id,
                }
            )
            frame_row = {
                "frame": frame,
                "showid": showid,
                "source": source_key,
                "destination": relative(new_destination),
                "equipment": equipment_by_key.get((actor, slot, showid), []),
            }
            selector_frames.append(frame_row)
            organized_files.append(
                {
                    "source": source_key,
                    "destination": relative(new_destination),
                    "actor": actor,
                    "slot": slot,
                    "showid": showid,
                    "symbol_id": symbol_id,
                }
            )
        manifest_selectors.append({**selector, "frames": selector_frames})

    compact["role_rendering_audit"] = relative(MANIFEST_PATH)
    compact["counts_by_category"] = dict(
        sorted(
            (
                (category, sum(1 for row in compact["files"] if row["category"] == category))
                for category in {row["category"] for row in compact["files"]}
            )
        )
    )
    COMPACT_MANIFEST_PATH.write_text(
        json.dumps(compact, ensure_ascii=False, indent=2),
        encoding="utf-8",
        newline="\n",
    )

    generated_at = datetime.now().astimezone().isoformat(timespec="seconds")
    manifest = {
        "generated_at": generated_at,
        "source_package": "Role_v7.swf",
        "source_xml": relative(XML_PATH),
        "equipment_source": relative(EQUIPMENT_PATH),
        "actor_roots": {actor: symbol_id for symbol_id, actor in ROOT_ACTORS.items()},
        "rendering_model": "Flash 时间轴动作 + showid 驱动的武器/防具子 MovieClip 分层组合",
        "selectors": manifest_selectors,
        "equipment": equipment,
        "files": organized_files,
    }
    MANIFEST_PATH.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
        newline="\n",
    )

    lines = [
        "# 《造梦西游1》角色换装渲染审计",
        "",
        f"生成时间：{generated_at}",
        "",
        "## 结论",
        "",
        "造梦1与造梦3的换装核心逻辑相同：角色动作时间轴保持同步，武器和防具使用装备 `showid` 选择对应外观。差别在于造梦1把大量换装零件嵌在一个 `Role_v7.swf` 的多层 MovieClip 中；造梦3更接近独立 body/weapon 图集。因此这里的 PNG 是原 Flash 时间轴导出的换装层或局部零件，不应单独当成完整角色皮肤。",
        "",
        "## 原版调用链",
        "",
        "1. `BaseHero` 保存 `curClothId` 与 `curWeaponId`，装备变化时从 `zbfj`/`zbwq` 写入 showid。",
        "2. `Role2` 递归找到 `bodyEquip`，使用 `gotoAndStop(curClothId)` 切换防具。",
        "3. `Role_fla` 内的武器与防具选择器继续按 showid（部分高级防具层使用 `showid-2` 或 `showid-3`）切换帧。",
        "4. 动作 MovieClip、身体层和武器层由 Flash 时间轴共同变换，形成最终角色画面。",
        "",
        "关键证据位于 `Role_v7/scripts/my/MyEquipObj.as`、`Role_v7/scripts/user/User.as`、`Role_v7/scripts/base/BaseHero.as`、`Role_v7/scripts/export/hero/Role2.as` 与 `Role_v7/scripts/Role_fla/*.as`。",
        "",
        "## 与造梦3的对照",
        "",
        "- 共同点：都以防具/武器 showid 选择外观，并让身体、武器与动作帧同步。",
        "- 造梦1：`Role_v7.swf` 内嵌多层局部零件，最终角色需要 Flash 时间轴的层级、位移和显隐共同合成。",
        "- 造梦3：角色包已拆为 `Role1v690.swf`、`ROLE1_1.swf`、`ROLE1_EQUIP_1.swf` 等独立资源；当前 Godot 的 `layered_sprite_animator.gd` 也直接使用 Body/Weapon 两个 Sprite2D 和独立 showid atlas。",
        "- 因此机制相同，资源粒度不同。造梦1素材若移植到 Godot，需要先按动作重建多层合成，不能只把单个 selector PNG 当作整套 body atlas。",
        "",
        "## 图片位置",
        "",
        "- `人物/悟空/待机、移动、攻击…` 与 `人物/唐僧/待机、移动、攻击…`：角色根 MovieClip 导出的完整动作帧，用来观察最终动作轮廓和同步节奏。",
        "- `人物/悟空/换装渲染` 与 `人物/唐僧/换装渲染`：本次整理的原始武器/防具选择器帧，按槽位与 showid 查找。",
        "- 完整动作帧只反映导出时的时间轴状态；原 SWF 没有像造梦3那样为每套装备保存一张完整 body 图集。",
        "",
        "## 已整理选择器",
        "",
        "| 角色 | 槽位 | SWF 符号 | 原类名 | 选择规则 | 导出帧 |",
        "| --- | --- | ---: | --- | --- | ---: |",
    ]
    for selector in manifest_selectors:
        lines.append(
            f"| {selector['actor']} | {selector['slot']} | {selector['symbol_id']} | "
            f"{selector['class_name']} | {selector['selection_rule']} | {len(selector['frames'])} |"
        )
    lines.extend(["", "## showid 与装备名称", ""])
    for actor in ("悟空", "唐僧"):
        for slot in ("武器", "防具"):
            lines.extend([f"### {actor} · {slot}", "", "| showid | 装备 | 代码 |", "| ---: | --- | --- |"])
            grouped: dict[int, list[dict[str, Any]]] = defaultdict(list)
            for item in equipment:
                if item["actor"] == actor and item["slot"] == slot:
                    grouped[int(item["showid"])].append(item)
            selector_showids = {
                int(frame["showid"])
                for selector in manifest_selectors
                if selector["actor"] == actor and selector["slot"] == slot
                for frame in selector["frames"]
            }
            for showid in sorted(selector_showids | set(grouped)):
                names = "、".join(item["name"] for item in grouped.get(showid, [])) or "原始/未在装备表命名"
                codes = "、".join(item["code"] for item in grouped.get(showid, [])) or "—"
                lines.append(f"| {showid} | {names} | `{codes}` |")
            lines.append("")
    lines.extend(
        [
            "## ���录说明",
            "",
            "素材按 `人物/角色/换装渲染/武器或防具/showid_XX/part_符号号.png` 整理。`part_符号号` 保留原 SWF 追溯信息；同一 showid 下的多个防具 part 属于不同身体层或动作姿态，由动作时间轴按需选择和组合，并不表示同一时刻全部叠加。",
            "",
            f"逐张素材、原始路径、选择规则与装备名称见 `{relative(MANIFEST_PATH)}`。",
            "",
        ]
    )
    REPORT_PATH.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"Organized {len(organized_files)} selector frames from {len(manifest_selectors)} selectors.")


if __name__ == "__main__":
    main()
