import SwiftUI
import LiqianCore
import LiqianDesign

/// 关系管理页（「我的 → 记录 → 关系管理」）：系统关系只读列出，
/// 用户自定义关系（闺蜜、战友等）可增删，数据走 RelationCatalog
/// （UserDefaults 的 customRelations）。改完离开页面即对所有选择器生效
/// （选择器每次打开都动态读目录）。
/// 删除口径：只删目录项——已记的记录上写着的关系字符串照原样保留，
/// 重新编辑那条记录时该值会被临时并入选项，不会丢。
struct RelationsManageView: View {
    @State private var customs: [String] = RelationCatalog.custom()
    @State private var draft = ""
    @State private var errorText: String?

    /// 快捷添加候选：系统里没有、自己也还没加过的才显
    private static let quickAdds = ["闺蜜", "战友", "发小", "老乡", "师长"]
    private var pendingQuickAdds: [String] {
        Self.quickAdds.filter {
            !LiqianConstants.relations.contains($0) && !customs.contains($0)
        }
    }

    var body: some View {
        List {
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
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                if !pendingQuickAdds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: LiqianMetrics.spacingS) {
                            ForEach(pendingQuickAdds, id: \.self) { name in
                                Button {
                                    add(name)
                                } label: {
                                    HStack(spacing: LiqianMetrics.spacingXS) {
                                        Image(systemName: "plus")
                                            .font(.footnote.weight(.semibold))
                                        Text(name)
                                            .font(.subheadline.weight(.medium))
                                    }
                                    .foregroundStyle(Palette.ink)
                                    .padding(.horizontal, LiqianMetrics.spacingSM)
                                    .frame(minHeight: 36)
                                    .background(
                                        Palette.primaryTint,
                                        in: Capsule()
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(
                        top: 8, leading: 16, bottom: 8, trailing: 16
                    ))
                }
            } header: {
                Text("添加关系")
            } footer: {
                Text("最多 6 个字，不能与已有关系重名。添加后，记账、提醒、现场登记里的关系选项都会多出这一项。")
            }

            Section {
                ForEach(LiqianConstants.relations, id: \.self) { name in
                    HStack {
                        Text(name)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text("系统")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                }
            } header: {
                Text("系统关系")
            }

            Section {
                if customs.isEmpty {
                    Text("还没有添加过关系。常用的老关系可以在上面一键添加。")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                } else {
                    ForEach(customs, id: \.self) { name in
                        Text(name)
                            .foregroundStyle(Palette.ink)
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    delete(name)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                Text("我添加的")
            } footer: {
                Text("删除不影响已记的记录，记录上的关系照原样保留。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("关系管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { customs = RelationCatalog.custom() }
    }

    private func add(_ raw: String) {
        switch RelationCatalog.add(raw) {
        case .success:
            customs = RelationCatalog.custom()
            draft = ""
            errorText = nil
        case .failure(let error):
            switch error {
            case .empty:
                errorText = "先输入一个关系名。"
            case .tooLong:
                errorText = "关系名最多 \(RelationCatalog.maxLength) 个字。"
            case .duplicate:
                errorText = "这个关系已经有了，不用重复添加。"
            }
        }
    }

    private func delete(_ name: String) {
        RelationCatalog.remove(name)
        customs = RelationCatalog.custom()
    }
}
