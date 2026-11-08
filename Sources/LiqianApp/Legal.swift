import SwiftUI
import LiqianDesign

/// 一节正文（标题在文档内唯一，兼作 ForEach 身份）。
/// body 是节首段落；items 是行式清单（每行一条，渲染时以细线分隔，
/// 承载 v2.0 的「信息—场景—目的」表格化清单，纯段落装不下这么多行）。
struct LegalSection: Identifiable {
    let heading: String
    let body: String
    var items: [String] = []
    var id: String { heading }
}

/// 一份法律文档：标题＋版本生效行＋文首摘要＋分节正文。纯内置文本、
/// 离线可读。v2.0（2026-11-08）按代码事实审计全面重写：文中每一项
/// 数据处理都与实际实现对得上（审计表见 docs/V531-NOTES.md），冲突时
/// 以本页为准。
struct LegalDoc {
    let title: String
    let effectiveLine: String
    let summary: String
    let sections: [LegalSection]
}

enum LegalTexts {
    static let privacyPolicy = LegalDoc(
        title: "隐私政策",
        effectiveLine: "版本 v2.0 · 生效日期：2026 年 11 月 16 日 · 运营者：知和数智",
        summary: "一句话先说清：礼记没有账号，也没有保存你账目的服务器。你的账目只存在你的设备和你自己的 iCloud 里；内容会离开设备的情形只有两种——你主动把礼簿共享给家人（经你的 iCloud），以及你自备密钥开启 AI 功能后，由你的设备直连 DeepSeek。",
        sections: [
            LegalSection(
                heading: "一、运营者与本政策的适用",
                body: "「礼记」由知和数智开发并运营，是一款记录亲友红白事人情往来的工具。本政策说明你在礼记中录入和产生的信息会被如何对待。礼记不设账号体系：你无需注册，打开即可记账，这决定了本政策的一个基本事实——我们没有服务器在收集、保存你的账目。"
            ),
            LegalSection(
                heading: "二、我们处理的信息与用途",
                body: "礼记处理的信息，全部是你主动录入或主动使用功能时产生的，仅用于实现对应功能：",
                items: [
                    "账目内容：你录入的礼簿（名称、场合、日期、地点）、收送记录（姓名、金额、关系、场合、收送方式、备注）与自定义关系——用于记账、往来统计、待回礼计算、提醒与礼谱生成。",
                    "现场内容：现场模式中来宾的手写签名图片与语音祝福录音——用于生成活礼谱；签名图片保存在本机数据中，录音以音频文件保存在本机，开启同步后随你的 iCloud 同步。",
                    "提醒与计划：你设置的场次日期与备礼计划——用于在本机生成提醒通知。",
                    "设置与偏好：主题、礼谱落款姓名、AI 开关等设置项——只保存在本机。",
                    "DeepSeek API Key：你自行申请的密钥，只保存在本机钥匙串（Keychain）中，不进入备份文件、不随 iCloud 同步，我们无法获取。",
                ]
            ),
            LegalSection(
                heading: "三、我们不收集的信息",
                body: "我们不收集你的通讯录、位置、设备标识符与广告标识符（IDFA）；不记录你的使用行为用于分析或画像；不投放广告。礼记不接入任何第三方统计、广告或崩溃上报服务，应用本身也不包含任何第三方 SDK。"
            ),
            LegalSection(
                heading: "四、系统权限调用说明",
                body: "以下权限只在你用到对应功能时才会申请，拒绝任何一项都只影响该功能，可随时在 iOS 系统设置中开启或关闭：",
                items: [
                    "相机：拍摄纸质礼单做文字识别。拒绝后可改用相册选图或手动录入。",
                    "照片（系统选择器）：选取已有的礼单照片。通过 iOS 系统照片选择器逐张选取，礼记无法访问你的整个相册。",
                    "麦克风：语音记账、录制语音祝福。拒绝后可使用文字输入。",
                    "语音识别：把语音转成记账文字。语音记账的实时转写使用 iOS 的本机语音识别（SpeechAnalyzer），全程在你的设备上完成，录音音频不会离开设备；语音祝福的转写同样只在本机进行。转出的文字如用于一句话记账、问账等 AI 功能，按第七节处理，音频本身不发送。拒绝后可使用文字输入。",
                    "通知：在你设置的日期以本地通知做人情提醒与备份提醒，全部通知都在本机排定，不经过任何服务器。拒绝后 App 内仍可查看，只是不再弹出提醒。",
                    "Face ID（或设备密码）：仅当你开启隐私锁时，在本机调用系统验证解锁；礼记不接触、不保存你的生物识别信息。未开启隐私锁时不会调用。",
                    "实时活动与小组件：现场模式可在锁屏显示本场收礼进度，小组件可在桌面与锁屏显示待回摘要；为此在本机存放的一份精简摘要（待回人数与金额、靠前的待回姓名、下一场提醒）只供你设备上的小组件读取，不会发送到任何服务器。",
                ]
            ),
            LegalSection(
                heading: "五、存储地点与保存期限",
                body: "默认情况下，全部数据只保存在你的设备上（本机的 SwiftData 数据库与 App 文件区）。开启 iCloud 同步后，数据会同步到你 Apple 账户下的 iCloud 私有数据库（CloudKit），我们没有自有服务器，也无法访问或查看你的 iCloud 数据；你可以在「我的 → 数据」中随时关闭同步，关闭后仅保存在本机。\n保存期限由你决定：删除的礼簿与记录会先进入「最近删除」保留 30 天，期间可恢复，期满自动彻底删除；卸载 App 会删除保存在本机的数据，已同步到 iCloud 的副本可在 iOS 系统设置的 iCloud 中管理与删除。"
            ),
            LegalSection(
                heading: "六、对外提供与第三方清单",
                body: "除下列两项外，我们不向任何第三方提供你的信息，也不出售任何数据。应用内购买由 Apple 处理支付，我们不接触你的支付信息。",
                items: [
                    "Apple（iCloud / CloudKit）：当你开启同步或使用家族共享时，数据存储与传输经由你的 Apple 账户完成，其处理适用 Apple 的隐私政策。",
                    "DeepSeek（深度求索）：仅在你启用 AI 功能并填入自己的 API Key 后发生。请求由你的设备经加密连接直达 DeepSeek 的接口，费用计入你的 DeepSeek 账户，其对收到数据的处理适用 DeepSeek 的隐私政策。具体发送内容见第七节。",
                ]
            ),
            LegalSection(
                heading: "七、AI 功能会发送什么",
                body: "AI 功能（界面中称「AI 管家」）默认关闭。以下发送只在 AI 已启用、且你主动触发相应功能时发生，全部由你的设备直接发送至 DeepSeek，不经过我们的服务器，我们不在服务器侧保存这些内容。不启用 AI 功能时，以下发送都不会发生，记账等基础功能不受影响：",
                items: [
                    "问账：你输入的问题文字；以及为回答该问题、由 App 在本机按需查到的账目结果（例如某人的往来汇总、某段时间的统计），仅限回答该问题所需的部分。",
                    "一句话记账与批量补录：你输入或粘贴的记账文字原文。",
                    "拍礼簿的 AI 增强：照片先在本机完成文字识别（Apple Vision），发送的只是识别出的文字，照片本身不发送。",
                    "贺词生成：场合与礼簿名称、你填写的主家姓名与关系、你选择的口吻。",
                    "礼谱谱序：事由、干支日期、地点、主家姓名与到场人数——不包含任何金额与来宾名单。",
                    "Key 验证：你保存或手动验证 API Key 时，会发送一次极小的测试请求，以确认 Key 是否可用。",
                ]
            ),
            LegalSection(
                heading: "八、家族协作（共享礼簿）",
                body: "你可以通过 iCloud 把某本礼簿共享给受邀的家人或礼簿班子成员。被共享礼簿中的记录（包括姓名与金额）将对受邀成员可见，成员可按你在礼簿中设定的角色查看或协助记录。共享的发起、成员管理与取消均由你在 App 内或系统共享设置中完成，数据经你的 iCloud 传递，我们无法查看共享内容。请只邀请你信任的人，并确认对方知晓其将看到该礼簿的内容。"
            ),
            LegalSection(
                heading: "九、你的权利与行使方式",
                body: "你的账目数据归你所有。下列权利都可直接在 App 内行使，无需向我们提出申请：",
                items: [
                    "查阅与复制：直接在 App 各页面查看；或在「我的 → 数据」导出 JSON 备份（礼记 Pro 可另行导出 CSV 表格）。",
                    "更正：礼簿与每条记录都可在 App 内编辑修改。",
                    "删除：可删除单条记录或整本礼簿；误删的内容可在 30 天内从「最近删除」恢复，期满自动彻底删除。",
                    "导出与转移：导出的备份文件由你自行保存，可在新设备上恢复导入；礼记不锁定你的数据。",
                    "撤回同意：在 iOS 系统设置中关闭已授予的权限；在「我的 → AI 管家」中关闭 AI 功能或删除 API Key，即停止一切 AI 发送；在「我的 → 数据」中关闭 iCloud 同步，即停止同步。",
                    "彻底删除：礼记没有账号，不设注销流程；删除 App 并在 iOS 系统设置中清除 iCloud 内的礼记数据，即完成全部删除。",
                ]
            ),
            LegalSection(
                heading: "十、未成年人",
                body: "礼记是面向成年人的人情往来记账工具。未成年人应在监护人的指导下使用；监护人若发现未成年人的信息被录入，可直接在 App 内删除，或通过第十三节的联系方式与我们联系处理。"
            ),
            LegalSection(
                heading: "十一、我们如何保护信息",
                body: "账目数据只保存在你的设备与你自己的 iCloud 账户中；AI 请求全程使用加密连接（HTTPS）由你的设备直连 DeepSeek；API Key 存放在 iOS 钥匙串中；你还可以开启隐私锁，用 Face ID 或设备密码保护本机数据。需要提醒的是：你导出的 JSON 备份文件未做加密、包含完整账目，请存放在你信任的位置。"
            ),
            LegalSection(
                heading: "十二、本政策的更新",
                body: "本政策每次更新都会在本页顶部标注新的版本号与生效日期，并在 App 内公布；涉及数据处理方式的重大变更，我们会在 App 内以更明显的方式提示。更新生效后你继续使用礼记，即表示你已了解更新后的政策；若你不接受更新内容，可以停止使用并卸载应用。"
            ),
            LegalSection(
                heading: "十三、联系我们",
                body: "对本政策或你的信息处理有任何疑问，可发送邮件至 inkroot001@gmail.com，或通过「我的 → 关于 → 意见反馈」与我们联系，我们会尽快答复。"
            ),
        ]
    )

    static let userAgreement = LegalDoc(
        title: "用户协议",
        effectiveLine: "版本 v2.0 · 生效日期：2026 年 11 月 16 日 · 运营者：知和数智",
        summary: "一句话先说清：礼记无需注册账号即可使用；你录入的账目永远归你所有、可自由导出；礼记 Pro 是一次性买断、不是订阅；AI 与装订成书是可选项，用与不用都不影响记账。",
        sections: [
            LegalSection(
                heading: "一、服务说明",
                body: "礼记由知和数智开发运营，是一款记录亲友红白事人情往来的工具，提供礼簿记账、往来统计、人情提醒、礼谱生成，以及可选的 AI 辅助与装订成书服务。使用礼记即表示你已阅读并同意本协议与《隐私政策》。"
            ),
            LegalSection(
                heading: "二、无需账号与数据归属",
                body: "礼记不设账号体系，你无需注册即可使用。你的数据保存在你的设备上，以及你选择开启同步时你自己的 iCloud 账户中。你录入的全部内容归你所有，你可自由导出、备份，并自由使用导出的礼谱与备份文件。因设备丢失、损坏、卸载应用等原因造成仅存在于本机的数据丢失的，我们无法为你恢复，建议开启 iCloud 同步或定期导出备份。"
            ),
            LegalSection(
                heading: "三、免费功能与礼记 Pro（买断会员）",
                body: "礼记的基础功能免费提供。礼记 Pro 为一次性买断，不是订阅，不会自动续费，购买后在你的 Apple 账户下长期有效。Pro 的具体权益以购买时 App 内付费墙页面列明为准，目前包括 CSV 导出、纪念版礼谱、家族汇册与印刷版礼谱导出。价格以 App Store 在购买时显示的价格为准，支付与退款均由 Apple 按其政策处理；如需退款，请按 Apple 的规则向 Apple 申请。你可以在 App 内通过「恢复购买」找回已购权益。我们可能随版本更新调整尚未购买的功能划分，但已完成买断的用户的已购权益，不会因版本更新被取消。"
            ),
            LegalSection(
                heading: "四、AI 功能条款",
                body: "AI 功能（问账、一句话解析、贺词与谱序撰写等，统称「AI 管家」）由第三方 DeepSeek 提供模型服务，属于可选功能、默认关闭；使用前需你自行申请 DeepSeek API Key 并承担相应费用，请求由你的设备直连 DeepSeek，不经过我们的服务器。AI 的解析与生成结果——包括姓名与金额的识别、问账答复与回礼建议——仅供参考，可能存在误差；内容保存前请核对，你的账目金额与往来差额永远以 App 本地账目为准。AI 功能的可用性受 DeepSeek 服务状态影响。"
            ),
            LegalSection(
                heading: "五、装订成书服务（内测）",
                body: "装订成书是礼记处于内测阶段的实体礼谱印制服务，现阶段由人工沟通与履约：你在 App 内登记意向后，我们会通过你留下的联系方式，与你确认礼谱内容、装订规格与最终价格，你确认价格并完成付款后，我们才开始制作。App 内成书说明页标注的参考价格（299–399 元）与预计周期（约 10 天）仅供预估，以双方最终确认为准。礼谱系按你的专属内容定制印制，依法不适用七日无理由退货；如印品存在质量问题或与双方确认的规格明显不符，我们负责免费重印或退款。预计交付周期以确认时告知为准，如将延误，我们会提前与你沟通。"
            ),
            LegalSection(
                heading: "六、使用须知",
                body: "你应对自己录入内容的真实性与合法性负责。录入亲友姓名、金额等信息时，请确保具有正当的人情往来记录事由；通过家族协作共享礼簿时，请确认受邀人知晓并同意查看该礼簿内容。请勿利用礼记从事违法活动、记录或传播违法内容，或干扰本服务的正常运行。"
            ),
            LegalSection(
                heading: "七、知识产权",
                body: "礼记应用软件及其界面设计、文案、礼谱版式与模板等内容的知识产权归知和数智所有，未经许可不得复制、反向工程或用于商业转售。你基于自有数据导出的礼谱、备份与表格文件归你自由保存与使用；你通过 AI 功能生成、并用于自身礼谱与贺卡的贺词与谱序文本，可自由使用。"
            ),
            LegalSection(
                heading: "八、服务变更与中断",
                body: "我们会尽力保持服务稳定。本地记账等核心功能不依赖网络；iCloud 同步、App Store 购买与 DeepSeek 等第三方服务的可用性由相应提供方决定，其变更或中断可能影响对应的可选功能。因不可抗力导致的服务中断，还请你理解。"
            ),
            LegalSection(
                heading: "九、责任限制",
                body: "在法律允许的范围内，对于因第三方服务的变更或中断、你的设备或账户保管不当、未备份造成的数据丢失等情形，我们不承担超出法律规定的责任；本条不排除依法不得排除的责任。本协议未尽事宜，适用中华人民共和国相关法律法规。"
            ),
            LegalSection(
                heading: "十、协议的更新",
                body: "本协议更新时会在 App 内公布新版本，并在页面顶部标注版本号与生效日期。更新公布后你继续使用礼记，即视为接受更新后的协议；若你不接受更新内容，可以停止使用并卸载应用，你已导出的数据不受影响。"
            ),
            LegalSection(
                heading: "十一、法律适用与争议解决",
                body: "本协议的订立、履行与解释适用中华人民共和国法律。因本协议产生的争议，双方应先友好协商解决；协商不成的，任一方可向知和数智所在地有管辖权的人民法院提起诉讼。"
            ),
            LegalSection(
                heading: "十二、联系我们",
                body: "对本协议有任何疑问，可发送邮件至 inkroot001@gmail.com，或通过「我的 → 关于 → 意见反馈」与我们联系。"
            ),
        ]
    )
}

/// 法律文本页：文首摘要＋分节正文＋行式清单，系统文本排版，支持选中
/// 复制，离线可读。清单行以细线分隔逐行呈现（v2.0 结构扩展，见
/// LegalSection.items），没有清单的节与旧版渲染一致。
struct LegalView: View {
    let doc: LegalDoc

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingL) {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
                    Text(doc.effectiveLine)
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                    Text(doc.summary)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(4)
                }
                ForEach(doc.sections) { section in
                    VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
                        Text(section.heading)
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        if !section.body.isEmpty {
                            Text(section.body)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                                .lineSpacing(4)
                        }
                        if !section.items.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(section.items.enumerated()), id: \.offset) { index, item in
                                    if index > 0 {
                                        Divider()
                                    }
                                    Text(item)
                                        .font(.body)
                                        .foregroundStyle(Palette.ink)
                                        .lineSpacing(4)
                                        .padding(.vertical, LiqianMetrics.spacingS)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
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
