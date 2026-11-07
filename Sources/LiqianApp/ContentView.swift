import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// iOS 26 原生 Tab：玻璃底栏由系统提供，不做自定义栏（skill 口径）。
/// 隐私锁（v1.1）：MeView 里开关（@AppStorage "privacyLock"），
/// 开启时冷启动即锁、回前台超过 30 秒重新锁、切后台内容模糊遮罩。
/// v2：启动清理最近删除的过期条目、回前台刷新小组件速览、承接小组件深链与快捷指令的「记一笔」。
struct ContentView: View {
    @AppStorage("privacyLock") private var privacyLockEnabled = false
    @AppStorage(AppTheme.storageKey) private var appThemeRaw = AppTheme.day.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allRecords: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var allLedgers: [Ledger]
    @State private var isLocked = true
    @State private var backgroundedAt: Date?
    @State private var showQuickRecord = false
    @State private var tabSelection = 0

    /// 切到后台/多任务预览时是否要盖模糊遮罩
    private var shieldVisible: Bool {
        privacyLockEnabled && scenePhase != .active
    }

    /// 当前外观主题（「我的 → 外观」切换，默认白天）
    private var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .day
    }

    var body: some View {
        ZStack {
            TabView(selection: $tabSelection) {
                Tab("礼簿", systemImage: "book.closed", value: 0) {
                    LedgersView()
                }
                Tab("往来", systemImage: "person.2", value: 1) {
                    PeopleView()
                }
                Tab("我的", systemImage: "person.crop.circle", value: 2) {
                    MeView()
                }
            }
            .tint(Palette.primary)
            .blur(radius: shieldVisible ? 20 : 0)

            if shieldVisible {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .accessibilityHidden(true)
                        .foregroundStyle(Palette.stone)
                }
            }

            if privacyLockEnabled && isLocked && scenePhase == .active {
                LockScreenView {
                    authenticate()
                }
            }
        }
        // 外观主题（v2.4）：强制外观覆盖系统跟随；主题值变化时重挂整棵子树，
        // 让 Palette 的主题动态色即时重解析（切换无须重启）
        .preferredColorScheme(appTheme.colorScheme)
        .id(appThemeRaw)
        .onAppear {
            if privacyLockEnabled {
                isLocked = true
                authenticate()
            } else {
                isLocked = false
            }
        }
        .task {
            TrashStore.purgeExpired()
            refreshWidgetSummary()
            checkQuickRecord()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                // 真从后台回来且超过 30 秒才重新锁（Face ID 弹窗造成的
                // inactive→active 不经过 .background，不会误触发）
                if privacyLockEnabled, !isLocked,
                   let bg = backgroundedAt,
                   Date().timeIntervalSince(bg) > 30 {
                    isLocked = true
                    authenticate()
                }
                backgroundedAt = nil
                refreshWidgetSummary()
                checkQuickRecord()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .liqianOpenAISettings)) { _ in
            // AI 引导 alert 的「去设置」落点：切到「我的」Tab（AI 设置行在该页）
            tabSelection = 2
        }
        .onOpenURL { url in
            // 小组件深链：liqian://quick-record
            guard url.scheme == "liqian", url.host == "quick-record" else { return }
            presentQuickRecord()
        }
        .sheet(isPresented: $showQuickRecord) {
            RecordFormView(personName: "", presetDirection: LiqianConstants.received)
        }
    }

    /// 小组件速览：用全部记录算待回礼汇总后写入 App Group
    private func refreshWidgetSummary() {
        let snapshots = AppSupport.snapshots(records: allRecords, ledgers: allLedgers)
        WidgetSummaryWriter.write(people: LedgerMath.people(from: snapshots))
    }

    /// 快捷指令落下的标记：读到就清掉并弹记一笔表单
    private func checkQuickRecord() {
        let defaults = UserDefaults(suiteName: WidgetSummaryWriter.suiteName)
        guard defaults?.bool(forKey: WidgetSummaryWriter.quickRecordKey) == true else { return }
        defaults?.set(false, forKey: WidgetSummaryWriter.quickRecordKey)
        presentQuickRecord()
    }

    private func presentQuickRecord() {
        // 没礼簿无处记；隐私锁还锁着时不弹（不能绕过锁定页露表单）
        guard !allLedgers.isEmpty else { return }
        if privacyLockEnabled && isLocked { return }
        showQuickRecord = true
    }

    private func authenticate() {
        Task {
            if await AppLockAuthenticator.authenticate() { isLocked = false }
        }
    }
}
