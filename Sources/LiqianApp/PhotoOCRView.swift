import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import Vision
import LiqianCore
import LiqianDesign

// MARK: - 设备端文字识别（Vision，全程 on-device、不联网）
// accurate 模式＋简体中文优先；照片先抹方向、限最大边长，大图直接喂
// 又慢又容易漂移。识别在后台任务里跑：跨任务只传 Data（可发送），
// CGImage 的解码与 Vision 请求都收在任务内部构造，不跨并发域传图。
// AI 增强是另一条路（把识别出的文字发 DeepSeek），不经过这里，
// 照片本身永远不出这台手机。

enum GiftListOCR {
    enum OCRError: Error {
        case noImageData
    }

    static func recognizeLines(in image: UIImage) async throws -> [String] {
        guard let data = normalizedJPEGData(image) else { throw OCRError.noImageData }
        return try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw OCRError.noImageData
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
    }

    /// 抹掉方向信息并把最大边限制到 2048，避免超大原图拖慢识别；
    /// 重绘后的图已无方向元数据，编码成 JPEG 供后台任务解码
    private static func normalizedJPEGData(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 2048
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.92)
    }
}

// MARK: - 系统相机桥接（SwiftUI 没有原生相机拍摄控件，用 UIImagePickerController）

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

// MARK: - 拍照识别礼单（v2.9）
// 照片 → Vision OCR（设备端）→ LedgerTextParser 规则解析 → 待确认列表
// （沿用一句话记账 v2.7 的可改可删行），一次导入当前礼簿、固定按收礼记。
// 规则解析读不顺（手写潦草/格式乱）时可点「AI 增强」：把 OCR 原文走
// Core 的 AIParse 多笔管线再解析一遍，替换候选并标注来源。

struct PhotoOCRView: View {
    let ledger: Ledger
    /// 导入完成回调（笔数），宿主据此给回执
    var onSaved: (Int) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allRecords: [GiftRecord]

    private enum Stage { case pick, recognizing, confirm, empty }
    /// 候选来源：本地规则解析 / AI 增强，确认页如实标注
    private enum Source { case rule, ai }

    /// 待确认行：姓名/金额可改可删，关系随行带走（不在行内编辑，与 v2.7 口径一致）
    private struct Row: Identifiable {
        let id = UUID()
        var name: String
        var amountText: String
        var relation: String?

        init(name: String, amountCents: Int, relation: String?) {
            self.name = name
            self.amountText = amountCents % 100 == 0
                ? "\(amountCents / 100)"
                : String(format: "%.2f", Double(amountCents) / 100.0)
            self.relation = relation
        }

        /// 行再校验：姓名非空、金额 > 0 才给分值
        var cents: Int? {
            let yuan = Double(amountText.trimmingCharacters(in: .whitespaces))
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
                  let yuan, yuan > 0 else { return nil }
            return Int((yuan * 100.0).rounded())
        }
    }

    @State private var stage: Stage = .pick
    @State private var source: Source = .rule
    @State private var pickedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var rows: [Row] = []
    /// 没列进确认列表的行数（规则解析失败行 / AI 侧无效与随礼条目），明示不静默
    @State private var skippedCount = 0
    @State private var ocrLines: [String] = []
    @State private var errorText: String?
    @State private var isEnhancing = false
    @State private var showAIGuide = false
    @State private var saveTrigger = 0

    private var isBai: Bool { ledger.isBai }

    private var stone: Color { isBai ? Palette.baiStone : Palette.stone }

    private var existingNames: Set<String> {
        Set(allRecords.filter { $0.ledgerID == ledger.id }.map(\.person))
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch stage {
                case .pick:
                    pickSections
                case .recognizing:
                    thumbnailSection
                    Section {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            ProgressView()
                            Text("正在识别…")
                                .foregroundStyle(Palette.ink)
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                    }
                case .confirm:
                    confirmSections
                case .empty:
                    emptySections
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.groupedBackground.ignoresSafeArea())
            .navigationTitle("拍照识别礼单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: saveTrigger)
            .alert("AI 还没准备好", isPresented: $showAIGuide) {
                Button("去设置") {
                    NotificationCenter.default.post(name: .liqianOpenAISettings, object: nil)
                }
                Button("好", role: .cancel) {}
            } message: {
                Text(AIAccess.readiness().guideMessage)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadPickedPhoto(newItem) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(
                    onImage: { image in
                        showCamera = false
                        startRecognition(image)
                    },
                    onCancel: { showCamera = false }
                )
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - 选图阶段

    @ViewBuilder
    private var pickSections: some View {
        Section {
            Text("对着纸质礼单拍一张，或从相册选一张，自动认出姓名和金额，核对后一次导入本礼簿（按收礼记）。识别在这台手机上完成，照片不上传。")
                .font(.footnote)
                .foregroundStyle(stone)
            // 识别能力如实说明，不夸大：Vision 对印刷体与工整手写有效，潦草手写识别率低
            Text("适合印刷体和工整手写的礼单；字迹潦草可能认不准，导入前请逐笔核对。")
                .font(.footnote)
                .foregroundStyle(stone)
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }

        Section {
            Button {
                showCamera = true
            } label: {
                Label("拍照", systemImage: "camera")
            }
            .frame(minHeight: LiqianMetrics.minTapTarget)
            .disabled(!cameraAvailable)
            Button {
                showPhotoPicker = true
            } label: {
                Label("从相册选", systemImage: "photo.on.rectangle")
            }
            .frame(minHeight: LiqianMetrics.minTapTarget)
            if !cameraAvailable {
                Text("当前设备没有可用相机，可从相册选一张礼单照片。")
                    .font(.footnote)
                    .foregroundStyle(stone)
            }
        }
    }

    // MARK: - 缩略图（确认/识别中/为空阶段置顶，方便对照原图核对）

    @ViewBuilder
    private var thumbnailSection: some View {
        if let pickedImage {
            Section {
                Image(uiImage: pickedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner))
                Button("换一张图") { resetToPick() }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
            }
        }
    }

    // MARK: - 确认阶段

    @ViewBuilder
    private var confirmSections: some View {
        thumbnailSection

        Section {
            HStack(spacing: LiqianMetrics.spacingS) {
                Text(source == .rule ? "本地规则解析" : "AI 增强解析")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(source == .rule ? Palette.stone : Palette.primary)
                Spacer()
                Text("方向：收礼")
                    .font(.footnote)
                    .foregroundStyle(stone)
            }
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }

        Section {
            if rows.isEmpty {
                Text("没有要导入的记录了。可以删改后重新解析，或换一张图。")
                    .font(.footnote)
                    .foregroundStyle(stone)
            } else {
                ForEach($rows) { $row in
                    rowEditor($row)
                }
            }
        } header: {
            Text("待确认（\(rows.count) 笔）")
        } footer: {
            if skippedCount > 0 {
                Text(skippedFooterText)
            }
        }

        if !ocrLines.isEmpty {
            Section {
                DisclosureGroup("识别原文（对照核对）") {
                    ForEach(Array(ocrLines.enumerated()), id: \.offset) { pair in
                        HStack(alignment: .top, spacing: LiqianMetrics.spacingS) {
                            Text("\(pair.offset + 1)")
                                .font(.footnote)
                                .foregroundStyle(stone)
                                .frame(width: 24, alignment: .trailing)
                            Text(pair.element)
                                .font(.footnote)
                                .foregroundStyle(Palette.ink)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }

        if source == .rule {
            Section {
                Button {
                    Task { await runAIEnhance() }
                } label: {
                    HStack {
                        Label("AI 增强识别", systemImage: "sparkles")
                        if isEnhancing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .frame(minHeight: LiqianMetrics.minTapTarget)
                .disabled(isEnhancing)
                Text("认得不顺时，把上面识别出的文字发送至 DeepSeek 重新解析一遍，手写、格式乱时更准；替换前请先看清现在的核对结果。")
                    .font(.footnote)
                    .foregroundStyle(stone)
            }
        } else {
            Section {
                Text("当前是 AI 增强的结果。觉得不对，点上方「换一张图」重新识别（回到规则解析）。")
                    .font(.footnote)
                    .foregroundStyle(stone)
            }
        }

        if !rows.isEmpty {
            Section {
                Button {
                    importAll()
                } label: {
                    Text("导入全部（\(rows.count) 笔）")
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                }
                .tint(isBai ? Palette.baiPrimary : Palette.primary)
            }
        }
    }

    private var skippedFooterText: String {
        switch source {
        case .rule:
            return "另有 \(skippedCount) 行没读出姓名和金额，没有列进来（多半是标题、合计这类行，或字迹太潦草）。对照下面的识别原文看看，漏了的用批量补录补上。"
        case .ai:
            return "另有 \(skippedCount) 条是随礼、或没读出姓名金额，没有列进来。随礼请用记一笔单独记。"
        }
    }

    private func rowEditor(_ row: Binding<Row>) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
            HStack(spacing: LiqianMetrics.spacingS) {
                TextField("姓名", text: row.name, prompt: Text("姓名"))
                HStack(spacing: 2) {
                    Text("¥")
                        .foregroundStyle(stone)
                    TextField("金额", text: row.amountText, prompt: Text("金额"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 96)
                }
                Button(role: .destructive) {
                    let id = row.wrappedValue.id
                    rows.removeAll { $0.id == id }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(stone)
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删掉这一笔")
            }
            if let relation = row.wrappedValue.relation {
                Text("关系：\(relation)")
                    .font(.footnote)
                    .foregroundStyle(stone)
            }
            if existingNames.contains(row.wrappedValue.name.trimmingCharacters(in: .whitespaces)) {
                Text("本礼簿已有同名记录，导入后将并列保存")
                    .font(.footnote)
                    .foregroundStyle(Palette.warning)
            }
        }
    }

    // MARK: - 为空阶段（两段识别都没读出可记的账：明确提示，不静默）

    @ViewBuilder
    private var emptySections: some View {
        thumbnailSection
        Section {
            Text("没认出姓名和金额，换一张更清晰的照片，或用粘贴导入。")
                .foregroundStyle(Palette.ink)
            Text("光线足一点、把礼单拍正拍近，识别会准很多；也可以先在相册里裁掉边角再选进来。")
                .font(.footnote)
                .foregroundStyle(stone)
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
    }

    // MARK: - 流程

    private func resetToPick() {
        stage = .pick
        source = .rule
        pickedImage = nil
        photoItem = nil
        rows = []
        ocrLines = []
        skippedCount = 0
        errorText = nil
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorText = "这张照片没读出来，换一张试试。"
                return
            }
            startRecognition(image)
        } catch {
            errorText = "这张照片没读出来，换一张试试。"
        }
    }

    private func startRecognition(_ image: UIImage) {
        pickedImage = image
        errorText = nil
        source = .rule
        stage = .recognizing
        Task {
            do {
                let lines = try await GiftListOCR.recognizeLines(in: image)
                finishRecognition(lines: lines)
            } catch {
                failRecognition()
            }
        }
    }

    /// 识别完成：OCR 文本走组装层（规则解析）产出候选；一笔都没有进为空态
    private func finishRecognition(lines: [String]) {
        ocrLines = lines
        let outcome = OCRCandidateBuilder.build(from: lines.joined(separator: "\n"))
        skippedCount = outcome.skipped.count
        if outcome.candidates.isEmpty {
            stage = .empty
        } else {
            rows = outcome.candidates.map {
                Row(name: $0.name, amountCents: $0.amountCents, relation: $0.relation)
            }
            stage = .confirm
        }
    }

    private func failRecognition() {
        ocrLines = []
        errorText = "识别没能完成，换一张更清晰的照片再试。"
        stage = .pick
    }

    /// AI 增强：OCR 原文走 Core 的 AIParse 多笔管线（与一句话记账/智能粘贴共用解码）
    private func runAIEnhance() async {
        switch AIAccess.readiness() {
        case .ready:
            break
        case .noKey, .notEnabled:
            showAIGuide = true
            return
        }
        guard !ocrLines.isEmpty else { return }
        isEnhancing = true
        errorText = nil
        do {
            let client = try DeepSeekClient()
            let data = try await client.chatJSON(
                system: Self.aiSystemPrompt,
                user: ocrLines.joined(separator: "\n")
            )
            let outcome = try AIParse.decode(data)
            isEnhancing = false
            // AI 侧没列进来的：无效条目＋拿不准的行号＋随礼（本页固定收礼，随礼不混入）
            var notListed = outcome.invalidCount + outcome.uncertain.count
            var newRows: [Row] = []
            for record in outcome.validRecords {
                if record.direction == LiqianConstants.given {
                    notListed += 1
                } else {
                    newRows.append(Row(name: record.name, amountCents: record.amountCents, relation: record.relation))
                }
            }
            guard !newRows.isEmpty else {
                errorText = "AI 也没读出可导入的账，先按现在的核对，或换一张更清晰的照片。"
                return
            }
            rows = newRows
            skippedCount = notListed
            source = .ai
        } catch let error as DeepSeekError {
            isEnhancing = false
            errorText = error.errorDescription
        } catch is AIParse.ParseError {
            isEnhancing = false
            errorText = "AI 返回内容格式异常，无法解析。先按现在的核对，或重试。"
        } catch {
            isEnhancing = false
            errorText = "AI 增强失败：\(error.localizedDescription)。先按现在的核对。"
        }
    }

    private static let aiSystemPrompt = """
        你是礼记的解析助手。用户会给你一段从纸质礼单拍照识别出来的文字（OCR 结果，可能有错字、漏字、行序混乱，一行未必只有一笔）。请把每一笔提取出来，只输出一个 JSON 对象，不要输出任何其他文字：{"records":[{"name":"","amountYuan":数字,"relation":null,"method":null,"direction":"received"}],"uncertain":[]}
        规则：1) name 姓名按原文最可能的写法，OCR 明显错字（如金额旁的人名被拆字）可结合上下文修正，但绝不凭空编造姓名；2) amountYuan 是金额数字，单位元，中文数字要换算（如「五百」=500）；3) direction：别人送给记账人是 "received"，记账人送出去是 "given"，看不出给 "received"；4) relation 只能是 亲戚/朋友/同事/同学/邻居/其他 之一，看不出给 null；5) method 只能是 现金/微信/支付宝/银行转账/实物 之一，看不出给 null；6) 标题、合计、日期这类不是记录的行直接跳过；拿不准是哪一笔、或金额读不出的，把原文行号（从 1 起）放进 uncertain，不要编造记录凑数。
        """

    /// 一次导入：沿用批量补录的落库口径——方向收礼、关系默认朋友、
    /// 方式默认现金、日期今天（AI 增强带来的关系同理带入）
    private func importAll() {
        var parsed: [(name: String, cents: Int, relation: String?)] = []
        for row in rows {
            guard let cents = row.cents else {
                errorText = "有记录缺姓名或金额，改好、或删掉那一行再导入。"
                return
            }
            parsed.append((row.name.trimmingCharacters(in: .whitespaces), cents, row.relation))
        }
        guard !parsed.isEmpty else { return }
        errorText = nil
        for item in parsed {
            modelContext.insert(
                GiftRecord(
                    ledgerID: ledger.id,
                    person: item.name,
                    relation: item.relation ?? "朋友",
                    amountCents: item.cents,
                    direction: LiqianConstants.received,
                    method: "现金",
                    date: LiqianDate.todayString()
                )
            )
        }
        try? modelContext.save()
        saveTrigger += 1
        onSaved(parsed.count)
        dismiss()
    }
}
