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
