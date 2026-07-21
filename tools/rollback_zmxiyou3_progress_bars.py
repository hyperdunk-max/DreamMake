#!/usr/bin/env python3
"""Restore the ZMX3 progress-frame cleanup from its audit manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLEANUP_MANIFEST = ROOT / "sources" / "manifests" / "zmxiyou3_progress_bar_cleanup.json"
ROLLBACK_MANIFEST = ROOT / "sources" / "manifests" / "zmxiyou3_progress_bar_rollback.json"
CLEANUP_REPORT = ROOT / "sources" / "ZMXIYOU3_PROGRESS_BAR_CLEANUP.md"
INITIAL_REPORT = ROOT / "sources" / "ZMXIYOU3_INITIAL_ORGANIZATION.md"
STANDARD_ROOT = ROOT / "assets" / "extracted" / "classified" / "zmxiyou3" / "UI" / "HUD" / "进度条"
STANDARD_HUD_ROOT = STANDARD_ROOT.parent
TEMP_ROOT = ROOT / ".tools" / "restore_progress"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def export_path(original_path: str) -> Path:
    normalized = Path(original_path)
    mappings = [
        (Path("assets/extracted/classified/zmxiyou3/公共元件/OtherMatv3570"), TEMP_ROOT / "OtherMatv3570"),
        (Path("assets/extracted/classified/zmxiyou3/公共元件/Commonv3720"), TEMP_ROOT / "Commonv3720"),
        (Path("assets/extracted/classified/zmxiyou3/公共元件/main/main_game"), TEMP_ROOT / "main_game"),
    ]
    for prefix, export_root in mappings:
        try:
            suffix = normalized.relative_to(prefix)
        except ValueError:
            continue
        all_export_path = export_root / suffix
        if all_export_path.exists():
            return all_export_path
        if suffix.parts and suffix.parts[0] == "sprites":
            sprite_only_path = export_root / Path(*suffix.parts[1:])
            if sprite_only_path.exists():
                return sprite_only_path
        return all_export_path
    raise ValueError(f"No temporary export mapping for {original_path}")


def preflight(data: dict[str, object]) -> dict[str, object]:
    if data.get("status") == "reverted":
        raise RuntimeError("Progress cleanup is already marked reverted")

    errors: list[str] = []
    retained_checks: list[dict[str, object]] = []
    deleted_checks: list[dict[str, object]] = []

    for row in data["retained"]:
        source = ROOT / row["standard_path"]
        destination = ROOT / row["original_path"]
        actual_hash = sha256(source) if source.is_file() else ""
        ok = source.is_file() and not destination.exists() and actual_hash == row["sha256"]
        retained_checks.append(
            {
                "standard_path": row["standard_path"],
                "original_path": row["original_path"],
                "expected_sha256": row["sha256"],
                "actual_sha256": actual_hash,
                "ok": ok,
            }
        )
        if not ok:
            errors.append(f"Retained preflight failed: {row['standard_path']}")

    for row in data["deleted"]:
        source = export_path(row["original_path"])
        destination = ROOT / row["original_path"]
        actual_hash = sha256(source) if source.is_file() else ""
        ok = source.is_file() and not destination.exists() and actual_hash == row["sha256"]
        deleted_checks.append(
            {
                "temporary_export": source.relative_to(ROOT).as_posix(),
                "original_path": row["original_path"],
                "expected_sha256": row["sha256"],
                "actual_sha256": actual_hash,
                "ok": ok,
            }
        )
        if not ok:
            errors.append(f"Deleted-frame preflight failed: {row['original_path']}")

    return {
        "retained": retained_checks,
        "deleted": deleted_checks,
        "errors": errors,
        "checked_files": len(retained_checks) + len(deleted_checks),
    }


def remove_empty_standard_directories() -> list[str]:
    removed: list[str] = []
    if not STANDARD_ROOT.exists():
        return removed
    for path in sorted(STANDARD_ROOT.rglob("*"), key=lambda item: len(item.parts), reverse=True):
        if path.is_dir() and not any(path.iterdir()):
            path.rmdir()
            removed.append(path.relative_to(ROOT).as_posix())
    if STANDARD_ROOT.is_dir() and not any(STANDARD_ROOT.iterdir()):
        STANDARD_ROOT.rmdir()
        removed.append(STANDARD_ROOT.relative_to(ROOT).as_posix())
    if STANDARD_HUD_ROOT.is_dir() and not any(STANDARD_HUD_ROOT.iterdir()):
        STANDARD_HUD_ROOT.rmdir()
        removed.append(STANDARD_HUD_ROOT.relative_to(ROOT).as_posix())
    return removed


def update_reports(reverted_at: str, restored: int) -> None:
    report = CLEANUP_REPORT.read_text(encoding="utf-8")
    if "状态：已回退" not in report:
        report = report.replace(
            "# 《造梦西游3》进度条冗余帧清理\n",
            "# 《造梦西游3》进度条冗余帧清理\n\n状态：已回退\n",
            1,
        )
        report += (
            "\n## 回退记录\n\n"
            f"{reverted_at} 已恢复 {restored} 张原时间轴 PNG；本报告仅保留为历史审计。\n"
            "详见 `sources/manifests/zmxiyou3_progress_bar_rollback.json`。\n"
        )
        CLEANUP_REPORT.write_text(report, encoding="utf-8", newline="\n")

    initial = INITIAL_REPORT.read_text(encoding="utf-8")
    old = (
        "已按素材整理规范清理角色 HUD、Boss 血条和加载条的数值驱动中间帧，保留满值、底槽或对照图。\n"
        "详细记录见 `sources/ZMXIYOU3_PROGRESS_BAR_CLEANUP.md` 与\n"
        "`sources/manifests/zmxiyou3_progress_bar_cleanup.json`。"
    )
    new = (
        "此前的进度条精简已按用户要求回退，原 705 张时间轴 PNG 均已恢复。\n"
        "历史清理与回退记录见 `sources/manifests/zmxiyou3_progress_bar_cleanup.json` 和\n"
        "`sources/manifests/zmxiyou3_progress_bar_rollback.json`。"
    )
    if old in initial:
        INITIAL_REPORT.write_text(initial.replace(old, new, 1), encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="only verify rollback inputs")
    args = parser.parse_args()

    data = json.loads(CLEANUP_MANIFEST.read_text(encoding="utf-8"))
    if data.get("status") == "reverted":
        rollback = (
            json.loads(ROLLBACK_MANIFEST.read_text(encoding="utf-8"))
            if ROLLBACK_MANIFEST.is_file()
            else {}
        )
        print(
            json.dumps(
                {
                    "rollback": "already_reverted",
                    "restored_files": rollback.get("restored_files"),
                    "rollback_manifest": ROLLBACK_MANIFEST.relative_to(ROOT).as_posix(),
                },
                ensure_ascii=False,
            )
        )
        return

    checks = preflight(data)
    if checks["errors"]:
        print(json.dumps(checks, ensure_ascii=False, indent=2))
        raise SystemExit(f"Rollback preflight failed for {len(checks['errors'])} files")
    if args.check:
        print(json.dumps({"preflight": "ok", "checked_files": checks["checked_files"]}, ensure_ascii=False))
        return

    for row in data["retained"]:
        source = ROOT / row["standard_path"]
        destination = ROOT / row["original_path"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        source.replace(destination)

    for row in data["deleted"]:
        source = export_path(row["original_path"])
        destination = ROOT / row["original_path"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)

    restored_rows = list(data["retained"]) + list(data["deleted"])
    verification_errors: list[str] = []
    for row in restored_rows:
        path = ROOT / row["original_path"]
        if not path.is_file() or sha256(path) != row["sha256"]:
            verification_errors.append(row["original_path"])
    if verification_errors:
        raise RuntimeError(f"Post-rollback verification failed: {verification_errors[:10]}")

    reverted_at = datetime.now().astimezone().isoformat(timespec="seconds")
    removed_empty = remove_empty_standard_directories()
    rollback = {
        "generated_at": reverted_at,
        "game": "zmxiyou3",
        "action": "revert progress bar cleanup",
        "cleanup_manifest": CLEANUP_MANIFEST.relative_to(ROOT).as_posix(),
        "restored_files": len(restored_rows),
        "restored_retained_moves": len(data["retained"]),
        "restored_deleted_exports": len(data["deleted"]),
        "sha256_verified": len(restored_rows),
        "removed_empty_standard_directories": removed_empty,
        "source_exports": [
            ".tools/restore_progress/OtherMatv3570",
            ".tools/restore_progress/Commonv3720",
            ".tools/restore_progress/main_game",
        ],
        "preflight": {
            "checked_files": checks["checked_files"],
            "errors": 0,
        },
    }
    ROLLBACK_MANIFEST.write_text(
        json.dumps(rollback, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    data["status"] = "reverted"
    data["reverted_at"] = reverted_at
    data["rollback_manifest"] = ROLLBACK_MANIFEST.relative_to(ROOT).as_posix()
    CLEANUP_MANIFEST.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    update_reports(reverted_at, len(restored_rows))

    resolved_temp = TEMP_ROOT.resolve()
    if resolved_temp.is_relative_to(ROOT.resolve()) and resolved_temp.name == "restore_progress":
        shutil.rmtree(resolved_temp)
    else:
        raise RuntimeError(f"Refusing to remove unexpected temporary path: {resolved_temp}")

    print(json.dumps(rollback, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
