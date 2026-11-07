import SwiftData
import SwiftUI
import LiqianCore

@main
struct LiqianApp: App {
    /// 长按快捷菜单承接（v4.5）：回调只在 AppDelegate 里有，见 ShortcutActions.swift
    @UIApplicationDelegateAdaptor(LiqianAppDelegate.self) private var appDelegate

    /// 容器与 iCloud 同步状态统一由 CloudSyncManager 持有：
    /// 容器在此一次性按「开关 + CloudKit 可用性」选定（CloudKit 失败回退本地），
    /// 全 App 共用同一个容器，降级路径见 CloudSync.swift。
    @StateObject private var cloudSync = CloudSyncManager()

    /// Pro 权益单点（v5）：全 App 共用一个实例，各门控面只问它
    @StateObject private var entitlements = EntitlementCenter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 全 App 固定中文区域：DatePicker 等系统控件跟随显示中文日期
                // （v2.4 必修：此前日期选择器显示 "Nov 7, 2026" 英文格式）
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .environmentObject(cloudSync)
                .environmentObject(entitlements)
        }
        .modelContainer(cloudSync.container)
    }
}
