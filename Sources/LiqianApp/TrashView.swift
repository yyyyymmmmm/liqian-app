import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 最近删除：删掉的礼簿/记录在这里保留 30 天。
/// 恢复入口可见化（PRO-AUDIT-2 F8）：左滑「恢复」＋长按菜单＋页脚说明三路，
/// 不再只靠右滑手势记忆；列表形态与其余页归一为 insetGrouped 原生行。
struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @State private var items: [TrashItem] = []
    @State private var confirmClearAll = false
    @State private var restoreTrigger = 0

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "最近删除是空的",
                    systemImage: "trash",
                    description: Text("删除的礼簿与记录保留 30 天，过期自动清除，期间可恢复。")
                )
            } else {
                List {
                    Section {
                        ForEach(items) { item in
                            row(item)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        restore(item)
                                    } label: {
                                        Label("恢复", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(Palette.primaryFill)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        purge(item)
                                    } label: {
                                        Label("彻底删除", systemImage: "trash.slash")
                                    }
                                    Button {
                                        restore(item)
                                    } label: {
                                        Label("恢复", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(Palette.primary)
                                }
                                .contextMenu {
                                    Button {
                                        restore(item)
                                    } label: {
                                        Label("恢复", systemImage: "arrow.uturn.backward")
                                    }
                                    Button(role: .destructive) {
                                        purge(item)
                                    } label: {
                                        Label("彻底删除", systemImage: "trash.slash")
                                    }
                                }
                        }
                    } footer: {
                        Text("左滑或长按一行可恢复或彻底删除。")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Palette.pageBG.ignoresSafeArea())
            }
        }
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("最近删除")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空最近删除", role: .destructive) {
                        confirmClearAll = true
                    }
                }
            }
        }
        .confirmationDialog("清空最近删除？", isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("全部彻底删除", role: .destructive) {
                TrashStore.clearAll()
                reload()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空后无法恢复。")
        }
        .sensoryFeedback(.success, trigger: restoreTrigger)
        .onAppear { reload() }
    }

    private func reload() {
        items = TrashStore.list()
    }

    private func restore(_ item: TrashItem) {
        if TrashStore.restore(id: item.id, into: modelContext) {
            restoreTrigger += 1
        }
        reload()
    }

    private func purge(_ item: TrashItem) {
        TrashStore.purge(id: item.id)
        reload()
    }

    /// 记录所属礼簿是否白事（方向签用色，F9）：按快照的 ledgerID 反查现存礼簿
    private func isBai(item: TrashItem) -> Bool {
        guard let lid = item.ledgerID else { return false }
        return ledgers.first { $0.id.uuidString == lid }?.isBai ?? false
    }

    private func row(_ item: TrashItem) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
            switch item.kind {
            case .record:
                if let r = item.record {
                    HStack(spacing: LiqianMetrics.spacingS) {
                        Text(r.person)
                            .foregroundStyle(Palette.ink)
                        DirectionTag(direction: r.direction, bai: isBai(item: item))
                        Spacer()
                        Text(LedgerMath.fmtMoney(cents: r.amountCents))
                            .font(.liqianMoney(.title3))
                            .foregroundStyle(Palette.ink)
                    }
                    Text("一笔记录 · \(LiqianDate.displayString(for: r.date))")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
            case .ledger:
                if let l = item.ledger {
                    HStack(spacing: LiqianMetrics.spacingS) {
                        Text(l.title)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(item.ledgerRecords?.count ?? 0) 笔")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                    Text("整本礼簿 · \(l.type) · \(LiqianDate.displayString(for: l.date))")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
            }
            Text("删除于 \(Self.dateText(item.deletedAt)) · 还剩 \(item.daysLeft) 天")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
        .padding(.vertical, LiqianMetrics.spacingXS)
        .contentShape(Rectangle())
    }

    private static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }
}
