"""ZMX2 monster pipeline: flatten, pack, trim, extract, generate Godot profiles."""
import json, os, re, shutil
from pathlib import Path
from PIL import Image
Image.MAX_IMAGE_PIXELS = None

BASE = Path("D:/DreamMake/assets/extracted/classified/zmxiyou2/怪物")
OUT = Path("D:/DreamMake/assets/selected/zmxiyou2/monsters")
SCRIPTS = Path("D:/DreamMake/scripts")

# Import our existing tools
import sys; sys.path.insert(0, str(SCRIPTS))
from sprite_packer import pack_sprites

# === Step 1: Flatten directory structure ===
print("=== Step 1: Flatten ===")
for monster_dir in sorted(BASE.iterdir()):
    if not monster_dir.is_dir(): continue
    mname = monster_dir.name

    for category_dir in sorted(monster_dir.iterdir()):
        if not category_dir.is_dir(): continue
        catname = category_dir.name  # "本体" or "特效与组成元件"

        for pkg_dir in sorted(category_dir.iterdir()):
            if not pkg_dir.is_dir(): continue

            for sym_dir in sorted(pkg_dir.iterdir()):
                if not sym_dir.is_dir(): continue
                sprites_dir = sym_dir / "sprites"
                if not sprites_dir.is_dir(): continue

                # Determine target name
                if catname == "本体":
                    target_name = "body"
                elif catname == "特效与组成元件":
                    target_name = sym_dir.name.split("_", 1)[-1] if "_" in sym_dir.name else sym_dir.name
                else:
                    target_name = catname

                # Rename PNGs from 1.png to frame_001.png
                pngs = sorted(sprites_dir.glob("*.png"), key=lambda f: int(re.search(r'(\d+)', f.stem).group(1)))
                target_dir = monster_dir / target_name
                target_dir.mkdir(exist_ok=True)

                for i, png in enumerate(pngs):
                    new_name = f"frame_{i+1:03d}.png"
                    shutil.move(str(png), str(target_dir / new_name))

                print(f"  {mname}/{target_name}: {len(pngs)} frames")

    # Clean up empty directories
    for category_dir in sorted(monster_dir.iterdir()):
        if category_dir.is_dir() and category_dir.name in ("本体", "特效与组成元件"):
            shutil.rmtree(category_dir)

# === Step 2: Pack sprite sheets ===
print("\n=== Step 2: Pack sprite sheets ===")
for monster_dir in sorted(BASE.iterdir()):
    if not monster_dir.is_dir(): continue
    for action_dir in sorted(monster_dir.iterdir()):
        if not action_dir.is_dir(): continue
        pngs = sorted(action_dir.glob("frame_*.png"))
        if len(pngs) < 2: continue
        try:
            pack_sprites(str(action_dir))
        except Exception as e:
            print(f"  FAIL {monster_dir.name}/{action_dir.name}: {e}")

# === Step 3: Trim transparency ===
print("\n=== Step 3: Trim ===")
for sf in sorted(BASE.rglob("sprite.png")):
    d = sf.parent
    jf = d / "sprite.json"
    if not jf.exists(): continue
    with open(jf) as f:
        meta = json.load(f)
    fw = meta["meta"]["frameSize"]["w"]
    fh = meta["meta"]["frameSize"]["h"]
    cols = meta["meta"]["columns"]
    count = meta["meta"]["frameCount"]

    img = Image.open(sf)
    max_w, max_h = 0, 0
    bboxes = []

    for fi in range(count):
        row, col = divmod(fi, cols)
        x, y = col * fw, row * fh
        frame = img.crop((x, y, x + fw, y + fh))
        alpha = frame.getchannel("A")
        bbox = alpha.getbbox()
        if bbox is None: bbox = (0, 0, 1, 1)
        bboxes.append(bbox)
        max_w = max(max_w, bbox[2] - bbox[0])
        max_h = max(max_h, bbox[3] - bbox[1])

    max_w += 2; max_h += 2
    saving = 1 - (max_w * max_h) / (fw * fh)
    if saving < 0.05: continue

    import math
    new_cols = math.ceil(math.sqrt(count))
    new_rows = math.ceil(count / new_cols)
    new_sheet = Image.new("RGBA", (new_cols * max_w, new_rows * max_h), (0, 0, 0, 0))
    new_frames = {}

    for fi in range(count):
        b = bboxes[fi]
        row, col = divmod(fi, cols)
        ox, oy = col * fw, row * fh
        frame = img.crop((ox, oy, ox + fw, oy + fh))
        content = frame.crop(b)
        nr, nc = divmod(fi, new_cols)
        nx, ny = nc * max_w, nr * max_h
        new_sheet.paste(content, (nx + 1, ny + 1), content)

        orig_frames = sorted(meta["frames"].keys())
        name = orig_frames[fi] if fi < len(orig_frames) else f"frame_{fi+1:03d}"
        new_frames[name] = {
            "x": nx, "y": ny, "w": max_w, "h": max_h,
            "ox": b[0], "oy": b[1], "cw": b[2] - b[0], "ch": b[3] - b[1],
        }

    sf.unlink()
    new_sheet.save(sf, optimize=True)
    new_meta = {
        "frames": new_frames,
        "meta": {
            "image": "sprite.png",
            "size": {"w": new_cols * max_w, "h": new_rows * max_h},
            "frameSize": {"w": max_w, "h": max_h},
            "columns": new_cols, "rows": new_rows,
            "frameCount": count, "trimmed": True,
            "originalFrameSize": {"w": fw, "h": fh},
        },
    }
    with open(jf, "w", encoding="utf-8") as f:
        json.dump(new_meta, f, ensure_ascii=False, indent=2)
    print(f"  {d.relative_to(BASE)}: {fw}x{fh} -> {max_w}x{max_h} ({saving:.1%} saved)")

# === Step 4: Extract frames for Godot import ===
print("\n=== Step 4: Extract frames ===")
extracted_count = 0
monster_summary = {}

for monster_dir in sorted(BASE.iterdir()):
    if not monster_dir.is_dir(): continue
    mname = monster_dir.name
    safe_name = re.sub(r'[^\w]', '_', mname).lower()
    if safe_name[0].isdigit(): safe_name = 'm' + safe_name

    actions = {}
    for action_dir in sorted(monster_dir.iterdir()):
        if not action_dir.is_dir(): continue
        sf = action_dir / "sprite.png"
        jf = action_dir / "sprite.json"
        if not sf.exists() or not jf.exists(): continue

        with open(jf) as f:
            meta = json.load(f)
        img = Image.open(sf)
        fw = meta["meta"]["frameSize"]["w"]
        fh = meta["meta"]["frameSize"]["h"]
        cols = meta["meta"]["columns"]
        count = meta["meta"]["frameCount"]

        out_dir = OUT / safe_name / action_dir.name
        out_dir.mkdir(parents=True, exist_ok=True)

        frames = sorted(meta["frames"].keys())
        for fi, fname in enumerate(frames):
            row, col = divmod(fi, cols)
            x, y = col * fw, row * fh
            frame = img.crop((x, y, x + fw, y + fh))
            frame.save(out_dir / f"frame_{fi+1:03d}.png")

        actions[action_dir.name] = {"frame_count": count}
        extracted_count += count

    monster_summary[mname] = {"sname": safe_name, "actions": actions}

with open("D:/DreamMake/.tools/zmxiyou2_monster_configs.json", "w", encoding="utf-8") as f:
    json.dump(monster_summary, f, ensure_ascii=False, indent=2)

print(f"Extracted {extracted_count} frames for {len(monster_summary)} monsters")
