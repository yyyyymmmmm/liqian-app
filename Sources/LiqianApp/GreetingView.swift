import SwiftUI
import LiqianCore
import LiqianDesign

/// 贺词生成：按礼簿事由让 DeepSeek 出 3 条候选——红事贺词、白事挽联/唁电短文，
/// 可用于礼谱题跋、请柬回执、唁电。每条一键复制，用不用、怎么改由人定。
struct GreetingView: View {
    let ledger: Ledger

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind
    @State private var tone = "庄重"
    @State private var hostName = ""
    @State private var relationToHost = ""
    @State private var candidates: [String] = []
    @State private var isGenerating = false
    @State private var errorText: String?
    @State private var copiedIndex: Int?
    /// 复制成功触感（v4.4）：此前只有按钮文案变「已复制」，无触觉确认
    @State private var copyTrigger = 0
    @State private var showGuide = false

    enum Kind: String, CaseIterable, Identifiable {
        case heci = "贺词"
        case wanlian = "挽联"
        case dianwen = "唁电短文"
        var id: String { rawValue }
    }

    init(ledger: Ledger) {
        self.ledger = ledger
        // 白事默认挽联，其他事由默认贺词
        _kind = State(initialValue: ledger.isBai ? .wanlian : .heci)
    }

    private var isBai: Bool { ledger.isBai }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $kind) {
                        ForEach(Kind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    Picker("口吻", selection: $tone) {
                        Text("庄重").tag("庄重")
                        Text("亲切").tag("亲切")
                    }
                    .pickerStyle(.segmented)
                    TextField("主家姓名（选填）", text: $hostName, prompt: Text("如：张建国"))
                    TextField("你和主家的关系（选填）", text: $relationToHost, prompt: Text("如：表弟、同事、老同学"))
                    Text("这本礼簿是「\(ledger.type)」。将把上面这几项发送至 DeepSeek 生成文字。")
                        .font(.footnote)
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }

                Section {
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack {
                            Text(candidates.isEmpty ? "生成 3 条" : "重新生成")
                            if isGenerating {
                                Spacer()
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                    }
                    .disabled(isGenerating)
                }

                if !candidates.isEmpty {
                    Section {
                        ForEach(candidates.indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
                                Text(candidates[i])
                                    .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                Button {
                                    UIPasteboard.general.string = candidates[i]
                                    copiedIndex = i
                                    copyTrigger += 1
                                } label: {
                                    Label(
                                        copiedIndex == i ? "已复制" : "复制这条",
                                        systemImage: copiedIndex == i ? "checkmark" : "doc.on.doc"
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(isBai ? Palette.baiPrimary : Palette.primary)
                                    .frame(minHeight: LiqianMetrics.minTapTarget)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, LiqianMetrics.spacingXS)
                        }
                        Text("AI 生成，请核对后再用；人名、称谓最容易出错，看清了再发。")
                            .font(.footnote)
                            .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                    } header: {
                        Text("生成结果")
                    }
                }
            }

            .navigationTitle("生成贺词")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .sensoryFeedback(.success, trigger: copyTrigger)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("AI 还没准备好", isPresented: $showGuide) {
                Button("去设置") {
                    NotificationCenter.default.post(name: .liqianOpenAISettings, object: nil)
                }
                Button("好", role: .cancel) {}
            } message: {
                Text(AIAccess.readiness().guideMessage)
            }
        }
    }

    private func generate() async {
        switch AIAccess.readiness() {
        case .ready:
            break
        case .noKey, .notEnabled:
            showGuide = true
            return
        }
        isGenerating = true
        errorText = nil
        copiedIndex = nil
        do {
            let client = try DeepSeekClient()
            let text = try await client.chatText(system: Self.systemPrompt, user: userPrompt)
            let parts = Self.splitCandidates(text)
            isGenerating = false
            if parts.isEmpty {
                errorText = "未生成可用内容，请重试。"
            } else {
                candidates = parts
            }
        } catch let error as DeepSeekError {
            isGenerating = false
            errorText = error.errorDescription
        } catch {
            isGenerating = false
            errorText = "生成失败：\(error.localizedDescription)"
        }
    }

    private var userPrompt: String {
        var lines = [
            "请写 3 条\(kind.rawValue)候选，口吻：\(tone)。",
            "场合：\(ledger.type)（礼簿名：\(ledger.title)）。",
        ]
        let host = hostName.trimmingCharacters(in: .whitespaces)
        if !host.isEmpty { lines.append("主家姓名：\(host)。") }
        let rel = relationToHost.trimmingCharacters(in: .whitespaces)
        if !rel.isEmpty { lines.append("写信人与主家的关系：\(rel)，落款称谓按这个关系拿捏。") }
        lines.append("3 条之间用一个空行隔开，不要编号、不要解释、不要前后缀。")
        return lines.joined(separator: "\n")
    }

    private static let systemPrompt = """
        你是深谙中国人情礼仪的文字先生，替人写婚丧嫁娶场合的得体文字。规矩：
        1) 贺词以四字句式为主，两到四句，庄重场合不用口语、不堆砌辞藻；
        2) 挽联给上下联两行，对仗、平仄大致相对，上联下联各一行，只给一副联再配横批一行也行；
        3) 唁电短文三到五句，沉痛得体，先唁后慰；
        4) 不用网络用语和梗，不用感叹号，不出现「愿逝者安息」之外的宗教词；
        5) 不确定的姓名、称谓宁可留空位也不许编造；
        6) 严格按用户要求输出 3 条候选，条与条之间只用一个空行分隔，不编号、不加任何解释。
        """

    /// 候选按空行拆分；顺手剥掉模型偶尔加的序号前缀
    private static func splitCandidates(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { chunk -> String in
                var lines = chunk
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if let first = lines.first {
                    let stripped = first.replacingOccurrences(
                        of: #"^\d+[\.、．]\s*"#, with: "", options: .regularExpression
                    )
                    lines[0] = stripped
                }
                return lines.joined(separator: "\n")
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
