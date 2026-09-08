## Purpose

在保留现有凭据存储和实际连接行为的前提下，限制调试日志中的秘密泄露并隔离不同认证上下文的连接，避免修复过程中引入配置迁移、证书切换或隐含明文降级。

## ADDED Requirements

### Requirement: Existing configuration remains usable
本次修复 SHALL 保留现有凭据存储与读取方式、证书验证策略和 TLS 实际行为，不自动迁移或删除配置中的凭据，不要求新增私有文件或受信证书。历史 SSL=0 配置 MUST 不因升级切换为明文。

#### Scenario: Existing configuration after upgrade
- **WHEN** 使用已有密码或 API key 配置升级插件，包括 SSL=0 或自签证书部署
- **THEN** 不要求凭据/证书迁移，连接传输方式保持原实际行为；既有安全风险在文档中明确保留而非声称已修复

### Requirement: Safe logging
所有日志级别包括 debug MUST 不记录原始凭据、认证消息或包含秘密的原始收发载荷；错误诊断 SHALL 保留方法、错误类别及非敏感上下文。

#### Scenario: Debug authentication
- **WHEN** 启用 debug 后用已有密码或 API key 认证
- **THEN** 日志不包含原始秘密，认证仍使用当前配置中的正确凭据，不改写凭据存储

### Requirement: Connection isolation
连接复用 MUST 与当前 endpoint、传输配置及认证身份一致；凭据轮换 SHALL 导致重新认证，失败初始化不得留下可复用成功状态。不同进程 MUST 不并发使用继承的同一连接与消息状态，目标缓存须与当前连接及 target 一致。

#### Scenario: Credential rotation or fork
- **WHEN** 同一主机配置换用不同凭据，或子进程首次使用继承客户端
- **THEN** 建立自身有效连接与认证状态，不复用旧身份或父进程的活动 socket
