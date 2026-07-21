#!/usr/bin/env python3
"""Build the guide-compliant ZMX2 standard material library.

The complete FFDec export remains untouched.  The classified tree contains
hard links to canonical visual/audio/font assets, excluding transparent PNGs,
verified numeric-progress intermediates, and byte-identical copies from other
symbol contexts.  Repeated frames inside one animation timeline are retained.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import organize_zmxiyou2_assets as initial


ROOT = Path(__file__).resolve().parents[1]
FULL_ROOT = ROOT / "assets" / "extracted" / "full" / "zmxiyou2"
FINAL_ROOT = ROOT / "assets" / "extracted" / "classified" / "zmxiyou2"
TEMP_ROOT = ROOT / "assets" / "extracted" / "classified" / "zmxiyou2_building"
MANIFEST_PATH = ROOT / "sources" / "manifests" / "zmxiyou2_standard_cleanup.json"
REPORT_PATH = ROOT / "sources" / "ZMXIYOU2_STANDARD_LIBRARY.md"

MATERIAL_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".svg",
    ".mp3", ".wav", ".ogg",
    ".ttf", ".otf", ".woff", ".woff2",
}


@dataclass(frozen=True)
class Candidate:
    source: Path
    destination: Path
    package: str
    category: str
    character_id: int | None
    symbol_name: str
    evidence: str
    progress_key: str = ""


PROGRESS_RULES: dict[tuple[str, int], dict[str, Any]] = {
    ("shared__OtherMat_v10", 294): {
        "key": "energy", "keep": 100, "destination": Path("UI/HUD/energy_slider.png"),
        "frames": 100, "instance": "wsmc",
        "formula": 'wsmc.gotoAndStop(getProperty(this, "wsValue"))',
        "script": "assets/extracted/full/zmxiyou2/shared/OtherMat_v10/scripts/export/RoleInfo.as",
        "replacement": "Godot TextureProgressBar or clipped TextureRect; step = 1",
    },
    ("shared__OtherMat_v10", 306): {
        "key": "hp", "keep": 1, "destination": Path("UI/HUD/hp_slider.png"),
        "frames": 101, "instance": "hpline",
        "formula": "hpline.gotoAndStop(round(100 * (1 - currentHP / maximumHP)) + 1)",
        "script": "assets/extracted/full/zmxiyou2/shared/OtherMat_v10/scripts/export/RoleInfo.as",
        "replacement": "Godot TextureProgressBar or clipped TextureRect; step = 1",
    },
    ("shared__OtherMat_v10", 309): {
        "key": "mp", "keep": 1, "destination": Path("UI/HUD/mp_slider.png"),
        "frames": 101, "instance": "mpline",
        "formula": "mpline.gotoAndStop(round(100 * (1 - currentMP / maximumMP)) + 1)",
        "script": "assets/extracted/full/zmxiyou2/shared/OtherMat_v10/scripts/export/RoleInfo.as",
        "replacement": "Godot TextureProgressBar or clipped TextureRect; step = 1",
    },
    ("shared__OtherMat_v10", 312): {
        "key": "exp", "keep": 1, "destination": Path("UI/HUD/exp_slider.png"),
        "frames": 101, "instance": "expline",
        "formula": "expline.gotoAndStop(round(100 * (1 - currentEXP / requiredEXP)) + 1)",
        "script": "assets/extracted/full/zmxiyou2/shared/OtherMat_v10/scripts/export/RoleInfo.as",
        "replacement": "Godot TextureProgressBar or clipped TextureRect; step = 1",
    },
    ("shared__backpack_v5", 10): {
        "key": "backpack_exp", "keep": 30, "destination": Path("UI/背包/backpack_exp_slider.png"),
        "frames": 30, "instance": "mc_exp",
        "formula": "mc_exp.gotoAndStop(round(30 * currentEXP / requiredEXP))",
        "script": "assets/extracted/full/zmxiyou2/shared/backpack_v5/scripts/export/pack/BackPack.as",
        "replacement": "Godot TextureProgressBar or clipped TextureRect; step = 1/30",
    },
    ("shared__backpack_v5", 477): {
        "key": "magic_exp", "keep": 50, "destination": Path("UI/背包/magic_exp_slider.png"),
        "frames": 50, "instance": "lhmc",
        "formula": "lhmc.gotoAndStop(int(currentValue / (nextGradeValue + 1) * 50))",
        "script": "assets/extracted/full/zmxiyou2/shared/backpack_v5/scripts/export/strength/SutraInterface.as",
        "replacement": "Godot TextureProgressBar or clipped TextureRect; step = 1/50",
    },
}


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def remap_category(category: str) -> str:
    if category == "UI/4399外壳":
        return "公共元件/4399外壳"
    if category.startswith("音频/"):
        return "公共元件/音频/" + category.removeprefix("音频/")
    return category


def progress_rule(row: initial.PlannedFile) -> tuple[dict[str, Any] | None, int | None]:
    if row.source.suffix.lower() != ".png" or row.character_id is None:
        return None, None
    rule = PROGRESS_RULES.get((row.package, int(row.character_id)))
    if rule is None:
        return None, None
    match = re.fullmatch(r"(\d+)\.png", row.source.name, flags=re.IGNORECASE)
    return (rule, int(match.group(1))) if match else (None, None)


def is_transparent(path: Path) -> bool:
    if path.suffix.lower() != ".png":
        return False
    try:
        with Image.open(path) as image:
            return image.convert("RGBA").getchannel("A").getbbox() is None
    except Exception:
        return False


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def animation_context(candidate: Candidate) -> str:
    parts = candidate.source.parts
    if candidate.source.suffix.lower() == ".png" and re.fullmatch(r"\d+", candidate.source.stem):
        if "sprites" in parts or "buttons" in parts:
            return str(candidate.source.parent).casefold()
    return str(candidate.source).casefold()


def canonical_score(candidate: Candidate) -> tuple[int, int, int, str]:
    return (
        0 if candidate.progress_key else 1,
        1 if "待识别" in candidate.category or "待确认" in candidate.category else 0,
        len(candidate.category),
        relative(candidate.source).casefold(),
    )


def build_candidates() -> tuple[
    list[Candidate], list[dict[str, Any]], list[dict[str, Any]], int, int, dict[str, dict[str, object]]
]:
    planned, unowned, monsters = initial.build_plan()
    if unowned:
        raise RuntimeError(f"Unowned files in complete extraction: {len(unowned)}")
    full_count = len(planned)
    nonmaterial_count = 0
    progress_removed: list[dict[str, Any]] = []
    preliminary: list[Candidate] = []

    for row in planned:
        if row.source.suffix.lower() not in MATERIAL_EXTENSIONS:
            nonmaterial_count += 1
            continue
        rule, frame = progress_rule(row)
        if rule is not None and frame is not None:
            if frame != int(rule["keep"]):
                progress_removed.append(
                    {
                        "source": relative(row.source),
                        "package": row.package,
                        "symbol_id": row.character_id,
                        "frame": frame,
                        "reason": "numeric_progress_intermediate",
                        "canonical_source": "",
                        "canonical_destination": rule["destination"].as_posix(),
                    }
                )
                continue
            preliminary.append(
                Candidate(
                    row.source, Path(rule["destination"]), row.package,
                    str(Path(rule["destination"]).parent).replace("\\", "/"),
                    row.character_id, row.symbol_name,
                    f"数值驱动时间轴 {rule['instance']} 的完整填充帧", str(rule["key"]),
                )
            )
            continue
        category = remap_category(row.category)
        old_prefix = Path(row.category)
        tail = row.destination.relative_to(old_prefix)
        preliminary.append(
            Candidate(
                row.source, Path(category) / tail, row.package, category,
                row.character_id, row.symbol_name, row.evidence,
            )
        )

    png_candidates = [row for row in preliminary if row.source.suffix.lower() == ".png"]
    with ThreadPoolExecutor(max_workers=16) as executor:
        blank_flags = list(executor.map(is_transparent, (row.source for row in png_candidates), chunksize=32))
    blank_sources = {str(row.source).casefold() for row, blank in zip(png_candidates, blank_flags) if blank}
    blank_removed: list[dict[str, Any]] = []
    candidates: list[Candidate] = []
    for row in preliminary:
        if str(row.source).casefold() in blank_sources:
            blank_removed.append(
                {
                    "source": relative(row.source),
                    "planned_destination": (FINAL_ROOT / row.destination).relative_to(ROOT).as_posix(),
                    "package": row.package,
                    "symbol_id": row.character_id,
                    "category": row.category,
                    "bytes": row.source.stat().st_size,
                    "reason": "fully_transparent_png",
                }
            )
        else:
            candidates.append(row)

    return candidates, progress_removed, blank_removed, full_count, nonmaterial_count, monsters


def deduplicate(candidates: list[Candidate]) -> tuple[
    list[Candidate], list[dict[str, Any]], dict[str, str], int
]:
    with ThreadPoolExecutor(max_workers=16) as executor:
        hashes = list(executor.map(sha256, (row.source for row in candidates), chunksize=16))
    hash_by_source = {str(row.source).casefold(): digest for row, digest in zip(candidates, hashes)}
    groups: dict[str, list[Candidate]] = defaultdict(list)
    for row, digest in zip(candidates, hashes):
        groups[digest].append(row)

    retained: list[Candidate] = []
    aliases: list[dict[str, Any]] = []
    repeated_frames_preserved = 0
    for digest, rows in groups.items():
        contexts: dict[str, list[Candidate]] = defaultdict(list)
        for row in rows:
            contexts[animation_context(row)].append(row)
        canonical_context = min(
            contexts,
            key=lambda key: min(canonical_score(row) for row in contexts[key]),
        )
        canonical_rows = sorted(contexts[canonical_context], key=lambda row: relative(row.source).casefold())
        retained.extend(canonical_rows)
        if len(canonical_rows) > 1:
            repeated_frames_preserved += len(canonical_rows) - 1
        canonical = min(canonical_rows, key=canonical_score)
        for context, context_rows in contexts.items():
            if context == canonical_context:
                continue
            for row in context_rows:
                aliases.append(
                    {
                        "removed_source": relative(row.source),
                        "planned_destination": (FINAL_ROOT / row.destination).relative_to(ROOT).as_posix(),
                        "canonical_source": relative(canonical.source),
                        "canonical_destination": (FINAL_ROOT / canonical.destination).relative_to(ROOT).as_posix(),
                        "sha256": digest,
                        "bytes": row.source.stat().st_size,
                        "reason": "byte_identical_other_symbol_context",
                    }
                )
    retained.sort(key=lambda row: row.destination.as_posix().casefold())
    return retained, aliases, hash_by_source, repeated_frames_preserved


def validate_destinations(rows: list[Candidate]) -> None:
    seen: dict[str, Candidate] = {}
    for row in rows:
        key = row.destination.as_posix().casefold()
        if key in seen:
            raise RuntimeError(f"Destination collision: {seen[key].source} and {row.source} -> {row.destination}")
        seen[key] = row


def build(apply: bool) -> dict[str, Any]:
    if not FULL_ROOT.exists():
        raise RuntimeError(f"Missing complete extraction: {FULL_ROOT}")
    if FINAL_ROOT.exists():
        raise RuntimeError(f"Classified root already exists: {FINAL_ROOT}")
    if TEMP_ROOT.exists():
        raise RuntimeError(f"Temporary classified root already exists: {TEMP_ROOT}")

    candidates, progress_removed, blank_removed, full_count, nonmaterial_count, monsters = build_candidates()
    retained, aliases, hash_by_source, repeated_frames_preserved = deduplicate(candidates)
    validate_destinations(retained)
    generated_at = datetime.now().astimezone().isoformat(timespec="seconds")
    category_counts = Counter(row.category for row in retained)

    result = {
        "mode": "apply" if apply else "audit",
        "complete_extraction_files": full_count,
        "nonmaterial_files_excluded": nonmaterial_count,
        "material_candidates": full_count - nonmaterial_count,
        "transparent_pngs_removed": len(blank_removed),
        "numeric_progress_frames_removed": len(progress_removed),
        "byte_identical_context_copies_removed": len(aliases),
        "repeated_animation_frames_preserved": repeated_frames_preserved,
        "retained_standard_files": len(retained),
        "categories": len(category_counts),
    }
    if not apply:
        return result

    TEMP_ROOT.mkdir(parents=True)
    for row in retained:
        destination = TEMP_ROOT / row.destination
        destination.parent.mkdir(parents=True, exist_ok=True)
        os.link(row.source, destination)
    os.replace(TEMP_ROOT, FINAL_ROOT)

    retained_records = [
        {
            "source": relative(row.source),
            "destination": relative(FINAL_ROOT / row.destination),
            "package": row.package,
            "category": row.category,
            "character_id": row.character_id,
            "symbol_name": row.symbol_name,
            "evidence": row.evidence,
            "sha256": hash_by_source[str(row.source).casefold()],
            "bytes": row.source.stat().st_size,
        }
        for row in retained
    ]
    progress_audit = []
    for (package, symbol_id), rule in PROGRESS_RULES.items():
        kept_source = next(
            row.source for row in retained
            if row.package == package and row.character_id == symbol_id and row.progress_key == rule["key"]
        )
        progress_audit.append(
            {
                "key": rule["key"],
                "package": package,
                "symbol_id": symbol_id,
                "instance": rule["instance"],
                "source_frames": rule["frames"],
                "formula": rule["formula"],
                "script": rule["script"],
                "kept_frame": rule["keep"],
                "kept_source": relative(kept_source),
                "kept_destination": relative(FINAL_ROOT / rule["destination"]),
                "removed_frames": int(rule["frames"]) - 1,
                "godot_replacement": rule["replacement"],
            }
        )
    manifest = {
        "generated_at": generated_at,
        "game": "zmxiyou2",
        "guide": "sources/ASSET_ORGANIZATION_GUIDE.md",
        "source_swf": "sources/raw/zmxiyou2.swf",
        "complete_extraction_root": relative(FULL_ROOT),
        "classified_root": relative(FINAL_ROOT),
        "storage": "NTFS hard links to the immutable complete extraction; no duplicated file data",
        "policy": (
            "Keep provenance intact. Exclude nonmaterial structure files, fully transparent PNGs, "
            "verified numeric-progress intermediates, and byte-identical copies from other symbol contexts. "
            "Preserve repeated frames within one animation timeline."
        ),
        "counts": result,
        "counts_by_category": dict(sorted(category_counts.items())),
        "numeric_progress_timelines": progress_audit,
        "numeric_progress_removed_files": progress_removed,
        "transparent_pngs": blank_removed,
        "byte_identical_aliases": aliases,
        "retained_files": retained_records,
        "monsters": sorted(monsters.values(), key=lambda item: int(str(item["class"])[7:])),
        "pending": [
            "PNG/SVG/JPG visual equivalence has not yet been audited for ZMX2; no cross-format file was removed in this pass.",
            "Repeated identical frames inside one timeline remain until FrameLabel and playback timing are verified.",
            "Anonymous Timeline/Shape ownership still needs SWF reference-graph refinement.",
        ],
    }
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")

    lines = [
        "# 《造梦西游2》标准素材库",
        "",
        f"生成时间：{generated_at}",
        "",
        f"完整溯源库 `{relative(FULL_ROOT)}` 保留 {full_count:,} 个文件且未做精简删除。",
        f"标准分类库保留 {len(retained):,} 项素材，使用 NTFS 硬链接，不重复占用文件数据。",
        "",
        "## 本轮精简",
        "",
        f"- 排除 {nonmaterial_count:,} 个只应存在于溯源层的源码、符号表和结构文件。",
        f"- 排除 {len(blank_removed):,} 张逐图验证为全透明的 PNG。",
        f"- 6 组数值驱动时间轴仅保留完整填充图，排除 {len(progress_removed):,} 张中间帧。",
        f"- 合并 {len(aliases):,} 个来自其他符号上下文的字节完全相同副本。",
        f"- 保留 {repeated_frames_preserved:,} 个同一动画时间轴内的重复帧，等待播放节奏核验。",
        "",
        "## 数值条标准项",
        "",
        "| 功能 | 原帧数 | 保留帧 | 标准路径 | Godot 替代 |",
        "| --- | ---: | ---: | --- | --- |",
    ]
    for row in progress_audit:
        lines.append(
            f"| `{row['key']}` | {row['source_frames']} | {row['kept_frame']} | "
            f"`{row['kept_destination']}` | {row['godot_replacement']} |"
        )
    lines.extend(
        [
            "",
            "## 尚未删除",
            "",
            "- 尚未完成视觉等价比对的 PNG/SVG/JPG 跨格式副本。",
            "- 同一时间轴内可能承担停顿节奏的重复动画帧。",
            "- 尚未通过 SWF 引用图唯一归属的匿名 Timeline/Shape。",
            "",
            f"逐文件保留、删除和别名证据见 `{relative(MANIFEST_PATH)}`。",
            "",
        ]
    )
    report = "\n".join(lines)
    REPORT_PATH.write_text(report, encoding="utf-8", newline="\n")
    (FINAL_ROOT / "README.md").write_text(report, encoding="utf-8", newline="\n")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Create the classified hard-link tree and reports")
    args = parser.parse_args()
    print(json.dumps(build(args.apply), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
