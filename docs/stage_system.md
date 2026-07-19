# 关卡与小怪系统

当前运行入口是 `scenes/stages/zmxiyou1_stage_1.tscn`。造梦西游一只作为首个美术来源，运行层使用与版本无关的资源类型，因此后续造二、造三或其他版本不需要复制关卡控制代码。

## 数据关系

- `ActorProperty`：所有角色、普通怪、Boss 共用的属性模型。
- `PropertyActor2D`：玩家和小怪共同继承的 2D 战斗单位基类，提供统一属性访问契约。
- `EnemyDefinition`：配置怪物名称、来源版本、属性、贴图、缩放、碰撞范围和 Boss 标记。
- `EnemySpawnDefinition`：配置出生标识、位置、数量、阵型间距和延迟。
- `StageDefinition`：配置地图贴图、地面、玩家出生点、怪物出生表和结束条件。
- `StageEndCondition`：可扩展的结束条件策略；当前第一关使用 `BossDefeatedCondition`。
- `StageController`：读取配置、生成怪物、收集死亡事件并判断关卡结束，不包含具体关卡数据。

## 添加关卡

1. 为新怪物创建 `EnemyDefinition` 资源；属性使用 `ActorProperty` 子资源。
2. 创建若干 `EnemySpawnDefinition`，为每组敌人指定稳定且唯一的 `spawn_id`。
3. 创建 `StageDefinition`，设置地图、地面、出生点和结束条件。
4. 将 `StageController` 放进场景并赋予该资源。控制器会通过信号发布开始、出生、死亡、Boss 出生和完成事件。

## 扩展结束条件

新建继承 `StageEndCondition` 的 Resource 脚本，实现：

```gdscript
func is_satisfied(active_enemies: Dictionary, defeated_spawn_ids: Array[StringName]) -> bool:
    return false
```

例如可以继续添加“全灭”“生存计时”“到达出口”“保护目标”或多个条件组合，而无需修改 `StageController`。

## 造一素材提取

`tools/extract_swf_resources.js` 可解析造一 110 字节轮换包、SWF 位图、符号类名和内嵌主程序。主程序将角色编号 19 注册为符号类 `"1"`，因此选取同编号的雪山图作为第一张地图，不依赖文件名猜测。JPEG3 的独立透明通道使用 `tools/compose_swf_jpeg_alpha.ps1` 合成。最终选用的五个素材及其 SWF 位图编号、源文件哈希和成品哈希记录在 `assets/selected/zmxiyou1/provenance.json`。

未筛选的研究导出位于被忽略的 `assets/extracted/`，并通过 `.gdignore` 阻止 Godot 导入；只有 `assets/selected/` 下的成品进入运行项目。
