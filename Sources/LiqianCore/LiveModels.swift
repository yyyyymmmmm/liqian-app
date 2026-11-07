import Foundation
import SwiftData

// MARK: - 活礼谱（v4.2）：来宾签名 + 语音祝福
//
// 「活礼谱」把礼谱从静态账目变成有笔迹、有声音的家族信物：
// - GuestSignature：来宾在 App 内手写签名（PencilKit 画布存 PNG），
//   礼谱 PDF 汇总成「簽名頁」，电子礼谱里显缩略图。
// - VoiceBlessing：来宾/主家录的语音祝福（音频文件存 App 容器目录，
//   库里只存相对文件名），礼谱内页以「聲」小印记标示，卷末祝福索引页
//   印深链二维码，扫码在装有 App 的设备上打开播放。
// 二进制（签名图/音频）不进 JSON 备份：备份只带元数据段（见 Backup.swift），
// 签名与录音本体保存在本机、随 iCloud 同步（备份页文案已如实注明）。

/// 来宾签名：一条签名挂一本礼簿；recordID 可空——现场流程里可以先签、
/// 后与记录对应（挂账笔时填上）。person 是签名人姓名原文（用户数据，
/// 照原样保存与展示，严禁繁简转换，与全谱口径一致）。
@Model
public final class GuestSignature {
    // CloudKit 不支持唯一约束（与全仓模型同口径，v4.0 iCloud 适配）：唯一性由 UUID 保证
    public var id: UUID = UUID()
    public var ledgerID: UUID = UUID()
    public var recordID: UUID?
    public var person: String = ""
    /// 签名 PNG 数据（外部存储，不撑主库文件）
    @Attribute(.externalStorage) public var imageData: Data = Data()
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        ledgerID: UUID,
        recordID: UUID? = nil,
        person: String,
        imageData: Data,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ledgerID = ledgerID
        self.recordID = recordID
        self.person = person
        self.imageData = imageData
        self.createdAt = createdAt
    }
}

/// 语音祝福：一条祝福必挂一笔记录（recordID 非空——祝福是「对这笔礼」的
/// 祝福）。fileName 只是文件名（如 "blessing-<uuid>.m4a"），音频本体在
/// App 容器 Application Support/Blessings/ 下，路径组装走 App 层
/// BlessingAudioStore。transcript 是录后语音转文字的结果，可空（未转/
/// 转写不可用时留空，不编造）。
@Model
public final class VoiceBlessing {
    // CloudKit 不支持唯一约束（与全仓模型同口径，v4.0 iCloud 适配）：唯一性由 UUID 保证
    public var id: UUID = UUID()
    public var recordID: UUID = UUID()
    public var fileName: String = ""
    /// 时长（秒）
    public var duration: Double = 0
    public var transcript: String?
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        recordID: UUID,
        fileName: String,
        duration: Double,
        transcript: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recordID = recordID
        self.fileName = fileName
        self.duration = duration
        self.transcript = transcript
        self.createdAt = createdAt
    }

    /// 祝福索引页二维码的深链（liqian://blessing/<id>）：
    /// 需装有本 App 的设备扫码才能打开播放，外部不可用（索引页已注明）。
    public var deepLink: String { LiqianDeepLink.blessingURL(id: id) }
}

// MARK: - 深链（liqian:// scheme；与小组件 liqian://quick-record 同一 scheme）

public enum LiqianDeepLink {
    public static func blessingURL(id: UUID) -> String {
        "liqian://blessing/\(id.uuidString)"
    }

    /// 从 URL 解析祝福 id；不是祝福深链时返回 nil
    public static func blessingID(from url: URL) -> UUID? {
        guard url.scheme == "liqian", url.host == "blessing" else { return nil }
        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: raw)
    }
}

// MARK: - ISO8601 时间串（备份元数据段的 createdAt 用）

public enum LiqianISO8601 {
    public static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// 解析失败返回 nil（备份数据容错，不让一条坏时间拖垮整段）
    public static func date(from string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
