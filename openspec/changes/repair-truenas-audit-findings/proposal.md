## Why

2026-09-08 重新审计发现，TrueNAS 客户端可能把超时或失败解释为成功，Native/Patch 存储入口还有 LUN、卷命名、远程执行边界和安装失败处理缺陷。这些问题会造成 PVE 状态与远端存储不一致；需要在继续使用相关写操作前完成定向修复。证据与编号见 `audit/2026-09-08/AUDIT.md`。

## What Changes

- 统一传输、解析和 API 失败语义；保留合法的 null/false/0 和字符串类型，关联请求与响应。
- 修正连接期限、心跳重连、WebSocket 帧与缓存处理，禁止盲目重放结果未知的写请求。
- 修正 LUN 查找、分配冲突、多步骤变更的失败隔离与有限补偿，保持稳定映射及卷/快照命名契约。
- **必要的行为收敛**：只拒绝 Native 误用本机 ZFS 的危险导入/导出路径，避免用远端池名操作本机同名数据集；不扩大为禁用全部复制、备份或迁移功能。
- 保留现有凭据存储与读取方式、TLS 验证策略和历史 SSL=0 的实际 TLS 行为；F09、F10、F25 后置，不因本次修复自动迁移配置、要求更换证书或切换明文。
- 隔离不同凭据、传输配置及进程的客户端状态，修复日志秘密泄露；不新增私有凭据文件或迁移 hooks。
- 修复 PVE 8/9 UI 引用、部署/构建脚本失败与版本边界，统一文档补丁的支持状态。
- 以已有故障脚本为基础建立分组回归，更新兼容性与验收限制；不增加生产资格、发布演练或逐对象证据系统。

## Capabilities

### New Capabilities

- `truenas-rpc-client`: RPC 结果、错误、协议、超时与重连契约。
- `truenas-storage-lifecycle`: Native/Patch 存储入口、LUN 生命周期、卷快照及远程边界。
- `truenas-connection-security`: 现有连接配置兼容、日志秘密保护与连接缓存隔离。
- `truenas-installation`: 安装、补丁生成、界面引用及兼容性说明。

### Modified Capabilities

无。当前 `openspec/specs/` 尚无主规格，本次为现有行为建立明确合同。

## Impact

涉及 `perl5/TrueNAS/{Client,Helpers}.pm`、Native `TrueNASPlugin.pm`、Patch `LunCmd/TrueNAS.pm`、PVE 8/9 ZFS/UI 补丁、`deploy.sh`、`build.sh`、README 与审计回归脚本。不新增运行时服务、不修改真实 TrueNAS 数据、不部署到 PVE 或发布包。本轮只记录规划；后续按用户确认的独立分支流程向上游逐组提交 PR。

本 change 当前只完成规划。`fix/audit-2026-09-08` 保留为审计与规划分支；实施按 [上游 PR 流程与拆分](upstream-pr-workflow.md) 另建各组修复分支，遵守 apply 前的分支检查与创建/切换确认规则，须在用户后续明确要求 apply 后开始；所有实施任务保持未完成。实际 PVE worker、iSCSI I/O 与 TrueNAS 联调资格另行授权，本地/隔离测试不冒充该资格。

用户已明确：非必要的破坏性修复先不做。F09/F10/F25 作为未修复风险保留，不进入本 change 的必做任务；以后有实际安全要求或另获升级迁移授权时再提案。必要正确性修复不得顺带改写已有卷标识、重建在用 extent 或收窄无关能力。
