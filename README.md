# Live OS (iOS Client)

这是 `bililive-go-UI` 的专属 iOS 客户端，用于管理录播服务、查看录播视频、并通过内嵌原生高性能播放器随时随地观看录制好的视频。

![首页预览](https://github.com/user-attachments/assets/875ad881-1dbb-44fa-a0d5-3a4d1c0ebbb9)

## ✨ 核心特性

- **全新 Glassmorphism 设计**：全面拥抱 iOS 原生毛玻璃拟物化设计，提供极具沉浸感的 UI 交互体验。
- **全局触觉震动反馈 (Haptics)**：每一次点击、滑动和状态切换，都有清脆的 Taptic Engine 震动反馈。
- **多端同步与鉴权隔离**：
  - 支持配置局域网与公网服务器地址。
  - 支持服务端多用户 **API Key** 鉴权。各个客户端的数据与播放进度严格隔离，互不干扰。
- **云端备份与恢复**：支持一键导出服务器当前配置、直播间列表到本地，或通过备份 ID 随时在多端恢复。
- **智能网络切换**：自动检测当前网络环境，在家里连接 WiFi 时直连内网以获得满速体验，外出时无缝切换公网穿透域名。
- **高性能视频播放器**：
  - 基于 [pillarbox-apple](https://github.com/SRGSSR/pillarbox-apple.git) 深度定制。
  - 支持服务端实时的 HLS 转封装流媒体播放，秒开不卡顿。
  - 丰富的手势操作：左右滑动精准快进/快退，上下边缘滑动调节音量，双击暂停/播放。
  - **长按屏幕侧边触发 2x 加速，松手恢复原倍速**，完全对标主流短视频 App 体验。

## 📸 应用截图

<p align="center">
  <img src="https://github.com/user-attachments/assets/1d011f72-d2b9-4744-891e-8e211e8642fc" width="30%" />
  <img src="https://github.com/user-attachments/assets/452a5da9-5592-41e4-ad9c-97ebad94d18d" width="30%" />
  <img src="https://github.com/user-attachments/assets/14cfca0e-d538-491d-8d44-0738edcc4341" width="30%" />
</p>

## ⚙️ 配合服务端使用

此客户端是整个监控生态的终端，必须配合 [bililive-go-UI](https://github.com/xuyuanzhang1122/bililive-go-UI) 以及公网分发层服务器配合使用。

1. **部署后端与公网入口**：在服务器上启动 `bililive-go-UI`，并配置好 Nginx/frp 或类似 `image.xumy.art` 的公网访问域名。
2. **开启多用户鉴权**：在服务端的 Web UI 设置中开启 API Key。
3. **配置 iOS 网络与认证**：
   - 在 App 的【设置 -> 网络配置】中填入局域网 IP 与公网域名，开启智能切换。
   - 在【设置 -> API Key】中粘贴 Web 管理台生成的专属 Key。
4. **开始使用**：连接成功后，所有的观看历史和续播进度会自动同步到该 Key 对应的云端用户空间！

## 🚀 编译与安装

本项目暂未提供 App Store 分发，请按照以下方式安装：

### 方案 A：下载自动构建的 IPA (推荐)
前往本仓库的 **[Releases](https://github.com/xuyuanzhang1122/bililive-ios/releases)** 页面，下载由 GitHub Actions 自动构建好的 `.ipa` 文件。
> **注意**：下载的 IPA 文件未经过企业签名，无法直接在 iOS 上安装。你需要自行使用 **AltStore**、**Sideloadly** 或 **爱思助手** 等工具进行个人签名并安装。

### 方案 B：使用 Xcode 自行编译
1. 克隆本仓库到本地：`git clone https://github.com/xuyuanzhang1122/bililive-ios.git`
2. 使用 Xcode 16 或更高版本打开 `Live OS.xcodeproj`。
3. 在 "Signing & Capabilities" 中，配置你自己的 Apple ID 作为 Team，修改 Bundle Identifier。
4. 连接你的 iOS 17.0+ 设备，按下 `Cmd + R` 编译运行即可。

## 致谢

本项目在开发过程中引用了以下优秀的开源项目：
- [pillarbox-apple](https://github.com/SRGSSR/pillarbox-apple.git)

---

*由 Xumy 倾力开发。*
