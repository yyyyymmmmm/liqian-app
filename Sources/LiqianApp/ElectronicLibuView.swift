import LiqianCore
import LiqianDesign
import SwiftData
import SwiftUI

// MARK: - 电子礼谱（v4.2 活礼谱）：App 内翻页阅读
//
// 选型：原生排版，不复用礼谱 PDF 的渲染页图——页图点不动、播不了声，
// 「活」礼谱的价值正在逐笔可交互：有语音祝福的笔带播放钮当场出声，
// 有签名的笔显签名缩略（笔迹本体）。版式与纸礼谱同源：成册口径一致
// （排除待送出、日期升序＋同日姓名序），页序同为 封面 → 内页 →
// 签名页 → 答谢页；纸礼谱（PDF）仍是导出存档的正本，这里是随身翻看本。

struct ElectronicLibuView: View {
    let ledger: Ledger

    @Query private var allRecords: [GiftRecord]
    @Query private var allSignatures: [GuestSignature]
    @Query private var allBlessings: [VoiceBlessing]
    @StateObject private var player = BlessingPlayer()
    @State private var page = 0

    private var isBai: Bool { ledger.isBai }
    private var accent: Color { isBai ? Palette.baiPrimary : Palette.primary }

    /// 成册口径（与 GiftBookPDF.makePDF 一致）
    private var counted: [GiftRecord] {
        allRecords
            .filter { $0.ledgerID == ledger.id && !$0.isPendingSend }
            .sorted { ($0.date, $0.person) < ($1.date, $1.person) }
    }

    private var signatures: [GuestSignature] {
        let countedIDs = Set(counted.map(\.id))
        return allSignatures
            .filter {
                $0.ledgerID == ledger.id
                    && ($0.recordID == nil || countedIDs.contains($0.recordID!))
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func blessings(of record: GiftRecord) -> [VoiceBlessing] {
        allBlessings
            .filter { $0.recordID == record.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func signature(of record: GiftRecord) -> GuestSignature? {
        signatures.first { $0.recordID == record.id }
    }

    private enum LibuPage: Identifiable {
        case cover
        case records([GiftRecord])
        case signatures([GuestSignature])
        case thanks

        var id: String {
            switch self {
            case .cover: return "cover"
            case .records(let rs): return "records-\(rs.first?.id.uuidString ?? "empty")"
            case .signatures: return "signatures"
            case .thanks: return "thanks"
            }
        }
    }

    private var pages: [LibuPage] {
        var result: [LibuPage] = [.cover]
        let perPage = 6
        if counted.isEmpty {
            result.append(.records([]))
        } else {
            for start in stride(from: 0, to: counted.count, by: perPage) {
                result.append(.records(Array(counted[start..<min(start + perPage, counted.count)])))
            }
        }
        if !signatures.isEmpty {
            result.append(.signatures(signatures))
        }
        result.append(.thanks)
        return result
    }

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, libuPage in
                pageView(libuPage)
                    .tag(index)
                    .padding(.horizontal, LiqianMetrics.spacingM)
                    .padding(.vertical, LiqianMetrics.spacingM)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .background(Palette.pageBG)
        .navigationTitle("电子礼谱")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "提示",
            isPresented: Binding(
                get: { player.errorText != nil },
                set: { if !$0 { player.errorText = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(player.errorText ?? "")
        }
        .onDisappear { player.stop() }
    }

    @ViewBuilder
    private func pageView(_ libuPage: LibuPage) -> some View {
        Group {
            switch libuPage {
            case .cover:
                coverPage
            case .records(let rs):
                recordsPage(rs)
            case .signatures(let sigs):
                signaturesPage(sigs)
            case .thanks:
                thanksPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
        .overlay(
            RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }

    // MARK: 封面页

    private var coverPage: some View {
        VStack(spacing: LiqianMetrics.spacingM) {
            Spacer()
            Text(ledger.title)
                .font(.liqianSerifFixed(size: 30))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(ledger.type)
                .font(.subheadline)
                .foregroundStyle(accent)
            if let location = ledger.location, !location.isEmpty {
                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(Palette.sub)
            }
            Text(LiqianDate.displayString(for: ledger.date))
                .font(.subheadline)
                .foregroundStyle(Palette.sub)
            Spacer()
            Text("共 \(counted.count) 笔 · 左右滑动翻页")
                .font(.footnote)
                .foregroundStyle(Palette.sub)
            Spacer().frame(height: LiqianMetrics.spacingL)
        }
        .padding(LiqianMetrics.spacingL)
    }

    // MARK: 记录页（有祝福可播、有签名显缩略）

    private func recordsPage(_ rs: [GiftRecord]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if rs.isEmpty {
                ContentUnavailableView(
                    "礼谱还是空的",
                    systemImage: "book.closed",
                    description: Text("记下第一笔后，这里就是可以翻看的电子礼谱。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(rs) { record in
                    recordRow(record)
                    if record.id != rs.last?.id {
                        Divider()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(LiqianMetrics.spacingM)
    }

    private func recordRow(_ record: GiftRecord) -> some View {
        let recordBlessings = blessings(of: record)
        return HStack(alignment: .top, spacing: LiqianMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.person)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if !recordBlessings.isEmpty {
                        Text("聲")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(accent)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text("\(record.relation) · \(LiqianDate.displayString(for: record.date))")
                    .font(.footnote)
                    .foregroundStyle(Palette.sub)
                if let sig = signature(of: record) {
                    SignatureThumbnail(imageData: sig.imageData, height: 34)
                        .frame(maxWidth: 150, alignment: .leading)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(LedgerMath.fmtMoney(cents: record.amountCents))
                    .font(.liqianMoney(.body))
                    .foregroundStyle(Palette.ink)
                if let first = recordBlessings.first {
                    Button {
                        player.toggle(first)
                    } label: {
                        Label(
                            player.isPlaying(first) ? "停止" : "听祝福",
                            systemImage: player.isPlaying(first) ? "stop.circle.fill" : "play.circle.fill"
                        )
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    if recordBlessings.count > 1 {
                        Text("共 \(recordBlessings.count) 段")
                            .font(.caption2)
                            .foregroundStyle(Palette.sub)
                    }
                }
            }
        }
        .padding(.vertical, LiqianMetrics.spacingS)
    }

    // MARK: 签名页

    private func signaturesPage(_ sigs: [GuestSignature]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
                Text("来宾签名")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: LiqianMetrics.spacingM
                ) {
                    ForEach(sigs) { sig in
                        VStack(spacing: 6) {
                            SignatureThumbnail(imageData: sig.imageData, height: 56)
                            Text(sig.person)
                                .font(.footnote)
                                .foregroundStyle(Palette.sub)
                        }
                    }
                }
            }
            .padding(LiqianMetrics.spacingM)
        }
    }

    // MARK: 答谢页

    private var thanksPage: some View {
        VStack(spacing: LiqianMetrics.spacingM) {
            Spacer()
            Text(isBai ? "铭谢" : "答谢")
                .font(.liqianSerifFixed(size: 24))
                .foregroundStyle(accent)
            Text(isBai
                ? "承蒙各位亲友亲临吊唁、慰问相助，主家铭记在心，谨此致谢。"
                : "承蒙各位亲友亲临道贺、慷慨赠礼，主家感激不尽，谨此致谢。")
                .font(.body)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, LiqianMetrics.spacingL)
            if let host = ledger.hostName, !host.isEmpty {
                Text("\(host) 谨谢")
                    .font(.subheadline)
                    .foregroundStyle(Palette.sub)
            }
            Spacer()
        }
        .padding(LiqianMetrics.spacingL)
    }
}
