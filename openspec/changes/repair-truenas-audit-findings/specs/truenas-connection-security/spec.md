## Purpose

定义连接 TrueNAS 时证书、凭据和连接复用的必要保护，保证当前配置决定实际认证身份，避免秘密进入公开配置响应或调试日志，同时保留明确的传输配置语义。

## ADDED Requirements

### Requirement: Verified TLS and explicit configuration
未指定传输配置时 SHALL 使用 TLS 并校验证书信任与主机名；显式关闭 SSL SHALL 按配置使用非 TLS 连接并在文档中说明明文传输风险。TLS 失败 MUST 不自动降级为明文或关闭校验。

#### Scenario: Certificate validation
- **WHEN** TLS 对端证书不受信或主机名不匹配
- **THEN** 连接失败且不会发送认证凭据；受信且名称匹配的证书可连接

### Requirement: Sensitive configuration and safe logging
Native 和 Patch 的密码、API key SHALL 使用适用 PVE 敏感配置读写机制，不在普通配置输出中暴露。所有日志级别包括 debug MUST 不记录原始凭据、认证消息或包含秘密的原始收发载荷；错误诊断保留方法、错误类别及非敏感上下文。

#### Scenario: Debug authentication and config read
- **WHEN** 启用 debug 后用密码或 API key 认证，并读取普通 PVE 存储配置
- **THEN** 日志与普通配置输出均不包含原始秘密，认证仍使用正确凭据

### Requirement: Connection isolation
连接复用 MUST 与当前 endpoint、传输配置及认证身份一致；凭据轮换 SHALL 导致重新认证，失败初始化不得留下可复用成功状态。不同进程 MUST 不并发使用继承的同一连接与消息状态，目标缓存须与当前连接及 target 一致。

#### Scenario: Credential rotation or fork
- **WHEN** 同一主机配置换用不同凭据，或子进程首次使用继承客户端
- **THEN** 建立自身有效连接与认证状态，不复用旧身份或父进程的活动 socket
