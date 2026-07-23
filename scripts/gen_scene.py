"""Generate enemy_animation_preview.tscn with clean formatting."""
from pathlib import Path

defs = []
for pattern in ['zmxiyou1_*.tres', 'zmxiyou2_*.tres']:
    for f in sorted(Path('resources/enemies').glob(pattern)):
        content = f.read_text(encoding='utf-8')
        if 'animation_profile' in content:
            if f.name in ('zmxiyou1_bat_sandbag.tres', 'zmxiyou1_rat_boss.tres', 'zmxiyou1_bull_demon_king.tres'):
                continue
            defs.append(f)

# Build ext_resource entries
ext_resources = []
for i, d in enumerate(defs):
    rel = 'res://' + d.as_posix()
    ext_resources.append(f'[ext_resource type="Resource" path="{rel}" id="{i+2}_enemy"]')

# Build array entries
array_entries = ', '.join(f'ExtResource("{i+2}_enemy")' for i in range(len(defs)))

# Scene template with proper formatting (one property per line)
scene = f"""[gd_scene load_steps={3 + len(defs)} format=3]

[ext_resource type="Script" path="res://src/debug/enemy_animation_preview.gd" id="1_preview"]
{chr(10).join(ext_resources)}

[sub_resource type="StyleBoxFlat" id="StyleBox_panel"]
bg_color = Color(0.055, 0.071, 0.105, 0.97)
content_margin_left = 18.0
content_margin_top = 18.0
content_margin_right = 18.0
content_margin_bottom = 18.0
border_width_right = 1
border_color = Color(0.22, 0.29, 0.41, 1)

[node name="EnemyAnimationPreview" type="Node2D"]
script = ExtResource("1_preview")
monster_definitions = Array[ExtResource("2_enemy")]([{array_entries}])

[node name="PreviewWorld" type="Node2D" parent="."]
position = Vector2(660, 575)

[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="PreviewWorld"]

[node name="UI" type="CanvasLayer" parent="."]

[node name="Panel" type="PanelContainer" parent="UI"]
anchors_preset = 6
anchor_bottom = 1.0
offset_right = 300.0
grow_vertical = 2
theme_override_styles/panel = SubResource("StyleBox_panel")

[node name="Margin" type="ScrollContainer" parent="UI/Panel"]
layout_mode = 2
horizontal_scroll_mode = 0

[node name="VBox" type="VBoxContainer" parent="UI/Panel/Margin"]
layout_mode = 2
theme_override_constants/separation = 10

[node name="Title" type="Label" parent="UI/Panel/Margin/VBox"]
layout_mode = 2
theme_override_font_sizes/font_size = 22
text = "敌人动画预览"

[node name="Subtitle" type="Label" parent="UI/Panel/Margin/VBox"]
layout_mode = 2
modulate = Color(0.65, 0.72, 0.84, 1)
text = "造1+造2 · {len(defs)}怪物"

[node name="MonsterRow" type="HBoxContainer" parent="UI/Panel/Margin/VBox"]
layout_mode = 2
theme_override_constants/separation = 8

[node name="MonsterLabel" type="Label" parent="UI/Panel/Margin/VBox/MonsterRow"]
layout_mode = 2
text = "怪物"

[node name="MonsterOption" type="OptionButton" parent="UI/Panel/Margin/VBox/MonsterRow"]
layout_mode = 2
size_flags_horizontal = 3

[node name="Separator" type="HSeparator" parent="UI/Panel/Margin/VBox"]
layout_mode = 2

[node name="ActionLabel" type="Label" parent="UI/Panel/Margin/VBox"]
layout_mode = 2
text = "动作"

[node name="ActionOption" type="OptionButton" parent="UI/Panel/Margin/VBox"]
layout_mode = 2

[node name="Buttons" type="HBoxContainer" parent="UI/Panel/Margin/VBox"]
layout_mode = 2

[node name="ReplayButton" type="Button" parent="UI/Panel/Margin/VBox/Buttons"]
layout_mode = 2
size_flags_horizontal = 3
text = "重播"

[node name="PauseButton" type="Button" parent="UI/Panel/Margin/VBox/Buttons"]
layout_mode = 2
size_flags_horizontal = 3
text = "暂停"

[node name="FacingButton" type="Button" parent="UI/Panel/Margin/VBox/Buttons"]
layout_mode = 2
size_flags_horizontal = 3
text = "朝向：右"

[node name="AutoNextCheck" type="CheckBox" parent="UI/Panel/Margin/VBox"]
layout_mode = 2
button_pressed = true
text = "动作结束后循环"

[node name="ZoomRow" type="HBoxContainer" parent="UI/Panel/Margin/VBox"]
layout_mode = 2

[node name="ZoomLabel" type="Label" parent="UI/Panel/Margin/VBox/ZoomRow"]
layout_mode = 2
size_flags_horizontal = 3
text = "预览缩放"

[node name="ZoomSpin" type="SpinBox" parent="UI/Panel/Margin/VBox/ZoomRow"]
custom_minimum_size = Vector2(105, 0)
layout_mode = 2
min_value = 0.5
max_value = 3.0
step = 0.1
value = 1.5

[node name="SizeRow" type="HBoxContainer" parent="UI/Panel/Margin/VBox"]
layout_mode = 2

[node name="SizeLabel" type="Label" parent="UI/Panel/Margin/VBox/SizeRow"]
layout_mode = 2
size_flags_horizontal = 3
text = "角色缩放"

[node name="SizeSpin" type="SpinBox" parent="UI/Panel/Margin/VBox/SizeRow"]
custom_minimum_size = Vector2(105, 0)
layout_mode = 2
min_value = 0.3
max_value = 5.0
step = 0.1
value = 1.5

[node name="Coordinates" type="HBoxContainer" parent="UI/Panel/Margin/VBox"]
layout_mode = 2

[node name="XLabel" type="Label" parent="UI/Panel/Margin/VBox/Coordinates"]
layout_mode = 2
text = "X"

[node name="XSpin" type="SpinBox" parent="UI/Panel/Margin/VBox/Coordinates"]
custom_minimum_size = Vector2(105, 0)
layout_mode = 2
min_value = -2000.0
max_value = 2000.0
allow_lesser = true
allow_greater = true

[node name="YLabel" type="Label" parent="UI/Panel/Margin/VBox/Coordinates"]
layout_mode = 2
text = "Y"

[node name="YSpin" type="SpinBox" parent="UI/Panel/Margin/VBox/Coordinates"]
custom_minimum_size = Vector2(105, 0)
layout_mode = 2
min_value = -2000.0
max_value = 2000.0
allow_lesser = true
allow_greater = true

[node name="EditButtons" type="HBoxContainer" parent="UI/Panel/Margin/VBox"]
layout_mode = 2

[node name="ResetButton" type="Button" parent="UI/Panel/Margin/VBox/EditButtons"]
layout_mode = 2
size_flags_horizontal = 3
text = "恢复当前值"

[node name="SaveButton" type="Button" parent="UI/Panel/Margin/VBox/EditButtons"]
layout_mode = 2
size_flags_horizontal = 3
text = "保存坐标"

[node name="Separator2" type="HSeparator" parent="UI/Panel/Margin/VBox"]
layout_mode = 2

[node name="FrameLabel" type="Label" parent="UI/Panel/Margin/VBox"]
layout_mode = 2
text = "当前帧：-"

[node name="OffsetLabel" type="Label" parent="UI/Panel/Margin/VBox"]
layout_mode = 2
text = "原点偏移：-"

[node name="SourceLabel" type="Label" parent="UI/Panel/Margin/VBox"]
layout_mode = 2
autowrap_mode = 2
text = "-"

[node name="EventLabel" type="Label" parent="UI/Panel/Margin/VBox"]
layout_mode = 2
autowrap_mode = 2
text = "-"

[node name="Legend" type="Label" parent="UI/Panel/Margin/VBox"]
layout_mode = 2
modulate = Color(0.66, 0.72, 0.82, 1)
autowrap_mode = 2
text = "拖动或方向键微调；Shift = 10px\\n白十字：原点  蓝点：offset  绿框：碰撞体"

[node name="Spacer" type="Control" parent="UI/Panel/Margin/VBox"]
custom_minimum_size = Vector2(0, 10)
layout_mode = 2
size_flags_vertical = 3

[node name="StatusLabel" type="Label" parent="UI/Panel/Margin/VBox"]
layout_mode = 2
modulate = Color(0.45, 0.88, 0.64, 1)
autowrap_mode = 2
text = "准备中"
"""

with open('scenes/debug/enemy_animation_preview.tscn', 'w', encoding='utf-8') as f:
    f.write(scene)
print(f"Generated scene with {len(defs)} monsters")
