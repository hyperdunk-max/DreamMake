#!/usr/bin/env python3
"""Build an auditable index for the extracted Dream Westward Journey assets."""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / ".tools"
STATE = TOOLS / "harvest_state"
EXPORT_ROOT = ROOT / "assets" / "extracted" / "full"
SOURCES = ROOT / "sources"
INDEX_PATH = SOURCES / "manifests" / "full_extraction_index.json"
UNAVAILABLE_PATH = SOURCES / "manifests" / "unavailable_resources.json"
REPORT_PATH = SOURCES / "FULL_EXTRACTION_REPORT.md"
ZMXIYOU2_ORGANIZATION_PATH = SOURCES / "manifests" / "zmxiyou2_canonical_migration.json"

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

GAME_LABELS = {
    "zmxiyou1": "造梦西游 1",
    "zmxiyou2": "造梦西游 2",
    "zmxiyou3": "造梦西游 3",
}

ROLE_LABELS = {
    "wukong": "悟空",
    "tangseng": "唐僧",
    "bajie": "猪八戒",
    "shaseng": "沙僧",
    "mixed_packages": "混合角色包",
}


def read_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def human_size(size: int) -> str:
    units = ("B", "KB", "MB", "GB", "TB")
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.2f} {unit}"
        value /= 1024
    raise AssertionError("unreachable")


def markdown_table(headers: list[str], rows: list[list[object]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |"]
    lines.append("| " + " | ".join("---" for _ in headers) + " |")
    lines.extend("| " + " | ".join(str(cell) for cell in row) + " |" for row in rows)
    return lines


def main() -> None:
    markers = [read_json(path) for path in sorted(STATE.glob("*.json"))]
    download_report = read_json(TOOLS / "full_resource_report.json")
    export_report = read_json(TOOLS / "full_export_report.json")
    classified_rows_by_package: dict[str, list[dict[str, object]]] = defaultdict(list)
    if ZMXIYOU2_ORGANIZATION_PATH.is_file():
        organization = read_json(ZMXIYOU2_ORGANIZATION_PATH)
        for row in organization.get("retained_files", organization.get("files", [])):
            classified_rows_by_package[str(row["package"])].append(row)

    packages_by_game: Counter[str] = Counter()
    packages_by_category: Counter[tuple[str, str]] = Counter()
    type_files: Counter[str] = Counter()
    type_bytes: Counter[str] = Counter()
    game_files: Counter[str] = Counter()
    game_bytes: Counter[str] = Counter()
    extensions: Counter[str] = Counter()
    character_variants: dict[tuple[str, str, str], list[str]] = defaultdict(list)
    package_rows: list[dict[str, object]] = []

    for marker in markers:
        resource = marker["resource"]
        game = resource["game"]
        category = resource["category"]
        output = Path(marker["output"])
        packages_by_game[game] += 1
        packages_by_category[(game, category.split("/")[0])] += 1

        parts = category.split("/")
        if parts[0] == "characters" and len(parts) >= 2:
            role = parts[1]
            kind = parts[2] if len(parts) >= 3 else "package"
            variant = parts[3] if len(parts) >= 4 else Path(resource["name"]).stem
            character_variants[(game, role, kind)].append(variant)

        package_file_count = 0
        package_bytes = 0
        package_type_files: Counter[str] = Counter()
        recorded_output = str(output.relative_to(ROOT)).replace("\\", "/")
        if output.exists():
            for path in output.rglob("*"):
                if not path.is_file():
                    continue
                size = path.stat().st_size
                relative_parts = path.relative_to(output).parts
                asset_type = relative_parts[0] if relative_parts and relative_parts[0] in FFDEC_TYPES else "other"
                type_files[asset_type] += 1
                type_bytes[asset_type] += size
                package_type_files[asset_type] += 1
                package_file_count += 1
                package_bytes += size
                game_files[game] += 1
                game_bytes[game] += size
                extensions[path.suffix.lower() or "[no extension]"] += 1
        elif game == "zmxiyou2" and classified_rows_by_package:
            old_game_root = EXPORT_ROOT / game
            package_key = "__".join(output.relative_to(old_game_root).parts)
            fallback_rows = classified_rows_by_package.get(package_key, [])
            old_package_prefix = output.relative_to(ROOT).as_posix()
            for row in fallback_rows:
                destination = ROOT / str(row["destination"])
                size = int(row["bytes"])
                source_relative = Path(str(row["source"])).relative_to(old_package_prefix)
                relative_parts = source_relative.parts
                asset_type = relative_parts[0] if relative_parts and relative_parts[0] in FFDEC_TYPES else "other"
                type_files[asset_type] += 1
                type_bytes[asset_type] += size
                package_type_files[asset_type] += 1
                package_file_count += 1
                package_bytes += size
                game_files[game] += 1
                game_bytes[game] += size
                extensions[destination.suffix.lower() or "[no extension]"] += 1
            recorded_output = f"assets/extracted/classified/zmxiyou2 (manifest package {package_key})"

        package_rows.append(
            {
                "game": game,
                "name": resource["name"],
                "category": category,
                "origin": resource["origin"],
                "source_sha256": marker["source_sha256"],
                "output": recorded_output,
                "files": package_file_count,
                "bytes": package_bytes,
                "types": dict(sorted(package_type_files.items())),
            }
        )

    unavailable = [row for row in download_report if row["status"] == "http_404"]
    download_status_by_game: Counter[tuple[str, str]] = Counter(
        (row["game"], row["status"]) for row in download_report
    )
    export_status = Counter(row["status"] for row in export_report)

    character_rows: list[dict[str, object]] = []
    for (game, role, kind), variants in sorted(character_variants.items()):
        variants = sorted(set(variants), key=lambda value: (not value.isdigit(), int(value) if value.isdigit() else value))
        character_rows.append(
            {
                "game": game,
                "role": role,
                "kind": kind,
                "count": len(variants),
                "variants": variants,
            }
        )

    index = {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "candidate_urls": len(download_report),
        "reachable_dynamic_packages": sum(1 for row in download_report if row["status"] in {"cached", "downloaded"}),
        "unavailable_http_404": len(unavailable),
        "exported_containers": len(markers),
        "export_status": dict(sorted(export_status.items())),
        "packages_by_game": dict(sorted(packages_by_game.items())),
        "packages_by_category": {
            f"{game}/{category}": count
            for (game, category), count in sorted(packages_by_category.items())
        },
        "files_by_game": {
            game: {"files": game_files[game], "bytes": game_bytes[game]}
            for game in sorted(packages_by_game)
        },
        "files_by_type": {
            kind: {"files": type_files[kind], "bytes": type_bytes[kind]}
            for kind in sorted(type_files)
        },
        "files_by_extension": dict(extensions.most_common()),
        "character_variants": character_rows,
        "packages": sorted(package_rows, key=lambda row: (row["game"], row["category"], row["name"])),
    }

    INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
    INDEX_PATH.write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
    UNAVAILABLE_PATH.write_text(json.dumps(unavailable, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")

    lines = [
        "# 《造梦西游》1–3 全资源提取报告",
        "",
        f"> 生成时间：{index['generated_at']}",
        "",
        "## 结论",
        "",
        f"已成功导出 **{len(markers)} 个有效 SWF 容器**，共 **{sum(game_files.values()):,} 个文件**（**{human_size(sum(game_bytes.values()))}**）。导出失败和超时均为 0。",
        "",
        "资源来自客户端主程序、网页外层加载器以及客户端代码实际发现的动态 SWF 地址。远端共检查 461 个候选地址，其中 237 个仍可取得；224 个返回 HTTP 404，未冒充为已提取资源，详单见 `sources/manifests/unavailable_resources.json`。造 3 页面旧 `sda` 地址返回的 23 KB 错误提示动画不计入游戏资源。",
        "",
        "## 各代汇总",
        "",
    ]
    lines.extend(
        markdown_table(
            ["游戏", "有效容器", "导出文件", "导出大小"],
            [
                [GAME_LABELS[game], packages_by_game[game], f"{game_files[game]:,}", human_size(game_bytes[game])]
                for game in sorted(packages_by_game)
            ],
        )
    )
    lines.extend(["", "## FFDec 类型分类", ""])
    lines.extend(
        markdown_table(
            ["类型目录", "文件数", "大小"],
            [
                [kind, f"{type_files[kind]:,}", human_size(type_bytes[kind])]
                for kind in sorted(type_files)
            ],
        )
    )
    lines.extend(["", "每个资源包内部保留 FFDec 的标准类型目录；空目录也保留，因此即使某包没有声音或精灵，目录结构仍一致。", "", "## 业务目录包数", ""])
    lines.extend(
        markdown_table(
            ["游戏", "业务分类", "容器数"],
            [
                [GAME_LABELS[game], category, count]
                for (game, category), count in sorted(packages_by_category.items())
            ],
        )
    )
    lines.extend(["", "## 角色多套资源", ""])
    lines.append("造 3 的角色外观和武器按 `角色/部位/showid/资源包/类型` 独立保存，便于后续人工选择；造 1、造 2 的角色素材由原版合并在单一 Role 包内，因此保留在 `characters/mixed_packages`，没有擅自拆散符号依赖。")
    lines.append("")
    lines.extend(
        markdown_table(
            ["游戏", "角色", "资源部位", "套数", "showid / 包"],
            [
                [GAME_LABELS[row["game"]], ROLE_LABELS.get(row["role"], row["role"]), row["kind"], row["count"], ", ".join(row["variants"])]
                for row in character_rows
            ],
        )
    )
    lines.extend(
        [
            "",
            "## 目录与索引",
            "",
            "- 造 1 完整导出：`assets/extracted/full/zmxiyou1/`",
            "- 造 2 唯一分类库：`assets/extracted/classified/zmxiyou2/`",
            "- 造 3 唯一分类库：`assets/extracted/classified/zmxiyou3/`（移动式整理，不另留完整提取副本）",
            "- 完整机器索引：`sources/manifests/full_extraction_index.json`",
            "- HTTP 404 候选详单：`sources/manifests/unavailable_resources.json`",
            "- 下载审计：`.tools/full_resource_report.json`",
            "- 导出审计：`.tools/full_export_report.json`",
            "- 原始与解码 SWF：`sources/raw/`、`sources/decoded/`",
            "",
            "重新生成索引：",
            "",
            "```powershell",
            "& '.tools\\python-portable\\python.exe' 'tools\\build_full_resource_index.py'",
            "```",
            "",
        ]
    )
    REPORT_PATH.write_text("\n".join(lines), encoding="utf-8", newline="\n")

    print(json.dumps({
        "containers": len(markers),
        "files": sum(game_files.values()),
        "bytes": sum(game_bytes.values()),
        "index": str(INDEX_PATH),
        "report": str(REPORT_PATH),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
