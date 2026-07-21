# 原始素材工作区

此目录用于记录来源和保存本地研究材料。原始 SWF 放在 `raw/`，提取结果放在
`../assets/extracted/<game>/`。这两个目录默认不纳入版本控制，避免把受版权保护的
原作文件意外提交到代码仓库。

已确认的 4399 入口（2026-07-14）：

| 版本 | 页面入口 | 实际 SWF |
| --- | --- | --- |
| 造梦西游 1 | `https://sbai.4399.com/4399swf/upload_swf/ftp5/hanbao/20110624/3/v25928.htm` | 同目录 `v25928.swf` |
| 造梦西游 2 | `https://sbai.4399.com/4399swf/upload_swf/ftp6/hanbao/20110927/4/v25928.htm` | 同目录 `v25928.swf` |
| 造梦西游 3（页面入口） | `https://www.4399.com/flash/zmhj.htm?g=3` | 页面脚本指向 `sda`，该镜像当前是错误动画 |
| 造梦西游 3（可用镜像） | `https://sbai.4399.com/4399swf/upload_swf/ftp7/hanbao/20120107/6/v260714.swf` | 真实外层 SWF，SHA-256 记录在 `manifests/zmxiyou3.json` |

注意：`sda.4399.com` 当前返回的 23 KB SWF 是 4399 的“访问错误”动画，并非游戏加载器；
同一路径的 `sbai.4399.com` 仍可取得真实文件。两者不能混用。

一、二代入口 SWF 均为 4399 外壳，内含真正的 `940×590 / 24 FPS` 游戏主 SWF。
游戏主 SWF 又会从同目录加载下列素材包：

- 一代：`Role_v7`、`Monster_v1`、`Monster2_v4`、`Monster3_v3`、`OtherMat_v9`、
  `backpack_v2`、`Music`
- 二代：`OtherMat_v10`、`Role_v6`、`Music`、`Common_v7`、`backpack_v5`，以及按关卡
  延迟加载的关卡包

部分素材包会把文件开头的一小段字节循环移位以阻止直接打开。研究副本在
`decoded/` 中还原为标准 SWF：一代通常还原前 110 字节（`100..109 + 0..99`），
二代还原前 325 字节（`300..324 + 0..299`）。

三代已确认的首批资源包：

- 核心：`MagicWeaponv1240`、`Commonv3720`、`petEIconv1450`、`EIconv3420`、
  `GameMapv3870`、`OtherMatv3570`、`GameBackGroundv3870`
- 角色：`Role1v690`（技能/子资源）以及按装备动态加载的 `ROLE1_1`、
  `ROLE1_EQUIP_1`
- 第一阶段：`stageInfov1620`、`stageCommonv1270`、`0v1150`、`Monster179`、
  `24v1180`

三代核心和关卡包遵循前 325 字节还原规则；`Role*`、`Monster*`、宠物和装备 SWF
按加载器逻辑直接读取，不做移位还原。

## 素材整理规范

造 1、造 2、造 3 的提取、分类、去重、命名、删除和运行时选材统一遵循
[`ASSET_ORGANIZATION_GUIDE.md`](ASSET_ORGANIZATION_GUIDE.md)。规范涵盖真实动画、数值驱动时间轴、
语义枚举、组合零件、文本生成和多格式去重；原始 SWF 与完整拆包始终保留用于溯源。
