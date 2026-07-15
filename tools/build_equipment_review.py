"""Render fixed-anchor equipment review sheets from selected source atlases.

Run with the bundled Pillow runtime:
    .tools/python-portable/python.exe tools/build_equipment_review.py

The production atlases are never modified.  Preview frames retain their full
source cell and use one shared scale per role so transparent padding and foot
anchors remain visible during review.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SELECTED = ROOT / "assets" / "selected" / "zmxiyou3"
ROLE_SPECS = {
    "wukong": {"display": "悟空", "cell": (200, 200)},
    "tangseng": {"display": "唐僧", "cell": (200, 200)},
    "bajie": {"display": "八戒", "cell": (300, 200)},
    "shaseng": {"display": "沙僧", "cell": (200, 200)},
}
SHASENG_ARROW_WEAPONS = {4, 7, 8, 9}


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/msyhbd.ttc" if bold else "C:/Windows/Fonts/msyh.ttc"),
        Path("C:/Windows/Fonts/simhei.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


TITLE_FONT = font(28, True)
LABEL_FONT = font(16, True)
NOTE_FONT = font(14)


def checker(size: tuple[int, int], tile: int = 12) -> Image.Image:
    image = Image.new("RGBA", size, "#f7f8fa")
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], tile):
        for x in range(0, size[0], tile):
            if (x // tile + y // tile) % 2:
                draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill="#e4e8eb")
    return image


def source_frame(path: Path, cell: tuple[int, int]) -> Image.Image:
    with Image.open(path) as atlas:
        return atlas.convert("RGBA").crop((0, 0, cell[0], cell[1]))


def compose(body_path: Path, weapon_path: Path | None, cell: tuple[int, int]) -> Image.Image:
    frame = source_frame(body_path, cell)
    if weapon_path is not None:
        frame.alpha_composite(source_frame(weapon_path, cell))
    return frame


def render_sheet(
    role_key: str,
    title: str,
    entries: list[tuple[str, Image.Image]],
    output: Path,
) -> None:
    columns = min(4, max(1, len(entries)))
    rows = math.ceil(len(entries) / columns)
    panel_w, panel_h = 230, 250
    header_h = 82
    canvas = Image.new("RGBA", (columns * panel_w + 32, rows * panel_h + header_h + 24), "#edf1f3")
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 14), title, font=TITLE_FONT, fill="#172026")
    draw.text((20, 51), "完整源图格 · 统一缩放 · 底部中心锚点预览", font=NOTE_FONT, fill="#607078")

    cell_w, cell_h = ROLE_SPECS[role_key]["cell"]
    shared_scale = min(190 / cell_w, 190 / cell_h)
    preview_size = (round(cell_w * shared_scale), round(cell_h * shared_scale))
    for index, (label, frame) in enumerate(entries):
        column = index % columns
        row = index // columns
        x = 16 + column * panel_w
        y = header_h + row * panel_h
        panel = checker((panel_w - 12, panel_h - 12))
        canvas.alpha_composite(panel, (x + 6, y + 6))
        preview = frame.resize(preview_size, Image.Resampling.LANCZOS)
        px = x + (panel_w - preview.width) // 2
        py = y + 8 + 194 - preview.height
        canvas.alpha_composite(preview, (px, py))
        draw.rectangle((x + 6, y + 204, x + panel_w - 6, y + panel_h - 6), fill="#ffffff")
        draw.text((x + 14, y + 216), label, font=LABEL_FONT, fill="#27343b")

    output.parent.mkdir(parents=True, exist_ok=True)
    (output.parent / ".gdignore").write_text(
        "# Review sheets are for manual asset selection, not runtime import.\n",
        encoding="utf-8",
        newline="\n",
    )
    canvas.convert("RGB").save(output, quality=95)


def resolve(root: Path, catalog_path: str) -> Path:
    return root / Path(catalog_path).relative_to("assets/selected/zmxiyou3")


def build_role(role_key: str) -> list[str]:
    role_root = SELECTED / role_key
    catalog = json.loads((role_root / "equipment_catalog.json").read_text(encoding="utf-8"))
    cell = ROLE_SPECS[role_key]["cell"]
    body_entries: list[tuple[str, Image.Image]] = []
    body_paths: dict[tuple[str, int], Path] = {}
    for category, entries in catalog["categories"].items():
        if not category.startswith("body"):
            continue
        mode = category.split("/", 1)[1] if "/" in category else "default"
        for entry in entries:
            showid = int(entry["showid"])
            path = resolve(SELECTED, entry["file"])
            body_paths[(mode, showid)] = path
            body_entries.append((f"{mode} · showid {showid}", compose(path, None, cell)))

    weapon_entries: list[tuple[str, Image.Image]] = []
    default_mode = "shovel" if role_key == "shaseng" else "default"
    for entry in catalog["categories"]["weapon"]:
        showid = int(entry["showid"])
        mode = "arrow" if role_key == "shaseng" and showid in SHASENG_ARROW_WEAPONS else default_mode
        body_path = body_paths[(mode, 1)]
        weapon_path = resolve(SELECTED, entry["file"])
        weapon_entries.append((f"{mode} · showid {showid}", compose(body_path, weapon_path, cell)))

    body_output = role_root / "review" / "equipment_body_variants.png"
    weapon_output = role_root / "review" / "equipment_weapon_variants.png"
    display = ROLE_SPECS[role_key]["display"]
    render_sheet(role_key, f"{display} · 衣服候选", body_entries, body_output)
    render_sheet(role_key, f"{display} · 武器候选", weapon_entries, weapon_output)
    return [
        body_output.relative_to(ROOT).as_posix(),
        weapon_output.relative_to(ROOT).as_posix(),
    ]


def main() -> None:
    generated: dict[str, list[str]] = {}
    for role_key in ROLE_SPECS:
        generated[role_key] = build_role(role_key)
    manifest = {
        "policy": "Preview only; production atlases remain byte-identical to extracted PNG files",
        "generated": generated,
    }
    output = SELECTED / "equipment_review_manifest.json"
    output.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
