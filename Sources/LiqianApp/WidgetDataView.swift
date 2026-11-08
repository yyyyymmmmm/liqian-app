import SwiftUI
import LiqianCore
import LiqianDesign

/// 小组件数据自检页（v5.11.1）：把 App 写、Widget 读这条共享通道的
/// 状态全部摆在面上——解析组名、最近写入与写后回读、逐候选探活、
/// 组件回执。入口在「我的 → 数据 → 小组件数据」。读数与三种故障
/// 子情形的对照表见 docs/V5111-NOTES.md：一张本页截图即可定案，
/// 不再靠猜。全页只读探活，不写任何数据（回执由 Widget 自己写）。
struct WidgetDataView: View {
    @State private var status = WidgetDiag.status()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    Text("解析组名")
                        .foregroundStyle(Palette.ink)
                    Text(status.resolvedGroup)
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                        .textSelection(.enabled)
                }
                .frame(minHeight: LiqianMetrics.minTapTarget)
                LabeledContent("数据通道") {
                    Text(status.suiteAvailable ? "可用" : "不可用")
                        .foregroundStyle(status.suiteAvailable ? Palette.ink : Palette.primary)
                }
                LabeledContent("组容器（配发）") {
                    Text(status.containerAvailable ? "存在" : "不存在")
                        .foregroundStyle(status.containerAvailable ? Palette.ink : Palette.primary)
                }
                LabeledContent("最近一次尝试") {
                    Text(status.attemptAt.map(WidgetDiag.timeText) ?? "从未")
                }
                LabeledContent("尝试结果") {
                    Text(resultText)
                }
                LabeledContent("最近写入") {
                    Text(writtenText)
                }
                LabeledContent("写后回读") {
                    Text(readbackText)
                }
            } header: {
                Text("写入状态")
            } footer: {
                Text("礼记每次打开或回到前台都会把小组件数据写入上面的组名通道，写完立即回读校验。数据通道不可用或组容器不存在，说明这个组没有在当前安装里建成，组件读不到数据。")
            }

            Section {
                ForEach(status.probes, id: \.groupID) { probe in
                    VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                        Text(probe.groupID)
                            .font(.footnote)
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                        Text(probeText(probe))
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                }
            } header: {
                Text("备用通道")
            } footer: {
                Text("组件读取时按上面顺序逐个尝试，命中哪家用哪家；礼记写入只写解析组名一家，不多处分发。若只有非第一家有数据，说明两边解析出的组名曾经不一致。")
            }

            Section {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    Text("组件实际读到的组名")
                        .foregroundStyle(Palette.ink)
                    Text(status.receiptGroup ?? "尚未收到组件回执")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                        .textSelection(.enabled)
                }
                .frame(minHeight: LiqianMetrics.minTapTarget)
                LabeledContent("回执时间") {
                    Text(status.receiptAt.map(WidgetDiag.timeText) ?? "—")
                }
            } header: {
                Text("组件回执")
            } footer: {
                Text("组件每次成功读到数据都会留下回执。长期没有回执，说明组件从没在任何一家通道读到过数据；回执组名与解析组名不同，说明组件是从备用通道读到的。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("小组件数据")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("重新检测") { status = WidgetDiag.status() }
            }
        }
    }

    private var resultText: String {
        switch status.result {
        case WidgetSummaryWriter.DiagResult.ok: return "成功"
        case WidgetSummaryWriter.DiagResult.suiteNil: return "失败：数据通道不可用"
        case WidgetSummaryWriter.DiagResult.encodeFailed: return "失败：编码出错"
        case nil: return "—"
        default: return "未知"
        }
    }

    private var writtenText: String {
        guard let writtenAt = status.writtenAt else { return "暂无" }
        return "\(WidgetDiag.timeText(writtenAt)) · \(status.bytes) 字节"
    }

    private var readbackText: String {
        switch status.readbackOK {
        case true: return "命中"
        case false: return "未命中"
        case nil: return "无记录"
        }
    }

    private func probeText(_ probe: WidgetDiag.CandidateProbe) -> String {
        if probe.hasSummary {
            var text = "有数据 · \(probe.summaryBytes) 字节"
            if let writtenAt = probe.writtenAt {
                text += " · 写入于 \(WidgetDiag.timeText(writtenAt))"
            }
            return text
        }
        if !probe.containerAvailable { return "组容器不存在" }
        if !probe.suiteAvailable { return "通道不可用" }
        return "通道在，暂无数据"
    }
}
