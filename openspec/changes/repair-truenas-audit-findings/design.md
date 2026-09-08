## Context

见 proposal 的 Why 和 `audit/2026-09-08/AUDIT.md` 的 F01–F28。客户端约 993 行，Native 585 行，LunCmd 252 行；共同依赖同步 Perl WebSocket/JSON-RPC。Native 继承本机 ZFSPoolPlugin，Patch 使用 PVE 8/9 补丁。仓库没有主规格或正式回归入口，已有 36+3+4 条故障断言不能当成修复验收。

本轮用户只授权审计与规划，不修改代码。未来按 1→2→3→4→5 阶段执行并提交；同一 Client 文件不并发分配多个写作者。

## Goals / Non-Goals

**Goals:** 用现有依赖和局部辅助函数恢复可观察错误、对象身份与实际能力合同；测试按同源风险分组，保持一次阶段提交可评审。

**Non-Goals:** 不更换协议栈、不实现通用事务/分布式锁/远程 ZFS 流服务、不扩展 TrueNAS/PVE 版本矩阵、不做真实磁盘或发布资格认证、不对历史报告做文本复原。

## Decisions

### 1. 保持现有调用风格，明确每次请求状态

保留 request 返回业务 result、has_error 表达失败的内部风格，新增最小的请求成功/结果未知信息，解决 undef 既可能是合法 null 又可能是传输失败的问题。每次调用开始清理陈旧 result/error，解析/发送/接收错误统一进入失败路径。具体 zfs/iscsi 包装器检查方法预期结果形状；PVE mutating callbacks 在失败时 die，不依靠任意结果的 truthiness。

拒绝“所有 undef 都失败”及“null 改 true”方案：前者误伤合法方法，后者改变数据。JSON-RPC code/message 与 DDP error 都归一化为不含秘密的诊断；错误处理接受字符串而不盲目解引用。类型转换仅在 volsize/lunid 等已知字段发生。

### 2. 同步连接、单个在途请求、统一期限

维持单连接同步请求，不增加并发调度器。连接、握手、写入和当前请求使用可传递的截止时间；完整写循环处理短写/可重试 errno。接收先排空 frame，再等待 socket；Ping/Pong/Close 与业务消息分离，关联 JSON-RPC/DDP ID，通知/异号消息不完成当前请求。

握手失败或心跳失败重置 socket/auth/frame/result/target-cache。max_retries 定义为连接建立的额外重试上限，所有 endpoint 尝试消耗同一总预算/期限；不得为每条通知重新开始计时。已经发送且无确定响应的写操作不自动重放，交由操作层查询资源状态。

### 3. 使用既有安全机制，不建立秘密管理系统

SSL 默认开启并验证证书和主机名，系统 CA 为信任来源；管理员可将内部 CA 安装到系统信任库，不默认新增 insecure 或任意 CA 配置字段。显式 SSL=0 保留历史意图，文档说明其明文风险，验证失败不降级。

已核对官方 PVE 8 `stable-8` 提交 `9aab8f6f52b314fda5e2aceef6472ffd21b7d5b3` 与 PVE 9 `master` 提交 `7c6a03839920d4939a8ae725a2b0ef91c0cbc6c9` 的 Plugin/API2 Storage Config 合同（源码链接见审计报告）。两者都先 extract_sensitive_params，再向 on_add_hook/on_update_hook 传敏感值；PVE 9 API >=13 改调 on_update_hook_full，默认适配旧 on_update_hook。

Native 与 Patch 的 plugindata 显式声明 truenas_password/truenas_apikey。沿用官方 PBS 模式：on_add_hook/on_update_hook 将值写入 `/etc/pve/priv/storage/` 下按 storeid 隔离的私有文件，exists 才更新、显式 undef 删除，on_delete_hook 清理，权限按私有凭据要求设置。ZFS Patch 只对 TrueNAS provider 操作这些文件，保留其他 provider 原有 hooks。PVE 9 需要完整 delete 上下文时覆盖 on_update_hook_full；旧 hook 仍支持 PVE 8。

运行时必须把 storeid 传到客户端初始化路径，由私有文件读取凭据，放入短生命周期配置副本；不能只写标记导致 Client 收不到密钥，也不向共享 `$scfg` 或普通输出回填秘密。现有明文配置在有锁的配置更新路径迁移到私有文件并移除旧字段，读取兼容仅限迁移期；不新增外部秘密管理依赖。实际文件读写用临时目录替身验证，不在开发机写 `/etc/pve`。

缓存可直接比较私有配置元组（endpoint、TLS、认证内容）和 PID，不必生成凭据 hash/manifest。配置改变、初始化失败或 fork 时废弃旧状态；子进程只关闭自身描述符，不向父进程使用的连接发送 Close。日志默认只记方法、ID、错误类别；不尝试用正则可靠脱敏所有未知 RPC 载荷。

### 4. 按操作定义有限补偿与状态查询

create/clone 记录本次明确创建的 zvol、extent、mapping；后续明确失败则逆序清理这些已确认对象。超时等结果未知先用目标 dataset/path/target 查询，确认身份一致才补偿或有限重试；无法确认时报告残留和恢复建议，不动已有同名对象。

delete 每步完成才继续；前一步失败不被后一步清除。LUN 枚举需要有效 target 和列表；mapping create 的明确冲突触发有限重查，不使用固定 sleep 互斥或新分布式锁。实际上限在 Client 一个位置表达。rename/template/必要的 resize 映射更新保留原 lunid；优先更新现有 extent 或在必须重建时保留原映射身份，结果以重新查询确定。服务端是否自动更新 extent 是优化差异，不能成为成功判定的隐含假设。

拒绝通用 saga/持久化补偿队列：目前只有少数同步操作，逐操作小型清理分支足够。拒绝“任何失败删除同名卷”：可能删除其他操作拥有的资源。

### 5. 固定 PVE 卷名与远程执行边界

以 parse_volname 取得真实 dataset；clone 返回 parent/name，snapshot_info 使用 snapshot_name。保留已有 createtxg 排序并验证回滚 blockers；官方当前父类 parser 已精确过滤 pool，相似前缀只做回归不重复实现。上述 PVE 9 基线 volume_resize 比 PVE 8 多 snapname 参数，并拒绝 snapshot resize；本仓库 Native 尚未接收该参数，计划显式拒绝后再处理当前卷，Patch 保留相同父类行为。

显式覆盖 Native stream format/import/export，未实现远程流时拒绝；只审查其余继承入口中真正针对远端池执行本地命令的路径，不重写整个父类。LunCmd 当前不被 dispatch 触达的 snapshot 分支返回明确 unsupported，不凭空新增 Patch 快照 API。

### 6. 先预检再部署，保留旧有效生成产物

参数、依赖、PVE 版本和资源检查必须先于 mv/rm/cp；未知参数立即退出。关键命令显式检查或配合正确初始化变量使用 shell 严格模式；首次安装无可选备份不能因单纯 set -e 被误伤。补丁先在副本验证可应用；失败报告阶段与恢复路径，不无条件重启 corosync/pve-cluster。成功只重启实际需要读取插件的服务，具体名单按现有 PVE 加载路径决定。

build 使用脚本相对目录、输入存在检查和临时输出；diff=1 表示正常差异，>1 才是执行错误。成功后替换产物。PVE 8/9 UI 两份相同错误一起修。API viewer 与旧 orig/FreeNAS 补丁选择明确标为历史参考、不进入支持安装链；此处不生成新的文档补丁或增加版本矩阵。

## Risks / Trade-offs

- [证书校验使旧自签部署连接失败] → README 给出系统信任迁移顺序，不能以禁用校验作为默认回退。
- [PVE 敏感值 hook 随版本变化] → 使用上述两个固定代表基线验证读写；不把分支基线证据扩展为所有 8/9 历史小版本支持，不能静默明文回退。
- [结果未知时无法确定远端状态] → 允许明确失败并留下诊断；不以“全部自动清理”作为验收目标。
- [本地测试没有真实 worker/iSCSI 资格] → 报告软件覆盖范围；真实部署前另获授权执行代表性联调，不把它变成本 change 隐含门槛。
- [图工具未解析 Perl] → 在每阶段执行图 impact/detect_changes 后，用源码和定向回归补足，不将 UNKNOWN 记为低风险。

## Migration Plan

本轮不执行迁移。未来实施按五阶段 commit，最后同步 README、审计状态和 tasks；只在测试证据证明后勾选。部署前备份当前插件/配置并安装受信 CA，先在可销毁环境验证。回滚使用先前匹配版本的插件与配置；不自动逆向撤销已在 TrueNAS 上完成的数据变更。任务产生的 wsx 临时目录/容器在测试结束清理，共享服务不动。
