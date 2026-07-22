#!/usr/bin/env python3
"""Finalize ZMX2 as a move-style canonical classified library.

Known assets keep their semantic destinations.  Uncertain assets move below
the top-level ``杂项`` directory.  After every retained item is verified as a
hard link to its complete-extraction source, the temporary ``full/zmxiyou2``
tree is removed.  Raw and decoded SWFs remain untouched.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
FULL_ROOT = ROOT / "assets" / "extracted" / "full" / "zmxiyou2"
CLASSIFIED_ROOT = ROOT / "assets" / "extracted" / "classified" / "zmxiyou2"
STANDARD_MANIFEST = ROOT / "sources" / "manifests" / "zmxiyou2_standard_cleanup.json"
MIGRATION_MANIFEST = ROOT / "sources" / "manifests" / "zmxiyou2_canonical_migration.json"
REPORT_PATH = ROOT / "sources" / "ZMXIYOU2_CANONICAL_LIBRARY.md"
GUIDE_PATH = ROOT / "sources" / "ASSET_ORGANIZATION_GUIDE.md"

UNKNOWN_MARKERS = ("待识别", "待确认")


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def ensure_within(path: Path, root: Path, label: str) -> Path:
    resolved = path.resolve()
    root_resolved = root.resolve()
    if not resolved.is_relative_to(root_resolved):
        raise RuntimeError(f"Unsafe {label} outside {root_resolved}: {resolved}")
    return resolved


def directory_stats(path: Path, *, exclude_readme: bool = False) -> tuple[int, int]:
    count = 0
    size = 0
    if not path.exists():
        return count, size
    for item in path.rglob("*"):
        if not item.is_file():
            continue
        if exclude_readme and item == path / "README.md":
            continue
        count += 1
        size += item.stat().st_size
    return count, size


def is_unknown(category: str) -> bool:
    return any(marker in category for marker in UNKNOWN_MARKERS)


def final_destination(row: dict[str, Any]) -> tuple[Path, str, bool]:
    current = ROOT / str(row["destination"])
    current_relative = current.relative_to(CLASSIFIED_ROOT)
    category = str(row["category"])
    if not is_unknown(category):
        return current, category, False

    category_path = Path(category)
    category_parts = category_path.parts
    if current_relative.parts[: len(category_parts)] != category_parts:
        raise RuntimeError(
            f"Destination/category mismatch: {current_relative.as_posix()} vs {category}"
        )
    tail = Path(*current_relative.parts[len(category_parts) :])
    destination = CLASSIFIED_ROOT / "杂项" / category_path / tail
    return destination, f"杂项/{category}", True


def build_plan() -> dict[str, Any]:
    guide = GUIDE_PATH.read_text(encoding="utf-8")
    if "移动式更新" not in guide:
        raise RuntimeError("The organization guide has not enabled move-style updates")
    standard = json.loads(STANDARD_MANIFEST.read_text(encoding="utf-8"))
    records: list[dict[str, Any]] = []
    destinations: set[str] = set()
    unknown_count = 0
    unknown_bytes = 0
    category_counts: Counter[str] = Counter()

    for source_row in standard["retained_files"]:
        current = ROOT / str(source_row["destination"])
        destination, category, unknown = final_destination(source_row)
        ensure_within(current, CLASSIFIED_ROOT, "classified source")
        ensure_within(destination, CLASSIFIED_ROOT, "classified destination")
        key = str(destination).casefold()
        if key in destinations:
            raise RuntimeError(f"Duplicate final destination: {destination}")
        destinations.add(key)
        row = dict(source_row)
        row["previous_destination"] = relative(current)
        row["destination"] = relative(destination)
        row["previous_category"] = str(source_row["category"])
        row["category"] = category
        row["moved_to_misc"] = unknown
        records.append(row)
        category_counts[category] += 1
        if unknown:
            unknown_count += 1
            unknown_bytes += int(row["bytes"])

    full_count, full_bytes = directory_stats(FULL_ROOT)
    classified_count, classified_bytes = directory_stats(CLASSIFIED_ROOT, exclude_readme=True)
    generated_at = datetime.now().astimezone().isoformat(timespec="seconds")
    return {
        "status": "planned",
        "generated_at": generated_at,
        "game": "zmxiyou2",
        "guide": relative(GUIDE_PATH),
        "raw_source": "sources/raw/zmxiyou2.swf",
        "decoded_source_root": "sources/decoded/zmxiyou2",
        "temporary_full_root": relative(FULL_ROOT),
        "canonical_classified_root": relative(CLASSIFIED_ROOT),
        "policy": (
            "Move-style canonical library: known assets keep semantic paths; uncertain assets move to 杂项; "
            "temporary full extraction is removed after manifest and hard-link verification."
        ),
        "before": {
            "full_files": full_count,
            "full_bytes": full_bytes,
            "classified_files": classified_count,
            "classified_bytes": classified_bytes,
        },
        "planned": {
            "retained_files": len(records),
            "known_files": len(records) - unknown_count,
            "misc_files": unknown_count,
            "misc_bytes": unknown_bytes,
            "full_files_to_remove": full_count,
        },
        "standard_cleanup_manifest": relative(STANDARD_MANIFEST),
        "standard_cleanup_counts": standard["counts"],
        "counts_by_final_category": dict(sorted(category_counts.items())),
        "retained_files": records,
        "full_removal": {
            "authorized_by": "user-requested move-style update",
            "precondition": "all retained classified files verified against full sources with os.path.samefile",
            "removed": False,
        },
        "pending": list(standard.get("pending", [])),
    }


def write_plan() -> dict[str, Any]:
    if not FULL_ROOT.exists():
        raise RuntimeError(f"Missing temporary full extraction: {FULL_ROOT}")
    if not CLASSIFIED_ROOT.exists():
        raise RuntimeError(f"Missing classified library: {CLASSIFIED_ROOT}")
    plan = build_plan()
    MIGRATION_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MIGRATION_MANIFEST.write_text(
        json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n"
    )
    return {
        "status": plan["status"],
        **plan["before"],
        **plan["planned"],
        "manifest": relative(MIGRATION_MANIFEST),
    }


def remove_empty_directories(root: Path) -> int:
    removed = 0
    for path in sorted(
        (item for item in root.rglob("*") if item.is_dir()),
        key=lambda item: len(item.parts),
        reverse=True,
    ):
        if not any(path.iterdir()):
            path.rmdir()
            removed += 1
    return removed


def apply_plan() -> dict[str, Any]:
    if not MIGRATION_MANIFEST.exists():
        raise RuntimeError("Missing planned migration manifest; run --plan first")
    plan = json.loads(MIGRATION_MANIFEST.read_text(encoding="utf-8"))
    if plan.get("status") != "planned":
        raise RuntimeError(f"Migration manifest is not planned: {plan.get('status')}")
    records = list(plan["retained_files"])
    if not FULL_ROOT.exists() or not CLASSIFIED_ROOT.exists():
        raise RuntimeError("Expected full and classified roots before migration")

    before_count, before_bytes = directory_stats(FULL_ROOT)
    if before_count != int(plan["before"]["full_files"]) or before_bytes != int(plan["before"]["full_bytes"]):
        raise RuntimeError("Full extraction changed after the migration plan was written")

    verified_links = 0
    moves: list[tuple[Path, Path]] = []
    for row in records:
        source = ROOT / str(row["source"])
        current = ROOT / str(row["previous_destination"])
        destination = ROOT / str(row["destination"])
        ensure_within(source, FULL_ROOT, "full source")
        ensure_within(current, CLASSIFIED_ROOT, "classified source")
        ensure_within(destination, CLASSIFIED_ROOT, "classified destination")
        if not source.is_file() or not current.is_file():
            raise RuntimeError(f"Missing pre-migration file: {source} / {current}")
        if source.stat().st_size != int(row["bytes"]) or current.stat().st_size != int(row["bytes"]):
            raise RuntimeError(f"Size mismatch before migration: {current}")
        if not os.path.samefile(source, current):
            raise RuntimeError(f"Classified file is not the verified source hard link: {current}")
        verified_links += 1
        if current != destination:
            if destination.exists():
                raise RuntimeError(f"Final destination already exists: {destination}")
            moves.append((current, destination))

    for current, destination in moves:
        destination.parent.mkdir(parents=True, exist_ok=True)
        os.replace(current, destination)
    empty_directories_removed = remove_empty_directories(CLASSIFIED_ROOT)

    final_destinations = [ROOT / str(row["destination"]) for row in records]
    if len({str(path).casefold() for path in final_destinations}) != len(records):
        raise RuntimeError("Final destination list is not unique")
    missing = [path for path in final_destinations if not path.is_file()]
    if missing:
        raise RuntimeError(f"Missing final classified files before full cleanup: {len(missing)}")
    for row, destination in zip(records, final_destinations):
        source = ROOT / str(row["source"])
        if not os.path.samefile(source, destination):
            raise RuntimeError(f"Hard-link verification failed after misc move: {destination}")

    full_resolved = FULL_ROOT.resolve()
    expected_parent = (ROOT / "assets" / "extracted" / "full").resolve()
    if full_resolved.parent != expected_parent or full_resolved.name != "zmxiyou2":
        raise RuntimeError(f"Unsafe full cleanup target: {full_resolved}")
    shutil.rmtree(full_resolved)
    if FULL_ROOT.exists():
        raise RuntimeError("Temporary full extraction still exists after cleanup")

    classified_count, classified_bytes = directory_stats(CLASSIFIED_ROOT, exclude_readme=True)
    if classified_count != len(records):
        raise RuntimeError(f"Classified count mismatch after cleanup: {classified_count}/{len(records)}")

    completed_at = datetime.now().astimezone().isoformat(timespec="seconds")
    plan["status"] = "complete"
    plan["completed_at"] = completed_at
    plan["full_removal"]["removed"] = True
    plan["full_removal"]["removed_files"] = before_count
    plan["full_removal"]["removed_logical_bytes"] = before_bytes
    plan["result"] = {
        "verified_hard_links_before_cleanup": verified_links,
        "files_moved_to_misc": len(moves),
        "empty_directories_removed": empty_directories_removed,
        "canonical_files": classified_count,
        "canonical_bytes": classified_bytes,
        "full_removed": True,
    }
    MIGRATION_MANIFEST.write_text(
        json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n"
    )

    lines = [
        "# 《造梦西游2》唯一规范素材库",
        "",
        f"完成时间：{completed_at}",
        "",
        f"`{relative(CLASSIFIED_ROOT)}` 是造2唯一规范元件库，共保留 {classified_count:,} 项。",
        f"其中 {plan['planned']['known_files']:,} 项位于正式语义分类，{plan['planned']['misc_files']:,} 项暂存于顶层 `杂项`。",
        f"临时完整拆包 `{relative(FULL_ROOT)}` 已在 {verified_links:,} 对硬链接逐项核验后删除。",
        "原始及解码 SWF 继续保留，需要复核时可重新提取临时 `full`。",
        "",
        "## 已执行的精简",
        "",
        f"- 全透明 PNG：{plan['standard_cleanup_counts']['transparent_pngs_removed']:,} 项未进入规范库。",
        f"- 数值进度中间帧：{plan['standard_cleanup_counts']['numeric_progress_frames_removed']:,} 项未进入规范库。",
        f"- 跨符号字节相同副本：{plan['standard_cleanup_counts']['byte_identical_context_copies_removed']:,} 项未进入规范库。",
        f"- 非素材结构导出物：{plan['standard_cleanup_counts']['nonmaterial_files_excluded']:,} 项未进入规范库。",
        "",
        "## 尚待继续整理",
        "",
        "- `杂项` 中的素材在引用关系确认后再移入正式分类。",
        "- PNG/SVG/JPG 的视觉等价去重仍需逐项验证。",
        "- 同一时间轴内的相同帧继续保留，直到播放节奏核验完成。",
        "",
        f"逐文件原路径、旧分类和最终路径见 `{relative(MIGRATION_MANIFEST)}`。",
        "",
    ]
    report = "\n".join(lines)
    REPORT_PATH.write_text(report, encoding="utf-8", newline="\n")
    (CLASSIFIED_ROOT / "README.md").write_text(report, encoding="utf-8", newline="\n")
    return {
        "status": "complete",
        **plan["result"],
        "manifest": relative(MIGRATION_MANIFEST),
        "report": relative(REPORT_PATH),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--plan", action="store_true", help="Write and validate the migration plan")
    mode.add_argument("--apply", action="store_true", help="Apply an existing planned migration")
    args = parser.parse_args()
    result = write_plan() if args.plan else apply_plan()
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
