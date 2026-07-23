"""Split ZMX2 body sprite sheets into per-action sheets using frame labels."""
import json, re, math
from pathlib import Path
from PIL import Image
Image.MAX_IMAGE_PIXELS = None

with open("D:/DreamMake/.tools/zmxiyou2_monster_frame_labels.json", encoding="utf-8") as f:
    monster_labels = json.load(f)

BASE = Path("D:/DreamMake/assets/extracted/classified/zmxiyou2/怪物")
SELECTED = Path("D:/DreamMake/assets/selected/zmxiyou2/monsters")

# Fix truncated labels (first char was lost due to SWF FrameLabel encoding)
FIX_LABELS = {
    'ait': 'wait', 'alk': 'walk', 'urt': 'hurt', 'ead': 'dead',
    'it1': 'hit1', 'it2': 'hit2', 'it3': 'hit3', 'it4': 'hit4', 'it5': 'hit5',
    'it6': 'hit6', 'it7': 'hit7', 'it8': 'hit8',
    'it1-1': 'hit1-1', 'it2-1': 'hit2-1', 'it2-2': 'hit2-2', 'it2-3': 'hit2-3', 'it2-4': 'hit2-4',
    'it3-1': 'hit3-1', 'it3-2': 'hit3-2',
    'eburn': 'reburn', 'enshen': 'shenfen', 'all': 'fall', 'un': 'run', 'ixed': 'fixed',
    'eady': 'ready',
}

# Action name mapping for Godot profiles
ACTION_MAP = {
    'walk': 'walk', 'wait': 'idle', 'hurt': 'hurt', 'dead': 'death',
    'hit1': 'attack1', 'hit2': 'attack2', 'hit3': 'attack3',
    'hit4': 'attack4', 'hit5': 'attack5',
    'hit1-1': 'attack1a', 'hit2-1': 'attack2a', 'hit2-2': 'attack2b',
    'hit3-1': 'attack3a', 'hit3-2': 'attack3b',
    'reburn': 'reburn', 'fall': 'fall', 'run': 'run', 'ready': 'ready',
    'shenfen': 'shenfen', 'fixed': 'fixed',
    'hit6': 'attack6', 'hit7': 'attack7', 'hit8': 'attack8',
    'hit2-3': 'attack2c', 'hit2-4': 'attack2d',
}

updated = 0

for mname in sorted(BASE.iterdir()):
    if not mname.is_dir(): continue
    mname = mname.name
    if mname not in monster_labels: continue

    info = monster_labels[mname]
    body_dir = BASE / mname / "body"
    if not body_dir.is_dir(): continue

    sf = body_dir / "sprite.png"
    jf = body_dir / "sprite.json"
    if not sf.exists() or not jf.exists(): continue

    with open(jf) as f:
        meta = json.load(f)

    img = Image.open(sf)
    fw = meta["meta"]["frameSize"]["w"]
    fh = meta["meta"]["frameSize"]["h"]
    cols = meta["meta"]["columns"]

    actions = info["actions"]
    new_actions = {}

    for raw_label, (start, end) in actions.items():
        label = FIX_LABELS.get(raw_label, raw_label)
        gd_action = ACTION_MAP.get(label, label)
        frame_count = end - start + 1

        # Extract frames
        frames = []
        for fi in range(start, end + 1):
            if fi >= meta["meta"]["frameCount"]: break
            row, col = divmod(fi, cols)
            x, y = col * fw, row * fh
            frame = img.crop((x, y, x + fw, y + fh))
            frames.append(frame)

        if len(frames) < 2:
            # Single frame - skip as action (might be a transition frame)
            continue

        # Pack into new sprite sheet
        new_cols = math.ceil(math.sqrt(len(frames)))
        new_rows = math.ceil(len(frames) / new_cols)
        new_sheet = Image.new("RGBA", (new_cols * fw, new_rows * fh), (0, 0, 0, 0))
        new_meta_frames = {}

        for i, frame in enumerate(frames):
            nr, nc = divmod(i, new_cols)
            nx, ny = nc * fw, nr * fh
            new_sheet.paste(frame, (nx, ny), frame if frame.mode == "RGBA" else None)
            new_meta_frames[f"{gd_action}_{i+1:03d}"] = {"x": nx, "y": ny, "w": fw, "h": fh}

        # Save
        action_dir = BASE / mname / gd_action
        action_dir.mkdir(exist_ok=True)
        new_sheet.save(action_dir / "sprite.png", optimize=True)

        new_meta = {
            "frames": new_meta_frames,
            "meta": {
                "image": "sprite.png",
                "size": {"w": new_cols * fw, "h": new_rows * fh},
                "frameSize": {"w": fw, "h": fh},
                "columns": new_cols, "rows": new_rows,
                "frameCount": len(frames),
            }
        }
        with open(action_dir / "sprite.json", "w", encoding="utf-8") as f:
            json.dump(new_meta, f, ensure_ascii=False, indent=2)

        new_actions[gd_action] = len(frames)

    # Remove old body directory (replaced by per-action dirs)
    import shutil
    shutil.rmtree(body_dir)

    # Update monster config
    monster_labels[mname]["new_actions"] = new_actions
    updated += 1
    print(f"{mname}: {list(new_actions.keys())} ({sum(new_actions.values())} frames)")

print(f"\nUpdated {updated} monsters with per-action sprite sheets")
with open("D:/DreamMake/.tools/zmxiyou2_monster_frame_labels.json", "w", encoding="utf-8") as f:
    json.dump(monster_labels, f, ensure_ascii=False, indent=2)
