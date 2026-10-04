# iOS 独立审查修复与竖屏能力

修复跨410及processing过渡的asset_version绑定：第一次ready后固定资产，每次ready回调前核验，变化取消新会话。历史DTO补可选recording/source，读取捕获原服务器认证，续播必须匹配已建立会话；无身份旧记录可展示但v2不自动续播。

指定只读录播已取得（5634539067字节，源SHA一致），实际为1080x1920 60fps High level42 SDR H264/AAC。新增独立竖屏SPS/PPS VideoToolbox真实探测，分别声明1920x1080与1080x1920，不放宽横屏上限。新原生探测回归先失败后通过，主机实际返回两个方向；手机是否支持以指定录播的后续实际时间线为准。

Tests/run-playback-v2.sh与run-playback-contract.sh通过；Simulator及签名iPhone正式包构建BUILD SUCCEEDED。独立诊断入口副本同步本轮产品Swift源码，使用单独Verification bundle验证指定大录播；正式包在结束后恢复安装。当前本报告只记代码验证，设备时间线另记。

完整跨仓独立审查来自同一fresh reviewer，5项Important唯一修复轮，详见服务端docs/superpowers/reports/2026-10-04-final-review.md；没有第二轮独立审查。未push。
