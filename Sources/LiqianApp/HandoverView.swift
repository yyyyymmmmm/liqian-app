import SwiftUI
import PDFKit
import UIKit
import LiqianCore
import LiqianDesign

/// 礼簿交接与纪念版（v4.5 传承）：都不依赖 iCloud，本地可用。
/// - 传承包：一本礼簿的完整备份（复用全量备份格式的单簿切片：礼簿＋记录＋
///   班子＋该簿相关的提醒无关，故不含 reminders 段）＋一页交接说明 PDF，
///   接收方在「我的 → 数据 → 从备份恢复」或后续的单簿导入里接手；
/// - 纪念版礼谱：复用 GiftBookPDF，封面带「紀念」题签，只读导出物，
///   给长辈留存/打印装订用，不回流到记账数据。
struct HandoverView: View {
    let ledger: Ledger
    let records: [GiftRecord]
    let members: [LedgerMember]

    /// Pro 权益单点（v5）：纪念版礼谱是门控面，传承包本身保持免费
    @EnvironmentObject private var entitlements: EntitlementCenter
    @State private var showPaywall = false
    @State private var packageURL: URL?
    @State private var noteURL: URL?
    @State private var memorialURL: URL?
    @State private var generating = false
    @State private var errorText: String?
    /// 生成成功/失败触感（v4.4，与礼谱导出口径一致）
    @State private var generateTrigger = 0
    @State private var generateErrorTrigger = 0

    /// 成册口径：排除待送出（与礼谱、统计一致）
    private var counted: [GiftRecord] { records.filter { !$0.isPendingSend } }

    private var receivedRecords: [GiftRecord] {
        counted.filter { $0.direction == LiqianConstants.received }
    }

    private var givenRecords: [GiftRecord] {
        counted.filter { $0.direction == LiqianConstants.given }
    }

    private var hostDisplay: String {
        let ledgerHost = (ledger.hostName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !ledgerHost.isEmpty { return ledgerHost }
        let global = (UserDefaults.standard.string(forKey: "hostName") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return global.isEmpty ? "主家" : global
    }

    var body: some View {
        List {
            Section {
                infoRow("礼簿", ledger.title)
                infoRow("事由", "\(ledger.type) · \(LiqianDate.displayString(for: ledger.date))")
                infoRow(
                    "收礼",
                    "\(receivedRecords.count) 笔 · \(LedgerMath.fmtMoney(cents: receivedRecords.reduce(0) { $0 + $1.amountCents }))"
                )
                infoRow(
                    "随礼",
                    "\(givenRecords.count) 笔 · \(LedgerMath.fmtMoney(cents: givenRecords.reduce(0) { $0 + $1.amountCents }))"
                )
                infoRow("主家", hostDisplay)
                infoRow("班子", members.isEmpty ? "未设" : "\(members.count) 人")
            } header: {
                Text("这本礼簿")
            }

            Section {
                Button {
                    makePackage()
                } label: {
                    Label("生成传承包", systemImage: "doc.zipper")
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                }
                if let packageURL {
                    ShareLink(item: packageURL) {
                        Label("分享传承包（数据）", systemImage: "square.and.arrow.up")
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                    }
                }
                if let noteURL {
                    ShareLink(item: noteURL) {
                        Label("分享交接说明（PDF）", systemImage: "doc.text")
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                    }
                }
            } header: {
                Text("交接给家人")
            } footer: {
                Text("传承包是这本礼簿的完整数据（记录与班子都在内），交接说明写清了簿名、笔数、总额和交接日期。接收方拿传承包在礼记里恢复，就能接着管这本簿。")
            }

            Section {
                Button {
                    // v5 门控：未开通 Pro 点按直达付费墙，不先生成再拦截
                    if entitlements.canUse(.memorialBook) {
                        makeMemorial()
                    } else {
                        showPaywall = true
                    }
                } label: {
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Label("生成纪念版礼谱", systemImage: "book.closed")
                        Spacer()
                        if !entitlements.canUse(.memorialBook) {
                            Text("Pro")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.primary)
                        }
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                }
                if generating {
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        ProgressView()
                        Text("正在成谱…")
                            .foregroundStyle(Palette.ink)
                    }
                } else if let memorialURL {
                    HandoverPDFPreviewView(url: memorialURL)
                        .frame(height: 420)
                        .listRowInsets(EdgeInsets())
                    ShareLink(item: memorialURL) {
                        Label("分享 / 保存纪念版礼谱", systemImage: "square.and.arrow.up")
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                    }
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            } header: {
                Text("纪念版")
            } footer: {
                Text("纪念版礼谱封面带「紀念」题签，内容与正式礼谱一致，是只读的留存件：打印装订、发给长辈都可以，不会改动记账数据。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: generateTrigger)
        .sensoryFeedback(.warning, trigger: generateErrorTrigger)
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
        }
        .navigationTitle("交接与纪念版")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Palette.stone)
            Spacer()
            Text(value)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
    }

    private func makePackage() {
        errorText = nil
        let data = LiqianBackup.makeBackup(
            ledgers: [ledger], records: records, members: members
        )
        let safeName = ledger.title.replacingOccurrences(of: "/", with: "、")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-传承包.json")
        do {
            try data.write(to: url, options: [.atomic])
            packageURL = url
            generateTrigger += 1
        } catch {
            errorText = "传承包生成失败，请重试。"
            generateErrorTrigger += 1
            return
        }
        noteURL = HandoverNotePDF.make(ledger: ledger, records: records, members: members)
        if noteURL == nil {
            errorText = "交接说明生成失败，传承包本身不受影响。"
            generateErrorTrigger += 1
        }
    }

    private func makeMemorial() {
        generating = true
        errorText = nil
        memorialURL = nil
        let url = GiftBookPDF.makePDF(
            ledger: ledger, records: records, memorial: true
        )
        generating = false
        if let url {
            memorialURL = url
            generateTrigger += 1
        } else {
            errorText = "纪念版礼谱生成失败，请重试。"
            generateErrorTrigger += 1
        }
    }
}

/// 交接页内的整谱预览（与 LibuExportView 的预览同为 PDFKit 薄封装；
/// 那份是文件私有，这里独立一份避免跨文件改动其可见性）
private struct HandoverPDFPreviewView: UIViewRepresentable {
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

/// 交接说明（一页 A4，横排）：写清这本簿是什么、多少笔、多少钱、谁交接。
/// 它是给人看的凭证页，不是礼谱本体，故用横排正文而非竖排礼制版式。
enum HandoverNotePDF {
    static func make(ledger: Ledger, records: [GiftRecord], members: [LedgerMember]) -> URL? {
        let counted = records.filter { !$0.isPendingSend }
        let received = counted.filter { $0.direction == LiqianConstants.received }
        let given = counted.filter { $0.direction == LiqianConstants.given }
        let receivedTotal = received.reduce(0) { $0 + $1.amountCents }
        let givenTotal = given.reduce(0) { $0 + $1.amountCents }

        let ledgerHost = (ledger.hostName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let globalHost = (UserDefaults.standard.string(forKey: "hostName") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let host = !ledgerHost.isEmpty ? ledgerHost : (globalHost.isEmpty ? "主家" : globalHost)
        let scribe = (ledger.scribe ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let verifier = (ledger.verifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let location = (ledger.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let today = LiqianDate.todayString()

        let pageW: CGFloat = 595
        let pageH: CGFloat = 842
        let bounds = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let safeName = ledger.title.replacingOccurrences(of: "/", with: "、")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-交接说明.pdf")

        let titleFont = UIFont(name: "Kaiti SC", size: 25) ?? UIFont.systemFont(ofSize: 25, weight: .semibold)
        let labelFont = UIFont(name: "Kaiti SC", size: 14) ?? UIFont.systemFont(ofSize: 14)
        let valueFont = UIFont.systemFont(ofSize: 14)
        let bodyFont = UIFont.systemFont(ofSize: 12.5)
        let ink = UIColor(white: 0.12, alpha: 1)
        let sub = UIColor(white: 0.42, alpha: 1)
        let line = UIColor(white: 0.85, alpha: 1)

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                let margin: CGFloat = 56
                var y: CGFloat = 64

                // 标题
                let title = "礼簿交接说明"
                let titleAttr: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: ink]
                let titleSize = (title as NSString).size(withAttributes: titleAttr)
                (title as NSString).draw(
                    at: CGPoint(x: (pageW - titleSize.width) / 2, y: y), withAttributes: titleAttr
                )
                y += titleSize.height + 10
                line.setStroke()
                let sep = UIBezierPath()
                sep.move(to: CGPoint(x: margin, y: y))
                sep.addLine(to: CGPoint(x: pageW - margin, y: y))
                sep.lineWidth = 0.75
                sep.stroke()
                y += 26

                // 键值行
                func row(_ label: String, _ value: String) {
                    let lAttr: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: sub]
                    let vAttr: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: ink]
                    (label as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: lAttr)
                    (value as NSString).draw(
                        in: CGRect(x: margin + 92, y: y, width: pageW - margin * 2 - 92, height: 22),
                        withAttributes: vAttr
                    )
                    y += 30
                }

                row("礼簿", ledger.title)
                row("事由", "\(ledger.type) · \(LiqianDate.displayString(for: ledger.date))（\(LiqianDate.ganzhiFullDate(for: ledger.date))）")
                if !location.isEmpty { row("地点", location) }
                row("收礼", "\(received.count) 笔 · \(LedgerMath.fmtMoney(cents: receivedTotal))")
                row("随礼", "\(given.count) 笔 · \(LedgerMath.fmtMoney(cents: givenTotal))")
                row("主家", host)
                if !scribe.isEmpty { row("书记", scribe) }
                if !verifier.isEmpty { row("核实", verifier) }
                if !members.isEmpty {
                    let team = members
                        .sorted {
                            ($0.roleValue.sortOrder, $0.createdAt, $0.name)
                                < ($1.roleValue.sortOrder, $1.createdAt, $1.name)
                        }
                        .map { "\($0.name)（\($0.role)）" }
                        .joined(separator: "、")
                    row("班子", team)
                }
                row("交接日期", "\(LiqianDate.displayString(for: today))（\(LiqianDate.lunarString(for: today))）")

                y += 14
                // 说明正文
                let note = "本说明随「\(ledger.title)-传承包」一同交接。传承包是这本礼簿的完整数据，"
                    + "包含全部 \(counted.count) 笔记录与班子名单。接收方在礼记「我的 → 数据 → "
                    + "从备份恢复」里导入传承包（或用后续版本的单簿导入），核对上面笔数与总额无误后，"
                    + "这本礼簿即完成交接。原数据请在交接确认后再行处理。"
                let noteStyle = NSMutableParagraphStyle()
                noteStyle.lineSpacing = 7
                let noteAttr: [NSAttributedString.Key: Any] = [
                    .font: bodyFont, .foregroundColor: ink,
                    .paragraphStyle: noteStyle,
                ]
                let noteRect = CGRect(x: margin, y: y, width: pageW - margin * 2, height: 160)
                (note as NSString).draw(in: noteRect, withAttributes: noteAttr)
                y += 150

                // 落款
                let sign = "主家 \(host) · \(LiqianDate.displayString(for: today))"
                let signAttr: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: ink]
                let signSize = (sign as NSString).size(withAttributes: signAttr)
                (sign as NSString).draw(
                    at: CGPoint(x: pageW - margin - signSize.width, y: y), withAttributes: signAttr
                )
            }
            return url
        } catch {
            return nil
        }
    }
}
