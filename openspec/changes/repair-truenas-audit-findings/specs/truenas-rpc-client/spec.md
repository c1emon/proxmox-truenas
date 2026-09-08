## Purpose

规定 TrueNAS 请求的可观察成功、失败和结果未知语义，以及 WebSocket 连接、响应关联和数据类型要求，使存储调用方能够可靠判断操作结果而不把通信故障当成成功。

## ADDED Requirements

### Requirement: Explicit request outcome
客户端 MUST 区分有效 RPC 成功、明确失败和发送后结果未知；传输、解析和 API 错误 SHALL 对调用方可见，不得沿用上一次成功状态。成功响应的 null、false、0 SHALL 原样保留，由具体方法合同判断业务成功。

#### Scenario: Mutation response is lost
- **WHEN** 写请求发送后连接 EOF 或等待响应超时
- **THEN** 调用方收到失败或结果未知，不能报告写入成功，也不能无状态查询地重放写请求

#### Scenario: Valid null and ordinary RPC error
- **WHEN** 收到合法 null 结果，或仅含 code/message 的错误，或非法 JSON
- **THEN** 分别保留成功 null、报告 RPC 错误、报告解析错误，且错误处理不产生二次异常

### Requirement: Correlated and type-preserving messages
客户端 MUST 只用与当前请求标识匹配的响应完成请求；通知和异号响应不得成为该请求的结果。消息编解码 SHALL 保留字符串、数值、布尔、null 与嵌套数据，不修改调用者的输入对象。

#### Scenario: Foreign response precedes matching response
- **WHEN** 服务端先发通知或不同 ID 的响应，再发当前 ID 的响应
- **THEN** 仅匹配响应能完成请求，等待不能超出原请求期限

#### Scenario: Numeric-looking credential
- **WHEN** 请求包含字符串 `00123` 与嵌套 `result: null`
- **THEN** 字符串前导零和类型、嵌套 null 及原输入对象保持不变

### Requirement: Bounded connection recovery
连接、握手、写入和响应等待 SHALL 在有限期限内结束；心跳失败 SHALL 使旧连接失效并允许有上限的重连和重新认证。重试预算 MUST 实际生效，不能无限循环或把已发送写请求作为普通重试对象。

#### Scenario: Silent handshake or failed heartbeat
- **WHEN** 对端接受连接后不响应握手，或旧连接心跳超时
- **THEN** 前者在期限内失败，后者清理旧连接并在预算内重连；业务调用不会无限阻塞

### Requirement: Correct WebSocket framing
客户端 SHALL 发送完整、掩码的客户端帧，消费已缓冲的数据帧，正确回应 Ping、忽略非业务 Pong、处理包括空载荷在内的 Close。断开或重连 MUST 丢弃旧连接帧状态。

#### Scenario: Buffered frames and control frame
- **WHEN** 一次读取含两个业务帧且插入 Ping，或收到空 Close
- **THEN** 已缓冲帧无需新 socket 数据即可消费，Ping 得到 Pong 且不成为 RPC 结果，Close 立即终止旧连接

#### Scenario: Partial write
- **WHEN** 底层只接受部分发送字节
- **THEN** 在同一期限内继续发送剩余字节或返回可观察失败，不把部分帧当作发送完成

### Requirement: Version parsing
版本解析 SHALL 使用传入版本字符串，支持现有 TrueNAS 与 TrueNAS-Scale 格式，并对不支持的格式返回明确的不可解析结果。

#### Scenario: Version formats
- **WHEN** 输入 `TrueNAS-25.10.0`、`TrueNAS-Scale-25.10.0` 或无效字符串
- **THEN** 前两者返回正确主次版本，后者不伪造版本
