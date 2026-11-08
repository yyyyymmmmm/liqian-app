import Foundation

/// 成书旗舰卡状态（v5.11.6）：首页礼谱成书旗舰卡的两态——升位
/// （场次日期已过＋成册笔数达标，卡升到礼簿段顶部）与常驻（卡在
/// 礼簿段下方）。状态判定规则本身仍在 HomeView（依赖账面数据），
/// 本枚举只承载「是哪一态」，供落点决策消费。
public enum BookFlagshipCardState: Equatable {
    case promoted
    case standing
}

/// 成书旗舰卡落点（v5.11.6）：点卡要去的页。导航机制（push 还是
/// sheet）是 App 层的事，本枚举只定「去哪一页、为哪本礼簿」。
public enum BookFlagshipDestination: Equatable {
    /// 升位态直达：成书说明/登记页
    case bookBinding(ledgerID: UUID)
    /// 常驻态直达：导出礼谱页（装订成书行就在该页内）
    case export(ledgerID: UUID)
}

/// 成书旗舰卡落点决策（v5.11.6 成书路径缩层，用户批准的审查整改
/// 第 2 件）：v5.11 的旧落点是两态都先进礼簿详情，再经详情页的
/// 导出 sheet 与「装订成书」行才到成书页——首页到成书说明共
/// 4 层，是全产品最深的高价值路径。本决策按卡态分开落点，路径
/// 缩为 2 层；礼簿行点按进详情、详情内原有导出/成书入口一律
/// 不动（旧路径保留，只是不再让旗舰卡绕它）。
///
/// 纯函数：只看卡态与礼簿 ID，单测钉死（BookFlagshipRouteTests）。
public enum BookFlagshipRouter {
    public static func destination(
        state: BookFlagshipCardState,
        ledgerID: UUID
    ) -> BookFlagshipDestination {
        switch state {
        case .promoted:
            return .bookBinding(ledgerID: ledgerID)
        case .standing:
            return .export(ledgerID: ledgerID)
        }
    }
}
