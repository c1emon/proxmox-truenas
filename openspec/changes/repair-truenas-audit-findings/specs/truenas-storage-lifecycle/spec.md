## Purpose

规定 PVE Native 与 Patch 存储调用中的卷、快照及 iSCSI 映射行为，确保数据对象身份、错误传播和远程执行边界一致，防止因不完整查询或部分成功而操作错误对象。

## ADDED Requirements

### Requirement: Storage callbacks expose failures
所有受支持的变更回调 MUST 只在所需步骤完成后返回成功；失败的删除、调整大小、克隆、模板转换、重命名及快照操作 SHALL 向 PVE 报错。读取失败不得返回伪造的零大小或空成功结果。

#### Scenario: Backend mutation or size query fails
- **WHEN** 后端返回错误或结果未知，包括删除重试全部失败
- **THEN** PVE 收到失败，不收到成功卷名、成功大小或正常完成状态；后续依赖步骤不执行

#### Scenario: Snapshot resize requested
- **WHEN** PVE 请求调整指定快照大小
- **THEN** 返回明确不支持，不忽略快照参数后调整当前卷

### Requirement: Validated LUN identity
构造 iSCSI 路径或 QEMU 参数之前 MUST 验证目标、extent、映射身份与非负整数 LUN ID；LUN 0 SHALL 有效，缺失或非法 ID SHALL 失败。枚举失败不得被解释成空 target。

#### Scenario: Missing identifier versus zero
- **WHEN** 映射缺少 lunid、包含非法值，或合法值为 0
- **THEN** 前两种拒绝生成路径和 QEMU 参数，后一种正常生成 LUN 0

### Requirement: Conflict-safe allocation and bounded compensation
分配 SHALL 以服务端唯一约束及有限冲突处理避免同一 target 的重复 LUN；多步骤创建、删除与重建 MUST 检查每步结果。明确失败时只补偿本次创建且身份可确认的资源；结果未知时先查询对象状态，不能盲删或重建已有对象。

#### Scenario: Concurrent mapping allocation
- **WHEN** 两个操作看到相同空闲 LUN，或服务端返回分配冲突
- **THEN** 冲突操作重新查询并有限重试或明确失败，不占用其他卷映射，也不遗留本次可确认的孤立 extent

#### Scenario: Intermediate deletion or creation fails
- **WHEN** 映射删除失败，或 extent 创建成功而映射创建明确失败
- **THEN** 前者停止依赖删除，后者只清理本次 extent；不能把后一步成功覆盖前一步失败

### Requirement: Stable mappings across metadata changes
卷重命名、模板转换、resize 后的必要映射更新 SHALL 保持卷与 extent 对应关系，并保留已有 LUN 身份；无法安全完成时 MUST 明确失败并报告可恢复状态，不以固定 sleep 作为成功证据。

#### Scenario: Rename with an existing mapping
- **WHEN** 已映射卷从旧名称改为新名称
- **THEN** 成功后新名称可访问正确卷，LUN 身份保持稳定；中途失败不会报告新卷成功可用

### Requirement: Consistent volume and snapshot names
克隆返回值 SHALL 保留 PVE 所需父卷关系；所有快照创建、删除、查询、回滚入口 MUST 把 PVE 编码卷名解析为实际 dataset。快照信息 SHALL 以快照短名索引，并按实际快照顺序判断回滚阻挡；卷列表 MUST 限定在配置 dataset 的路径边界内。

#### Scenario: Clone snapshot round trip
- **WHEN** 对 `base-100-disk-0/vm-101-disk-0` 创建、列出、删除或回滚快照 `s1`
- **THEN** 操作同一实际克隆 dataset，列表以 `s1` 为键，不拼出包含父卷编码的错误 dataset

#### Scenario: Similar pool prefix
- **WHEN** 配置 pool 为 `tank/pve`，同时存在 `tank/pve-other` 下的卷
- **THEN** 后者不会被当成本存储的卷

### Requirement: Remote-only execution boundary
Native 插件 MUST 不广告或执行依赖 PVE 本机 ZFS 数据集的继承导入/导出及其他未支持回调；受支持能力与实际实现 SHALL 一致。Patch 路由到未实现方法时 SHALL 返回清晰的不支持错误，不产生未定义函数异常。

#### Scenario: Native stream import or export
- **WHEN** PVE 查询流格式或调用 Native 导入/导出
- **THEN** 返回无受支持格式或明确不支持，且不执行本机 `zfs send`、`zfs recv` 或其他针对远端池名的本机写命令
