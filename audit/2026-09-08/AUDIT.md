# TrueNAS 插件重新审计（2026-09-08）

## 范围与结论

原报告误删后，根据当前源码重新审计；不声称恢复原文或原编号。基线为 `7b670801e7358d2c1e467416bf022b36e025daff`（插件 1.0.119），分支 `fix/audit-2026-09-08`。覆盖共用 Client/Helpers、Native、Patch LunCmd、PVE 8/9 补丁、部署/生成脚本及说明。此次不修改实现。

按独立修复边界归并为 **28 项：P1 15 项、P2 12 项、P3 1 项**。P1 表示可能误报存储变更成功、操作错误对象、泄露凭据或阻断关键操作；P2 为协议/契约/可用性缺陷；P3 为当前未发现生产调用的辅助缺陷。数量不等于断言数，也不强行对齐已丢失报告的 24 项。

本轮证据：

- [客户端结果](reaudit-client-results.tap)：`repro.pl` 在 wsx 一次性 Debian bookworm 容器中 **36/36** 通过，其中 35 条 BUG 断言确认缺陷、1 条控制断言。使用真实 Perl 协议依赖，PVE/logging 为替身，涉及 pipe/Unix socket/本地 TCP。
- [界面与部署结果](reaudit-surface-results.tap)：`node audit/2026-09-08/surface-repro.cjs` **4/4** BUG 断言通过。UI 为提取回调，系统命令为替身。
- [执行说明](re-audit-execution-notes.md)：远程临时目录和容器已清理；没有真实 TrueNAS、磁盘、凭据、PVE worker 或 iSCSI I/O 测试。
- `inheritance-results.tap` 为保留的历史证据，不能冒充本轮执行；继承问题另由当前源码及官方父类确认。
- GitNexus 已刷新到上述 HEAD（26 files，104 nodes，112 edges，0 flows）。Perl 仅有文件节点，函数/文件影响查询为 UNKNOWN 或无可解析调用关系，因此结合源码核查，空图不是安全证据。

下文 Tn 指本轮客户端 TAP 第 n 项，Un 指本轮 surface TAP 第 n 项；S 指当前源码确认，H 指历史继承脚本证据。所有项目当前均为**未修复**。

### 后续范围决定（用户确认）

非必要的破坏性修复先不做：**F09、F10、F25 后置，未修复**。其余 25 项进入当前 OpenSpec 修复范围；这不表示它们已实现。原发现和修复建议保留为审计记录，不将后置项伪装成通过验收。

| 后置项 | 保留风险 | 再次处理的触发条件 |
| --- | --- | --- |
| F09 TLS 证书验证 | 现有 TLS 无服务器身份验证 | 明确传输安全要求或另获证书升级授权 |
| F10 凭据存储迁移 | 凭据仍使用现有配置方式，实际访问边界未验证 | 确认暴露范围并另获集群迁移/回滚授权 |
| F25 SSL=0 行为修正 | 配置 0 仍实际使用 TLS，语义不一致 | 另获传输行为变更授权；不能升级后自动切明文 |

F11 日志秘密保护和 F12 缓存身份隔离仍在本次范围。F08 限定为防止远端池名操作本机数据集的必要保护，不禁用无关功能；既有卷名、有效 LUN 范围及在用 extent 身份保持兼容。

## P1：存储正确性与安全（15 项）

### F01 传输失败不设置错误，写操作误报成功
- 类别/位置：错误传播；`perl5/TrueNAS/Client.pm:139-166,351-355,871-958`。
- 触发与影响：发送后 timeout/EOF 返回 undef，却没有 error；create/delete/resize/clone 等仅检查 has_error，仍返回 1，调用者继续执行后续变更。
- 证据：T1–5、T19–20；真实本地套接字与故障注入。
- 修复/验收：每次请求重置状态；传输失败可观察，已发送结果未知单独表述；同组写操作不得报告成功或盲目重放。

### F02 PVE 回调忽略变更失败
- 类别/位置：PVE 合同；`TrueNASPlugin.pm:159-235,278-295,355-412,463-478`（目录 `perl5/PVE/Storage/Custom/`）。
- 触发与影响：clone 失败仍返回卷名，resize 失败返回新大小，free_image 五次失败仍正常返回；模板/rename/快照回调也缺少必要结果检查。PVE 9 的 resize 额外 snapname 参数被 Native 忽略，可能把快照请求作用于当前卷，应显式拒绝。
- 证据：T15–16、T33；其余同源路径 S。
- 修复/验收：各变更回调以具体方法结果为准，失败抛出 PVE 可见错误，依赖步骤停止；不能把 PVE 正常的 undef 成功约定误当作失败本身。

### F03 缺失 LUN ID 变成 LUN 0
- 类别/位置：对象身份；`TrueNASPlugin.pm:244-274,297-327`。
- 触发与影响：extent 存在但无 lunid，path 生成空尾路径，QEMU 用 int(undef) 得到 0，可能访问另一块磁盘。
- 证据：T17，S。
- 修复/验收：验证 target/extent/mapping 和非负整数 lunid；缺失拒绝，合法 0 允许。

### F04 删除首错被覆盖，失败后继续破坏性步骤
- 类别/位置：多步删除；`Client.pm:696-718,745-753`；`LunCmd/TrueNAS.pm:94-107,165-171`。
- 触发与影响：targetextent delete 失败后继续 extent delete，第二次成功清除首错；Patch 删除仅日志后返回正常，modify 继续重建。
- 证据：T27；Patch/recreate 路径 S。
- 修复/验收：逐步检查，保留首错，停止依赖删除/重建；区分明确不存在与查询失败。

### F05 多步骤创建缺少有限补偿
- 类别/位置：资源生命周期；`Client.pm:656-694`；`TrueNASPlugin.pm:135-156,189-210`。
- 触发与影响：zvol/clone 成功而 LUN 失败，或 extent 成功而 mapping 失败，留下本次孤立对象，重试遇到冲突。
- 证据：S；当前没有清理已创建对象的失败分支。
- 修复/验收：记录本次已确认创建对象，明确失败才定向补偿；响应丢失先查询实际状态，不能把已有同名对象当成本次资源删除。注入一个中间失败及一个结果未知代表例。

### F06 rename/template 未保持映射一致性
- 类别/位置：卷可访问性；`TrueNASPlugin.pm:159-187,278-295`。
- 触发与影响：rename 只改 zvol 名未同步 extent；template 删除重建 LUN 且忽略失败，可能改变 LUN 或留下不可访问对象。
- 证据：S；未完成真实 TrueNAS rename 联调，不断言服务端必然如何自动更新 extent。
- 修复/验收：成功需确认新 dataset 与 extent 路径一致、保持原有 LUN 身份；中途失败明确返回可恢复状态，不以 sleep 为成功证据。

### F07 LUN 枚举失败和分配竞争
- 类别/位置：并发分配；`Client.pm:21,656-685,720-743`，`LunCmd/TrueNAS.pm:73-85`。
- 触发与影响：枚举失败视为空 target 返回 0；两个 worker 先查后建可选同号，固定 sleep 不能提供互斥。Client 的 1024 与其他文件未使用的 255 常量也造成维护歧义。
- 证据：T26；竞争为 S 推导，未运行真实并发 worker。
- 修复/验收：枚举失败停止；用服务端冲突结果触发有限重新查询/分配，不引入分布式锁服务；统一实际生效上限，测试两个竞争请求。

### F08 Native 继承本机 ZFS 流操作
- 类别/位置：远程执行边界；`TrueNASPlugin.pm:1-2`，缺少 volume_import/export/formats 覆盖。
- 触发与影响：PVE 查询/调用继承回调会广告 zfs 格式并用远端池名构造本机 zfs send/recv；本机恰有同名池时存在误操作风险。
- 证据：S + H（`inheritance-repro.pl`、`inheritance-results.tap`）；[官方父类](https://raw.githubusercontent.com/proxmox/pve-storage/master/src/PVE/Storage/ZFSPoolPlugin.pm)。master 可变，本轮不是固定版本真机资格。
- 修复/验收：显式拒绝尚未实现的远程流能力；检查其他继承入口，拦截命令验证无本机 zfs 副作用。不在本 change 实现远程流框架。

### F09 TLS 不验证证书
- 当前处置：用户同意后置，以下为原修复建议，不属于本次必做范围。
- 类别/位置：传输安全；`Client.pm:181-186`。
- 触发与影响：SSL_verify_mode 为 0，无法验证服务器身份；网络攻击者可窃取认证消息或篡改响应。
- 证据：S；未实施中间人攻击。
- 修复/验收：默认校验证书与主机名，系统 CA 信任；受信/不受信/名称不匹配代表例，不允许验证失败后自动降级。

### F10 凭据未进入 PVE 敏感配置机制
- 当前处置：用户同意后置，以下为原修复建议，不属于本次必做范围。
- 类别/位置：配置保护；`TrueNASPlugin.pm:37-68`，`ZFSPlugin.pm.8.patch:64-106`、`.9.patch:65-106`。
- 触发与影响：Native sensitive-properties 为空，Patch 只新增普通字符串属性，密码/API key 缺少相应敏感读写合同。
- 证据：S，另核对下列固定 PVE 8/9 官方 Plugin/Config 合同；真实 PVE 权限/API 输出未测试，不能声称匿名用户可读。
- 修复/验收：按所支持 PVE 8/9 API 使用敏感属性读写/删除机制，并保证运行时能取回凭据；不仅改属性标记。验证普通输出不含秘密及认证仍可用。

### F11 debug 暴露配置与认证载荷
- 类别/位置：日志；`Client.pm:26,97,147,258,358-359,542`；`Helpers.pm:22-70`；`deploy.sh:78-80`。
- 触发与影响：开启 debug 后完整配置、认证 RPC、原始数据经 Dumper/日志输出，包含 key/password 等秘密。
- 证据：S；未输出任何真实凭据。
- 修复/验收：优先取消原始认证/收发载荷日志，仅保留方法、ID、错误类别；固定假凭据日志测试覆盖 debug。无需通用数据分类框架。

### F12 客户端缓存跨凭据复用且初始化错误检测不正确
- 类别/位置：身份隔离；`TrueNASPlugin.pm:94-129`；`LunCmd/TrueNAS.pm:175-225`。
- 触发与影响：仅以 host 缓存，轮换凭据仍用旧身份；客户端在初始化验证前入缓存，Patch 用不存在的 has_error 字段检查错误。
- 证据：T34；其余 S。跨进程 socket 复用是待集成确认风险，不宣称已真实复现。
- 修复/验收：按 endpoint/TLS/认证上下文复用，失败初始化不缓存；检查方法而非字段；以 PID 检查做低成本 fork 隔离，旧 socket 关闭不得向父连接发送协议关闭消息。

### F13 握手可无限等待
- 类别/位置：可用性；`Client.pm:180-234`。
- 触发与影响：对端 TCP 接受后不回完整 HTTP 握手，阻塞读行不受请求 timeout 约束，可卡住 PVE worker。
- 证据：T21–22，外部 watchdog 才能结束。
- 修复/验收：连接/握手共用有限期限并关闭失败 socket；静默本地服务端测试。

### F14 部署失败仍报告成功并重启集群服务
- 类别/位置：部署副作用；`deploy.sh:37-83`。
- 触发与影响：cp/mv/patch/rsync/apt 失败未停，最后 systemctl 成功掩盖失败；无条件重启 corosync/pve-cluster 扩大影响。
- 证据：U3；测试替身未重启真实服务。
- 修复/验收：先预检，关键失败非零停止；缺失可选旧备份走首次安装逻辑；成功只重启必要服务。用失败复制/补丁代表例验证无后续重启。

### F15 PVE 8/9 provider 切换引用不存在
- 类别/位置：UI；`pvemanagerlib.js.8.patch:31,112`、`.9.patch:31,98`。
- 触发与影响：lookupReference('truenas_apikey') 与字段 truenas_apikey_field 不匹配，切换 provider 抛异常，中断表单处理。
- 证据：U1–2，提取回调运行，非真实浏览器全流程。
- 修复/验收：统一引用并验证切入/切出两种行为；Native 当前无此 UI，不将 Patch 结论套用 Native。

## P2：协议、合同与工具（12 项）

### F16 心跳失败绕过重连，重试参数未生效
- 位置：`Client.pm:45,85-99,279-309`。
- 影响/证据：_receive 异常直接离开 request，不走连接重建；max_retries 只有赋值无消费。T10–11、S。
- 修复/验收：心跳失败转断开，重新连接认证有预算；区分业务写请求重放和连接重试。

### F17 帧未掩码，短写未处理
- 位置：`Client.pm:312-320`。
- 影响/证据：客户端 wire 帧不符合 mask 要求，严格服务端会拒绝；单次 syswrite 可能截断。T18；短写为 S，未真实网络诱发。
- 修复/验收：明确客户端 masked frame，期限内写完或失败；wire 检查与短写替身。

### F18 缓冲与控制帧处理错误
- 位置：`Client.pm:239-252,323-380`。
- 影响/证据：已缓存第二帧等新数据才读；断开保留旧帧；Ping 当 RPC 结果；空 Close 变 timeout。T12–14、T35–36。
- 修复/验收：先消费缓冲、按 opcode 分流控制帧、重置连接帧状态；复用这四类代表例。

### F19 响应不关联请求 ID
- 位置：`Client.pm:254-275,408-494`。
- 影响/证据：不同 ID 的合法响应可成为本次结果，T8。
- 修复/验收：保存当前 ID，通知/异号不能完成请求；匹配等待受原期限限制。

### F20 RPC/解析错误丢失或二次异常
- 位置：`Client.pm:260-267,449-494,529-543`。
- 影响/证据：error 无 data.reason 时丢失；非法 DDP JSON 传字符串到按 hash 处理的 on_error；JSON-RPC 解析异常未统一捕获。T6–7、S。
- 修复/验收：安全错误归一化，保留 code/message，兼容 data.reason；非法 JSON 不产生二次异常。

### F21 null 文本替换篡改数据
- 位置：`Client.pm:460-461`。
- 影响/证据：顶层和嵌套 result:null 均变 true，T9。
- 修复/验收：移除全局替换，合法 null 由方法语义解释；嵌套 null、false、0 原样保存。

### F22 泛化数字转换破坏字符串及输入对象
- 位置：`Client.pm:418,501-523,393-405`。
- 影响/证据：数字样式凭据丢前导零，递归改写调用者结构；查询构造器也泛化转数值。T23、S。
- 修复/验收：只在 API 明确的数字字段边界转换，字符串和输入对象保持不变。

### F23 克隆与快照命名合同不一致
- 位置：`TrueNASPlugin.pm:189-210,368-441`。
- 影响/证据：clone 不返回父模板前缀；删除/回滚直接拼编码 volname；snapshot_info 用完整路径作键。T28–31。
- 修复/验收：统一解析实际 dataset，返回父卷关系及短 snapshot 名；同一克隆全链路命名测试。

### F24 大小查询失败伪装为零大小
- 位置：`TrueNASPlugin.pm:445-461`。
- 影响/证据：API 失败后字段默认 0，PVE 得到成功零值，T32。
- 修复/验收：检查查询状态和必要字段，失败抛错；有效大小（包括合同允许的零）不与查询失败混淆。

### F25 显式 SSL false 无效
- 当前处置：用户同意后置，保留原实际 TLS 行为；以下为原修复建议，不自动应用。
- 位置：`Client.pm:32`。
- 影响/证据：`|| 1` 覆盖配置 0，T24。
- 修复/验收：仅未定义时用默认值；显式非 TLS 按配置工作并说明明文风险，不引入自动降级。

### F26 未知部署参数导致死循环
- 位置：`deploy.sh:17-32`。
- 影响/证据：case 无默认分支且不 shift，U4 由外部 timeout 结束。
- 修复/验收：未知参数立即非零，进入任何系统变更前完成参数检查。

### F27 补丁工具缺少版本/输入保护，文档支持边界不清
- 位置：`deploy.sh:13,47-48,62-66`；`build.sh:5-20`；`README.md:5,74-79,132-136`；`pve-docs/api-viewer/`。
- 影响/证据：只按主版本选文件、不预检；build 重定向可能覆盖旧补丁且错误被后续 cd 掩盖；API docs 补丁没有生成/安装路径，orig 文件仍有 FreeNAS 名称。S；没有真实 APT/补丁应用测试。
- 修复/验收：支持版本资源预检，build 区分 diff=1 与真正错误并临时生成后替换；README 明确版本基线。此次选择将 API viewer/旧 orig 补丁明确列为历史参考、非受支持自动安装产物，不新增 docs 小版本矩阵。

## P3：辅助函数（1 项）

### F28 版本解析使用未初始化变量
- 位置：`Client.pm:980-990`。
- 影响/证据：匹配 `$parsed` 而非 `$version`，始终无法解析，T25。当前没有发现正式调用入口，因此不升级为实际版本准入故障。
- 修复/验收：使用实际输入，TrueNAS/TrueNAS-Scale/非法值三例足够。

## 不冒充已确认缺陷的观察项

- LunCmd 存在 snapshot/destroy/rollback 到未定义函数的分支，但当前 8/9 ZFS patch 的 lun_cmds 不路由这些方法。列入分派边界的小修任务，返回明确不支持；不称为已复现在线快照故障。
- 官方当前父类 `zfs_parse_zvol_list` 已以 parsed_pool 精确相等过滤相似 pool 前缀，不将 Client 的宽前缀查询单独算作越界缺陷。fork 后连接所有权、PVE 9 扩展回调参数作为定向合同检查，不增加真实环境资格矩阵。
- Helpers 的 warn/warning 级别表不一致，纳入日志小修；未证明运行时丢日志。
- release workflow 的宽权限、标签 shell 插值和缺少构建门禁属于潜在加固点；当前无不可信标签入口证据，不扩大为供应链整改项目。

## 修复计划与任务映射

正式计划见 [OpenSpec change](../../openspec/changes/repair-truenas-audit-findings/proposal.md)，所有实施项保持未勾选。

| 阶段 | 覆盖发现 | 交付与最小验收 |
| --- | --- | --- |
| 1 错误与数据合同 | F01、F20–22、F28 | 请求/解析错误、类型保真、版本辅助；分组单元回归 |
| 2 连接与安全 | F11–13、F16–19 | 有界协议、日志/缓存、旧配置兼容；本地 socket 与假凭据代表例，无证书/凭据迁移 |
| 3 存储生命周期 | F02–08、F23–24 | PVE 回调、LUN、多步补偿、远程边界；PVE 替身及父类命令拦截 |
| 4 安装与界面 | F14–15、F26–27 | 脚本输入/错误语义、UI、兼容性文档；命令替身和 8/9 UI 回调 |
| 5 集成与文档同步 | 本次 25 项；另列后置 3 项 | 一次分组回归、结论审查、清理任务资源、按实际结果勾选任务，不称 28 项全修复 |

按阶段提交，阶段之间保持依赖顺序。未来 apply 前检查实施分支与工作树；本次只提交审计/规划资料。真实 TrueNAS/PVE/iSCSI 的部署资格后置，触发条件为准备在真实环境使用；在另获授权前不把它列为本次软件修复的强制验收。

## 外部合同来源

- [JSON-RPC 2.0](https://www.jsonrpc.org/specification)：响应 ID、error code/message 与合法 result 值。
- [RFC 6455](https://datatracker.ietf.org/doc/html/rfc6455#section-5.2)：客户端 masking、控制帧及关闭处理。
- [PVE ZFSPoolPlugin 官方源码](https://raw.githubusercontent.com/proxmox/pve-storage/master/src/PVE/Storage/ZFSPoolPlugin.pm)：继承与卷名合同；具体实现验证需保存所用固定版本。
- PVE 8 代表源码基线 `9aab8f6f52b314fda5e2aceef6472ffd21b7d5b3`：[Plugin](https://git.proxmox.com/?p=pve-storage.git;a=blob;f=src/PVE/Storage/Plugin.pm;hb=9aab8f6f52b314fda5e2aceef6472ffd21b7d5b3)、[API2 Config](https://git.proxmox.com/?p=pve-storage.git;a=blob;f=src/PVE/API2/Storage/Config.pm;hb=9aab8f6f52b314fda5e2aceef6472ffd21b7d5b3)。PVE 9 代表基线 `7c6a03839920d4939a8ae725a2b0ef91c0cbc6c9`：[Plugin](https://git.proxmox.com/?p=pve-storage.git;a=blob;f=src/PVE/Storage/Plugin.pm;hb=7c6a03839920d4939a8ae725a2b0ef91c0cbc6c9)、[API2 Config](https://git.proxmox.com/?p=pve-storage.git;a=blob;f=src/PVE/API2/Storage/Config.pm;hb=7c6a03839920d4939a8ae725a2b0ef91c0cbc6c9)。两者通过 sensitive-properties 和配置 hooks 分离秘密；PVE 9 增加 full update hook 适配，详见 design。属于源码合同核查，不是安装版本全覆盖。
