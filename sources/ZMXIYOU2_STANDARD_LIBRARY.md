# 《造梦西游2》标准素材库

生成时间：2026-07-21T20:28:20+08:00

完整溯源库 `assets/extracted/full/zmxiyou2` 保留 35,444 个文件且未做精简删除。
标准分类库保留 26,558 项素材，使用 NTFS 硬链接，不重复占用文件数据。

## 本轮精简

- 排除 4,131 个只应存在于溯源层的源码、符号表和结构文件。
- 排除 1,611 张逐图验证为全透明的 PNG。
- 6 组数值驱动时间轴仅保留完整填充图，排除 477 张中间帧。
- 合并 2,667 个来自其他符号上下文的字节完全相同副本。
- 保留 8,071 个同一动画时间轴内的重复帧，等待播放节奏核验。

## 数值条标准项

| 功能 | 原帧数 | 保留帧 | 标准路径 | Godot 替代 |
| --- | ---: | ---: | --- | --- |
| `energy` | 100 | 100 | `assets/extracted/classified/zmxiyou2/UI/HUD/energy_slider.png` | Godot TextureProgressBar or clipped TextureRect; step = 1 |
| `hp` | 101 | 1 | `assets/extracted/classified/zmxiyou2/UI/HUD/hp_slider.png` | Godot TextureProgressBar or clipped TextureRect; step = 1 |
| `mp` | 101 | 1 | `assets/extracted/classified/zmxiyou2/UI/HUD/mp_slider.png` | Godot TextureProgressBar or clipped TextureRect; step = 1 |
| `exp` | 101 | 1 | `assets/extracted/classified/zmxiyou2/UI/HUD/exp_slider.png` | Godot TextureProgressBar or clipped TextureRect; step = 1 |
| `backpack_exp` | 30 | 30 | `assets/extracted/classified/zmxiyou2/UI/背包/backpack_exp_slider.png` | Godot TextureProgressBar or clipped TextureRect; step = 1/30 |
| `magic_exp` | 50 | 50 | `assets/extracted/classified/zmxiyou2/UI/背包/magic_exp_slider.png` | Godot TextureProgressBar or clipped TextureRect; step = 1/50 |

## 尚未删除

- 尚未完成视觉等价比对的 PNG/SVG/JPG 跨格式副本。
- 同一时间轴内可能承担停顿节奏的重复动画帧。
- 尚未通过 SWF 引用图唯一归属的匿名 Timeline/Shape。

逐文件保留、删除和别名证据见 `sources/manifests/zmxiyou2_standard_cleanup.json`。
