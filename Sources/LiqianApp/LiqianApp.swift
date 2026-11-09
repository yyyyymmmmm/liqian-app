import SwiftData
import SwiftUI
import LiqianCore

/// 界面语言（v5.13 语言全跟随）：偏好存 UserDefaults（Core
/// AppLanguage 单点口径），根视图据此定环境 locale——SwiftUI
/// 字面文案查表、DatePicker 等系统控件的语言都随之切换，即时生效。

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

    /// 问账会话持有者（v5.8）：页面无关地持有问账消息与在途问答，
    /// 离页/杀进程不再丢回复（见 AdvisorSession 与 docs/V58-NOTES.md）
    @StateObject private var advisorSession = AdvisorSession()

    @AppStorage(AppLanguagePreference.storageKey) private var languageRaw = AppLanguagePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 全 App 语言（v5.13 修订 v2.4 固定 zh_CN）：按语言偏好
                // 解析——简体 zh_CN（日期控件中文格式，与旧版一致）、
                // 繁体 zh-Hant；跟随系统时非中文/简体中文回落简体。
                .environment(\.locale, Locale(identifier: AppLanguage.resolve(
                    preference: AppLanguagePreference(storedRaw: languageRaw),
                    preferredLanguages: Locale.preferredLanguages
                ).localeIdentifier))
                .environmentObject(cloudSync)
                .environmentObject(entitlements)
                .environmentObject(advisorSession)
        }
        .modelContainer(cloudSync.container)
    }
}
