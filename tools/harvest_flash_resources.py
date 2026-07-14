#!/usr/bin/env python3
"""Discover, download, decode, classify, and export Dream Journey Flash assets.

The harvester is intentionally resumable. Downloads use `.part` files, decoded
SWFs are validated by signature, and successful FFDec exports receive markers
under `.tools/harvest_state`.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / ".tools"
MANIFEST_PATH = TOOLS / "full_resource_manifest.json"
REPORT_PATH = TOOLS / "full_resource_report.json"
STATE_DIR = TOOLS / "harvest_state"
FFDEC = TOOLS / "ffdec" / "ffdec-cli.exe"

BASE_URLS = {
    "zmxiyou1": "https://sbai.4399.com/4399swf/upload_swf/ftp5/hanbao/20110624/3/",
    "zmxiyou2": "https://sbai.4399.com/4399swf/upload_swf/ftp6/hanbao/20110927/4/",
    "zmxiyou3": "https://sbai.4399.com/4399swf/upload_swf/ftp7/hanbao/20120107/6/",
}

ROLE_NAMES = {1: "wukong", 2: "tangseng", 3: "bajie", 4: "shaseng"}
SWF_MAGIC = (b"CWS", b"FWS", b"ZWS")
# Current 4399 "access error" movie, served for some nonexistent paths.
KNOWN_ERROR_HASHES = {
    "7ae5fab9d7c370babffa840557c4566a4d5cc8d89e4bdd6cc80f524eb52b1719"
}


@dataclass(frozen=True)
class Resource:
    game: str
    name: str
    category: str
    origin: str

    @property
    def url(self) -> str:
        return BASE_URLS[self.game] + self.name


def natural_key(value: str) -> list[int | str]:
    return [int(part) if part.isdigit() else part.lower() for part in re.split(r"(\d+)", value)]


def add_resource(items: dict[tuple[str, str], Resource], game: str, name: str, category: str, origin: str) -> None:
    name = name.replace("\\", "/").lstrip("./")
    if not name.lower().endswith(".swf"):
        name += ".swf"
    if name.lower() in {"_assets/assets.swf", "assets/assets.swf", "assets.swf"}:
        return
    key = (game, name)
    previous = items.get(key)
    if previous is None or previous.category in {"shared", "candidate"}:
        items[key] = Resource(game, name, category, origin)


def category_for_name(name: str) -> str:
    lower = name.lower()
    if "music" in lower or lower.startswith("sound"):
        return "audio"
    if lower.startswith("monster"):
        return "monsters"
    if lower.startswith(("pet", "turtle", "dragon", "phoenix", "rabbit", "mouse", "monkey", "horse", "tigress", "nian", "ufo", "neat", "yintiger")):
        return "pets"
    if lower.startswith("role"):
        return "characters/mixed_packages"
    if lower[0:1].isdigit() or lower.startswith("stage"):
        return "stages"
    if "interface" in lower or lower in {
        "aboutus.swf", "cartoon.swf", "gamehelp.swf", "shaizi.swf", "union.swf"
    }:
        return "ui"
    if "map" in lower or "background" in lower:
        return "environments"
    if "magicweapon" in lower:
        return "magic_weapons"
    return "shared"


def scan_swf_literals(scripts_dir: Path) -> set[str]:
    found: set[str] = set()
    if not scripts_dir.exists():
        return found
    pattern = re.compile(r"[A-Za-z0-9_./-]+\.swf", re.IGNORECASE)
    for path in scripts_dir.rglob("*.as"):
        text = path.read_text(encoding="utf-8", errors="ignore")
        for value in pattern.findall(text):
            value = value.lstrip("/")
            if value.lower().startswith("_assets/"):
                continue
            found.add(value)
    return found


def stage3_alias(stage: str) -> str:
    aliases = {
        "0": "0v1150", "3": "3v690", "4": "4v1070", "9": "9v680",
        "10": "10v960", "11": "11_1", "12": "12_2", "13": "13v760",
        "14": "14v960", "15": "15v680", "17": "17_2", "21": "21v680",
        "22": "22v680", "23": "23v1110", "24": "24v1180", "25": "25v1310",
        "40": "40v680", "41": "41v3651", "42": "42v680", "44": "44_2",
        "47": "47v680", "48": "48v680", "50": "50v8201", "53": "53v800",
        "54": "54v840", "55": "55v880", "56": "56v960",
    }
    return aliases.get(stage, stage)


def parse_zmxiyou3_equipment(items: dict[tuple[str, str], Resource]) -> None:
    equipment = TOOLS / "core_scripts" / "zmxiyou3_full" / "scripts" / "my" / "AllEquipment.as"
    role_ids: dict[tuple[int, str], set[int]] = {}
    if equipment.exists():
        text = equipment.read_text(encoding="utf-8", errors="ignore")
        pattern = re.compile(
            r'new\s+MyEquipObj\(\s*(\d+)\s*,.*?\s*,\s*"(zbfj|zbwq)"\s*,\s*"(悟空|唐僧|八戒|沙僧)"',
            re.DOTALL,
        )
        chinese_roles = {"悟空": 1, "唐僧": 2, "八戒": 3, "沙僧": 4}
        for match in pattern.finditer(text):
            show_id = int(match.group(1))
            kind = "body" if match.group(2) == "zbfj" else "weapon"
            role = chinese_roles[match.group(3)]
            role_ids.setdefault((role, kind), set()).add(show_id)

    # Default and unequipped states can be selected even when no item uses them.
    for role in range(1, 5):
        role_ids.setdefault((role, "body"), set()).update({0, 1})
        role_ids.setdefault((role, "weapon"), set()).update({0, 1})

    for (role, kind), ids in role_ids.items():
        role_name = ROLE_NAMES[role]
        for show_id in sorted(ids):
            if kind == "weapon":
                filename = f"ROLE{role}_EQUIP_{show_id}.swf"
                category = f"characters/{role_name}/weapon/{show_id}"
                add_resource(items, "zmxiyou3", filename, category, "AllEquipment weapon showid")
            elif role == 4:
                for style in ("SHOVEL", "ARROW"):
                    filename = f"ROLE4_{style}_{show_id}.swf"
                    category = f"characters/{role_name}/body_{style.lower()}/{show_id}"
                    add_resource(items, "zmxiyou3", filename, category, "AllEquipment body showid")
            else:
                filename = f"ROLE{role}_{show_id}.swf"
                category = f"characters/{role_name}/body/{show_id}"
                add_resource(items, "zmxiyou3", filename, category, "AllEquipment body showid")


def build_manifest() -> list[Resource]:
    items: dict[tuple[str, str], Resource] = {}

    game1 = [
        "Role_v7.swf", "Monster_v1.swf", "Monster2_v4.swf", "Monster3_v3.swf",
        "OtherMat_v9.swf", "backpack_v2.swf", "Music.swf",
    ]
    for name in game1:
        category = "characters/mixed_packages" if name.startswith("Role") else category_for_name(name)
        add_resource(items, "zmxiyou1", name, category, "Aloader.urls")

    game2 = [
        "OtherMat_v10.swf", "Role_v6.swf", "Music.swf", "Common_v7.swf", "backpack_v5.swf",
        "1_v6.swf", "2.swf", "3.swf", "4.swf", "5_v7.swf", "6.swf", "7.swf",
        "8.swf", "9.swf", "10.swf", "11.swf", "Pig9.swf",
    ]
    for name in game2:
        category = "characters/mixed_packages" if name.startswith("Role") else category_for_name(name)
        add_resource(items, "zmxiyou2", name, category, "Aloader/MainGame")

    game3_core = [
        "MagicWeaponv1240.swf", "Commonv3720.swf", "petEIconv1450.swf",
        "EIconv3420.swf", "GameMapv3870.swf", "OtherMatv3570.swf",
        "GameBackGroundv3870.swf", "stageInfov1620.swf", "stageCommonv1270.swf",
        "Role1v690.swf", "Role2v3550.swf", "Role3v690.swf", "Role4v3550.swf",
        "petsUniversalv690.swf",
    ]
    for name in game3_core:
        add_resource(items, "zmxiyou3", name, category_for_name(name), "Aloader/Config")

    config_pets = [
        "nianv1040", "monkeyv690", "horsev680", "tigressv680", "turtlev680",
        "phoenixv680", "dragonv680", "rabbitv680", "ufov680", "mousev790",
        "neat", "roomhorse", "yintiger",
    ]
    for name in config_pets:
        add_resource(items, "zmxiyou3", name, "pets", "Config.getPetSwfNameByPetName")

    scripts = TOOLS / "core_scripts" / "zmxiyou3_full" / "scripts"
    for name in scan_swf_literals(scripts):
        if name.lower() in {"mainresourcev3730.swf", "font.swf"}:
            # These are embedded in the main SWF; local main extraction covers them.
            continue
        add_resource(items, "zmxiyou3", name, category_for_name(name), "ActionScript literal")

    # Every stage id is passed to Decrypt.loadByName. Invalid candidates are
    # retained in the report but rejected by HTTP/SWF validation.
    for stage in range(0, 66):
        name = stage3_alias(str(stage))
        add_resource(items, "zmxiyou3", name, f"stages/{stage}", "MainGame stage id")

    # Optional monster packages are loaded based on events, tasks, and stages.
    monster_pattern = re.compile(r"\bMonster\d+\b")
    if scripts.exists():
        monster_names: set[str] = set()
        for path in scripts.rglob("*.as"):
            monster_names.update(monster_pattern.findall(path.read_text(encoding="utf-8", errors="ignore")))
        for name in monster_names:
            add_resource(items, "zmxiyou3", name, "monsters", "ActionScript monster reference")

    parse_zmxiyou3_equipment(items)

    manifest = sorted(items.values(), key=lambda item: (item.game, natural_key(item.category), natural_key(item.name)))
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(
        json.dumps([asdict(item) | {"url": item.url} for item in manifest], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return manifest


def load_manifest() -> list[Resource]:
    if not MANIFEST_PATH.exists():
        return build_manifest()
    data = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    return [Resource(row["game"], row["name"], row["category"], row["origin"]) for row in data]


def rotate_header(data: bytes, pivot: int, head: int) -> bytes:
    return data[pivot:head] + data[:pivot] + data[head:]


def decode_swf(game: str, data: bytes) -> bytes | None:
    if data[:3] in SWF_MAGIC:
        return data
    candidates = [rotate_header(data, 100, 110)] if game == "zmxiyou1" else [rotate_header(data, 300, 325)]
    for candidate in candidates:
        if candidate[:3] in SWF_MAGIC:
            return candidate
    return None


def safe_local_name(name: str) -> Path:
    parts = [part for part in Path(name).parts if part not in {".", ".."}]
    return Path(*parts)


def download_one(resource: Resource, timeout: int = 45) -> dict[str, object]:
    relative = safe_local_name(resource.name)
    raw_path = ROOT / "sources" / "raw" / resource.game / relative
    decoded_path = ROOT / "sources" / "decoded" / resource.game / relative
    raw_path.parent.mkdir(parents=True, exist_ok=True)
    decoded_path.parent.mkdir(parents=True, exist_ok=True)

    if decoded_path.exists():
        existing = decoded_path.read_bytes()
        if existing[:3] in SWF_MAGIC:
            return {
                "game": resource.game, "name": resource.name, "status": "cached",
                "bytes": raw_path.stat().st_size if raw_path.exists() else len(existing),
                "decoded_sha256": hashlib.sha256(existing).hexdigest(),
                "category": resource.category,
            }

    request = urllib.request.Request(resource.url, headers={"User-Agent": "Mozilla/5.0 CodexResourceHarvester/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = response.read()
    except urllib.error.HTTPError as exc:
        return {"game": resource.game, "name": resource.name, "status": f"http_{exc.code}", "category": resource.category}
    except Exception as exc:  # noqa: BLE001 - report all network failures
        return {"game": resource.game, "name": resource.name, "status": "network_error", "error": str(exc), "category": resource.category}

    raw_hash = hashlib.sha256(data).hexdigest()
    if raw_hash in KNOWN_ERROR_HASHES:
        return {"game": resource.game, "name": resource.name, "status": "error_movie", "bytes": len(data), "category": resource.category}

    decoded = decode_swf(resource.game, data)
    if decoded is None:
        return {
            "game": resource.game, "name": resource.name, "status": "invalid_swf",
            "bytes": len(data), "raw_sha256": raw_hash, "category": resource.category,
        }

    part_path = raw_path.with_suffix(raw_path.suffix + ".part")
    part_path.write_bytes(data)
    part_path.replace(raw_path)
    decoded_path.write_bytes(decoded)
    return {
        "game": resource.game, "name": resource.name, "status": "downloaded",
        "bytes": len(data), "raw_sha256": raw_hash,
        "decoded_sha256": hashlib.sha256(decoded).hexdigest(), "category": resource.category,
    }


def download_all(resources: list[Resource], workers: int) -> list[dict[str, object]]:
    results: list[dict[str, object]] = []
    total = len(resources)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        future_map = {executor.submit(download_one, item): item for item in resources}
        for index, future in enumerate(concurrent.futures.as_completed(future_map), start=1):
            result = future.result()
            results.append(result)
            status = result["status"]
            if status in {"downloaded", "cached"} or index % 25 == 0:
                print(f"[{index}/{total}] {result['game']} {result['name']} -> {status}", flush=True)

    results.sort(key=lambda row: (str(row["game"]), natural_key(str(row["name"]))))
    REPORT_PATH.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    return results


def local_main_resources() -> list[tuple[Resource, Path]]:
    local: list[tuple[Resource, Path]] = []
    mains = [
        # The first two embedded game files are already valid CWS files.  Keep
        # them in raw/ because no byte rotation is required, but still export
        # them as the canonical main-game containers.
        ("zmxiyou1", "main_game.swf", "shared/main", ROOT / "sources/raw/zmxiyou1_game.swf"),
        ("zmxiyou2", "main_game.swf", "shared/main", ROOT / "sources/raw/zmxiyou2_game.swf"),
        ("zmxiyou3", "main_game.swf", "shared/main", ROOT / "sources/decoded/zmxiyou3_game.swf"),
        # Preserve assets embedded in the 4399 page-level loader as well as
        # the game itself.  zmxiyou3_loader.swf is only the 23 KiB error
        # animation returned by the obsolete sda host and is intentionally
        # not included here.
        ("zmxiyou1", "portal_loader.swf", "shared/portal_loader", ROOT / "sources/raw/zmxiyou1.swf"),
        ("zmxiyou2", "portal_loader.swf", "shared/portal_loader", ROOT / "sources/raw/zmxiyou2.swf"),
        ("zmxiyou3", "portal_loader.swf", "shared/portal_loader", ROOT / "sources/raw/zmxiyou3.swf"),
    ]
    for game, name, category, path in mains:
        if path.exists():
            local.append((Resource(game, name, category, "embedded main SWF"), path))
    return local


def export_path(resource: Resource) -> Path:
    stem = Path(resource.name).stem
    return ROOT / "assets" / "extracted" / "full" / resource.game / Path(resource.category) / stem


def extract_one(resource: Resource, swf_path: Path, force: bool = False) -> dict[str, object]:
    source_hash = hashlib.sha256(swf_path.read_bytes()).hexdigest()
    marker_name = hashlib.sha1(f"{resource.game}|{resource.name}".encode()).hexdigest() + ".json"
    marker = STATE_DIR / marker_name
    if marker.exists() and not force:
        previous = json.loads(marker.read_text(encoding="utf-8"))
        if previous.get("source_sha256") == source_hash and Path(previous.get("output", "")).exists():
            return {"game": resource.game, "name": resource.name, "status": "export_cached", "output": previous["output"]}

    out = export_path(resource)
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["_JAVA_OPTIONS"] = "-Xmx2048m"
    command = [
        str(FFDEC), "-config", "parallelSpeedUp=false", "-onerror", "ignore",
        "-timeout", "90", "-exportTimeout", "900", "-export", "all",
        str(out), str(swf_path),
    ]
    started = time.time()
    completed = subprocess.run(command, env=env, capture_output=True, text=True, errors="replace", timeout=1200)
    status = "exported" if completed.returncode == 0 else "export_failed"
    result = {
        "game": resource.game, "name": resource.name, "status": status,
        "output": str(out), "seconds": round(time.time() - started, 2),
        "returncode": completed.returncode,
    }
    if completed.returncode == 0:
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text(
            json.dumps({"source_sha256": source_hash, "output": str(out), "resource": asdict(resource)}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    else:
        log = TOOLS / "harvest_logs" / f"{resource.game}_{Path(resource.name).stem}.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(completed.stdout + "\n" + completed.stderr, encoding="utf-8", errors="replace")
        result["log"] = str(log)
    return result


def extract_all(resources: list[Resource], force: bool = False, workers: int = 3) -> list[dict[str, object]]:
    jobs: list[tuple[Resource, Path]] = local_main_resources()
    for resource in resources:
        path = ROOT / "sources" / "decoded" / resource.game / safe_local_name(resource.name)
        if path.exists() and path.read_bytes()[:3] in SWF_MAGIC:
            jobs.append((resource, path))

    results: list[dict[str, object]] = []

    def run_job(job: tuple[Resource, Path]) -> dict[str, object]:
        resource, path = job
        try:
            return extract_one(resource, path, force=force)
        except subprocess.TimeoutExpired:
            return {"game": resource.game, "name": resource.name, "status": "export_timeout"}

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, workers)) as executor:
        future_map = {executor.submit(run_job, job): job[0] for job in jobs}
        for index, future in enumerate(concurrent.futures.as_completed(future_map), start=1):
            resource = future_map[future]
            try:
                result = future.result()
            except Exception as exc:  # noqa: BLE001 - preserve the remaining export queue
                result = {
                    "game": resource.game, "name": resource.name,
                    "status": "export_exception", "error": str(exc),
                }
            results.append(result)
            print(
                f"[{index}/{len(jobs)}] {resource.game}/{resource.name} -> {result['status']}",
                flush=True,
            )
    export_report = TOOLS / "full_export_report.json"
    export_report.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    return results


def summary(resources: list[Resource]) -> None:
    report = json.loads(REPORT_PATH.read_text(encoding="utf-8")) if REPORT_PATH.exists() else []
    exports_path = TOOLS / "full_export_report.json"
    exports = json.loads(exports_path.read_text(encoding="utf-8")) if exports_path.exists() else []
    status_counts: dict[str, int] = {}
    for row in report:
        status_counts[row["status"]] = status_counts.get(row["status"], 0) + 1
    export_counts: dict[str, int] = {}
    for row in exports:
        export_counts[row["status"]] = export_counts.get(row["status"], 0) + 1
    print(json.dumps({
        "manifest_candidates": len(resources),
        "download_status": status_counts,
        "export_status": export_counts,
    }, ensure_ascii=False, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("discover", "download", "extract", "all", "summary"))
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    if args.command == "discover":
        resources = build_manifest()
        print(f"manifest: {len(resources)} candidates -> {MANIFEST_PATH}")
        return

    resources = load_manifest()
    if args.command in {"download", "all"}:
        download_all(resources, max(1, args.workers))
    if args.command in {"extract", "all"}:
        extract_all(resources, force=args.force, workers=max(1, args.workers))
    summary(resources)


if __name__ == "__main__":
    main()
