//
//  ContentView.swift
//  Live OS
//
//  Created by xu on 2026/4/24.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppConfig.self) private var appConfig

    var body: some View {
        TabView {
            VideoLibraryView()
                .tabItem {
                    Label("视频库", systemImage: "play.rectangle.on.rectangle")
                }
            RoomListView()
                .tabItem {
                    Label("直播间", systemImage: "antenna.radiowaves.left.and.right")
                }
            HistoryView()
                .tabItem {
                    Label("历史", systemImage: "clock")
                }
            SettingsView(isInitialSetup: false)
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
        }
        .tint(Color(red: 0.12, green: 0.86, blue: 0.78)) // A modern teal/cyan accent color
        .overlay(alignment: .top) {
            if appConfig.activeURL.isEmpty {
                unconfiguredBanner
            }
        }
    }

    private var unconfiguredBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("未配置服务器")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text("请前往“设置”填写地址以使用完整功能")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appConfig.activeURL.isEmpty)
    }
}

#Preview {
    ContentView()
        .environment(AppConfig())
}
