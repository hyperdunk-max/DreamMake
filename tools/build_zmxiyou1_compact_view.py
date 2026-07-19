#!/usr/bin/env python3
"""Build a compact, action-labelled view of the classified ZMX1 visuals."""

from __future__ import annotations

import json
import os
import re
import xml.sax
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_MANIFEST = ROOT / "sources" / "manifests" / "zmxiyou1_image_classification.json"
TEMP_ROOT = ROOT / "assets" / "extracted" / "classified" / "zmxiyou1_compact"
FINAL_ROOT = ROOT / "assets" / "extracted" / "classified" / "zmxiyou1"
MANIFEST_PATH = ROOT / "sources" / "manifests" / "zmxiyou1_compact_classification.json"
REPORT_PATH = ROOT / "sources" / "ZMXIYOU1_COMPACT_CLASSIFICATION.md"
XML_FILES = {
    "Role_v7": ROOT / ".tools" / "zmxiyou1_xml" / "Role_v7.xml",
    "Monster_v1": ROOT / ".tools" / "zmxiyou1_xml" / "Monster_v1.xml",
    "Monster2_v4": ROOT / ".tools" / "zmxiyou1_xml" / "Monster2_v4.xml",
    "Monster3_v3": ROOT / ".tools" / "zmxiyou1_xml" / "Monster3_v3.xml",
}


@dataclass(frozen=True)
class FrameLabel:
    name: str
    start: int
    end: int


class SpriteLabelHandler(xml.sax.ContentHandler):
    def __init__(self) -> None:
        super().__init__()
        self.sprites: dict[int, dict[str, Any]] = {}
        self._sprite_id: int | None = None
        self._item_depth: int = 0
        self._frame: int = 1
        self._frame_count: int = 0
        self._labels: list[tuple[str, int]] = []

    def startElement(self, name: str, attrs: Any) -> None:  # noqa: N802 - SAX API
        if name != "item":
            return
        item_type = attrs.get("type", "")
        if self._sprite_id is None and item_type == "DefineSpriteTag":
            self._sprite_id = int(attrs["spriteId"])
            self._item_depth = 1
            self._frame = 1
            self._frame_count = int(attrs.get("frameCount", "0"))
            self._labels = []
            return
        if self._sprite_id is None:
            return
        self._item_depth += 1
        if item_type == "FrameLabelTag":
            self._labels.append((attrs.get("name", "other"), self._frame))
        elif item_type == "ShowFrameTag":
            self._frame += 1

    def endElement(self, name: str) -> None:  # noqa: N802 - SAX API
        if name != "item" or self._sprite_id is None:
            return
        self._item_depth -= 1
        if self._item_depth != 0:
            return
        labels: list[FrameLabel] = []
        for index, (label_name, start) in enumerate(self._labels):
            next_start = self._labels[index + 1][1] if index + 1 < len(self._labels) else self._frame_count + 1
            labels.append(FrameLabel(label_name, start, max(start, next_start - 1)))
        self.sprites[self._sprite_id] = {
            "frame_count": self._frame_count,
            "labels": labels,
        }
        self._sprite_id = None
        self._item_depth = 0
        self._frame = 1
        self._frame_count = 0
        self._labels = []


def parse_sprite_labels(path: Path) -> dict[int, dict[str, Any]]:
    handler = SpriteLabelHandler()
    xml.sax.parse(str(path), handler)
    return handler.sprites


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def safe_name(value: str, maximum: int = 42) -> str:
    value = value.rsplit(".", 1)[-1]
    value = re.sub(r"^(?:Monster\d+|Role_fla|Monster\d*_fla)[._]?", "", value)
    value = re.sub(r"[<>:\"/\\|?*\x00-\x1f]", "_", value).strip(" ._")
    value = re.sub(r"\s+", "_", value)
    return (value or "其他")[:maximum]


def monster_folder(info: dict[str, Any]) -> str:
    number = int(str(info["class"])[7:])
    name = str(info.get("name", "")).strip()
    return f"M{number:02d}_{safe_name(name)}" if name else f"M{number:02d}"


def action_meta(label: str) -> tuple[str, str]:
    lower = label.lower()
    if lower in {"wait", "stand", "idle"}:
        return "待机", "idle"
    if lower == "walk":
        return "移动", "move"
    if lower == "run":
        return "奔跑", "run"
    walk_variant = re.fullmatch(r"walk[_-]?(\d+)", lower)
    if walk_variant:
        number = int(walk_variant.group(1))
        return f"移动{number}", f"move{number}"
    wait_variant = re.fullmatch(r"(?:wait|stand|idle)[_-]?(\d+)", lower)
    if wait_variant:
        number = int(wait_variant.group(1))
        return f"待机{number}", f"idle{number}"
    if lower == "hurt":
        return "受伤", "hurt"
    if lower in {"afterhurt", "recover"}:
        return "受伤恢复", "recover"
    if lower in {"dead", "death"}:
        return "死亡", "death"
    hit = re.fullmatch(r"hit[_-]?(\d+)(?:[_-](\d+))?", lower)
    if hit:
        number = int(hit.group(1))
        if hit.group(2) is not None:
            phase = int(hit.group(2))
            return f"攻击{number}_阶段{phase}", f"attack{number}_{phase}"
        return f"攻击{number}", f"attack{number}"
    jump = re.fullmatch(r"jump[_-]?(\d+)", lower)
    if jump:
        number = int(jump.group(1))
        return f"跳跃{number}", f"jump{number}"
    if any(word in lower for word in ("appear", "birth", "show", "come")):
        return "出场", "appear"
    if lower == "fly":
        return "飞行", "fly"
    if lower == "turntoegg":
        return "变蛋", "egg"
    if lower == "reburn":
        return "重燃", "burn"
    ascii_slug = re.sub(r"[^a-z0-9]+", "_", lower).strip("_")
    return safe_name(label), ascii_slug or "action"


def action_for_frame(sprite: dict[str, Any] | None, frame: int) -> FrameLabel:
    if sprite is None:
        return FrameLabel("other", 1, frame)
    labels: list[FrameLabel] = sprite["labels"]
    selected: FrameLabel | None = None
    for label in labels:
        if label.start <= frame <= label.end:
            selected = label
            break
    return selected if selected is not None else FrameLabel("other", 1, int(sprite["frame_count"]))


def called_actions(script_paths: list[Path]) -> set[str]:
    result: set[str] = set()
    for path in script_paths:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        result.update(re.findall(r'(?:curAction|lastHit)\s*(?:==|!=|=)\s*"([^"]+)"', text))
        result.update(re.findall(r'gotoAnd(?:Play|Stop)\(\s*"([^"]+)"', text))
    return result


def output_category(record: dict[str, Any], monsters_by_old_folder: dict[str, dict[str, Any]]) -> tuple[Path, str, str]:
    category = str(record["category"])
    symbol_name = str(record.get("symbol_name", ""))
    leaf = safe_name(symbol_name)
    parts = category.split("/")

    if category.startswith("怪物/") and len(parts) >= 3:
        old_folder = parts[1]
        info = monsters_by_old_folder[old_folder]
        base = Path("怪物") / monster_folder(info)
        if parts[2] == "特效":
            return base / "特效" / leaf, "fx", "monster_effect"
        return base, "frame", "monster_body"
    if category == "特效/怪物公共特效":
        return Path("怪物") / "公共特效" / leaf, "fx", "effect"
    if category == "特效/公共战斗特效":
        return Path("人物") / "公共特效" / leaf, "fx", "effect"
    if category.startswith("特效/悟空"):
        return Path("人物") / "悟空" / "特效" / leaf, "fx", "effect"
    if category.startswith("特效/唐僧"):
        return Path("人物") / "唐僧" / "特效" / leaf, "fx", "effect"
    if category.startswith("人物/悟空"):
        if "动作片段" in category:
            return Path("人物") / "悟空" / "动作零件" / leaf, "part", "role_part"
        return Path("人物") / "悟空", "frame", "role_body"
    if category.startswith("人物/唐僧"):
        if "动作片段" in category:
            return Path("人物") / "唐僧" / "动作零件" / leaf, "part", "role_part"
        if symbol_name == "export.hero.Role2Shadow":
            return Path("人物") / "唐僧" / "分身", "frame", "role_body"
        return Path("人物") / "唐僧", "frame", "role_body"

    ui_map = {
        "UI/HUD与血条": "HUD",
        "UI/技能界面": "技能",
        "UI/菜单与面板": "菜单",
    }
    if category in ui_map:
        return Path("UI") / ui_map[category] / leaf, "ui", "ui"
    if category.startswith("UI/背包"):
        symbol_folder = leaf if symbol_name else "其他"
        return Path("UI") / "背包" / symbol_folder, "bag", "ui"
    if category.startswith("UI/公共界面与图标"):
        symbol_folder = leaf if symbol_name else "其他"
        return Path("UI") / "公共" / symbol_folder, "ui", "ui"
    if category.startswith("UI/4399外壳"):
        return Path("UI") / "外壳" / (leaf if symbol_name else "其他"), "ui", "ui"

    package = str(record["package"])
    asset_type = str(record["asset_type"])
    return Path("未分类") / package / asset_type, "asset", "unclassified"


def link(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise RuntimeError(f"Duplicate compact destination: {destination}")
    os.link(source, destination)


def main() -> None:
    if TEMP_ROOT.exists() and any(TEMP_ROOT.iterdir()):
        raise SystemExit(f"Compact output is not empty: {TEMP_ROOT}")
    source_manifest = json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))
    sprite_maps = {key: parse_sprite_labels(path) for key, path in XML_FILES.items()}

    monsters_by_old_folder: dict[str, dict[str, Any]] = {}
    for info in source_manifest["monsters"]:
        old_folder = str(info["folder"])
        monsters_by_old_folder[old_folder] = info

    base_actions: dict[str, set[str]] = {}
    for package in ("Monster_v1", "Monster2_v4", "Monster3_v3"):
        package_root = ROOT / "assets" / "extracted" / "full" / "zmxiyou1" / "monsters" / package
        base_actions[package] = called_actions(
            [package_root / "scripts" / "base" / "BaseObject.as", package_root / "scripts" / "base" / "BaseMonster.as"]
        )

    records = sorted(source_manifest["files"], key=lambda row: str(row["source"]))
    counters: Counter[str] = Counter()
    compact_records: list[dict[str, Any]] = []
    category_counts: Counter[str] = Counter()
    action_audit: dict[str, dict[str, Any]] = {}

    for record in records:
        source = ROOT / str(record["source"])
        rel_folder, prefix, kind = output_category(record, monsters_by_old_folder)
        package = str(record["package"])
        character_id = record.get("character_id")
        action_label = ""
        code_called: bool | None = None

        if kind in {"monster_body", "role_body"} and str(record["asset_type"]) == "sprites" and character_id is not None:
            frame_match = re.fullmatch(r"(\d+)\.png", source.name, flags=re.IGNORECASE)
            if frame_match:
                frame_number = int(frame_match.group(1))
                sprite = sprite_maps.get(package, {}).get(int(character_id))
                label = action_for_frame(sprite, frame_number)
                action_label = label.name
                action_folder, prefix = action_meta(label.name)
                rel_folder = rel_folder / action_folder
                local_index = frame_number - label.start + 1
                file_name = f"{prefix}_{local_index:03d}{source.suffix.lower()}"
                if kind == "monster_body":
                    old_monster_folder = str(record["category"]).split("/")[1]
                    info = monsters_by_old_folder[old_monster_folder]
                    monster_class = str(info["class"])
                    package_root = ROOT / "assets" / "extracted" / "full" / "zmxiyou1" / "monsters" / package
                    class_script = package_root / "scripts" / "export" / "monster" / f"{monster_class}.as"
                    calls = base_actions.get(package, set()) | called_actions([class_script])
                    code_called = label.name in calls
                    audit_key = monster_folder(info)
                    audit = action_audit.setdefault(
                        audit_key,
                        {"class": monster_class, "name": info.get("name", ""), "actions": {}, "calls": sorted(calls)},
                    )
                    audit["actions"][label.name] = {
                        "folder": action_folder,
                        "start": label.start,
                        "end": label.end,
                        "code_called": code_called,
                    }
            else:
                file_name = "frame_001" + source.suffix.lower()
        else:
            counter_key = rel_folder.as_posix()
            counters[counter_key] += 1
            file_name = f"{prefix}_{counters[counter_key]:04d}{source.suffix.lower()}"

        destination = TEMP_ROOT / rel_folder / file_name
        link(source, destination)
        logical_destination = FINAL_ROOT / rel_folder / file_name
        compact_record = {
            "source": relative(source),
            "destination": relative(logical_destination),
            "category": rel_folder.as_posix(),
            "file": file_name,
            "package": package,
            "symbol_name": record.get("symbol_name", ""),
            "character_id": character_id,
            "action_label": action_label,
            "code_called": code_called,
            "evidence": record.get("evidence", ""),
        }
        compact_records.append(compact_record)
        category_counts[rel_folder.as_posix()] += 1

    generated_at = datetime.now().astimezone().isoformat(timespec="seconds")
    manifest = {
        "generated_at": generated_at,
        "source_manifest": relative(SOURCE_MANIFEST),
        "classified_root": relative(FINAL_ROOT),
        "storage": "NTFS hard links",
        "files": compact_records,
        "monster_action_audit": action_audit,
        "counts_by_category": dict(sorted(category_counts.items())),
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "# 《造梦西游1》简洁资源分类",
        "",
        f"生成时间：{generated_at}",
        "",
        "目录已经压缩为 `人物 / 怪物 / UI / 未分类` 四层主结构。怪物本体依据 SWF `FrameLabel` 拆为待机、移动、攻击、受伤、死亡和特殊动作。",
        "文件名使用 `idle_001.png`、`attack1_001.png`、`hurt_001.png` 等简洁形式。",
        "",
        "## 怪物动画",
        "",
        "| 怪物 | 原作名 | 动画标签 |",
        "| --- | --- | --- |",
    ]
    for monster_key, audit in sorted(action_audit.items()):
        labels = ", ".join(
            f"{label}({data['start']}-{data['end']})"
            for label, data in sorted(audit["actions"].items(), key=lambda item: int(item[1]["start"]))
        )
        lines.append(f"| {monster_key} | {audit['name'] or '未写明'} | {labels} |")
    lines.extend(
        [
            "",
            "每个动作的原始标签、帧区间和代码调用证据见：",
            f"`{relative(MANIFEST_PATH)}`",
            "",
            "分类目录使用硬链接，仅供浏览和复制；不要直接编辑。",
            "",
        ]
    )
    report = "\n".join(lines)
    REPORT_PATH.write_text(report, encoding="utf-8")
    (TEMP_ROOT / "README.md").write_text(report, encoding="utf-8")

    print(
        json.dumps(
            {
                "files": len(compact_records),
                "monsters": len(action_audit),
                "monster_action_groups": sum(len(row["actions"]) for row in action_audit.values()),
                "categories": len(category_counts),
                "temp_root": relative(TEMP_ROOT),
                "final_root": relative(FINAL_ROOT),
                "manifest": relative(MANIFEST_PATH),
                "report": relative(REPORT_PATH),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
