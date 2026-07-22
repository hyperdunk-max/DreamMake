#!/usr/bin/env python3
"""Extract traceable ZMX1 monster animation and behavior events.

The exact animation events come from ActionScript ``addFrameScript`` calls on
the root or nested MovieClip classes.  Monster class behavior (projectile
creation, sound, state changes, dispatches, and timing conditions) is kept as
separate source evidence because it is not necessarily tied to an animation
frame.

This script only reads the full extraction and writes an audit manifest.  It
does not edit or delete extracted assets.
"""

from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from audit_zmxiyou1_monster_timelines import PACKAGES, XML_ROOT, parse_timelines, symbol_map


ROOT = Path(__file__).resolve().parents[1]
FULL_ROOT = ROOT / "assets" / "extracted" / "full" / "zmxiyou1" / "monsters"
TIMELINE_AUDIT = ROOT / "sources" / "manifests" / "zmxiyou1_monster_timeline_audit.json"
OUTPUT = ROOT / "sources" / "manifests" / "zmxiyou1_monster_events.json"


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def find_matching_brace(text: str, opening: int) -> int:
    """Find the closing brace while ignoring strings and comments."""
    depth = 0
    quote = ""
    escaped = False
    line_comment = False
    block_comment = False
    index = opening
    while index < len(text):
        char = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""
        if line_comment:
            if char == "\n":
                line_comment = False
            index += 1
            continue
        if block_comment:
            if char == "*" and following == "/":
                block_comment = False
                index += 2
            else:
                index += 1
            continue
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            index += 1
            continue
        if char in {'"', "'"}:
            quote = char
        elif char == "/" and following == "/":
            line_comment = True
            index += 2
            continue
        elif char == "/" and following == "*":
            block_comment = True
            index += 2
            continue
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    raise ValueError(f"Unmatched brace at character {opening}")


def function_ranges(text: str) -> dict[str, dict[str, Any]]:
    pattern = re.compile(
        r"\bfunction\s+([A-Za-z_$][\w$]*)\s*\([^)]*\)"
        r"\s*(?::\s*[^\s{]+)?\s*\{",
        re.MULTILINE,
    )
    result: dict[str, dict[str, Any]] = {}
    for match in pattern.finditer(text):
        opening = text.find("{", match.start(), match.end())
        closing = find_matching_brace(text, opening)
        result[match.group(1)] = {
            "body": text[opening + 1 : closing].strip(),
            "start_line": line_number(text, match.start()),
            "end_line": line_number(text, closing),
            "start_offset": match.start(),
            "end_offset": closing + 1,
        }
    return result


def classify_frame_code(code: str) -> list[str]:
    if not code.strip():
        return ["no_op"]
    kinds: list[str] = []
    checks = (
        ("action_transition", r"\bcurAction\s*=|\bgotoAnd(?:Stop|Play)\s*\("),
        ("projectile_spawn", r"\bnew\s+[\w.$]*Bullet\w*\s*\(|getNewObj\([^\n;]*Bullet"),
        ("object_spawn", r"\bnew\s+[A-Za-z_$][\w.$]*\s*\(|\bgetNewObj\s*\(|\baddChild(?:At)?\s*\("),
        ("sound", r"\bSoundManager\.play\s*\("),
        ("event_dispatch", r"\bdispatchEvent\s*\("),
        ("combat", r"\b(?:attack|beAttack|fireHit|releSkill|hitTest|setRole|setAction)\w*\s*\("),
        ("motion", r"\b(?:speed\.[xy]|graity|horizenSpeed)\s*=|\bsetStatic\s*\("),
        ("visibility", r"\bvisible\s*="),
        ("cleanup", r"\b(?:removeChild|removeMovieClip|destroy)\w*\s*\("),
        ("timeline_control", r"(?<![\w.])(?:stop|play)\s*\("),
    )
    for kind, pattern in checks:
        if re.search(pattern, code, flags=re.IGNORECASE):
            kinds.append(kind)
    if code and not kinds:
        kinds.append("custom_script")
    return kinds


def frame_scripts(path: Path) -> list[dict[str, Any]]:
    text = path.read_text(encoding="utf-8-sig")
    functions = function_ranges(text)
    registrations: list[tuple[int, str]] = []
    for call in re.finditer(r"\baddFrameScript\s*\((.*?)\)\s*;", text, flags=re.DOTALL):
        registrations.extend(
            (int(index), method)
            for index, method in re.findall(r"(\d+)\s*,\s*this\.([A-Za-z_$][\w$]*)", call.group(1))
        )
    events: list[dict[str, Any]] = []
    for zero_based, method in registrations:
        function = functions.get(method)
        if function is None:
            events.append(
                {
                    "frame": zero_based + 1,
                    "frame_index_zero_based": zero_based,
                    "method": method,
                    "types": ["unresolved_frame_script"],
                    "code": "",
                    "source": relative(path),
                    "source_lines": None,
                }
            )
            continue
        code = str(function["body"])
        events.append(
            {
                "frame": zero_based + 1,
                "frame_index_zero_based": zero_based,
                "method": method,
                "types": classify_frame_code(code),
                "code": code,
                "source": relative(path),
                "source_lines": {
                    "start": function["start_line"],
                    "end": function["end_line"],
                },
            }
        )
    return events


def symbol_script(package_root: Path, symbol_name: str) -> Path | None:
    if not symbol_name or symbol_name.startswith("character_"):
        return None
    candidate = package_root / "scripts" / Path(*symbol_name.split(".")).with_suffix(".as")
    return candidate if candidate.exists() else None


def reachable_sprite_ids(start_ids: Iterable[int], timelines: dict[int, Any]) -> set[int]:
    pending = list(start_ids)
    visited: set[int] = set()
    while pending:
        current = pending.pop()
        if current in visited:
            continue
        visited.add(current)
        sprite = timelines.get(current)
        if sprite is not None:
            pending.extend(sprite.referenced_ids() - visited)
    return visited


def method_at_offset(functions: dict[str, dict[str, Any]], offset: int) -> str:
    matches = [
        (name, item)
        for name, item in functions.items()
        if int(item["start_offset"]) <= offset < int(item["end_offset"])
    ]
    if not matches:
        return "<class>"
    return min(matches, key=lambda item: int(item[1]["end_offset"]) - int(item[1]["start_offset"]))[0]


def behavior_evidence(path: Path) -> list[dict[str, Any]]:
    text = path.read_text(encoding="utf-8-sig")
    functions = function_ranges(text)
    patterns = (
        ("action_state", re.compile(r"\bcurAction\s*=\s*['\"][^'\"]+['\"]")),
        ("timeline_command", re.compile(r"\bgotoAnd(?:Stop|Play)\s*\([^;]+")),
        ("projectile_spawn", re.compile(r"\bnew\s+[\w.$]*Bullet\w*\s*\([^;]*")),
        ("object_factory", re.compile(r"\bAUtils\.getNewObj\s*\([^;]+")),
        ("sound", re.compile(r"\bSoundManager\.play\s*\([^;]+")),
        ("event_dispatch", re.compile(r"\b\w*eventManger\.dispatchEvent\s*\([^;]+")),
        (
            "gameplay_call",
            re.compile(
                r"\bthis\.(?:fire\w*|shoot\w*|releSkill\w*|attackTarget|add\w*(?:Bullet|Effect)\w*)\s*\([^;]*",
                flags=re.IGNORECASE,
            ),
        ),
        (
            "collision_check",
            re.compile(r"\b(?:HitTest\.[\w$]+|[\w.$]+\.hitTestObject|AUtils\.testIntersects)\s*\([^;]+"),
        ),
        (
            "damage_application",
            re.compile(r"\b(?:[\w.$]+\.)?Hp\s*[-+]?=\s*[^;]+|\b(?:getRealHurt|beAttackBack)\s*\([^;]+"),
        ),
        (
            "timing_condition",
            re.compile(
                r"\bif\s*\([^\n]*(?:\bcount\b|\b\w*(?:Time|CD)\w*\b)[^\n]*\)",
                flags=re.IGNORECASE,
            ),
        ),
    )
    rows: list[dict[str, Any]] = []
    seen: set[tuple[str, int, str]] = set()
    for kind, pattern in patterns:
        for match in pattern.finditer(text):
            line = line_number(text, match.start())
            code = " ".join(match.group(0).split())
            key = (kind, line, code)
            if key in seen:
                continue
            seen.add(key)
            rows.append(
                {
                    "kind": kind,
                    "method": method_at_offset(functions, match.start()),
                    "source": relative(path),
                    "line": line,
                    "code": code,
                    "frame_mapping": "not_inferred",
                }
            )
    return sorted(rows, key=lambda row: (int(row["line"]), str(row["kind"]), str(row["code"])))


def attack_profiles(path: Path) -> dict[str, list[dict[str, Any]]]:
    text = path.read_text(encoding="utf-8-sig")
    result: dict[str, list[dict[str, Any]]] = {}
    pattern = re.compile(r"attackBackInfoDict\s*\[\s*['\"]([^'\"]+)['\"]\s*\]\s*=\s*\{")
    for match in pattern.finditer(text):
        opening = text.find("{", match.start(), match.end())
        closing = find_matching_brace(text, opening)
        code = text[match.start() : closing + 1]
        fields: dict[str, Any] = {}
        for key in ("hitMaxCount", "attackInterval", "AttackInterval", "power", "attackKind"):
            field = re.search(rf"['\"]{key}['\"]\s*:\s*([^,\n}}]+)", code)
            if field:
                value = field.group(1).strip().strip("'\"")
                fields["attackInterval" if key == "AttackInterval" else key] = value
        speed = re.search(r"['\"]attackBackSpeed['\"]\s*:\s*(\[[^\]]*\])", code)
        if speed:
            fields["attackBackSpeed"] = speed.group(1)
        result.setdefault(match.group(1), []).append(
            {
                "fields": fields,
                "code": code,
                "source": relative(path),
                "source_lines": {
                    "start": line_number(text, match.start()),
                    "end": line_number(text, closing),
                },
            }
        )
    return result


def main() -> None:
    audit = json.loads(TIMELINE_AUDIT.read_text(encoding="utf-8"))
    package_data: dict[str, dict[str, Any]] = {}
    for package in PACKAGES:
        package_root = FULL_ROOT / package
        package_data[package] = {
            "root": package_root,
            "symbols": symbol_map(package_root),
            "timelines": parse_timelines(XML_ROOT / f"{package}.xml"),
        }

    source_files: dict[str, str] = {relative(TIMELINE_AUDIT): sha256(TIMELINE_AUDIT)}
    script_cache: dict[Path, list[dict[str, Any]]] = {}
    monsters: dict[str, dict[str, Any]] = {}
    counts: Counter[str] = Counter()
    unique_frame_scripts: set[tuple[str, int, int, str]] = set()
    unique_meaningful_frame_events: set[tuple[str, int, int, str]] = set()

    shared_runtime_evidence: dict[str, list[dict[str, Any]]] = {}
    for package in PACKAGES:
        rows: list[dict[str, Any]] = []
        for shared_name in ("BaseMonster.as", "BaseObject.as"):
            shared_path = FULL_ROOT / package / "scripts" / "base" / shared_name
            if not shared_path.exists():
                continue
            evidence = behavior_evidence(shared_path)
            source_files[relative(shared_path)] = sha256(shared_path)
            rows.append(
                {
                    "source": relative(shared_path),
                    "source_sha256": source_files[relative(shared_path)],
                    "behavior_evidence": evidence,
                }
            )
            counts["shared_behavior_evidence"] += len(evidence)
        shared_runtime_evidence[package] = rows

    for monster_key, monster in sorted(audit["monsters"].items()):
        package = str(monster["package"])
        data = package_data[package]
        package_root = data["root"]
        symbols: dict[int, str] = data["symbols"]
        timelines: dict[int, Any] = data["timelines"]
        root_id = int(monster["root_symbol_id"])
        root_script = symbol_script(package_root, str(monster["root_symbol"]))
        root_events: list[dict[str, Any]] = []
        behavior: list[dict[str, Any]] = []
        profiles: dict[str, list[dict[str, Any]]] = {}
        if root_script is not None:
            root_events = frame_scripts(root_script)
            behavior = behavior_evidence(root_script)
            profiles = attack_profiles(root_script)
            source_files[relative(root_script)] = sha256(root_script)

        monster_row: dict[str, Any] = {
            "package": package,
            "source_folder": monster["source_folder"],
            "root_symbol_id": root_id,
            "root_symbol": monster["root_symbol"],
            "root_script": relative(root_script) if root_script else None,
            "shared_runtime_evidence_package": package,
            "attack_profiles": profiles,
            "behavior_evidence": behavior,
            "actions": [],
        }
        counts["monsters"] += 1
        counts["behavior_evidence"] += len(behavior)
        counts["attack_profile_definitions"] += sum(len(rows) for rows in profiles.values())

        root_timeline = timelines.get(root_id)
        for action in monster["actions"]:
            start = int(action["root_frame_start"])
            end = int(action["root_frame_end"])
            action_root_events = []
            for event in root_events:
                if start <= int(event["frame"]) <= end:
                    row = dict(event)
                    row["timeline_scope"] = "root"
                    row["root_frame"] = row["frame"]
                    row["action_root_frame"] = int(row["frame"]) - start + 1
                    action_root_events.append(row)
                    event_key = (package, root_id, int(row["frame"]), str(row["method"]))
                    unique_frame_scripts.add(event_key)
                    if row["types"] != ["no_op"]:
                        unique_meaningful_frame_events.add(event_key)

            direct_ids: set[int] = set()
            if root_timeline is not None:
                direct_ids = {
                    int(item.character_id)
                    for item in root_timeline.display_list_at(start).values()
                    if item.character_id is not None
                }
            reachable = reachable_sprite_ids(direct_ids, timelines)
            provider_ids = {int(provider["symbol_id"]) for provider in action["providers"]}
            provider_rows: list[dict[str, Any]] = []
            nested_rows: list[dict[str, Any]] = []

            for symbol_id in sorted(reachable | provider_ids):
                symbol_name = symbols.get(symbol_id, f"character_{symbol_id}")
                script = symbol_script(package_root, symbol_name)
                if script is None:
                    if symbol_id in provider_ids:
                        provider = next(item for item in action["providers"] if int(item["symbol_id"]) == symbol_id)
                        provider_rows.append({**provider, "script": None, "frame_events": []})
                    continue
                if script not in script_cache:
                    script_cache[script] = frame_scripts(script)
                    source_files[relative(script)] = sha256(script)
                events = script_cache[script]
                if not events and symbol_id not in provider_ids:
                    continue
                timeline = timelines.get(symbol_id)
                row = {
                    "symbol_id": symbol_id,
                    "symbol_name": symbol_name,
                    "frame_count": timeline.frame_count if timeline else None,
                    "script": relative(script),
                    "script_sha256": source_files[relative(script)],
                    "frame_events": [],
                }
                for event in events:
                    event_row = dict(event)
                    event_row["timeline_scope"] = "complete_action" if symbol_id in provider_ids else "nested"
                    if symbol_id in provider_ids:
                        event_row["action_frame"] = event_row["frame"]
                    else:
                        event_row["action_frame"] = None
                    row["frame_events"].append(event_row)
                    event_key = (package, symbol_id, int(event_row["frame"]), str(event_row["method"]))
                    unique_frame_scripts.add(event_key)
                    if event_row["types"] != ["no_op"]:
                        unique_meaningful_frame_events.add(event_key)
                if symbol_id in provider_ids:
                    provider = next(item for item in action["providers"] if int(item["symbol_id"]) == symbol_id)
                    row.update(provider)
                    provider_rows.append(row)
                elif events:
                    nested_rows.append(row)

            monster_row["actions"].append(
                {
                    "label": action["label"],
                    "folder": action["folder"],
                    "root_frame_start": start,
                    "root_frame_end": end,
                    "root_frame_events": action_root_events,
                    "providers": provider_rows,
                    "nested_event_sources": nested_rows,
                }
            )
            counts["actions"] += 1
            counts["provider_timelines"] += len(provider_rows)
            counts["root_frame_event_references"] += len(action_root_events)
            counts["provider_frame_event_references"] += sum(len(row["frame_events"]) for row in provider_rows)
            counts["nested_frame_event_references"] += sum(len(row["frame_events"]) for row in nested_rows)

        monsters[monster_key] = monster_row

    counts["unique_frame_script_registrations"] = len(unique_frame_scripts)
    counts["unique_exact_frame_events"] = len(unique_meaningful_frame_events)
    counts["source_scripts"] = len(source_files) - 1

    invalid_event_frames: list[dict[str, Any]] = []
    unresolved_frame_scripts = 0
    for monster_key, monster in monsters.items():
        for action in monster["actions"]:
            for provider in [*action["providers"], *action["nested_event_sources"]]:
                for event in provider["frame_events"]:
                    if event["types"] == ["unresolved_frame_script"]:
                        unresolved_frame_scripts += 1
                    if provider["frame_count"] is not None and int(event["frame"]) > int(provider["frame_count"]):
                        invalid_event_frames.append(
                            {
                                "monster": monster_key,
                                "action": action["label"],
                                "symbol": provider["symbol_name"],
                                "frame": event["frame"],
                                "frame_count": provider["frame_count"],
                            }
                        )
            unresolved_frame_scripts += sum(
                1 for event in action["root_frame_events"] if event["types"] == ["unresolved_frame_script"]
            )
    validation = {
        "status": "pass",
        "monster_coverage_matches_timeline_audit": len(monsters) == len(audit["monsters"]),
        "action_coverage_matches_timeline_audit": counts["actions"] == int(audit["counts"]["actions"]),
        "provider_coverage_matches_timeline_audit": counts["provider_timelines"] == int(audit["counts"]["provider_assignments"]),
        "event_frames_out_of_range": invalid_event_frames,
        "unresolved_frame_scripts": unresolved_frame_scripts,
        "all_hashed_sources_exist": all((ROOT / path).exists() for path in source_files),
    }
    if not all(
        (
            validation["monster_coverage_matches_timeline_audit"],
            validation["action_coverage_matches_timeline_audit"],
            validation["provider_coverage_matches_timeline_audit"],
            not invalid_event_frames,
            unresolved_frame_scripts == 0,
            validation["all_hashed_sources_exist"],
        )
    ):
        validation["status"] = "fail"
        raise RuntimeError(json.dumps(validation, ensure_ascii=False, indent=2))
    payload = {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "purpose": "Batch, source-traceable extraction of ZMX1 monster animation frame events and non-frame behavior evidence.",
        "scope": "All monsters present in zmxiyou1_monster_timeline_audit.json across Monster_v1, Monster2_v4, and Monster3_v3.",
        "source_timeline_audit": relative(TIMELINE_AUDIT),
        "extraction_policy": {
            "exact_frame_events": "Only ActionScript addFrameScript registrations are treated as exact frame events. addFrameScript uses zero-based indices; frame is stored one-based.",
            "complete_action_mapping": "Events on a complete action provider expose action_frame directly. Events on nested children keep only their local frame because parent/child playback offsets are not inferred.",
            "behavior_evidence": "Monster class state changes, projectile creation, sounds, dispatches, and timing conditions are extracted with source lines but frame_mapping remains not_inferred.",
            "empty_or_missing_scripts": "A provider without an ActionScript class or addFrameScript registration legitimately has no extracted exact frame event; visual frames remain valid animation data.",
            "deletion_effect": "This manifest is generated entirely from assets/extracted/full and the timeline audit; classified root-frame PNG files are not an input.",
        },
        "packages": list(PACKAGES),
        "source_files_sha256": dict(sorted(source_files.items())),
        "shared_runtime_evidence": shared_runtime_evidence,
        "monsters": monsters,
        "counts": dict(sorted(counts.items())),
        "validation": validation,
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload["counts"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
