"""Replace ZMX1 selected monster frame copies with classified sprite atlases.

Dry-run is the default. Pass --execute after reviewing the validation output.
The script preserves profile timing, source events, and sprite offsets; only the
image source fields are migrated.
"""

from __future__ import annotations

import argparse
import filecmp
import json
import re
import shutil
from pathlib import Path

from sprite_packer import pack_sprites


ROOT = Path(__file__).resolve().parents[1]
CLASSIFIED_ROOT = ROOT / "assets/extracted/classified/zmxiyou1/怪物"
SELECTED_ROOT = ROOT / "assets/selected/zmxiyou1/monsters"
PROFILE_ROOT = ROOT / "resources/enemies/animations"

CLASSIFIED_MONSTER_DIRS = {
    "M01": "M01",
    "M02": "M02",
    "M03": "M03_大猩猩",
    "M04": "M04_彌猴王",
    "M06": "M06_禺狨王",
    "M07": "M07",
    "M08": "M08",
    "M09": "M09_彭魔王",
    "M10": "M10_鲛魔王",
    "M11": "M11_狮驼王",
    "M13": "M13",
    "M14": "M14",
    "M15": "M15",
    "M16": "M16",
    "M17": "M17_龟丞相",
    "M18": "M18",
    "M19": "M19_鲨魔王",
    "M20": "M20",
    "M21": "M21_蝙蝠洞",
    "M22": "M22_牛魔王",
    "M23": "M23_牛魔王",
    "M25": "M25",
    "M26": "M26_龙王",
    "M27": "M27_宝箱",
}

SELECTED_MONSTER_DIRS = {
    "M01": "m01",
    "M02": "m02",
    "M03": "m03_gorilla",
    "M04": "m04_monkey_king",
    "M06": "m06_yu_rong",
    "M07": "m07",
    "M08": "m08",
    "M09": "m09_peng",
    "M10": "m10_jiao",
    "M11": "m11_lion",
    "M13": "m13",
    "M14": "m14",
    "M15": "m15",
    "M16": "m16",
    "M17": "m17_turtle",
    "M18": "m18",
    "M19": "m19_shark",
    "M20": "m20",
    "M21": "m21_bat",
    "M22": "m22_bull",
    "M23": "m23_bull",
    "M25": "m25",
    "M26": "m26_dragon",
    "M27": "m27_chest",
}

DEFAULT_ACTION_PATHS = {
    "hurt": "受伤",
    "recover": "受伤恢复",
    "idle": "待机",
    "move": "移动",
    "death": "死亡",
    "attack1": "攻击1",
    "attack2": "攻击2",
    "attack3": "攻击3",
    "attack4": "攻击4",
    "attack5": "攻击5",
    "idle1": "待机1",
    "idle2": "待机2",
    "move1": "移动1",
    "move2": "移动2",
    "attack1_1": "攻击1_阶段1",
    "attack1_2": "攻击1_阶段2",
    "attack2_1": "攻击2_阶段1",
    "attack2_2": "攻击2_阶段2",
    "attack3_1": "攻击3_阶段1",
}

ACTION_PATH_OVERRIDES = {
    ("M04", "attack2"): "攻击2/元件45ssss_9",
    ("M06", "attack1"): "攻击1/元件9_23",
    ("M06", "attack2"): "攻击2/元件12_26",
    ("M08", "attack1"): "攻击1/character_218",
    ("M09", "egg"): "变蛋/Timeline_101",
    ("M09", "fly"): "共享动作时间轴",
    ("M09", "attack2"): "攻击2/Timeline_97",
    ("M09", "reburn"): "重燃/character_622",
    ("M10", "attack1"): "攻击1/Timeline_21",
    ("M10", "attack3"): "攻击3/character_1112",
    ("M11", "attack2"): "攻击2/Timeline_190",
    ("M11", "attack3"): "攻击3/character_159",
    ("M16", "attack2"): "攻击2/Timeline_76",
    ("M18", "attack2"): "攻击2/Timeline_174",
    ("M20", "attack1"): "攻击1/Timeline_212",
    ("M23", "attack2"): "攻击2/Timeline_35",
    ("M23", "attack3"): "攻击3/Timeline_40",
    ("M23", "attack4"): "攻击4/Timeline_42",
    ("M23", "attack5"): "攻击5/Timeline_52",
    ("M26", "attack2"): "攻击2/Timeline_14",
    ("M26", "attack3"): "攻击3/Timeline_26",
}

ACTION_START_RE = re.compile(r'^&"([^\"]+)": \{$')


def atlas_source(mid: str, action: str) -> Path | None:
    if (mid, action) == ("M01", "idle"):
        return None
    relative = ACTION_PATH_OVERRIDES.get((mid, action), DEFAULT_ACTION_PATHS.get(action))
    if relative is None:
        raise ValueError(f"No classified atlas mapping for {mid}/{action}")
    return CLASSIFIED_ROOT / CLASSIFIED_MONSTER_DIRS[mid] / relative


def atlas_target(mid: str, action: str) -> Path:
    return SELECTED_ROOT / SELECTED_MONSTER_DIRS[mid] / action


def frame_count(json_path: Path) -> int:
    data = json.loads(json_path.read_text(encoding="utf-8"))
    return int(data["meta"]["frameCount"])


def migrate_profile(profile_path: Path, execute: bool) -> tuple[int, list[tuple[Path, Path]]]:
    text = profile_path.read_text(encoding="utf-8")
    mid_match = re.search(r'source_monster_id = &"(M\d+)"', text)
    if mid_match is None or mid_match.group(1) not in CLASSIFIED_MONSTER_DIRS:
        return 0, []
    mid = mid_match.group(1)
    copies: list[tuple[Path, Path]] = []
    action_count = 0

    def replace_action(action: str, body: str, trailing_comma: bool) -> str:
        nonlocal action_count
        profile_count_match = re.search(r'"frame_count": (\d+)', body)
        if profile_count_match is None:
            raise ValueError(f"Missing frame_count in {profile_path.name}/{action}")
        profile_count = int(profile_count_match.group(1))
        source_dir = atlas_source(mid, action)
        target_dir = atlas_target(mid, action)

        if source_dir is not None:
            source_json = source_dir / "sprite.json"
            source_png = source_dir / "sprite.png"
            if not source_json.is_file() or not source_png.is_file():
                raise FileNotFoundError(f"Missing classified atlas for {mid}/{action}: {source_dir}")
            json_count = frame_count(source_json)
            if json_count != profile_count:
                raise ValueError(
                    f"Frame count mismatch {profile_path.name}/{action}: "
                    f"profile={profile_count}, atlas={json_count}"
                )
            copies.extend(((source_png, target_dir / "sprite.png"), (source_json, target_dir / "sprite.json")))
        else:
            local_json = target_dir / "sprite.json"
            local_png = target_dir / "sprite.png"
            if local_json.is_file() and local_png.is_file():
                if frame_count(local_json) != profile_count:
                    raise ValueError("Existing M01 idle atlas has an invalid frame count")
            else:
                source_frames = sorted(target_dir.glob("frame_*.png"))
                if len(source_frames) != profile_count:
                    raise ValueError(
                        f"M01 idle fallback needs {profile_count} frames, found {len(source_frames)}"
                    )

        resource_dir = target_dir.relative_to(ROOT).as_posix()
        body = re.sub(r'^"path_pattern": .*\n', "", body, flags=re.MULTILINE)
        body = re.sub(r'^"sprite_sheet(?:_json)?": .*\n', "", body, flags=re.MULTILINE)
        atlas_fields = (
            f'"sprite_sheet": "res://{resource_dir}/sprite.png",\n'
            f'"sprite_sheet_json": "res://{resource_dir}/sprite.json",\n'
        )
        body = body.replace('"source_events":', atlas_fields + '"source_events":', 1)
        if '"sprite_sheet":' not in body or '"sprite_sheet_json":' not in body:
            raise ValueError(f"Cannot locate source_events in {profile_path.name}/{action}")
        action_count += 1
        suffix = "," if trailing_comma else ""
        return f'&"{action}": {{\n{body.rstrip()}\n}}{suffix}\n'

    lines = text.splitlines(keepends=True)
    migrated_parts: list[str] = []
    index = 0
    while index < len(lines):
        start_line = lines[index].rstrip("\r\n")
        start_match = ACTION_START_RE.match(start_line)
        if start_match is None:
            migrated_parts.append(lines[index])
            index += 1
            continue

        depth = 0
        end_index = index
        while end_index < len(lines):
            depth += lines[end_index].count("{") - lines[end_index].count("}")
            if depth == 0:
                break
            end_index += 1
        if depth != 0:
            raise ValueError(f"Unclosed action block in {profile_path.name}/{start_match.group(1)}")

        end_line = lines[end_index].rstrip("\r\n")
        trailing_comma = end_line.endswith(",")
        body = "".join(lines[index + 1 : end_index])
        migrated_parts.append(replace_action(start_match.group(1), body, trailing_comma))
        index = end_index + 1

    migrated = "".join(migrated_parts)
    if execute and migrated != text:
        profile_path.write_text(migrated, encoding="utf-8", newline="\n")
    return action_count, copies


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true", help="apply the validated migration")
    args = parser.parse_args()

    profiles = sorted(PROFILE_ROOT.glob("zmxiyou1*_profile.tres"))
    all_copies: dict[Path, Path] = {}
    action_total = 0
    for profile in profiles:
        count, copies = migrate_profile(profile, args.execute)
        action_total += count
        for source, target in copies:
            previous = all_copies.get(target)
            if previous is not None and previous != source:
                raise ValueError(f"Conflicting atlas sources for {target}: {previous} and {source}")
            all_copies[target] = source

    frame_files = sorted(SELECTED_ROOT.rglob("frame_*.png"))
    frame_imports = sorted(SELECTED_ROOT.rglob("frame_*.png.import"))
    missing_targets = [target for target in all_copies if not target.is_file()]
    mismatched_targets = [
        target
        for target, source in all_copies.items()
        if target.is_file() and not filecmp.cmp(source, target, shallow=False)
    ]
    print(
        f"validated profiles={len(profiles)} actions={action_total} "
        f"unique_atlas_files={len(all_copies)} frame_png={len(frame_files)} "
        f"frame_import={len(frame_imports)} target_missing={len(missing_targets)} "
        f"target_mismatch={len(mismatched_targets)}"
    )
    if not args.execute:
        print("dry-run only; pass --execute to migrate")
        return 0

    m01_idle = atlas_target("M01", "idle")
    if not (m01_idle / "sprite.png").is_file() or not (m01_idle / "sprite.json").is_file():
        pack_sprites(str(m01_idle), str(m01_idle / "sprite"))
    if frame_count(m01_idle / "sprite.json") != 6:
        raise ValueError("Packed M01 idle atlas does not contain 6 frames")

    for target, source in all_copies.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    for path in frame_files + frame_imports:
        resolved = path.resolve()
        if SELECTED_ROOT.resolve() not in resolved.parents:
            raise ValueError(f"Refusing to delete outside selected monster root: {resolved}")
        path.unlink()

    for directory in sorted(SELECTED_ROOT.rglob("*"), key=lambda path: len(path.parts), reverse=True):
        if directory.is_dir():
            try:
                directory.rmdir()
            except OSError:
                pass

    print("migration complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
