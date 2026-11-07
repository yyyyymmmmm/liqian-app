import SwiftUI
import LiqianCore
import LiqianDesign

/// 礼谱导出 sheet（v3）：确认落款姓名 → 选谱序文体 → 生成礼谱（封面/谱序/内页/汇总）。
/// 谱序来源：选了文体且 AI 就绪时走 DeepSeek；不可用或生成失败自动回退内置模板，
/// 不阻塞导出。落款姓名与「我的 → 礼谱落款姓名」共用同一 @AppStorage 键。
struct LibuExportView: View {
    let ledger: Ledger
    let records: [GiftRecord]

    @AppStorage("hostName") private var storedHostName = ""
    @Environment(\.dismiss) private var dismiss

    @State private var nameText = ""
    @State private var style: LibuPrefaceStyle = .wenyan
    @State private var generating = false
    @State private var pdfURL: URL?
    @State private var errorText: String?
    @State private var fallbackNote: String?

    private var isBai: Bool { ledger.isBai }

    /// 到场亲友数：成册口径（排除待送出）后的 distinct 人数，与谱内汇总一致
    private var guestCount: Int {
        Set(records.filter { !$0.isPendingSend }.map(\.person)).count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("主家姓名，如：杨敏杰", text: $nameText)
                        .font(.body)
                    Text("封面落款、谱序落款和主家印都用这个名字；不填就用「主家谨识」。")
                        .font(.footnote)
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                } header: {
                    Text("落款姓名")
                }

                Section {
                    Picker("谱序文体", selection: $style) {
                        ForEach(LibuPrefaceStyle.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(styleNote)
                        .font(.footnote)
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                } header: {
                    Text("谱序")
                }

                Section {
                    if generating {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            ProgressView()
                            Text("正在成谱…")
                                .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                    } else if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("分享 / 保存礼谱 PDF", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                        }
                        if let fallbackNote {
                            Text(fallbackNote)
                                .font(.footnote)
                                .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                        }
                        Button("重新生成") { generate() }
                    } else {
                        Button {
                            generate()
                        } label: {
                            Text("生成礼谱")
                                .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                        }
                        if let errorText {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(isBai ? Palette.baiPrimary : Palette.primary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("导出礼谱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                if nameText.isEmpty { nameText = storedHostName }
            }
        }
    }

    private var styleNote: String {
        switch style {
        case .none:
            return "不要谱序页：封面之后直接是宾客内页。"
        case .wenyan, .baihua:
            if AIAccess.readiness() == .ready {
                return "用你启用的 AI（DeepSeek）现写一篇，只给它事由、日期、主家名和人数，不给金额。"
            }
            return "AI 还没启用，会用内置的典雅模板成序（到「我的 → AI 智能助手」启用后可现写）。"
        }
    }

    private func generate() {
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        storedHostName = name
        generating = true
        errorText = nil
        fallbackNote = nil
        pdfURL = nil
        let chosenStyle = style
        let guests = guestCount
        Task {
            var preface: String? = nil
            if chosenStyle != .none {
                let resolved = await LibuPreface.resolve(
                    type: ledger.type, date: ledger.date, style: chosenStyle,
                    hostName: name, guestCount: guests
                )
                preface = resolved.text
                if resolved.usedTemplate {
                    fallbackNote = resolved.note
                }
            } else {
                // 没有 AI 调用时让 ProgressView 先转起来再渲染
                await Task.yield()
            }
            let url = GiftBookPDF.makePDF(
                ledger: ledger, records: records,
                hostName: name, prefaceText: preface
            )
            generating = false
            if let url {
                pdfURL = url
            } else {
                errorText = "礼谱生成失败，请重试。"
            }
        }
    }
}

/// 谱序文体
enum LibuPrefaceStyle: String, CaseIterable, Identifiable {
    case wenyan
    case baihua
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wenyan: return "文言"
        case .baihua: return "白话"
        case .none: return "不用"
        }
    }
}

/// 谱序来源：AI 优先（素材只给事由/干支日期/主家名/人数，绝不给金额），
/// 不就绪或失败回退内置模板，永不阻塞导出。
enum LibuPreface {
    struct Resolved {
        let text: String
        let usedTemplate: Bool
        let note: String?
    }

    static func resolve(
        type: String, date: String, style: LibuPrefaceStyle,
        hostName: String, guestCount: Int
    ) async -> Resolved {
        if AIAccess.readiness() == .ready, let client = try? DeepSeekClient() {
            do {
                let raw = try await client.chatText(
                    system: aiSystemPrompt(
                        type: type, date: date, style: style,
                        hostName: hostName, guestCount: guestCount
                    ),
                    user: "请按要求撰写这篇礼谱序。"
                )
                let cleaned = raw.filter { !$0.isWhitespace }
                if cleaned.count >= 40 {
                    return Resolved(text: cleaned, usedTemplate: false, note: nil)
                }
            } catch {
                // 落到模板回退
            }
            return Resolved(
                text: template(type: type, date: date, hostName: hostName, guestCount: guestCount),
                usedTemplate: true,
                note: "AI 这次没写成，谱序用了内置模板，礼谱本身不受影响。"
            )
        }
        return Resolved(
            text: template(type: type, date: date, hostName: hostName, guestCount: guestCount),
            usedTemplate: true,
            note: nil
        )
    }

    /// AI 撰序提示（规范原文口径）：只写正文、不要标题不要落款，不编造人名事件，不提金额
    static func aiSystemPrompt(
        type: String, date: String, style: LibuPrefaceStyle,
        hostName: String, guestCount: Int
    ) -> String {
        let styleText = style == .wenyan
            ? "用浅近文言、典雅凝练"
            : "用庄重白话、真挚不煽情"
        let host = hostName.isEmpty ? "主家" : hostName
        return "你是家族礼谱的撰序人。为一场\(type)撰写礼谱序，\(styleText)，"
            + "150–250 字，只写正文不要标题不要落款（落款由程序加），"
            + "素材：主家\(host)，日期\(LiqianDate.ganzhiFullDate(for: date))，"
            + "到场亲友共 \(guestCount) 人。"
            + "不得编造具体人名与事件细节，不得提及金额。"
    }

    /// 内置模板谱序（文言体，按事由六篇；白事克制）。变量：主家名、干支全日期、到场人数。
    /// v2.8：模板是写死的固定文本，随礼谱固定文字口径换繁体版；三个变量
    /// （主家名＝用户数据、干支日期、人數）照旧插值，其中干支日期只做生成串
    /// 字形映射（LibuText），主家名严禁转换。AI 谱序正文不经此处、不转换。
    static func template(type: String, date: String, hostName: String, guestCount: Int) -> String {
        let host = hostName.isEmpty ? "主家" : hostName
        let gz = LibuText.traditionalGenerated(LiqianDate.ganzhiFullDate(for: date))
        switch type {
        case "婚礼":
            return "歲在\(gz)，\(host)之府，佳兒淑女，結縭於斯。是日高朋滿座，親眷雲集，"
                + "到場者凡\(guestCount)人，笙歌起於堂前，笑語聞於巷陌。遠者千里而至，近者比鄰而來，"
                + "所贈非物，皆一片心也。謹列芳名於左，誌厚誼於右，彙成此譜。"
                + "異日展卷，猶憶今朝；傳之子孫，永念斯情。"
        case "寿宴":
            return "歲在\(gz)，\(host)為親設宴，祝壽於堂。到場親友凡\(guestCount)人，"
                + "兒孫繞膝，故舊登門，或攜酒，或捧桃，言笑晏晏，共慶長者之福。"
                + "人生之樂，莫過於骨肉團圓、親朋無恙。謹列芳名，彙成此譜。"
                + "他年展讀之時，福澤綿長之象，宛然在目。"
        case "乔迁":
            return "歲在\(gz)，\(host)喬遷新居，燕賀之賓凡\(guestCount)人，盈於門庭。"
                + "棟宇初成，親朋咸集，置酒高堂，共話家常。新居之喜，不在廣廈，"
                + "而在故人皆至、笑語如舊。謹列芳名，彙成此譜，以誌今日之聚，以念平生之誼。"
        case "满月", "周岁":
            return "歲在\(gz)，\(host)家中新添稚子，親朋聞訊，咸來道賀，"
                + "是日到場者凡\(guestCount)人。襁褓小兒，未知人間之誼，"
                + "而滿堂賓客，皆他日護持之念。謹列芳名，彙成此譜。"
                + "待兒長成，展卷而讀，當知自家根系之深、人情之厚。"
        case "升学", "开业":
            return "歲在\(gz)，\(host)之府，鵬程初展，新程方啟，"
                + "登門道賀者凡\(guestCount)人，絡繹於途。所賀者非一時之成，所期者乃長遠之業；"
                + "所記者非簿上之數，乃平生之扶持。謹列芳名，彙成此譜。他年回首來路，皆見於此。"
        case LiqianConstants.baiType:
            return "歲在\(gz)，\(host)家中有故，親朋聞訃，咸來弔唁，"
                + "執紼登堂者凡\(guestCount)人。生者之慟，賴故舊之慰而稍解；"
                + "逝者之名，因眾人之念而不朽。扶柩送行、登堂行禮者，皆平生之厚誼也。"
                + "謹列芳名，彙成此譜，以誌哀思，以謝親朋。"
        default:
            return "歲在\(gz)，\(host)之府有喜，親朋咸集，到場者凡\(guestCount)人。"
                + "遠者跋涉而至，近者比鄰而來，所贈非物，皆一片心也。"
                + "謹列芳名於左，誌厚誼於右，彙成此譜。異日展卷，猶憶今朝；傳之子孫，永念斯情。"
        }
    }
}
