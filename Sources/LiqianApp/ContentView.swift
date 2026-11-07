import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// iOS 26 原生 Tab：玻璃底栏由系统提供，不做自定义栏（skill 口径）。
/// 隐私锁（v1.1）：MeView 里开关（@AppStorage "privacyLock"），
/// 开启时冷启动即锁、回前台超过 30 秒重新锁、切后台内容模糊遮罩。
/// v2：启动清回收站过期条目、回前台刷新小组件速览、承接小组件深链与快捷指令的「记一笔」。
struct ContentView: View {
    @AppStorage("privacyLock") private var privacyLockEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allRecords: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var allLedgers: [Ledger]
    @State private var isLocked = true
    @State private var backgroundedAt: Date?
    @State private var showQuickRecord = false

    /// 切到后台/多任务预览时是否要盖模糊遮罩
    private var shieldVisible: Bool {
        privacyLockEnabled && scenePhase != .active
    }

    var body: some View {
        ZStack {
            TabView {
                Tab("礼簿", systemImage: "book.closed") {
                    LedgersView()
                }
                Tab("人情", systemImage: "person.2") {
                    PeopleView()
                }
                Tab("我的", systemImage: "person.crop.circle") {
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
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.stone)
                }
            }

            if privacyLockEnabled && isLocked && scenePhase == .active {
                LockScreenView {
                    authenticate()
                }
            }
        }
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
