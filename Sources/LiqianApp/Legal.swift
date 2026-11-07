import SwiftUI
import LiqianDesign

/// 一节正文（标题在文档内唯一，兼作 ForEach 身份）
struct LegalSection: Identifiable {
    let heading: String
    let body: String
    var id: String { heading }
}

/// 一份法律文档：标题＋生效行＋分节正文。纯内置文本、离线可读，
/// 与「我的 → 关于」的数据说明同一口径（本地优先、iCloud 自有账号、
/// AI 自备 Key 直连），冲突时以本页为准。
struct LegalDoc {
    let title: String
    let effectiveLine: String
    let sections: [LegalSection]
}

enum LegalTexts {
    /// 生效日期占位：2026 年 11 月——正式对外发布前由用户确认到具体日期
    static let privacyPolicy = LegalDoc(
        title: "隐私政策",
        effectiveLine: "生效日期：2026 年 11 月 · 运营主体：知和数智",
        sections: [
            LegalSection(
                heading: "先说清楚的",
                body: "礼记是一款人情往来记账工具，由知和数智开发运营。我们不设账号体系，也没有服务器保存你的账目。你录入的内容默认只保存在你的设备上，这就是本政策的出发点。"
            ),
            LegalSection(
                heading: "一、保存在设备上的内容",
                body: "你录入的礼簿、收送记录、提醒日子、礼簿班子成员，以及来宾签名图片与语音祝福录音等内容，保存在这台设备中，用于记账、提醒、生成礼谱与回礼参考等功能。除下面第二节（iCloud 同步）与第三节（AI 功能）说明的情形外，这些内容不会离开你的设备。"
            ),
            LegalSection(
                heading: "二、iCloud 同步（可选）",
                body: "开启 iCloud 同步后，上述内容通过 Apple 的 iCloud 服务，在你自己的 Apple 账户下、在你自己的设备之间同步（CloudKit 私有数据库）。这些数据存放在你的 iCloud 空间里，我们无法查看、获取或使用。你可以在「我的 → 数据」中随时关闭同步；关闭后数据仅保存在本机。iCloud 对数据的处理同时适用 Apple 的隐私政策。"
            ),
            LegalSection(
                heading: "三、AI 功能（可选，默认关闭）",
                body: "礼记的智能解析、问账与谱序撰写由 DeepSeek 提供支持，属于可选功能：需要你先在「我的 → AI 智能助手」中启用，并填入你自己的 DeepSeek API Key。API Key 只保存在本机钥匙串（Keychain）中，不上传、不进备份。\n启用后，你主动提交给 AI 处理的文本（例如一句话记账的内容、接龙补录的原文、礼单识别出的文字、向问账提出的问题），会从你的设备直接发送到 DeepSeek 的服务器进行处理；撰写谱序时发送的是事由、日期、地点、主家姓名与到场人数，不含金额。这些发送不经过我们的服务器，我们不保存其中的内容。DeepSeek 对其收到数据的处理适用 DeepSeek 的隐私政策，请在使用前留意。不启用 AI 功能时，上述发送都不会发生，记账功能不受影响。"
            ),
            LegalSection(
                heading: "四、相机、照片与语音",
                body: "拍摄或选取礼单照片时，文字识别在本机完成（Apple Vision），照片本身不会上传。语音输入使用 Apple 的系统语音识别服务，语音数据的处理适用 Apple 的隐私政策。语音祝福录音仅保存在本机与你的 iCloud 中。"
            ),
            LegalSection(
                heading: "五、我们不做的事",
                body: "我们不收集使用行为分析数据，不投放广告，不使用广告标识符（IDFA），不接入第三方统计或广告 SDK，也不会出售你的任何数据。除你主动使用 AI 功能时的直连发送外，我们不向任何第三方共享你录入的内容。"
            ),
            LegalSection(
                heading: "六、备份文件",
                body: "你可以在「我的 → 数据」中导出 JSON 备份文件。备份文件由你自行保存与保管，它包含你的账目内容且未加密，请存放在你信任的位置；从备份恢复会覆盖设备上的现有数据，请在恢复前确认。"
            ),
            LegalSection(
                heading: "七、数据的删除",
                body: "你可以在 App 内删除礼簿与单条记录；被删内容会进入「最近删除」保留 30 天，期间可恢复，之后自动清除。卸载 App 会删除保存在本机的数据；已同步到 iCloud 的数据可在系统的 iCloud 设置中管理与删除。"
            ),
            LegalSection(
                heading: "八、本政策的更新与联系",
                body: "本政策更新时会在 App 内公布新版本，重大变更会以更明显的方式提示。对本政策有任何疑问，可通过「我的 → 关于 → 意见反馈」与我们联系。"
            ),
        ]
    )

    static let userAgreement = LegalDoc(
        title: "用户协议",
        effectiveLine: "生效日期：2026 年 11 月 · 运营主体：知和数智",
        sections: [
            LegalSection(
                heading: "一、服务说明",
                body: "礼记由知和数智提供，是一款记录亲友红白事人情往来的工具，提供礼簿记账、礼谱生成、往来统计、人情提醒，以及可选的 AI 辅助解析等功能。使用礼记即表示你已阅读并同意本协议。"
            ),
            LegalSection(
                heading: "二、你的数据归你",
                body: "你录入的全部内容归你所有，由你负责保管。建议开启 iCloud 同步或定期导出备份：因设备丢失、损坏、卸载应用等原因造成仅存在于本机的数据丢失的，我们无法为你恢复。导出的备份与礼谱文件由你自行保存、使用。"
            ),
            LegalSection(
                heading: "三、使用须知",
                body: "请勿利用礼记记录或传播违法内容，或从事任何违法活动。AI 生成与解析的结果——包括姓名、金额的识别与回礼建议——仅供参考，可能存在误差；内容保存前请核对，最终记账结果以你确认的内容为准。"
            ),
            LegalSection(
                heading: "四、费用",
                body: "礼记目前免费提供。若未来推出收费功能，我们会在购买前明确告知价格与内容，未经你主动确认不会产生任何费用。"
            ),
            LegalSection(
                heading: "五、权利归属",
                body: "礼记应用本身及其界面设计、文案等内容的权利归知和数智所有。你基于自有数据导出的礼谱、备份等文件，可由你自由保存与使用。"
            ),
            LegalSection(
                heading: "六、责任说明",
                body: "我们会尽力保持服务稳定可用，但因不可抗力，或 iCloud、DeepSeek 等第三方服务的变更与中断导致的使用影响，还请你理解；在法律允许的范围内，我们对上述情形不承担超出法律规定的责任。本协议未尽事宜，适用中华人民共和国相关法律法规。"
            ),
            LegalSection(
                heading: "七、协议的更新",
                body: "本协议更新时会在 App 内公布新版本；更新公布后你继续使用礼记，即视为接受更新后的协议。若你不接受更新内容，可以停止使用并卸载应用。"
            ),
        ]
    )
}

/// 法律文本页：分节正文、系统文本排版，支持选中复制，离线可读。
struct LegalView: View {
    let doc: LegalDoc

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingL) {
                Text(doc.effectiveLine)
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
                ForEach(doc.sections) { section in
                    VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
                        Text(section.heading)
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                            .lineSpacing(4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LiqianMetrics.spacingM)
            .textSelection(.enabled)
        }
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle(doc.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
