# v5.14.0 全原生整改（三期全包）施工笔记

- 基线：feat/v513-lang-ui 顶端 a1c32a0；分支 feat/v514-native-pass，独立 worktree 作业。
- 依据：`~/workspace/liqian-review/native-audit.md`（不合格清单 8 项＋分期建议）。
- 范围说明：原简报只含第 1＋2 期、记一笔与落印列第 3 期禁区；**用户于施工当日（2026-11-09）提前裁完第 3 期、简报追加并入本版**，故本版三期全包，下方按期分开销账。
- 版本：App/Widget 的 Info.plist 字面量（Project.swift 三处口径）升 5.14.0/81。

## 第 1 期 · 低风险局部替换

1. **图表页范围选择器**（审计 #1）：自绘 HStack＋Capsule＋matchedGeometryEffect(rangePill)＋手写阴影整段删除 → 系统 `Picker`＋`.pickerStyle(.segmented)`（与全 App 其余 8 处分段同款）；年份 Menu 行与 `.sensoryFeedback(.selection)` 保留；`@Namespace rangeNamespace` 一并删除。
2. **图表页占比条**（审计 #4）：自绘 ShareBar（GeometryReader 手算段宽）→ `ShareStackBar`：Swift Charts 单行堆叠 BarMark（x 域 0…1、轴/图例全隐、整体 3pt 圆角裁切）；段内百分比（≥16% 才标）、双色阶、入场生长（entrance 缩放 fraction）与无障碍汇总文案全保留。差异一处：旧版 2pt 段缝不再复刻，堆叠条以段界色差分段（系统图表惯例）。
3. **大场模式写死字号**（审计 #5 的 BatchEntry 部分）：BatchEntryView 17/20/34pt 共 9 处 `.font(.system(size:))` 清零 → `.dynamicTypeSize(effectiveTypeSize)` 环境注入；保底档走 Core `TextSizeScale.bigModeTargetIndex`（新函数＋单测）：保底 accessibility2（下标 8），比 App 内「特大」档（accessibility1）高一档、只设保底，与 v5.13 机制同源。映射说明：旧写死 34pt 金额 ≈ .largeTitle 在 AX2 档的 ≈33pt；旧 17/20pt 的各行文字改由各自语义档按系统比例放大，不再逐处对位。金额格宽度（96/150）与行高（44/76）改由生效字号是否辅助功能档推导，不再读 bigMode 布尔。
4. **同心圆角**（审计 #7）：Components 封面小签（LedgerCoverCard.coverBlock，卡内 cardPadding 边距内嵌、容器 coverCorner——系统同心机制的标准场景）手算 `LiqianRadius.concentric` → iOS 26 `ConcentricRectangle`。**保留一处并记理由**：OnboardingView 礼谱封面意象里的小签是居中构图（VStack 居中排布、非边距内嵌），同心机制按实际边距推导会把圆角推向 0、与定版 4pt 不符，故该处保留 `LiqianRadius.concentric` 推导函数（函数因此保留，全仓仅剩此一处调用）。
5. **散落动画字面量**（审计 #6 散落部分，3 处）：
   - ChartsView 入场 `.easeOut(duration: 0.7)` → 系统 `.default`（Reduce Motion 分支不变）；
   - VoiceInputPanel 滚底 `.easeOut(duration: 0.15)` → 系统 `.default`；
   - RecordFormView 金额光标 `.easeInOut(duration: 0.55).repeatForever` → 随自绘光标 AmountCaret 在第 3 期整段删除（系统 TextField 自带光标），字面量自然消亡。

## 第 2 期 · 结构归位

6. **人物详情页 List 化**（审计 #3）：整页 ScrollView＋VStack 手堆卡片 → `List`＋`.listStyle(.insetGrouped)`（与 LedgerDetailView 同构），背景 groupedBackground 不变、底部 safeAreaBar 双按钮不动。构成：统计头（Section 单行）、重要日子（Section＋header，日子逐行＋管理提醒 NavigationLink）、回礼参考（Section＋header）、往来记录（Section 真列表行：系统分隔，点行编辑、左滑删除/编辑、长按四动作——编辑/签名/语音祝福/删除——全保留且与 LedgerDetail 同序；行增删 `.animation(.snappy)` 口径随 Section 保留）。空态 ContentUnavailableView 入 Section 透明行底。原手绘 hairline Divider 与逐行手算 padding 随归位删除（系统行距/分隔承接）。
7. **动效令牌瘦身**（审计 #6 令牌部分）：`MotionTokens` 四档整层退役并删除枚举——
   - pageCrossfade：AdvisorView 4 处＋OnboardingView 1 处调用点 → 系统 `.default`（Reduce Motion 时 nil 的原口径逐处保留）；
   - liquidSpring：唯一调用点在图表自绘分段内，已随第 1 期删除；
   - press：唯一宿主 ScaleOnPressButtonStyle，已退役（见下）。
   **ScaleOnPressButtonStyle 退役**：组件本体删除；调用点 7 处（HomeView 4、LedgersView 1、RecordFormView chips 2）一律去掉该样式、回系统默认按钮样式（automatic）：所在皆为 List/Form 行语境，系统行高亮即按压反馈；FAB 等玻璃按钮本走系统玻璃形变、未受影响。
8. **卡面阴影 LiqianElevation**（审计 #8，观察项）：随人物详情 List 归位后复核全仓调用点——仅剩首开引导封面意象（OnboardingView）一处 `card` 档在用：那是静态内容意象（礼谱封面造型）、非列表卡面，系统无等价的静态意象投影，**保留 card 档并记此理由**；`floating` 档自 v5 玻璃收敛后已无任何调用点，本期随归位删除（删的是死代码，非为清零而清零）。

## 第 3 期 · 用户提前拍板并入

9. **记一笔表单**（审计 #2）：容器 ScrollView＋VStack 手堆 → 系统 `Form`：方向 segmented＝独立 Section；主表单＝Section 单行（行底显式保留纸墨令牌色 Palette.card/baiCard、行内边距沿 cardPadding，「一张纸」的身份由系统分组表面＋令牌底色共同承接）；活礼谱 RecordLiveMediaSection（编辑态）＝独立 Section、自有表面以透明行底＋零行距原样嵌入；保存并继续/删除各成 Section。字段、校验、落印 overlay、四种 init（含 **v5.12 宾客回执预填 init＋onSavedNewRecord 回调**，源码守卫钉死）一字未动。
10. **自绘金额键盘整段删除**：面板 amountKeypadPanel、键面 LazyVGrid、删除键点按/长按手势拼装、keypadInput 输入函数、自绘光标 AmountCaret 全删；金额改真 TextField＋系统 `.keyboardType(.decimalPad)`，FocusState 三面（姓名/金额/备注）自此全走系统键盘。金额显示写死 44pt → 自家语义金额口径 `.liqianMoney(.largeTitle)`（定版「记账大字显示」档），¥ 符号走 `.liqianMoney(.title2)`。旧键盘的输入合法性约束（至多两位小数、整数至多 7 位、不留前导零、首位 "." 补 0）由 Core 新纯函数 `AmountInputText.sanitized` 在 onChange 承接（单测覆盖 13 例），保存侧 Double 校验不变。
11. **落印 sealIn**：印章图形本体（SealStampView/Overlay 造型）一字未动；其动画由自研 sealIn 令牌曲线（.bouncy(duration:extraBounce:) 参数化）→ 系统 `.bouncy` 预设弹簧拼装既有缩放/旋转/淡入（同一落印观感），Reduce Motion 分支（.easeIn 0.2 淡入）保留。随本条，MotionTokens 最后一档亦退役（见第 7 条）。

## 验收

- 源码守卫＋新纯函数单测：新增 Tests/LiqianCoreTests/NativePassGuardTests.swift（9 个用例：图表分段 Picker 化/占比条 Charts 化/BatchEntry 无写死字号/人物详情 List 化/ScaleOnPress＋MotionTokens 全仓零引用/记一笔 Form＋decimalPad＋回执 init 保留/落印 .bouncy/AmountInputText 13 例/bigMode 保底函数），沿 PrintBookAssemblyTests 的 repoSource 同款守卫口径。
- CI 与解包数据见本文件末尾回填。
- 红线自查：AnalyzerFeeder 零改动（不在 diff 名单）；金额双色/待回口径/统计隔离/扫码随礼链路/v5.13 本地化与字号机制零回归（本期未动相关文件，字号只在 BatchEntry 追加注入）；新改文案无新增字符串（未动本地化表）。

## 真机未验（如实声明）

- 图表页系统 segmented Picker 的切换手感与年份 Menu 展开；
- 占比堆叠条的段内百分比在窄段下的排版（Charts annotation overlay 行为）；
- 人物详情 List 的滚动/左滑/长按实景与统计头行距；
- 大场模式 AX2 保底下的整页观感（金额格≈33pt 是否合现场读数）；
- ConcentricRectangle 在礼簿卡上的实际推导圆角（须真机/渲染核对与旧 4pt 的差异）；
- 记一笔 Form 化后的整页观感、decimalPad 输入与净化函数的跟手程度、落印 .bouncy 的盖印观感与旧曲线差异。

（CI/解包回填见下方追记）
