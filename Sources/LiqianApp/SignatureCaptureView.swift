import LiqianCore
import LiqianDesign
import PencilKit
import SwiftData
import SwiftUI

// MARK: - 签名采集（v4.2 活礼谱）
//
// 全屏 PencilKit 画布，drawingPolicy = .anyInput：手指可签（现场来宾
// 多半没有 Apple Pencil）。签名是「纸面行为」：画布固定白纸底、黑笔，
// 不随深浅色变——导出的 PNG 只有笔迹（透明底），进礼谱纸面与电子礼谱
// 都自然。完成时把 PKDrawing 渲成 PNG 交给调用方落库，本视图不碰数据库。

struct SignatureCaptureView: View {
    let person: String
    /// 完成回调：PNG 数据（笔迹，透明底）
    var onSave: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var canvas = PKCanvasView()
    /// 保存成功触感（v4.7 审计补齐）：原来点「完成」只有页面消失、无任何确认感
    @State private var saveTrigger = 0

    private var isEmpty: Bool { drawing.strokes.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                PKCanvasRepresentable(canvas: canvas, drawing: $drawing)
                if isEmpty {
                    Text("请\(person)在虚线框内签名")
                        .font(.body)
                        .foregroundStyle(Palette.paperStone)
                        .allowsHitTesting(false)
                }
                RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                    .strokeBorder(
                        Palette.paperStone.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                    )
                    .padding(LiqianMetrics.spacingL)
                    .allowsHitTesting(false)
            }
            .navigationTitle("来宾签名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清除") {
                        drawing = PKDrawing()
                        canvas.drawing = PKDrawing()
                    }
                    .disabled(isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
                        .disabled(isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
        .sensoryFeedback(.success, trigger: saveTrigger)
    }

    private func save() {
        guard !isEmpty else { return }
        // 笔迹外扩一点边距再出图，避免贴边裁切
        let rect = drawing.bounds.insetBy(dx: -16, dy: -16)
        let image = drawing.image(from: rect, scale: 2.0)
        guard let png = image.pngData() else { return }
        saveTrigger += 1
        onSave(png)
        dismiss()
    }
}

/// PKCanvasView 包装：手指/触控笔都可签；工具固定黑色中粗笔
private struct PKCanvasRepresentable: UIViewRepresentable {
    let canvas: PKCanvasView
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3.5)
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let parent: PKCanvasRepresentable

        init(_ parent: PKCanvasRepresentable) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

// MARK: - 签名缩略图（纸白底圆角片：电子礼谱/记录区共用）

struct SignatureThumbnail: View {
    let imageData: Data
    var height: CGFloat = 40

    var body: some View {
        if let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .padding(.horizontal, 6)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner))
                .overlay(
                    RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner)
                        .strokeBorder(Palette.line, lineWidth: 1)
                )
        }
    }
}

// MARK: - 记录编辑页「签名与祝福」区（编辑已有记录时出现）
//
// 签名/祝福都挂在具体一笔上，新增记录要先保存才有 id 可挂，故只在
// 编辑态出现；人物页/礼簿详情的记录行也有同样的入口（contextMenu）。

struct RecordLiveMediaSection: View {
    let record: GiftRecord

    @Environment(\.modelContext) private var modelContext
    @Query private var allSignatures: [GuestSignature]
    @Query private var allBlessings: [VoiceBlessing]
    @State private var showSignaturePad = false
    @State private var showBlessings = false

    private var signatures: [GuestSignature] {
        allSignatures
            .filter { $0.recordID == record.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var blessings: [VoiceBlessing] {
        allBlessings
            .filter { $0.recordID == record.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
            HStack(spacing: 6) {
                Text("签名与祝福")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("活礼谱")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Palette.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.primaryTint)
                    .clipShape(Capsule())
            }

            if signatures.isEmpty {
                Button {
                    showSignaturePad = true
                } label: {
                    Label("请 \(record.person) 签名", systemImage: "signature")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.primary)
                }
            } else {
                ForEach(signatures) { sig in
                    HStack(spacing: LiqianMetrics.spacingS) {
                        SignatureThumbnail(imageData: sig.imageData, height: 44)
                        Spacer()
                        Button(role: .destructive) {
                            modelContext.delete(sig)
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "trash")
                                .font(.body.weight(.medium))
                        }
                        .accessibilityLabel("删除签名")
                    }
                }
                Button {
                    showSignaturePad = true
                } label: {
                    Label("再签一个", systemImage: "signature")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.primary)
                }
            }

            Divider()

            Button {
                showBlessings = true
            } label: {
                HStack {
                    Label("语音祝福", systemImage: "waveform")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(blessings.isEmpty ? "还没有" : "\(blessings.count) 段")
                        .font(.subheadline)
                        .foregroundStyle(Palette.sub)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.sub)
                }
            }
        }
        .padding(LiqianMetrics.spacingM)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
        .sheet(isPresented: $showSignaturePad) {
            SignatureCaptureView(person: record.person) { png in
                modelContext.insert(
                    GuestSignature(
                        ledgerID: record.ledgerID, recordID: record.id,
                        person: record.person, imageData: png
                    )
                )
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $showBlessings) {
            RecordBlessingsView(record: record)
        }
    }
}
