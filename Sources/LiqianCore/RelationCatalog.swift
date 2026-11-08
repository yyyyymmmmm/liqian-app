import Foundation

// MARK: - 关系目录（自定义关系：系统词表 + 用户新增）
//
// 系统关系是 LiqianConstants.relations（亲戚/朋友/同事/同学/邻居/其他）；
// 用户可以在「我的 → 记录 → 关系管理」里新增系统之外的关系（如闺蜜、战友），
// 存 UserDefaults 的 JSON [String]（键 customRelationsKey）。记录本身一直只存
// 关系字符串，删掉某个自定义关系不影响已记的记录（记录照原样保留该字符串）。
// 本期不做改名/排序/跨设备同步；后续如需同步可改走 NSUbiquitousKeyValueStore。

public enum RelationCatalog {
    /// UserDefaults 存储键（备份恢复写回也用同一常量，勿改字面）
    public static let customRelationsKey = "customRelations"

    /// 自定义关系字数上限（校验口径，管理页与解析共用）
    public static let maxLength = 6

    // MARK: - 读取

    /// 全部可选关系：系统词表在前、自定义按添加顺序附后（动态读，
    /// 管理页改完返回选择器即生效，无需重启）。
    public static func all(in defaults: UserDefaults = .standard) -> [String] {
        LiqianConstants.relations + custom(in: defaults)
    }

    /// 只读自定义部分（已清洗：去空白、去空、与系统词表及自身不重名）。
    public static func custom(in defaults: UserDefaults = .standard) -> [String] {
        guard let data = defaults.data(forKey: customRelationsKey),
              let list = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return sanitized(list)
    }

    /// 选择器数据源：all() 基础上临时并入 current（编辑旧记录时它可能是一条
    /// 已被删除的自定义关系，不并入 Picker 的选中态会丢、显示空白）。
    /// current 为空串时不并入。
    public static func pickerOptions(
        including current: String, in defaults: UserDefaults = .standard
    ) -> [String] {
        let base = all(in: defaults)
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !base.contains(trimmed) else { return base }
        return base + [trimmed]
    }

    // MARK: - 写入

    /// 整体覆盖自定义列表（备份恢复写回走这里）；写入前同样清洗。
    public static func setCustom(
        _ list: [String], in defaults: UserDefaults = .standard
    ) {
        let clean = sanitized(list)
        if let data = try? JSONEncoder().encode(clean) {
            defaults.set(data, forKey: customRelationsKey)
        }
    }

    /// 校验一条待新增的关系（纯函数，可单测）。existing 传 all() 全量，
    /// 与系统词表重名也算重复。
    public static func validate(
        _ raw: String, existing: [String]
    ) -> Result<String, RelationValidationError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .failure(.empty) }
        if trimmed.count > maxLength { return .failure(.tooLong) }
        if existing.contains(trimmed) { return .failure(.duplicate) }
        return .success(trimmed)
    }

    /// 新增一条自定义关系：校验通过才写入，返回清洗后的关系名或失败原因。
    @discardableResult
    public static func add(
        _ raw: String, in defaults: UserDefaults = .standard
    ) -> Result<String, RelationValidationError> {
        switch validate(raw, existing: all(in: defaults)) {
        case .failure(let error):
            return .failure(error)
        case .success(let name):
            setCustom(custom(in: defaults) + [name], in: defaults)
            return .success(name)
        }
    }

    /// 删除一条自定义关系（系统关系不在自定义列表里，删它无效果）。
    /// 已记的记录不受影响——记录上的关系字符串照原样保留。
    public static func remove(
        _ name: String, in defaults: UserDefaults = .standard
    ) {
        setCustom(custom(in: defaults).filter { $0 != name }, in: defaults)
    }

    // MARK: - 改名（v5.10：用户拍板级联改变，历史记录随改名一起变）

    /// 改名校验（纯函数，可单测）：规则与新增一致（去空白、≤6 字），
    /// 但重名判定要把旧名自身排除——新名与旧名相同视为「不改」放行，
    /// 与系统词表或其他自定义关系重名仍判 duplicate。
    /// existing 传 all() 全量（含旧名）。
    public static func validateRename(
        from old: String, rawNew: String, existing: [String]
    ) -> Result<String, RelationValidationError> {
        let trimmed = rawNew.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .failure(.empty) }
        if trimmed.count > maxLength { return .failure(.tooLong) }
        if trimmed != old, existing.contains(trimmed) { return .failure(.duplicate) }
        return .success(trimmed)
    }

    /// 目录内改名：把自定义列表里的旧名原位换成新名（顺序不变）。
    /// 旧名不在自定义列表（系统关系/不存在）时返回 false、目录不动——
    /// 系统关系不可改名由调用方在 UI 层拦下，这里是第二道防线。
    /// 只动目录；记录/提醒/回收站快照的级联改写由 RelationCascade 在
    /// 调用方逐处执行（值映射口径与本函数的新名一致）。
    @discardableResult
    public static func renameCustom(
        from old: String, to new: String, in defaults: UserDefaults = .standard
    ) -> Bool {
        var list = custom(in: defaults)
        guard let idx = list.firstIndex(of: old) else { return false }
        list[idx] = new
        setCustom(list, in: defaults)
        // setCustom 会清洗：若新名与系统词表撞名会被剔除，改名即失败，回读确认
        return custom(in: defaults).contains(new)
    }

    // MARK: - 排序（v5.10：自定义顺序就是选择器里自定义部分的顺序）

    /// 从一份「全部关系」的新顺序里提取自定义关系的相对顺序（纯函数）。
    /// 系统关系在 all() 里恒定居前、不参与排序持久化；管理页把整表拖动
    /// 的结果传进来，这里只取自定义名在新顺序中的先后写回。
    public static func extractCustomOrder(
        from fullOrder: [String], customs: [String]
    ) -> [String] {
        let set = Set(customs)
        var result = fullOrder.filter { set.contains($0) }
        // 兜底：fullOrder 里缺失的自定义名按原序补回尾部，一个不丢
        for name in customs where !result.contains(name) { result.append(name) }
        return result
    }

    /// 按管理页拖动后的整表顺序重写自定义顺序（系统部分忽略）。
    public static func applyOrder(
        fullOrder: [String], in defaults: UserDefaults = .standard
    ) {
        setCustom(
            extractCustomOrder(from: fullOrder, customs: custom(in: defaults)),
            in: defaults
        )
    }

    /// 清洗：逐条去空白、去空、去掉与系统词表重名者、自身去重保序。
    private static func sanitized(_ list: [String]) -> [String] {
        var seen = Set(LiqianConstants.relations)
        var result: [String] = []
        for item in list {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }
}

/// 新增关系校验失败原因（管理页据此给人话提示）
public enum RelationValidationError: Error, Equatable {
    case empty
    case tooLong
    case duplicate
}

// MARK: - 改名级联的值映射（v5.10）
//
// 用户拍板：改名＝级联改变。目录改名之外，所有落了旧名的引用都要改写：
// 账目记录（GiftRecord.relation）、提醒（ReminderDay.relation）、回收站
// 快照（BackupRecord.relation）。值映射只有一个口径——恰好等于旧名才换
// 新名，其余原样——收敛在这里一处纯函数，App 层逐模型套用、单测证明
// 套用后旧名零残留（old != new 时）。
public enum RelationCascade {
    /// 单值映射：等于旧名 → 新名；否则原样。
    public static func map(_ value: String, from old: String, to new: String) -> String {
        value == old ? new : value
    }

    /// 整列映射（校验/单测用）：对一组关系值套用级联。
    public static func applied(to values: [String], from old: String, to new: String) -> [String] {
        values.map { map($0, from: old, to: new) }
    }
}
