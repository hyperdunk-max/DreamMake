#!/usr/bin/env python3
"""Refine ZMX1 visual ownership through SWF definition references.

The first-pass manifest classifies directly exported symbols.  This module
follows DefineSprite/DefineShape/bitmap references from those named roots so
anonymous child assets can be assigned without guessing.  Assets with no
source or visual evidence are rejected from the browseable classification;
the complete extraction remains untouched.
"""

from __future__ import annotations

import json
import re
import xml.sax
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_MANIFEST = ROOT / "sources" / "manifests" / "zmxiyou1_image_classification.json"
AUDIT_PATH = ROOT / "sources" / "manifests" / "zmxiyou1_reference_audit.json"
XML_FILES = {
    "Role_v7": ROOT / ".tools" / "zmxiyou1_xml" / "Role_v7.xml",
    "Monster_v1": ROOT / ".tools" / "zmxiyou1_xml" / "Monster_v1.xml",
    "Monster2_v4": ROOT / ".tools" / "zmxiyou1_xml" / "Monster2_v4.xml",
    "Monster3_v3": ROOT / ".tools" / "zmxiyou1_xml" / "Monster3_v3.xml",
    "OtherMat_v9": ROOT / ".tools" / "zmxiyou1_xml" / "OtherMat_v9.xml",
    "backpack_v2": ROOT / ".tools" / "zmxiyou1_xml" / "backpack_v2.xml",
    "main_game": ROOT / ".tools" / "zmxiyou1_xml" / "main_game.xml",
}

UNCERTAIN_PREFIX = "待确认/"
DEFINITION_ID_ATTRIBUTES = (
    "spriteId",
    "shapeId",
    "characterID",
    "buttonId",
    "fontId",
    "textId",
    "editTextId",
    "morphShapeId",
    "soundId",
    "binaryDataId",
    "videoStreamId",
)
REFERENCE_ATTRIBUTES = ("characterId", "bitmapId")
OTHER_MAT_PACKAGE = "OtherMat_v9"
OTHER_MAT_ROOT = ROOT / "assets" / "extracted" / "full" / "zmxiyou1" / "shared" / "OtherMat_v9"
DIGIT_CATEGORY_PREFIX = "UI/公共素材/数字/"
BAKED_INVENTORY_ICON_PREFIX = "UI/公共素材/装备/背包图标"
DROP_EQUIPMENT_ICON_PREFIX = "UI/公共素材/装备/掉落图标"
UNIVERSAL_EQUIPMENT_ICON_PREFIX = "UI/公共素材/装备/通用图标"
SKILL_ICON_SYMBOLS = {
    "slz",
    "hytx",
    "lys",
    "lyfb",
    "hmz",
    "blb",
    "xbz",
    "shy",
    "tjgl",
    "smp",
}
DIGIT_STYLE_NAMES = {
    "pnum": "pnum_玩家数值",
    "bunum": "bunum_恢复数值",
    "bulnum": "bulnum_子弹数值",
    "hurtnum": "hurtnum_伤害数值",
    "bnum": "bnum_暴击数值",
    "num": "num_连击数值",
}


class ReferenceGraphHandler(xml.sax.ContentHandler):
    """Stream a large FFDec XML file and retain only definition references."""

    def __init__(self) -> None:
        super().__init__()
        self.depth = 0
        self.definition_stack: list[tuple[int, int]] = []
        self.definitions: dict[int, str] = {}
        self.edges: dict[int, set[int]] = defaultdict(set)

    def startElement(self, name: str, attrs: Any) -> None:  # noqa: N802 - SAX API
        if name != "item":
            return
        self.depth += 1
        item_type = attrs.get("type", "")
        definition_id: int | None = None
        if item_type.startswith("Define"):
            for key in DEFINITION_ID_ATTRIBUTES:
                value = attrs.get(key, "")
                if value.isdigit():
                    definition_id = int(value)
                    break
        if definition_id is not None:
            self.definition_stack.append((self.depth, definition_id))
            self.definitions[definition_id] = item_type

        owner = self.definition_stack[-1][1] if self.definition_stack else 0
        if definition_id is None:
            for key in REFERENCE_ATTRIBUTES:
                value = attrs.get(key, "")
                if value.isdigit():
                    self.edges[owner].add(int(value))

    def endElement(self, name: str) -> None:  # noqa: N802 - SAX API
        if name != "item":
            return
        if self.definition_stack and self.definition_stack[-1][0] == self.depth:
            self.definition_stack.pop()
        self.depth -= 1


def parse_reference_graph(path: Path) -> ReferenceGraphHandler:
    handler = ReferenceGraphHandler()
    xml.sax.parse(str(path), handler)
    return handler


def is_uncertain(record: dict[str, Any]) -> bool:
    return str(record["category"]).startswith(UNCERTAIN_PREFIX)


def seed_category(record: dict[str, Any]) -> str | None:
    """Return a trusted root classification, including reviewed main symbols."""

    package = str(record["package"])
    category = str(record["category"])
    symbol_name = str(record.get("symbol_name", ""))
    if not is_uncertain(record):
        return category
    if package != "main_game" or not symbol_name:
        return None
    if symbol_name == "GOGO":
        return "UI/战斗提示"
    return "场景与地图/关卡元件"


def manual_seed_categories(source_manifest: dict[str, Any]) -> dict[tuple[str, int], set[str]]:
    folders = {str(row["class"]): str(row["folder"]) for row in source_manifest["monsters"]}
    return {
        # Both classes create SpecialEffectBullet("Monster13Bullet1").
        ("Monster2_v4", 509): {
            f"怪物/{folders['Monster13']}/特效",
            f"怪物/{folders['Monster16']}/特效",
        },
        # Monster24.as imports Monster23Child.* and executes new Fire(this).
        ("Monster2_v4", 755): {f"怪物/{folders['Monster24']}/特效"},
        # Role2.as creates hit4FallDown; 元件4_97 plays Role2_hit4.
        ("Role_v7", 656): {"特效/唐僧_Role2"},
        ("Role_v7", 657): {"特效/唐僧_Role2"},
    }


def equipment_codes() -> set[str]:
    """Read the authoritative icon codes from AllEquipment.as."""

    path = OTHER_MAT_ROOT / "scripts" / "my" / "AllEquipment.as"
    text = path.read_text(encoding="utf-8", errors="ignore")
    return set(re.findall(r'new\s+MyEquipObj\([^,]+,"[^"]*","([^"]+)"', text))


def othermat_specialized_seeds(symbols: dict[int, str]) -> dict[int, set[str]]:
    """Create reviewed roots for visually distinct public-asset families."""

    equip_codes = equipment_codes()
    seeds: dict[int, set[str]] = defaultdict(set)
    for character_id, symbol_name in symbols.items():
        leaf = symbol_name.rsplit(".", 1)[-1]
        timeline_base = re.sub(r"_\d+$", "", leaf)
        if leaf in equip_codes:
            seeds[character_id].add("UI/公共素材/装备/背包图标")
            continue
        if leaf.startswith("fall_") and leaf[5:] in equip_codes:
            seeds[character_id].add("UI/公共素材/装备/掉落图标")
            continue
        digit_match = re.fullmatch(r"(pnum|bunum|bulnum|hurtnum|bnum|num)([0-9])", leaf)
        if digit_match:
            style = DIGIT_STYLE_NAMES[digit_match.group(1)]
            seeds[character_id].add(f"UI/公共素材/数字/{style}")
            continue
        if leaf == "miss":
            seeds[character_id].add("UI/公共素材/数字/战斗文字")
            continue
        if timeline_base in SKILL_ICON_SYMBOLS:
            seeds[character_id].add("UI/公共素材/技能图标")

    seeds[505].add("UI/公共素材/关卡入口")  # export.SelectPLace
    seeds[702].add("UI/公共素材/过场动画/片尾")  # export.scene.Ending
    seeds[716].add("UI/公共素材/过场动画/片头")  # export.scene.Opening
    return seeds


def propagate_claims(
    seeds: dict[int, set[str]],
    edges: dict[int, set[int]],
) -> dict[int, set[tuple[int, str]]]:
    claims: dict[int, set[tuple[int, str]]] = defaultdict(set)
    for seed_id, categories in seeds.items():
        pending = [seed_id]
        visited: set[int] = set()
        while pending:
            character_id = pending.pop()
            if character_id in visited:
                continue
            visited.add(character_id)
            claims[character_id].update((seed_id, category) for category in categories)
            pending.extend(edges.get(character_id, ()))
    return claims


def specialized_public_category(categories: set[str]) -> str:
    if len(categories) == 1:
        return next(iter(categories))
    # The XML graph proves these components are genuinely reused by multiple
    # reviewed public-asset roots.  Keep that fact instead of applying an
    # arbitrary priority between entrance, cutscene, digit, or icon families.
    return "UI/公共素材/共享元件"


def category_identity(category: str) -> tuple[str, str]:
    parts = category.split("/")
    if category.startswith("人物/") and len(parts) >= 2:
        return "role", parts[1]
    if category.startswith("特效/悟空"):
        return "role", "悟空_Role1"
    if category.startswith("特效/唐僧"):
        return "role", "唐僧_Role2"
    if category.startswith("怪物/") and len(parts) >= 2:
        return "monster", parts[1]
    if category == "特效/怪物公共特效":
        return "monster_common", "怪物公共"
    if category == "特效/公共战斗特效":
        return "battle_common", "战斗公共"
    if category.startswith("UI/"):
        return "ui", parts[1] if len(parts) >= 2 else "UI"
    if category.startswith("场景与地图/"):
        return "scene", parts[1] if len(parts) >= 2 else "场景"
    return "other", category


def component_category(categories: set[str], package: str) -> str:
    """Describe inferred children without pretending they are root animations."""

    if not categories:
        raise ValueError("Cannot classify a component without a source claim")
    identities = {category_identity(category) for category in categories}
    kinds = {kind for kind, _owner in identities}
    owners = {owner for _kind, owner in identities}

    if len(identities) == 1:
        kind, owner = next(iter(identities))
        category = next(iter(categories))
        if kind == "role":
            if category.startswith("特效/"):
                return f"特效/{owner}/组成元件"
            return f"人物/{owner}/组成元件"
        if kind == "monster":
            if category.endswith("/特效"):
                return f"怪物/{owner}/特效元件"
            return f"怪物/{owner}/组成元件"
        if kind == "ui":
            return f"{category}/组成元件"
        if kind == "scene":
            return "场景与地图/关卡元件"
        return category

    if kinds == {"role"}:
        if len(owners) == 1:
            return f"人物/{next(iter(owners))}/共享元件"
        return "人物/公共元件"
    if kinds <= {"monster", "monster_common"}:
        monster_owners = {owner for kind, owner in identities if kind == "monster"}
        if len(monster_owners) == 1 and "monster_common" not in kinds:
            return f"怪物/{next(iter(monster_owners))}/共享元件"
        return "怪物/公共元件"
    if kinds == {"ui"}:
        return "UI/公共界面与图标/共享元件"
    if kinds == {"scene"}:
        return "场景与地图/共享元件"
    return f"公共元件/{package}"


def refine_manifest(source_manifest: dict[str, Any], *, write_audit: bool = True) -> dict[str, Any]:
    records = list(source_manifest["files"])
    records_by_package: dict[str, list[dict[str, Any]]] = defaultdict(list)
    symbol_by_id: dict[str, dict[int, str]] = defaultdict(dict)
    for record in records:
        package = str(record["package"])
        records_by_package[package].append(record)
        character_id = record.get("character_id")
        symbol_name = str(record.get("symbol_name", ""))
        if character_id is not None and symbol_name:
            symbol_by_id[package].setdefault(int(character_id), symbol_name)

    manual = manual_seed_categories(source_manifest)
    claims_by_package: dict[str, dict[int, set[tuple[int, str]]]] = {}
    specialized_claims_by_package: dict[str, dict[int, set[tuple[int, str]]]] = {}
    package_audit: dict[str, dict[str, Any]] = {}

    for package, xml_path in XML_FILES.items():
        if not xml_path.exists():
            raise FileNotFoundError(f"Missing SWF XML evidence: {xml_path}")
        graph = parse_reference_graph(xml_path)
        seeds: dict[int, set[str]] = defaultdict(set)
        for record in records_by_package.get(package, []):
            character_id = record.get("character_id")
            if character_id is None:
                continue
            category = seed_category(record)
            if category is not None:
                seeds[int(character_id)].add(category)
        for (seed_package, character_id), categories in manual.items():
            if seed_package == package:
                seeds[character_id].update(categories)

        claims = propagate_claims(seeds, graph.edges)
        claims_by_package[package] = claims
        specialized_claims: dict[int, set[tuple[int, str]]] = {}
        if package == OTHER_MAT_PACKAGE:
            specialized_claims = propagate_claims(
                othermat_specialized_seeds(symbol_by_id[package]),
                graph.edges,
            )
        specialized_claims_by_package[package] = specialized_claims
        package_audit[package] = {
            "xml": xml_path.relative_to(ROOT).as_posix(),
            "definitions": len(graph.definitions),
            "reference_edges": sum(len(children) for children in graph.edges.values()),
            "trusted_seed_symbols": len(seeds),
            "reachable_character_ids": len(claims),
            "specialized_public_character_ids": len(specialized_claims),
        }

    retained: list[dict[str, Any]] = []
    rejected: list[dict[str, Any]] = []
    resolution_counts: Counter[str] = Counter()
    category_counts: Counter[str] = Counter()

    for original in records:
        record = dict(original)
        package = str(record["package"])
        character_id = record.get("character_id")
        specialized_claims = (
            specialized_claims_by_package.get(package, {}).get(int(character_id), set())
            if character_id is not None
            else set()
        )
        if specialized_claims:
            categories = {category for _seed_id, category in specialized_claims}
            seed_ids = sorted({seed_id for seed_id, _category in specialized_claims})
            seed_labels = [symbol_by_id[package].get(seed_id, f"character_{seed_id}") for seed_id in seed_ids]
            refined_category = specialized_public_category(categories)
            if refined_category.startswith(DIGIT_CATEGORY_PREFIX):
                rejected.append(
                    {
                        "source": record["source"],
                        "package": package,
                        "asset_type": record["asset_type"],
                        "character_id": character_id,
                        "category": refined_category,
                        "reason": "数字位图由 Godot Text、Style 与 shader 在运行时生成",
                    }
                )
                resolution_counts["rejected_redundant"] += 1
                continue
            if refined_category.startswith(BAKED_INVENTORY_ICON_PREFIX):
                rejected.append(
                    {
                        "source": record["source"],
                        "package": package,
                        "asset_type": record["asset_type"],
                        "character_id": character_id,
                        "category": refined_category,
                        "reason": "背包格背景已烘焙，与透明装备通用图标重复",
                    }
                )
                resolution_counts["rejected_redundant"] += 1
                continue
            if refined_category.startswith(DROP_EQUIPMENT_ICON_PREFIX):
                refined_category = refined_category.replace(
                    DROP_EQUIPMENT_ICON_PREFIX,
                    UNIVERSAL_EQUIPMENT_ICON_PREFIX,
                    1,
                )
            record["original_category"] = record["category"]
            record["category"] = refined_category
            record["confidence"] = "high"
            record["classification_method"] = "source-backed public visual family"
            record["reference_seed_ids"] = seed_ids
            record["reference_categories"] = sorted(categories)
            record["evidence"] = (
                "公共素材自动分类：SWF XML 引用根 "
                + ", ".join(seed_labels[:8])
                + (f" 等{len(seed_labels)}项" if len(seed_labels) > 8 else "")
            )
            retained.append(record)
            category_counts[refined_category] += 1
            resolution_counts["specialized_public"] += 1
            continue
        if not is_uncertain(record):
            record["classification_method"] = "direct symbolClass/source/package evidence"
            retained.append(record)
            category_counts[str(record["category"])] += 1
            resolution_counts["direct"] += 1
            continue

        claims = (
            claims_by_package.get(package, {}).get(int(character_id), set())
            if character_id is not None
            else set()
        )
        if not claims:
            reason = "无 character_id 且视觉为空白" if character_id is None else "无可信命名根符号引用"
            rejected.append(
                {
                    "source": record["source"],
                    "package": package,
                    "asset_type": record["asset_type"],
                    "character_id": character_id,
                    "reason": reason,
                }
            )
            resolution_counts["rejected"] += 1
            continue

        categories = {category for _seed_id, category in claims}
        seed_ids = sorted({seed_id for seed_id, _category in claims})
        seed_labels = [symbol_by_id[package].get(seed_id, f"character_{seed_id}") for seed_id in seed_ids]
        refined_category = component_category(categories, package)
        record["original_category"] = record["category"]
        record["category"] = refined_category
        record["confidence"] = "high"
        record["classification_method"] = "SWF XML reference graph"
        record["reference_seed_ids"] = seed_ids
        record["reference_categories"] = sorted(categories)
        label_preview = ", ".join(seed_labels[:6])
        if len(seed_labels) > 6:
            label_preview += f" 等{len(seed_labels)}项"
        record["evidence"] = f"SWF XML 引用链：{package} character {character_id} 被根符号 {label_preview} 引用"
        retained.append(record)
        category_counts[refined_category] += 1
        resolution_counts["reference_graph"] += 1

    generated_at = datetime.now().astimezone().isoformat(timespec="seconds")
    audit = {
        "generated_at": generated_at,
        "source_manifest": SOURCE_MANIFEST.relative_to(ROOT).as_posix(),
        "policy": "保留有 symbolClass、源码、包来源或 SWF XML 引用链证据且运行时仍需要的素材；无法归属、视觉为空白、可由运行时生成或已烘焙重复的分类副本删除，完整提取库不变。",
        "counts": {
            "input_files": len(records),
            "retained_files": len(retained),
            "rejected_files": len(rejected),
            **dict(sorted(resolution_counts.items())),
        },
        "packages": package_audit,
        "manual_source_evidence": [
            {
                "package": "OtherMat_v9",
                "classification": "装备、关卡入口、数字、技能图标、片头片尾",
                "evidence": "AllEquipment.as 装备表、SelectPLace.as 关卡选择界面、ANumber.as 数字前缀调用、技能图标视觉抽样，以及 export.scene.Opening/Ending 引用子树。",
            },
            {
                "package": "Monster2_v4",
                "character_id": 509,
                "symbol": "Monster13Bullet1",
                "classification": "Monster13 与 Monster16 共用特效",
                "evidence": "Monster13.as:87 与 Monster16.as:87 均创建 SpecialEffectBullet(\"Monster13Bullet1\")；视觉为飞剑。",
            },
            {
                "package": "Monster2_v4",
                "character_id": 755,
                "symbol": "export.monster.Monster23Child.Fire",
                "classification": "Monster24 特效",
                "evidence": "Monster24.as:7 导入 Monster23Child.*，Monster24.as:154 执行 new Fire(this)；视觉为火焰。",
            },
            {
                "package": "Role_v7",
                "character_ids": [656, 657],
                "symbols": ["Role_fla.元件4_97", "hit4FallDown"],
                "classification": "唐僧第四段攻击特效",
                "evidence": "元件4_97.as:18 播放 Role2_hit4；Role2.as:281 创建 hit4FallDown；视觉为黄/青落地光柱。",
            },
        ],
        "rejected": rejected,
        "counts_by_category": dict(sorted(category_counts.items())),
    }
    if write_audit:
        AUDIT_PATH.parent.mkdir(parents=True, exist_ok=True)
        AUDIT_PATH.write_text(
            json.dumps(audit, ensure_ascii=False, indent=2),
            encoding="utf-8",
            newline="\n",
        )

    result = dict(source_manifest)
    result["generated_at"] = generated_at
    result["policy"] = audit["policy"]
    result["reference_audit"] = AUDIT_PATH.relative_to(ROOT).as_posix()
    result["counts_by_category"] = dict(sorted(category_counts.items()))
    result["files"] = retained
    result["rejected_files"] = rejected
    return result


def main() -> None:
    source_manifest = json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))
    refined = refine_manifest(source_manifest, write_audit=True)
    print(
        json.dumps(
            {
                "input_files": len(source_manifest["files"]),
                "retained_files": len(refined["files"]),
                "rejected_files": len(refined["rejected_files"]),
                "audit": AUDIT_PATH.relative_to(ROOT).as_posix(),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
