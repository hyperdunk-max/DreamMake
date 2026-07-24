# 造梦西游 1 怪物战斗系统：Godot 集成设计与实现状态

> 初始设计：2026-07-22
>
> 实现状态更新：2026-07-24
>
> 事件来源：`zmxiyou1_monster_events.json`、`zmxiyou1_monster_timeline_audit.json`、保留的 ActionScript 导出
>
> 运行时选材：`zmxiyou1_enemy_combat_runtime_assets.json`
>
> 事件同步结果：`zmxiyou1_monster_event_sync.json`

本文是造 1 怪物战斗运行时的当前权威设计。2026-07-22 版本中的“每种弹道一个场景”“Boss 必须各用独立场景”等内容已经被数据驱动实现取代；下文同时记录已完成范围和仍未解决的来源缺口，不能把“已接入通用运行时”等同于“所有怪物已经与原版完全一致”。

## 一、不可破坏的资源与溯源边界

1. 原始 SWF、解码文件和标准分类库是溯源依据，运行时代码不修改它们。
2. 正式战斗只读取 `assets/selected/zmxiyou1/monsters` 下的 `sprite.png + sprite.json`；不拆散图集，也不复制一套只供战斗使用的帧配置。
3. 原样选取的图集保留像素和 JSON 坐标；静态 PNG 仍打包成一帧图集。来源、目标、帧数、哈希和未决项写入 `zmxiyou1_enemy_combat_runtime_assets.json`。
4. ActionScript 不在 Godot 中执行。同步工具只把已审计脚本规范化为 `action_transition`、`projectile_spawn`、`projectile_warning`、`grab_check`、`life_steal_tick`、`motion` 等惰性类型事件。
5. 怪物 `sprite_offset` 只能由统一入口 `scenes/debug/animation_browser.tscn` 保存到正式 `EnemyAnimationProfile`；战斗场景不保存坐标副本。

截至 2026-07-24，事件同步覆盖 27 个 profile、165 个动作和 346 个类型化事件。M24 的四个程序控制组件明确标为 `runtime_component`，不伪造根动作帧事件；同步仍保留现有 `sprite_offset`、碰撞与人工配置字段。

## 二、运行时架构

### 2.1 统一的怪物运行时

小怪与 Boss 都复用 `AnimatedEnemy`，差异放在资源和少量有来源证据的机制分支中：

```text
AnimatedEnemy (CharacterBody2D)
├── EnemyDefinition
│   ├── ActorProperty：HP / DEF / ATK
│   ├── EnemyAnimationProfile：动作图集、偏移、来源事件
│   ├── 原版等级变体参数（适用时）
│   └── source_controller_scene：经审计的组合 Boss 组件（适用时）
├── Zmxiyou1EnemyStrategy：24 Hz 来源 AI 与冷却
├── EnemyCombatCatalog：ActionScript 审计字段 → 安全攻击描述
├── AnimatedSprite2D：sprite pack 动作
├── CollisionShape2D：怪物物理碰撞体
└── EnemyBullet / ProjectileSpriteEffect / CombatStatusController
```

这保留了通用场景与 Resource 参数化的优势，也允许 M09、M10、M19、M22、M23、M24、M26 等特殊机制在同一个受测运行时内实现。M22/M24 的控制器只负责各自的来源阶段或组合行为，不复制怪物生命、受击、物理或资源加载系统。

### 2.2 两个时钟

- 原版 AI、冷却、阶段计数和状态持续时间固定按 24 Hz 来源 tick 运行。
- Godot 移动、碰撞查询和画面更新仍按项目 physics FPS 运行。
- ActionScript 中的 `px/tick` 在策略层换算为 `px/s`，避免物理 FPS 改变怪物速度或冷却。
- 同一动作被强制重播时先回到第 0 帧，保证第 0 帧弹道事件不会丢失。

### 2.3 攻击描述与事件

`EnemyCombatCatalog` 从审计清单读取以下白名单字段：

- 伤害种类、power、最大命中数、重复命中间隔和击退；
- 弹道来源、生成帧、生成偏移、预警、代码移动参数；
- `addEffect` 中可规范化的 poison / ice 状态。

来源代码只作为数据证据，不通过 `eval`、动态表达式或脚本加载执行。顶层动作只在真正的 `action_transition` 事件结束；嵌套 `timeline_branch` 中保留的来源标签不会误结束 M23 `attack5` 等复合动作。

死亡事件不再受 ATTACK 状态过滤：154 个已同步 `visibility` 事件按来源帧切换正式 AnimatedSprite，复现隔帧闪烁。`BossDead` 也不再由 `is_boss` 推断；只有死亡时间轴含 `spawn_object` 且源码实际创建 `BossDead` 的 M04/M06/M09/M10/M11/M19/M21/M23 才播放该 sprite pack，M03/M17/M22/M26 不会凭 Boss 标记多出特效。

## 三、Godot 碰撞替代 Flash `hitTestObject`

### 3.1 近战

怪物使用 Godot 物理空间查询目标，不调用 Flash 矩形命中接口。攻击描述继续决定有效帧、命中上限和间隔；Godot 碰撞层决定实际可命中的玩家对象。

### 3.2 弹道

`EnemyBullet` 是统一的 `Area2D` 弹道：

- 每帧从 sprite pack 的 atlas region、trim 后的 `ox/oy/cw/ch` 和可见像素边界生成矩形 `CollisionShape2D`；
- 不改写 `sprite.png` 或 `sprite.json`；
- 动画弹道使用时间轴画面表现位移，M14 使用来源代码对应的水平加速与最大距离；
- 支持弹道专属伤害、击退、最大命中数、重复命中帧间隔、激活延迟、淡入、循环和状态效果；
- 施法者销毁时清理其循环弹道，并在命中回调前校验弱引用，避免传递已释放 source。

相比 Flash 的 `hitTestObject`，碰撞查询进入 Godot 物理层，碰撞形状仍随原版可见帧变化，因此既保留帧语义又能使用 collision layer / mask、可视化调试和确定性的命中筛选。

## 四、已接入的弹道与共享特效

正式选择记录以 `zmxiyou1_enemy_combat_runtime_assets.json` 为准。当前主要条目如下：

| 来源 | 运行时用途 | 帧数 | 实现 |
|---|---:|---:|---|
| shared `BossDead` | Boss 死亡爆炸 | 12 | 图集播放后销毁 |
| shared `auraBlue` | 掉落光环参考色 | 19 | 图集；颜色变体可由 shader 生成 |
| shared `poisonHead` / `poisonUp` | 中毒常驻标识 / 施加动画 | 1 / 41 | `CombatStatusController` |
| M04 `Boss2Bullet1` | attack3 动画弹道 | 50 | 保留既有 runtime repack |
| M09 `Boss4Bullet1` | attack1 / attack3 火焰 | 1 | 一帧 sprite pack，循环与淡入由运行时实现 |
| M10 `Boss5Bullet1` | attack3 动画弹道 | 25 | 逐帧碰撞 |
| M10 `BeAttack` | 物理背击特效 | 10 | 来源专属 overlay |
| M11 `Boss6Bullet1` | attack3 动画弹道与中毒 | 241 | 逐帧碰撞 + poison |
| M14 `Bullet1` | attack1 移动弹道 | 1 | 代码移动、加速、距离耗尽 |
| M18 `Bullet1` / `Bullet2` / `Bullet2Pre` | 两种弹道和地面预警 | 44 / 18 / 25 | 接触触发、预警完成后替换 |
| M19 `Bullet1` / `Bullet2` / `Bullet2Pre` | 分阶段弹道和预警 | 51 / 30 / 24 | 阶段动作共用来源图集 |
| M13 `Monster13Bullet1` | attack2 飞剑 | 27 | SWF symbol509 恢复；逐帧碰撞 |
| M24 `BG` / `Hands` / `Heart` / `Eyes` / `Fire` | 组合 Boss | 1 / 1 / 23 / 25 / 40 | 独立 24 Hz 组件与逐帧碰撞 |
| M26 `Bullet1` / `Bullet2` / `ice` | attack1、attack4 和冻结 | 41 / 68 / 35 | 弹道 + ice 状态 |

M19 `hit3-2` 的 18 帧动作已从 `M19_鲨魔王/攻击3_阶段2` 原样选择到 `m19_shark/attack3_2`。PNG 和 JSON 的 SHA-256 已写入选材清单；当前正式 `sprite_offset` 为零，只能在统一动画浏览器中校准。

## 五、已完成的来源专属机制

### M09 彭魔王

- 初始为地面状态，之后按来源 tick 在飞行和地面周期间切换；对应使用 `fly` 或地面待机/移动动作。
- 致死伤害先进入蛋形态：单人需 5 次命中，双人需 10 次命中。
- 168 ticks 未击破则重燃并恢复 10000 HP；期间按来源间隔生成火焰。
- 一帧火焰图集保留 0.6 秒淡入和循环，不因只有一帧而立即销毁。

### M10 鲛魔王

- DEF 为来源值 80。
- 从怪物同向一侧命中视为原版背击方向：只受 1 点伤害。
- 物理背击播放 `Monster10BeAttack` 的 10 帧 sprite pack；不以通用 shader 替代这个有独立来源素材的特效。

### M18

- 当前按来源作为 M19 二阶段召唤物：非 Boss、飞行单位、DEF 25。
- attack1 不再在第 0 帧无条件发射；使用 Godot 重叠查询触发，并在目标 `(-100, -100)` 生成 Bullet1。
- attack2 开始在自身生成 Bullet2；来源 frame 48 在目标 x、地面 y=510 生成预警，隐藏本体，预警播完再生成 Bullet2 并恢复可见性。

### M19 鲨魔王

- DEF 为来源值 90。
- HP 低于 70% 首次进入二阶段，并在原位置生成一个 M18；Boss 销毁时清理召唤物。
- attack2 弹道偏移为 `±600, -40`；attack3 预警位于目标 `(-100, -100)`。
- 二阶段 `attack3_2` 使用独立的正式 profile 动作与来源事件。

### M23 牛魔王

- attack5 frame 27 的 `grab_check` 使用 Godot 目标查询；只抓取水平距离 200 px 内玩家。
- 抓取时使用可叠加的外部控制锁和可见性锁，不覆盖玩家其他系统的锁状态。
- 5 次 `life_steal_tick` 每次造成 50 魔法伤害并为 Boss 回复 500 HP。
- 动作结束、受伤或节点销毁都会恢复玩家控制与可见性。

### M26 龙王

- 玩家最低等级 `> 20` 时采用高等级来源变体：HP 40000、DEF 150、攻击 variant 0。
- 其余情况采用低等级来源变体：HP 12000、DEF 50、攻击 variant 1。
- 低等级冻结持续 48 ticks，高等级持续 120 ticks；控制锁可与其他系统叠加。
- attack4 弹道生成位置为 `target.x - 65, boss.y - 120`。

### M24 牛魔王（最终组合形态）

- `EnemyDefinition.source_controller_scene` 挂载来源专属组合控制器，全部视觉仍由正式 profile 中的 sprite pack 构建。
- BG 在 48 ticks 内淡入；之后两只 Hands 各自保留随机方向、`[-400, 400]` 边界、加速下砸、24 ticks 停留和 attack-id 刷新。
- Heart 初始隐藏 5–9 秒、淡入 48 ticks、显露 2–5 秒、淡出 48 ticks，后续隐藏 5–11 秒；只有 alpha 精确为 1 时启用来源 `colipse` 对应的 Godot 伤害碰撞体。
- Fire 每 2–6 秒生成，批次数严格循环 `2 → 4 → 6`；使用 symbol755 的完整 40 帧图集，只在来源 currentFrame 25–36 查询逐帧可见像素碰撞。
- 双手造成 400 魔伤、击退 `[6,-5]`；Fire 造成 300 魔伤、击退 `[2,-10]`，均按 24 Hz 换算 Godot 速度并共享来源 attack id。
- 死亡后整体按 48 ticks 淡出再清理，不播放其他 Boss 的通用死亡爆炸。

### M22 牛魔王（奔跑阶段）

- 初始向左以来源 `13 px/tick = 312 px/s` 奔跑；相对摄像机中心保留 `-360 / +400` 两个来源边界。
- 奔跑期间等价于 `isYourFather = true`：拒绝受击，并用 `walk` 的来源攻击描述进行 Godot 接触形状查询，造成 300 物伤。
- 到达边界后停止并变为可伤；首次停留跨 25 次来源调用，后续跨 73 次来源调用，然后刷新 attack id 并反向奔跑。
- 死亡动作结束时先在来源坐标 `(1500, 450)` 生成 M23，再让 M22 按 BaseMonster 的一秒 alpha 淡出；不额外播放其来源时间轴没有生成的通用 BossDead。

### M11 中毒与 M26 冻结

- poison：持续 240 ticks，每 24 ticks 造成 20 伤害；`poisonUp` 位于 y=-50，`poisonHead` 位于 y=-70。
- ice：按 M26 等级变体持续 48 或 120 ticks；图集位于 x=-90、y=-115。
- 两者直接读取正式 sprite pack。状态结束时只释放自身持有的控制锁和视觉节点。

## 六、AI 与状态机覆盖范围

`Zmxiyou1EnemyStrategy` 现在覆盖当前 27 个 runtime profile 对应的 25 个来源怪物 ID。M01/M02/M03/M07/M17/M20/M25 使用已审计 BaseMonster 的 36-tick 概率攻击；M01 保留“受击后才索敌”。M08/M15 保留飞行垂直加速度与目标高度，M14 保持 200–350 px 射程，M06 保留 24-tick hit1/hit2 循环，M21/M27 明确为不移动且不攻击的可破坏对象。

已有 M04/M09/M10/M11/M13/M16/M18/M19/M23/M24/M26 分支继续保留来源冷却和阶段逻辑；所有直接 `setYourFather(N)` 的技能已记录为整数来源无敌 ticks。完整构造器、距离、概率和选择变体见 `zmxiyou1_enemy_strategy_audit.json`，不能根据动作数量或目录名反推新的行为。

## 七、已解除的来源缺口与仍未项

### M13 `Monster13Bullet1`（已完成）

已沿 `symbolClass → DefineSprite → PlaceObject` 在 `Monster2_v4.swf` 定位 `DefineSprite_509_Monster13Bullet1`，恢复并打包 27 帧、每帧 `333×19` 的原始飞剑时间轴。`M13 hit2` 第 3 帧的 `throwKnife()` 已同步为 `projectile_spawn`，运行时保持时间轴自身位移并使用逐帧可见像素碰撞体。M16 虽有同名方法，但没有已审计动作调用，因此没有推断性绑定。

### M24 `BG / Hands / Heart / Eyes / Fire`（已完成）

M24 已确认为程序控制的组合 Boss：静态 BG、两只独立 Hands、23 帧 Heart、两只镜像的 25 帧 Eyes，以及按批次生成的 40 帧 Fire。正式实现以多个 sprite-pack 节点保持来源层级和独立时钟；固定 24 Hz alpha 插值等价实现源码的 2 秒透明度变化，Godot shape query 替换 `complexHitTestObject`。完整矩阵、随机区间和命中窗口已记录在 `zmxiyou1_enemy_combat_runtime_assets.json`。

BG/Hands 的 classified 静态 PNG 已与 SWF 直接导出核验为逐字节一致；Heart/Eyes 复用现有 classified 图集；Fire 从 symbol755 的 40 帧完整渲染结果打包，没有把 `组成元件/Fire` 误当作动画帧。`zmxiyou1_m24_boss_test.gd` 已覆盖伤害窗口、双手下砸、Fire 批次和帧窗、死亡淡出，M24 已从阻塞清单移除。

### 已完成 AI 审计后的剩余上下文项

逐怪物构造器与 `myIntelligence` 已完成源码级复核。正式 `StageDefinition.source_stage/source_level` 会在敌人 `_ready` 前注入上下文，因此 M03/M17 的 Boss/普通形态和 M27 的 `totalStage` 立方 HP 公式共用同一套 profile 与 definition。当前剩余项不再是未知 AI，而是 M03/M06/M17/M21 的传送门，以及 M21/M27 的光环/活动掉落需要接入后续来源关卡进度层。项目对“完全一致”的完成判定仍须同时满足动作帧、类型化事件、伤害/状态、AI 决策、弹道碰撞和这些关卡副作用都有证据与自动测试。

## 八、现代 Godot 优势的使用边界

允许并推荐：

- `CharacterBody2D` / `Area2D` / collision layer 与 mask 替代 Flash 碰撞判断；
- Resource 驱动怪物定义、动作 profile 和等级变体；
- 统一状态组件、弱引用、自动清理和可叠加控制锁；
- shader 实现没有独立来源动画的白闪、调色等程序效果；
- headless 测试验证来源 tick、帧事件、碰撞和资源完整性。

不允许为了“现代化”改变：

- 原版动作帧、事件时机、有效攻击次数、冷却和状态持续时间；
- 有独立来源素材的专属视觉（例如 M10 背击）；
- sprite pack 的像素、帧顺序或 JSON 坐标；
- 未经来源审计的组合时间轴。

## 九、验证入口

```powershell
godot --headless --path . --script tests/enemy_combat_runtime_test.gd
godot --headless --path . --script tests/enemy_status_effects_test.gd
godot --headless --path . --script tests/zmxiyou1_enemy_combat_profiles_test.gd
godot --headless --path . --script tests/zmxiyou1_enemy_projectile_profiles_test.gd
godot --headless --path . --script tests/zmxiyou1_monster_event_sync_test.gd
godot --headless --path . --script tests/zmxiyou1_m24_boss_test.gd
godot --headless --path . --script tests/zmxiyou1_enemy_strategy_coverage_test.gd
godot --headless --path . --script tests/animation_browser_test.gd
godot --headless --path . --script scripts/validate_zmxiyou1_monster_atlases.gd
godot --headless --path . --quit-after 300 scenes/stages/zmxiyou1_combat_test.tscn
```

视觉复核统一从以下入口进入：

```powershell
godot --animation-mode=enemies scenes/debug/animation_browser.tscn
```

任何通过视觉判断得到的保留、删除、重命名、组合或坐标结论，都必须先回写相应 `sources/manifests` 或正式 profile，再进入战斗运行时。
