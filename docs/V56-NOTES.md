# v5.6 语音输入体验专业化：语音面板（真实电平声纹＋流式实时转写＋计时/取消/完成）

分支 `feat/v56-voice-panel`（基线 feat/v551-isolation-fix），版本 5.6.0/64。
用户原话（v5.5.1 真机验收后）：「好了，但是感觉不专业，没有实时转文字，
没有声纹，看看有没有成熟的借鉴」。

## 调研节（先调研后动手，出处与提炼）

查了五类成熟形态，提炼共性后再落本版设计：

1. **微信语音输入**：长按/点击说话，识别文字实时上屏；有独立复刻其
   语音输入法的实现笔记明说其波形「由实时音频 RMS 电平驱动、没有
   写死的假动画——声音大波形大、安静波形小」；微信语音消息另有上滑
   「取消 / 转文字」的双出口与 60 秒产品上限（上限是语音消息的产
   品口径，非转写能力口径）。
   - https://www.xiaogenban1993.com/blog/26.05/%E8%AF%AD%E9%9F%93%E8%BE%93%E5%85%A5%E6%B3%95
   - https://www.ithome.com/0/985/675.htm
2. **iOS 语音备忘录**：录音即有实时波形（真实拾音）＋红色录音指示
   ＋计时；展开录音视图可切到实时转写、当前词高亮；结束靠明确的
   停止/Done 动作收尾。
   - https://support.apple.com/guide/iphone/view-a-transcription-iph00953a982/18.0/ios/18.0
3. **iOS 系统听写 / 豆包语音输入**：未定稿文本以**灰色临时显示**在
   光标处、随说话不断更新，停止后最终文本转正式插入——「未定稿与
   已定稿视觉有别」是两家共用的关键细节。
   - https://docs.hagicode.com/guides/voice-recognition/doubao/
4. **苹果官方 SpeechAnalyzer 示例（WWDC25 session 277）与开发者
   实测**：volatile（未定稿）结果渲染为灰色、final（已定稿）用正
   常文本色，两段拼接呈现是这条新链的标准 UI 解法；会话以一次点
   按结束并 call finalize 冲刷最后的 volatile 结果（本 App v5.5
   起的收尾口径与此一致）。
   - https://dev.to/simple_memo/ios-26-speechanalyzer-what-i-learned-wiring-it-to-a-mic-f7p
   - https://github.com/m1kuapp/turn/blob/HEAD/docs/research/0023-turn-ios.md
5. **讯飞/微信团队的流式实践**：流式识别以约 200ms 一次的节奏吐
   中间结果——「边说边出」靠的是持续的中间结果流，不是等说完再
   整段贴上。本链的结果序列与电平推送（约 21–30 次/秒）均在此
   节奏量级。
   - https://cloud.baidu.com/article/4056322

**提炼共性（＝本版面板的验收标准）**：①录音是一个明确面板/浮层，
不是按钮变个颜色；②波形由真实声音电平驱动，安静时低平、说话时
起伏；③文字边说边出，未定稿部分与已定稿视觉有别；④有计时；
⑤有取消与完成两个明确出口，取消不留痕、完成才落字。

## 面板结构（新文件 Sources/LiqianApp/VoiceInputPanel.swift）

两入口（一句话记账、AI 问账）共用同一组件 `VoiceInputPanel`，
以 sheet 呈现（detents 0.55/medium、禁滑动误关、拖拽指示隐藏，
出口只有两个钮；sheet 被系统非正常回收时 onDismiss 兜底按取消
处理）。自上而下：

- **状态行**（四态）：录音中＝朱砂录音点＋「正在录音」＋右侧计时
  （0:00 起、等宽数字）；准备中（启动/资产下载）＝转圈＋人话
  （下载提示沿用 errorText 通道、在此按状态呈现）；结果流异常＝
  danger 图标＋人话（面板不关、可经「关闭」退出）；已点完成＝
  「正在收尾…」（等 finalize 冲刷交付，两钮禁用防重复点）。
- **声纹波形**（VoiceWaveformView）：42 根墨色柱、新电平从右侧
  进入向左滚出（语音备忘录式）、不满时左侧补零。柱高只由真实
  电平决定；唯一的 animation 是柱高变化的系统补间（0.09s），
  Reduce Motion 时关闭。波形对 VoiceOver 隐藏（状态由状态行播报）。
- **流式转写区**：定稿段墨色（Palette.ink）、未定稿段石色
  （Palette.stone）同段拼接，随新结果自动滚到底；空态一句占位
  人话。数据来自转写器新发布的 finalizedText/volatileText——
  TranscriptAccumulator 自 v5.5 起本就分两段累积，本轮**无需扩
  展它**，转写器只把两段同步发布出来。
- **底部出口**：「取消」＝Mat.regular 玻璃钮（异常态文案转「关
  闭」），点了即 cancelTranscription＋关面板，不落任何字；
  「完成」＝Mat.tinted 玻璃主钮（仅录音中出现），点了走
  finishTranscription：停录→收尾 finalize 冲刷→以最终全文一
  次交付调用方，最后一句不丢。

**接线与提交语义（与 v5.5.1 对照）**：两调用方删除原 `onText`
逐字回填，改走面板完成回调——一句话记账：全文进其文本框、待
点「解析」走原解析流；AI 问账：全文进输入框待发送、不自动发
问。与 v5.5.1 的 onText 末态逐字一致，只是落字时点从「边说边
填」收敛为「完成时一次交付」（这正是面板形态的题中之义：取消
可不留痕的前提就是录音中不先落字）。转写器的 onText 本身保留
原语义继续回调，不再有调用方依赖它回填。

**视觉纪律核对（DESIGN.md 定版）**：内容层（波形/文本/状态行）
纸墨平面零玻璃；玻璃只进底部两钮（功能层）；朱砂只落录音状态
点与完成主钮的系统染色（均走 Palette.primary 主题令牌、未写死
hex）；无深色控制台风；无装饰性假波形动画。

## 真实电平数据通道（算法口径）

- **采集点**：AnalyzerFeeder 的 tap 内、对**原始输入 buffer**
  （转换前）逐采样算全通道 RMS（float 直读、int16/int32 按满量
  程归一；平方和用 Double 累加防溢出；不分配任何对象）。
- **换算**（LiqianCore.VoiceLevelMath，纯函数＋8 个新单测）：
  dB = 20·log10(RMS)；静默地板 −50 dB → 0，0 dB → 1，线性映
  射钳制（日常说话 −20…−10 dB 落在 0.6…0.8 的明显起伏区）。
- **惯性（专业电平表 ballistics）**：attack 即时跟上（说话不迟
  滞）；decay 每步 ×0.72 滑落（停口后约 10 步滑到近零，不跳崖），
  且不跌破当前目标值（小声持续说话不被衰减吃掉）。
- **节流**：锁内累计帧数，间隔 ≥ 采样率/30 帧（约 1/30 秒）才
  推送一次。为让常规采样率也落在 20–30 次/秒，tap bufferSize
  由 4096 改为 2048（48kHz ≈ 23 次/秒、44.1kHz ≈ 21 次/秒；
  96kHz 靠节流阈值压回约 30 次/秒）。bufferSize 只是 tap 的分
  片大小，分析器按流消费、不按 buffer 边界对齐，喂入与转写语
  义不变；feeder 的启动/收尾次序与隔离结构未动。
- **回送**：经新增 @Sendable 电平钩子（既有钩子范式的第三例：
  trace/onFirstBuffer 之后）送回 SpeechTranscriber，回主执行者
  后追加进 @Published 环形缓冲（容量 42＝面板柱数，Task 内做代
  际校验，过期推送丢弃）。

## 计时口径（如实说明）

面板计时 0:00 起、每 0.25 秒刷新已录秒数、收尾取消计时任务。
**现行实时转写链没有任何 app 侧时长上限**（遍查 v5.5.1 代码：
无截断常量、无自动停录）——调研中见到的 60 秒是微信语音消息
的产品口径，不适用于「说一长句记账」的场景，本版不自设上限：
计时只如实报已录时长。若日后要加上限，属产品决策、另版再定。

## 隔离红线复核（动 feeder 前已读 V551-NOTES，本节为验收证据）

- feeder 保持 `nonisolated final class AnalyzerFeeder:
  @unchecked Sendable`，声明未动；
- tap 闭包捕获列表改后原文：
  `[gate, firstFlag, meter, converter, analyzerFormat, continuation, onFirstBuffer, onLevel]`
  ——较 v5.5.1 只增 `meter`（OSAllocatedUnfairLock 电平状态）与
  `onLevel`（@Sendable 钩子）两个 Sendable 值；无 self、无
  SpeechTranscriber、闭包体内无 `self.` 引用（仅 Self.rms /
  Self.convertBuffer 类型方法调用，与 v5.5.1 同范式）；
- 电平计算全部在 feeder 的 nonisolated 静态方法与 LiqianCore
  纯函数里完成，转写器侧只在 Task { @MainActor } 内追加数组；
- MicTrace.swift 与全部步号字面量未动（电平/面板不新增步号）。

## 隐私段落 rider（Legal.swift 第四节「语音识别」条）

按新链实情订正（文件转写路径分开表述，沿 v5.3.1 审计口径）：

- 改前：「…其中语音祝福的转写在本机进行；语音记账使用 iOS 系
  统语音识别服务，其对语音数据的处理适用 Apple 的隐私政策。…」
  ——「系统语音识别服务」是旧 SFSpeechRecognizer 链时代的表述，
  与 v5.5 起的 SpeechAnalyzer 本机链不符（旧口径可能暗示音频经
  Apple 服务处理）。
- 改后：「语音记账的实时转写使用 iOS 的本机语音识别
  （SpeechAnalyzer），全程在你的设备上完成，录音音频不会离开
  设备；语音祝福的转写同样只在本机进行。转出的文字如用于一句
  话记账、问账等 AI 功能，按第七节处理，音频本身不发送。」
  其中文件转写「只在本机」有代码据：BlessingAudio 的
  requiresOnDeviceRecognition = true。
- **版本号与生效日处理**：政策现行版本行仍为「版本 v2.0 · 生
  效日期：2026 年 11 月 16 日」——该版本尚未生效（本版构建于
  11 月 8 日，在生效日之前），本次属**生效前文本的事实订正**，
  原地修订、不升版本号、不改生效日；第七节及其他章节一字未动
  （转出文字用于 AI 的发送口径本就在第七节既有条目内，本条只
  加一句指引）。

## 不许动清单（核对）

SpeechAnalyzer 配置（显式 init/volatileResults/audioTimeRange）
与 AssetInventory 资产流程未动；AnalyzerFeeder 隔离结构与启动/
收尾次序未动（仅 bufferSize 与电平旁路，见上）；MicTrace 步号
未动；问答纪律与 draft_record 未动；Blessing 全链未动；
TranscriptAccumulator 未动（本就分定稿/未定稿两段）。

## 验收实测（2026-11-08 本机亲验）

- CI：run **42456058700 success**（Build/单测/预签断言/打包/上传
  全绿，含 `presign assertions passed` 口径与历版一致）。
- 单测：**229 个用例、0 失败**（v5.5.1 基线 221 ＋ 本轮新增
  VoiceLevelMath 8 个，VoiceLevelMathTests 套件单独 passed）。
- 解包验：App 与 Widget 的 Info.plist 均 **5.6.0/64**；PlugIns
  只有 LiqianWidget，**无 LiqianShare.appex**。
- 源码级隔离复核证据（可复现）：
  - `grep -rn "installTap" Sources/` 全仓**仅一处**：
    AnalyzerFeeder.swift:148；QuickSentenceView.swift 内
    installTap / AVAudioEngine() 均 **0 命中**；
  - tap 闭包捕获列表原文：
    `[gate, firstFlag, meter, converter, analyzerFormat, continuation, onFirstBuffer, onLevel]`
    ——无 self、无 SpeechTranscriber；
  - feeder 声明原文（AnalyzerFeeder.swift:36）：
    `nonisolated final class AnalyzerFeeder: @unchecked Sendable`；
  - MicTrace.swift 相对基线分支 **零改动**（步号体系未动）。
- 二进制抽查：App 主二进制中 `VoiceInputPanel`／`AnalyzerFeeder`
  相关符号共 198 处命中（面板与 feeder 均已进包）；中文步名未命
  中属 Swift 小字符串内联编码的历版同一现象，源码调用逐字在位。
- IPA：`~/workspace/your_files/liqian-v5.6/liqian-native-unsigned.ipa`
  （4,059,107 字节，未签名，SideStore 覆盖安装、数据不动）。

## 如实声明（不宣称已修好）

本版是体验形态改版：数据通道（真实电平）与面板均为新代码，CI
与解包只能证明「包对、测过」；波形是否真随声音起伏、灰/墨两段
是否如预期、取消是否真不落字，都要以真机实测为准（清单见上节）。
隔离红线与转写链语义未动，v5.5.1 的结案结论不受本版影响。

## 真机待验（装 v5.6 后）

1. 两入口点麦克风均上面板：说话时波形随声音起伏（大声柱高、
   小声柱低）、停口时波形缓落、静音时低平；
2. 文字边说边长：未定稿段灰色、定稿后转墨色，长句自动滚到底；
3. 计时自 0:00 正常走字；
4. 「取消」：面板关闭、两处输入框一字不落（原有内容不被动）；
5. 「完成」：最终全文（含最后一句）正确落入——一句话进文本框
   待解析、问账进输入框待发送，均不自动触发下一步；
6. 语音祝福录一段回归（Blessing 全链未动，作旁证）。
