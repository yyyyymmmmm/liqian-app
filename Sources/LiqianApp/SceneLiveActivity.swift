import ActivityKit
import Foundation
import LiqianCore

/// 现场模式 Live Activity 的 App 侧控制（启动/更新/结束）。
/// 全程静默降级：系统未授权（areActivitiesEnabled=false）、重签环境下
/// ActivityKit 不可用、request 抛错——任何一种都当没这功能，现场登记主流程
/// 绝不受影响。同一时刻至多一个现场横幅：start 时已有进行中的就只更新它。
enum SceneLiveActivityController {

    static func start(
        ledgerTitle: String, isBai: Bool,
        entryCount: Int, totalCents: Int, lastPerson: String
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = SceneActivityAttributes.ContentState(
            entryCount: entryCount, totalCents: totalCents, lastPerson: lastPerson
        )
        Task {
            if let existing = Activity<SceneActivityAttributes>.activities.first {
                await existing.update(ActivityContent(state: state, staleDate: nil))
                return
            }
            let attributes = SceneActivityAttributes(ledgerTitle: ledgerTitle, isBai: isBai)
            _ = try? Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        }
    }

    static func update(entryCount: Int, totalCents: Int, lastPerson: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = SceneActivityAttributes.ContentState(
            entryCount: entryCount, totalCents: totalCents, lastPerson: lastPerson
        )
        Task {
            guard let activity = Activity<SceneActivityAttributes>.activities.first else { return }
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    static func end() {
        Task {
            for activity in Activity<SceneActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .default)
            }
        }
    }
}
