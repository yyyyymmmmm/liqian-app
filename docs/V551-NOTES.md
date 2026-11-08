# v5.5.1 麦克风闪退第六轮：按 .ips 栈动刀——清除框架回调的 MainActor 隔离污染

分支 `feat/v551-isolation-fix`（基线 feat/v55-speech-analyzer），版本 5.5.1/63。
提交：ef01959 结构搬迁主体 / df1b33d 补 import os / 本 NOTES 回填。

## 两份崩溃日志（用户真机发回，本轮动工前逐字核过）

同型：`EXC_BREAKPOINT (SIGTRAP)`、`Trace/BPT trap: 5`，故障栈同头：

```
libdispatch.dylib  _dispatch_assert_queue_fail
libdispatch.dylib  dispatch_assert_queue
libswift_Concurrency.dylib  _swift_task_checkIsolatedSwift
libswift_Concurrency.dylib  swift_task_isCurrentExecutorWithFlagsImpl
```

- **LiqianApp-2026-11-07-190050.ips**（旧版，故障线程 7，
  queue=com.apple.root.default-qos）：
  `SpeechTranscriber.start()` 的 closure #1 ←
  `TCC __TCCAccessRequest_block_invoke_8` ← XPC 回复链。
  ——语音授权回调被 TCC 从 XPC 线程投递，进闭包序言即被击杀。
- **LiqianApp-2026-11-08-141608.ips**（v5.5，故障线程 4，
  queue=RealtimeMessenger.mServiceQueue）：
  `SpeechTranscriber.installCapture(analyzerFormat:continuation:generation:)`
  的 closure #3 ← `AVAudioNodeTap::TapMessage::RealtimeMessenger_Perform()`。
  ——即 installTap 的 tap 闭包，被 AVFAudio 从实时音频队列调用，
  同样死在序言。故 v5.5 面包屑永远停在 #27：28 的落标代码在闭包
  正文里，正文根本没机会跑。

## 根因（定版）

`SpeechTranscriber` 是 `@MainActor` 隔离类型。它在自身方法里形成
并交给框架的闭包，继承了 MainActor 隔离、自带执行者断言序言
（`swift_task_isCurrentExecutor`）；框架从自有队列（TCC 的 XPC
线程、AVFAudio 的 RealtimeMessenger 队列）调用时，序言检查必
失败 → `_dispatch_assert_queue_fail` → EXC_BREAKPOINT。

这解释了此前五轮为何全灭：v2.7/v5.4 的格式与竞态修、v5.4.1 的
授权快路、v5.4.2 的启动次序、v5.5 的整链换框架——改的全是闭包
**正文**或正文之外的编排，序言一个字没动；且每轮只是让死亡点在
不同回调之间搬家（授权回调 → 识别结果回调 → tap 闭包）。

## 修法（结构隔离，不是给闭包加标注）

### ① 采音喂入整体搬出隔离区——新建 `Sources/LiqianApp/AnalyzerFeeder.swift`

`nonisolated final class AnalyzerFeeder: @unchecked Sendable`，持有
AVAudioEngine、tap、AVAudioConverter、AsyncStream continuation、
接受旗/首包旗（OSAllocatedUnfairLock）。`SpeechTranscriber`
（保持 @MainActor、UI 状态与编排不变）只同步调用 feeder 的
`startCapture / startEngine / stopCapture / finishInput /
deactivateSession`。

- tap 闭包只在 feeder 方法内形成，**显式捕获列表**＝
  `[gate, firstFlag, converter, analyzerFormat, continuation, onFirstBuffer]`
  ——两个锁＋本次调用的局部值，无 self、无 SpeechTranscriber、
  无任何 @MainActor 状态；框架在任何线程调用都没有隔离序言可断言。
- 步号 24/25/26 经 feeder 的 `TraceHook`（@Sendable）在
  startCapture 同步执行时逐点回调转写器落 MicTrace：落点次序、
  失败点精度（哪一步抛错、之前步号已落）与 v5.5 直落一致。
- 步号 28 经 feeder 的 `@Sendable onFirstBuffer` 钩子：钩子在转写器
  侧以内建 `Task { @MainActor }` 回主执行者落标（合法跳板），
  代际校验口径不变。
- 线程模型：feeder 的裸状态字段只在调用方串行上下文（转写器
  MainActor 同步直调、不跨 await）读写；音频线程只碰两个锁与
  捕获的局部值。`@unchecked Sendable` 按此模型担责，文件头有全文。
- 抛错口径（LiqianSpeech code 1/2）、会话类别（.playAndRecord +
  .spokenAudio）、bufferSize 4096、converter primeMethod=.none、
  收尾次序（关旗→停引擎→摘 tap→finish 输入流→finalize 冲刷→
  停用会话）全部与 v5.5 一致，未动语义。

### ② convertBuffer 的纯逻辑抽到 Core

容量计算（帧数 × 采样率比截断 +1）抽为
`LiqianCore.AudioConvertMath.outputFrameCapacity`，feeder 的
convertBuffer 调用它；补 6 个单测（下采样/整除/上采样/等速率/
极小 buffer/非法入参）。

## 框架回调清点表（语音功能全量，逐个去隔离）

范围：QuickSentenceView（实时转写）、BlessingAudio（祝福录/播/
文件转写）、VoiceBlessingView、AdvisorView、AISettingsView 五个
文件内的全部框架回调点。每个点写明原隔离来源与改后形态。

| # | 回调点 | 原隔离来源 | 框架投递线程 | 改法 | 改后 |
|---|---|---|---|---|---|
| 1 | installTap 的 tap 闭包（本轮主犯，11-08 .ips 点名） | 在 @MainActor 类 SpeechTranscriber 的方法 installCapture 内形成，继承 MainActor 隔离 | AVFAudio RealtimeMessenger 队列 | 结构搬迁：整体移入 nonisolated AnalyzerFeeder，闭包显式捕获白名单（见上），转写器只调 feeder 方法 | 闭包在 nonisolated 上下文形成，无执行者序言；捕获 0 个隔离对象（源码证据见验收节） |
| 2 | 麦克风授权桥 requestRecordPermissionBridge（SpeechTranscriber、BlessingRecorder 两处调用） | 桥本体 v5.4.1 已定版 nonisolated static、入参 `@escaping @Sendable`；调用点闭包按 @Sendable 形参成形、不继承隔离，正文只建 Task 回 MainActor | TCC XPC 回复线程 | 复核确认已达标，**不改**（本轮逐字复查桥声明与两处调用点） | nonisolated，安全 |
| 3 | 语音授权桥 requestSpeechAuthorizationBridge | 同上（nonisolated static + @Sendable 入参） | TCC XPC 回复线程 | 复核确认已达标，**不改**（实时链已不调用它，文件转写链经 Runner 自己的 withCheckedContinuation 调用，见 #4） | nonisolated，安全 |
| 4 | BlessingTranscriber 的 SFSpeechRecognizer.requestAuthorization 回调＋SFSpeechURLRecognitionRequest 的 recognitionTask handler | 原先就长在无标注的 enum BlessingTranscriber 内——本工程无默认隔离设置（Project.swift 只有 SWIFT_VERSION，隔离只来自显式 @MainActor），**经查并无 MainActor 污染**；但与外层同文件、靠「碰巧没标注」保命 | Speech 框架自有队列 | 按预案结构化定版：执行体整体抽进独立的 `private enum BlessingRecognitionRunner`（nonisolated），授权与识别 handler 只许在此形成；结果经 CheckedContinuation 回调用方 async 上下文；入口 BlessingTranscriber.transcribe 只做转发，语义（locale/on-device 旗/final 口径/失败返 nil）逐字不变。防的是日后外层被标 @MainActor 时污染复发 | 执行体隔离自由由类型结构保证，不再依赖外层标注状态 |
| 5 | BlessingRecorder 的录音回调面 | 查清：**BlessingRecorder 从未给 AVAudioRecorder 设置 delegate**（全仓仅 BlessingPlayer 有 `p.delegate = self`），不存在 AVAudioRecorderDelegate 回调点；录制完成靠 stop() 同步读 currentTime。其余两个闭包：(a) 授权桥闭包——同 #2，安全；(b) Timer.scheduledTimer 计时闭包——在 @MainActor 方法内形成，但 Timer 只在调度它的 run loop（主 run loop）触发，纵有隔离序言也必在主执行者上通过，且正文只建 Task 回 MainActor 读状态 | Timer＝主 run loop；桥＝TCC 线程 | 无 delegate 可桥接，**不改**；Timer 与桥闭包维持现状并在此定版结论 | 安全（无框架异线程投递面） |
| 6 | BlessingPlayer 的 AVAudioPlayerDelegate.audioPlayerDidFinishPlaying | 方法长在 @MainActor 类上，但 v4.2 起已声明为 `nonisolated` 并在正文首行建 Task 回 MainActor——正是本轮推广的范式 | AVAudioPlayer 内部队列（不保证主线程） | 复核确认已达标，**不改**（文件内先行范例） | nonisolated 方法＋Task 跳板，安全 |
| 7 | AVAudioConverter 的 inputBlock 闭包（convertBuffer 内） | v5.5 时已是 nonisolated static 方法内的闭包，只捕获 delivered 旗与入参 buffer | 转换器在调用方线程（tap 音频线程）同步调用 | 随 convertBuffer 一并迁入 nonisolated AnalyzerFeeder（静态方法），形成上下文不变 | nonisolated，安全 |
| 8 | SpeechAnalyzer 资产/启动面：AssetInventory.status/downloadAndInstall、analyzer.start、module.results 消费 | 均为 async API（编译器续体），非闭包回调；results 消费是本方 `Task { @MainActor }` 主动拉取 | 本方任务执行者 | 无回调可去隔离，**不改**（列入清单以示清点完整） | 不适用 |
| 9 | NotificationCenter | 语音功能五文件内只有一处 `post`（QuickSentenceView 发 .liqianOpenAISettings 通知），**没有任何 block 观察者注册**；全仓的 block 观察者在 CloudSync/SceneModeView，不属语音功能、不在本轮范围 | — | 无此回调点，**不改** | 不适用 |

## 不许动清单（核对）

SpeechAnalyzer 配置（SpeechTranscriber 显式 init、volatileResults、
audioTimeRange）与 AssetInventory 资产流程未动；TranscriptAccumulator
未动；问答纪律与 draft_record 未动；UI 与状态语义（isRecording/
isStarting/errorText/onText 全量语义）未动；MicTrace 步号体系未动
（24/25/26 改经 trace 钩子落标、28 改经首包钩子落标，步名与编号
一字未改）；Blessing 录音/播放/文件转写语义未动（仅转写执行体
换了容身的类型）；基线不变（不带 Share 扩展、CI 预签断言）。

## 验收实测（2026-11-08 本机亲验）

- CI：首轮 run 42454845077 构建失败——仅 AnalyzerFeeder 两处
  `cannot find 'OSAllocatedUnfairLock' in scope`（该符号在 os
  模块，feeder 漏 import；旧文件靠其他 import 传递可见），
  df1b33d 补 `import os` 后第二轮 run **42454938122 success**
  （Build/单测/预签断言/打包/上传全绿，日志含
  `presign assertions passed (2 binaries)`；日志中 2 处 `error:`
  命中均为工作流自身 grep 命令的回显，非构建错误）。
  `nonisolated final class` 声明被当前工具链直接接受、无相关报错。
- 单测：**221 个用例、0 失败**（v5.5 基线 215 ＋ 本轮新增
  AudioConvertMath 6 个，日志中 AudioConvertMathTests 全过）。
- 解包验：App 与 Widget 的 Info.plist 均 **5.5.1/63**；PlugIns
  只有 LiqianWidget，**无 LiqianShare.appex**。
- 二进制抽查（App 主二进制原始字节）：`AnalyzerFeeder` 37 处
  命中（新类已进包）；步名「首个音频已喂入分析器」「音频会话
  已激活」命中；「已装 tap」未命中属 Swift 小字符串内联编码的
  历版同一现象（24/25/26 改为经钩子传字符串字面量，源码调用
  逐字在位，见下条源码证据）。
- **源码级隔离复核证据**（本轮核心断言，可复现）：
  - `grep -rn "installTap" Sources/` 全仓**仅一处**：
    AnalyzerFeeder.swift:128；QuickSentenceView.swift 内
    installTap / AVAudioEngine() 均 **0 命中**——转写器已不直接
    碰引擎与 tap。
  - tap 闭包捕获列表原文：
    `[gate, firstFlag, converter, analyzerFormat, continuation, onFirstBuffer]`
    ——无 self、无 SpeechTranscriber；闭包体内 `self.` 引用
    **0 处**（仅有 `Self.convertBuffer` 类型方法调用）。
  - feeder 声明原文（AnalyzerFeeder.swift:35）：
    `nonisolated final class AnalyzerFeeder: @unchecked Sendable`。
- IPA：`~/workspace/your_files/liqian-v5.5.1/liqian-native-unsigned.ipa`
  （4,016,262 字节，未签名，SideStore 覆盖安装、数据不动）。

## 真机判读法（装 v5.5.1 后）

1. 问账页、一句话记账页点麦克风：应直接进入识别、说话出字，
   点停止后最后一句完整落入输入框；语音祝福录一段并等转写
   出现（验 #4 的 Runner 迁移无回归）；祝福播放一条（验 #6）。
2. 若仍闪退：重开 App → 我的 → AI 管家 → 拉到底截「语音诊断」
   一行，并按老路径发回当次的 .ips。这次的栈**不应该**再出现
   `swift_task_isCurrentExecutor` 砸在语音闭包上；诊断行判读：
   停在 24/25/26＝feeder 启动段（会话/格式/tap 装配）出事；
   停在 27 无 28＝引擎或分析器启动段；**28 已落**＝tap 闭包已
   活过首包——五轮以来从未到达的位置，若死在 28 之后，问题
   已换性质，按新栈另案处理。

## 如实声明（不宣称已修好）

这是六轮里第一轮有 .ips 栈逐帧对位支撑的修法：两份日志点名的
两个闭包（授权回调、tap 闭包）一个已复核定版、一个已结构搬迁，
且源码级复核可复现。但真机点麦克风出字之前，不下治愈结论——
结案标准只有一个：用户真机点麦克风、说话出字。
