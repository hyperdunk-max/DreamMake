# 《造梦西游3》素材初步整理

生成时间：2026-07-21T17:31:50+08:00

本轮采用唯一归档策略：分类过程只移动文件，不复制、不建立硬链接。
原拆包目录 `assets/extracted/full/zmxiyou3` 已清空并移除；唯一分类库位于 `assets/extracted/classified/zmxiyou3`。

## 分类统计

| 分类 | 文件数 |
| --- | ---: |
| `UI` | 4,799 |
| `人物` | 5,848 |
| `公共元件` | 7,954 |
| `场景与地图` | 33,163 |
| `宠物` | 5,288 |
| `怪物` | 2,065 |
| `法宝` | 4,838 |
| `音频` | 211 |

## 去重处理

现有角色精选区中有 157 个文件原为逐字节复制。
逐一校验 SHA-256 后，保留 `assets/selected/zmxiyou3` 中的可用成品，删除分类库中的对应源位置副本；
原路径和校验值保留在 `playable_roles_manifest.json` 与机器审计中。

## 当前边界

本轮完成包级初分，并保留 FFDec 的 images、sprites、scripts 等内部结构，避免破坏符号证据。
动作标签、怪物原作名、关卡名和匿名元件归属将在后续精分阶段依据源码与 SWF 引用链继续整理。

机器审计：`sources/manifests/zmxiyou3_unique_organization.json`

## 进度条精简

此前的进度条精简已按用户要求回退，原 705 张时间轴 PNG 均已恢复。
历史清理与回退记录见 `sources/manifests/zmxiyou3_progress_bar_cleanup.json` 和
`sources/manifests/zmxiyou3_progress_bar_rollback.json`。
