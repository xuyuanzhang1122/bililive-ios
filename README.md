<div align="center">

<img src="Live%20OS/Live%20OS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-Light.png" width="120" alt="Live OS" />

# 📱 Live OS

**bililive-go 的随身遥控器 —— 躺床上用手机刷录播**

管直播间、看录播、续播进度和电脑端同步，一个 App 全搞定。

[![Release](https://img.shields.io/github/v/release/xuyuanzhang1122/bililive-ios?style=flat-square&color=4c8eda&label=最新版本)](https://github.com/xuyuanzhang1122/bililive-ios/releases)
[![Platform](https://img.shields.io/badge/iOS-17.0+-000000?style=flat-square&logo=apple)](https://github.com/xuyuanzhang1122/bililive-ios/releases)
[![Build](https://img.shields.io/github/actions/workflow/status/xuyuanzhang1122/bililive-ios/ios-ipa-build.yml?style=flat-square&label=IPA%20构建)](https://github.com/xuyuanzhang1122/bililive-ios/actions)

[功能](#-能做什么) · [截图](#-应用截图) · [安装](#-怎么装) · [配合服务端](#%EF%B8%8F-配合服务端使用)

<br>

<img src="https://github.com/user-attachments/assets/875ad881-1dbb-44fa-a0d5-3a4d1c0ebbb9" width="85%" alt="首页预览" />

</div>

---

## 👋 这是什么

[bililive-go-UI](https://github.com/xuyuanzhang1122/bililive-go-UI) 的专属 iOS 客户端。后端在服务器上挂着录直播，这个 App 就是你手里的终端：加直播间、刷录播、看直播状态，电脑上看到一半的视频拿手机接着看，进度还是连着的。

> 💡 纯原生开发，播放器基于 [pillarbox-apple](https://github.com/SRGSSR/pillarbox-apple) 深度定制，秒开不卡。

---

## ✨ 能做什么

### 🎬 看录播

- **视频库 + 内嵌播放器**：录好的视频按主播归类，点开就放
- **进度跟电脑端同步**：服务端记录观看历史，换设备接着看，精确从上次的秒数续播
- **画中画**：切后台也能继续放

### 🎮 播放器手势（对标主流短视频 App）

- 横滑 **快进快退**、竖滑调 **音量 / 亮度**、双击 **暂停**
- **长按屏幕两侧 → 下拉锁定 2 倍速**，松手不掉速；再长按下拉解锁
- 右下角 **倍速菜单**：0.5x / 0.75x / 1x / 1.25x / 1.5x / 2x / 3x 点选

### ☁️ 备份与找回

- **一键导出**：服务器配置 + 直播间列表打包，存手机本地（可分享）或上传云端拿一个短 ID
- **换机 / 重装找回**：输入短 ID，自动还原配置、重启服务、双端重新同步 —— 服务器重置了也不怕配置丢

### 🔐 多端与鉴权

- **智能网络切换**：在家自动走局域网满速，出门无缝切公网域名
- **多用户 API Key**：每个客户端的历史、进度严格隔离，互不串台

### 🧊 设计

- **Liquid Glass 毛玻璃质感** UI，适配 iOS 26
- **全局触觉反馈**：点击、滑动、状态切换都有 Taptic Engine 震动

---

## 📸 应用截图

<div align="center">
  <img src="https://github.com/user-attachments/assets/1d011f72-d2b9-4744-891e-8e211e8642fc" width="30%" />
  <img src="https://github.com/user-attachments/assets/452a5da9-5592-41e4-ad9c-97ebad94d18d" width="30%" />
  <img src="https://github.com/user-attachments/assets/14cfca0e-d538-491d-8d44-0738edcc4341" width="30%" />
</div>

---

## 🚀 怎么装

> 暂未上架 App Store，两种方式任选。

### 方案 A：下载现成 IPA（推荐）

去 **[Releases](https://github.com/xuyuanzhang1122/bililive-ios/releases)** 页下载构建好的 `.ipa`。

> ⚠️ IPA 没经过企业签名，不能直接装。用 **AltStore** / **Sideloadly** / **爱思助手** 做个人签名后安装。

### 方案 B：Xcode 自己编译

```bash
git clone https://github.com/xuyuanzhang1122/bililive-ios.git
```

1. Xcode 16+ 打开 `Live OS.xcodeproj`
2. 在 **Signing & Capabilities** 里填自己的 Apple ID 作为 Team，改一下 Bundle Identifier
3. 连上 iOS 17.0+ 的设备，`Cmd + R` 跑起来

---

## ⚙️ 配合服务端使用

这个 App 是终端，得配合 [bililive-go-UI](https://github.com/xuyuanzhang1122/bililive-go-UI) 用（备份/找回还需要配套源站，不配也不影响看录播）。

| 步骤 | 做什么 |
|:---:|------|
| **1** | 服务器上跑起 `bililive-go-UI`，配好局域网 IP 或公网域名 |
| **2** | 服务端 Web 设置页开启 **API Key** |
| **3** | App【设置 → 网络配置】填局域网 IP + 公网域名，开智能切换 |
| **4** | App【设置 → API Key】粘贴服务端生成的 Key |
| **5** | （可选）App【设置 → 备份服务器】填源站地址，启用云备份找回 |

连上之后，观看历史和续播进度会自动同步到这个 Key 对应的云端空间。

---

## 🙏 致谢

- 播放器内核 [pillarbox-apple](https://github.com/SRGSSR/pillarbox-apple) — SRG SSR
- 配套后端 [bililive-go-UI](https://github.com/xuyuanzhang1122/bililive-go-UI)

<div align="center">

**喜欢的话点个 ⭐ Star～ · 由 Xumy 倾力开发**

</div>
