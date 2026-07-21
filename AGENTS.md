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

