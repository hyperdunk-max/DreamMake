#!/usr/bin/env python3
"""Remove verified numeric progress frames from the ZMX3 classified library.

The decoded SWFs remain the source of truth.  This script only edits
``assets/extracted/classified/zmxiyou3`` and records every removed file hash.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLASSIFIED = ROOT / "assets" / "extracted" / "classified" / "zmxiyou3"
STANDARD = CLASSIFIED / "UI" / "HUD" / "进度条"
MANIFEST = ROOT / "sources" / "manifests" / "zmxiyou3_progress_bar_cleanup.json"
REPORT = ROOT / "sources" / "ZMXIYOU3_PROGRESS_BAR_CLEANUP.md"


@dataclass(frozen=True)
class Sequence:
    key: str
    purpose: str
    package: str
    source_dir: Path
    expected_frames: int
    keep: dict[int, Path]
    formula: str
    direction: str
    evidence: list[str]
    note: str = ""


OTHER_MAT_SPRITES = CLASSIFIED / "公共元件" / "OtherMatv3570" / "sprites"
MAIN_SPRITES = CLASSIFIED / "公共元件" / "main" / "main_game" / "sprites"
COMMON_SPRITES = CLASSIFIED / "公共元件" / "Commonv3720" / "sprites"

SEQUENCES = [
    Sequence(
        key="role_hp",
        purpose="角色生命条",
        package="OtherMatv3570.swf",
        source_dir=OTHER_MAT_SPRITES / "DefineSprite_120_OtherMat_fla.血_43",
        expected_frames=101,
        keep={1: Path("角色") / "hp_slider.png"},
        formula="round(100 * (1 - current_hp / max_hp)) + 1",
        direction="第 1 帧为满值，第 101 帧为空值",
        evidence=["scripts/export/RoleInfo.as:278"],
    ),
    Sequence(
        key="role_mp",
        purpose="角色魔法条",
        package="OtherMatv3570.swf",
        source_dir=OTHER_MAT_SPRITES / "DefineSprite_123_OtherMat_fla.Symbol1_45",
        expected_frames=101,
        keep={1: Path("角色") / "mp_slider.png"},
        formula="round(100 * (1 - current_mp / max_mp)) + 1",
        direction="第 1 帧为满值，第 101 帧为空值",
        evidence=["scripts/export/RoleInfo.as:280"],
    ),
    Sequence(
        key="role_exp",
        purpose="角色经验条",
        package="OtherMatv3570.swf",
        source_dir=OTHER_MAT_SPRITES / "DefineSprite_126_OtherMat_fla.Symbol2_46",
        expected_frames=101,
        keep={1: Path("角色") / "exp_slider.png"},
        formula="round(100 * (1 - current_exp / next_exp)) + 1",
        direction="第 1 帧为满值，第 101 帧为空值",
        evidence=["scripts/export/RoleInfo.as:282"],
    ),
    Sequence(
        key="role_energy",
        purpose="角色无双能量条",
        package="OtherMatv3570.swf",
        source_dir=OTHER_MAT_SPRITES / "DefineSprite_108_OtherMat_fla.元件1_38",
        expected_frames=100,
        keep={
            1: Path("角色") / "energy_slider_bg.png",
            100: Path("角色") / "energy_slider.png",
        },
        formula="wsmc.gotoAndStop(getWsValue())",
        direction="第 1 帧为空槽，第 100 帧为满值",
        evidence=["scripts/export/RoleInfo.as:285-286", "scripts/export/RoleInfo.as:getWsValue"],
    ),
    Sequence(
        key="boss_hp",
        purpose="Boss 生命条组合预览",
        package="OtherMatv3570.swf",
        source_dir=OTHER_MAT_SPRITES / "DefineSprite_385_GMain_bossBlood",
        expected_frames=101,
        keep={1: Path("Boss") / "boss_hp_full_preview.png"},
        formula="100 - round(100 * current_hp / max_hp)",
        direction="传入 0 时 Flash 停在第 1 帧满值，100 为耗尽",
        evidence=[
            "scripts/export/GameInfo.as:528-545",
            "scripts/base/BaseMonster.as:126",
            "SWF XML: symbol385 depth 2 mask moves across 101 frames",
        ],
        note="Boss 名称是独立 namemc（symbol384）的 118 帧语义枚举，本次不删除。",
    ),
    Sequence(
        key="boss_hp_embedded_duplicate",
        purpose="主程序内嵌 Boss 血条分类副本",
        package="zmxiyou3_game.swf / embedded MainResourcev3730",
        source_dir=MAIN_SPRITES
        / "DefineSprite_128_MainResourcev3730_swf$ad398ca7c4f9a83781ef2b28c311051e-1013417090",
        expected_frames=101,
        keep={},
        formula="与 OtherMatv3570 的 Boss 血条同构",
        direction="全部由 OtherMatv3570 标准项与独立 Boss 名称枚举覆盖",
        evidence=[
            "逐帧尺寸一致；像素差异仅位于嵌套 Boss 名称文字区域",
            "OtherMatv3570 symbol385 是运行时 gc.bossBloodClass 的来源",
        ],
        note="标准分类层不保留同一资源的主程序内嵌副本。",
    ),
    Sequence(
        key="loading_progress",
        purpose="资源加载进度条",
        package="Commonv3720.swf",
        source_dir=COMMON_SPRITES / "DefineSprite_347_Common_fla.加载_18",
        expected_frames=100,
        keep={
            1: Path("加载") / "loading_slider_01_preview.png",
            100: Path("加载") / "loading_slider_100.png",
        },
        formula="bar.gotoAndStop(rate)",
        direction="第 1 帧显示 01%，第 100 帧显示 100%",
        evidence=[
            "main_game/scripts/export/LoadingBar.as:setProcess",
            "main_game/scripts/export/LoadingBar2.as:setProcess",
            "main_game/scripts/export/LoadingBar3.as:updatePregress 使用 width 直接生成比例",
        ],
        note="保留 1% 与 100% 对照图；运行时百分比文字由 Godot Label 生成。",
    ),
]


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def numbered_pngs(path: Path) -> dict[int, Path]:
    result: dict[int, Path] = {}
    for file in path.glob("*.png"):
        if not file.stem.isdigit():
            raise RuntimeError(f"Unexpected non-numbered PNG: {file}")
        result[int(file.stem)] = file
    return result


def verify_completed_manifest() -> bool:
    if not MANIFEST.is_file():
        return False
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if data.get("status") == "reverted":
        print(json.dumps({"cleanup_reverted": True, "rollback_manifest": data.get("rollback_manifest")}, ensure_ascii=False))
        return True
    for row in data["retained"]:
        path = ROOT / row["standard_path"]
        if not path.is_file() or sha256(path) != row["sha256"]:
            raise RuntimeError(f"Retained progress asset failed verification: {path}")
    for sequence in SEQUENCES:
        if sequence.source_dir.exists():
            raise RuntimeError(f"Cleaned source directory unexpectedly exists: {sequence.source_dir}")
    print(json.dumps({"already_clean": True, "deleted": data["counts"]["deleted_files"]}, ensure_ascii=False))
    return True


def write_report(manifest: dict[str, object]) -> None:
    sequence_rows = []
    for row in manifest["sequences"]:
        sequence_rows.append(
            f"| {row['purpose']} | {row['original_frames']} | {row['retained_frames']} | {row['deleted_frames']} |"
        )
    REPORT.write_text(
        "\n".join(
            [
                "# 《造梦西游3》进度条冗余帧清理",
                "",
                f"生成时间：{manifest['generated_at']}",
                "",
                "依据 `sources/ASSET_ORGANIZATION_GUIDE.md`，本次只处理已由源码公式和 SWF 时间轴共同确认的数值驱动序列。",
                "真实动画、Boss 名称枚举、宠物成长和其他尚未完成引用映射的候选项未删除。",
                "",
                "| 序列 | 原帧数 | 保留 | 删除 |",
                "| --- | ---: | ---: | ---: |",
                *sequence_rows,
                "",
                f"合计删除 **{manifest['counts']['deleted_files']}** 张分类层 PNG，保留 **{manifest['counts']['retained_files']}** 张标准素材。",
                "",
                "## Godot 替代方式",
                "",
                "- 生命、魔法、经验、无双、Boss 血条：`TextureProgressBar` 或裁切区域，整数复刻时使用 `step = 1`。",
                "- 加载条：完整纹理裁切或 Shader；百分比使用 `Label` 动态显示。",
                "- Boss 名称继续使用独立语义枚举，不与生命比例合并。",
                "",
                "逐文件原路径、SHA-256、源码公式和未处理候选见：",
                "`sources/manifests/zmxiyou3_progress_bar_cleanup.json`",
                "",
            ]
        ),
        encoding="utf-8",
        newline="\n",
    )


def main() -> None:
    if verify_completed_manifest():
        return

    required_sources = [
        ROOT / "sources" / "decoded" / "zmxiyou3" / "OtherMatv3570.swf",
        ROOT / "sources" / "decoded" / "zmxiyou3" / "Commonv3720.swf",
        ROOT / "sources" / "decoded" / "zmxiyou3_game.swf",
    ]
    missing_sources = [relative(path) for path in required_sources if not path.is_file()]
    if missing_sources:
        raise FileNotFoundError(f"Missing decoded provenance SWFs: {missing_sources}")

    sequence_audit: list[dict[str, object]] = []
    retained: list[dict[str, object]] = []
    deleted: list[dict[str, object]] = []

    for sequence in SEQUENCES:
        if not sequence.source_dir.is_dir():
            raise FileNotFoundError(f"Missing progress sequence: {sequence.source_dir}")
        files = numbered_pngs(sequence.source_dir)
        expected_numbers = set(range(1, sequence.expected_frames + 1))
        if set(files) != expected_numbers:
            raise RuntimeError(
                f"Unexpected frame set for {sequence.key}: got {sorted(files)}, expected 1..{sequence.expected_frames}"
            )
        for frame, destination_relative in sequence.keep.items():
            destination = STANDARD / destination_relative
            if destination.exists():
                raise FileExistsError(f"Standard destination already exists: {destination}")
            destination.parent.mkdir(parents=True, exist_ok=True)

        original_rows = {
            frame: {
                "path": relative(path),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
            for frame, path in files.items()
        }

        for frame, path in files.items():
            original = original_rows[frame]
            if frame in sequence.keep:
                destination = STANDARD / sequence.keep[frame]
                path.replace(destination)
                retained.append(
                    {
                        "sequence": sequence.key,
                        "frame": frame,
                        "original_path": original["path"],
                        "standard_path": relative(destination),
                        "bytes": original["bytes"],
                        "sha256": original["sha256"],
                    }
                )
            else:
                path.unlink()
                deleted.append(
                    {
                        "sequence": sequence.key,
                        "frame": frame,
                        "original_path": original["path"],
                        "bytes": original["bytes"],
                        "sha256": original["sha256"],
                        "reason": "数值驱动时间轴中间帧" if sequence.keep else "重复包中的分类副本",
                    }
                )
        if any(sequence.source_dir.iterdir()):
            raise RuntimeError(f"Unexpected files remain in cleaned sequence: {sequence.source_dir}")
        sequence.source_dir.rmdir()

        sequence_audit.append(
            {
                "key": sequence.key,
                "purpose": sequence.purpose,
                "package": sequence.package,
                "original_directory": relative(sequence.source_dir),
                "original_frames": sequence.expected_frames,
                "retained_frames": len(sequence.keep),
                "deleted_frames": sequence.expected_frames - len(sequence.keep),
                "formula": sequence.formula,
                "direction": sequence.direction,
                "evidence": sequence.evidence,
                "note": sequence.note,
            }
        )

    manifest: dict[str, object] = {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "game": "zmxiyou3",
        "policy": "Only verified numeric progress frames and one repeated embedded package copy are removed from classified; decoded SWFs remain provenance.",
        "source_swfs": [relative(path) for path in required_sources],
        "standard_root": relative(STANDARD),
        "counts": {
            "input_files": len(retained) + len(deleted),
            "retained_files": len(retained),
            "deleted_files": len(deleted),
            "deleted_bytes": sum(int(row["bytes"]) for row in deleted),
        },
        "runtime_replacement": {
            "control": "TextureProgressBar or clipped TextureRect/Shader",
            "step": 1,
            "loading_text": "Godot Label",
            "boss_names": "independent semantic enum; not deleted",
        },
        "sequences": sequence_audit,
        "retained": retained,
        "deleted": deleted,
        "pending_review": [
            "GameVipInterfacev3530 的 20 帧 VIP 经验条",
            "GardenInterfacev3500 的 20/100 帧成长与经验条",
            "PetInterfacev1270 的 20/50 帧宠物属性与强化进度条",
            "BackPackInterfacev1000 的 30 帧角色经验条",
            "SutraInterfacev1320 的 50 帧强化进度条",
            "其余恰为 20/25/30/50/100 帧的序列可能是真实特效，未按帧数推断删除",
        ],
    }
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    write_report(manifest)
    print(json.dumps(manifest["counts"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
