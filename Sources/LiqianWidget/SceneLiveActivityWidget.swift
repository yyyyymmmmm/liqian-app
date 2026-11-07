import ActivityKit
import SwiftUI
import WidgetKit
import LiqianCore

// MARK: - 现场模式 Live Activity（锁屏横幅＋灵动岛）
// 启动/更新/结束在 App 侧 SceneLiveActivityController；这里只负责渲染。
// 内容全是本场进度（笔数/合计/最近一位），不含敏感个人信息细节，
// 金额仍挂 .privacySensitive() 与其他组件同口径。
struct SceneLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SceneActivityAttributes.self) { context in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.ledgerTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text("现场收礼 · 已登记 \(context.state.entryCount) 笔")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(fmtMoney(cents: context.state.totalCents))
                        .font(.system(.headline, weight: .semibold).monospacedDigit())
                        .privacySensitive()
                    if !context.state.lastPerson.isEmpty {
                        Text("最近 · \(context.state.lastPerson)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(WPalette.paper)
            .activitySystemActionForegroundColor(WPalette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.ledgerTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("已登记 \(context.state.entryCount) 笔")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(fmtMoney(cents: context.state.totalCents))
                        .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                        .privacySensitive()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.lastPerson.isEmpty {
                        Text("最近登记 · \(context.state.lastPerson)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                Image(systemName: "book.closed")
            } compactTrailing: {
                Text("\(context.state.entryCount) 笔")
                    .font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: "book.closed")
            }
        }
    }
}
