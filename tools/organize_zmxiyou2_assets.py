#!/usr/bin/env python3
"""Historical ZMX2 organizer retained only for audit reference.

The original move mode predates ``sources/ASSET_ORGANIZATION_GUIDE.md`` and is
disabled. The former ``--restore-full`` path is also disabled because ZMX2 now
uses ``classified`` as its canonical library and ``full`` as a disposable
extraction area. Re-extract from the retained raw/decoded SWFs when needed.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "assets" / "extracted" / "full" / "zmxiyou2"
CLASSIFIED_PARENT = ROOT / "assets" / "extracted" / "classified"
FINAL_ROOT = CLASSIFIED_PARENT / "zmxiyou2"
TEMP_ROOT = CLASSIFIED_PARENT / "zmxiyou2_organizing"
MANIFEST_PATH = ROOT / "sources" / "manifests" / "zmxiyou2_initial_organization.json"
REPORT_PATH = ROOT / "sources" / "ZMXIYOU2_INITIAL_ORGANIZATION.md"

VISUAL_EXTENSIONS = {".png", ".jpg", ".jpeg", ".svg"}
AUDIO_EXTENSIONS = {".mp3", ".wav", ".ogg"}
FONT_EXTENSIONS = {".ttf", ".otf", ".woff", ".woff2"}

ROLE_NAMES = {"Role1": "悟空", "Role2": "唐僧", "Role3": "八戒"}


@dataclass(frozen=True)
class Package:
    key: str
    root: Path
    kind: str
    symbols: dict[int, str]


@dataclass(frozen=True)
class PlannedFile:
    source: Path
    destination: Path
    package: str
    category: str
    character_id: int | None
    symbol_name: str
    evidence: str


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def safe_name(value: str, maximum: int = 72) -> str:
    value = value.rsplit(".", 1)[-1]
    value = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", value).strip(" ._")
    value = re.sub(r"\s+", "_", value)
    return (value or "未命名")[:maximum]


def package_key(path: Path) -> str:
    return path.relative_to(SOURCE_ROOT).as_posix().replace("/", "__")


def read_symbols(path: Path) -> dict[int, str]:
    result: dict[int, str] = {}
    with path.open("r", encoding="utf-8", errors="replace", newline="") as handle:
        for row in csv.reader(handle, delimiter=";"):
            if len(row) >= 2 and row[0].isdigit():
                result[int(row[0])] = row[1]
    return result


def package_kind(path: Path) -> str:
    rel = path.relative_to(SOURCE_ROOT).as_posix()
    if rel.startswith("audio/"):
        return "audio"
    if rel.startswith("characters/"):
        return "role"
    if rel == "shared/Pig9":
        return "role3"
    if rel.startswith("shared/backpack"):
        return "backpack"
    if rel.startswith("shared/Common"):
        return "common"
    if rel.startswith("shared/main"):
        return "main"
    if rel.startswith("shared/OtherMat"):
        return "othermat"
    if "portal" in rel.lower():
        return "portal"
    if rel.startswith("stages/"):
        return "stage"
    return "unknown"


def discover_packages() -> list[Package]:
    packages: list[Package] = []
    for symbols_path in sorted(SOURCE_ROOT.rglob("symbolClass/symbols.csv")):
        root = symbols_path.parent.parent
        packages.append(Package(package_key(root), root, package_kind(root), read_symbols(symbols_path)))
    return sorted(packages, key=lambda item: len(item.root.parts), reverse=True)


def owner_package(path: Path, packages: list[Package]) -> Package | None:
    for package in packages:
        try:
            path.relative_to(package.root)
            return package
        except ValueError:
            continue
    return None


def visual_character_id(package: Package, path: Path) -> int | None:
    parts = path.relative_to(package.root).parts
    if not parts:
        return None
    if parts[0] == "sprites" and len(parts) >= 2:
        match = re.match(r"DefineSprite_(\d+)(?:_|$)", parts[1])
        return int(match.group(1)) if match else None
    if parts[0] == "buttons" and len(parts) >= 2:
        match = re.match(r"DefineButton(?:2)?_(\d+)(?:_|$)", parts[1])
        return int(match.group(1)) if match else None
    if parts[0] in {"images", "shapes", "morphshapes", "sounds"}:
        match = re.match(r"(\d+)(?:_|\.|$)", path.name)
        return int(match.group(1)) if match else None
    return None


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore") if path.exists() else ""


def monster_catalog(packages: list[Package]) -> dict[str, dict[str, object]]:
    catalog: dict[str, dict[str, object]] = {}
    for package in packages:
        if package.kind not in {"stage", "common"}:
            continue
        for symbol_name in package.symbols.values():
            match = re.fullmatch(r"export\.monster\.(Monster\d+)", symbol_name)
            if not match:
                continue
            monster_class = match.group(1)
            script = package.root / "scripts" / "export" / "monster" / f"{monster_class}.as"
            text = read_text(script)
            name_match = re.search(r'monsterName\s*=\s*"([^"]+)"', text)
            display_name = name_match.group(1).strip() if name_match else ""
            is_boss = bool(re.search(r"isBoss\s*=\s*true", text))
            current = catalog.get(monster_class)
            candidate = {
                "class": monster_class,
                "name": display_name,
                "boss": is_boss,
                "package": package.key,
                "script": relative(script) if script.exists() else "",
            }
            if current is None or (not current["name"] and display_name):
                catalog[monster_class] = candidate
    return catalog


def monster_folder(monster_class: str, catalog: dict[str, dict[str, object]]) -> str:
    number = int(monster_class[7:])
    display_name = str(catalog.get(monster_class, {}).get("name", "")).strip()
    return f"M{number:02d}_{safe_name(display_name)}" if display_name else f"M{number:02d}"


def role_category(package: Package, character_id: int | None, symbol_name: str) -> tuple[str, str]:
    leaf = symbol_name.rsplit(".", 1)[-1]
    exact = re.fullmatch(r"export\.hero\.(Role[123])", symbol_name)
    if exact:
        role = exact.group(1)
        return f"人物/{ROLE_NAMES[role]}/本体", f"symbolClass {symbol_name}"
    if symbol_name == "export.hero.Role2Shadow":
        return "人物/唐僧/分身", "symbolClass export.hero.Role2Shadow"
    if leaf in {"HeroBeHurt", "MonsterBeHurt1", "MonsterBeHurt2", "WsEffect"}:
        return "人物/公共战斗特效", f"共享战斗符号 {leaf}"

    if "八戒" in symbol_name or "Role3" in symbol_name:
        owner = "八戒"
    elif "唐僧" in symbol_name or "Role2" in symbol_name:
        owner = "唐僧"
    elif "悟空" in symbol_name or "Role1" in symbol_name:
        owner = "悟空"
    elif package.kind == "role3":
        owner = "八戒"
    elif character_id is not None and character_id > 608:
        owner = "唐僧"
    else:
        owner = "悟空"

    effect_words = ("bullet", "effect", "技能", "冰柱", "加血", "升龙斩", "冲刺斩", "无双", "fire", "cure")
    action_words = ("攻击", "奔跑", "等待", "跳", "受伤", "弹跳", "落下", "hit")
    lower = symbol_name.lower()
    if any(word in lower for word in effect_words):
        return f"人物/{owner}/特效/{safe_name(leaf)}", f"角色效果符号 {symbol_name}"
    if any(word in lower for word in action_words):
        return f"人物/{owner}/动作零件/{safe_name(leaf)}", f"角色动作符号 {symbol_name}"
    return f"人物/{owner}/待识别元件", "按角色资源包和符号编号初步归属"


def stage_name(package: Package) -> str:
    match = re.search(r"stages__(\d+)", package.key)
    return f"关卡{int(match.group(1)):02d}" if match else safe_name(package.key)


def category_for_visual(
    package: Package,
    character_id: int | None,
    symbol_name: str,
    catalog: dict[str, dict[str, object]],
) -> tuple[str, str]:
    leaf = symbol_name.rsplit(".", 1)[-1]
    lower = symbol_name.lower()

    if package.kind in {"role", "role3"}:
        return role_category(package, character_id, symbol_name)

    if package.kind in {"stage", "common"}:
        root_match = re.fullmatch(r"export\.monster\.(Monster\d+)", symbol_name)
        prefix_match = re.match(r"(?:export\.monster\.)?(Monster\d+)", leaf)
        monster_class = root_match.group(1) if root_match else (prefix_match.group(1) if prefix_match else "")
        if monster_class:
            section = "本体" if root_match else "特效与组成元件"
            return f"怪物/{monster_folder(monster_class, catalog)}/{section}", f"怪物符号 {symbol_name}"
        if package.kind == "stage":
            scene_words = ("bg", "floor", "files", "stage", "aurora", "boat", "wall", "door")
            if any(word in lower for word in scene_words):
                return f"场景与地图/{stage_name(package)}", f"关卡场景符号 {symbol_name}"
            return f"场景与地图/{stage_name(package)}/待识别元件", "来自独立关卡包，尚未反查到唯一导出类"
        if "magicweapon" in lower or symbol_name.startswith("export.magicWeapon."):
            return f"公共元件/法宝/{safe_name(leaf)}", f"法宝符号 {symbol_name}"
        if symbol_name.startswith("export.aura.") or leaf in {"BossDead", "poisonUp", "poisonHead"}:
            return f"公共元件/战斗特效/{safe_name(leaf)}", f"公共特效符号 {symbol_name}"
        if "cartoon" in lower:
            return "场景与地图/过场动画", f"过场符号 {symbol_name}"
        return "公共元件/Common_v7/待识别", "来自公共资源包"

    if package.kind == "backpack":
        return "UI/背包", "backpack_v5 专用资源包"
    if package.kind == "othermat":
        if any(word in lower for word in ("opening", "ending", "scene")):
            return "场景与地图/过场动画", f"过场符号 {symbol_name}"
        if any(word in lower for word in ("skill", "passive", "buyskill")):
            return "UI/技能", f"技能界面符号 {symbol_name}"
        if any(word in lower for word in ("gameinfo", "batter", "blood", "hurt", "num")):
            return "UI/HUD", f"HUD 符号 {symbol_name}"
        return "UI/菜单与面板", "OtherMat_v10 公共界面资源包"
    if package.kind == "main":
        if any(word in lower for word in ("gamesence", "stage", "floor", "bg", "boat", "wall", "door", "stoppoint")):
            return "场景与地图/主程序关卡结构", f"主程序场景符号 {symbol_name}"
        if any(word in lower for word in ("gameinfo", "blood", "loading", "alert", "cue")):
            return "UI/HUD与提示", f"主程序 UI 符号 {symbol_name}"
        return "公共元件/主程序待识别", "来自主程序资源包"
    if package.kind == "portal":
        return "UI/4399外壳", "网页外壳资源包"
    if package.kind == "audio":
        return "公共元件/音频包视觉元件", "Music 包中的视觉资源"
    return f"待识别/{safe_name(package.key)}", "未识别资源包"


def category_for_audio(symbol_name: str) -> tuple[str, str]:
    lower = symbol_name.lower()
    for role, actor in ROLE_NAMES.items():
        if role.lower() in lower:
            return f"音频/人物/{actor}", f"音频符号 {symbol_name}"
    if lower.startswith("bg"):
        return "音频/背景音乐", f"音频符号 {symbol_name}"
    return "音频/其他", "未命名或公共音频"


def category_for_file(
    package: Package,
    path: Path,
    catalog: dict[str, dict[str, object]],
) -> tuple[str, int | None, str, str]:
    suffix = path.suffix.lower()
    character_id = visual_character_id(package, path)
    symbol_name = package.symbols.get(character_id, "") if character_id is not None else ""
    if suffix in VISUAL_EXTENSIONS:
        category, evidence = category_for_visual(package, character_id, symbol_name, catalog)
        return category, character_id, symbol_name, evidence
    if suffix in AUDIO_EXTENSIONS:
        category, evidence = category_for_audio(symbol_name)
        return category, character_id, symbol_name, evidence
    if suffix in FONT_EXTENSIONS:
        return "UI/字体", character_id, symbol_name, "字体文件"
    return f"结构证据/{safe_name(package.key)}", character_id, symbol_name, "FFDec 源码、符号表或结构数据"


def destination_for(
    package: Package,
    source: Path,
    category: str,
    character_id: int | None,
    symbol_name: str,
) -> Path:
    package_folder = safe_name(package.key, 96)
    parts = source.relative_to(package.root).parts
    asset_kind = parts[0] if parts else "other"
    if character_id is not None:
        symbol_folder = f"symbol_{character_id}_{safe_name(symbol_name, 48)}"
        if asset_kind in {"sprites", "buttons"} and len(parts) >= 2:
            tail = Path(*parts[2:]) if len(parts) > 2 else Path(source.name)
        else:
            tail = Path(source.name)
        return Path(category) / package_folder / symbol_folder / safe_name(asset_kind) / tail
    return Path(category) / package_folder / Path(*parts)


def build_plan() -> tuple[list[PlannedFile], list[Path], dict[str, dict[str, object]]]:
    packages = discover_packages()
    catalog = monster_catalog(packages)
    planned: list[PlannedFile] = []
    unowned: list[Path] = []
    destinations: dict[str, Path] = {}
    for source in sorted(path for path in SOURCE_ROOT.rglob("*") if path.is_file()):
        package = owner_package(source, packages)
        if package is None:
            unowned.append(source)
            continue
        category, character_id, symbol_name, evidence = category_for_file(package, source, catalog)
        rel_destination = destination_for(package, source, category, character_id, symbol_name)
        collision_key = rel_destination.as_posix().casefold()
        prior = destinations.get(collision_key)
        if prior is not None:
            raise RuntimeError(f"Destination collision: {prior} and {source} -> {rel_destination}")
        destinations[collision_key] = source
        planned.append(
            PlannedFile(source, rel_destination, package.key, category, character_id, symbol_name, evidence)
        )
    return planned, unowned, catalog


def remove_empty_directories(root: Path) -> int:
    removed = 0
    if not root.exists():
        return removed
    for path in sorted((item for item in root.rglob("*") if item.is_dir()), key=lambda item: len(item.parts), reverse=True):
        if not any(path.iterdir()):
            path.rmdir()
            removed += 1
    if root.exists() and not any(root.iterdir()):
        root.rmdir()
        removed += 1
    return removed


def accounting(planned: Iterable[PlannedFile]) -> tuple[int, int, Counter[str], Counter[str]]:
    rows = list(planned)
    return (
        len(rows),
        sum(row.source.stat().st_size for row in rows),
        Counter(row.category for row in rows),
        Counter(row.package for row in rows),
    )


def write_outputs(
    planned: list[PlannedFile],
    catalog: dict[str, dict[str, object]],
    source_count: int,
    source_bytes: int,
    removed_directories: int,
) -> None:
    generated_at = datetime.now().astimezone().isoformat(timespec="seconds")
    category_counts = Counter(row.category for row in planned)
    package_counts = Counter(row.package for row in planned)
    records = []
    for row in planned:
        destination = FINAL_ROOT / row.destination
        records.append(
            {
                "source": relative(row.source),
                "destination": relative(destination),
                "package": row.package,
                "category": row.category,
                "character_id": row.character_id,
                "symbol_name": row.symbol_name,
                "evidence": row.evidence,
                "bytes": destination.stat().st_size,
            }
        )
    manifest = {
        "generated_at": generated_at,
        "original_source_root": relative(SOURCE_ROOT),
        "classified_root": relative(FINAL_ROOT),
        "storage": "single canonical moved tree; no source/classified copies or hard links",
        "policy": "Every extracted file is moved exactly once. Intentional repeated animation frames are preserved.",
        "source_removed": not SOURCE_ROOT.exists(),
        "source_file_count": source_count,
        "classified_source_file_count": len(records),
        "source_bytes": source_bytes,
        "removed_empty_directories": removed_directories,
        "counts_by_category": dict(sorted(category_counts.items())),
        "counts_by_package": dict(sorted(package_counts.items())),
        "monsters": sorted(catalog.values(), key=lambda item: int(str(item["class"])[7:])),
        "files": records,
    }
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")

    lines = [
        "# 《造梦西游2》素材初步整理",
        "",
        f"生成时间：{generated_at}",
        "",
        f"已将完整拆包中的 **{source_count:,} 个文件**（{source_bytes / 1024 / 1024:.2f} MB）迁移到单一分类树 `{relative(FINAL_ROOT)}`。",
        "原完整拆包目录已清空并删除；本次没有创建分类副本或硬链接，因此不存在“源树 + 分类树”双份路径。",
        "动画中为表达停顿或节奏而重复的帧保留不动，它们属于原始时间轴信息，不视为整理产生的重复。",
        "",
        "## 初步分类",
        "",
        "| 分类 | 文件数 |",
        "| --- | ---: |",
    ]
    lines.extend(f"| `{category}` | {count:,} |" for category, count in sorted(category_counts.items()))
    lines.extend(
        [
            "",
            "## 当前边界",
            "",
            "- 已依据资源包、`symbolClass`、导出类名和怪物脚本完成第一轮人物、怪物、UI、场景、公共元件、音频分类。",
            "- 无法仅凭导出名唯一反查的底层 Timeline/Shape 保留在对应人物、关卡或公共包的“待识别元件”中，没有强行猜测。",
            "- ActionScript、符号表、帧信息、字体与文本等非视觉文件统一保存在同一分类树的 `结构证据` / `UI/字体` 下，便于后续反查；它们不再另存一套源目录。",
            "",
            f"逐文件迁移依据见 `{relative(MANIFEST_PATH)}`。",
            "",
        ]
    )
    report = "\n".join(lines)
    REPORT_PATH.write_text(report, encoding="utf-8", newline="\n")
    (FINAL_ROOT / "README.md").write_text(report, encoding="utf-8", newline="\n")


def apply_plan(planned: list[PlannedFile], catalog: dict[str, dict[str, object]]) -> dict[str, object]:
    if FINAL_ROOT.exists():
        raise RuntimeError(f"Final output already exists: {FINAL_ROOT}")
    if TEMP_ROOT.exists():
        if any(TEMP_ROOT.iterdir()):
            raise RuntimeError(f"Temporary output is not empty: {TEMP_ROOT}")
        TEMP_ROOT.rmdir()

    source_count, source_bytes, category_counts, _package_counts = accounting(planned)
    TEMP_ROOT.mkdir(parents=True)
    moved = 0
    for row in planned:
        destination = TEMP_ROOT / row.destination
        destination.parent.mkdir(parents=True, exist_ok=True)
        os.replace(row.source, destination)
        moved += 1

    temp_files = [path for path in TEMP_ROOT.rglob("*") if path.is_file()]
    temp_bytes = sum(path.stat().st_size for path in temp_files)
    if len(temp_files) != source_count or temp_bytes != source_bytes:
        raise RuntimeError(
            f"Post-move accounting mismatch: files {len(temp_files)}/{source_count}, bytes {temp_bytes}/{source_bytes}"
        )

    removed_directories = remove_empty_directories(SOURCE_ROOT)
    if SOURCE_ROOT.exists():
        leftovers = [path for path in SOURCE_ROOT.rglob("*") if path.is_file()]
        raise RuntimeError(f"Source root still contains {len(leftovers)} files")
    os.replace(TEMP_ROOT, FINAL_ROOT)
    final_files = [path for path in FINAL_ROOT.rglob("*") if path.is_file()]
    final_bytes = sum(path.stat().st_size for path in final_files)
    if len(final_files) != source_count or final_bytes != source_bytes:
        raise RuntimeError(
            f"Final accounting mismatch: files {len(final_files)}/{source_count}, bytes {final_bytes}/{source_bytes}"
        )
    write_outputs(planned, catalog, source_count, source_bytes, removed_directories)
    return {
        "moved_files": moved,
        "bytes": source_bytes,
        "categories": len(category_counts),
        "source_removed": not SOURCE_ROOT.exists(),
        "classified_root": relative(FINAL_ROOT),
        "manifest": relative(MANIFEST_PATH),
        "report": relative(REPORT_PATH),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Disabled legacy move mode")
    parser.add_argument(
        "--restore-full",
        action="store_true",
        help="Disabled legacy restore mode",
    )
    return parser.parse_args()


def restore_full() -> dict[str, object]:
    raise SystemExit(
        "Legacy restore mode is disabled: classified/zmxiyou2 is the canonical library. "
        "Re-extract a temporary full tree from sources/raw or sources/decoded when needed."
    )

    # Historical implementation retained below for audit reference.
    if not MANIFEST_PATH.exists():
        raise SystemExit(f"Missing move manifest: {MANIFEST_PATH}")
    if not FINAL_ROOT.exists():
        raise SystemExit(f"Missing historical classified tree: {FINAL_ROOT}")
    if SOURCE_ROOT.exists() and any(SOURCE_ROOT.rglob("*")):
        raise SystemExit(f"Provenance root is not empty: {SOURCE_ROOT}")

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    records = list(manifest.get("files", []))
    source_root_resolved = SOURCE_ROOT.resolve()
    final_root_resolved = FINAL_ROOT.resolve()
    planned: list[tuple[Path, Path, int]] = []
    original_keys: set[str] = set()
    classified_keys: set[str] = set()
    for record in records:
        original = (ROOT / str(record["source"])).resolve()
        classified = (ROOT / str(record["destination"])).resolve()
        if not original.is_relative_to(source_root_resolved):
            raise SystemExit(f"Unsafe restore target outside provenance root: {original}")
        if not classified.is_relative_to(final_root_resolved):
            raise SystemExit(f"Unsafe restore source outside classified root: {classified}")
        original_key = str(original).casefold()
        classified_key = str(classified).casefold()
        if original_key in original_keys or classified_key in classified_keys:
            raise SystemExit(f"Duplicate restore path in manifest: {original} <- {classified}")
        if not classified.is_file():
            raise SystemExit(f"Missing classified source during restore: {classified}")
        size = classified.stat().st_size
        if size != int(record["bytes"]):
            raise SystemExit(f"Size mismatch during restore: {classified}")
        original_keys.add(original_key)
        classified_keys.add(classified_key)
        planned.append((classified, original, size))

    expected_count = int(manifest["source_file_count"])
    expected_bytes = int(manifest["source_bytes"])
    if len(planned) != expected_count or sum(row[2] for row in planned) != expected_bytes:
        raise SystemExit("Historical manifest accounting does not match the restore plan")

    SOURCE_ROOT.mkdir(parents=True, exist_ok=True)
    for classified, original, _size in planned:
        original.parent.mkdir(parents=True, exist_ok=True)
        os.replace(classified, original)

    readme = FINAL_ROOT / "README.md"
    if readme.exists():
        readme.unlink()
    removed_directories = remove_empty_directories(FINAL_ROOT)
    restored_files = [path for path in SOURCE_ROOT.rglob("*") if path.is_file()]
    restored_bytes = sum(path.stat().st_size for path in restored_files)
    if len(restored_files) != expected_count or restored_bytes != expected_bytes:
        raise RuntimeError(
            f"Restore accounting mismatch: files {len(restored_files)}/{expected_count}, "
            f"bytes {restored_bytes}/{expected_bytes}"
        )
    if FINAL_ROOT.exists():
        leftovers = [path for path in FINAL_ROOT.rglob("*") if path.is_file()]
        raise RuntimeError(f"Historical classified tree still contains {len(leftovers)} files")
    return {
        "restored_files": len(restored_files),
        "restored_bytes": restored_bytes,
        "provenance_root": relative(SOURCE_ROOT),
        "historical_classified_removed": not FINAL_ROOT.exists(),
        "empty_directories_removed": removed_directories,
    }


def main() -> None:
    args = parse_args()
    if args.restore_full:
        print(json.dumps(restore_full(), ensure_ascii=False, indent=2))
        return
    if args.apply:
        raise SystemExit(
            "Legacy move mode is disabled by sources/ASSET_ORGANIZATION_GUIDE.md; "
            "build a non-destructive classified tree instead."
        )
    if not SOURCE_ROOT.exists():
        raise SystemExit(f"Missing source root: {SOURCE_ROOT}")
    if FINAL_ROOT.exists():
        raise SystemExit(f"Classified root already exists: {FINAL_ROOT}")
    planned, unowned, catalog = build_plan()
    if unowned:
        preview = "\n".join(relative(path) for path in unowned[:20])
        raise SystemExit(f"{len(unowned)} files have no owning package:\n{preview}")
    source_files = [path for path in SOURCE_ROOT.rglob("*") if path.is_file()]
    if len(planned) != len(source_files):
        raise SystemExit(f"Planning mismatch: planned={len(planned)}, source={len(source_files)}")
    source_count, source_bytes, category_counts, package_counts = accounting(planned)
    summary = {
        "mode": "apply" if args.apply else "dry-run",
        "planned_files": source_count,
        "planned_bytes": source_bytes,
        "unique_destinations": len({row.destination.as_posix().casefold() for row in planned}),
        "maximum_destination_characters": max(len(str(FINAL_ROOT / row.destination)) for row in planned),
        "packages": len(package_counts),
        "monsters": len(catalog),
        "categories": dict(sorted(category_counts.items())),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
