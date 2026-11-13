import CloudKit
import CoreData
import Foundation
import SwiftData
import SwiftUI
import UIKit
import os
import LiqianCore

/// iCloud 同步（feat/icloud）：SwiftData + CloudKit 私有数据库自动同步。
///
/// 降级总原则：**绝不闪退、绝不丢数据**。
/// - 账号状态用 CKContainer.accountStatus 异步探测，只影响状态展示：
///   未登录时数据先存本机（CloudKit 镜像会等账号可用后自动补同步）。
/// - 侧载重签剥掉 iCloud entitlement 时，CloudKit 容器创建多半失败或
///   账号探测报错 → 状态落到 .unavailable，界面明示当前安装方式
///   不支持同步。
/// - 同步开关改动写 UserDefaults，下次启动才切换存储模式（界面有明示）。
///
/// 存储模式锁定（v5.14.2，四线会诊定因后立的规矩）：旧版每启重判
/// 存储模式（开关＋entitlement 探针＋CloudKit 创建成败三个输入都
/// 可能跨启动翻转），两份配置又都没显式指定 store URL——用户数据
/// 疑似写进一个店面、后续启动读另一个而「消失」。自本版起：
/// ① 模式只在首次决策（或用户在设置里显式改开关）时定版并写
///    UserDefaults 锁定，后续启动直接用锁定模式，不许静默翻转；
/// ② 本地模式显式指定 Application Support 下的固定 store URL；
/// ③ CloudKit 创建错误不再被 try? 吞，进 store 日志；每次启动的
///    模式/依据/store 路径与大小记日志并在「我的 → 数据」显形；
/// ④ 容器建好后做写-回读自检，失败或内存模式一律硬显形并阻断记账；
/// ⑤ 搁浅数据救援（StoreRescue）把其他候选店面里主店没有的礼簿
///    按 ID 去重并入，并给用户可见回执。救援自 v5.14.3 起移出
///    init：ContentView 首帧后才跑、开扫前先写尝试计数、建
///    CloudKit 容器只许走本文件唯一入口（含 entitlement 门禁）——
///    v5.14.2 救援在 init 尾部无门禁直建 CloudKit 容器，重签无
///    entitlement 环境触发不可捕获异常，且完成标志后写，装机
///    每启必崩（定因见 liqian-review/v5142-crash-diag.md）。
@MainActor
final class CloudSyncManager: ObservableObject {

    /// CloudKit 容器 ID：iCloud. + App bundle id（与 Project.swift 的 entitlement 保持一致）
    static let containerIdentifier = "iCloud.site.didichou.liqian"
    /// 同步开关的 UserDefaults 键（默认开）
    static let enabledKey = "icloudSyncEnabled"
    /// 存储模式锁定的 UserDefaults 键（v5.14.2）：值 "cloudKit" / "local"
    static let modeLockKey = "storeModeLock"
    /// 锁定依据的 UserDefaults 键（v5.14.2）：Basis 的 rawValue
    static let modeLockBasisKey = "storeModeLockBasis"
    /// 上次启动模式 token 的 UserDefaults 键（v5.14.2，诊断行对比用）
    static let lastModeKey = "storeModeLastLaunch"
    /// 搁浅数据救援完成标志（v5.14.2）：置位后不再重跑，幂等守门
    static let rescueDoneKey = "storeRescueV5142Done"
    /// 救援尝试计数（v5.14.3）：开扫**之前**先自增落盘——崩在半途
    /// 计数已增，配合上限杜绝「标志后写、崩即每启必崩」死循环
    static let rescueAttemptsKey = "storeRescueAttempts"
    /// 救援自动尝试上限（v5.14.3）：未完成且计数达此数即停自动跑
    static let rescueMaxAttempts = 2

    static let storeLogger = Logger(subsystem: "site.didichou.liqian", category: "store")

    /// 锁定依据（落 UserDefaults 的是 rawValue，改名即断锁，慎改）
    private enum Basis: String {
        /// 探针与创建都通过，CloudKit 可用
        case cloudKitAvailable
        /// 用户把同步开关关了
        case userChoiceOff
        /// entitlement 探针判定无 iCloud 容器（重签环境常态）
        case noEntitlement
        /// CloudKit 容器创建抛错（原文进日志）
        case cloudKitCreateFailed
    }

    /// 本地模式的显式 store 文件（v5.14.2）：固定落在 Application
    /// Support，不再依赖「默认位置两配置相同」的未证假设
    static var localStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiqianLocal.store")
    }

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

    /// 一次启动的决策产物（launch(schema:enabled:) 的返回值）
    private struct LaunchOutcome {
        var container: ModelContainer
        var mode: StoreMode
        var decision: LaunchDecision
        var basis: String
        var emergency: Bool
    }

    @Published private(set) var status: Status = .checking

    /// 容器：LiqianApp 用它挂 .modelContainer
    let container: ModelContainer
    /// 本次启动建容器用的模型清单（救援在首帧后跑，届时复用同一份）
    private let schema: Schema
    /// 本次启动的实际存储模式
    let storeMode: StoreMode
    /// 「我的 → 数据」的存储诊断小字（模式＋文件＋大小，启动时定版）
    let diagnosticLine: String
    private let launchDecision: LaunchDecision
    private let launchBasis: String
    private let enabledAtLaunch: Bool

    /// 存储不安全（v5.14.2）：内存模式、落盘自检失败或救援落盘失败。
    /// 此态下记什么都可能关 App 即丢——ContentView 挂固定红条＋
    /// 启动弹窗，各记账入口整页阻断，绝不沉默。
    @Published private(set) var storageUnsafe = false
    /// 搁浅数据救援回执（v5.14.2）：真找回数据时才置位，界面弹给用户看
    @Published private(set) var rescueReceipt: String?

    /// 用户开关：写 UserDefaults；下次启动才切换存储模式（＝显式改锁）
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
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        self.syncEnabled = enabled
        self.enabledAtLaunch = enabled

        let schema = Self.makeSchema()
        self.schema = schema
        let previousToken = defaults.string(forKey: Self.lastModeKey)
        let outcome = Self.launch(schema: schema, enabled: enabled, defaults: defaults)
        self.container = outcome.container
        self.storeMode = outcome.mode
        self.launchDecision = outcome.decision
        self.launchBasis = outcome.basis

        // —— 决策留痕：模式/依据/store 路径与大小进日志＋诊断行 ——
        let info = Self.storeInfo(for: outcome.container, emergency: outcome.emergency)
        let token = outcome.emergency ? "emergency"
            : (outcome.mode == .cloudKit ? "cloudKit" : "local")
        var diagLine = Self.makeDiagnosticLine(
            mode: outcome.mode, emergency: outcome.emergency,
            url: info.url, bytes: info.bytes, flipped: previousToken != nil && previousToken != token
        )
        // 救援已达尝试上限且仍未完成（v5.14.3）：不再自动跑，
        // 在诊断行显形——用户截图回传即可判读
        if !defaults.bool(forKey: Self.rescueDoneKey),
           defaults.integer(forKey: Self.rescueAttemptsKey) >= Self.rescueMaxAttempts {
            diagLine += "（" + L10n.string("旧数据查找已暂停") + "）"
        }
        self.diagnosticLine = diagLine
        defaults.set(token, forKey: Self.lastModeKey)
        Self.storeLogger.info(
            "launch token=\(token, privacy: .public) basis=\(outcome.basis, privacy: .public) store=\(info.url?.path ?? "-", privacy: .public) bytes=\(info.bytes ?? -1) prev=\(previousToken ?? "-", privacy: .public)"
        )

        // —— 落盘自检：内存模式直接判不安全；文件模式写-回读探针 ——
        var unsafe = outcome.emergency
        if !outcome.emergency, !Self.runProbe(container: outcome.container) {
            unsafe = true
        }
        self.storageUnsafe = unsafe

        recomputeStatus()
        registerObservers()
        if storeMode == .cloudKit {
            Task { await refreshAccountStatus() }
        }

        // —— 搁浅数据救援不在 init 里跑（v5.14.3）：改由
        // ContentView 首帧后 .task 调 runRescueIfNeeded()——救援
        // 打开候选店面属于重活且有平台异常面，绝不许再压在启动
        // 关键路径上（v5.14.2 在此派发、首候选无门禁建 CloudKit
        // 容器，重签环境装机每启必崩，见 crash-diag 报告）
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// 全 App 共用的模型清单（容器与救援候选店面同口径）
    static func makeSchema() -> Schema {
        Schema([
            Ledger.self, GiftRecord.self, ReminderDay.self, LedgerMember.self,
            GuestSignature.self, VoiceBlessing.self,
            GuestEventBinding.self, GuestReceipt.self,
            StorageProbe.self
        ])
    }

    // MARK: - 启动决策（锁定优先，显式改锁才重决）

    /// 存储模式决策（v5.14.2）：
    /// - 已有锁定且开关状态与锁定依据不矛盾 → 直接按锁定开店，不重判；
    ///   锁定 CloudKit 而本次创建失败时只本次回退本地（锁不动、日志留痕、
    ///   诊断行显形），不许静默改锁。
    /// - 无锁定（本版首启/老用户升级）或用户显式改过开关 → 重新决策：
    ///   开关关→本地；探针判定无 entitlement→本地锁定；CloudKit 创建
    ///   成功→CloudKit 锁定；创建抛错→本地锁定（错误原文进日志）。
    ///   决策结果当场落锁。
    private static func launch(schema: Schema, enabled: Bool, defaults: UserDefaults) -> LaunchOutcome {
        let lockedMode = defaults.string(forKey: modeLockKey)
        let lockedBasis = defaults.string(forKey: modeLockBasisKey)
        // 显式改锁判定：开关关着而锁不是「关着的本地」，或开关开着而锁
        // 是「用户关掉的本地」——都说明用户在设置里动过开关，以开关为准
        let explicitChange: Bool
        if enabled {
            explicitChange = lockedMode == "local" && lockedBasis == Basis.userChoiceOff.rawValue
        } else {
            explicitChange = !(lockedMode == "local" && lockedBasis == Basis.userChoiceOff.rawValue)
        }

        if let lockedMode, !explicitChange {
            if lockedMode == "cloudKit" {
                let cloud = makeCloudContainer(schema: schema)
                if let container = cloud.container {
                    return LaunchOutcome(
                        container: container, mode: .cloudKit, decision: .cloudKit,
                        basis: lockedBasis ?? Basis.cloudKitAvailable.rawValue, emergency: false)
                }
                storeLogger.error(
                    "locked cloudKit container failed this launch, fallback to local once: \(cloud.error?.localizedDescription ?? "?", privacy: .public)")
                let local = makeLocalContainer(schema: schema)
                return LaunchOutcome(
                    container: local.container, mode: .localOnly,
                    decision: local.emergency ? .emergencyMemory : .localByFallback,
                    basis: lockedBasis ?? Basis.cloudKitAvailable.rawValue, emergency: local.emergency)
            }
            let local = makeLocalContainer(schema: schema)
            let decision: LaunchDecision = local.emergency ? .emergencyMemory
                : (lockedBasis == Basis.userChoiceOff.rawValue ? .localByUserChoice : .localByFallback)
            return LaunchOutcome(
                container: local.container, mode: .localOnly, decision: decision,
                basis: lockedBasis ?? "", emergency: local.emergency)
        }

        // 首次决策 / 显式改锁：结果落锁
        func lock(_ mode: String, _ basis: Basis) {
            defaults.set(mode, forKey: modeLockKey)
            defaults.set(basis.rawValue, forKey: modeLockBasisKey)
        }
        if !enabled {
            let local = makeLocalContainer(schema: schema)
            lock("local", .userChoiceOff)
            return LaunchOutcome(
                container: local.container, mode: .localOnly,
                decision: local.emergency ? .emergencyMemory : .localByUserChoice,
                basis: Basis.userChoiceOff.rawValue, emergency: local.emergency)
        }
        guard hasCloudKitEntitlement() else {
            let local = makeLocalContainer(schema: schema)
            lock("local", .noEntitlement)
            return LaunchOutcome(
                container: local.container, mode: .localOnly,
                decision: local.emergency ? .emergencyMemory : .localByFallback,
                basis: Basis.noEntitlement.rawValue, emergency: local.emergency)
        }
        let cloud = makeCloudContainer(schema: schema)
        if let container = cloud.container {
            lock("cloudKit", .cloudKitAvailable)
            return LaunchOutcome(
                container: container, mode: .cloudKit, decision: .cloudKit,
                basis: Basis.cloudKitAvailable.rawValue, emergency: false)
        }
        // 创建失败不再被 try? 静默吞：错误原文进日志，落本地并锁定
        storeLogger.error(
            "cloud container creation failed, lock local: \(cloud.error?.localizedDescription ?? "?", privacy: .public)")
        let local = makeLocalContainer(schema: schema)
        lock("local", .cloudKitCreateFailed)
        return LaunchOutcome(
            container: local.container, mode: .localOnly,
            decision: local.emergency ? .emergencyMemory : .localByFallback,
            basis: Basis.cloudKitCreateFailed.rawValue, emergency: local.emergency)
    }

    // MARK: - 容器工厂（分级回退）

    /// 运行时 entitlement 探针：侧载重签会剥掉 iCloud 容器 entitlement，此时
    /// 强行构造 CloudKit 容器会触发不可捕获的异常、启动直接闪退（v4.0 真机
    /// 实锤：开关默认开，升级后首次启动即走到 CloudKit 路径）。先查内嵌
    /// 描述文件，含本容器 ID 才放行 CloudKit 路径；查不到描述文件
    /// （App Store 包的 entitlements 在二进制内）时放行，仍有创建回退兜底。
    private static func hasCloudKitEntitlement() -> Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(bytes: data, encoding: .isoLatin1) else {
            return true
        }
        return text.contains(containerIdentifier)
    }

    /// 全仓唯一「建 CloudKit 容器」入口（v5.14.3 收口）：主启动链
    /// 与搁浅救援共用，任何地方不得绕过它直接构造带
    /// cloudKitDatabase 的容器（源码守卫单测钉死）。入口内先过
    /// entitlement 门禁：探针不过直接拒建（entitled=false），
    /// 绝不真去构造——无 entitlement 强建会触发不可捕获异常、
    /// 启动即崩（v4.0 实锤；v5.14.2 救援绕过门禁直建正是装机
    /// 每启必崩的崩点）。创建错误原样交出，不许 try? 吞。
    /// CloudKit 配置保持平台要求形态（不显式指定 URL，平台镜像
    /// 的店面位置由诊断行与日志暴露，见 storeInfo）。
    static func makeCloudKitContainer(
        schema: Schema
    ) -> (container: ModelContainer?, entitled: Bool, error: Error?) {
        guard hasCloudKitEntitlement() else {
            storeLogger.error("cloudKit container refused at gateway: no entitlement")
            return (nil, false, nil)
        }
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private(containerIdentifier)
        )
        do {
            return (try ModelContainer(for: schema, configurations: [config]), true, nil)
        } catch {
            return (nil, true, error)
        }
    }

    /// 主启动链的薄封装（v5.14.3 起实现收敛到唯一入口）
    private static func makeCloudContainer(schema: Schema) -> (container: ModelContainer?, error: Error?) {
        let gate = makeCloudKitContainer(schema: schema)
        return (gate.container, gate.error)
    }

    /// 本地配置（v5.14.2 起显式固定 URL）；文件存储再失败则内存兜底
    /// （至少 App 能打开并按存储异常硬显形）
    private static func makeLocalContainer(schema: Schema) -> (container: ModelContainer, emergency: Bool) {
        let url = localStoreURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fileConfig = ModelConfiguration(
            schema: schema, url: url, cloudKitDatabase: .none
        )
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

    // MARK: - 落盘自检与诊断

    /// 写-回读探针（v5.14.2）：探针记录写入→save→换新 context 按 token
    /// 回读核对→删除→save。任一步失败即判存储不安全。探针实体独立、
    /// 不进备份/列表/统计，删不净也无害（下次启动先清残留）。
    private static func runProbe(container: ModelContainer) -> Bool {
        do {
            let writer = ModelContext(container)
            for row in try writer.fetch(FetchDescriptor<StorageProbe>()) {
                writer.delete(row)
            }
            let token = UUID()
            writer.insert(StorageProbe(token: token))
            try writer.save()
            let reader = ModelContext(container)
            let found = try reader.fetch(
                FetchDescriptor<StorageProbe>(predicate: #Predicate { $0.token == token }))
            guard found.count == 1 else {
                storeLogger.error("store probe read-back mismatch: \(found.count, privacy: .public)")
                return false
            }
            for row in found { reader.delete(row) }
            try reader.save()
            return true
        } catch {
            storeLogger.error("store probe failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 实际店面位置与大小（诊断/日志用；内存模式无文件可报）
    private static func storeInfo(
        for container: ModelContainer, emergency: Bool
    ) -> (url: URL?, bytes: Int?) {
        guard !emergency, let url = container.configurations.first?.url else {
            return (nil, nil)
        }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
        return (url, bytes)
    }

    /// 诊断小字（「我的 → 数据」）：当前存储模式＋店面文件名＋大小；
    /// 与上次启动模式不同时后缀显形——翻转从此看得见
    private static func makeDiagnosticLine(
        mode: StoreMode, emergency: Bool, url: URL?, bytes: Int?, flipped: Bool
    ) -> String {
        let modeWord: String
        if emergency {
            modeWord = L10n.string("内存（异常）")
        } else if mode == .cloudKit {
            modeWord = "iCloud"
        } else {
            modeWord = L10n.string("本机")
        }
        let sizeWord = bytes.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        } ?? "—"
        var line = L10n.format("存储诊断：%@ · %@ · %@", modeWord, url?.lastPathComponent ?? "—", sizeWord)
        if flipped {
            line += "（" + L10n.string("与上次启动不同") + "）"
        }
        return line
    }

    /// 救援回执看过后关闭（ContentView 的回执弹窗用）
    func dismissRescueReceipt() {
        rescueReceipt = nil
    }

    /// 救援可否碰 CloudKit 候选（v5.14.3）：entitlement 门禁探针不过、
    /// 或本次锁定依据本身就记着 CloudKit 走不通（noEntitlement /
    /// cloudKitCreateFailed）时关门——救援只扫本地候选，绝不许
    /// 绕开门禁（v5.14.2 崩点正是救援无门禁直建 CloudKit 容器）
    private var rescueCloudKitAllowed: Bool {
        guard Self.hasCloudKitEntitlement() else { return false }
        return launchBasis != Basis.noEntitlement.rawValue
            && launchBasis != Basis.cloudKitCreateFailed.rawValue
    }

    /// 搁浅数据救援触发点（v5.14.3 起由 ContentView 首帧后 .task
    /// 调用，不再压在 init 的启动关键路径上）：
    /// - 内存模式不跑（并进内存也留不住，口径同 v5.14.2）；
    /// - **开扫之前**先把尝试计数自增落盘：崩在半途计数已增、
    ///   完成标志未置，下次启动按计数判是否还自动跑；计数达
    ///   上限且未完成 → 不再自动跑（诊断行显形），杜绝每启必崩；
    /// - 跑完才写完成标志；落盘失败不置标志，按 ID 去重下次重试；
    /// - 键兼容 v5.14.2 已装机环境：那边只可能写过 done（崩在
    ///   半途则什么都没写），attempts 键缺失按 0 读，容忍半写。
    func runRescueIfNeeded() {
        let defaults = UserDefaults.standard
        guard !isEmergencyStorage else { return }
        guard !defaults.bool(forKey: Self.rescueDoneKey) else { return }
        let attempts = defaults.integer(forKey: Self.rescueAttemptsKey)
        guard attempts < Self.rescueMaxAttempts else { return }
        defaults.set(attempts + 1, forKey: Self.rescueAttemptsKey)
        let result = StoreRescue.run(
            main: container, schema: schema,
            allowCloudKit: rescueCloudKitAllowed)
        if result.completed {
            defaults.set(true, forKey: Self.rescueDoneKey)
            if result.ledgersMerged > 0 || result.recordsMerged > 0 {
                rescueReceipt = L10n.format(
                    "找回 %lld 本礼簿、%lld 笔记录，已并入本机",
                    result.ledgersMerged, result.recordsMerged
                )
            }
        } else {
            storageUnsafe = true
        }
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

    /// 开关已改但存储模式下次启动才切换（＝显式改锁，见 launch 决策）
    var hasPendingChange: Bool { syncEnabled != enabledAtLaunch }

    /// 应急内存模式（本地文件存储打开失败）：记什么都不会落盘、关 App 即丢。
    /// 这是绝不能沉默的状态——ContentView 据此挂固定红色警示条。
    var isEmergencyStorage: Bool { launchDecision == .emergencyMemory }

    /// 开关诚实化（v5.14.2）：本地回退/锁定本地（探针无 entitlement、
    /// 创建失败、内存应急）时 CloudKit 在本安装里根本用不了，开关必须
    /// 呈关闭且不可拨——不许再出现「开关开着、小字说不支持」的矛盾态。
    /// 用户主动关掉的本地（localByUserChoice）与 CloudKit 模式不在此列，
    /// 开关照常可拨（拨动＝显式改锁，下次启动重决）。
    var syncToggleLockedOff: Bool {
        isEmergencyStorage
            || (storeMode == .localOnly && launchDecision == .localByFallback)
    }

    /// 未登录时给出「去设置」入口
    var showsSettingsShortcut: Bool { status == .notSignedIn && !hasPendingChange }
}
