# T8：iOS 观看历史身份补强

## 范围
本轮在已提交的 T7 检查点 9fb7a72 上补充 history POST 的 recording_id/source_version，播放器捕获会话身份及原始客户端，避免旧进度写到替换后的来源或新服务器账号。

## 验证
编码回归先失败（缺 snake_case 身份字段），补齐 Codable 后通过。Tests/run-playback-v2.sh、Tests/run-playback-contract.sh 均通过；Simulator 与合法签名 iPhone 构建均 BUILD SUCCEEDED，正式包覆盖安装及启动通过。身份补强以自动契约验证；不冒充指定大录播验收。

## 状态
完整 T7 指定 5,634,539,067 字节录播验收仍需只读本机副本。未 push。
