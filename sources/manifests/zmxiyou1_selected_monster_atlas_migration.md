# 造梦西游 1 selected 怪物图集迁移清单

- 日期：2026-07-23
- 范围：`assets/selected/zmxiyou1/monsters`
- 标准来源：`assets/extracted/classified/zmxiyou1/怪物`
- 运行时配置：`resources/enemies/animations/zmxiyou1*_profile.tres`
- 执行工具：`scripts/optimize_zmxiyou1_monster_atlases.py`

## 判断与保留策略

本次只改变开发选材层的存储格式，不修改原始 SWF、解码文件或 classified 标准库。
依据 `zmxiyou1_monster_timeline_audit.json` 和
`zmxiyou1_all_monster_animations_selected.json` 中记录的完整动作提供者，逐动作将
selected 的 `frame_NNN.png` 副本替换为同一提供者已经在 classified 中打包好的
`sprite.png + sprite.json`。像素核验覆盖当前 26 个 profile、155 个动作：143 个动作
的 selected 首帧与候选图集可直接还原为相同像素；6 个双匹配来自待机/移动共用同一
时间轴；旧 `zmxiyou1_m09_peng_demon_king_profile.tres` 的 11 个动作复用已核验的
M09 标准映射。

保留以下运行时语义：

- profile 中的 `fps`、`loop`、`next_animation`、`source_events` 和人工保存的
  `sprite_offset` 原样保留；
- classified 中多元件动作只选择时间轴审计确认的完整动作提供者，不合并其他零件；
- trim 图集继续保留 `ox/oy/cw/ch`，运行时用 `AtlasTexture.margin` 恢复原帧画布；
- `bat_sandbag.png`、`rat_boss.png` 和龟丞相旧测试用 `attack1_unique.png` 不在本次
  删除范围内，因为仍有独立资源引用；
- M01 待机是根时间轴静态回退，classified 没有对应完整子时间轴；唯一例外是将现有
  6 张 selected 待机帧本地打包成图集，不伪造 classified 来源。

## 标准映射

普通动作按以下语义目录直接映射：受伤、受伤恢复、待机、移动、死亡、攻击1～攻击5；
M19 的分阶段动作映射到同名“阶段”目录。多元件动作的完整提供者固定为：

- M04 攻击2：`元件45ssss_9`
- M06 攻击1/攻击2：`元件9_23`、`元件12_26`
- M08 攻击1：`character_218`
- M09 变蛋/飞行/攻击2/重燃：`Timeline_101`、`共享动作时间轴`、`Timeline_97`、
  `character_622`
- M10 攻击1/攻击3：`Timeline_21`、`character_1112`
- M11 攻击2/攻击3：`Timeline_190`、`character_159`
- M16 攻击2：`Timeline_76`
- M18 攻击2：`Timeline_174`
- M20 攻击1：`Timeline_212`
- M23 攻击2～攻击5：`Timeline_35`、`Timeline_40`、`Timeline_42`、`Timeline_52`
- M26 攻击2/攻击3：`Timeline_14`、`Timeline_26`

同一怪物的历史别名目录不再复制一套素材；两个 M09 profile 共用 `m09_peng`，两个
M23 profile 共用 `m23_bull`。其他命名目录以当前正式 enemy definition 引用为准。

## 删除范围与理由

执行前 selected 中共有 6,046 个 PNG，其中 6,043 个是逐帧 PNG，并有 6,043 个对应
`.import`。图集复制、JSON
帧数校验和 profile 改写成功后，删除这些 `frame_NNN.png(.import)`；它们均是可由保留
图集区域恢复的开发层冗余副本。只清理因此变空的目录，不删除上述独立测试素材。

## 执行后核验

执行结果：

- 复制 classified 图集 139 组，并生成 M01 待机本地图集 1 组；selected 现有
  `sprite.png + sprite.json` 140 组；
- selected PNG/JSON/导入文件合计约 37.9 MiB，迁移前为约 149.3 MiB；
- 逐帧 `frame_NNN.png` 和对应 `.import` 均为 0；三个独立测试 PNG 及引用保留；
- 26 个造 1 profile 的 155 个动作均包含 `sprite_sheet` 与 `sprite_sheet_json`，
  `path_pattern` 残留为 0；
- `validate_zmxiyou1_monster_atlases.gd` 已实际构建全部 155 个动作，图集帧数与 profile
  全部一致，Godot 返回 0；
- 统一动画浏览器敌人模式与造 1 战斗测试场景均可无窗口启动并返回 0。浏览器扫描造 2
  中文资源名时仍会输出既有的 scene unique ID 警告，不来自本次造 1 图集迁移；战斗测试
  退出时仍有既有资源占用提示。
