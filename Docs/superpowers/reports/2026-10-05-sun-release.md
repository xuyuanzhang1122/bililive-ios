# iOS sun 发布验证

用户已授权正式 Release 和推送。数字包版本 3.0.0、构建号 6，LiveOSReleaseName sun；设置 sun（3.0.0），关于页新增本次迭代并保留旧记录，应用名称不再为 RC Preview。

Xcode 27 无签名 Release iphoneos 构建成功。本地 IPA ZIP 完整性及 Info.plist 3.0.0 / 6 / sun 通过；本地结果不替代 GitHub Xcode26.4.1 构建结论。

公开资产 LiveOS.ipa 未签名，需自行个人重签，不是 App Store / TestFlight 分发。建议搭配服务端 sun，旧服务端适配保留。

GitHub Xcode26.4.1 运行 37300317425 已 success；Actions IPA 与 Release 实际下载文件逐字节一致，GitHub digest、ZIP、Mach-O 与 3.0.0 / 6 / sun 元数据通过。公开地址 https://github.com/xuyuanzhang1122/bililive-ios/releases/tag/sun；SHA256 e15416859de9c9eb734e2779f8f4aa16f99bab97f9caf54943fbfe2ab2aaf663，大小 8699764 字节。播放契约与 v2 会话回归均通过。详情见相邻 sun-ipa-evidence.json。指定大文件之前 iPhone 时间线验证与本轮版本同步区分记录，不虚称新增硬件矩阵验收。
