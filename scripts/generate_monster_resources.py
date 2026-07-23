"""Generate Godot .tres resources for all ZMX1 monsters"""
import json, os
from pathlib import Path

with open("D:/DreamMake/.tools/monster_configs.json", encoding="utf-8") as f:
    monsters = json.load(f)

RES_DIR = Path("D:/DreamMake/resources/enemies/animations")
DEF_DIR = Path("D:/DreamMake/resources/enemies")
RES_DIR.mkdir(parents=True, exist_ok=True)

# Monster display names
MONSTER_NAMES = {
    "M01": "小怪1号", "M02": "小怪2号", "M03": "大猩猩", "M04": "彌猴王",
    "M06": "禺狨王", "M07": "小怪7号", "M08": "蝙蝠",
    "M09": "彭魔王", "M10": "鲛魔王", "M11": "狮驼王",
    "M13": "骷髅兵", "M14": "远程骷髅", "M15": "小怪15号",
    "M16": "小怪16号", "M17": "龟丞相", "M18": "Boss18",
    "M19": "鲨魔王", "M20": "小怪20号",
    "M21": "蝙蝠洞", "M22": "牛魔王", "M23": "牛魔王(二)",
    "M24": "牛魔王(最终)", "M25": "小怪25号",
    "M26": "龙王", "M27": "宝箱",
}

profiles_made = 0
definitions_made = 0

for mc in monsters:
    sname = mc["sname"]
    mid = mc["mid"]
    display = MONSTER_NAMES.get(mid, mc["mid"])
    actions = mc["actions"]

    if not actions:
        print(f"  SKIP {mid}: no actions")
        continue

    # === Generate Profile ===
    profile_path = RES_DIR / f"zmxiyou1_{sname}_profile.tres"
    action_blocks = []
    for a in actions:
        key = a["key"]
        atlas_root = f"res://assets/selected/zmxiyou1/monsters/{sname}/{key}"
        block = f'''&"{key}": {{
"display_name": "{a["display_name"]}",
"fps": 24.0,
"frame_count": {a["frame_count"]},
"loop": {'true' if a["loop"] else 'false'},
"next_animation": &"{a["next"]}",
"sprite_sheet": "{atlas_root}/sprite.png",
"sprite_sheet_json": "{atlas_root}/sprite.json",
"source_events": Array[Dictionary]([]),
"sprite_offset": Vector2(0, 0)
}}'''
        action_blocks.append(block)

    actions_str = ",\n".join(action_blocks)

    profile_content = f"""[gd_resource type="Resource" script_class="EnemyAnimationProfile" format=3]

[ext_resource type="Script" path="res://src/enemies/enemy_animation_profile.gd" id="1_profile"]

[resource]
script = ExtResource("1_profile")
default_animation = &"idle"
source_monster_id = &"{mid}"
source_package = &"Monster_v1"
source_event_audit = "res://sources/manifests/zmxiyou1_monster_events.json"
actions = {{
{actions_str}
}}
"""
    with open(profile_path, "w", encoding="utf-8") as f:
        f.write(profile_content)
    profiles_made += 1

    # === Generate Definition ===
    def_path = DEF_DIR / f"zmxiyou1_{sname}.tres"
    hp = mc["hp"]
    atk = min(200, max(10, hp // 10))
    is_boss = mc["is_boss"]

    def_content = f"""[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=5 format=3]

[ext_resource type="Script" path="res://src/enemies/enemy_definition.gd" id="1_enemy"]
[ext_resource type="Script" path="res://src/attributes/actor_property.gd" id="2_property"]
[ext_resource type="Resource" path="res://resources/enemies/animations/zmxiyou1_{sname}_profile.tres" id="3_animation"]

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
enemy_id = &"zmxiyou1_{sname}"
display_name = "{display}"
source_game = 1
property_template = SubResource("ActorProperty_{sname}")
animation_profile = ExtResource("3_animation")
visual_scale = Vector2(1.5, 1.5)
visual_offset = Vector2(0, 0)
collision_size = Vector2(60, 90)
is_boss = {'true' if is_boss else 'false'}
"""
    with open(def_path, "w", encoding="utf-8") as f:
        f.write(def_content)
    definitions_made += 1

print(f"Generated {profiles_made} profiles, {definitions_made} definitions")
