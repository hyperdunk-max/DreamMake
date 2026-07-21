# 《造梦西游1》角色换装渲染审计

生成时间：2026-07-21T01:32:17+08:00

## 结论

造梦1与造梦3的换装核心逻辑相同：角色动作时间轴保持同步，武器和防具使用装备 `showid` 选择对应外观。差别在于造梦1把大量换装零件嵌在一个 `Role_v7.swf` 的多层 MovieClip 中；造梦3更接近独立 body/weapon 图集。因此这里的 PNG 是原 Flash 时间轴导出的换装层或局部零件，不应单独当成完整角色皮肤。

## 原版调用链

1. `BaseHero` 保存 `curClothId` 与 `curWeaponId`，装备变化时从 `zbfj`/`zbwq` 写入 showid。
2. `Role2` 递归找到 `bodyEquip`，使用 `gotoAndStop(curClothId)` 切换防具。
3. `Role_fla` 内的武器与防具选择器继续按 showid（部分高级防具层使用 `showid-2` 或 `showid-3`）切换帧。
4. 动作 MovieClip、身体层和武器层由 Flash 时间轴共同变换，形成最终角色画面。

关键证据位于 `Role_v7/scripts/my/MyEquipObj.as`、`Role_v7/scripts/user/User.as`、`Role_v7/scripts/base/BaseHero.as`、`Role_v7/scripts/export/hero/Role2.as` 与 `Role_v7/scripts/Role_fla/*.as`。

## 与造梦3的对照

- 共同点：都以防具/武器 showid 选择外观，并让身体、武器与动作帧同步。
- 造梦1：`Role_v7.swf` 内嵌多层局部零件，最终角色需要 Flash 时间轴的层级、位移和显隐共同合成。
- 造梦3：角色包已拆为 `Role1v690.swf`、`ROLE1_1.swf`、`ROLE1_EQUIP_1.swf` 等独立资源；当前 Godot 的 `layered_sprite_animator.gd` 也直接使用 Body/Weapon 两个 Sprite2D 和独立 showid atlas。
- 因此机制相同，资源粒度不同。造梦1素材若移植到 Godot，需要先按动作重建多层合成，不能只把单个 selector PNG 当作整套 body atlas。

## 图片位置

- `人物/悟空/待机、移动、攻击…` 与 `人物/唐僧/待机、移动、攻击…`：角色根 MovieClip 导出的完整动作帧，用来观察最终动作轮廓和同步节奏。
- `人物/悟空/换装渲染` 与 `人物/唐僧/换装渲染`：本次整理的原始武器/防具选择器帧，按槽位与 showid 查找。
- 完整动作帧只反映导出时的时间轴状态；原 SWF 没有像造梦3那样为每套装备保存一张完整 body 图集。

## 已整理选择器

| 角色 | 槽位 | SWF 符号 | 原类名 | 选择规则 | 导出帧 |
| --- | --- | ---: | --- | --- | ---: |
| 悟空 | 武器 | 177 | 元件68_121 | showid | 8 |
| 悟空 | 防具 | 143 | 元件54_112 | showid | 6 |
| 悟空 | 防具 | 152 | 元件56_115 | showid | 6 |
| 悟空 | 防具 | 160 | 元件55_118 | showid | 6 |
| 悟空 | 防具 | 186 | 元件52_128 | showid | 6 |
| 唐僧 | 武器 | 723 | 元件26_11 | showid | 8 |
| 唐僧 | 防具 | 737 | 元件3_23 | showid-3 | 3 |
| 唐僧 | 防具 | 741 | 元件4_24 | showid-3 | 3 |
| 唐僧 | 防具 | 745 | 元件2_25 | showid-3 | 3 |
| 唐僧 | 防具 | 749 | 元件1_26 | showid-3 | 3 |
| 唐僧 | 防具 | 755 | 元件13_27 | showid | 6 |
| 唐僧 | 防具 | 810 | 元件5_31 | showid-2 | 3 |
| 唐僧 | 防具 | 856 | 元件7_44 | showid-2 | 3 |
| 唐僧 | 防具 | 903 | 元件8_53 | showid-2 | 3 |
| 唐僧 | 防具 | 987 | 元件10_74 | showid-2 | 3 |

## showid 与装备名称

### 悟空 · 武器

| showid | 装备 | 代码 |
| ---: | --- | --- |
| 1 | 原始/未在装备表命名 | `—` |
| 2 | 粗糙的行者棍、普通的行者棍 | `ccxzg、ptxzg` |
| 3 | 优秀的行者棍、精良的行者棍 | `yxxzg、jlxzg` |
| 4 | 天煞月戟 | `tsyj` |
| 5 | 如意金箍棒 | `ryjgb` |
| 6 | 青龙刀 | `qld` |
| 7 | 家传宝剑 | `jcbj` |
| 8 | 童年的冰糖葫芦 | `tndbthl` |

### 悟空 · 防具

| showid | 装备 | 代码 |
| ---: | --- | --- |
| 1 | 大圣战铠 | `dszk` |
| 2 | 粗糙的行者服、普通的行者服 | `ccxzf、ptxzf` |
| 3 | 优秀的行者服、精良的行者服 | `yxxzf、jlxzf` |
| 4 | 地煞猿甲 | `dsyj` |
| 5 | 玄武甲 | `xwj` |
| 6 | 血海魔甲 | `xhmj` |

### 唐僧 · 武器

| showid | 装备 | 代码 |
| ---: | --- | --- |
| 1 | 原始/未在装备表命名 | `—` |
| 2 | 粗糙的松木杖、普通的松木杖 | `ccsmz、ptsmz` |
| 3 | 优秀的松木杖、精良的松木杖 | `yxsmz、jlsmz` |
| 4 | 地煞权杖 | `dsqz` |
| 5 | 白虎杖 | `bhz` |
| 6 | 血海邪皇 | `xhxh` |
| 7 | 九环禅杖 | `jhcz` |
| 8 | 童年的拨浪鼓 | `tndblg` |

### 唐僧 · 防具

| showid | 装备 | 代码 |
| ---: | --- | --- |
| 1 | 锦襕袈裟 | `zljs` |
| 2 | 粗糙的袈裟、普通的袈裟 | `ccjs、ptjs` |
| 3 | 优秀的袈裟、精良的袈裟 | `yxjs、jljs` |
| 4 | 家传衣裳 | `jcys` |
| 5 | 麒麟袍 | `qlp` |
| 6 | 天煞羽袍 | `tsyp` |

## ���录说明

素材按 `人物/角色/换装渲染/武器或防具/showid_XX/part_符号号.png` 整理。`part_符号号` 保留原 SWF 追溯信息；同一 showid 下的多个防具 part 属于不同身体层或动作姿态，由动作时间轴按需选择和组合，并不表示同一时刻全部叠加。

逐张素材、原始路径、选择规则与装备名称见 `sources/manifests/zmxiyou1_role_rendering.json`。
