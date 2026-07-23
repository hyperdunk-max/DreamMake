"""Batch: extract all monster sprite frames and generate Godot profiles"""
import json, os, re
from pathlib import Path
from PIL import Image
Image.MAX_IMAGE_PIXELS = None

BASE = Path("D:/DreamMake/assets/extracted/classified/zmxiyou1/怪物")
OUT = Path("D:/DreamMake/assets/selected/zmxiyou1/monsters")

# Load event data for HP and attack info
with open("D:/DreamMake/sources/manifests/zmxiyou1_monster_events.json", encoding="utf-8") as f:
    events = json.load(f)

# Map monster dir to event data
dir_to_id = {
    "M01": "M01", "M02": "M02", "M03_大猩猩": "M03", "M04_彌猴王": "M04",
    "M06_禺狨王": "M06", "M07": "M07", "M08": "M08",
    "M09_彭魔王": "M09", "M10_鲛魔王": "M10", "M11_狮驼王": "M11",
    "M13": "M13", "M14": "M14", "M15": "M15", "M16": "M16",
    "M17_龟丞相": "M17", "M18": "M18", "M19_鲨魔王": "M19",
    "M20": "M20", "M21_蝙蝠洞": "M21", "M22_牛魔王": "M22",
    "M23_牛魔王": "M23", "M24_牛魔王": "M24", "M25": "M25",
    "M26_龙王": "M26", "M27_宝箱": "M27",
}

# Action name mapping (Chinese folder -> English key)
ACTION_KEY_MAP = {
    "待机": "idle", "移动": "move", "受伤": "hurt", "死亡": "death",
    "攻击1": "attack1", "攻击2": "attack2", "攻击3": "attack3",
    "攻击4": "attack4", "攻击5": "attack5",
    "受伤恢复": "recover", "变蛋": "egg", "重燃": "reburn", "飞行": "fly",
    "待机1": "idle1", "待机2": "idle2",
    "移动1": "move1", "移动2": "move2",
    "攻击1_阶段1": "attack1_1", "攻击1_阶段2": "attack1_2",
    "攻击2_阶段1": "attack2_1", "攻击2_阶段2": "attack2_2",
    "攻击3_阶段1": "attack3_1", "攻击3_階段2": "attack3_2",
    "共享动作时间轴": "shared",
}

# Display names
ACTION_DISPLAY = {
    "idle": "待机", "move": "移动", "hurt": "受伤", "death": "死亡",
    "attack1": "攻击1", "attack2": "攻击2", "attack3": "攻击3",
    "attack4": "攻击4", "attack5": "攻击5",
    "recover": "受伤恢复", "egg": "变蛋", "reburn": "重燃", "fly": "飞行",
}

LOOP_ACTIONS = {"idle", "move", "fly", "idle1", "idle2", "move1", "move2", "shared"}
NEXT_DEFAULTS = {
    "attack1": "idle", "attack2": "idle", "attack3": "idle",
    "attack4": "idle", "attack5": "idle",
    "hurt": "idle", "recover": "move", "egg": "reburn",
    "attack1_1": "attack1_2", "attack2_1": "attack2_2",
}

total_extracted = 0
monster_configs = []

for monster_dir in sorted(BASE.iterdir()):
    if not monster_dir.is_dir() or not monster_dir.name.startswith("M"):
        continue

    mname = monster_dir.name
    mid = dir_to_id.get(mname, mname)
    event_info = events["monsters"].get(mid, {})

    # Get HP
    hp = 100
    for ev in event_info.get("behavior_evidence", []):
        m = re.search(r'sHp\s*=\s*(\d+)', ev.get("code", ""))
        if m:
            hp = int(m.group(1))
            break

    # Get attacks
    attacks = {}
    for action, profiles in event_info.get("attack_profiles", {}).items():
        for p in profiles:
            f = p.get("fields", {})
            attacks[action] = f

    is_boss = hp >= 1500 or len(event_info.get("attack_profiles", {})) > 1

    # Extract frames and collect action info
    actions_list = []
    safe_name = re.sub(r'[_一-鿿]+', '', mname).replace('牛魔王', 'bull').replace('大猩猩', 'gorilla').replace('禺狨王', 'monkey').replace('彭魔王', 'peng').replace('鲛魔王', 'jiao').replace('狮驼王', 'lion').replace('龟丞相', 'turtle').replace('鲨魔王', 'shark').replace('龙王', 'dragon').replace('寶箱', 'chest').replace('蝙蝠洞', 'bat')

    # Actually use pinyin-like names
    safe_map = {
        "M01": "m01", "M02": "m02", "M03_大猩猩": "m03_gorilla", "M04_彌猴王": "m04_monkey_king",
        "M06_禺狨王": "m06_yu_rong", "M07": "m07", "M08": "m08",
        "M09_彭魔王": "m09_peng", "M10_鲛魔王": "m10_jiao", "M11_狮驼王": "m11_lion",
        "M13": "m13", "M14": "m14", "M15": "m15", "M16": "m16",
        "M17_龟丞相": "m17_turtle", "M18": "m18", "M19_鲨魔王": "m19_shark",
        "M20": "m20", "M21_蝙蝠洞": "m21_bat", "M22_牛魔王": "m22_bull",
        "M23_牛魔王": "m23_bull", "M24_牛魔王": "m24_bull_final",
        "M25": "m25", "M26_龙王": "m26_dragon", "M27_宝箱": "m27_chest",
    }
    sname = safe_map.get(mname, mname.lower().replace('_', '_'))
    out_dir = OUT / sname

    # Find all actions for this monster
    for action_dir in sorted(monster_dir.iterdir()):
        if not action_dir.is_dir():
            continue
        if action_dir.name in ("特效", "parts", "共享动作时间轴", "组成元件"):
            continue

        action_key = ACTION_KEY_MAP.get(action_dir.name, None)
        if action_key is None:
            continue

        # Find the sprite sheet
        sf = action_dir / "sprite.png"
        jf = action_dir / "sprite.json"

        # Check for multi-element actions
        if not sf.exists():
            subs = [d for d in action_dir.iterdir() if d.is_dir()]
            if subs:
                # Use the biggest element (most frames = main composite)
                best_sub = None
                best_count = 0
                for sub in subs:
                    sub_jf = sub / "sprite.json"
                    if sub_jf.exists():
                        with open(sub_jf) as f:
                            sm = json.load(f)
                        if sm["meta"]["frameCount"] > best_count:
                            best_count = sm["meta"]["frameCount"]
                            best_sub = sub
                if best_sub:
                    sf = best_sub / "sprite.png"
                    jf = best_sub / "sprite.json"

        if not sf.exists() or not jf.exists():
            continue

        # Extract frames
        with open(jf) as f:
            meta = json.load(f)
        img = Image.open(sf)
        fw = meta["meta"]["frameSize"]["w"]
        fh = meta["meta"]["frameSize"]["h"]
        cols = meta["meta"]["columns"]
        count = meta["meta"]["frameCount"]

        action_out = out_dir / action_key
        action_out.mkdir(parents=True, exist_ok=True)

        frames = sorted(meta["frames"].keys())
        for fi, fname in enumerate(frames):
            row, col = divmod(fi, cols)
            x, y = col * fw, row * fh
            frame = img.crop((x, y, x + fw, y + fh))
            frame.save(action_out / f"frame_{fi+1:03d}.png")

        is_loop = action_key in LOOP_ACTIONS
        next_anim = NEXT_DEFAULTS.get(action_key, action_key if is_loop else "idle")
        display_name = ACTION_DISPLAY.get(action_key, action_dir.name)

        actions_list.append({
            "key": action_key,
            "display_name": display_name,
            "frame_count": count,
            "loop": is_loop,
            "next": next_anim,
        })
        total_extracted += count

    monster_configs.append({
        "dir": mname,
        "sname": sname,
        "mid": mid,
        "hp": hp,
        "is_boss": is_boss,
        "display_name": mname.replace("M", "").replace("_", "").split("M")[0] if "M" in mname else mname,
        "actions": actions_list,
        "attacks": attacks,
    })

print(f"Total frames extracted: {total_extracted}")
print(f"Monsters processed: {len(monster_configs)}")

# Save monster config for Godot profile generation
with open("D:/DreamMake/.tools/monster_configs.json", "w", encoding="utf-8") as f:
    json.dump(monster_configs, f, ensure_ascii=False, indent=2)
print("Config saved to .tools/monster_configs.json")
