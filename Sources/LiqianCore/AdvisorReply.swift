import Foundation

// MARK: - 问账回复收敛（v5.7）：任何一次提问必须落一条可见回复
//
// 背景（真机点名）：问账里问「明天天气咋样」没有任何回复。逐出口查实
// （见 docs/V57-NOTES.md）：旧管线不存在能「回答账外问题」的出口——
// 工具问答的系统提示词第 6 条明令拒绝账外问题、工具循环走满后落回
// 意图管线，意图解析对账外问题只给 unknown、规则兜底返回 nil，终点
// 是 .unsupported 的「这个问法我还不会」非答复卡；最坏情况还要串行
// 走满 4 轮工具＋1 轮意图解析才落地，用户席上就是长时间沉默。
//
// v5.7 的收敛结构（AdvisorView.ask 按此顺序落点）：
// 1. 工具问答（含账外 lane：账外问题由模型在第一轮直接作答）；
// 2. 意图解析＋规则兜底 → AdvisorEngine 结构化结果卡（账内问法）；
// 3. 通用作答 lane（无工具纯文本，模型用自身知识回答账外问题）；
// 4. 本收敛器裁决最终出口：有通用回答出回答、AI 未就绪出
//    .unsupported 卡（带开通引导）、AI 就绪但全链失败出致歉文案。
// 本文件只做第 4 步的纯决策与兜底文案单点定义，可单测；网络与模型
// 调用都在 App 层，收敛器不碰。

public enum AdvisorReplyConvergence {

    /// 收敛裁决的三种终点（UI 层按 case 呈现，不再有第四种可能）
    public enum Outcome: Equatable, Sendable {
        /// 账外问题由模型自身知识作答（文本已去首尾空白、保证非空）
        case generalAnswer(String)
        /// AI 未就绪（无 Key/未启用）且规则兜底也兜不住：
        /// 出既有 .unsupported 卡，卡内文案自带开通引导
        case unsupportedWithoutAI
        /// AI 就绪但全链失败（网络异常/接口异常等真故障）：
        /// 致歉并建议重试，不把故障伪装成「不会这个问题」
        case failureApology
    }

    /// - aiReady: AIAccess.readiness() == .ready
    /// - generalAnswer: 通用作答 lane 的返回值；nil 或纯空白都视为没拿到
    public static func resolve(aiReady: Bool, generalAnswer: String?) -> Outcome {
        if let generalAnswer {
            let trimmed = generalAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return .generalAnswer(trimmed)
            }
        }
        return aiReady ? .failureApology : .unsupportedWithoutAI
    }

    /// 真故障兜底文案（单点定义，UI 与单测共用，不在视图里散写）
    public static let failureApologyText =
        "这次没答上来，可能是网络不太顺。请检查网络后稍等一下再问我；也可以先换个说法问我账上的事。"
}
