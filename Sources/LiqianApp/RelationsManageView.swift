import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 关系管理页（v5.10 重构，审计 #5）：对标微信标签管理——
/// 一张平铺表（与记账选择器同口径：预置在前、自定义在后），行内带用量
/// 「N 人 · M 笔」，点行下钻到该关系的人物列表；改名/删除有可见入口
/// （行尾菜单＋左滑＋编辑模式），规则写在输入框正下方、影响写清在弹窗里。
///
/// 口径定版：
/// - 改名＝级联改变（用户拍板）：目录、全部记录、提醒、回收站快照里
///   落了旧名的地方一并改写，值映射走 RelationCascade 单点口径。
/// - 删除只删目录选项：已记记录上的关系名照原样保留（与删除影响文案一致）。
/// - 排序持久化的是自定义段的相对顺序，即选择器里自定义部分的顺序；
///   预置关系恒定居前、不可改名/删除，行菜单里写明原因。
/// 用量与引用计数按全部记录现算（含示例与待送出——管理页管的是数据
/// 本身，不做统计隔离；笔数口径与级联/删除的影响面严格一致）。
struct RelationsManageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [GiftRecord]
    @Query private var reminders: [ReminderDay]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]

    @State private var ordered: [String] = RelationCatalog.all()
    @State private var draft = ""
    @State private var errorText: String?
    @State private var relationRoute: RelationRoute?
    @State private var renameTarget: String?
    @State private var renameDraft = ""
    @State private var renameError: String?
    @State private var deleteTarget: String?

    struct RelationRoute: Identifiable, Hashable {
        let relation: String
        var id: String { relation }
    }

    /// 快捷添加候选：系统里没有、自己也还没加过的才显
    private static let quickAdds = ["闺蜜", "战友", "发小", "老乡", "师长"]
    private var pendingQuickAdds: [String] {
        Self.quickAdds.filter { !ordered.contains($0) }
    }

    private var usageByRelation: [String: RelationUsage] {
        let snaps = AppSupport.snapshots(records: records, ledgers: ledgers)
        return Dictionary(
            uniqueKeysWithValues: LedgerMath.relationUsage(from: snaps).map { ($0.relation, $0) }
        )
    }

    /// 引用计数（级联/删除的影响面）：全部记录＋提醒，不分状态
    private func recordRefs(_ name: String) -> Int {
        LedgerMath.relationReferenceCount(of: name, in: records.map(\.relation))
    }

    private func reminderRefs(_ name: String) -> Int {
        LedgerMath.relationReferenceCount(of: name, in: reminders.map(\.relation))
    }

    private func isSystem(_ name: String) -> Bool {
        LiqianConstants.relations.contains(name)
    }

    var body: some View {
        List {
            // 添加区（收敛为顶部一段）：规则前置到输入框正下方，带字数计数
            Section {
                HStack(spacing: LiqianMetrics.spacingSM) {
                    TextField("新关系，如闺蜜、战友", text: $draft)
                        .onSubmit { add(draft) }
                    Button("添加") { add(draft) }
                        .foregroundStyle(Palette.primary)
                        .disabled(
                            draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
                .frame(minHeight: LiqianMetrics.minTapTarget)
                HStack {
                    Text("最多 \(RelationCatalog.maxLength) 个字，不能与已有关系重名。")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                    Spacer()
                    Text("\(draft.count)/\(RelationCatalog.maxLength)")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.stone)
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                if !pendingQuickAdds.isEmpty {
                    HStack(spacing: LiqianMetrics.spacingS) {
                        Text("常用的：")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: LiqianMetrics.spacingS) {
                                ForEach(pendingQuickAdds, id: \.self) { name in
                                    Button {
                                        add(name)
                                    } label: {
                                        Text(name)
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(Palette.ink)
                                            .padding(.horizontal, LiqianMetrics.spacingSM)
                                            .frame(minHeight: 30)
                                            .background(Palette.primaryTint, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(
                        top: LiqianMetrics.spacingXS,
                        leading: LiqianMetrics.cardPadding,
                        bottom: LiqianMetrics.spacingXS,
                        trailing: LiqianMetrics.cardPadding
                    ))
                }
            } header: {
                Text("添加关系")
            } footer: {
                Text("添加后，记账、提醒、现场登记里的关系选项都会多出这一项。")
            }

            // 全部关系（与选择器平铺同口径）：行内用量＋下钻＋可见管理入口
            Section {
                ForEach(ordered, id: \.self) { name in
                    relationRow(name)
                }
                .onMove { offsets, destination in
                    ordered.move(fromOffsets: offsets, toOffset: destination)
                    RelationCatalog.applyOrder(fullOrder: ordered)
                    refresh()
                }
            } header: {
                Text("全部关系")
            } footer: {
                Text("排序就是记账时选项的顺序，预置关系固定在前。改名会把已记的记录、提醒与最近删除里的旧名一并改掉；删除只删选项，已记记录上的关系名保留不变。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("关系管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .onAppear { refresh() }
        .navigationDestination(item: $relationRoute) { route in
            RelationPeopleView(relation: route.relation)
        }
        .alert("改名", isPresented: renamePresented, presenting: renameTarget) { target in
            TextField("新关系名", text: $renameDraft)
            Button("取消", role: .cancel) {}
            Button("改名") { performRename(target) }
        } message: { target in
            Text(renameMessage(target))
        }
        .alert(
            "改名没成",
            isPresented: Binding(
                get: { renameError != nil },
                set: { if !$0 { renameError = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(renameError ?? "")
        }
        .confirmationDialog(
            "删除关系",
            isPresented: deletePresented,
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { target in
            Button("删除「\(target)」", role: .destructive) { performDelete(target) }
            Button("取消", role: .cancel) {}
        } message: { target in
            Text(deleteMessage(target))
        }
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    // MARK: - 行

    private func relationRow(_ name: String) -> some View {
        let system = isSystem(name)
        let usage = usageByRelation[name]
        return HStack(spacing: LiqianMetrics.spacingSM) {
            Button {
                relationRoute = RelationRoute(relation: name)
            } label: {
                HStack(spacing: LiqianMetrics.spacingSM) {
                    Text(name)
                        .foregroundStyle(Palette.ink)
                    if system {
                        Text("预置")
                            .font(.caption)
                            .foregroundStyle(Palette.stone)
                    }
                    Spacer()
                    Text("\(usage?.people ?? 0) 人 · \(usage?.records ?? 0) 笔")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.stone)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.stone)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                if system {
                    Button {
                    } label: {
                        Label("预置关系，不能改名或删除", systemImage: "lock")
                    }
                    .disabled(true)
                } else {
                    Button {
                        renameTarget = name
                        renameDraft = name
                    } label: {
                        Label("改名", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleteTarget = name
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Palette.stone)
                    .frame(minWidth: LiqianMetrics.minTapTarget, minHeight: LiqianMetrics.minTapTarget)
                    .contentShape(Rectangle())
            }
        }
        .frame(minHeight: LiqianMetrics.minTapTarget)
        .moveDisabled(system)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !system {
                Button {
                    renameTarget = name
                    renameDraft = name
                } label: {
                    Label("改名", systemImage: "pencil")
                }
                .tint(Palette.primary)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !system {
                Button(role: .destructive) {
                    deleteTarget = name
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - 文案

    private func renameMessage(_ target: String) -> String {
        let recs = recordRefs(target)
        let rems = reminderRefs(target)
        if recs == 0 && rems == 0 {
            return "「\(target)」还没有被记录或提醒使用，改名只改目录。"
        }
        var parts: [String] = []
        if recs > 0 { parts.append("\(recs) 笔记录") }
        if rems > 0 { parts.append("\(rems) 条提醒") }
        return "改名会级联更新：\(parts.joined(separator: "、"))上的「\(target)」会一起改成新名，历史记录跟着变。"
    }

    private func deleteMessage(_ target: String) -> String {
        let recs = recordRefs(target)
        if recs == 0 {
            return "「\(target)」还没有被任何记录使用。删除后，记账时将不再有此选项。"
        }
        return "「\(target)」正被 \(recs) 笔记录使用。删除后，这些记录上的关系名保留不变，之后记账将不再有此选项。"
    }

    private func validationMessage(_ error: RelationValidationError) -> String {
        switch error {
        case .empty: return "先输入一个关系名。"
        case .tooLong: return "关系名最多 \(RelationCatalog.maxLength) 个字。"
        case .duplicate: return "这个关系已经有了，不用重复添加。"
        }
    }

    // MARK: - 动作

    private func refresh() {
        ordered = RelationCatalog.all()
    }

    private func add(_ raw: String) {
        switch RelationCatalog.add(raw) {
        case .success:
            refresh()
            draft = ""
            errorText = nil
        case .failure(let error):
            errorText = validationMessage(error)
        }
    }

    /// 改名级联（用户拍板）：校验 → 目录原位改名 → 记录/提醒逐条套
    /// RelationCascade 映射 → 回收站快照同步 → 落盘。任一步的旧名残留
    /// 都不许静默：落盘后按当前数据复查，仍有残留则报错给用户。
    private func performRename(_ old: String) {
        switch RelationCatalog.validateRename(
            from: old, rawNew: renameDraft, existing: RelationCatalog.all()
        ) {
        case .failure(let error):
            renameError = validationMessage(error)
        case .success(let new):
            if new == old { return }
            guard RelationCatalog.renameCustom(from: old, to: new) else {
                renameError = "改名失败，请再试一次。"
                return
            }
            for record in records where record.relation == old {
                record.relation = RelationCascade.map(record.relation, from: old, to: new)
            }
            for day in reminders where day.relation == old {
                day.relation = RelationCascade.map(day.relation, from: old, to: new)
            }
            TrashStore.renameRelation(from: old, to: new)
            try? modelContext.save()
            refresh()
            let residue = recordRefs(old) + reminderRefs(old)
            if residue > 0 {
                renameError = "还有 \(residue) 处没改过来，请再试一次。"
            }
        }
    }

    private func performDelete(_ name: String) {
        RelationCatalog.remove(name)
        refresh()
    }
}

/// 关系下钻（关系管理行落点）：用这个关系往来的人物列表，
/// 金额为该关系口径内的收/随汇总，点人进往来详情。
struct RelationPeopleView: View {
    let relation: String

    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @State private var personRoute: PeopleView.NameRoute?

    private var people: [PersonSummary] {
        let snaps = AppSupport.snapshots(records: records, ledgers: ledgers)
            .filter { $0.relation == relation }
        return LedgerMath.people(from: snaps)
            .sorted { ($0.received + $0.given) > ($1.received + $1.given) }
    }

    var body: some View {
        Group {
            if people.isEmpty {
                ContentUnavailableView {
                    Label("还没有人用这个关系", systemImage: "person.2.slash")
                } description: {
                    Text("记账时把关系选成「\(relation)」，这里就会有人了。")
                }
            } else {
                List {
                    ForEach(people) { p in
                        Button {
                            personRoute = PeopleView.NameRoute(name: p.name)
                        } label: {
                            HStack(spacing: LiqianMetrics.spacingSM) {
                                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                                    Text(p.name)
                                        .foregroundStyle(Palette.ink)
                                    Text("\(p.count) 笔")
                                        .font(.footnote)
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.stone)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: LiqianMetrics.spacingXS) {
                                    Text(LedgerMath.fmtMoney(cents: p.received + p.given))
                                        .font(.liqianMoney(.title3))
                                        .foregroundStyle(Palette.ink)
                                        .contentTransition(.numericText())
                                    Text(balanceText(p))
                                        .font(.caption)
                                        .foregroundStyle(Palette.stone)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Palette.stone)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle(relation)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $personRoute) { route in
            PersonDetailView(name: route.name)
        }
    }

    /// 差额文案（定版术语，与人情总览一致）：待回／多随／已结清
    private func balanceText(_ p: PersonSummary) -> String {
        if p.balance == 0 { return "已结清" }
        return p.balance > 0
            ? "待回 \(LedgerMath.fmtMoney(cents: p.balance))"
            : "多随 \(LedgerMath.fmtMoney(cents: -p.balance))"
    }
}
