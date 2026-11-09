import SwiftUI
import SwiftData
import LiqianCore
import LiqianDesign

/// 家族汇册生成页（v5，Pro）：多选礼簿 → 合并成一部汇册 PDF
/// （总目＋分章＋正文＋跨簿人物总索引）。示例礼簿不入汇册候选——
/// 汇册是传家物件，不混演示数据。
struct FamilyAlbumView: View {
    @Query(sort: \Ledger.date, order: .forward) private var ledgers: [Ledger]
    @Query private var allRecords: [GiftRecord]
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<UUID> = []
    @State private var generating = false
    @State private var albumURL: URL?
    @State private var errorText: String?

    private var candidates: [Ledger] {
        let sampleIDs = SampleData.sampleIDs(ledgers: ledgers)
        return ledgers.filter { !sampleIDs.contains($0.id) }
    }

    private func counted(of ledger: Ledger) -> [GiftRecord] {
        allRecords.filter { $0.ledgerID == ledger.id && !$0.isPendingSend }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { ledger in
                        Button {
                            if selected.contains(ledger.id) {
                                selected.remove(ledger.id)
                            } else {
                                selected.insert(ledger.id)
                            }
                            albumURL = nil
                        } label: {
                            HStack(spacing: LiqianMetrics.spacingSM) {
                                Image(systemName: selected.contains(ledger.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(ledger.id) ? Palette.primary : Palette.stone)
                                    .symbolEffect(.bounce, value: selected.contains(ledger.id))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ledger.title)
                                        .foregroundStyle(Palette.ink)
                                    Text("\(ledger.type) · \(LiqianDate.displayString(for: ledger.date)) · \(counted(of: ledger).count) 笔")
                                        .font(.footnote)
                                        .foregroundStyle(Palette.stone)
                                }
                                Spacer()
                            }
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("选择礼簿（至少两本）")
                } footer: {
                    Text("汇册按年份编章：卷首总目、逐簿章题页与正文（礼谱排版）、卷末跨簿人物总索引。生成需要一点时间。")
                }

                Section {
                    if generating {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            ProgressView()
                            Text("正在编册…")
                                .foregroundStyle(Palette.ink)
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                    } else if let albumURL {
                        PDFPreviewView(url: albumURL)
                            .frame(height: 480)
                            .listRowInsets(EdgeInsets())
                    } else {
                        Button {
                            generate()
                        } label: {
                            Text("生成汇册")
                                .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                        }
                        .disabled(selected.count < 2)
                        if let errorText {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(Palette.danger)
                        }
                    }
                } header: {
                    Text("成册")
                }
            }
            .listStyle(.insetGrouped)
            .background(Palette.groupedBackground.ignoresSafeArea())
            .navigationTitle("家族汇册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .safeAreaBar(edge: .bottom) {
                if let albumURL, !generating {
                    ShareLink(item: albumURL) {
                        Label("分享 / 保存汇册", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                    }
                    .liqianGlassButton(.tinted)
                    .padding(.horizontal, LiqianMetrics.spacingL)
                    .padding(.vertical, LiqianMetrics.spacingSM)
                }
            }
        }
    }

    private func generate() {
        let items = candidates
            .filter { selected.contains($0.id) }
            .map { FamilyAlbumPDF.Item(ledger: $0, countedRecords: counted(of: $0)) }
        guard items.count >= 2 else { return }
        generating = true
        errorText = nil
        Task {
            await Task.yield()
            let url = FamilyAlbumPDF.makeAlbum(items: items, libuScript: AppLanguage.resolved().libuScript)
            generating = false
            if let url {
                albumURL = url
            } else {
                errorText = "汇册生成失败，请重试。"
            }
        }
    }
}
