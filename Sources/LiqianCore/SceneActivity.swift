import ActivityKit
import Foundation

/// 现场模式 Live Activity 的类型定义（App 启动/更新、Widget 扩展渲染，两边共享，
/// 故放 Core——App 与 LiqianWidget target 都依赖 LiqianCore）。
/// 现场收礼台一开几小时，锁屏横幅实时显示本场进度（笔数/合计/最近一位），
/// 书记锁屏也能核对，不用反复解锁进 App。
public struct SceneActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// 本场已登记笔数
        public var entryCount: Int
        /// 本场收礼合计（分）
        public var totalCents: Int
        /// 最近登记的一位来宾姓名（可能为空：刚开场还没记）
        public var lastPerson: String

        public init(entryCount: Int, totalCents: Int, lastPerson: String) {
            self.entryCount = entryCount
            self.totalCents = totalCents
            self.lastPerson = lastPerson
        }
    }

    /// 礼簿名（开场时定格，现场中途改名不影响横幅）
    public var ledgerTitle: String
    /// 白事场：横幅走素色口径
    public var isBai: Bool

    public init(ledgerTitle: String, isBai: Bool) {
        self.ledgerTitle = ledgerTitle
        self.isBai = isBai
    }
}
