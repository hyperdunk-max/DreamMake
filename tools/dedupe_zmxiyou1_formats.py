#!/usr/bin/env python3
"""Audit and remove visually equivalent SVG/JPG copies from the ZMX1 browse tree.

Candidates must be connected through the original SWF definition graph.  The
script then normalizes both visuals and accepts only low-error matches.  PNG is
kept as the runtime-friendly browse format; the complete extraction remains
untouched.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.sax
from collections import Counter, defaultdict, deque
from datetime import datetime
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, ImageChops, ImageStat


ROOT = Path(__file__).resolve().parents[1]
TOOLS_ROOT = ROOT / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

from refine_zmxiyou1_classification import ReferenceGraphHandler, XML_FILES  # noqa: E402


CLASSIFIED_ROOT = ROOT / "assets" / "extracted" / "classified" / "zmxiyou1"
MANIFEST_PATH = ROOT / "sources" / "manifests" / "zmxiyou1_compact_classification.json"
AUDIT_PATH = ROOT / "sources" / "manifests" / "zmxiyou1_format_duplicates.json"
REPORT_PATHS = (
    ROOT / "sources" / "ZMXIYOU1_COMPACT_CLASSIFICATION.md",
    CLASSIFIED_ROOT / "README.md",
)
SVG_CACHE_ROOT = ROOT / ".tools" / "zmxiyou1_format_audit" / "svg"
SVG_CACHE_INDEX = ROOT / ".tools" / "zmxiyou1_format_audit" / "svg_index.tsv"
NORMALIZED_SIZE = 48
REMOVABLE_EXTENSIONS = {".svg", ".jpg", ".jpeg"}
PIXEL_EXACT_THRESHOLD = 0.0001


class TimelineReferenceGraphHandler(ReferenceGraphHandler):
    """Retain aggregate edges plus the active direct children for each frame."""

    def __init__(self) -> None:
        super().__init__()
        self.sprite_stack: list[dict[str, Any]] = []
        self.button_stack: list[dict[str, Any]] = []
        self.sprite_frames: dict[int, list[set[int]]] = {}
        self.button_states: dict[int, dict[str, set[int]]] = {}

    def startElement(self, name: str, attrs: Any) -> None:  # noqa: N802 - SAX API
        super().startElement(name, attrs)
        if name != "item":
            return
        item_type = attrs.get("type", "")
        if item_type == "DefineSpriteTag":
            self.sprite_stack.append(
                {
                    "depth": self.depth,
                    "id": int(attrs["spriteId"]),
                    "display": {},
                    "frames": [],
                }
            )
            return
        if item_type == "DefineButton2Tag":
            self.button_stack.append(
                {
                    "depth": self.depth,
                    "id": int(attrs["buttonId"]),
                    "states": defaultdict(set),
                }
            )
            return

        if self.sprite_stack and self.depth == int(self.sprite_stack[-1]["depth"]) + 1:
            timeline = self.sprite_stack[-1]
            depth_value = attrs.get("depth", "")
            if item_type in {"PlaceObjectTag", "PlaceObject2Tag", "PlaceObject3Tag", "PlaceObject4Tag"}:
                character_id = attrs.get("characterId", "")
                if depth_value.isdigit() and character_id.isdigit():
                    timeline["display"][int(depth_value)] = int(character_id)
            elif item_type in {"RemoveObjectTag", "RemoveObject2Tag"} and depth_value.isdigit():
                timeline["display"].pop(int(depth_value), None)
            elif item_type == "ShowFrameTag":
                timeline["frames"].append(set(timeline["display"].values()))

        if self.button_stack and item_type == "BUTTONRECORD":
            button = self.button_stack[-1]
            character_id = attrs.get("characterId", "")
            if character_id.isdigit():
                for attribute, state in (
                    ("buttonStateUp", "up"),
                    ("buttonStateOver", "over"),
                    ("buttonStateDown", "down"),
                    ("buttonStateHitTest", "hitTest"),
                ):
                    if attrs.get(attribute, "false") == "true":
                        button["states"][state].add(int(character_id))

    def endElement(self, name: str) -> None:  # noqa: N802 - SAX API
        if name == "item":
            if self.sprite_stack and int(self.sprite_stack[-1]["depth"]) == self.depth:
                timeline = self.sprite_stack.pop()
                self.sprite_frames[int(timeline["id"])] = list(timeline["frames"])
            if self.button_stack and int(self.button_stack[-1]["depth"]) == self.depth:
                button = self.button_stack.pop()
                self.button_states[int(button["id"])] = {
                    state: set(character_ids)
                    for state, character_ids in button["states"].items()
                }
        super().endElement(name)


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_svg_cache_index() -> dict[str, Path]:
    if not SVG_CACHE_INDEX.exists():
        raise FileNotFoundError(
            "Missing SVG render cache. Run tools/render_zmxiyou1_svg_cache.gd with Godot first."
        )
    result: dict[str, Path] = {}
    for line in SVG_CACHE_INDEX.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        source, cache_name = line.split("\t", 1)
        result[source] = SVG_CACHE_ROOT / cache_name
    return result


def classified_relative(destination: str) -> str:
    return (ROOT / destination).relative_to(CLASSIFIED_ROOT).as_posix()


def normalize_raster(path: Path) -> Image.Image:
    with Image.open(path) as opened:
        image = opened.convert("RGBA")
    alpha = image.getchannel("A")
    box = alpha.getbbox()
    canvas = Image.new("RGBA", (NORMALIZED_SIZE, NORMALIZED_SIZE), (0, 0, 0, 0))
    if box is None:
        return canvas
    image = image.crop(box)
    image.thumbnail((NORMALIZED_SIZE, NORMALIZED_SIZE), Image.Resampling.LANCZOS)
    offset = ((NORMALIZED_SIZE - image.width) // 2, (NORMALIZED_SIZE - image.height) // 2)
    canvas.alpha_composite(image, offset)
    return canvas


def flattened(image: Image.Image, color: tuple[int, int, int, int]) -> Image.Image:
    background = Image.new("RGBA", image.size, color)
    background.alpha_composite(image)
    return background.convert("RGB")


def visual_error(left: Image.Image, right: Image.Image) -> float:
    errors: list[float] = []
    for background in ((0, 0, 0, 255), (255, 255, 255, 255)):
        difference = ImageChops.difference(flattened(left, background), flattened(right, background))
        errors.extend(ImageStat.Stat(difference).mean)
    return sum(errors) / (len(errors) * 255.0)


def walk_related(
    start: int,
    adjacency: dict[int, set[int]],
    maximum_depth: int,
) -> dict[int, int]:
    distances = {start: 0}
    pending: deque[int] = deque([start])
    while pending:
        current = pending.popleft()
        distance = distances[current]
        if distance >= maximum_depth:
            continue
        for related in adjacency.get(current, set()):
            if related in distances:
                continue
            distances[related] = distance + 1
            pending.append(related)
    distances.pop(start, None)
    return distances


def build_graphs() -> tuple[
    dict[str, dict[int, set[int]]],
    dict[str, dict[int, set[int]]],
    dict[str, TimelineReferenceGraphHandler],
]:
    children_by_package: dict[str, dict[int, set[int]]] = {}
    parents_by_package: dict[str, dict[int, set[int]]] = {}
    handlers: dict[str, TimelineReferenceGraphHandler] = {}
    for package, xml_path in XML_FILES.items():
        if not xml_path.exists():
            raise FileNotFoundError(f"Missing SWF XML graph: {xml_path}")
        graph = TimelineReferenceGraphHandler()
        xml.sax.parse(str(xml_path), graph)
        handlers[package] = graph
        children = {owner: set(children) for owner, children in graph.edges.items()}
        parents: dict[int, set[int]] = defaultdict(set)
        for owner, children_ids in children.items():
            for child in children_ids:
                parents[child].add(owner)
        children_by_package[package] = children
        parents_by_package[package] = dict(parents)
    return children_by_package, parents_by_package, handlers


def active_direct_children(
    record: dict[str, Any],
    handlers: dict[str, TimelineReferenceGraphHandler],
) -> set[int] | None:
    package = str(record["package"])
    character_id = record.get("character_id")
    if character_id is None or package not in handlers:
        return None
    source = str(record["source"])
    name = Path(source).stem
    handler = handlers[package]
    if "/sprites/" in source.replace("\\", "/") and name.isdigit():
        frames = handler.sprite_frames.get(int(character_id), [])
        frame_index = int(name) - 1
        if 0 <= frame_index < len(frames):
            return set(frames[frame_index])
    if "/buttons/" in source.replace("\\", "/"):
        state_match = re.search(r"_(up|over|down|hitTest)$", name, flags=re.IGNORECASE)
        if state_match:
            state = state_match.group(1)
            state = "hitTest" if state.lower() == "hittest" else state.lower()
            return set(handler.button_states.get(int(character_id), {}).get(state, set()))
    return None


def acceptance_reason(
    removed: dict[str, Any],
    kept: dict[str, Any],
    relation: str,
    distance: int,
    score: float,
    threshold: float,
    children_by_package: dict[str, dict[int, set[int]]],
    handlers: dict[str, TimelineReferenceGraphHandler],
) -> str | None:
    removed_id = removed.get("character_id")
    kept_id = kept.get("character_id")
    if removed_id is None or kept_id is None:
        return None
    removed_id = int(removed_id)
    kept_id = int(kept_id)
    package = str(removed["package"])

    if relation == "ancestor" and distance == 1 and score <= threshold:
        visible = active_direct_children(kept, handlers)
        if visible == {removed_id}:
            return "single_component_rendered_frame"
    if relation == "descendant" and distance == 1 and score <= 0.001:
        if children_by_package.get(package, {}).get(removed_id, set()) == {kept_id}:
            return "single_bitmap_vector_wrapper"
    if score <= PIXEL_EXACT_THRESHOLD:
        return "normalized_pixels_exact"
    return None


def candidate_pngs(
    record: dict[str, Any],
    records_by_package_id: dict[tuple[str, int], list[dict[str, Any]]],
    children_by_package: dict[str, dict[int, set[int]]],
    parents_by_package: dict[str, dict[int, set[int]]],
    maximum_depth: int,
) -> list[tuple[dict[str, Any], str, int]]:
    package = str(record["package"])
    character_id = record.get("character_id")
    if character_id is None:
        return []
    character_id = int(character_id)
    related: dict[int, tuple[str, int]] = {}
    for relation, adjacency in (
        ("ancestor", parents_by_package.get(package, {})),
        ("descendant", children_by_package.get(package, {})),
    ):
        for related_id, distance in walk_related(character_id, adjacency, maximum_depth).items():
            previous = related.get(related_id)
            if previous is None or distance < previous[1]:
                related[related_id] = (relation, distance)

    result: list[tuple[dict[str, Any], str, int]] = []
    seen: set[str] = set()
    for related_id, (relation, distance) in related.items():
        for candidate in records_by_package_id.get((package, related_id), []):
            if Path(str(candidate["source"])).suffix.lower() != ".png":
                continue
            destination = str(candidate["destination"])
            if destination in seen:
                continue
            seen.add(destination)
            result.append((candidate, relation, distance))
    return result


def audit(threshold: float, maximum_depth: int) -> dict[str, Any]:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    records: list[dict[str, Any]] = list(manifest["files"])
    svg_cache = load_svg_cache_index()
    children_by_package, parents_by_package, handlers = build_graphs()

    records_by_package_id: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        character_id = record.get("character_id")
        if character_id is not None:
            records_by_package_id[(str(record["package"]), int(character_id))].append(record)

    @lru_cache(maxsize=None)
    def normalized(destination: str) -> Image.Image:
        path = ROOT / destination
        if path.suffix.lower() == ".svg":
            key = classified_relative(destination)
            path = svg_cache[key]
        return normalize_raster(path)

    duplicates: list[dict[str, Any]] = []
    near_matches: list[dict[str, Any]] = []
    candidate_pairs = 0
    candidates_with_related_png = 0
    extension_counts: Counter[str] = Counter()

    for record in records:
        extension = Path(str(record["source"])).suffix.lower()
        if extension not in REMOVABLE_EXTENSIONS:
            continue
        extension_counts[extension] += 1
        candidates = candidate_pngs(
            record,
            records_by_package_id,
            children_by_package,
            parents_by_package,
            maximum_depth,
        )
        if not candidates:
            continue
        candidates_with_related_png += 1
        source_image = normalized(str(record["destination"]))
        scored: list[tuple[float, int, str, dict[str, Any]]] = []
        for candidate, relation, distance in candidates:
            candidate_pairs += 1
            score = visual_error(source_image, normalized(str(candidate["destination"])))
            scored.append((score, distance, relation, candidate))
        scored.sort(key=lambda row: (row[0], row[1], str(row[3]["destination"])))
        accepted_row: dict[str, Any] | None = None
        for score, distance, relation, kept in scored:
            reason = acceptance_reason(
                record,
                kept,
                relation,
                distance,
                score,
                threshold,
                children_by_package,
                handlers,
            )
            if reason is None:
                continue
            accepted_row = {
                "removed_source": record["source"],
                "removed_destination": record["destination"],
                "removed_extension": extension,
                "removed_character_id": record.get("character_id"),
                "kept_source": kept["source"],
                "kept_destination": kept["destination"],
                "kept_character_id": kept.get("character_id"),
                "package": record["package"],
                "relation": relation,
                "graph_distance": distance,
                "visual_error": round(score, 8),
                "acceptance": reason,
                "category": record["category"],
            }
            break
        if accepted_row is not None:
            duplicates.append(accepted_row)
            continue

        score, distance, relation, kept = scored[0]
        if score <= max(0.08, threshold * 4.0):
            near_matches.append(
                {
                    "removed_source": record["source"],
                    "removed_destination": record["destination"],
                    "removed_extension": extension,
                    "removed_character_id": record.get("character_id"),
                    "kept_source": kept["source"],
                    "kept_destination": kept["destination"],
                    "kept_character_id": kept.get("character_id"),
                    "package": record["package"],
                    "relation": relation,
                    "graph_distance": distance,
                    "visual_error": round(score, 8),
                    "category": record["category"],
                }
            )

    duplicates.sort(key=lambda row: (row["removed_extension"], row["visual_error"], row["removed_destination"]))
    near_matches.sort(key=lambda row: (row["visual_error"], row["removed_destination"]))
    return {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "policy": (
            "Only remove SVG/JPG files that are connected to a retained PNG through the original "
            "SWF definition graph and are either the sole component of that exact rendered frame, a "
            "single-bitmap wrapper, or pixel-exact after normalization. PNG remains the browse/runtime "
            "format; full extraction is unchanged."
        ),
        "classified_root": relative(CLASSIFIED_ROOT),
        "compact_manifest": relative(MANIFEST_PATH),
        "threshold": threshold,
        "maximum_graph_depth": maximum_depth,
        "counts": {
            "classified_files_before": len(records),
            "removable_candidates": sum(extension_counts.values()),
            "candidates_by_extension": dict(sorted(extension_counts.items())),
            "candidates_with_related_png": candidates_with_related_png,
            "visual_pairs_compared": candidate_pairs,
            "duplicates": len(duplicates),
            "near_matches": len(near_matches),
        },
        "duplicates": duplicates,
        "near_matches": near_matches[:500],
    }


def update_reports(removed_count: int, remaining_count: int) -> None:
    section = (
        "## 多格式去重\n\n"
        f"依据 SWF 定义引用链与归一化视觉比对，删除 {removed_count:,} 个与保留 PNG 等价的 "
        "SVG/JPG 分类副本；分类目录现保留 "
        f"{remaining_count:,} 项素材。完整提取库未改动。\n\n"
        f"逐项证据见 `{relative(AUDIT_PATH)}`。\n"
    )
    for path in REPORT_PATHS:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        text = re.sub(r"\n## 多格式去重\n.*?(?=\n## |\Z)", "", text, flags=re.DOTALL)
        text = re.sub(r"共保留 [\d,]+ 项", f"共保留 {remaining_count:,} 项", text, count=1)
        path.write_text(text.rstrip() + "\n\n" + section, encoding="utf-8", newline="\n")


def remove_empty_directories(root: Path) -> int:
    removed = 0
    directories = sorted((path for path in root.rglob("*") if path.is_dir()), key=lambda path: len(path.parts), reverse=True)
    for directory in directories:
        try:
            directory.rmdir()
        except OSError:
            continue
        removed += 1
    return removed


def apply_audit(audit_data: dict[str, Any]) -> dict[str, Any]:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    duplicates: list[dict[str, Any]] = list(audit_data["duplicates"])
    removed_destinations = {str(row["removed_destination"]) for row in duplicates}
    classified_resolved = CLASSIFIED_ROOT.resolve()

    for destination in sorted(removed_destinations):
        path = (ROOT / destination).resolve()
        if not path.is_relative_to(classified_resolved):
            raise RuntimeError(f"Refusing to delete outside classified root: {path}")
        if not path.exists():
            raise FileNotFoundError(f"Classified duplicate is missing: {path}")
        path.unlink()

    retained_records = [
        record for record in manifest["files"] if str(record["destination"]) not in removed_destinations
    ]
    if len(manifest["files"]) - len(retained_records) != len(removed_destinations):
        raise RuntimeError("Manifest removal count does not match duplicate audit")

    category_counts = Counter(str(record["category"]) for record in retained_records)
    manifest["generated_at"] = datetime.now().astimezone().isoformat(timespec="seconds")
    manifest["files"] = retained_records
    manifest["format_duplicate_audit"] = relative(AUDIT_PATH)
    manifest["format_duplicate_files"] = duplicates
    manifest["counts_by_category"] = dict(sorted(category_counts.items()))
    MANIFEST_PATH.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
        newline="\n",
    )

    empty_directories = remove_empty_directories(CLASSIFIED_ROOT)
    update_reports(len(duplicates), len(retained_records))
    audit_data["applied"] = True
    audit_data["applied_at"] = datetime.now().astimezone().isoformat(timespec="seconds")
    audit_data["counts"]["classified_files_after"] = len(retained_records)
    audit_data["counts"]["empty_directories_removed"] = empty_directories
    return audit_data


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Delete accepted copies and update the compact manifest.")
    parser.add_argument("--threshold", type=float, default=0.015, help="Maximum normalized visual error.")
    parser.add_argument("--max-depth", type=int, default=6, help="Maximum SWF graph distance to a PNG candidate.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if AUDIT_PATH.exists():
        existing = json.loads(AUDIT_PATH.read_text(encoding="utf-8"))
        if existing.get("applied"):
            removed_present = [
                row["removed_destination"]
                for row in existing.get("duplicates", [])
                if (ROOT / row["removed_destination"]).exists()
            ]
            kept_missing = [
                row["kept_destination"]
                for row in existing.get("duplicates", [])
                if not (ROOT / row["kept_destination"]).is_file()
            ]
            if removed_present or kept_missing:
                raise RuntimeError(
                    "Applied format audit no longer matches the classified tree: "
                    f"removed_present={len(removed_present)}, kept_missing={len(kept_missing)}"
                )
            summary = dict(existing["counts"])
            summary["audit"] = relative(AUDIT_PATH)
            summary["applied"] = True
            summary["verified_existing_audit"] = True
            print(json.dumps(summary, ensure_ascii=False, indent=2))
            return
    audit_data = audit(args.threshold, args.max_depth)
    if args.apply:
        audit_data = apply_audit(audit_data)
    else:
        audit_data["applied"] = False
    AUDIT_PATH.write_text(
        json.dumps(audit_data, ensure_ascii=False, indent=2),
        encoding="utf-8",
        newline="\n",
    )
    summary = dict(audit_data["counts"])
    summary["audit"] = relative(AUDIT_PATH)
    summary["applied"] = audit_data["applied"]
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
