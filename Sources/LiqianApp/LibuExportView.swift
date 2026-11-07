import SwiftUI
import SwiftData
import PDFKit
import StoreKit
import LiqianCore
import LiqianDesign

/// 礼谱导出 sheet（v2.10 两步式）：选谱序文体 →「生成预览」在本 sheet 内
/// 整谱翻页预览 → 底部「分享 / 保存」才调系统分享。生成失败在预览区红字明示。
/// 谱序来源：选了文体且 AI 就绪时走 DeepSeek；不可用或生成失败自动回退内置模板，
/// 不阻塞导出。
/// 主家/书记/核实人/地点是礼簿自身属性（在礼簿表单里设），导出直接读礼簿，
/// 本 sheet 不再出现这些字段；主家为空时的回退链在 GiftBookPDF 内
/// （礼簿主家 → 全局「礼谱落款姓名」设置 →「主家」字面）。
struct LibuExportView: View {
    let ledger: Ledger
    let records: [GiftRecord]
    /// 活礼谱（v4.2）：本簿签名与成册口径内记录的祝福，由详情页透传；
    /// 默认空——为空时生成的谱与旧版逐页一致。
    var signatures: [GuestSignature] = []
    var blessings: [VoiceBlessing] = []

    @Environment(\.dismiss) private var dismiss
    /// 评分引导（v4.5）：只在礼谱生成成功后、且 ReviewPrompt 条件齐备时请求
    @Environment(\.requestReview) private var requestReview
    /// 全 App 记录/礼簿（只为评分引导算累计真实记录数，排除示例账本）
    @Query private var allRecords: [GiftRecord]
    @Query private var allLedgers: [Ledger]

    @State private var style: LibuPrefaceStyle = .wenyan
    @State private var generating = false
    @State private var pdfURL: URL?
    @State private var errorText: String?
    @State private var fallbackNote: String?
    /// 导出生成成功/失败的触感（v4.4）：此前生成完只有画面变化，无反馈
    @State private var exportTrigger = 0
    @State private var exportErrorTrigger = 0

    private var isBai: Bool { ledger.isBai }

    /// 到场亲友数：成册口径（排除待送出）后的 distinct 人数，与谱内汇总一致
    private var guestCount: Int {
        Set(records.filter { !$0.isPendingSend }.map(\.person)).count
    }

    var body: some View {
        NavigationStack {
            List {
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
                        PDFPreviewView(url: pdfURL)
                            .frame(height: 480)
                            .listRowInsets(EdgeInsets())
                        if let fallbackNote {
                            Text(fallbackNote)
                                .font(.footnote)
                                .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                        }
                        Button("重新生成预览") { generate() }
                    } else {
                        Button {
                            generate()
                        } label: {
                            Text("生成预览")
                                .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                        }
                        if let errorText {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(Palette.danger)
                        }
                    }
                } header: {
                    Text("预览")
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
            // v5 设计一期：行动条迁 safeAreaBar，分享钮改玻璃主按钮
            // （Mat.tinted），撤掉旧 ultraThinMaterial 底板——玻璃纪律
            // 「二选一」取玻璃钮＋系统滚动边缘，不再手搭材质底。
            .safeAreaBar(edge: .bottom) {
                if let pdfURL, !generating {
                    ShareLink(item: pdfURL) {
                        Label("分享 / 保存礼谱", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                    }
                    .liqianGlassButton(.tinted)
                    .padding(.horizontal, LiqianMetrics.spacingL)
                    .padding(.vertical, LiqianMetrics.spacingSM)
                }
            }
            .onChange(of: style) {
                // 文体变了，旧预览作废，免得分享出去的和选的不一致
                pdfURL = nil
                errorText = nil
                fallbackNote = nil
            }
            .sensoryFeedback(.success, trigger: exportTrigger)
            .sensoryFeedback(.warning, trigger: exportErrorTrigger)
        }
    }

    private var styleNote: String {
        switch style {
        case .none:
            return "不要谱序页：封面之后直接是宾客内页。"
        case .wenyan, .baihua:
            if AIAccess.readiness() == .ready {
                return "用你启用的 AI（DeepSeek）现写一篇，只给它事由、日期、地点、主家名和人数，不给金额。"
            }
            return "AI 还没启用，会用内置的典雅模板成序（到「我的 → AI 智能助手」启用后可现写）。"
        }
    }

    private func generate() {
        generating = true
        errorText = nil
        fallbackNote = nil
        pdfURL = nil
        let chosenStyle = style
        let guests = guestCount
        // 主家与地点都读礼簿属性。谱序里的主家名走与 GiftBookPDF 落款相同的
        // 回退链（礼簿主家 → 全局「礼谱落款姓名」设置 → 模板内回退「主家」），
        // 保证谱序落款与封面/汇总落款是同一个人。
        let ledgerHost = (ledger.hostName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let host = ledgerHost.isEmpty
            ? (UserDefaults.standard.string(forKey: "hostName") ?? "")
            : ledgerHost
        let location = (ledger.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            var preface: String? = nil
            if chosenStyle != .none {
                let resolved = await LibuPreface.resolve(
                    type: ledger.type, date: ledger.date, style: chosenStyle,
                    hostName: host, guestCount: guests, location: location
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
                prefaceText: preface,
                signatures: signatures, blessings: blessings
            )
            generating = false
            if let url {
                pdfURL = url
                exportTrigger += 1
                maybeRequestReview()
            } else {
                errorText = "礼谱生成失败，请重试。"
                exportErrorTrigger += 1
            }
        }
    }

    /// 评分引导（v4.5）：礼谱生成成功是本 App 最明确的正向时刻。
    /// 条件（累计真实记录 ≥20 笔、距上次请求 ≥120 天）都在 ReviewPrompt 里，
    /// 不满足就完全沉默；先记时再请求，避免同一次成功重复触发。
    /// 延迟 1.2 秒等预览与成功震动先落地，弹窗不抢第一眼。
    /// 失败路径（上方 else）永远不走到这里。
    private func maybeRequestReview() {
        let sampleIDs = SampleData.sampleIDs(ledgers: allLedgers)
        let total = allRecords.filter { !sampleIDs.contains($0.ledgerID) }.count
        guard ReviewPrompt.shouldRequest(totalRecords: total) else { return }
        ReviewPrompt.markRequested()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            requestReview()
        }
    }
}

/// PDFKit 整谱预览（sheet 内翻页看全谱，确认无误再分享）
private struct PDFPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
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

/// 谱序来源：AI 优先（素材只给事由/干支日期/地点/主家名/人数，绝不给金额），
/// 不就绪或失败回退内置模板，永不阻塞导出。
enum LibuPreface {
    struct Resolved {
        let text: String
        let usedTemplate: Bool
        let note: String?
    }

    static func resolve(
        type: String, date: String, style: LibuPrefaceStyle,
        hostName: String, guestCount: Int, location: String = ""
    ) async -> Resolved {
        if AIAccess.readiness() == .ready, let client = try? DeepSeekClient() {
            do {
                let raw = try await client.chatText(
                    system: aiSystemPrompt(
                        type: type, date: date, style: style,
                        hostName: hostName, guestCount: guestCount, location: location
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
                text: template(type: type, date: date, hostName: hostName, guestCount: guestCount, location: location),
                usedTemplate: true,
                note: "AI 这次没写成，谱序用了内置模板，礼谱本身不受影响。"
            )
        }
        return Resolved(
            text: template(type: type, date: date, hostName: hostName, guestCount: guestCount, location: location),
            usedTemplate: true,
            note: nil
        )
    }

    /// AI 撰序提示（规范原文口径）：只写正文、不要标题不要落款，不编造人名事件，不提金额
    static func aiSystemPrompt(
        type: String, date: String, style: LibuPrefaceStyle,
        hostName: String, guestCount: Int, location: String = ""
    ) -> String {
        let styleText = style == .wenyan
            ? "用浅近文言、典雅凝练"
            : "用庄重白话、真挚不煽情"
        let host = hostName.isEmpty ? "主家" : hostName
        let place = location.isEmpty ? "" : "，举办地点\(location)"
        return "你是家族礼谱的撰序人。为一场\(type)撰写礼谱序，\(styleText)，"
            + "150–250 字，只写正文不要标题不要落款（落款由程序加），"
            + "素材：主家\(host)，日期\(LiqianDate.ganzhiFullDate(for: date))\(place)，"
            + "到场亲友共 \(guestCount) 人。"
            + "不得编造具体人名与事件细节，不得提及金额。"
    }

    /// 内置模板谱序（文言体，按事由六篇；白事克制）。变量：主家名、干支全日期、到场人数、地点。
    /// v2.8：模板是写死的固定文本，随礼谱固定文字口径换繁体版；变量
    /// （主家名＝用户数据、干支日期、地点原文、人數）照旧插值，其中干支日期只做生成串
    /// 字形映射（LibuText），主家名与地点严禁转换。AI 谱序正文不经此处、不转换。
    /// 地点非空时以「於＋地点」缀在岁在句后（v2.10）。
    static func template(type: String, date: String, hostName: String, guestCount: Int, location: String = "") -> String {
        let host = hostName.isEmpty ? "主家" : hostName
        let gz = LibuText.traditionalGenerated(LiqianDate.ganzhiFullDate(for: date))
        let place = location.isEmpty ? "" : "於\(location)，"
        switch type {
        case "婚礼":
            return "歲在\(gz)，\(place)\(host)之府，佳兒淑女，結縭於斯。是日高朋滿座，親眷雲集，"
                + "到場者凡\(guestCount)人，笙歌起於堂前，笑語聞於巷陌。遠者千里而至，近者比鄰而來，"
                + "所贈非物，皆一片心也。謹列芳名於左，誌厚誼於右，彙成此譜。"
                + "異日展卷，猶憶今朝；傳之子孫，永念斯情。"
        case "寿宴":
            return "歲在\(gz)，\(place)\(host)為親設宴，祝壽於堂。到場親友凡\(guestCount)人，"
                + "兒孫繞膝，故舊登門，或攜酒，或捧桃，言笑晏晏，共慶長者之福。"
                + "人生之樂，莫過於骨肉團圓、親朋無恙。謹列芳名，彙成此譜。"
                + "他年展讀之時，福澤綿長之象，宛然在目。"
        case "乔迁":
            return "歲在\(gz)，\(place)\(host)喬遷新居，燕賀之賓凡\(guestCount)人，盈於門庭。"
                + "棟宇初成，親朋咸集，置酒高堂，共話家常。新居之喜，不在廣廈，"
                + "而在故人皆至、笑語如舊。謹列芳名，彙成此譜，以誌今日之聚，以念平生之誼。"
        case "满月", "周岁":
            return "歲在\(gz)，\(place)\(host)家中新添稚子，親朋聞訊，咸來道賀，"
                + "是日到場者凡\(guestCount)人。襁褓小兒，未知人間之誼，"
                + "而滿堂賓客，皆他日護持之念。謹列芳名，彙成此譜。"
                + "待兒長成，展卷而讀，當知自家根系之深、人情之厚。"
        case "升学", "开业":
            return "歲在\(gz)，\(place)\(host)之府，鵬程初展，新程方啟，"
                + "登門道賀者凡\(guestCount)人，絡繹於途。所賀者非一時之成，所期者乃長遠之業；"
                + "所記者非簿上之數，乃平生之扶持。謹列芳名，彙成此譜。他年回首來路，皆見於此。"
        case LiqianConstants.baiType:
            return "歲在\(gz)，\(place)\(host)家中有故，親朋聞訃，咸來弔唁，"
                + "執紼登堂者凡\(guestCount)人。生者之慟，賴故舊之慰而稍解；"
                + "逝者之名，因眾人之念而不朽。扶柩送行、登堂行禮者，皆平生之厚誼也。"
                + "謹列芳名，彙成此譜，以誌哀思，以謝親朋。"
        default:
            return "歲在\(gz)，\(place)\(host)之府有喜，親朋咸集，到場者凡\(guestCount)人。"
                + "遠者跋涉而至，近者比鄰而來，所贈非物，皆一片心也。"
                + "謹列芳名於左，誌厚誼於右，彙成此譜。異日展卷，猶憶今朝；傳之子孫，永念斯情。"
        }
    }
}
