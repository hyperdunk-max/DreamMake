# DreamMake workspace instructions

## 素材整理任务

开始整理、筛选、去重、重命名或删除《造梦西游》素材前，必须先阅读：

`sources/ASSET_ORGANIZATION_GUIDE.md`

这份规范适用于造 1、造 2、造 3 及后续版本。核心约定：

- 原始 SWF、解码文件和 `assets/extracted/full` 是溯源库，默认不做精简删除。
- `assets/extracted/classified/<game>` 是整理后的标准分类库，应去除可由运行时生成的冗余帧和重复格式。
- `assets/selected/<game>` 是实际开发选材，不应反向取代完整溯源记录。
- 删除前必须区分真实动画、数值驱动时间轴、语义枚举和组合零件，不能仅凭文件数量批量判断。
- 每次人工判断、保留项和删除范围都要写入 `sources/manifests`，以便其他对话继续工作。
- 保留用户已经完成的人工分类和命名；若需要调整规则或目录，先更新规范和清单，再执行迁移。

## 动画预览规范

- 交互式动画预览的唯一统一入口是 `scenes/debug/animation_browser.tscn`。
- 浏览器当前统一承载“角色动作、敌人动作、技能特效”三类模块；后续动画预览必须作为该浏览器的新模块或现有模块能力实现，不再新建彼此独立的浏览界面。
- `role_animation_preview.tscn`、`enemy_animation_preview.tscn` 和 `skill_effect_calibrator.tscn` 是浏览器内部模块。为兼容既有测试可单独运行，但不作为新增预览功能的入口。
- 新模块应沿用统一交互：对象/动作选择、重播、暂停/继续、朝向、缩放、X/Y 坐标、画布拖拽、方向键微调、恢复/保存、当前帧与来源信息；不适用的控件可以省略，不能用另一套同义控件重复实现。
- 坐标修改必须写回正式运行时配置：角色显示原点使用动画配置的 `visual_nudge`，敌人逐动作使用 `sprite_offset`，技能特效使用现有显示偏移配置；禁止另建只在预览器生效的坐标副本。
- 预览画布应保留主体空间，筛选与参数控件放在侧栏；默认展示可读的代表动作，并支持窗口尺寸变化。
- 预览必须读取正式运行时资源或明确标注的溯源数据，不复制一套只供预览使用的动画配置。涉及素材筛选、去重、命名或删除时仍须先遵守 `sources/ASSET_ORGANIZATION_GUIDE.md` 并更新 `sources/manifests`。
- 命令行可用 `--animation-mode=roles`、`--animation-mode=enemies` 或 `--animation-mode=skills` 打开指定模块；截图和自动化检查也应优先从统一入口进入。

## 素材打包工具

`sprite_packer.py` 位于 `scripts/sprite_packer.py`，将序列帧 PNG 打包为 sprite sheet + JSON 坐标文件。

用法：
```bash
python3 scripts/sprite_packer.py "<输入目录>" ["<输出前缀>"] [列数]
```

- 输入目录：包含序列帧 PNG 的目录
- 输出前缀（可选）：生成 `{前缀}.png` 和 `{前缀}.json`，默认在输入目录下生成 `sprite.png` + `sprite.json`
- 列数（可选）：每行列数，不指定则自动算为接近正方形

JSON 格式：
```json
{
  "frames": {
    "frame_001": { "x": 0, "y": 0, "w": 71, "h": 62 },
    "frame_002": { "x": 71, "y": 0, "w": 71, "h": 62 }
  },
  "meta": {
    "image": "sprite.png",
    "size": { "w": 355, "h": 310 },
    "frameSize": { "w": 71, "h": 62 },
    "columns": 5,
    "rows": 5,
    "frameCount": 25
  }
}
```

注意事项：
- 只支持等大序列帧（所有帧尺寸一致），不支持不等大帧的紧凑打包
- 输入目录下的 PNG 全部参与打包，如果多次运行需清理上一次的 `sprite.png` 避免重复打包
- RGBA 图片保留透明通道

## 造梦西游 1 怪物素材结构

### 当前目录层级（2026-07-22 整理后）

```
assets/extracted/classified/zmxiyou1/怪物/<MXX_名称>/
  ├── 受伤/               ← sprite.png + sprite.json
  ├── 待机/               ← sprite.png + sprite.json（如有子时间轴元件）
  ├── 攻击1/              ← sprite.png + sprite.json（单元件动作）
  ├── 攻击2/              ← 多元件动作保留子目录:
  │   └── 元件XX_YY/sprite.png
  ├── 死亡/
  ├── 移动/
  ├── 特效/               ← 弹道等专属特效（如有）
  └── 共享动作时间轴/     ← 跨动作复用的时间轴（如有）
```
  ├── 移动/
  ├── 特效/               ← 弹道等特效（如有，最多 1 层子目录）
  └── 共享动作时间轴/     ← 跨动作复用的时间轴（如有）
```

### 已执行的整理操作

1. **根时间轴定位帧已删除** — 这些是 Flash 根时间轴的组装快照，不含运行时事件，
   不作为动画播放素材，仅曾用于校准零件位置。2026-07-22 已全部删除（150 个目录）。

2. **完整时间轴中间层已去除** — 原先 `动作/完整时间轴/元件X/sprite.png`，
   现为 `动作/sprite.png`（单元件）或 `动作/元件X/sprite.png`（多元件）。

3. **组成元件 → parts** — 原名 `组成元件/其他/`，已扁平化为 `parts/`，
   存放 SVG 和 PNG 零件图。SVG 和 PNG 互补（矢量图形→SVG，位图→PNG），不是重复格式。

4. **sprite sheet 已 trim** — 逐帧裁剪透明边界后重新打包，节省约 22% 磁盘空间
   （95MB → 75MB）。Trim 后的 JSON 包含每帧的 `ox/oy/cw/ch` 偏移字段。

5. **parts/ 已删除** — 组成元件是 Flash 源文件（SVG/PNG），已烘焙到各动作的
   sprite sheet 中，无需保留。多元件动作中冗余的 character_XXX 子层也已清理
   （复合元件 45ssss_9 已包含全部视觉内容）。

### Godot 集成设计

特效与动画的完整映射、状态机设计和简化策略见：
`sources/manifests/zmxiyou1_godot_integration_design.md`

核心要点：
- **小怪** (13只): 共用 `TrashMonster.tscn` 场景，只换 sprite sheet 和参数
- **Boss**: 独立场景（多阶段攻击 + 专属弹道）
- **光环**: 4 色合并为 1 张 sprite + shader 调色
- **受击特效**: Shader 闪烁，无需素材
- **弹道**: 默认 AnimatedBullet（动画弹道），仅 M14 用 MovingBullet（代码移动）
- **状态机**: idle→walk→attack→hurt→dead 五态，转换规则来自 AS 帧事件

### 动画偏移调整

**所有怪物 sprite_offset 的调整必须在动画浏览器中进行**，禁止在战斗场景或其他地方调整。

启动动画浏览器（敌人模式）：
```bash
godot --animation-mode=enemies scenes/debug/animation_browser.tscn
```

工作流：
1. 左上角怪物下拉选择目标怪物
2. 动作下拉切换动作
3. 方向键微调位置（Shift+方向键 = 10px 步长），或拖拽鼠标
4. 点击"保存坐标"写入对应 profile 的 `sprite_offset`
5. 调整后的 offset 会自动反映到战斗场景中（战斗场景通过 `EnemyAnimationProfile` 读取同一份 offset）

### 实战测试

战斗测试场景：
```bash
godot scenes/stages/zmxiyou1_combat_test.tscn
```

用于验证动画、AI 和碰撞效果，**不在战斗场景中调整动画位置**。

### 相关脚本

| 脚本 | 用途 |
|---|---|
| `scripts/sprite_packer.py` | 序列帧→sprite sheet 打包 |
| `scripts/batch_pack.py` | 批量打包（遍历怪物目录） |
| `scripts/trim_sprites.py` | 裁剪透明像素、重新打包 |
| `scripts/reorganize_monsters.py` | 目录层级整理（一次性工具） |

### 事件数据

怪物帧事件提取自 ActionScript 源码，存储在：
`sources/manifests/zmxiyou1_monster_events.json`

包含每帧的 `action_transition`、`timeline_control`、`cleanup` 等事件类型，
以及攻击参数（power、hitMaxCount、attackBackSpeed 等）。
事件绑定在子时间轴元件上，根时间轴本身通常只有 `stop()`。
