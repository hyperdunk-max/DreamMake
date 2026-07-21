#!/usr/bin/env python3
"""Move the ZMX3 extraction into one auditable, non-duplicated asset library.

Unlike the ZMX1 browsing view, this organizer never creates hard links or
copies.  Extracted package directories are moved into their final category,
and files already promoted to ``assets/selected`` become the sole canonical
copy.  Original paths remain in manifests as provenance only.
"""

from __future__ import annotations

import hashlib
import json
import shutil
from collections import Counter
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "assets" / "extracted" / "full" / "zmxiyou3"
TARGET_ROOT = ROOT / "assets" / "extracted" / "classified" / "zmxiyou3"
SELECTED_ROOT = ROOT / "assets" / "selected" / "zmxiyou3"
SELECTED_MANIFEST = SELECTED_ROOT / "playable_roles_manifest.json"
AUDIT_PATH = ROOT / "sources" / "manifests" / "zmxiyou3_unique_organization.json"
REPORT_PATH = ROOT / "sources" / "ZMXIYOU3_INITIAL_ORGANIZATION.md"

OLD_PREFIX = PurePosixPath("assets/extracted/full/zmxiyou3")
NEW_PREFIX = PurePosixPath("assets/extracted/classified/zmxiyou3")


def package_moves() -> list[tuple[PurePosixPath, PurePosixPath]]:
    moves: list[tuple[PurePosixPath, PurePosixPath]] = [
        (PurePosixPath("characters/wukong"), PurePosixPath("人物/悟空")),
        (PurePosixPath("characters/tangseng"), PurePosixPath("人物/唐僧")),
        (PurePosixPath("characters/bajie"), PurePosixPath("人物/八戒")),
        (PurePosixPath("characters/shaseng"), PurePosixPath("人物/沙僧")),
        (
            PurePosixPath("characters/mixed_packages/Role1v690"),
            PurePosixPath("人物/悟空/技能与动作/Role1v690"),
        ),
        (
            PurePosixPath("characters/mixed_packages/Role2v3550"),
            PurePosixPath("人物/唐僧/技能与动作/Role2v3550"),
        ),
        (
            PurePosixPath("characters/mixed_packages/Role3v690"),
            PurePosixPath("人物/八戒/技能与动作/Role3v690"),
        ),
        (
            PurePosixPath("characters/mixed_packages/Role4v3550"),
            PurePosixPath("人物/沙僧/技能与动作/Role4v3550"),
        ),
        (
            PurePosixPath("characters/mixed_packages/RoleSkillInterfacev3550"),
            PurePosixPath("UI/技能/RoleSkillInterfacev3550"),
        ),
    ]

    directory_categories = {
        "audio": PurePosixPath("音频"),
        "environments": PurePosixPath("场景与地图/地图与背景"),
        "magic_weapons": PurePosixPath("法宝"),
        "monsters": PurePosixPath("怪物"),
        "pets": PurePosixPath("宠物"),
        "shared": PurePosixPath("公共元件"),
        "ui": PurePosixPath("UI/界面"),
    }
    for source_category, destination_category in directory_categories.items():
        root = SOURCE_ROOT / source_category
        for package in sorted((path for path in root.iterdir() if path.is_dir()), key=lambda path: path.name.lower()):
            moves.append(
                (
                    PurePosixPath(source_category) / package.name,
                    destination_category / package.name,
                )
            )

    stages_root = SOURCE_ROOT / "stages"
    for package in sorted((path for path in stages_root.iterdir() if path.is_dir()), key=lambda path: path.name.lower()):
        if package.name == "stageCommonv1270":
            destination = PurePosixPath("场景与地图/公共元件") / package.name
        elif package.name == "stageInfov1620":
            destination = PurePosixPath("场景与地图/关卡信息") / package.name
        else:
            destination = PurePosixPath("场景与地图/关卡") / package.name
        moves.append((PurePosixPath("stages") / package.name, destination))

    return moves


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tree_stats(path: Path) -> tuple[int, int]:
    files = [item for item in path.rglob("*") if item.is_file()]
    return len(files), sum(item.stat().st_size for item in files)


def remove_empty_parents(path: Path, stop: Path) -> None:
    current = path
    while current != stop and current.is_dir() and not any(current.iterdir()):
        current.rmdir()
        current = current.parent


def mapped_relative(path: PurePosixPath, moves: list[tuple[PurePosixPath, PurePosixPath]]) -> PurePosixPath:
    for old, new in sorted(moves, key=lambda row: len(row[0].parts), reverse=True):
        try:
            suffix = path.relative_to(old)
        except ValueError:
            continue
        return new / suffix
    raise ValueError(f"No classification mapping for {path.as_posix()}")


def map_recorded_path(value: str, moves: list[tuple[PurePosixPath, PurePosixPath]]) -> str:
    normalized = PurePosixPath(value.replace("\\", "/"))
    try:
        relative = normalized.relative_to(OLD_PREFIX)
    except ValueError:
        return value
    return (NEW_PREFIX / mapped_relative(relative, moves)).as_posix()


def rewrite_path_strings(value: Any, moves: list[tuple[PurePosixPath, PurePosixPath]]) -> Any:
    if isinstance(value, str):
        return map_recorded_path(value, moves)
    if isinstance(value, list):
        return [rewrite_path_strings(item, moves) for item in value]
    if isinstance(value, dict):
        return {key: rewrite_path_strings(item, moves) for key, item in value.items()}
    return value


def move_packages(moves: list[tuple[PurePosixPath, PurePosixPath]]) -> list[dict[str, Any]]:
    audit: list[dict[str, Any]] = []
    for old, new in moves:
        source = SOURCE_ROOT / Path(*old.parts)
        destination = TARGET_ROOT / Path(*new.parts)
        if not source.is_dir():
            raise FileNotFoundError(f"Missing source package: {source}")
        if destination.exists():
            raise FileExistsError(f"Classification destination already exists: {destination}")
        files, size = tree_stats(source)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source), str(destination))
        audit.append(
            {
                "original": (OLD_PREFIX / old).as_posix(),
                "destination": (NEW_PREFIX / new).as_posix(),
                "files": files,
                "bytes": size,
            }
        )
    return audit


def promote_selected_files(moves: list[tuple[PurePosixPath, PurePosixPath]]) -> list[dict[str, Any]]:
    manifest = json.loads(SELECTED_MANIFEST.read_text(encoding="utf-8"))
    promoted: list[dict[str, Any]] = []
    rewritten_records: list[dict[str, Any]] = []
    seen_sources: set[Path] = set()

    for record in manifest["files"]:
        original_source = str(record["source"])
        mapped_source = ROOT / Path(*PurePosixPath(map_recorded_path(original_source, moves)).parts)
        destination_text = str(record["destination"])
        destination = ROOT / Path(*PurePosixPath(destination_text).parts)
        if not mapped_source.is_file():
            raise FileNotFoundError(f"Moved source is missing: {mapped_source}")
        if not destination.is_file():
            raise FileNotFoundError(f"Selected destination is missing: {destination}")
        source_hash = sha256(mapped_source)
        destination_hash = sha256(destination)
        if source_hash != destination_hash:
            raise RuntimeError(f"Selected file differs from source: {destination}")
        if mapped_source in seen_sources:
            raise RuntimeError(f"One source was promoted more than once: {mapped_source}")
        seen_sources.add(mapped_source)

        mapped_source.unlink()
        remove_empty_parents(mapped_source.parent, TARGET_ROOT)
        metadata = {key: value for key, value in record.items() if key not in {"source", "destination", "bytes"}}
        rewritten_records.append(
            {
                "canonical": destination_text,
                "original_source": original_source,
                "sha256": destination_hash.lower(),
                "bytes": destination.stat().st_size,
                **metadata,
            }
        )
        promoted.append(
            {
                "original_source": original_source,
                "removed_classified_copy": mapped_source.relative_to(ROOT).as_posix(),
                "canonical": destination_text,
                "sha256": destination_hash.lower(),
                "bytes": destination.stat().st_size,
            }
        )

    manifest["policy"] = (
        "Each listed PNG has one canonical file in assets/selected. The former extracted path is provenance only; "
        "its duplicate was removed after SHA-256 verification."
    )
    manifest["files"] = rewritten_records
    SELECTED_MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return promoted


def rewrite_selected_path_references(moves: list[tuple[PurePosixPath, PurePosixPath]]) -> int:
    rewritten = 0
    for path in SELECTED_ROOT.rglob("*.json"):
        if path == SELECTED_MANIFEST:
            continue
        original = json.loads(path.read_text(encoding="utf-8"))
        updated = rewrite_path_strings(original, moves)
        if updated == original:
            continue
        path.write_text(json.dumps(updated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        rewritten += 1
    return rewritten


def rewrite_harvest_markers(moves: list[tuple[PurePosixPath, PurePosixPath]]) -> int:
    marker_root = ROOT / ".tools" / "harvest_state"
    rewritten = 0
    for path in marker_root.glob("*.json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        output = Path(str(data.get("output", "")))
        try:
            relative = output.relative_to(SOURCE_ROOT)
        except ValueError:
            continue
        new_relative = mapped_relative(PurePosixPath(relative.as_posix()), moves)
        data["output"] = str(TARGET_ROOT / Path(*new_relative.parts))
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        rewritten += 1
    return rewritten


def write_report(audit: dict[str, Any]) -> None:
    category_rows = "\n".join(
        f"| `{category}` | {count:,} |"
        for category, count in audit["files_by_category"].items()
    )
    REPORT_PATH.write_text(
        "\n".join(
            [
                "# 《造梦西游3》素材初步整理",
                "",
                f"生成时间：{audit['generated_at']}",
                "",
                "本轮采用唯一归档策略：分类过程只移动文件，不复制、不建立硬链接。",
                f"原拆包目录 `{OLD_PREFIX.as_posix()}` 已清空并移除；唯一分类库位于 `{NEW_PREFIX.as_posix()}`。",
                "",
                "## 分类统计",
                "",
                "| 分类 | 文件数 |",
                "| --- | ---: |",
                category_rows,
                "",
                "## 去重处理",
                "",
                f"现有角色精选区中有 {audit['selected_promotions']:,} 个文件原为逐字节复制。",
                "逐一校验 SHA-256 后，保留 `assets/selected/zmxiyou3` 中的可用成品，删除分类库中的对应源位置副本；",
                "原路径和校验值保留在 `playable_roles_manifest.json` 与机器审计中。",
                "",
                "## 当前边界",
                "",
                "本轮完成包级初分，并保留 FFDec 的 images、sprites、scripts 等内部结构，避免破坏符号证据。",
                "动作标签、怪物原作名、关卡名和匿名元件归属将在后续精分阶段依据源码与 SWF 引用链继续整理。",
                "",
                "机器审计：`sources/manifests/zmxiyou3_unique_organization.json`",
                "",
            ]
        ),
        encoding="utf-8",
        newline="\n",
    )


def main() -> None:
    if not SOURCE_ROOT.is_dir():
        raise SystemExit(f"Source extraction does not exist: {SOURCE_ROOT}")
    if TARGET_ROOT.exists() and any(TARGET_ROOT.iterdir()):
        raise SystemExit(f"Target must be absent or empty: {TARGET_ROOT}")

    before_files, before_bytes = tree_stats(SOURCE_ROOT)
    moves = package_moves()
    move_audit = move_packages(moves)
    promoted = promote_selected_files(moves)
    rewritten_selected_manifests = rewrite_selected_path_references(moves)
    rewritten_markers = rewrite_harvest_markers(moves)

    for path in sorted(SOURCE_ROOT.rglob("*"), key=lambda item: len(item.parts), reverse=True):
        if path.is_dir() and not any(path.iterdir()):
            path.rmdir()
    if SOURCE_ROOT.exists() and not any(SOURCE_ROOT.iterdir()):
        SOURCE_ROOT.rmdir()

    after_files, after_bytes = tree_stats(TARGET_ROOT)
    expected_files = before_files - len(promoted)
    expected_bytes = before_bytes - sum(int(row["bytes"]) for row in promoted)
    if after_files != expected_files or after_bytes != expected_bytes:
        raise RuntimeError(
            f"Post-move totals differ: files={after_files}/{expected_files}, bytes={after_bytes}/{expected_bytes}"
        )

    counts: Counter[str] = Counter()
    for path in TARGET_ROOT.rglob("*"):
        if path.is_file():
            counts[path.relative_to(TARGET_ROOT).parts[0]] += 1

    audit: dict[str, Any] = {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "policy": "move-only classification; selected assets are canonical after verified source-duplicate removal",
        "source_root_removed": not SOURCE_ROOT.exists(),
        "target_root": TARGET_ROOT.relative_to(ROOT).as_posix(),
        "before": {"files": before_files, "bytes": before_bytes},
        "after": {"files": after_files, "bytes": after_bytes},
        "selected_promotions": len(promoted),
        "selected_bytes_promoted": sum(int(row["bytes"]) for row in promoted),
        "selected_json_manifests_rewritten": rewritten_selected_manifests,
        "harvest_markers_rewritten": rewritten_markers,
        "files_by_category": dict(sorted(counts.items())),
        "package_moves": move_audit,
        "promoted_files": promoted,
    }
    AUDIT_PATH.parent.mkdir(parents=True, exist_ok=True)
    AUDIT_PATH.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    write_report(audit)
    print(json.dumps({key: audit[key] for key in ("before", "after", "selected_promotions", "files_by_category")}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
