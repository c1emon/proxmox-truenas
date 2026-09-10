# 上游 PR 实施流程

用户于 2026-09-08 确认采用本流程。记录规则时未开始业务代码修复。后续用户已授权首组 F15 的分支、修复、测试和本地提交，随后授权推送并手动创建 PR #144；实施状态见末尾记录。后续实施仍遵守 apply 前的分支检查及创建/切换确认规则。

## 分支与提交

`fix/audit-2026-09-08` 保留审计与 OpenSpec 总计划。五个任务阶段用于分类和依赖分析，不作为五个大 PR 或严格的阶段提交顺序。实施时选择一组关联问题，核对 `origin`（fork）、`upstream`（原仓库）和实际目标分支，从最新上游目标分支建立独立修复分支。

每个 PR 解决一个完整问题，可以有多个清晰 commit。PR 包含对应代码、必要测试和用户文档，不夹带其他未合并修复。总计划与审计材料默认保留在规划分支，是否提交上游以原仓库贡献规范为准；不要为携带任务清单而把整个规划分支合入修复分支。

OpenSpec 读取与代码实施分开定位：保留可读取的规划 checkout，必要时使用独立 worktree；从规划 checkout 读取本 change 的 artifacts 和实施指令，只选择当次 PR 对应的任务子集。业务代码修改、测试和提交均在用户确认的修复 checkout 执行，任务状态回写规划 checkout。开始前明确两个绝对路径并核对分支，不在缺少 change 的修复 checkout 盲目运行默认 apply，也不在规划 checkout 实施业务代码。创建或切换实现分支仍先按用户规则确认。

## 执行循环

1. 核对工作树、远程和上游贡献要求，拉取最新上游目标分支。若需创建或切换实现分支，先取得用户确认；不自动丢弃、stash 或提交已有工作。
2. 明确本 PR 的 Fxx 范围、依赖和兼容性边界；执行 GitNexus impact，UNKNOWN 用源码检查补足，然后实施。
3. 完成最小充分的回归验证和差异复核，执行提交前 GitNexus detect_changes。每个 PR 同步自己的必要文档，不拖到全部修复结束。
4. 将修复分支推送到 fork，以原仓库目标分支为 base 创建 PR，写清问题、修复后的行为、实际验证和兼容性影响。
5. 在同一分支处理维护者反馈，按改动范围重新验证并更新 PR。
6. 合并后重新拉取上游，更新本地主分支和 fork 主分支。若发生分叉先检查，禁止为同步而强推覆盖。无论普通、squash 或 rebase 合并，下一分支均从更新后的上游基线创建，不从旧修复分支延续。
7. 在规划分支记录该组发现、验证证据、commit/PR 链接及合并状态；只有实现与验证完成才勾选相关任务，上游接受与否单独记录。跨 PR 任务在全部相关部分完成前保持未勾选。旧分支清理另询问用户。

默认先完整走通一个小 PR。存在依赖的下一组等待前置 PR 合并；无依赖的组可各自从上游目标分支并行，不默认使用叠加 PR。维护者拒绝或改变方案时先调整计划，不把未接受的依赖偷偷带入下一 PR。

## 初始拆分建议

以下是候选边界，不是要求同时创建全部 PR；实施前根据实际代码耦合及维护者反馈调整，保证中间版本行为完整。

| 候选组 | 范围 | 问题 |
| --- | --- | --- |
| 1 | PVE 8/9 UI API Key 字段引用 | F15 |
| 2 | 构建、部署参数和失败处理及相关文档 | F14、F26、F27 |
| 3 | RPC 错误传播与响应解析 | F01、F20、F21 |
| 4 | 保留参数类型和调用方输入 | F22 |
| 5 | WebSocket 帧、收发与响应关联 | F17、F18、F19 |
| 6 | 握手期限、心跳与连接恢复 | F13、F16 |
| 7 | 日志脱敏与连接缓存隔离 | F11、F12 |
| 8 | 存储回调失败、缺失 LUN 与容量查询 | F02、F03、F24 |
| 9 | 多步骤创建、删除及有限清理 | F04、F05 |
| 10 | LUN 分配并发协调 | F07 |
| 11 | 卷/快照命名及设备身份保持 | F06、F23 |
| 12 | 危险的本机 ZFS stream 继承入口 | F08 |

组 8、9 等依赖组 3 的错误语义，应等待其合并。存储组默认排期为组 3 → 8 → 9 → 10；组 11 等组 8、9 合并后推进，组 10 与 11 是否并行再根据实际补丁判断。这样可以先稳定回调失败合同，再增加多步骤补偿与分配协调，并在已合并的 clone/template 路径上修复命名和设备身份。这里的串行安排包含共享路径的冲突控制，不把“修改同一文件”本身当成必然的功能依赖。

组 12 可独立于组 9、10 安排，但与组 8、11 共享 Native 文件，须复核继承入口、能力声明和卷名解析的衔接。每组实施前列出实际共享文件；若上游已合并相关修改，更新基线后重新核对补丁与回归，不按旧上下文强行应用或覆盖已合并行为。其他依赖以实施前影响分析为准。

组 10、11、12 涉及存储行为，提交实现前先向维护者说明问题及兼容性边界；发送沟通内容需有用户明确授权。

F28 仍在总计划内，低优先级单独安排，不为凑组混入无关 PR。F09/F10/F25 保持用户确认的后置状态，不报告为已修复。真实 PVE/TrueNAS/iSCSI 资格、部署和发布不因采用本流程而自动纳入实施。

## 实施记录

### 组 1：F15 / 任务 4.4（2026-09-08）

- 用户授权：创建修复分支、实施、测试及本地提交；后续授权推送。GitHub CLI 创建 PR 因令牌权限不足失败，用户随后手动创建了上游 PR。
- 原仓库：`boomshankerx/proxmox-truenas`；`upstream/main` 基线 `835129a71d94fd5d759a70ed22b23e081dc988c7`。`origin` 为 `c1emon/proxmox-truenas`。
- 修复分支：`fix/truenas-api-key-field-reference`；代码 worktree 为本仓库下 `.worktrees/fix-truenas-api-key-field-reference`；本地提交 `c4f1a30`。
- 改动：仅将 PVE 8/9 补丁 provider 回调中的 API Key 查找改为已声明的 `truenas_apikey_field`，保留提交字段名 `truenas_apikey`，不变更配置/API 或凭据存储。
- 回归：在修复 worktree 执行 `node --test tests/provider-switch.test.cjs`。修改前 2 通过、2 失败（两版切离时查找不存在引用）；修改后 4/4 通过，覆盖切入保留配置、切离清空不适用字段及字段校验状态。仅使用 Node 内置模块。
- 验证与复核：两份补丁的 `git apply --numstat` 解析、`git diff --check` 通过；独立 reviewer 未发现实质问题。GitNexus 已绑定修复 worktree 执行 impact/detect-changes，但补丁 hunk 没有可映射的索引符号，已用源码、实际差异和回归补足，未把空图当成安全证明。
- 验证边界：回调与字段替身，不是真实 ExtJS/PVE 浏览器或完整补丁部署验证；未连接 TrueNAS、未使用远程容器，无远程资源需要清理。修复 worktree 保留供后续审阅和推送。
- 上游 PR：[#144](https://github.com/boomshankerx/proxmox-truenas/pull/144)；来源 `c1emon:fix/truenas-api-key-field-reference`，目标 `boomshankerx:main`，包含修复提交 `c4f1a30`。2026-09-10 通过 GitHub API 核对已合并，时间为 2026-09-09 22:56:12（Asia/Shanghai），合并提交 `c025d1a31eb827dbb055c786ec9a2652e13f6b30`。
- 状态：F15 本地实现与验证完成；已推送且上游 PR 已合并。此条仅记录组 1 的完成状态。

- 合并后同步（2026-09-10）：上游 `main` 更新到 `a600a9d`。本地及 fork 的 `main` 原有 `d14217f`、`7b67080` 两条初始化提交，采用普通合并保留历史，现同步至 `c3945a0`；未强推。同步后的 F15 回归 4/4 通过。下一修复分支仍从最新 `upstream/main` 创建，避免携带 fork 的初始化资料。用户于 2026-09-10 确认清理后，已删除 F15 本地分支、fork 远程分支及对应 worktree；删除前确认工作树干净，修复提交包含在上游与本地 main 中。审计规划分支保留。


### 组 2：F14/F26/F27 / 任务 4.1、4.2、4.3、4.5（2026-09-10）

- 用户授权：从最新上游建立独立分支，修复、测试及本地提交；暂不推送或创建 PR。
- 基线：`upstream/main` 的 `a600a9d`；分支 `fix/build-deploy-error-handling`，worktree `.worktrees/fix-build-deploy-error-handling`；本地提交 `4dc435f`。
- 改动：`build.sh` 验证版本及全部输入，从脚本目录生成，正确区分 diff 的差异/失败状态，全部生成成功后才替换输出。`deploy.sh` 先校验参数、命令、版本及资源，允许首次安装没有备份，先在副本应用两份补丁；APT/复制/补丁/客户端同步等失败停止，不进入成功重启；仅重启 pvedaemon/pvestatd/pveproxy。保留 -d/-r/-p 和默认 Native，增加帮助选项；不再操作未安装的 API viewer 产物。
- 文档：说明 Native/Patch、补丁版本基线、首次安装/恢复及失败后的人工处理、历史 API viewer/orig 补丁、既有 TLS/凭据/debug 风险和 Native stream 迁移未获支持资格；未声称 F08/F09/F10/F11/F25 等其他组已修复。
- 验证：修复 worktree 中 `node --test tests/*.test.cjs` 8/8 通过（4 个新增脚本分组 + 4 个 F15 回调测试），`bash -n build.sh deploy.sh`、`git diff --check` 通过。脚本分组包含不同 cwd、缺输入、第二次 diff 失败保留双输出、未知参数正常报错退出、版本/资源错误、首次 Native、PVE 8/9 Patch，以及复制/补丁/APT/rsync 失败后的停止行为。
- 独立复核：生产代码未发现实质问题；测试复核发现超时可能被误判为正确失败，已要求无执行错误/信号且未知参数有明确错误信息，最终回归通过。GitNexus impact 为 UNKNOWN 的 shell 入口已由源码补足，提交前执行 detect-changes；不将无调用流当成安全证明。
- 测试隔离记录：早期测试副本缺少目标路径替换，该轮部署结果已弃用；检查相关宿主目标均不存在。修正后的测试明确将目标和 TMPDIR 限定到临时目录，APT/systemctl/dpkg 为替身，未执行真实部署。测试临时目录已清理，剩余 0；未使用远程容器、真实 TrueNAS 或磁盘。worktree 保留供审阅。
- 兼容性边界：没有凭据或配置迁移，没有自动撤销已经完成的文件/包操作；失败时保留可用备份并要求检查后重试。软件验证不等于真实 PVE/ExtJS/iSCSI 或完整发布资格。
- 状态：本地实现与验证完成；未推送、未创建 PR、未上游合并。其他修复组保持未实施。

### 组 2 远程补充验证（2026-09-10）

- 用户授权使用 `wsx`；测试输入为修复提交 `4dc435f` 的 git archive。宿主为 Linux x86_64 / Docker 29.7.2；独立 Debian 12.15（bookworm-slim）容器，Node.js 18.20.4、Bash 5.2.15、GNU diff 3.8、GNU patch 2.7.6。
- 容器内 `node --test tests/*.test.cjs` 8/8 通过，`bash -n build.sh deploy.sh` 通过。文件操作使用 Linux 工具；APT、systemctl、版本查询仍为测试替身，目标路径在临时目录。
- 使用官方 Proxmox 签名 APT 仓库下载并仅解包：PVE 8 的 `pve-manager 8.4.14`、`libpve-storage-perl 8.3.7`，PVE 9 的 `pve-manager 9.2.10`、`libpve-storage-perl 9.1.10`。对解包后的实际 ZFSPlugin.pm 和 pvemanagerlib.js 执行与部署脚本相同的 `patch --batch --forward --ignore-whitespace`；四份补丁均成功，无 .rej。PVE 8 界面补丁的首个 hunk 偏移 16 行，其余偏移 37 行；其他补丁无偏移或 fuzz 提示。
- 文档待校正：README 将 PVE 9 存储包基线写为 `9.2.10`，本次签名仓库所提供并验证的是 `9.1.10`；不能声称已验证存储包 `9.2.10`。本轮仅记录差异，未改变修复提交。
- 边界：没有安装 PVE 软件包、启动 PVE 服务或连接 TrueNAS；没有验证 ExtJS 实际交互、Perl 插件运行、iSCSI/ZFS 数据路径或真实服务重启。实际软件包文件匹配不等于完整部署验证。
- 清理：任务容器 `truenas-scripts-20260910-xLNfWm`、远程目录 `/tmp/truenas-scripts-20260910-xLNfWm` 及本轮新拉取的 Debian 镜像已删除。未推送、未创建 PR。

### 组 2 人工复核调整（2026-09-10）

- 按用户要求恢复原五服务重启列表和顺序；缩小范围改为 deploy.sh 的 TODO，design/spec 同步调整，取代前述三服务方案。
- 新增同目录 script-common.sh，复用 fail、require_commands、detect_pve_version；加载本身仅定义函数。README 说明公共文件依赖，三个脚本主要阶段添加简短英文注释。
- 本地及 wsx 独立 Debian bookworm 容器回归均 8/8 通过，包含 Native/Patch 原列表和异 cwd 加载；最终注释修改后 bash -n 与 diff --check 通过。独立 reviewer 未发现实质问题。未执行真实服务重启。
- 远程任务容器、目录 /tmp/truenas-common-Jnn33L 和本轮拉取的镜像已清理。本次调整保留在工作树供人工 review，未提交、未推送。

- 后续完整 wsx 软件测试：当前工作树回归 8/8、真实软件包文件补充场景 18/18，通过首次/重复 Patch、Native 恢复、模拟重装、debug、sed/重启失败及 build/deploy 衔接检查。详见 `audit/2026-09-08/wsx-full-2026-09-10/README.md`；远程资源已清理。随后仅为各测试补充英文目的注释，语法检查通过。

- 显式数据传递复核：query_package_version(package) 和 detect_pve_version(manager_version) 使用局部变量并通过 stdout 返回；两个脚本显式接收完整包版本和主版本。build cleanup 改为接收路径参数、使用局部 file。deploy 的 stage/work 保留为明确的 trap 生命周期状态。
- 本轮本地及 wsx Debian 容器回归均 9/9 通过，新增调用者变量不被覆盖、空/失败版本查询、不支持版本和命令替换错误传播验证；Shell 语法检查通过，独立 reviewer 无实质问题。远程容器、目录及本轮拉取镜像已清理。此前 18 个包文件场景未在此次辅助函数调整后重跑，不视为当前版本新增验证。改动仍未提交或推送。

### 组 2 提交与手动 PR 交接（2026-09-10）

- 修复分支 fix/build-deploy-error-handling 已提交并推送到 origin（c1emon/proxmox-truenas），HEAD b58a2f3；包含此前 4dc435f，基于 upstream/main a600a9d。工作树干净。
- README 存储包基线已校正为 9.1.10；重新查询官方 trixie/pve-no-subscription 的 9.x 包索引确认其为该渠道最新版本，不把 pve-manager 9.2.10 等同于存储包版本。
- 最终独立复核无阻断问题，提交前执行 GitNexus detect-changes（含暂存新增公共文件）；Shell 调用未被图解析，已用源码及测试补足。最新逻辑在本地及 wsx 回归 9/9 通过。
- gh 创建上游 PR 失败：GraphQL Resource not accessible by personal access token (createPullRequest)。修复推送成功，PR 尚未创建；用户决定手动创建。
- PR base：boomshankerx/proxmox-truenas 的 main；head：c1emon/proxmox-truenas 的 fix/build-deploy-error-handling。
- 英文标题：fix: stop source build and deployment scripts on failures
- 英文正文：audit/2026-09-08/wsx-full-2026-09-10/upstream-pr-body.md。用户创建后记录 PR URL；等待该 PR 接受后再按既定流程继续下一组。

- 用户已手动创建上游 PR #146：https://github.com/boomshankerx/proxmox-truenas/pull/146 。2026-09-10 经 GitHub API 核实为 OPEN，base main，head fix/build-deploy-error-handling，head commit b58a2f3be65daff82a19bf1957bb1da6c0760a2f，标题与准备内容一致。当前等待上游审阅；未合并，不启动下一修复组。
