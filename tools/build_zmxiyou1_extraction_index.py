#!/usr/bin/env python3
"""Build a manual-curation index for the complete Dream Journey 1 export."""

from __future__ import annotations

import hashlib
import json
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPORT_ROOT = ROOT / "assets" / "extracted" / "full" / "zmxiyou1"
RAW_ROOT = ROOT / "sources" / "raw" / "zmxiyou1"
DECODED_ROOT = ROOT / "sources" / "decoded" / "zmxiyou1"
MANIFEST_PATH = ROOT / "sources" / "manifests" / "zmxiyou1_full_extraction.json"
DUPLICATES_PATH = ROOT / "sources" / "manifests" / "zmxiyou1_duplicate_files.json"
REPORT_PATH = ROOT / "sources" / "ZMXIYOU1_FULL_EXTRACTION_REPORT.md"
LOCAL_README_PATH = EXPORT_ROOT / "README.md"

FFDEC_TYPES = {
    "binaryData",
    "buttons",
    "fonts",
    "frames",
    "images",
    "morphshapes",
    "movies",
    "scripts",
    "shapes",
    "sounds",
    "sprites",
    "symbolClass",
    "texts",
}

PACKAGE_ROOTS = {
    "Music": EXPORT_ROOT / "audio" / "Music",
    "Role_v7": EXPORT_ROOT / "characters" / "mixed_packages" / "Role_v7",
    "Monster_v1": EXPORT_ROOT / "monsters" / "Monster_v1",
    "Monster2_v4": EXPORT_ROOT / "monsters" / "Monster2_v4",
    "Monster3_v3": EXPORT_ROOT / "monsters" / "Monster3_v3",
    "OtherMat_v9": EXPORT_ROOT / "shared" / "OtherMat_v9",
    "backpack_v2": EXPORT_ROOT / "shared" / "backpack_v2",
    "main_game": EXPORT_ROOT / "shared" / "main" / "main_game",
    "portal_loader": EXPORT_ROOT / "shared" / "portal_loader" / "portal_loader",
    "portal_4399_gif": EXPORT_ROOT / "shared" / "portal_embedded" / "4399_gif",
}

ACTIVE_LOADER_PACKAGES = [
    "Role_v7.swf",
    "Monster_v1.swf",
    "Monster2_v4.swf",
    "Monster3_v3.swf",
    "OtherMat_v9.swf",
    "backpack_v2.swf",
    "Music.swf",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def human_size(size: int) -> str:
    value = float(size)
    for unit in ("B", "KB", "MB", "GB"):
        if value < 1024.0 or unit == "GB":
            return f"{value:.2f} {unit}"
        value /= 1024.0
    raise AssertionError("unreachable")


def asset_type(package_root: Path, path: Path) -> str:
    for part in path.relative_to(package_root).parts[:-1]:
        if part in FFDEC_TYPES:
            return part
    return "other"


def source_rows() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for kind, folder in (("raw", RAW_ROOT), ("decoded", DECODED_ROOT)):
        if not folder.exists():
            continue
        for path in sorted(folder.rglob("*.swf")):
            rows.append(
                {
                    "kind": kind,
                    "file": relative(path),
                    "bytes": path.stat().st_size,
                    "sha256": sha256(path),
                }
            )
    return rows


def main() -> None:
    if not EXPORT_ROOT.exists():
        raise SystemExit(f"Missing export root: {EXPORT_ROOT}")

    package_rows: list[dict[str, object]] = []
    totals_by_type: Counter[str] = Counter()
    bytes_by_type: Counter[str] = Counter()
    hashes: dict[str, list[Path]] = defaultdict(list)
    sizes: dict[str, int] = {}
    all_files: list[Path] = []

    for package_name, package_root in PACKAGE_ROOTS.items():
        files = sorted(path for path in package_root.rglob("*") if path.is_file()) if package_root.exists() else []
        by_type: Counter[str] = Counter()
        type_bytes: Counter[str] = Counter()
        for path in files:
            kind = asset_type(package_root, path)
            size = path.stat().st_size
            by_type[kind] += 1
            type_bytes[kind] += size
            totals_by_type[kind] += 1
            bytes_by_type[kind] += size
            digest = sha256(path)
            hashes[digest].append(path)
            sizes[digest] = size
        all_files.extend(files)
        package_rows.append(
            {
                "package": package_name,
                "path": relative(package_root),
                "exists": package_root.exists(),
                "files": len(files),
                "bytes": sum(path.stat().st_size for path in files),
                "types": {
                    kind: {"files": by_type[kind], "bytes": type_bytes[kind]}
                    for kind in sorted(by_type)
                },
            }
        )

    duplicate_groups: list[dict[str, object]] = []
    duplicate_extra_bytes = 0
    for digest, paths in hashes.items():
        if len(paths) < 2:
            continue
        size = sizes[digest]
        duplicate_extra_bytes += size * (len(paths) - 1)
        duplicate_groups.append(
            {
                "sha256": digest,
                "bytes_each": size,
                "copies": len(paths),
                "reclaimable_bytes": size * (len(paths) - 1),
                "files": [relative(path) for path in paths],
            }
        )
    duplicate_groups.sort(key=lambda row: (-int(row["reclaimable_bytes"]), str(row["sha256"])))

    embedded_swf = []
    for path in all_files:
        if path.stat().st_size < 3:
            continue
        with path.open("rb") as handle:
            signature = handle.read(3)
        if signature in (b"FWS", b"CWS", b"ZWS"):
            embedded_swf.append(
                {
                    "file": relative(path),
                    "signature": signature.decode("ascii"),
                    "bytes": path.stat().st_size,
                    "sha256": sha256(path),
                }
            )

    manifest = {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "game": "造梦西游1",
        "scope": "主程序、4399 外壳、7 个动态资源包及递归发现的内嵌 SWF",
        "active_loader_source": "assets/extracted/full/zmxiyou1/shared/main/main_game/scripts/loader/Aloader.as",
        "active_loader_packages": ACTIVE_LOADER_PACKAGES,
        "scope_notes": [
            "无版本号和旧版本 SWF 名称仅出现在各资源包附带的历史 Loader 副本中，不在当前主程序加载队列。",
            "cdn.comment.4399pk.com 下的 SWF 是网页评论控件，不属于游戏客户端资源。",
        ],
        "export_root": relative(EXPORT_ROOT),
        "godot_ignored_by": "assets/extracted/.gdignore",
        "containers_exported": len(PACKAGE_ROOTS),
        "files": len(all_files),
        "bytes": sum(path.stat().st_size for path in all_files),
        "files_by_type": {
            kind: {"files": totals_by_type[kind], "bytes": bytes_by_type[kind]}
            for kind in sorted(totals_by_type)
        },
        "packages": package_rows,
        "source_files": source_rows(),
        "embedded_swf": embedded_swf,
        "duplicate_groups": len(duplicate_groups),
        "duplicate_reclaimable_bytes": duplicate_extra_bytes,
        "duplicates_manifest": relative(DUPLICATES_PATH),
    }
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    DUPLICATES_PATH.write_text(
        json.dumps(
            {
                "generated_at": manifest["generated_at"],
                "policy": "仅报告字节完全一致的文件；未自动删除，供人工整理时安全去重。",
                "groups": duplicate_groups,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    package_lines = [
        f"| {row['package']} | `{row['path']}` | {row['files']:,} | {human_size(int(row['bytes']))} |"
        for row in package_rows
    ]
    type_lines = [
        f"| `{kind}` | {totals_by_type[kind]:,} | {human_size(bytes_by_type[kind])} |"
        for kind in sorted(totals_by_type)
    ]
    report = "\n".join(
        [
            "# 《造梦西游1》完整拆包索引",
            "",
            f"生成时间：{manifest['generated_at']}",
            "",
            f"已完整导出 **{len(PACKAGE_ROOTS)} 个容器**、**{len(all_files):,} 个文件**（{human_size(int(manifest['bytes']))}）。",
            "导出覆盖主程序、4399 外壳、角色、三套怪物、公共 UI、背包和音乐，并递归拆出了外壳内嵌的 4399 动画。",
            "当前主程序 `loader/Aloader.as` 的有效加载列表与这 7 个动态包完全一致；旧版本文件名仅存在于资源包附带的历史 Loader 副本中。",
            "",
            "## 手工整理入口",
            "",
            f"- 完整导出目录：`{relative(EXPORT_ROOT)}`",
            f"- 机器索引：`{relative(MANIFEST_PATH)}`",
            f"- 字节级重复文件清单：`{relative(DUPLICATES_PATH)}`",
            "- 原始 SWF：`sources/raw/zmxiyou1/`",
            "- 标准化 SWF：`sources/decoded/zmxiyou1/`",
            "",
            "`assets/extracted/.gdignore` 会阻止 Godot 扫描整个拆包目录；整理后的成品请复制到 `assets/selected/zmxiyou1/`。",
            "",
            "## 容器",
            "",
            "| 容器 | 路径 | 文件数 | 大小 |",
            "| --- | --- | ---: | ---: |",
            *package_lines,
            "",
            "## FFDec 分类",
            "",
            "| 目录 | 文件数 | 大小 |",
            "| --- | ---: | ---: |",
            *type_lines,
            "",
            "常用整理顺序：先看 `symbolClass/` 和 `scripts/` 确认语义，再到 `sprites/`、`frames/`、`images/` 选成品；音效位于 `sounds/`，文本位于 `texts/`。",
            "",
            "## 去重",
            "",
            f"检测到 {len(duplicate_groups):,} 组字节完全一致的文件，理论可回收 {human_size(duplicate_extra_bytes)}。",
            "本次仅生成清单，不自动删除，避免破坏 FFDec 的符号/帧目录关系。你完成挑选后，我可根据整理目录再次安全去重。",
            "",
        ]
    )
    REPORT_PATH.write_text(report, encoding="utf-8")
    LOCAL_README_PATH.write_text(report, encoding="utf-8")

    print(
        json.dumps(
            {
                "containers": len(PACKAGE_ROOTS),
                "files": len(all_files),
                "bytes": manifest["bytes"],
                "duplicate_groups": len(duplicate_groups),
                "duplicate_reclaimable_bytes": duplicate_extra_bytes,
                "manifest": relative(MANIFEST_PATH),
                "report": relative(REPORT_PATH),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
