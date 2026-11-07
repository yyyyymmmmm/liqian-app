import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 礼簿班子管理页（v4.5）：一本礼簿的经手人——主家、书记、核实、只读。
///
/// 同步口径（与 Core MemberSync 一致，详见 docs/V45-FAMILY-NOTES.md）：
/// - 书记 / 核实：班子是唯一真源，本页任何变更后立即按班子推导回写
///   礼簿的 scribe / verifier 字段（无此角色 → 清空），保证礼谱落款一致；
/// - 主家：班子有主家成员时 hostName 跟随班子；没有时字段保持不变
///   （hostName 还兼全局落款回退与建簿预填语义，不随班子清空）；
/// - 首次打开且班子为空时，按礼簿现有字段生成种子成员（老数据衔接）；
///   用 UserDefaults 标记防「用户删空班子后又被种子复活」。
struct LedgerMembersView: View {
    let ledger: Ledger

    @Environment(\.modelContext) private var modelContext
    @Query private var allMembers: [LedgerMember]

    @State private var showNewMember = false
    @State private var editingMember: LedgerMember?
    @State private var memberToDelete: LedgerMember?
    @State private var sharingAvailability: SharingAvailability?

    private var members: [LedgerMember] {
        allMembers
            .filter { $0.ledgerID == ledger.id }
            .sorted {
                ($0.roleValue.sortOrder, $0.createdAt, $0.name)
                    < ($1.roleValue.sortOrder, $1.createdAt, $1.name)
            }
    }

    private var seededKey: String { "membersSeeded.\(ledger.id.uuidString)" }

    var body: some View {
        List {
            Section {
                if members.isEmpty {
                    Text("还没有班子成员。把主家、书记、核实人设好，礼谱落款和日后协作都按班子来。")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                } else {
                    ForEach(members) { member in
                        memberRow(member)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    memberToDelete = member
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    editingMember = member
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                            }
                    }
                }
                Button {
                    showNewMember = true
                } label: {
                    Label("添加成员", systemImage: "person.badge.plus")
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                }
            } header: {
                Text("班子成员")
            } footer: {
                Text("书记、核实人以班子为准，会同步到礼簿信息与礼谱落款；同一角色有多人时，落款取最早加入的一位。")
            }

            Section {
                HStack(spacing: LiqianMetrics.spacingSM) {
                    Image(systemName: sharingAvailability?.isAvailable == true
                          ? "checkmark.icloud" : "icloud.slash")
                        .foregroundStyle(Palette.ink)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(sharingAvailability?.message ?? "正在读取 iCloud 状态…")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
                Button {
                    // availability 为真（iCloud 接通）后在此创建 CKShare 并
                    // 呈现 CloudSharingView；当前构建恒不可用，按钮禁用。
                } label: {
                    Label("邀请家人协作", systemImage: "person.2.badge.gearshape")
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                }
                .disabled(sharingAvailability?.isAvailable != true)
                ForEach(MemberRole.allCases, id: \.self) { role in
                    HStack {
                        Text(role.rawValue)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(LedgerSharing.permissionText(for: role))
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                }
            } header: {
                Text("协作共享")
            } footer: {
                Text("邀请发出后，家人按上面的权限一起管这本礼簿：书记、核实可记账，只读只能查看。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("礼簿班子")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            seedIfNeeded()
            syncFields()
        }
        .task {
            sharingAvailability = await LedgerSharing.availability()
        }
        .sheet(isPresented: $showNewMember) {
            MemberFormView(existing: nil) { name, role in
                modelContext.insert(
                    LedgerMember(ledgerID: ledger.id, name: name, role: role.rawValue)
                )
                afterMutation()
            }
        }
        .sheet(item: $editingMember) { member in
            MemberFormView(existing: member) { name, role in
                member.name = name
                member.role = role.rawValue
                afterMutation()
            }
        }
        .alert(
            "删除这位成员？",
            isPresented: Binding(
                get: { memberToDelete != nil },
                set: { if !$0 { memberToDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let m = memberToDelete {
                    modelContext.delete(m)
                    afterMutation()
                }
                memberToDelete = nil
            }
            Button("取消", role: .cancel) { memberToDelete = nil }
        } message: {
            Text("删除后，若他是唯一的书记或核实人，礼簿的对应落款会一并清空。")
        }
    }

    private func memberRow(_ member: LedgerMember) -> some View {
        HStack(spacing: LiqianMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                Text(member.name)
                    .foregroundStyle(Palette.ink)
                Text(roleNote(member.roleValue))
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
            Spacer()
            Text(member.role)
                .font(.caption.weight(.semibold))
                .foregroundStyle(member.roleValue == .viewer ? Palette.stone : Palette.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    member.roleValue == .viewer ? Palette.surface : Palette.primaryTint,
                    in: Capsule()
                )
        }
    }

    private func roleNote(_ role: MemberRole) -> String {
        switch role {
        case .host: return "礼簿归属人，礼谱落款主家"
        case .scribe: return "记账人，礼谱落款书记"
        case .verifier: return "对账人，礼谱落款核实"
        case .viewer: return "只能查看，不能记账"
        }
    }

    // MARK: - 同步

    private var fieldValues: MemberSync.FieldValues {
        MemberSync.FieldValues(
            hostName: ledger.hostName, scribe: ledger.scribe, verifier: ledger.verifier
        )
    }

    /// 班子 → 礼簿字段（口径见文件头）；有变化才写回
    private func syncFields() {
        let next = MemberSync.fields(from: members.map(\.value), current: fieldValues)
        guard next != fieldValues else { return }
        ledger.hostName = next.hostName
        ledger.scribe = next.scribe
        ledger.verifier = next.verifier
        try? modelContext.save()
    }

    /// 班子为空且从未管理过时，按礼簿现有字段生成种子成员
    private func seedIfNeeded() {
        guard members.isEmpty,
              !UserDefaults.standard.bool(forKey: seededKey) else { return }
        let seeds = MemberSync.seed(from: fieldValues)
        UserDefaults.standard.set(true, forKey: seededKey)
        guard !seeds.isEmpty else { return }
        let base = Date()
        for (index, seed) in seeds.enumerated() {
            modelContext.insert(
                LedgerMember(
                    ledgerID: ledger.id,
                    name: seed.name,
                    role: seed.role.rawValue,
                    createdAt: base.addingTimeInterval(Double(index))
                )
            )
        }
        try? modelContext.save()
    }

    /// 增删改统一收尾：标记已管理（防种子复活）→ 保存 → 同步字段
    private func afterMutation() {
        UserDefaults.standard.set(true, forKey: seededKey)
        try? modelContext.save()
        syncFields()
    }
}

/// 成员编辑表单（新建/编辑共用）：姓名 + 角色
private struct MemberFormView: View {
    let existing: LedgerMember?
    let onSave: (String, MemberRole) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var role: MemberRole

    init(existing: LedgerMember?, onSave: @escaping (String, MemberRole) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _role = State(initialValue: existing?.roleValue ?? .viewer)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Text("姓名")
                            .foregroundStyle(Palette.ink)
                        TextField("姓名", text: $name, prompt: Text("如：杨敏杰"))
                    }
                }
                Section {
                    Picker("角色", selection: $role) {
                        ForEach(MemberRole.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                } footer: {
                    Text("主家是礼簿归属人；书记记账、核实对账，两人会出现在礼谱落款里；只读只能查看。")
                }
            }
            .navigationTitle(existing == nil ? "添加成员" : "编辑成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(trimmedName, role)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}
