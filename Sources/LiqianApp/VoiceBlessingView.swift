import LiqianCore
import LiqianDesign
import SwiftData
import SwiftUI

// MARK: - 一笔记录的语音祝福（v4.2 活礼谱）：录 / 播 / 删 / 转写
//
// 从记录行、记录编辑页、人物页进入。录音走 BlessingRecorder（AAC 存
// App 容器目录），入库后异步转写（BlessingTranscriber，文件型识别；
// 不可达 transcript 留空）。播放走共享 BlessingPlayer（同时只播一条）。
// 删除 = 删行 + 删音频文件，两边都清。

struct RecordBlessingsView: View {
    let record: GiftRecord

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allBlessings: [VoiceBlessing]
    @StateObject private var player = BlessingPlayer()
    @StateObject private var recorder = BlessingRecorder()

    private var blessings: [VoiceBlessing] {
        allBlessings
            .filter { $0.recordID == record.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if blessings.isEmpty && !recorder.isRecording {
                    Text("还没有语音祝福。让 \(record.person) 对着手机说一句，声音会跟着这笔礼一起收进礼谱。")
                        .font(.subheadline)
                        .foregroundStyle(Palette.sub)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(blessings) { blessing in
                    blessingRow(blessing)
                }
                .onDelete(perform: deleteBlessings)

                Section {
                    recordControl
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("语音祝福")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert(
                "提示",
                isPresented: Binding(
                    get: { recorder.errorText != nil || player.errorText != nil },
                    set: { if !$0 { recorder.errorText = nil; player.errorText = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(recorder.errorText ?? player.errorText ?? "")
            }
            .onDisappear {
                player.stop()
                if recorder.isRecording { recorder.cancel() }
            }
        }
    }

    private func blessingRow(_ blessing: VoiceBlessing) -> some View {
        HStack(spacing: LiqianMetrics.spacingSM) {
            Button {
                player.toggle(blessing)
            } label: {
                Image(systemName: player.isPlaying(blessing) ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Palette.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying(blessing) ? "停止播放" : "播放祝福")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(blessingDurationText(blessing.duration))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Text(blessing.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.footnote)
                        .foregroundStyle(Palette.sub)
                }
                if let transcript = blessing.transcript, !transcript.isEmpty {
                    Text(transcript)
                        .font(.footnote)
                        .foregroundStyle(Palette.sub)
                        .lineLimit(3)
                } else if !BlessingAudioStore.exists(blessing.fileName) {
                    Text("录音文件不在本机（保存在录制的那台设备上）")
                        .font(.footnote)
                        .foregroundStyle(Palette.warning)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var recordControl: some View {
        if recorder.isRecording {
            HStack(spacing: LiqianMetrics.spacingSM) {
                Circle()
                    .fill(Palette.danger)
                    .frame(width: 10, height: 10)
                Text("录音中 \(blessingDurationText(recorder.elapsed))")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button("取消") { recorder.cancel() }
                Button("完成") { finishRecording() }
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.primary)
            }
        } else {
            Button {
                recorder.start()
            } label: {
                Label("录一段祝福", systemImage: "mic.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.primary)
            }
        }
    }

    private func finishRecording() {
        guard let result = recorder.stop() else { return }
        let blessing = VoiceBlessing(
            recordID: record.id,
            fileName: result.fileName,
            duration: result.duration
        )
        modelContext.insert(blessing)
        try? modelContext.save()
        // 转写是异步锦上添花：拿到文字回填，拿不到就留空（不阻塞、不编造）
        let fileName = result.fileName
        Task {
            if let text = await BlessingTranscriber.transcribe(fileName: fileName),
               !text.isEmpty {
                blessing.transcript = text
                try? modelContext.save()
            }
        }
    }

    private func deleteBlessings(at offsets: IndexSet) {
        for index in offsets {
            let blessing = blessings[index]
            BlessingAudioStore.remove(blessing.fileName)
            modelContext.delete(blessing)
        }
        try? modelContext.save()
    }
}

// MARK: - 深链播放页（liqian://blessing/<id>）
//
// 礼谱祝福索引页二维码扫码落点：ContentView.onOpenURL 命中后弹出。
// 只做播放这一件事：谁的祝福、哪本礼簿、录音在不在本机，都说清楚。

struct BlessingPlayerView: View {
    let blessing: VoiceBlessing

    @Environment(\.dismiss) private var dismiss
    @Query private var allRecords: [GiftRecord]
    @Query private var allLedgers: [Ledger]
    @StateObject private var player = BlessingPlayer()

    private var record: GiftRecord? {
        allRecords.first { $0.id == blessing.recordID }
    }

    private var ledgerTitle: String? {
        guard let record else { return nil }
        return allLedgers.first { $0.id == record.ledgerID }?.title
    }

    private var fileAvailable: Bool {
        BlessingAudioStore.exists(blessing.fileName)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: LiqianMetrics.spacingM) {
                Spacer()
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Palette.primary)
                if let record {
                    Text("\(record.person) 的祝福")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if let ledgerTitle {
                        Text(ledgerTitle)
                            .font(.subheadline)
                            .foregroundStyle(Palette.sub)
                    }
                }
                Text("\(blessingDurationText(blessing.duration)) · \(blessing.createdAt, format: .dateTime.year().month().day())")
                    .font(.footnote)
                    .foregroundStyle(Palette.sub)

                if fileAvailable {
                    Button {
                        player.toggle(blessing)
                    } label: {
                        Label(
                            player.isPlaying(blessing) ? "停止" : "播放祝福",
                            systemImage: player.isPlaying(blessing) ? "stop.fill" : "play.fill"
                        )
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Palette.primaryFill)
                        .clipShape(Capsule())
                    }
                } else {
                    Text("这段祝福的录音保存在录制的那台设备上，本机没有这个文件。")
                        .font(.subheadline)
                        .foregroundStyle(Palette.warning)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, LiqianMetrics.spacingL)
                }

                if let transcript = blessing.transcript, !transcript.isEmpty {
                    Text(transcript)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, LiqianMetrics.spacingL)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Palette.pageBG)
            .navigationTitle("语音祝福")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
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
    }
}
