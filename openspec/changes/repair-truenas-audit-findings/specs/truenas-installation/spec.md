## Purpose

约束 TrueNAS 插件安装、补丁生成和 PVE 界面配置行为，确保不支持的输入在系统变更前被拒绝，安装失败可见，且文档清楚区分已验证版本与尚未完成的真实部署验证。

## ADDED Requirements

### Requirement: Validated installation inputs
安装 SHALL 在修改系统文件前检查参数、必要依赖、版本与所选模式资源；未知参数、不支持版本或缺失补丁 MUST 立即非零退出。Native 与 Patch 模式 SHALL 有明确互斥行为。

#### Scenario: Unknown option or unsupported version
- **WHEN** 输入未知参数、版本检测失败或 patch 版本无对应资源
- **THEN** 非零退出，不循环等待，不修改系统文件或重启服务

### Requirement: Failure-aware deployment
关键复制、恢复、补丁和依赖安装失败 MUST 终止后续安装并返回非零，不得重启服务或报告成功；首次安装缺少可选旧备份 SHALL 按明确的首次安装流程处理。成功安装 SHALL 保留原有 corosync、pve-cluster、pvedaemon、pvestatd、pveproxy 重启列表与顺序。缩小重启范围 SHALL 仅记为后续考虑的注释，待真实 PVE 验证后单独决定。

#### Scenario: Copy or patch failure
- **WHEN** 关键复制失败或补丁不能应用
- **THEN** 立即停止并指明失败步骤，不执行成功收尾及服务重启

### Requirement: Reliable patch generation
补丁生成 SHALL 验证工作目录和输入文件，将正常差异与执行错误区分；生成错误 MUST 非零退出且不能覆盖可用补丁为不完整产物。

#### Scenario: Missing source versus normal difference
- **WHEN** 输入文件缺失或比较工具执行失败，或者两个合法输入仅有内容差异
- **THEN** 前者保留旧产物并失败，后者可生成有效补丁并成功

### Requirement: UI references and documented support
PVE 8/9 Patch UI SHALL 能切换 provider 而不触发缺失引用异常，正确清理不适用字段。文档 SHALL 分开陈述 Native 与 Patch 支持范围、既有 TLS/凭据限制及后置触发条件、API viewer 补丁状态、实际验证版本和未验证环境；不得将仅按主版本选文件等同于所有小版本兼容，不要求本次迁移凭据或证书。

#### Scenario: Provider switch and compatibility lookup
- **WHEN** 用户在 PVE 8/9 Patch UI 切离 TrueNAS 并按安装文档选择版本
- **THEN** 表单无引用异常，说明能确定适用补丁和 API viewer 支持状态，未验证版本不被声称已通过部署
