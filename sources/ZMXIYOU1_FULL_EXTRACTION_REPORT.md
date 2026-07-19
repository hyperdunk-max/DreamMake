# 《造梦西游1》完整拆包索引

生成时间：2026-07-19T15:26:21+08:00

已完整导出 **10 个容器**、**19,596 个文件**（691.23 MB）。
导出覆盖主程序、4399 外壳、角色、三套怪物、公共 UI、背包和音乐，并递归拆出了外壳内嵌的 4399 动画。
当前主程序 `loader/Aloader.as` 的有效加载列表与这 7 个动态包完全一致；旧版本文件名仅存在于资源包附带的历史 Loader 副本中。

## 手工整理入口

- 完整导出目录：`assets/extracted/full/zmxiyou1`
- 机器索引：`sources/manifests/zmxiyou1_full_extraction.json`
- 字节级重复文件清单：`sources/manifests/zmxiyou1_duplicate_files.json`
- 原始 SWF：`sources/raw/zmxiyou1/`
- 标准化 SWF：`sources/decoded/zmxiyou1/`

`assets/extracted/.gdignore` 会阻止 Godot 扫描整个拆包目录；整理后的成品请复制到 `assets/selected/zmxiyou1/`。

## 容器

| 容器 | 路径 | 文件数 | 大小 |
| --- | --- | ---: | ---: |
| Music | `assets/extracted/full/zmxiyou1/audio/Music` | 57 | 2.93 MB |
| Role_v7 | `assets/extracted/full/zmxiyou1/characters/mixed_packages/Role_v7` | 3,834 | 54.72 MB |
| Monster_v1 | `assets/extracted/full/zmxiyou1/monsters/Monster_v1` | 2,294 | 111.95 MB |
| Monster2_v4 | `assets/extracted/full/zmxiyou1/monsters/Monster2_v4` | 5,606 | 122.79 MB |
| Monster3_v3 | `assets/extracted/full/zmxiyou1/monsters/Monster3_v3` | 1,233 | 49.45 MB |
| OtherMat_v9 | `assets/extracted/full/zmxiyou1/shared/OtherMat_v9` | 3,644 | 78.55 MB |
| backpack_v2 | `assets/extracted/full/zmxiyou1/shared/backpack_v2` | 767 | 9.63 MB |
| main_game | `assets/extracted/full/zmxiyou1/shared/main/main_game` | 2,112 | 258.99 MB |
| portal_loader | `assets/extracted/full/zmxiyou1/shared/portal_loader/portal_loader` | 46 | 2.14 MB |
| portal_4399_gif | `assets/extracted/full/zmxiyou1/shared/portal_embedded/4399_gif` | 3 | 81.66 KB |

## FFDec 分类

| 目录 | 文件数 | 大小 |
| --- | ---: | ---: |
| `binaryData` | 3 | 1.96 MB |
| `buttons` | 188 | 1.38 MB |
| `fonts` | 7 | 457.42 KB |
| `frames` | 11 | 45.15 KB |
| `images` | 976 | 51.24 MB |
| `morphshapes` | 1 | 1.54 KB |
| `scripts` | 1,287 | 4.91 MB |
| `shapes` | 2,512 | 165.55 MB |
| `sounds` | 28 | 2.92 MB |
| `sprites` | 14,542 | 462.76 MB |
| `symbolClass` | 9 | 12.09 KB |
| `texts` | 32 | 177.00 B |

常用整理顺序：先看 `symbolClass/` 和 `scripts/` 确认语义，再到 `sprites/`、`frames/`、`images/` 选成品；音效位于 `sounds/`，文本位于 `texts/`。

## 去重

检测到 2,166 组字节完全一致的文件，理论可回收 196.39 MB。
本次仅生成清单，不自动删除，避免破坏 FFDec 的符号/帧目录关系。你完成挑选后，我可根据整理目录再次安全去重。
