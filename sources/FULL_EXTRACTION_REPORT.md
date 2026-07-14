# 《造梦西游》1–3 全资源提取报告

> 生成时间：2026-07-14T16:34:58+08:00

## 结论

已成功导出 **243 个有效 SWF 容器**，共 **119,360 个文件**（**4.45 GB**）。导出失败和超时均为 0。

资源来自客户端主程序、网页外层加载器以及客户端代码实际发现的动态 SWF 地址。远端共检查 461 个候选地址，其中 237 个仍可取得；224 个返回 HTTP 404，未冒充为已提取资源，详单见 `sources/manifests/unavailable_resources.json`。造 3 页面旧 `sda` 地址返回的 23 KB 错误提示动画不计入游戏资源。

## 各代汇总

| 游戏 | 有效容器 | 导出文件 | 导出大小 |
| --- | --- | --- | --- |
| 造梦西游 1 | 9 | 19,593 | 691.15 MB |
| 造梦西游 2 | 19 | 35,444 | 1.12 GB |
| 造梦西游 3 | 215 | 64,323 | 2.65 GB |

## FFDec 类型分类

| 类型目录 | 文件数 | 大小 |
| --- | --- | --- |
| binaryData | 11 | 8.19 MB |
| buttons | 2,240 | 23.16 MB |
| fonts | 54 | 13.30 MB |
| frames | 246 | 1.50 MB |
| images | 9,330 | 636.87 MB |
| morphshapes | 16 | 27.84 KB |
| scripts | 16,797 | 94.38 MB |
| shapes | 16,442 | 1.25 GB |
| sounds | 185 | 7.86 MB |
| sprites | 73,208 | 2.43 GB |
| symbolClass | 243 | 119.65 KB |
| texts | 588 | 4.60 KB |

每个资源包内部保留 FFDec 的标准类型目录；空目录也保留，因此即使某包没有声音或精灵，目录结构仍一致。

## 业务目录包数

| 游戏 | 业务分类 | 容器数 |
| --- | --- | --- |
| 造梦西游 1 | audio | 1 |
| 造梦西游 1 | characters | 1 |
| 造梦西游 1 | monsters | 3 |
| 造梦西游 1 | shared | 4 |
| 造梦西游 2 | audio | 1 |
| 造梦西游 2 | characters | 1 |
| 造梦西游 2 | shared | 6 |
| 造梦西游 2 | stages | 11 |
| 造梦西游 3 | audio | 13 |
| 造梦西游 3 | characters | 81 |
| 造梦西游 3 | environments | 2 |
| 造梦西游 3 | magic_weapons | 1 |
| 造梦西游 3 | monsters | 12 |
| 造梦西游 3 | pets | 17 |
| 造梦西游 3 | shared | 19 |
| 造梦西游 3 | stages | 52 |
| 造梦西游 3 | ui | 18 |

## 角色多套资源

造 3 的角色外观和武器按 `角色/部位/showid/资源包/类型` 独立保存，便于后续人工选择；造 1、造 2 的角色素材由原版合并在单一 Role 包内，因此保留在 `characters/mixed_packages`，没有擅自拆散符号依赖。

| 游戏 | 角色 | 资源部位 | 套数 | showid / 包 |
| --- | --- | --- | --- | --- |
| 造梦西游 1 | 混合角色包 | package | 1 | Role_v7 |
| 造梦西游 2 | 混合角色包 | package | 1 | Role_v6 |
| 造梦西游 3 | 猪八戒 | body | 7 | 0, 1, 2, 4, 5, 9, 11 |
| 造梦西游 3 | 猪八戒 | weapon | 10 | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 |
| 造梦西游 3 | 混合角色包 | package | 5 | Role1v690, Role2v3550, Role3v690, Role4v3550, RoleSkillInterfacev3550 |
| 造梦西游 3 | 沙僧 | body_arrow | 8 | 0, 1, 2, 3, 4, 5, 9, 11 |
| 造梦西游 3 | 沙僧 | body_shovel | 8 | 0, 1, 2, 3, 4, 5, 9, 11 |
| 造梦西游 3 | 沙僧 | weapon | 10 | 0, 1, 2, 3, 4, 6, 7, 8, 9, 10 |
| 造梦西游 3 | 唐僧 | body | 8 | 0, 1, 2, 3, 4, 5, 9, 11 |
| 造梦西游 3 | 唐僧 | weapon | 8 | 0, 1, 2, 3, 5, 7, 8, 9 |
| 造梦西游 3 | 悟空 | body | 7 | 0, 1, 2, 3, 4, 9, 11 |
| 造梦西游 3 | 悟空 | weapon | 10 | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 |

## 目录与索引

- 全部导出资源：`assets/extracted/full/`
- 完整机器索引：`sources/manifests/full_extraction_index.json`
- HTTP 404 候选详单：`sources/manifests/unavailable_resources.json`
- 下载审计：`.tools/full_resource_report.json`
- 导出审计：`.tools/full_export_report.json`
- 原始与解码 SWF：`sources/raw/`、`sources/decoded/`

重新生成索引：

```powershell
& '.tools\python-portable\python.exe' 'tools\build_full_resource_index.py'
```
