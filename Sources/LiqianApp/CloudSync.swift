import CloudKit
import CoreData
import Foundation
import SwiftData
import SwiftUI
import UIKit
import LiqianCore

/// iCloud 同步（feat/icloud）：SwiftData + CloudKit 私有数据库自动同步。
///
/// 降级总原则：**绝不闪退、绝不丢数据**。
/// - 存储模式只在启动时决定一次：开关开 → 先试 CloudKit 配置，创建抛错
///   立刻回退本地配置（两者同为默认存储位置，本地数据原地保留、原地继续用）。
/// - 账号状态用 CKContainer.accountStatus 异步探测，只影响状态展示：
///   未登录时数据先存本机（CloudKit 镜像会等账号可用后自动补同步）。
/// - 侧载重签剥掉 iCloud entitlement 时，CloudKit 配置创建多半失败或账号
///   探测报错 → 状态落到 .unavailable，界面明示当前安装方式不支持同步。
/// - 同步开关改动写 UserDefaults，下次启动才切换存储模式（界面有明示）。
@MainActor
final class CloudSyncManager: ObservableObject {

    /// CloudKit 容器 ID：iCloud. + App bundle id（与 Project.swift 的 entitlement 保持一致）
    static let containerIdentifier = "iCloud.site.didichou.liqian"
    /// 同步开关的 UserDefaults 键（默认开）
    static let enabledKey = "icloudSyncEnabled"

    /// 界面状态（「我的 → 数据」的 iCloud 行读它）
    enum Status: Equatable {
        /// 用户关了开关：仅本地
        case disabled
        /// 账号状态探测中
        case checking
        /// 同步进行中（有导入/导出事件未结束）
        case syncing
        /// 已同步（引擎启用且最近一次同步事件成功；或尚无事件待处理）
        case synced
        /// 未登录 iCloud
        case notSignedIn
        /// iCloud 账号受限（家长控制/组织策略等）
        case restricted
        /// 当前环境用不了 CloudKit（侧载剥 entitlement、容器异常等）：已回退本地
        case unavailable
    }

    /// 本次启动实际选定的存储模式（启动后不变）
    enum StoreMode: Equatable {
        case cloudKit
        case localOnly
    }

    /// 启动决策（区分本地模式的成因，文案与待生效判断用）
    private enum LaunchDecision: Equatable {
        case cloudKit
        /// 启动时开关就是关的
        case localByUserChoice
        /// CloudKit 配置创建失败后回退
        case localByFallback
        /// 连本地文件存储都失败，临时内存存储兜底（数据异常，明示用户）
        case emergencyMemory
    }

    private enum AccountState: Equatable {
        case unknown
        case available
        case noAccount
        case restricted
        case error
    }

    @Published private(set) var status: Status = .checking

    /// 容器：LiqianApp 用它挂 .modelContainer
    let container: ModelContainer
    /// 本次启动的实际存储模式
    let storeMode: StoreMode
    private let launchDecision: LaunchDecision
    private let enabledAtLaunch: Bool

    /// 用户开关：写 UserDefaults；下次启动才切换存储模式
    @Published var syncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(syncEnabled, forKey: Self.enabledKey)
            recomputeStatus()
        }
    }

    private var accountState: AccountState = .unknown
    private var syncBusy = false
    // 观察者 token 只在主线程增删、deinit 里统一移除；NSObjectProtocol 非 Sendable，
    // Swift 6 下用 nonisolated(unsafe) 承接这一既定用法（deinit 无法访问隔离属性）。
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init() {
        let enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        self.syncEnabled = enabled
        self.enabledAtLaunch = enabled

        let schema = Schema([
            Ledger.self, GiftRecord.self, ReminderDay.self, LedgerMember.self,
            GuestSignature.self, VoiceBlessing.self
        ])
        if !enabled {
            let local = Self.makeLocalContainer(schema: schema)
            self.container = local.container
            self.storeMode = .localOnly
            self.launchDecision = local.emergency ? .emergencyMemory : .localByUserChoice
        } else if Self.hasCloudKitEntitlement(), let cloud = Self.makeCloudContainer(schema: schema) {
            self.container = cloud
            self.storeMode = .cloudKit
            self.launchDecision = .cloudKit
        } else {
            let local = Self.makeLocalContainer(schema: schema)
            self.container = local.container
            self.storeMode = .localOnly
            self.launchDecision = local.emergency ? .emergencyMemory : .localByFallback
        }

        recomputeStatus()
        registerObservers()
        if storeMode == .cloudKit {
            Task { await refreshAccountStatus() }
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 容器工厂（分级回退）

    /// 运行时 entitlement 探针：侧载重签会剥掉 iCloud 容器 entitlement，此时
    /// 强行构造 CloudKit 容器会触发不可捕获的异常、启动直接闪退（v4.0 真机
    /// 实锤：开关默认开，升级后首次启动即走到 CloudKit 路径）。先查内嵌
    /// 描述文件，含本容器 ID 才放行 CloudKit 路径；查不到描述文件
    /// （App Store 包的 entitlements 在二进制内）时放行，仍有 try? 回退兜底。
    private static func hasCloudKitEntitlement() -> Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(bytes: data, encoding: .isoLatin1) else {
            return true
        }
        return text.contains(containerIdentifier)
    }

    /// CloudKit 配置：与本地配置同为默认存储位置，切换/回退不搬家、不丢数据
    private static func makeCloudContainer(schema: Schema) -> ModelContainer? {
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private(containerIdentifier)
        )
        return try? ModelContainer(for: schema, configurations: [config])
    }

    /// 本地配置；文件存储再失败则内存存储兜底（至少 App 能打开并明示异常）
    private static func makeLocalContainer(schema: Schema) -> (container: ModelContainer, emergency: Bool) {
        let fileConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [fileConfig]) {
            return (container, false)
        }
        let memoryConfig = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        // schema 是编译期内建的，内存容器再失败说明二进制损坏——此时无路可退
        let container = try! ModelContainer(for: schema, configurations: [memoryConfig])
        return (container, true)
    }

    // MARK: - 账号探测与同步事件

    /// 异步探测 iCloud 账号状态（只影响展示；本地读写从不依赖它）
    func refreshAccountStatus() async {
        guard storeMode == .cloudKit else { return }
        let container = CKContainer(identifier: Self.containerIdentifier)
        do {
            switch try await container.accountStatus() {
            case .available:
                accountState = .available
            case .noAccount:
                accountState = .noAccount
            case .restricted:
                accountState = .restricted
            default:
                accountState = .error
            }
        } catch {
            accountState = .error
        }
        recomputeStatus()
    }

    private func registerObservers() {
        // iCloud 账号登录/退出时重新探测
        let accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccountStatus() }
        }
        observers.append(accountObserver)

        // 回前台时刷新一次（用户可能刚去系统设置里登录了 iCloud）
        let activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccountStatus() }
        }
        observers.append(activeObserver)

        guard storeMode == .cloudKit else { return }
        // CloudKit 镜像的导入/导出事件 → 同步中/已同步
        let syncObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: nil
        ) { [weak self] note in
            guard let event = note.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            // Event 非 Sendable：先在当前线程摘出需要的事实（是否导入/导出、是否结束），
            // 只把 Sendable 的 Bool 带进 MainActor 任务，避免数据竞争告警。
            let isSyncType = event.type == .import || event.type == .export
            let finished = event.endDate != nil
            Task { @MainActor in self?.handleSyncEvent(isSyncType: isSyncType, finished: finished) }
        }
        observers.append(syncObserver)
    }

    private func handleSyncEvent(isSyncType: Bool, finished: Bool) {
        guard isSyncType else { return }
        if finished {
            syncBusy = false
            // 单次事件失败多为网络抖动，镜像会自动重试，不据此翻成不可用
        } else {
            syncBusy = true
        }
        recomputeStatus()
    }

    private func recomputeStatus() {
        if launchDecision == .emergencyMemory {
            status = .unavailable
            return
        }
        guard syncEnabled else {
            status = .disabled
            return
        }
        guard storeMode == .cloudKit else {
            status = .unavailable
            return
        }
        switch accountState {
        case .noAccount:
            status = .notSignedIn
        case .restricted:
            status = .restricted
        case .error:
            status = .unavailable
        case .unknown:
            status = .checking
        case .available:
            status = syncBusy ? .syncing : .synced
        }
    }

    // MARK: - 界面文案

    /// 状态行副标题（人话，说明现状与后果）
    var statusSubtitle: String {
        if hasPendingChange {
            return syncEnabled ? "已开启，下次打开 App 时开始同步" : "已关闭，下次打开 App 时停止同步"
        }
        switch status {
        case .disabled:
            return "已关闭，数据只存在这台手机上"
        case .checking:
            return "正在检查 iCloud 状态…"
        case .syncing:
            return "正在同步到你的 iCloud…"
        case .synced:
            return "已开启，换手机或重装后数据自动回来"
        case .notSignedIn:
            return "未登录 iCloud，先存在这台手机上"
        case .restricted:
            return "iCloud 账号受限，暂时无法同步"
        case .unavailable:
            if launchDecision == .emergencyMemory {
                return "数据存储异常，请先导出备份，再联系支持"
            }
            return "当前安装方式不支持 iCloud 同步，数据保存在本机"
        }
    }

    /// 开关已改但存储模式下次启动才切换
    var hasPendingChange: Bool { syncEnabled != enabledAtLaunch }

    /// 未登录时给出「去设置」入口
    var showsSettingsShortcut: Bool { status == .notSignedIn && !hasPendingChange }
}
