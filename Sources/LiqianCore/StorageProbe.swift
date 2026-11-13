import Foundation
import SwiftData

/// 存储落盘自检探针（v5.14.2）：启动时往真容器里写一条带随机 token 的
/// 探针记录、save 后换一个新 context 回读核对、删净。
///
/// 为什么要一条独立实体：拿用户实体（礼簿/记录/提醒）做探针，删除
/// 失败或进程中途死掉会把假数据留在用户账里；探针实体不进备份、
/// 不进任何列表与统计口径（全仓呈现/汇总只查业务实体），探针后
/// 确删，残留也无害（下次启动探针先清残留再测）。
/// CloudKit 兼容口径与全仓模型一致：无唯一约束、属性带默认值。
@Model
public final class StorageProbe {
    public var id: UUID = UUID()
    /// 本次启动探针的随机令牌，回读时按它核对确实是刚写下的那条
    public var token: UUID = UUID()
    public var createdAt: Date = Date()

    public init(id: UUID = UUID(), token: UUID, createdAt: Date = Date()) {
        self.id = id
        self.token = token
        self.createdAt = createdAt
    }
}
