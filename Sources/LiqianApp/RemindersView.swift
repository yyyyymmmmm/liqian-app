import SwiftData
import SwiftUI
import UIKit
import UserNotifications
import LiqianCore
import LiqianDesign

/// 人情提醒（v3.0）：「我的 → 记录 → 人情提醒」。
/// 上半是重要日子列表（按临近排序，带下一次日期与倒计时），下半是待回礼
/// 提醒设置区。排期计算在 Core ReminderPlanner，这里管授权、编辑与重排触发：
/// 任何日子/设置变化（onChange 签名）都会全量重排系统通知。
struct RemindersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var days: [ReminderDay]
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]

    @AppStorage(ReminderScheduler.pendingEnabledKey) private var pendingEnabled = false
    @AppStorage(ReminderScheduler.pendingDaysKey) private var pendingDays = ReminderScheduler.defaultPendingDays

    @State private var formMode: FormMode?
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    /// 提醒开关/删除的触感（v4.4）：本页此前全无反馈——左滑启停、删除、
    /// 待回礼提醒总开关都是静默生效，与全 App 的 sensoryFeedback 体系对齐
    @State private var dayToggleTrigger = 0
    @State private var dayDeleteTrigger = 0

    private enum FormMode: Identifiable {
        case create
        case edit(ReminderDay)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let d): return "edit-\(d.id.uuidString)"
            }
        }
    }

    /// 汇总口径快照：示例账本的记录不计入（与「我的」页一致）
    private var snapshots: [EntrySnapshot] {
        let ids = SampleData.sampleIDs(ledgers: ledgers)
        return AppSupport.snapshots(
            records: records.filter { !ids.contains($0.ledgerID) },
            ledgers: ledgers
        )
    }

    /// 列表按临近排序：启用的在前、按下一次日子升序；停用的沉底
    private var sortedDays: [ReminderDay] {
        days.sorted { a, b in
            if a.enabled != b.enabled { return a.enabled && !b.enabled }
            return nextOccurrence(of: a) < nextOccurrence(of: b)
        }
    }

    /// 数据签名：日子或待回设置一变就重排（表单只管存数据，重排收敛在这里）
    private var scheduleSignature: String {
        let dayPart = days.map {
            "\($0.id.uuidString)|\($0.person)|\($0.kind)|\($0.calendarKind)|\($0.month)|\($0.day)|\($0.leadDays)|\($0.enabled)|\($0.note)"
        }.joined(separator: ";")
        return dayPart + "#\(pendingEnabled)#\(pendingDays)"
    }

    var body: some View {
        List {
            if authStatus == .denied {
                Section {
                    VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
                        Label("通知未开，提醒不会推送", systemImage: "bell.slash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.danger)
                        Text("日子和排期都记着，只是系统不让弹窗。去系统设置里给「礼记」打开通知即可。")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                        Button("去系统设置打开通知") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .font(.subheadline)
                    }
                    .padding(.vertical, LiqianMetrics.spacingXS)
                }
            }

            Section {
                if sortedDays.isEmpty {
                    ContentUnavailableView {
                        Label("还没有记日子", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("把亲友的生日、结婚纪念日记下来，到日子之前会提醒你。")
                    } actions: {
                        Button("记一个日子") { formMode = .create }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.primary)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(sortedDays) { day in
                        NavigationLink {
                            ReminderDayFormView(existing: day)
                        } label: {
                            dayRow(day)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(day)
                                try? modelContext.save()
                                dayDeleteTrigger += 1
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                day.enabled.toggle()
                                try? modelContext.save()
                                dayToggleTrigger += 1
                            } label: {
                                Label(day.enabled ? "停用" : "启用",
                                      systemImage: day.enabled ? "bell.slash" : "bell")
                            }
                            .tint(Palette.stone)
                        }
                    }
                }
            } header: {
                Text("重要日子")
            } footer: {
                Text("每年重复，提前在上午 9 点提醒。农历日子按年换算成公历推送。")
            }

            Section {
                Toggle(isOn: $pendingEnabled) {
                    Text("待回礼提醒")
                        .foregroundStyle(Palette.ink)
                }
                .tint(Palette.primary)
                if pendingEnabled {
                    Picker("超过天数", selection: $pendingDays) {
                        ForEach([15, 30, 60, 90], id: \.self) { n in
                            Text("\(n) 天").tag(n)
                        }
                    }
                }
            } header: {
                Text("待回礼")
            } footer: {
                Text("有人待回的礼超过设定天数还没回时，每月最多汇总提醒一条，只报事实，不逐人提醒。默认关闭。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: pendingEnabled)
        .sensoryFeedback(.selection, trigger: dayToggleTrigger)
        .sensoryFeedback(.warning, trigger: dayDeleteTrigger)
        .navigationTitle("人情提醒")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    formMode = .create
                } label: {
                    Label("记一个日子", systemImage: "plus")
                }
            }
        }
        .sheet(item: $formMode) { mode in
            switch mode {
            case .create:
                ReminderDayFormView()
            case .edit(let day):
                ReminderDayFormView(existing: day)
            }
        }
        .task {
            // 首次进入：还没问过授权就在这里问（系统只真正弹窗一次）；
            // 已拒绝的靠顶部横幅与设置按钮兜底。
            let status = await ReminderScheduler.authorizationStatus()
            authStatus = status
            if status == .notDetermined {
                _ = await ReminderScheduler.requestAuthorization()
                authStatus = await ReminderScheduler.authorizationStatus()
            }
        }
        .onChange(of: scheduleSignature) { _, _ in
            reschedule()
        }
    }

    private func dayRow(_ day: ReminderDay) -> some View {
        let occurrence = nextOccurrence(of: day)
        return HStack(spacing: LiqianMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                HStack(spacing: LiqianMetrics.spacingS) {
                    Text(day.person)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(day.enabled ? Palette.ink : Palette.stone)
                    Text(day.kind)
                        .font(.caption)
                        .foregroundStyle(Palette.primary)
                        .padding(.horizontal, LiqianMetrics.spacingS)
                        .padding(.vertical, 2)
                        .background(Palette.primaryTint, in: Capsule())
                }
                Text(setDayText(day))
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
                if !day.note.isEmpty, day.kind == LiqianConstants.reminderOther {
                    Text(day.note)
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: LiqianMetrics.spacingXS) {
                if day.enabled {
                    Text(countdownText(occurrence))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.primary)
                    Text("下次 \(LiqianDate.displayString(for: LiqianDate.string(from: occurrence)))")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                } else {
                    Text("已停用")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
            }
        }
        .padding(.vertical, LiqianMetrics.spacingXS)
    }

    /// 设的日子原文：公历「每年公历 11月16日」；农历「每年农历 10月8日（十月初八）」
    private func setDayText(_ day: ReminderDay) -> String {
        if day.isLunarText {
            let occ = nextOccurrence(of: day)
            let traditional = ReminderMath.dateNote(calendarKind: day.calendarKind, occurrence: occ)
            return "每年农历 \(day.month)月\(day.day)日（\(traditional)）"
        }
        return "每年公历 \(day.month)月\(day.day)日"
    }

    private func countdownText(_ occurrence: Date) -> String {
        let n = ReminderMath.daysUntil(occurrence, from: Date())
        switch n {
        case 0: return "就是今天"
        case 1: return "明天"
        default: return "还有 \(n) 天"
        }
    }

    private func nextOccurrence(of day: ReminderDay) -> Date {
        ReminderMath.nextOccurrence(
            calendarKind: day.calendarKind, month: day.month, day: day.day, from: Date()
        )
    }

    private func reschedule() {
        ReminderScheduler.reschedule(days: days.map(\.value), snapshots: snapshots)
    }
}

private extension ReminderDay {
    var isLunarText: Bool { calendarKind == LiqianConstants.calendarLunar }
}

/// 重要日子新建/编辑表单（原生 Form）：保存只写数据，
/// 通知重排由列表页的数据签名统一触发。
struct ReminderDayFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [GiftRecord]

    let existing: ReminderDay?

    @State private var person: String
    @State private var relation: String
    @State private var kind: String
    @State private var calendarKind: String
    @State private var month: Int
    @State private var day: Int
    @State private var leadDays: Int
    @State private var enabled: Bool
    @State private var note: String
    /// 保存成功/开关切换触感（v4.4，与列表页同口径）
    @State private var saveTrigger = 0

    init(existing: ReminderDay? = nil) {
        self.existing = existing
        _person = State(initialValue: existing?.person ?? "")
        _relation = State(initialValue: existing?.relation ?? "")
        _kind = State(initialValue: existing?.kind ?? LiqianConstants.reminderBirthday)
        _calendarKind = State(initialValue: existing?.calendarKind ?? LiqianConstants.calendarGregorian)
        _month = State(initialValue: existing?.month ?? 1)
        _day = State(initialValue: existing?.day ?? 1)
        _leadDays = State(initialValue: existing?.leadDays ?? 3)
        _enabled = State(initialValue: existing?.enabled ?? true)
        _note = State(initialValue: existing?.note ?? "")
    }

    /// 人物联想：往来里出现过的名字，按当前输入过滤（点了带入关系）
    private var suggestions: [PersonSummary] {
        let trimmed = person.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let people = LedgerMath.people(from: AppSupport.snapshots(records: records, ledgers: []))
        return people
            .filter { $0.name.contains(trimmed) && $0.name != trimmed }
            .prefix(6)
            .map { $0 }
    }

    /// 当月可选的最大日子：农历恒 30；公历按月（2 月给到 29，闰年才用得上）
    private var maxDay: Int {
        if calendarKind == LiqianConstants.calendarLunar { return 30 }
        switch month {
        case 2: return 29
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private var canSave: Bool {
        !person.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Text("姓名")
                            .foregroundStyle(Palette.ink)
                        TextField("姓名", text: $person, prompt: Text("如：大舅"))
                            .multilineTextAlignment(.trailing)
                    }
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: LiqianMetrics.spacingS) {
                                ForEach(suggestions) { p in
                                    Button {
                                        person = p.name
                                        if relation.isEmpty { relation = p.relation }
                                    } label: {
                                        Text(p.name)
                                            .font(.subheadline)
                                            .foregroundStyle(Palette.primary)
                                            .padding(.horizontal, LiqianMetrics.spacingSM)
                                            .padding(.vertical, LiqianMetrics.spacingXS)
                                            .background(Palette.primaryTint, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    Picker("关系", selection: $relation) {
                        Text("不选").tag("")
                        // 数据源＝关系目录（系统＋自定义）；已删的自定义关系
                        // 临时并入，保证正在编辑的日子选中态不丢
                        ForEach(RelationCatalog.pickerOptions(including: relation), id: \.self) { r in
                            Text(r).tag(r)
                        }
                    }
                } header: {
                    Text("人物")
                }

                Section {
                    Picker("类型", selection: $kind) {
                        ForEach(LiqianConstants.reminderKinds, id: \.self) { k in
                            Text(k).tag(k)
                        }
                    }
                    Picker("历法", selection: $calendarKind) {
                        Text(LiqianConstants.calendarGregorian).tag(LiqianConstants.calendarGregorian)
                        Text(LiqianConstants.calendarLunar).tag(LiqianConstants.calendarLunar)
                    }
                    .pickerStyle(.segmented)
                    Picker("月份", selection: $month) {
                        ForEach(1...12, id: \.self) { m in
                            Text("\(m) 月").tag(m)
                        }
                    }
                    Picker("日子", selection: $day) {
                        ForEach(1...maxDay, id: \.self) { d in
                            Text("\(d) 日").tag(d)
                        }
                    }
                } header: {
                    Text("日子")
                } footer: {
                    if calendarKind == LiqianConstants.calendarLunar {
                        Text("按农历记：每年到了这个农历月日就提醒（闰月年份按正月算）。")
                    }
                }

                Section {
                    Picker("提前提醒", selection: $leadDays) {
                        ForEach(LiqianConstants.reminderLeadOptions, id: \.self) { n in
                            Text(n == 0 ? "当天" : "提前 \(n) 天").tag(n)
                        }
                    }
                    Toggle("启用提醒", isOn: $enabled)
                        .tint(Palette.primary)
                } header: {
                    Text("提醒")
                } footer: {
                    Text("在提前那天的上午 9 点推送。")
                }

                Section {
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Text("备注")
                            .foregroundStyle(Palette.ink)
                        TextField("备注", text: $note, prompt: Text("选填"))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle(existing == nil ? "记一个日子" : "编辑日子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: month) { _, _ in clampDay() }
            .onChange(of: calendarKind) { _, _ in clampDay() }
            .scrollDismissesKeyboard(.interactively)
            .sensoryFeedback(.success, trigger: saveTrigger)
            .sensoryFeedback(.selection, trigger: enabled)
        }
    }

    private func clampDay() {
        if day > maxDay { day = maxDay }
    }

    private func save() {
        let name = person.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let fields: (String, String, String, String, Int, Int, Int, Bool, String) = (
            name, relation, kind, calendarKind, month, min(day, maxDay),
            leadDays, enabled, note.trimmingCharacters(in: .whitespaces)
        )
        if let existing {
            existing.person = fields.0
            existing.relation = fields.1
            existing.kind = fields.2
            existing.calendarKind = fields.3
            existing.month = fields.4
            existing.day = fields.5
            existing.leadDays = fields.6
            existing.enabled = fields.7
            existing.note = fields.8
        } else {
            modelContext.insert(ReminderDay(
                person: fields.0, relation: fields.1, kind: fields.2,
                calendarKind: fields.3, month: fields.4, day: fields.5,
                leadDays: fields.6, enabled: fields.7, note: fields.8
            ))
        }
        try? modelContext.save()
        saveTrigger += 1
        dismiss()
    }
}
