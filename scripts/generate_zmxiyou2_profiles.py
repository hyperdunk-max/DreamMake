"""Generate Godot profiles and definitions for ZMX2 monsters."""
import json, re, os
from pathlib import Path

with open("D:/DreamMake/.tools/zmxiyou2_monster_configs.json", encoding="utf-8") as f:
    monsters = json.load(f)

RES_DIR = Path("D:/DreamMake/resources/enemies/animations")
DEF_DIR = Path("D:/DreamMake/resources/enemies")

# HP estimates based on game progression
HP_TABLE = {"M30": 80, "M31": 100, "M32": 200, "M33": 300, "M34": 300, "M35": 150,
    "M36": 120, "M37": 140, "M38": 500, "M39": 600, "M40": 800, "M41": 180,
    "M42": 200, "M43": 250, "M44": 300, "M45": 1200, "M46": 1500, "M47": 1800,
    "M48": 2000, "M49": 2000, "M50": 400, "M51": 2500, "M52": 500, "M53": 100,
    "M54": 120, "M55": 150, "M56": 3000, "M57": 350, "M58": 5000, "M59": 3000,
    "M60": 3500, "M61": 4000, "M62": 200, "M63": 220, "M64": 4500, "M65": 300,
    "M66": 350, "M67": 5000, "M68": 400, "M69": 6000, "M72": 7000, "M73": 8000,
    "M74": 9000, "M75": 10000, "M76": 12000, "M77": 15000, "M78": 500,
    "M79": 20000, "M80": 25000, "M81": 50000, "M70": 450, "M71": 500}

DISPLAY_NAMES = {
    "M30": "小怪30", "M31": "小怪31", "M32_守夜人": "守夜人", "M33_黑无常": "黑无常",
    "M34_白无常": "白无常", "M35": "小怪35", "M36": "小怪36", "M37": "小怪37",
    "M38_秦广王": "秦广王", "M39_判官": "判官", "M40_阎罗王": "阎罗王",
    "M41": "小怪41", "M42": "小怪42", "M43": "小怪43", "M44": "小怪44",
    "M45_白骨精": "白骨精", "M46_红孩儿": "红孩儿", "M47_孟婆": "孟婆",
    "M48_悟空怪": "悟空怪", "M49_唐僧怪": "唐僧怪", "M50": "小怪50",
    "M51_转轮王": "转轮王", "M52_秦广王傀儡": "秦广王傀儡",
    "M53": "小怪53", "M54": "小怪54", "M55": "小怪55",
    "M56_夜叉": "夜叉", "M57": "小怪57", "M58_刑天": "刑天",
    "M59_转轮王": "转轮王(二)", "M60_转轮王": "转轮王(三)",
    "M61_楚江王": "楚江王", "M62": "小怪62", "M63": "小怪63",
    "M64_宋帝王": "宋帝王", "M65": "小怪65", "M66": "小怪66",
    "M67_五官王": "五官王", "M68": "小怪68", "M69_卞城王": "卞城王",
    "M72_都市王": "都市王", "M73_泰山王": "泰山王(一)",
    "M74_泰山王": "泰山王(二)", "M75_泰山王": "泰山王(三)",
    "M76_泰山王": "泰山王(四)", "M77_平等王": "平等王",
    "M78": "小怪78", "M79_劈天斧": "劈天斧", "M80_风神盾": "风神盾",
    "M81_战神刑天": "战神刑天", "M70": "小怪70", "M71": "小怪71",
}

for raw_name, info in sorted(monsters.items()):
    mname = raw_name
    sname = info["sname"]
    actions = info["actions"]

    if not actions: continue

    mid_match = re.match(r'(M\d+)', raw_name)
    mid = mid_match.group(1) if mid_match else raw_name
    display = DISPLAY_NAMES.get(raw_name, raw_name)
    hp = 100
    for key, val in HP_TABLE.items():
        if key in raw_name or key == mid:
            hp = val; break
    is_boss = hp >= 800

    # Generate profile
    action_blocks = []
    default_action = None
    for action_key, action_info in sorted(actions.items()):
        if action_key == "body":
            if default_action is None:
                default_action = "full"
            key = "full"
            display_key = "完整动画"
        else:
            if default_action is None:
                default_action = action_key
            key = re.sub(r'[^\w]', '_', action_key).lower()
            display_key = action_key

        count = action_info["frame_count"]
        path = f"res://assets/selected/zmxiyou2/monsters/{sname}/{action_key}/frame_%03d.png"

        block = f'''&"{key}": {{
"display_name": "{display_key}",
"fps": 24.0,
"frame_count": {count},
"loop": {"true" if default_action and key == default_action else "false"},
"next_animation": &"{default_action or key}",
"path_pattern": "{path}",
"source_events": Array[Dictionary]([]),
"sprite_offset": Vector2(0, 0)
}}'''
        action_blocks.append(block)

    if default_action is None: default_action = list(actions.keys())[0]

    profile_content = f"""[gd_resource type="Resource" script_class="EnemyAnimationProfile" format=3]

[ext_resource type="Script" path="res://src/enemies/enemy_animation_profile.gd" id="1_profile"]

[resource]
script = ExtResource("1_profile")
default_animation = &"{default_action}"
source_monster_id = &"Z2_{mid}"
source_package = &"ZMX2"
actions = {{
{','.join(action_blocks)}
}}
"""
    pf_path = RES_DIR / f"zmxiyou2_{sname}_profile.tres"
    with open(pf_path, "w", encoding="utf-8") as f:
        f.write(profile_content)

    # Generate definition
    atk = min(300, max(10, hp // 8))
    def_content = f"""[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=5 format=3]

[ext_resource type="Script" path="res://src/enemies/enemy_definition.gd" id="1_enemy"]
[ext_resource type="Script" path="res://src/attributes/actor_property.gd" id="2_property"]
[ext_resource type="Resource" path="res://resources/enemies/animations/zmxiyou2_{sname}_profile.tres" id="3_animation"]

[sub_resource type="Resource" id="ActorProperty_{sname}"]
script = ExtResource("2_property")
max_health = {hp}
max_mana = 0
attack = {atk}
defense = 10
crit_rate = 0.0
dodge_rate = 0.0

[resource]
script = ExtResource("1_enemy")
enemy_id = &"zmxiyou2_{sname}"
display_name = "[造2] {display}"
source_game = 2
property_template = SubResource("ActorProperty_{sname}")
animation_profile = ExtResource("3_animation")
visual_scale = Vector2(1.5, 1.5)
visual_offset = Vector2(0, 0)
collision_size = Vector2(60, 90)
is_boss = {'true' if is_boss else 'false'}
"""
    df_path = DEF_DIR / f"zmxiyou2_{sname}.tres"
    with open(df_path, "w", encoding="utf-8") as f:
        f.write(def_content)

print(f"Generated {len(monsters)} profile + definition pairs")
