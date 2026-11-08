# v5.4.1 麦克风闪退第三轮：取证面包屑＋授权执行者陷阱

分支 `feat/v541-mic-forensics`（基线 feat/v54-five-fixes），版本 5.4.1/60。

## 背景

v2.7、v5.4 两轮代码审计推定修复后，用户装 v5.4 真机点麦克风**仍闪退**，
且明确反馈「没有弹权限申请」。主会话已亲验：v5.4 包内 Info.plist 的
NSMicrophoneUsageDescription 与 NSSpeechRecognitionUsageDescription
都在、文案正确——**不是缺权限文案被系统杀**。本轮换打法：不再猜，
先埋点取证，同时把剩余面全审一遍，审出新的可疑点就修。

用户这句「没弹权限申请」是关键线索：他早在旧版本就授权过语音与
麦克风，本机两项授权都是**已决（已授权）**状态——点麦克风本来就
不该再弹框。于是问题收敛为：在「授权已决」的路径上，代码做了什么
会直接崩的事？

## 本轮坐实/修复（3 项）

### 修复 1（强候选主因）：授权回调的执行者陷阱（iOS 26 + Swift 6）

旧 `SpeechTranscriber.start()` 无论授权状态如何，一律走
`SFSpeechRecognizer.requestAuthorization { … }` →
`AVAudioApplication.requestRecordPermission { … }` 两段异步回调。

公开同形案例（emergent-inc/mosaic 仓库的 iOS dictation 修复 commit，
2026 年）明确记录了这一崩法：这两个授权 API 的回调由 TCC 在 **XPC
回复线程**投递；若回调闭包被编译器推断为 `@MainActor` 隔离（闭包写在
`@MainActor` 类内部、捕获隔离状态时正是如此——本类两段回调都是这个
形状），Swift 6 运行时会在回调入口做执行者检查，
`swift_task_isCurrentExecutor` → `dispatch_assert_queue_fail`
（EXC_BREAKPOINT）直接陷阱。且该陷阱**专挑授权已决时触发**（未决时
回调路径不同），与用户「不弹框＋点就闪退」严丝合缝。

修法（与公开修复同构）：
- **同步快路**：`start()` 先同步读 `SFSpeechRecognizer.authorizationStatus()`
  与 `AVAudioApplication.shared.recordPermission`。语音已授权＋麦克风
  已授权 → 直接 `beginSession`，一个异步回调都不发；已拒绝/受限 →
  直接给人话报错收尾。只有**未决**才发请求。
- **nonisolated 桥**：真正需要请求时，经
  `SpeechTranscriber.requestSpeechAuthorizationBridge` /
  `requestRecordPermissionBridge`（`nonisolated static`、回调
  `@Sendable` 非隔离），回主执行者靠显式 `Task { @MainActor in }`。
- `BlessingRecorder.start()` 同病同治：先同步读 recordPermission 分流，
  未决时也走同一个 nonisolated 麦克风桥。

### 修复 2：setActive(true) 带了只对停用有效的 option

`beginSession` 旧写法 `setActive(true, options: .notifyOthersOnDeactivation)`：
该 option 在 AVAudioSession 文档口径里只对**停用**有效（同一公开来源
指出，激活时传它在严格执法的系统上会抛错）。虽被 do/catch 兜成报错、
不算闪退，但属无谓失败点。改：激活 `setActive(true)` 不带 option，
停用侧（stop）保留原 option。

### 修复 3：识别器无强引用 ＋ BlessingRecorder 吞了 record() 返回值

- v5.4 为并发安全改「beginSession 内现建识别器」后，recognizer 只是
  局部变量，recognitionTask 存续期间无人强引用（苹果官方示例都是
  属性持有）。补 `activeRecognizer` 属性，beginSession 赋值、stop 清空。
- `BlessingRecorder.beginRecording` 旧代码丢弃 `rec.record()` 的 Bool
  返回：返回 false 时界面会假装在录（计时走字、文件是空的）。改：
  检查返回值，false 即报错收尾。

## 取证面包屑（MicTrace，本轮的另一半交付）

`Sources/LiqianCore/MicTrace.swift`（Core 层、6 个新单测）：
每一步用 UserDefaults 同步写（set 后 synchronize()，保证进程被杀前
标记已落盘），键 `micTrace`（最新步：步号＋名称＋详情＋时间）＋
`micTraceOpen`（会话未正常结束旗）。

- SpeechTranscriber 步号：1 点麦克风 → 2 探针 → 3 同步读授权状态
  （详情带两项状态 rawValue）→ 4/5 请求语音授权与回调 → 6/7 麦克风
  快路/请求与回调 → 10 进 beginSession → 11 会话已激活 → 12 输入
  格式（详情带采样率/声道）→ 13 已装 tap → 14 引擎已启动 → 15 首个
  识别结果 → 16 识别结束回调；异常 98/99。
- BlessingRecorder 步号：101 点录制 → 102 授权分流 → 103 授权回调 →
  104 进 beginRecording → 105 会话已激活 → 106 录音器已创建 →
  107 录音中/record() 失败 → 108 异常。
- 会话正常结束（stop/录完/优雅失败）都会 close() 清旗；**从未启动过的
  stop() 不许 close**（traceArmed 武装位守着），免得页面 onDisappear
  抹掉上次闪退留下的标记。
- **显示**：App 启动后若发现上次会话未正常结束，AI 管家设置页底部
  出现「语音诊断」一节，一行摘要：上次流程停在第几步（含详情）。
  平时整节不显示。

下次若还闪退，取证走双路：①用户把设置页诊断行截图发来（停在哪步
一目了然）；②系统 设置→隐私与安全性→分析与改进 里的礼记 .ips
崩溃日志。两路对上就能定点修，不再整链重审。

## 排除/坐实表（剩余面全审结论）

| # | 审计面 | 结论 |
|---|---|---|
| ① | AdvisorView 麦克风按钮 tap 路径 | **排除**。按钮是普通 Button(.plain)，全页无 TapGesture/手势叠加、无 FocusState 与 scrollDismissesKeyboard，输入坞在 ScrollView 之外不存在滚动手势抢点；onDisappear 的 stop() 有代际作废＋traceArmed 守卫，不误伤。按钮 disabled 只挂 isStarting，无吞点路径。 |
| ② | 已拒绝/受限状态下两授权 API 的衔接 | **排除（且已改得更稳）**。官方文档口径：已拒绝时 requestRecordPermission 回调立即以 false 返回（可能在任意线程——这正是修复 1 要避开回调的另一理由）；旧代码收到 false 后只置 errorText、不碰引擎，衔接本身没问题。本轮改同步读状态后，已拒状态连回调都不发，直接报错。 |
| ③ | iOS 26 上 SFSpeechRecognizer 与 .measurement 模式 | **无官方弃用/回归记录**。依据：SFSpeechRecognizer 在 iOS 26 未被弃用（新 SpeechAnalyzer 是并行新框架，非替代弃用）；.measurement 是录音类会话的长期标准模式，公开问题只涉及它与播放共存时的音量路由（听筒出声），与本例「点麦克风即闪退」无关。故 .measurement 不动；本轮真正命中的 iOS 26 议题是修复 1 的执行者陷阱（Swift 6 运行时检查＋TCC 回调线程）。 |
| ④ | BlessingAudio 录制/转写路径（VoiceBlessingView） | **坐实 1 项并已修**（修复 3 的 record() 返回值）。其余排除：录制入口只调 recorder.start() 一条链；转写是录后文件型识别、失败一律 return nil 不阻塞保存；BlessingRecorder 的 setCategory(.playAndRecord)＋setActive(true) 本就无非法 option。 |
| ⑤ | 全部语音文件强制解包/越界/onText 链再扫 | **排除**。QuickSentenceView/BlessingAudio/VoiceBlessingView/AdvisorView 四文件零 try!/as!/强制解包（grep 命中的均为布尔取反）；唯一数组下标是 BlessingAudioStore.directory 的 urls(...)[0]，iOS 平台契约保证 applicationSupportDirectory 至少返回一条，属理论项、不动。onText 回调链：识别回调经代际校验后可选调用（onText?），两处赋值都是弱引用捕获的视图状态赋值，无环无越界。 |

另：音频中断（来电等）无 interruption 观察者——中断会让识别以
error 回调收尾走 stop()，是功能降级不是闪退，本轮不动、记在此处。

## 未动清单

- 问账/记账/工具纪律、AdvisorChatStore、RollingMoneyText 等 v5.4
  其余四修零改动；BlessingTranscriber 不埋面包屑（录后文件转写、
  非点麦克风路径，且与录制会话并发写标记会互相污染步号）。
- .measurement 模式保留（见排除表 ③）。

## 验收实测（2026-11-08 本机亲验）

- CI：首跑 run 42451454882 红——`requestRecordPermission` 回调变体
  缺 `completionHandler:` 标签的编译错误（1 行），修复后重跑
  run **42451541288 success**（`** BUILD SUCCEEDED **`、
  `** TEST SUCCEEDED **`、`presign assertions passed (2 binaries)`）。
- 单测：**209 个唯一用例全过、0 失败**（基线 203＋MicTraceTests 6 例：
  从未用过无摘要、落步开会话且摘要带步号、最新步覆盖、close 清摘要、
  close 后再 mark 重新武装、详情进条目）。
- 解包验：App 与 Widget 均 **5.4.1/60**；PlugIns 只有 LiqianWidget，
  **无 LiqianShare.appex**；包内 Info.plist 麦克风/语音识别文案仍在。
  原始字节抽查：Core 二进制命中 `micTrace`/`micTraceOpen` 键与
  「上次用麦克风时」诊断文案；App 二进制命中「点麦克风·开始启动」
  「同步读授权状态」「祝福录音·点录制」「会话正常结束」等步名与
  诊断节页脚长文案（「语音诊断」四字标题为 Swift 小字符串内联编码
  未命中，与历版同一现象）。
- IPA：`~/workspace/your_files/liqian-v5.4.1/liqian-native-unsigned.ipa`
  （3,998,458 字节）。

## 真机待验（不宣称闪退已修）

本轮的立场：**要么修掉（修复 1 是迄今最贴合症状的坐实级候选），
要么让下次闪退自报死步**。装 v5.4.1 后请用户：
1. 问账页与一句话记账页点麦克风各试一次：已授权应直接开始听、
   不弹框、不闪退；
2. 语音祝福录一段并保存、回放；
3. 若仍闪退：重开 App → 我的 → AI 管家 → 拉到底看「语音诊断」
   一行，连同停在的步号截图发回；有条件再附系统分析里的 .ips。
