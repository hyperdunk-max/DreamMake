#!/usr/bin/env python3
"""Build review sheets for Dream Westward Journey 3 Wukong body images."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "assets/extracted/full/zmxiyou3/characters/wukong/body"
WEAPON_SOURCE_ROOT = ROOT / "assets/extracted/full/zmxiyou3/characters/wukong/weapon"
SELECTED_ROOT = ROOT / "assets/selected/zmxiyou3/wukong"
OUTPUT_ROOT = SELECTED_ROOT / "review"
CANDIDATE_ROOT = SELECTED_ROOT / "body_candidates"
WEAPON_CANDIDATE_ROOT = SELECTED_ROOT / "weapon_candidates"

VARIANTS = {
    "0": "默认 / 无防具",
    "1": "普通的行者服",
    "2": "枯叶衫",
    "3": "翼火甲",
    "4": "紫金轻甲",
    "9": "虬龙甲",
    "11": "斗战",
}

WEAPON_VARIANTS = {
    "0": "默认武器",
    "1": "普通的行者棍",
}

ACTIONS = [
    ("wait", "待机", 0, 0),
    ("wait2", "待机变化", 1, 0),
    ("walk", "行走", 2, 0),
    ("run", "跑步", 3, 0),
    ("jump_skill", "跳跃 / 技能", 4, 0),
    ("jump_air", "空中", 5, 0),
    ("hit1_2", "普攻 1 / 2", 6, 0),
    ("hit3", "普攻 3", 7, 0),
    ("hit4", "普攻 4", 8, 0),
    ("hit5", "普攻 5", 9, 0),
    ("hit6", "普攻 6", 10, 0),
    ("hit8", "技能 8", 11, 0),
    ("skill_hurt", "技能 / 受击", 12, 2),
    ("hit14", "技能 14", 13, 0),
]

OVERVIEW_ACTIONS = ("wait", "run", "jump_skill", "hit1_2", "hit5", "skill_hurt")
ATLAS_VARIANTS = ("0", "1", "2", "3", "4", "9")
CELL_SIZE = 200


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/msyhbd.ttc" if bold else "C:/Windows/Fonts/msyh.ttc"),
        Path("C:/Windows/Fonts/simhei.ttf"),
    ]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


FONT_TITLE = load_font(30, bold=True)
FONT_HEADING = load_font(19, bold=True)
FONT_BODY = load_font(16)
FONT_SMALL = load_font(13)


def checker(size: tuple[int, int], tile: int = 12) -> Image.Image:
    image = Image.new("RGBA", size, "#f8fafb")
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], tile):
        for x in range(0, size[0], tile):
            if (x // tile + y // tile) % 2:
                draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill="#e6eaed")
    return image


def atlas_path(showid: str) -> Path:
    return SOURCE_ROOT / showid / f"ROLE1_{showid}" / "images" / f"1_ROLE1_{showid}.png"


def load_atlas_frame(showid: str, row: int, column: int) -> Image.Image:
    with Image.open(atlas_path(showid)) as atlas:
        atlas = atlas.convert("RGBA")
        return atlas.crop(
            (
                column * CELL_SIZE,
                row * CELL_SIZE,
                (column + 1) * CELL_SIZE,
                (row + 1) * CELL_SIZE,
            )
        )


def load_showid11_frame(row: int) -> Image.Image:
    path = (
        SOURCE_ROOT
        / "11/ROLE1_11/sprites/DefineSprite_130_ROLE1_11"
        / f"{row + 1}.png"
    )
    with Image.open(path) as image:
        return image.convert("RGBA")


def load_frame(showid: str, row: int, column: int = 0) -> Image.Image:
    if showid == "11":
        return load_showid11_frame(row)
    return load_atlas_frame(showid, row, column)


def place_frame(canvas: Image.Image, frame: Image.Image, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    area_w = x1 - x0
    area_h = y1 - y0
    alpha_box = frame.getbbox()
    if not alpha_box:
        return
    subject = frame.crop(alpha_box)
    scale = min(area_w / subject.width, area_h / subject.height, 1.65)
    size = (max(1, round(subject.width * scale)), max(1, round(subject.height * scale)))
    subject = subject.resize(size, Image.Resampling.LANCZOS)
    x = x0 + (area_w - subject.width) // 2
    y = y1 - subject.height - 8
    canvas.alpha_composite(subject, (x, y))


def build_overview() -> Path:
    margin = 24
    label_w = 145
    cell_w = 205
    cell_h = 225
    header_h = 125
    variants = list(VARIANTS)
    actions = [action for action in ACTIONS if action[0] in OVERVIEW_ACTIONS]
    width = margin * 2 + label_w + cell_w * len(variants)
    height = margin * 2 + header_h + cell_h * len(actions)
    canvas = Image.new("RGBA", (width, height), "#eef1f3")
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, 18), "造梦西游 3 · 悟空身体外观筛选", font=FONT_TITLE, fill="#172026")
    draw.text((margin, 58), "原版 200×200 动作格 · showid 5 远端已失效", font=FONT_BODY, fill="#5c6870")

    top = margin + 72
    for index, showid in enumerate(variants):
        x = margin + label_w + index * cell_w
        draw.rounded_rectangle((x + 4, top, x + cell_w - 6, top + 48), radius=5, fill="#ffffff")
        draw.text((x + 14, top + 7), f"showid {showid}", font=FONT_HEADING, fill="#1c272d")
        draw.text((x + 14, top + 30), VARIANTS[showid], font=FONT_SMALL, fill="#66737b")

    grid_top = margin + header_h
    for row_index, (_, label, source_row, source_col) in enumerate(actions):
        y = grid_top + row_index * cell_h
        draw.text((margin + 4, y + 92), label, font=FONT_HEADING, fill="#344149")
        draw.text((margin + 4, y + 118), f"row {source_row}", font=FONT_SMALL, fill="#7b878e")
        for column_index, showid in enumerate(variants):
            x = margin + label_w + column_index * cell_w
            panel = checker((cell_w - 10, cell_h - 10))
            canvas.alpha_composite(panel, (x + 4, y + 4))
            frame = load_frame(showid, source_row, source_col)
            place_frame(canvas, frame, (x + 12, y + 12, x + cell_w - 14, y + cell_h - 14))

    output = OUTPUT_ROOT / "body_variant_overview.png"
    canvas.convert("RGB").save(output, quality=95)
    return output


def build_atlas_detail(showid: str) -> Path:
    margin = 20
    label_w = 150
    cell_w = 112
    cell_h = 112
    header_h = 88
    columns = 6
    width = margin * 2 + label_w + columns * cell_w
    height = margin * 2 + header_h + len(ACTIONS) * cell_h
    canvas = Image.new("RGBA", (width, height), "#eef1f3")
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, 14), f"悟空 showid {showid} · {VARIANTS[showid]}", font=FONT_TITLE, fill="#172026")
    draw.text((margin, 52), "原图坐标按 row / column 标记", font=FONT_BODY, fill="#5c6870")

    top = margin + header_h
    for row_index, (_, label, source_row, _) in enumerate(ACTIONS):
        y = top + row_index * cell_h
        draw.text((margin + 2, y + 32), label, font=FONT_BODY, fill="#344149")
        draw.text((margin + 2, y + 56), f"row {source_row}", font=FONT_SMALL, fill="#7b878e")
        for column in range(columns):
            x = margin + label_w + column * cell_w
            panel = checker((cell_w - 6, cell_h - 6), tile=8)
            canvas.alpha_composite(panel, (x + 3, y + 3))
            frame = load_atlas_frame(showid, source_row, column)
            frame = frame.resize((100, 100), Image.Resampling.LANCZOS)
            canvas.alpha_composite(frame, (x + 6, y + 6))
            draw.text((x + 8, y + 88), f"c{column}", font=FONT_SMALL, fill="#344149")

    output = OUTPUT_ROOT / f"body_showid_{showid}_actions.png"
    canvas.convert("RGB").save(output, quality=95)
    return output


def build_showid11_detail() -> Path:
    margin = 24
    cell_w = 250
    cell_h = 220
    columns = 4
    rows = (len(ACTIONS) + columns - 1) // columns
    width = margin * 2 + columns * cell_w
    height = 110 + rows * cell_h + margin
    canvas = Image.new("RGBA", (width, height), "#eef1f3")
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, 18), "悟空 showid 11 · 斗战", font=FONT_TITLE, fill="#172026")
    draw.text((margin, 58), "MovieClip 外层 14 个动作代表帧", font=FONT_BODY, fill="#5c6870")

    for index, (_, label, source_row, _) in enumerate(ACTIONS):
        column = index % columns
        row = index // columns
        x = margin + column * cell_w
        y = 94 + row * cell_h
        panel = checker((cell_w - 12, cell_h - 12))
        canvas.alpha_composite(panel, (x + 6, y + 6))
        frame = load_showid11_frame(source_row)
        place_frame(canvas, frame, (x + 14, y + 14, x + cell_w - 14, y + cell_h - 42))
        draw.rectangle((x + 6, y + cell_h - 48, x + cell_w - 6, y + cell_h - 6), fill="#ffffff")
        draw.text((x + 16, y + cell_h - 42), label, font=FONT_BODY, fill="#27343b")
        draw.text((x + 16, y + cell_h - 22), f"outer frame {source_row + 1}", font=FONT_SMALL, fill="#77838a")

    output = OUTPUT_ROOT / "body_showid_11_actions.png"
    canvas.convert("RGB").save(output, quality=95)
    return output


def export_atlas_candidate(showid: str) -> dict[str, object]:
    output = CANDIDATE_ROOT / f"showid_{showid}"
    output.mkdir(parents=True, exist_ok=True)
    source_atlas = atlas_path(showid)
    shutil.copy2(source_atlas, output / "source_atlas.png")

    exported_frames: list[dict[str, object]] = []
    for key, label, row, _ in ACTIONS:
        action_dir = output / "frames" / key
        for column in range(6):
            frame = load_atlas_frame(showid, row, column)
            if frame.getchannel("A").getbbox() is None:
                continue
            action_dir.mkdir(parents=True, exist_ok=True)
            frame_path = action_dir / f"frame_{column:02d}.png"
            frame.save(frame_path)
            exported_frames.append(
                {
                    "action": key,
                    "action_label": label,
                    "row": row,
                    "column": column,
                    "file": str(frame_path.relative_to(ROOT)).replace("\\", "/"),
                }
            )

    candidate = {
        "showid": showid,
        "name": VARIANTS[showid],
        "format": "bitmap_atlas_6x14",
        "frame_size": [200, 200],
        "source_atlas": str(source_atlas.relative_to(ROOT)).replace("\\", "/"),
        "selected_atlas": str((output / "source_atlas.png").relative_to(ROOT)).replace("\\", "/"),
        "frames": exported_frames,
    }
    (output / "manifest.json").write_text(
        json.dumps(candidate, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return candidate


def export_showid11_candidate() -> dict[str, object]:
    output = CANDIDATE_ROOT / "showid_11"
    source_sprites = SOURCE_ROOT / "11/ROLE1_11/sprites"
    selected_sprites = output / "source_sprites"
    selected_sprites.mkdir(parents=True, exist_ok=True)

    sprite_groups: list[dict[str, object]] = []
    for source_group in sorted(source_sprites.iterdir()):
        if not source_group.is_dir():
            continue
        selected_group = selected_sprites / source_group.name
        selected_group.mkdir(parents=True, exist_ok=True)
        files = []
        for source_png in sorted(source_group.glob("*.png"), key=lambda path: int(path.stem)):
            selected_png = selected_group / source_png.name
            shutil.copy2(source_png, selected_png)
            files.append(str(selected_png.relative_to(ROOT)).replace("\\", "/"))
        if files:
            sprite_groups.append({"group": source_group.name, "files": files})

    candidate = {
        "showid": "11",
        "name": VARIANTS["11"],
        "format": "movieclip_sprite_groups",
        "outer_action_group": "DefineSprite_130_ROLE1_11",
        "source": str(source_sprites.relative_to(ROOT)).replace("\\", "/"),
        "sprite_groups": sprite_groups,
        "png_count": sum(len(group["files"]) for group in sprite_groups),
    }
    (output / "manifest.json").write_text(
        json.dumps(candidate, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return candidate


def export_weapon_candidate(showid: str) -> dict[str, object]:
    source_atlas = next(
        (WEAPON_SOURCE_ROOT / showid).glob(f"ROLE1_EQUIP_{showid}/images/*.png")
    )
    output = WEAPON_CANDIDATE_ROOT / f"showid_{showid}"
    output.mkdir(parents=True, exist_ok=True)
    selected_atlas = output / "source_atlas.png"
    shutil.copy2(source_atlas, selected_atlas)
    candidate = {
        "showid": showid,
        "name": WEAPON_VARIANTS[showid],
        "format": "bitmap_atlas_6x14",
        "frame_size": [200, 200],
        "source_atlas": str(source_atlas.relative_to(ROOT)).replace("\\", "/"),
        "selected_atlas": str(selected_atlas.relative_to(ROOT)).replace("\\", "/"),
    }
    (output / "manifest.json").write_text(
        json.dumps(candidate, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return candidate


def main() -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    generated = [build_overview()]
    generated.extend(build_atlas_detail(showid) for showid in ATLAS_VARIANTS)
    generated.append(build_showid11_detail())
    candidates = [export_atlas_candidate(showid) for showid in ATLAS_VARIANTS]
    candidates.append(export_showid11_candidate())
    weapon_candidates = [export_weapon_candidate(showid) for showid in WEAPON_VARIANTS]

    manifest = {
        "character": "wukong",
        "game": "zmxiyou3",
        "source": str(SOURCE_ROOT.relative_to(ROOT)).replace("\\", "/"),
        "variants": VARIANTS,
        "unavailable_showids": ["5"],
        "actions": [
            {"key": key, "label": label, "row": row, "representative_column": column}
            for key, label, row, column in ACTIONS
        ],
        "candidates": candidates,
        "weapon_candidates": weapon_candidates,
        "generated": [str(path.relative_to(ROOT)).replace("\\", "/") for path in generated],
    }
    (OUTPUT_ROOT / "review_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
