# v5.5 麦克风闪退第五轮：旧语音管线整体退役，迁移 SpeechAnalyzer 新框架

分支 `feat/v55-speech-analyzer`（基线 feat/v542-mic-order），版本 5.5.0/62。

## 为什么迁移（真机证据链，不再是推定）

v5.4.2 按黑匣子钉死的窗口做了次序翻正（先建 recognitionTask 再启动
引擎），用户装机后点麦克风**仍闪退、诊断行仍停在 #14 引擎已启动**
（14:05:45）：`audioEngine.start()` 成功返回，首个 buffer 落标（18）、
0.5 秒存活标（19）、首个识别结果（15）都没到达。至此四轮全灭：

| 轮次 | 修的是什么 | 结果 |
|---|---|---|
| v2.7 | tap 格式校验、重入闸门、残留 tap | 未命中 |
| v5.4 | 代际、tap 竞态、音频会话 option、stop 幂等、识别器现建 | 未命中 |
| v5.4.1 | 授权同步快路（避 TCC 回调执行者陷阱）＋黑匣子取证 | 授权段排除，窗口钉死在引擎启动后 |
| v5.4.2 | 启动次序翻正（task 先行） | 死亡点没动 |

四轮的共同分母只剩旧管线本身（AVAudioEngine tap →
SFSpeechAudioBufferRecognitionRequest.append → SFSpeechRecognizer
实时识别）。按 V542-NOTES 预案整链换实现，不再给旧管线贴膏药。

## API 选型依据（按苹果官方文档核对，非凭记忆）

出处：苹果开发者文档 Speech 框架各页（SpeechAnalyzer /
SpeechTranscriber / AssetInventory / AnalyzerInput）、WWDC25
Session 277「Bring advanced speech-to-text to your app with
SpeechAnalyzer」、官方示例工程（Bringing advanced speech-to-text
capabilities to your app）。本机无法直开 developer.apple.com 的
DocC 页面，声明经两份逐字转引官方文档 JSON 的独立核查记录交叉
验证（类型声明、方法签名、async 属性均逐项对过）。

- **模块选 `SpeechTranscriber`，不选 `DictationTranscriber`**：
  前者是苹果为取代 SFSpeechRecognizer 推出新一代本机模型，官方
  摘要定位「normal conversation and general purposes」，WWDC25 与
  官方实时采音示例用的都是它；后者官方定位是旧听写模型的封装、
  「compatible with older devices」的兜底模块，识别质量上限就是
  旧引擎。本 App 的下游是 DeepSeek 对人名/金额的解析，识别准确率
  优先，故选新模型。代价：硬件门槛更高——`SpeechTranscriber
  .isAvailable == false`（老机型）时给明确人话错误、**不静默换
  引擎、不回退旧管线**；DictationTranscriber 兜底记为后备方向，
  真机若报 isAvailable=false 再评估，本轮不做。
- **配置用显式 init 不用 preset**：`SpeechTranscriber(locale:
  transcriptionOptions: [] , reportingOptions: [.volatileResults],
  attributeOptions: [.audioTimeRange])`——要什么语义在代码里写死，
  不依赖 preset 的内部组合（WWDC 视频里的 preset 名与发货 SDK
  曾不一致，有前科）。
- **结果语义**：`module.results` 是 `AsyncSequence<Result, Error>`；
  `Result.text: AttributedString`、`isFinal: Bool`——isFinal=false
  是 volatile（同短语临时猜测、整体改写），true 是定稿（只增不
  改）。累积口径：volatile 整体替换、final 顺序拼接，对外全文 =
  定稿＋volatile，与旧链「每次回调给全量文本」的 onText 语义
  一致。累积逻辑抽到 LiqianCore `TranscriptAccumulator` 并补单测。
- **喂入**：`SpeechAnalyzer` 是 actor；`start(inputSequence:)`
  消费 `AsyncStream<AnalyzerInput>`；分析器**不做任何格式转换**
  （文档明示），必须先经 `SpeechAnalyzer.bestAvailableAudioFormat
  (compatibleWith:)` 取目标格式、逐 buffer 用 AVAudioConverter
  转换后以 `AnalyzerInput(buffer:)` 喂入；转换器
  `primeMethod = .none`（官方示例口径，避免时间戳漂移）。
  `bestAvailableAudioFormat` 在资产未安装时返回 nil，故必须在
  资产就绪后调用。
- **收尾**：`finalizeAndFinishThroughEndOfInput()` 冲刷已喂入音频
  的最终结果；未 start 过的分析器直接释放即为合法结束（文档：
  finish 方法与释放二选一）。本实现 stop 后先 finish 输入流再
  finalize，flush 期间结果消费保持有效，最后一句不丢。
- **音频会话**：官方实时采音示例口径 `.playAndRecord` +
  `.spokenAudio`；旧链的 `.record` + `.measurement` 随旧链退役。
- **授权**：新框架各文档页与官方示例均未要求语音识别授权
  （示例工程只声明麦克风权限键）——本链只走麦克风授权，沿用
  v5.4.1 同步分流（已决同步读、未决经 nonisolated 桥）。plist 里
  NSSpeechRecognitionUsageDescription 保留：文件转写链
  （BlessingTranscriber）仍需要它。

## 资产安装流程（zh-CN）

1. `SpeechTranscriber.supportedLocale(equivalentTo: Locale
   (identifier: "zh-CN"))` 归一化 locale（官方论坛口径：直造的
   Locale 可能与系统资产对不上）；nil → 「不支持中文」人话错误。
2. `AssetInventory.status(forModules:)` 查状态并落面包屑：
   `.unsupported` → 明确错误；`.installed` → 直接继续；
   `.supported` / `.downloading` → 置 errorText 提示「正在准备
   语音模型，首次使用需要下载，请保持网络畅通…」（经既有
   isStarting/errorText 通道呈现），走
   `assetInstallationRequest(supporting:)` →
   `downloadAndInstall()`；抛错 → 「语音模型下载失败，请检查
   网络后重试；也可以直接输入文字」，**不回退旧管线**。
3. 资产就绪后才查 bestAvailableAudioFormat 并启动分析器。

模型是系统托管资产（跨 App 共享、系统自动更新），首次下载后
后续启动直接命中 `.installed`。

## 面包屑步号对照（MicTrace 机制不变，设置页诊断行照常显示）

新链（v5.5）：

| 步号 | 名称 | 步号 | 名称 |
|---|---|---|---|
| 1 | 点麦克风·开始启动 | 23 | 分析器格式就绪 |
| 2 | 新框架可用 | 24 | 音频会话已激活 |
| 3 | 同步读麦克风授权 | 25 | 读取输入格式 |
| 4 | 请求麦克风授权 | 26 | 已装 tap |
| 5 | 麦克风授权回调 | 27 | 分析器已启动 |
| 6 | 麦克风已授权（同步快路） | 28 | 首个音频已喂入分析器 |
| 20 | 语音模型资产状态 | 29 | 首个识别结果 |
| 21 | 语音模型下载开始 | 30 | 识别结果流结束/异常 |
| 22 | 语音模型已就绪 | 98/99 | 启动失败/启动异常 |

退役（旧 SFSpeech 链 v5.4.1–v5.4.2）：2 识别器探针、3 同步读授权
状态（含语音）、4–5 语音授权请求/回调、6 请求麦克风授权（旧编
号）、7 麦克风授权回调、10 进入 beginSession、11 音频会话已激活、
12 读取输入格式、13 已装 tap、14 引擎已启动、15 首个识别结果、
16 识别结束回调、17 识别任务已建、18 首个音频已流入识别、
19 引擎启动后存活确认。祝福录音链 101 起的步号不变。

判读：停在 20/21＝资产环节（下载中被杀/下载失败未走完）；停在
27 无 28＝引擎已转但音频没喂进分析器；停在 28 无 29＝音频在流、
分析器没出结果；停在 29 后＝已出字，问题转到识别进行中/收尾段。

## 与旧链的差异清单

- 移除：`SFSpeechAudioBufferRecognitionRequest`、
  `SFSpeechRecognizer` 实时实例与 `recognitionTask`、
  `request.endAudio()`、语音识别授权分流、`.record`/`.measurement`
  会话口径、旧步号 2–19。源码中 `SFSpeechAudioBuffer
  RecognitionRequest` 仅剩 QuickSentenceView.swift 退役说明注释
  两处提及（306–313 行），无任何代码引用。
- 新增：`Speech.SpeechTranscriber` 模块＋`Speech.SpeechAnalyzer`
  会话＋`AsyncStream<AnalyzerInput>` 喂入＋AVAudioConverter 转换
  ＋AssetInventory 资产流程＋`TranscriptAccumulator`（Core）及
  其 6 个单测。
- 保留：对外接口（start/stop/toggle、isRecording/isStarting/
  errorText、onText 全量文本语义）与两个调用方零改动；代际作废、
  tap 接受旗、首 buffer 原子旗落标、格式校验先行、MicTrace 机制；
  两个 nonisolated 授权桥（`requestRecordPermissionBridge` 仍被
  BlessingRecorder 共用；`requestSpeechAuthorizationBridge` 本链
  不再调用、保留供旧文件转写路径按需取用）。
- 不动：BlessingRecorder / BlessingTranscriber（录文件＋
  SFSpeechURLRecognitionRequest 文件转写，从未闪退）、问答纪律、
  draft_record、其余全部功能；plist 权限文案全保留。

## 隐私口径变化（留给主会话跟进，本轮未动政策文本）

旧链 SFSpeechRecognizer 未强制本机识别，识别可能走苹果服务器；
新链 SpeechAnalyzer 为全程本机识别、音频不出设备。v5.3.1 隐私
政策里语音识别段落的表述建议随本版一并复核更新。

## 如实声明（不宣称已修好）

本轮是整链换实现：闪退的共同分母（旧管线）在代码层面已不存在，
但没有真机验证前不宣称治愈。真机待验：

1. 问账页、一句话记账页点麦克风：直接进入识别、说话实时出字，
   点停止后最后一句完整落到输入框；
2. 首次使用若弹「正在准备语音模型…」：保持网络，等下载完成自动
   进入识别（下载只发生一次）；
3. 若仍闪退：重开 App → 我的 → AI 管家 → 拉到底截「语音诊断」
   一行回传（看新步号停在哪：20/21 资产、28 喂入、29 结果）；
4. 语音祝福录制回归一次（本轮未动，顺手确认）。

## 验收实测

（待 CI 与解包验后回填。）
