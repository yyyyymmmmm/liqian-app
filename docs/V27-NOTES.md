# V27-NOTES（真机缺陷修复：一句话记账麦克风闪退 + AI 记账多笔）

## 缺陷 1：点麦克风即闪退

### 根因排查（先证伪首要嫌疑）

- **嫌疑一「缺 UsageDescription」——证伪。** `Project.swift` 自 commit 8dcc37f 起就带
  `NSSpeechRecognitionUsageDescription` 与 `NSMicrophoneUsageDescription`（Tuist
  `extendingDefault` 注入）；进一步解开用户实际安装的 v2.6 IPA
  （`~/workspace/your_files/liqian-v2.6-record/liqian-native-unsigned.ipa`）读其中
  Info.plist，两个键都在、值非空。所以不是 TCC 缺文案杀进程。
  本版仍按新口径更新了两条文案：麦克风「用于语音记账，把你说的话转成文字」、
  语音识别「用于将语音转写为记账文字」。
- **真根因在音频启动路径（`SpeechTranscriber`，位于 QuickSentenceView.swift）。**
  AVAudioEngine 装 tap 有两类 **Swift do/catch 拦不住的 NSException**，旧代码两类都可能踩：
  1. **无效输入格式装 tap**：`beginSession()` 直接拿 `input.outputFormat(forBus: 0)`
     去 `installTap`。硬件路由未就绪时该格式的 sampleRate/channelCount 为 0，
     installTap 触发 AVFAudio 的 NSException，进程直接终止——且 do/catch 抓不到，
     旧代码的「录音启动失败」提示永远走不到。
  2. **重入 start() / 残留 tap 重复装**：授权（语音识别 + 麦克风）是异步链，
     `isRecording` 在引擎真正启动前一直是 false，`toggle()` 拿它判断状态——
     授权慢一点、或用户连点，`start()` 就会二次进入、两次 `beginSession()`；
     且旧 `stop()` 只在 `audioEngine.isRunning` 时才 `removeTap`，
     启动中途失败残留的 tap 不摘，下一次在同一 bus 上再 installTap =
     「only one tap per bus」NSException，必崩。

### 修法（全部在 SpeechTranscriber 内）

- 新增 `@Published isStarting` 重入闸门：`start()` 入口 `guard !isRecording, !isStarting`，
  `toggle()` 在启动中忽略点击，视图层按钮同时 `.disabled(isStarting)` 并显示「正在启动…」；
  每条退出路径（授权拒/麦克风拒/启动成功/失败）都复位。
- 装 tap 前校验格式：`format.sampleRate > 0 && format.channelCount > 0`，
  不满足直接给人话提示「麦克风暂时不可用，可直接输入文字」并收尾，绝不 installTap。
- 装 tap 前先无条件 `removeTap(onBus: 0)` 清残留；`stop()` 改为不管引擎是否在跑
  都摘 tap，并用 `sessionActivated` 标记决定是否 deactivate 音频会话（不误关他人状态）。
- 识别器不可用/未授权仍走既有口径：errorText 人话提示 + 文本输入始终可用，不闪退。

### grep 证据

- `grep -n "UsageDescription" Project.swift` → NSFaceID/NSSpeech/NSMicrophone 三键齐全（48/49 行为新文案）。
- v2.6 IPA 内 Info.plist 实测含 `NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`（python plistlib 读取）。

## 缺陷 2：AI 记账只能记一笔

### 根因

一句话记账与智能粘贴是两套独立实现：智能粘贴（BatchEntryView）本来就是
`{"records":[...]}` 多笔数组；而一句话记账的 prompt 明写「提取成一笔，只输出一个 JSON 对象」，
解码结构 `RawResult` 也只收单条，回调只预填单笔表单——所以永远只有一笔。

### 修法：Core 共用多笔管线

- 新增 `Sources/LiqianCore/AIParse.swift`：`AIParse.decode(_:) -> Outcome`，
  统一做多笔解码＋字段映射（金额元→分换算四舍五入、关系/方式白名单过滤、
  direction "given"→随礼 其余→收礼、eventHint 透传）。单条缺字段宽容处理
  （落成 `isValid=false` 条目保留顺序、不拖垮整批），整体结构不对才抛
  `AIParse.ParseError.unreadable`。
- **一句话记账**（QuickSentenceView）：prompt 改为多笔提取（明写「大舅2000，二姨1000，
  张三给了500 → 3 条」、多行逐笔、不许合并）；解析后进入「待确认（N 笔）」列表——
  每行姓名/金额（元）/方向（分段）可改、可删行，无效条目略过并明示条数；
  底部「保存全部（N 笔）」一次回调。可用记录为 0 时明确提示
  「没听出可记的账，换个说法试试。」，不静默、不进确认态。
  N=1 时走同一列表，无单独分支。保存前逐行再校验（缺姓名/金额拦下并提示改或删行）。
- **落库通道**（RecordFormView）：新增 `saveAIResults(_:)` 取代旧单笔 `applyAIResult`——
  沿用 `save()` 的字段口径（关系/方式缺失取表单当前选择、日期取表单日期、
  随礼状态口径一致）与防重入 `isSaving`，整批一次 `modelContext.save()`，
  落印只盖一次（全随礼用礼簿名首字印，其余含混合盖「礼」印，与 save() 同口径）；
  「保存并继续」开着时清字段续记并报「已保存 N 笔」。
- **智能粘贴**（BatchEntryView）：删掉自带 `AIResponse` 私有解码，改走 `AIParse.decode`，
  预览行映射不变（无效→failed 行、随礼→givenBlocked 行、uncertain 透传）——
  语音转写文本与粘贴文本自此共用同一条多笔管线。

### 单测（Tests/LiqianCoreTests/AIParseTests.swift，固定 JSON 喂解码器，不依赖网络）

- `testMultiPersonSentenceDecodesAllRecords`：3 人一句话 → 3 条，金额 200000/100000/50000 分、方向与关系/方式映射正确。
- `testFieldMappingWhitelistAndInvalidRecords`：88.5 元→8850 分、白名单外关系「表哥」过滤为 nil、eventHint 透传、无效条目标记与计数、uncertain 透传。
- `testUnreadableThrows`：非 JSON / 缺 records / records 类型错误均抛错。

## 自查

- 6 个改动文件括号配平全过（{}()[] 深度归零）。
- grep 无残留：`applyAIResult`、`AIResponse`、`QuickSentenceParseError`、`onParsed`、`RawResult` 均已清零。
- 未改数据模型与备份格式；未 commit/push；本机无 Swift 工具链，真编译与单测执行留待 CI。
