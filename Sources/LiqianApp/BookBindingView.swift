import SwiftUI
import UIKit
import LiqianCore
import LiqianDesign

/// 装订成书说明页（v5 成书做实）：把「礼谱做成实体书」讲清楚——工艺、
/// 预期价格带与周期（口径引 POD 调研）、首批人工履约内测的登记方式。
/// 红线：不在 App 内伪造在线下单。登记只做两件真事：存一份本机记录，
/// 再打开一封预填好的邮件（发到 inkroot001@gmail.com），由用户点发送；
/// 之后人工确认确切页数与印厂书面报价，用户点头才下单付款。
struct BookBindingView: View {
    let ledger: Ledger
    /// 成册口径笔数（已排除待送出）
    let countedCount: Int

    @State private var intentSaved = false

    private static let intentsKey = "bindingIntentRecords"

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
                    Text("把这本礼簿，做成一本能传下去的礼谱")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    Text("《\(ledger.title)》的礼谱已经是印刷级排版——竖排右起、谱序、落印。装订成书就是把它印出来、锁线精装成册：摆在家里、送给长辈，都是拿得出手的传家件。")
                        .font(.subheadline)
                        .foregroundStyle(Palette.stone)
                }
                .padding(.vertical, LiqianMetrics.spacingXS)
            }

            Section {
                infoRow("工艺", "锁线精装 · 右开本 · 米白纸内页")
                infoRow("印刷文件", "用本页的「印刷版礼谱」导出（含出血与封面展开图）")
                infoRow("预期价格", "约 299–399 元 / 本（按页数定）")
                infoRow("预期周期", "约 10 天（下单到收货）")
            } header: {
                Text("成书口径")
            } footer: {
                Text("价格与周期是当前调研的预期口径：终价要按这本谱的确切页数向印厂询书面报价后确认，周期以印厂排期为准——都确认清楚、你点头之后才下单付款。")
            }

            Section {
                Text("首批是人工履约内测：登记后，我们会人工联系你，核对页数、拿到印厂书面报价再报你确认。不在 App 里下单、不在 App 里收款。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                Button {
                    registerIntent()
                } label: {
                    Label("登记意向", systemImage: "envelope")
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.primary)
                if intentSaved {
                    Text("已在本机记下这次意向，并打开了一封预填邮件——请在邮件里点「发送」，意向才算登记成功；不想发也没关系，不会产生任何订单。")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
            } header: {
                Text("意向登记（首批内测）")
            }
        }
        .listStyle(.insetGrouped)
        .background(Palette.groupedBackground.ignoresSafeArea())
        .navigationTitle("装订成书")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: LiqianMetrics.spacingSM) {
            Text(label)
                .foregroundStyle(Palette.stone)
            Spacer()
            Text(value)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: LiqianMetrics.minTapTarget)
    }

    /// 登记＝本机留痕＋预填邮件（mailto 到产品反馈邮箱），仅此而已
    private func registerIntent() {
        var records = UserDefaults.standard.stringArray(forKey: Self.intentsKey) ?? []
        let stamp = ISO8601DateFormatter().string(from: Date())
        records.append("\(ledger.title)|\(ledger.type)|\(ledger.date)|\(countedCount)|\(stamp)")
        UserDefaults.standard.set(records, forKey: Self.intentsKey)
        intentSaved = true

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "inkroot001@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "礼谱成书意向登记 · \(ledger.title)"),
            URLQueryItem(
                name: "body",
                value: """
                我想登记礼谱装订成书意向：

                礼簿：\(ledger.title)
                事由：\(ledger.type) · \(LiqianDate.displayString(for: ledger.date))
                笔数：\(countedCount) 笔（成册口径）
                联系方式（请填）：

                其他说明：

                （发送后会有人人工联系我，确认确切页数与印厂书面报价，我确认价格后再下单。）
                """
            ),
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}
