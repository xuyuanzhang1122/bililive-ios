# Bililive OS (iOS Client)

这是 `bililive-go-UI` 的专属 iOS 客户端，用于管理录播服务、查看录播视频、并通过内嵌播放器播放录制好的视频。

## 功能特性

- **多端同步与鉴权**：支持配置局域网与公网服务器地址，支持 API Key 鉴权。
- **智能网络切换**：自动检测当前网络环境，在局域网内使用内网地址以获得更快的访问速度。
- **视频库管理**：查看、管理已录制的视频，支持单个或批量删除。
- **直播间管理**：添加或移除直播间监控。
- **高性能播放器**：
  - HLS 流媒体播放（后端自动将 FLV/TS 转封装为 HLS）。
  - 丰富的手势操作：左右滑动快进/快退，上下滑动调节音量，双击暂停/播放。
  - 长按侧边触发 2x 加速，松手恢复原倍速。
  - 多级倍速调节（0.78x / 1x / 1.25x / 1.5x / 2x）。

## 编译与安装

本项目暂未提供 App Store 或 TestFlight 分发，需要使用 Xcode 自行编译并安装到真机。

### 环境要求

- macOS 操作系统
- Xcode 16 或更高版本
- iOS 17.0 或更高版本的 iPhone/iPad

### 编译步骤

1. 克隆本仓库到本地：
   ```bash
   git clone https://github.com/xuyuanzhang1122/bililive-ios.git
   ```
2. 在 Xcode 中打开 `Live OS.xcodeproj` 或 `Live OS.xcworkspace`。
3. 在 Xcode 的 "Signing & Capabilities" 设置中，配置你自己的 Apple ID 作为 Team，并更新 Bundle Identifier（如果需要）。
4. 通过 USB 或局域网连接你的 iOS 设备。
5. 在 Xcode 顶部选择你的设备作为目标运行环境。
6. 点击运行按钮（或按 `Cmd + R`）编译并安装 App 到设备上。

*(注：如果是免费 Apple 开发者账号，每 7 天需要重新签名一次)*

## 配合服务端使用

此客户端需配合 [bililive-go-UI](https://github.com/xuyuanzhang1122/bililive-go-UI) 服务端使用。

1. 在服务端的 Web UI 设置中开启 API Key。
2. 在 App 的设置界面填入服务端的局域网 IP / 公网域名，以及 API Key。
3. 连接成功后即可开始管理你的录播视频。
