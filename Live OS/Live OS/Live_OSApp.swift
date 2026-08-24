//
//  Live_OSApp.swift
//  Live OS
//
//  Created by xu on 2026/4/24.
//

import SwiftUI

@main
struct Live_OSApp: App {
    @State private var appConfig = AppConfig()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let cache = URLCache(memoryCapacity: 50_000_000, diskCapacity: 200_000_000)
        URLCache.shared = cache
    }

    @State private var showLaunch = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(appConfig)
                if showLaunch {
                    LaunchScreenView {
                        showLaunch = false
                    }
                    .zIndex(1)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // 首次触发本地网络授权弹窗的那次探测必然失败，授权后回到前台需重测一次
                if phase == .active {
                    appConfig.refreshNetworkStatus()
                }
            }
        }
    }
}
