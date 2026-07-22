# 造梦西游 1 怪物特效-动画关系梳理 & Godot 集成设计

> 生成日期: 2026-07-22
> 数据来源: `zmxiyou1_monster_events.json`, `zmxiyou1_monster_timeline_audit.json`, 整理后的素材目录

## 一、怪物分层

### 小怪 (Trash Mob) — 13 只
**M01, M02, M03, M07, M13, M15, M20, M25, M27, M21, M17, M16, M08**

特征:
- 动作 5~6 个: 待机, 移动, 受伤, 攻击1, 死亡 (+ 受伤恢复)
- 纯物理近战 (hit1 kind=physics)
- 无弹道特效目录
- 死亡时调用 `dropAura()` + `destroy()`

### 中 BOSS — 4 只
**M06_禺狨王, M14, M22_牛魔王, M24_牛魔王**

特征:
- HP 1000~200000
- 有魔法攻击
- M14: `EnemyMoveBullet("Monster14Bullet1")` — **唯一使用 EnemyMoveBullet 的怪物**（有代码驱动的水平移动）
- M22/M24: 有 `addBeAttackEffect()` 受击特效
- M24: 有独立的 BG/Hands 特效层（背景和手臂独立动画）

### 大 BOSS — 9 只
**M04_彌猴王, M09_彭魔王, M10_鲛魔王, M11_狮驼王, M18, M19_鲨魔王, M23_牛魔王, M26_龙王**

特征:
- HP 1500~48000
- 3~5 个攻击阶段
- 多个弹道类型 (SpecialEffectBullet)
- 复杂的多阶段攻击 (hit1/hit2/hit3, 阶段1/阶段2)
- 部分有 `addBeAttackEffect()` 和弹道预警 (BulletPre)

## 二、特效分类

### A. 共享特效 (公共特效/)

| 资源 | 帧数 | 用途 | 使用者 |
|---|---|---|---|
| `BossDead` | 12fr | BOSS 死亡爆炸 | 所有有 `standInObj` 的怪物 |
| `auraBlue` | 19fr | 蓝色光环 | 通用 |
| `auraGreen` | 19fr | 绿色光环 | 通用 |
| `auraRed` | 19fr | 红色光环 | 通用 |
| `auraWhile` | 19fr | 白色光环 | 通用 |
| `poisonHead` | 1fr | 中毒头顶标识 | 通用 |
| `poisonUp` | 41fr | 中毒上升粒子 | 通用 |

### B. 专属弹道 (各怪物 特效/ 目录)

| 怪物 | 特效 | 类型 | 帧数 | 对应攻击 |
|---|---|---|---|---|
| M04 | Boss2Bullet1 | SpecialEffectBullet | 50fr | hit3 (magic) |
| M09 | Boss4Bullet1 | SpecialEffectBullet | ？| hit1~hit4 |
| M10 | Boss5Bullet1 | SpecialEffectBullet | 25fr | hit2 |
| M10 | BeAttack | 受击特效 | 10fr | 受击时 |
| M11 | Boss6Bullet1 | SpecialEffectBullet | 241fr | hit3 |
| M14 | Bullet1 | EnemyMoveBullet | ？| hit1 |
| M18 | Bullet1 | SpecialEffectBullet | 44fr | hit1 |
| M18 | Bullet2 | SpecialEffectBullet | 18fr | hit2 |
| M18 | Bullet2Pre | 弹道预警 | 25fr | hit2 预警 |
| M19 | Bullet1 | SpecialEffectBullet | 51fr | hit2 |
| M19 | Bullet2 | SpecialEffectBullet | 30fr | hit3 |
| M19 | Bullet2Pre | 弹道预警 | 24fr | hit3 预警 |
| M24 | BG | 背景层 | ？| 常驻 |
| M24 | Hands | 手臂层 | ？| 常驻 |
| M26 | Bullet1 | SpecialEffectBullet | 41fr | hit1 |
| M26 | Bullet2 | SpecialEffectBullet | 68fr | hit3 |
| M26 | ice | 冰系特效 | 35fr | hit2/hit4 |

### C. 代码驱动的特效（无独立素材，需 Shader/代码实现）

| 特效 | 触发条件 | 实现方式 |
|---|---|---|
| `dropAura()` | 死亡时 | 掉落光环（可能引用 aura 素材 + 位移动画） |
| `addBeAttackEffect()` | 受击时 | 受到攻击的闪烁/变色效果 → Shader |
| `addBackBeAttackEffect()` | 受击时 | 击退受击效果 → Shader |

## 三、弹道系统分析

### SpecialEffectBullet（动画弹道）
**使用者**: Boss2Bullet1, Boss4Bullet1, Boss5Bullet1, Boss6Bullet1, Monster13Bullet1, Monster18Bullet1/2, Monster19Bullet1/2, Monster26Bullet1/2

```actionscript
// SpecialEffectBullet 继承自 BaseBullet
// 没有代码移动逻辑——弹道轨迹完全在 Flash 时间轴里
// 碰撞检测在 BaseBullet.checkAttack() 中用 hitTestObject()
class SpecialEffectBullet extends BaseBullet {
    override function step(): void {
        super.step();  // 只调用 checkAttack()
    }
}
```

**Godot 实现**: AnimatedSprite2D 播放 sprite sheet，用 Area2D + CollisionShape2D 做碰撞检测。弹道"移动"由动画帧自身表现。

### EnemyMoveBullet（代码移动弹道）
**使用者**: Monster14Bullet1 (仅 M14)

```actionscript
class EnemyMoveBullet extends BaseBullet {
    override function step(): void {
        this.x += this.speed;               // 水平移动
        if (speed < 7) speed += 0.4;        // 加速
        this.distance -= abs(this.speed);
        if (distance <= 0) this.destroy();  // 距离耗尽销毁
    }
}
```

**Godot 实现**: CharacterBody2D + AnimatedSprite2D，在 `_physics_process` 中移动。

### 弹道预警 (BulletPre)
**使用者**: M18 Bullet2Pre, M19 Bullet2Pre

弹道发射前的地面预警标识——通常是红色闪烁区域，警告玩家弹道即将到来。

**Godot 实现**: 预警阶段播放 BulletPre 动画 → 短暂延迟 → 发射实际 Bullet 动画。

## 四、攻击参数总结

| 怪物 | HP | 攻击 | 类型 | 伤害 | 命中次数 | 击退 [x, y] |
|---|---|---|---|---|---|---|
| M01 | 50 | hit1 | physics | 5 | 1 | [2, -5] |
| M02 | 100 | hit1 | physics | 12 | 1 | [6, -5] |
| M03 | 300 | hit1 | physics | 20 | 1 | [6, -5] |
| **M04** | **1500** | hit1/hit2/hit3 | phy/phy/**magic** | 30/20/20 | 2/50/40 | —/[2,-7]/**[15,0]** |
| M06 | 3000 | hit1/hit2 | phy/magic | 30/40 | 1/1 | [12,-2]/[2,-12] |
| M07 | 600 | hit1 | physics | 35 | 1 | [5,-5] |
| M08 | 500 | hit1 | physics | 25 | 1 | [5,-5] |
| M09 | ? | hit1~hit4 | 混合 | 70~200 | 99 | 微小 |
| M10 | 24000 | hit1/hit2/hit3 | phy/phy/magic | 120/200/150 | 2/30/40 | —/[2,-7]/[15,0] |
| M11 | 6000 | hit1/hit2/hit3 | phy/phy/magic | 60/200/40 | 2/30/40 | —/[2,-7]/[2,-4] |
| M13 | 700 | hit1/hit2 | phy/phy | 45/60 | 20/20 | [10,-2]/[2,-2] |
| M14 | 1000 | hit1 | **magic** | 30 | 1 | [2,-5] |
| M15 | 800 | hit1 | physics | 55 | 1 | [5,-5] |
| M16 | 1200 | hit1/hit2 | phy/magic | 90/110 | 20/20 | [6,-2]/[2,-2] |
| M17 | 1600 | hit1 | magic | 110 | 2 | [2,-5] |
| M18 | 999999 | hit1/hit2 | phy/phy | 150/300 | 1~100 | [0,-2]/[5,-5] |
| M19 | 48000 | hit1~hit3(多阶段) | 混合 | 130~300 | 2~40 | 可变 |
| M20 | 1400 | hit1 | physics | 100 | 1 | [10,-2] |
| M22 | 40000 | walk | physics | 300 | 1 | [20,-2] |
| M23 | 20000 | hit1~hit5 | 混合 | 50~210 | 30~40 | 可变 |
| M24 | 200000 | hit1/hit2 | magic | 300~400 | 2~30 | [6,-5]/[2,-10] |
| M25 | 5000 | hit1 | physics | 200 | 1 | [10,-3] |
| M26 | 12000 | hit1~hit4 | 混合 | 17~300 | 30~40 | 可变 |

## 五、Godot 场景设计

### 5.1 节点层级（通用怪物场景）

```
Monster (CharacterBody2D)
├── CollisionShape2D              # 碰撞体
├── AnimationPlayer               # 动作状态机控制器
├── BodySprites (Node2D)
│   └── AnimatedSprite2D          # 身体动画 (sprite sheet)
├── EffectLayer (Node2D)          # 特效层
│   ├── AnimatedSprite2D (aura)   # 光环（按需显示）
│   ├── AnimatedSprite2D (hurt)   # 受击特效
│   └── AnimatedSprite2D (dead)   # 死亡特效
├── BulletSpawner (Node2D)        # 弹道生成点
└── HPBar (Control)               # 血条（可独立或由 HUD 管理）
```

### 5.2 简化策略

#### 小怪（13只）—— 共享状态机
```
TrashMonster.tscn (通用场景)
  - 动作集: idle, walk, hurt, attack1, dead
  - 特效集: dropAura (死亡), redFlash (受击 Shader)
  - 参数化: HP, damage, speed, sprite_sheet_path
```

所有小怪使用**同一个场景**，通过 Resource 配置不同的 sprite sheet 路径和数值参数。

#### Boss — 独立场景
每个大 BOSS 需要独立场景，因为：
- 多阶段攻击（3~5 种）
- 专属弹道类型
- 特殊机制（M04 弹道, M09 变蛋, M19 多阶段, M24 BG+Hands 层）

### 5.3 特效实现

| 特效 | Godot 实现 | 简化 |
|---|---|---|
| **光环 (aura*)** | AnimatedSprite2D，4 种颜色 | **合并为 1 张 sprite + shader 调色** |
| **受击闪烁** | ShaderMaterial: white flash 0.1s | 所有怪物共用 |
| **死亡爆炸 (BossDead)** | AnimatedSprite2D + 自动销毁 | 全局单例 |
| **中毒标识 (poisonHead/Up)** | AnimatedSprite2D 挂在受击怪物上 | 全局资源 |
| **弹道 (Bullet)** | 独立 Bullet 场景 + 对应 sprite sheet | 每种弹道一个 .tscn |
| **弹道预警 (BulletPre)** | BulletPre 场景 → tween 后替换为 Bullet | M18/M19 专用 |

### 5.4 动作状态机

```
                  ┌──────────┐
         ┌───────→│   IDLE   │←──────┐
         │        └────┬─────┘       │
         │        ┌────↓─────┐       │
         │        │   WALK   │       │
         │        └────┬─────┘       │
         │    ┌───────→↓            │
      afterHurt│  ┌──────────┐      │
         │    │   │ ATTACK1~N│      │
         │    │   └────┬─────┘      │
         │    │        ↓ (animation │
         │    │        ↓  end)      │
         └────↑────────┘            │
              │                     │
         ┌────↓─────┐               │
         │   HURT   │───────────────┘
         └────┬─────┘
              ↓
         ┌──────────┐
         │   DEAD   │  → BossDead → destroy()
         └──────────┘
```

状态转换规则（从 events JSON 的 `action_transition` 提取）：
- attack → wait (攻击结束回待机)
- hurt → afterHurt → walk (受伤恢复后行走)
- any → dead (HP≤0 时强制死亡)
- idle → walk (AI 检测到目标后移动)

### 5.5 弹道系统

```gdscript
# Bullet.gd (通用弹道)
class_name Bullet extends Area2D

@export var sprite_sheet: CompressedTexture2D
@export var frame_data: JSON
@export var damage: int
@export var hit_max_count: int
@export var knockback: Vector2
@export var is_magic: bool
@export var use_code_movement: bool = false  # true for EnemyMoveBullet
@export var speed: float = 0
@export var max_distance: int = 0
```

两种弹道子类：
- `AnimatedBullet`: 纯动画播放，碰撞靠 Area2D 的 `body_entered`
- `MovingBullet`: 代码移动 + 动画播放（仅 M14）

### 5.6 资源路径约定

```
assets/selected/zmxiyou1/monsters/
  M01/
    idle/sprite.png       + idle/sprite.json
    walk/sprite.png       + walk/sprite.json
    hurt/sprite.png       + hurt/sprite.json
    attack1/sprite.png    + attack1/sprite.json
    dead/sprite.png       + dead/sprite.json
    monster_config.tres   # HP, damage, speed, actions...
  M04/
    ...actions...
    effects/
      Boss2Bullet1/sprite.png + json
    monster_config.tres
  shared/
    aura_sheet.png        # 4色光环合并 (blue/green/red/white)
    boss_dead.png         # 死亡爆炸
    poison.png            # 中毒特效
    beattack_flash.shader # 受击闪烁
```

## 六、可进一步简化的点

1. **光环 4 色合并**: auraBlue/Green/Red/While → 1 张 sprite sheet + shader 参数 `aura_color: Color`
2. **小怪统一场景**: 13 只小怪共用 `TrashMonster.tscn`，只换 `monster_config.tres`
3. **受击特效 Shader 化**: `addBeAttackEffect()` → 白色闪烁 shader，无需额外素材
4. **dropAura 统一**: 所有怪物死亡时的光环掉落，很可能就是 aura 素材 + 向下位移 + fade
5. **M14 是唯一代码移动弹道**: 其余全部是动画弹道 → 默认用 AnimatedBullet 即可
