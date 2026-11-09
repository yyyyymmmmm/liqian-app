import Foundation

// MARK: - 礼谱内页条目流（v5.12.1：废止 v3.1「段段换页」，纯计算可单测）

/// 内页条目流的一项：节题签列或一笔记录列。节与节在同一条流里相接，
/// 整流排满页列数才换页——节结束不换页（v3.1 的旧规矩是逐节独立
/// 切块，一节 1 笔也独占一页，用户实报「没写满就换了一页」）。
public enum LibuFlowEntry<Element> {
    case sectionTitle(relation: String, count: Int)
    case record(Element)
}

public enum LibuBookFlow {
    /// 拼流：每节＝[题签列，该节各笔记录列…]，节序与节内序即入参序。
    /// includeTitles 为假（全册只有一节）时不出题签、流里只有记录，
    /// 与汇总小计「单组不出组头」的口径一致。
    public static func entries<Element>(
        sections: [LibuRelationSection<Element>],
        includeTitles: Bool
    ) -> [LibuFlowEntry<Element>] {
        var flow: [LibuFlowEntry<Element>] = []
        for section in sections {
            if includeTitles {
                flow.append(.sectionTitle(
                    relation: section.relation, count: section.records.count
                ))
            }
            flow.append(contentsOf: section.records.map { LibuFlowEntry.record($0) })
        }
        return flow
    }

    /// 切页：按 columnsPerPage 贪心装页，带题签孤行守护——题签列不许
    /// 落在一页的最后一列（其记录全在下页会题文与正文分离），恰逢
    /// 页末列时顺延到下页首列，该页就此收页、少排一列。
    public static func paginate<Element>(
        entries: [LibuFlowEntry<Element>],
        columnsPerPage: Int
    ) -> [[LibuFlowEntry<Element>]] {
        guard !entries.isEmpty, columnsPerPage > 0 else { return [] }
        var pages: [[LibuFlowEntry<Element>]] = []
        var current: [LibuFlowEntry<Element>] = []
        for entry in entries {
            if !current.isEmpty, current.count == columnsPerPage - 1,
               case .sectionTitle = entry {
                pages.append(current)
                current = []
            }
            if current.count == columnsPerPage {
                pages.append(current)
                current = []
            }
            current.append(entry)
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }
}

// MARK: - 姓名列分档（v5.12.1：超 4 字不截断，按字数降字号整列收进）

public enum LibuNameLayout {
    /// 字号/步距分档：≤4 字原档（20/27，与 v2.10 的 3 字位归一排版
    /// 同值）；5–6 字降一档（16/22）；7 字以上再降一档（13/18）。
    /// 旧版在绘制层硬取前 4 字，5 字以上姓名被静默砍掉尾字、无任何
    /// 标记——礼谱是留存物，错名性质重，本档保证全名完整绘出。
    public static func tier(characterCount: Int) -> (fontSize: CGFloat, step: CGFloat) {
        if characterCount <= 4 { return (20, 27) }
        if characterCount <= 6 { return (16, 22) }
        return (13, 18)
    }

    /// 姓名列占的纵向槽位数：沿 v2.10 归一口径（不足 3 字按 3 字位，
    /// 短名与三字名底边齐），长名按实际字数。
    public static func slotCount(characterCount: Int) -> Int {
        max(3, characterCount)
    }

    /// 姓名列总高（列顶到列底）＝槽位数 × 该档步距。
    public static func height(characterCount: Int) -> CGFloat {
        CGFloat(slotCount(characterCount: characterCount))
            * tier(characterCount: characterCount).step
    }
}

// MARK: - 金额大写分档与记录列高模型（v5.12.1：大写防溢出）

public enum LibuAmountLayout {
    /// 大写字号/步距分档：≤10 字原档（13/18）；11–14 字步距收一档
    /// （13/15）；15 字以上字号步距同收（12/13）。阈值按诊断测算：
    /// 13 字大写（¥188,888）配四字名＋最长小字＋首笔日期时，原档
    /// 整列约 678pt、超 647pt 列高会压版框下线；收一档后约 639pt
    /// 收得进。旧版 drawVertical 无下界检查、无截断、无缩放。
    public static func tier(uppercaseCount: Int) -> (fontSize: CGFloat, step: CGFloat) {
        if uppercaseCount <= 10 { return (13, 18) }
        if uppercaseCount <= 14 { return (13, 15) }
        return (12, 13)
    }
}

/// 记录列高的单一事实源：GiftBookPDF 内页的列内堆叠（姓名→间隔→
/// 大写→间隔→小字→首笔日期）逐项与此同值（绘制层直接引用这些
/// 常量与分档），单测据此断言最不利组合不溢出列高。
public enum LibuColumnMetrics {
    /// 列可用高：版心 contentTop 116 → contentBottom 763。
    public static let columnHeight: CGFloat = 647
    public static let gapAfterName: CGFloat = 14
    public static let gapAfterAmount: CGFloat = 10
    public static let gapBeforeDate: CGFloat = 8
    /// 小字（阿拉伯金额＋方式）步距（衬线 9 号）。
    public static let smallStep: CGFloat = 13
    /// 首笔日期小字步距（楷体 10.5）。
    public static let dateStep: CGFloat = 14

    /// 一笔记录列的总高；dateCount 为 nil 表示该笔不是当日首笔
    /// （不出日期小字）。
    public static func recordHeight(
        nameCount: Int, uppercaseCount: Int, smallCount: Int, dateCount: Int?
    ) -> CGFloat {
        var height = LibuNameLayout.height(characterCount: nameCount)
        height += gapAfterName
        height += CGFloat(uppercaseCount)
            * LibuAmountLayout.tier(uppercaseCount: uppercaseCount).step
        height += gapAfterAmount
        height += CGFloat(smallCount) * smallStep
        if let dateCount {
            height += gapBeforeDate + CGFloat(dateCount) * dateStep
        }
        return height
    }
}

// MARK: - 彙总行流分页（v5.12.1：keep-together，纯计算可单测）

/// 彙总的一行：dy 为行后步进；group 为所属组序号（同组行在数组中
/// 相邻）；keepGroupWhole 标记该组应整组同页（按方式/按關係小計
/// 这类小组），大组（按日小計）置假、只保组头不落单。
public struct LibuSummaryRow {
    public let dy: CGFloat
    public let isHeader: Bool
    public let group: Int
    public let keepGroupWhole: Bool

    public init(dy: CGFloat, isHeader: Bool, group: Int, keepGroupWhole: Bool) {
        self.dy = dy
        self.isHeader = isHeader
        self.group = group
        self.keepGroupWhole = keepGroupWhole
    }
}

public enum LibuSummaryPaginator {
    /// 把彙总行流切成页（返回每页的行下标）。容量均为「自该页行流
    /// 起点起可用的高度」：firstPageCapacity/pageCapacity 以行流排到
    /// 版心底为限；lastPage*Capacity 是末页保护——末页行流不得越过
    /// 校对/落款区上界，超了把尾行顺次挪到新页。
    /// 规则：①keepGroupWhole 的组若整组放得进一整页，就整组同页
    /// （放不进当前页剩余空间时整组换页）；整组比一页还高时退化
    /// 为逐行流。②组头行不许成为一页的最后一行。③末页挪行的
    /// 切口同样服从 ①②——复核在挪行之后做，不断整组、不留组头
    /// 落单。旧版是扁平行数组纯机械切块，彙总会断在小計组中间。
    public static func paginate(
        rows: [LibuSummaryRow],
        firstPageCapacity: CGFloat,
        pageCapacity: CGFloat,
        lastPageCapacity: CGFloat,
        lastPageFirstCapacity: CGFloat
    ) -> [[Int]] {
        guard !rows.isEmpty else { return [[]] }

        func capacity(pageIndex: Int) -> CGFloat {
            pageIndex == 0 ? firstPageCapacity : pageCapacity
        }
        // 组区间（同组相邻）：[(start, end))
        var groupRanges: [(start: Int, end: Int)] = []
        for (i, row) in rows.enumerated() {
            if let last = groupRanges.last, rows[last.end - 1].group == row.group {
                groupRanges[groupRanges.count - 1].end = i + 1
            } else {
                groupRanges.append((start: i, end: i + 1))
            }
        }
        func height(_ range: (start: Int, end: Int)) -> CGFloat {
            rows[range.start..<range.end].reduce(0) { $0 + $1.dy }
        }

        // —— 贪心装页（规则 ①②）——
        var pages: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        func closePage() {
            pages.append(current)
            current = []
            used = 0
        }
        for range in groupRanges {
            let groupHeight = height(range)
            if rows[range.start].keepGroupWhole {
                if groupHeight <= capacity(pageIndex: pages.count) - used {
                    for i in range.start..<range.end {
                        current.append(i)
                        used += rows[i].dy
                    }
                    continue
                }
                if !current.isEmpty,
                   groupHeight <= capacity(pageIndex: pages.count + 1) {
                    closePage()
                    for i in range.start..<range.end {
                        current.append(i)
                        used += rows[i].dy
                    }
                    continue
                }
                // 整组比一页还高：退化为逐行流（仍守规则 ②）
            }
            for i in range.start..<range.end {
                let row = rows[i]
                if !current.isEmpty,
                   used + row.dy > capacity(pageIndex: pages.count) {
                    closePage()
                }
                if row.isHeader, !current.isEmpty, i + 1 < rows.count,
                   used + row.dy <= capacity(pageIndex: pages.count),
                   used + row.dy + rows[i + 1].dy > capacity(pageIndex: pages.count) {
                    // 组头放得下、组员放不下：组头随组员一起换页
                    closePage()
                }
                current.append(i)
                used += row.dy
            }
        }
        if !current.isEmpty { closePage() }
        guard !pages.isEmpty else { return [[]] }

        // —— 末页保护＋切口复核（规则 ③）——
        func pageHeight(_ page: [Int]) -> CGFloat {
            page.reduce(0) { $0 + rows[$1].dy }
        }
        while pages.count >= 1 {
            let last = pages[pages.count - 1]
            let limit = pages.count == 1 ? lastPageFirstCapacity : lastPageCapacity
            guard last.count > 1, pageHeight(last) > limit else { break }
            // 保留行数 split：从末尾逐行挪出，直到保留部分 ≤ limit
            var split = last.count
            var keepHeight = pageHeight(last)
            while split > 1, keepHeight > limit {
                split -= 1
                keepHeight -= rows[last[split]].dy
            }
            // 切口复核（交替至稳定）：保留页不许组头收尾；切口不许
            // 把 keepGroupWhole 的组劈开（整组随行）。split 只减不增。
            var adjusted = true
            while adjusted, split > 1 {
                adjusted = false
                if rows[last[split - 1]].isHeader {
                    split -= 1
                    adjusted = true
                    continue
                }
                if split < last.count,
                   rows[last[split - 1]].group == rows[last[split]].group,
                   rows[last[split]].keepGroupWhole {
                    split -= 1
                    adjusted = true
                }
            }
            pages[pages.count - 1] = Array(last[..<split])
            pages.append(Array(last[split...]))
        }
        return pages
    }
}
