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
    /// 自定义主题基色（v5.9）：主题值不变（恒 custom）时基色变化也要
    /// 触发重挂，故纳入根视图身份键计算
    @AppStorage(AppTheme.customBaseStorageKey) private var customThemeBaseHex = ""
    /// 语言偏好（v5.13）：纳入根身份键，切换即重挂整棵子树，
    /// 代码拼装的串（L10n）与静态字面一并即时换语言，不必重启
    @AppStorage(AppLanguagePreference.storageKey) private var languageRaw = AppLanguagePreference.system.rawValue
    /// 界面字号档（v5.13）：与系统 Dynamic Type 取大（只设保底），
    /// 环境注入在根视图修饰链上即时生效
    @AppStorage(AppTextSizeTier.storageKey) private var textSizeTierRaw = AppTextSizeTier.standard.rawValue
    @Environment(\.dynamicTypeSize) private var systemTypeSize

    /// 生效字号：系统值与所选档保底的较大者（Core 纯函数定口径）
    private var effectiveTypeSize: DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        let systemIndex = all.firstIndex(of: systemTypeSize) ?? 3
        let target = TextSizeScale.targetIndex(
            systemIndex: systemIndex,
            tier: AppTextSizeTier(storedRaw: textSizeTierRaw)
        )
        return all[min(target, all.count - 1)]
    }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var allRecords: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var allLedgers: [Ledger]
    @Query private var allReminderDays: [ReminderDay]
    @Query private var allBlessings: [VoiceBlessing]
    @State private var isLocked = true
    /// 活礼谱（v4.2）：祝福深链 liqian://blessing/<id> 的播放目标
    @State private var deepLinkBlessing: VoiceBlessing?
    @State private var backgroundedAt: Date?
    @State private var showQuickRecord = false
    @State private var tabSelection = 0
    /// 首开引导（v5）：一次性标记未置位时呈现；隐私锁未解开前不呈现
    /// （cover 会盖在锁屏之上）。设置页无重看入口（v5.8.1 删，审计 #4），
    /// 本标记置位后不再自动呈现。
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: OnboardingView.doneKey)
    /// 小组件人物深链（v4.5）：liqian://person/<姓名> 的待达姓名，
    /// 交给 PeopleView 消费（切到往来页后由它置人物路由并清空）
    @State private var personDeepLinkName: String?
    /// 分享导入（v4.5）：liqian://share-import 承接——目标礼簿（sheet 目标）、
    /// 暂存文本（喂给 BatchEntryView 粘贴流）、导入完成提示
    @State private var shareImportTarget: Ledger?
    @State private var shareImportText = ""
    @State private var showShareImportResult = false
    @State private var shareImportResultText = ""
    /// 存储健康（v4.2 起）：应急内存模式绝不沉默，顶部挂警示条；
    /// v5.14.2 扩为 storageUnsafe（自检失败/救援落盘失败同罪），
    /// 条改固定红＋启动弹窗＋记账入口阻断（见 StorageGuard）
    @EnvironmentObject private var cloudSync: CloudSyncManager
    /// 存储不安全启动弹窗（v5.14.2）：每次启动不安全就弹一次，
    /// 「去导出备份」直达「我的」Tab；记账入口另有整页阻断兜底
    @State private var showStorageAlert = false

    /// 救援回执弹窗绑定（v5.14.2）：真找回数据才有值，关掉即销
    private var rescueAlertBinding: Binding<Bool> {
        Binding(
            get: { cloudSync.rescueReceipt != nil },
            set: { presented in
                if !presented { cloudSync.dismissRescueReceipt() }
            }
        )
    }

    /// 切到后台/多任务预览时是否要盖模糊遮罩
    private var shieldVisible: Bool {
        privacyLockEnabled && scenePhase != .active
    }

    /// 首开呈现绑定（v5）：隐私锁未解开时恒 false（cover 不盖锁屏），
    /// 解锁后自动接上；被关掉（完成/跳过）即置一次性标记，此后不再
    /// 自动呈现（v5.8.1 起设置页无重看入口，审计 #4）。
    private var onboardingPresentation: Binding<Bool> {
        Binding(
            get: { showOnboarding && !(privacyLockEnabled && isLocked) },
            set: { presented in
                if !presented { finishOnboarding() }
            }
        )
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: OnboardingView.doneKey)
        showOnboarding = false
    }

    /// 当前外观主题（「我的 → 外观」切换，默认白天）
    private var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .day
    }

    var body: some View {
        ZStack {
            TabView(selection: $tabSelection) {
                // 四栏（v4.6）：首页 0 / 往来 1 / 图表 2 / 我的 3——
                // 全 App 的 tabSelection 赋值点都按这张表，改索引必全局核对
                // v5 设计一期（审计 §3.5 枚举点 1）：Tab 图标走 label 闭包——
                // 选中时符号 .bounce 一次，未选/选中用线面形变区分状态
                // （往来 person.2↔.fill、我的 crop.circle↔.fill；首页与图表
                // 本就是 .fill 定版，只吃 bounce）。动效由系统在 Reduce
                // Motion 时自动抑制。
                Tab(value: 0) {
                    // v4.7：首页改总览台 HomeView（倒计时/待回/本月/快捷动作/
                    // 最近动态/我的礼簿）；待回行与本月卡经这两个绑定回本视图
                    // 走既有通道切 Tab——personDeepLinkName 与 liqian://person
                    // 深链共用同一绑定，tabSelection 即本 TabView 的选择值。
                    HomeView(deepLinkPerson: $personDeepLinkName, tabSelection: $tabSelection)
                } label: {
                    Label("首页", systemImage: "house.fill")
                        .symbolEffect(.bounce, value: tabSelection == 0)
                }
                Tab(value: 1) {
                    PeopleView(deepLinkPerson: $personDeepLinkName)
                } label: {
                    Label("往来", systemImage: tabSelection == 1 ? "person.2.fill" : "person.2")
                        .symbolEffect(.bounce, value: tabSelection == 1)
                }
                Tab(value: 2) {
                    ChartsView()
                } label: {
                    Label("图表", systemImage: "chart.bar.fill")
                        .symbolEffect(.bounce, value: tabSelection == 2)
                }
                Tab(value: 3) {
                    MeView()
                } label: {
                    Label("我的", systemImage: tabSelection == 3 ? "person.crop.circle.fill" : "person.crop.circle")
                        .symbolEffect(.bounce, value: tabSelection == 3)
                }
            }
            .tint(Palette.primary)
            // v5 设计一期外壳：下滑时标签栏最小化、顶部滚动边缘改柔边
            // （系统渲染，禁止手工渐变模仿——DESIGN 附录定版）
            .tabBarMinimizeBehavior(.onScrollDown)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaInset(edge: .top, spacing: 0) {
                // 存储不安全硬显形（v5.14.2）：内存模式/落盘自检失败/
                // 救援落盘失败一律固定警示红（不随主题变色——旧版用
                // 主题色，腾讯蓝主题下是蓝条，用户根本没认出是警示）
                if cloudSync.storageUnsafe {
                    Text("数据存储异常：现在记的内容不会被保存，请先到「我的 → 数据」导出备份。")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red)
                }
            }
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
        // 让 Palette 的主题动态色即时重解析（切换无须重启）。
        // v5.9：自定义主题下身份键拼入基色——只换基色不换主题也要重挂。
        .preferredColorScheme(appTheme.colorScheme)
        // 界面字号三档（v5.13）：系统 Dynamic Type 之上设保底（Core
        // TextSizeScale），语义字体的主要界面随之缩放；导出字号不经此路。
        .dynamicTypeSize(effectiveTypeSize)
        .id((appTheme == .custom ? "custom-\(customThemeBaseHex)" : appThemeRaw) + "-lang-" + languageRaw)
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
            // 存储不安全（v5.14.2）：启动先弹窗拦一道（红条常驻、
            // 记账入口另有整页阻断，这里负责把话说到用户眼前）
            if cloudSync.storageUnsafe {
                showStorageAlert = true
            }
            refreshWidgetSummary()
            checkQuickRecord()
            checkShareImport()
            checkShortcutPending()
            calibrateReminders()
            // 宾客回执（v5.12）：冷启动先同步一次（锁屏只盖界面，
            // 同步本身只拉回执元数据落库，不展示）
            await GuestSyncCenter.shared.syncAll(in: modelContext)
        }
        .fullScreenCover(isPresented: onboardingPresentation) {
            OnboardingView { finishOnboarding() }
        }
        .onChange(of: isLocked) { _, locked in
            // 分享导入（v4.5）：锁定状态下暂存不承接，解锁一刻补检，
            // 免得用户解完锁还要退后台再回来才弹导入
            if !locked {
                checkShareImport()
                // 宾客回执（v5.12）：解锁后补同步一次（锁定期间只在冷启动拉过）
                Task { await GuestSyncCenter.shared.syncAll(in: modelContext) }
            }
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
                // 宾客回执（v5.12）：回前台增量同步；锁着时不拉（解锁有补检）
                if !isLocked {
                    Task { await GuestSyncCenter.shared.syncAll(in: modelContext) }
                }
                // 分享导入（v4.5）：扩展没能自动打开 App、用户手动点开时，
                // 靠回前台这一检把暂存接上（深链直达时走 onOpenURL 那条）
                checkShareImport()
                checkShortcutPending()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .liqianShortcutAction)) { _ in
            // App 运行中点长按快捷菜单：AppDelegate 已写标记，这里立即消费
            // （checkQuickRecord 内部含隐私锁与无礼簿守卫；切 Tab 侧同理）
            checkQuickRecord()
            checkShortcutPending()
        }
        .onReceive(NotificationCenter.default.publisher(for: .liqianOpenAISettings)) { _ in
            // AI 引导 alert 的「去设置」落点：切到「我的」Tab（AI 设置行在该页）；
            // v4.6 四栏后「我的」是 3（原三栏时为 2，2 现为图表，勿回退）
            tabSelection = 3
        }
        .onOpenURL { url in
            // 小组件深链：liqian://quick-record
            if url.scheme == "liqian", url.host == "quick-record" {
                presentQuickRecord()
                return
            }
            // 分享导入（v4.5）：liqian://share-import——扩展已把文本与
            // 目标礼簿暂存进 App Group，这里统一走 checkShareImport 承接
            // （读暂存→弹批量解析待确认流）；锁着时它内部会直接返回不承接
            if url.scheme == "liqian", url.host == "share-import" {
                checkShareImport()
                return
            }
            // 小组件待回礼整卡深链（v5.1）：liqian://pending——落点与长按
            // 快捷菜单「查看待回礼」同处（往来 Tab，待回礼汇总在该页）；
            // 隐私锁锁着时不承接，与 person 深链锁定口径一致
            if LiqianDeepLink.isPending(url) {
                if privacyLockEnabled && isLocked { return }
                tabSelection = 1
                return
            }
            // 小组件人物深链（v4.5）：liqian://person/<姓名>——切到往来页，
            // 姓名经 personDeepLinkName 交 PeopleView 打开该人物详情；
            // 隐私锁锁着时同样不承接（不绕过锁定页）
            if let name = LiqianDeepLink.personName(from: url) {
                if privacyLockEnabled && isLocked { return }
                tabSelection = 1
                personDeepLinkName = name
                return
            }
            // 活礼谱（v4.2）：祝福深链 liqian://blessing/<id>（礼谱祝福
            // 索引页二维码扫码落点）；隐私锁锁着时不弹（不绕过锁定页）
            if let id = LiqianDeepLink.blessingID(from: url),
               let blessing = allBlessings.first(where: { $0.id == id }) {
                if privacyLockEnabled && isLocked { return }
                deepLinkBlessing = blessing
            }
        }
        .sheet(isPresented: $showQuickRecord) {
            RecordFormView(personName: "", presetDirection: LiqianConstants.received)
        }
        .sheet(item: $shareImportTarget) { ledger in
            BatchEntryView(ledger: ledger, initialPasteText: shareImportText) { n in
                shareImportResultText = "共记 \(n) 笔"
                showShareImportResult = true
            }
        }
        .alert("分享导入", isPresented: $showShareImportResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(shareImportResultText)
        }
        // 存储不安全阻断弹窗（v5.14.2）：口径定版——先导出备份、
        // 再联系支持；修好之前记的账关掉 App 就会丢
        .alert("数据现在存不住", isPresented: $showStorageAlert) {
            Button("去导出备份") { tabSelection = 3 }
            Button("知道了", role: .cancel) {}
        } message: {
            Text("数据现在存不住，先导出备份并联系支持。修好之前记的账，关掉 App 就会丢。")
        }
        // 搁浅数据救援回执（v5.14.2）：真找回才弹，没找到安静无打扰
        .alert("找回数据", isPresented: rescueAlertBinding) {
            Button("好", role: .cancel) { cloudSync.dismissRescueReceipt() }
        } message: {
            Text(cloudSync.rescueReceipt ?? "")
        }
        .sheet(item: $deepLinkBlessing) { blessing in
            BlessingPlayerView(blessing: blessing)
        }
    }

    /// 人情提醒启动校准（v3.0）：防系统清掉待发通知、也让授权状态变化后
    /// 排期跟上。口径与人情提醒页一致（示例账本记录不计入）。
    private func calibrateReminders() {
        let ids = SampleData.sampleIDs(ledgers: allLedgers)
        let snapshots = AppSupport.snapshots(
            records: allRecords.filter { !ids.contains($0.ledgerID) },
            ledgers: allLedgers
        )
        ReminderScheduler.reschedule(days: allReminderDays.map(\.value), snapshots: snapshots)
    }

    /// 小组件速览：用全部记录算待回礼汇总后写入 App Group。
    /// v4.5 起一并带上本月收/送与下一个重要日子（小组件套件数据源）。
    /// 本月口径：记录 date（yyyy-MM-dd）前缀匹配当前年月；随礼只计已送出
    /// （待送出不算，口径同 PersonSummary.given）；与旧字段同源，不做示例隔离。
    private func refreshWidgetSummary() {
        let snapshots = AppSupport.snapshots(records: allRecords, ledgers: allLedgers)
        let monthPrefix = String(LiqianDate.todayString().prefix(7))
        var monthReceived = 0
        var monthGiven = 0
        for entry in snapshots where entry.date.hasPrefix(monthPrefix) {
            if entry.direction == LiqianConstants.received {
                monthReceived += entry.amountCents
            } else if entry.direction == LiqianConstants.given,
                      entry.status != LiqianConstants.pendingStatus {
                monthGiven += entry.amountCents
            }
        }
        WidgetSummaryWriter.write(
            people: LedgerMath.people(from: snapshots),
            monthReceivedCents: monthReceived,
            monthGivenCents: monthGiven,
            nextReminder: WidgetSummaryWriter.nextReminder(from: allReminderDays.map(\.value))
        )
        // 礼簿清单快照（v4.5）：Share Extension 选目标礼簿用，
        // allLedgers 已按日期倒序，第一本即最近一本
        WidgetSummaryWriter.writeLedgerList(ledgers: allLedgers)
    }

    /// 分享导入承接（v4.5）：读 App Group 暂存 → 定目标礼簿（暂存 id 优先，
    /// 已删/缺失时落最近一本）→ 弹 BatchEntryView 粘贴待确认流（预填文本）。
    /// 暂存只在确定能弹时才清：没有礼簿时保留，等建好礼簿下次再承接；
    /// 暂存为空静默作罢；隐私锁锁着时不读不弹（与既有深链守卫一致，
    /// 解锁后由 isLocked 的 onChange 补检）；已在导入中不重复弹。
    private func checkShareImport() {
        if privacyLockEnabled && isLocked { return }
        guard shareImportTarget == nil,
              let defaults = UserDefaults(suiteName: WidgetSummaryWriter.suiteName),
              let text = defaults.string(forKey: WidgetSummaryWriter.shareTextKey),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        let wantedID = defaults.string(forKey: WidgetSummaryWriter.shareLedgerIDKey)
            .flatMap(UUID.init(uuidString:))
        guard let ledger = allLedgers.first(where: { $0.id == wantedID }) ?? allLedgers.first
        else { return }
        defaults.removeObject(forKey: WidgetSummaryWriter.shareTextKey)
        defaults.removeObject(forKey: WidgetSummaryWriter.shareLedgerIDKey)
        tabSelection = 0
        shareImportText = text
        shareImportTarget = ledger
    }

    /// 快捷指令落下的标记：读到就清掉并弹记一笔表单
    private func checkQuickRecord() {
        let defaults = UserDefaults(suiteName: WidgetSummaryWriter.suiteName)
        guard defaults?.bool(forKey: WidgetSummaryWriter.quickRecordKey) == true else { return }
        defaults?.set(false, forKey: WidgetSummaryWriter.quickRecordKey)
        presentQuickRecord()
    }

    /// 长按快捷菜单「查看待回礼」（v4.5）：消费标记后切「往来」Tab（待回礼
    /// 汇总在该页）。隐私锁锁着时不承接——标记已消费直接丢弃，不解锁后补跳，
    /// 与 liqian://person 深链的锁定口径一致。
    private func checkShortcutPending() {
        guard ShortcutActions.consumePendingTab() else { return }
        if privacyLockEnabled && isLocked { return }
        tabSelection = 1
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
