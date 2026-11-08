# v5.3.2 统计块对齐统一＋麦克风文案扩围

用户圈图原话：图表页总览卡与首页本月往来卡「怎么没有居中、感觉
乱七八糟」。病根：统计格按内容宽度撑开——HStack 里几个内容宽
VStack 前挤后散、左右两列起始线不齐、标签与数字顺序各页不一。

## 一、定版规范（先组件、后套用）

Design 层新增共享组件（Sources/LiqianDesign/Components.swift）：

- `StatCell`：统计格单元——数字在上、标签在下，数字与标签均居中；
  每格 `maxWidth: .infinity` 等分容器；数字走 liqianMoney 字阶
  （等宽数字、暗色降字重）＋数值变更 numericText 过渡（Reduce
  Motion 关闭）；大数字单行下限缩放 0.7 防挤爆；可选单位小字
  （人/场/笔，石色 footnote 基线对齐）；也支持自定义数字视图
  （图表总览的滚动金额）；VoiceOver 合并读「标签＋数值」。
- `StatRow`：单行等分（HStack＋令牌间距 spacingM，格子自带等宽）。
- `StatGrid`：多行等宽分栏（LazyVGrid，列/行间距同走 spacingM）。

口径红线：汇总数字颜色与字重沿用各页现状（默认墨色；问账时段卡
收礼数原 primary 色保持），v5.0.2「逐笔双色/汇总墨色」分界不破——
本组件只管排版，不借机改色、不改任何统计口径与数值来源。

## 二、逐页对账（旧排法 → 新排法）

| 页面 | 旧排法 | 新排法 |
|---|---|---|
| 图表页 ChartsView 总览六指标（圈图①） | LazyVGrid 2 列、格内左对齐、标签在上数字在下，两列起始线不齐 | StatGrid：常规字号 3 列×2 行、无障碍大字号退 2 列×3 行；StatCell 数字在上（滚动金额 RollingMoneyText 原样嵌入）＋标签在下、居中。顺序与全 App 翻正统一 |
| 首页 HomeView 本月往来卡（圈图②） | HStack(spacingL) 三个内容宽 VStack（数字上/标签下），前挤后散 | StatRow 三格等分居中；笔数格改「数字＋单位小字」与图表计格同形 |
| 人物详情 PersonDetailView 头部（收礼/随礼合计） | HStack＋Spacer，两格靠各自 maxWidth「偶然等分」，私有 headerStat | StatRow 两格结构等宽；私有 headerStat 删除（数值动画收敛进组件） |
| 礼簿详情 LedgerDetailView 头部（收礼/随礼/人数） | 封面块右侧内容宽 HStack 三格，宽窄随数字长度浮动，私有 headerStat | HStack(spacingS) 三枚 StatCell 等分（头部宽度受封面块约束，不用 StatRow 的 spacingM）；标签并入笔数「收礼 · N 笔」沿用旧文案；人数格同形 |
| 人情总览 StatsView 年度往来行 | 行内「标签＋数字」横排配对（summaryPair）＋「共 N 笔」散文挤一列 | List 行内 StatRow 三格等分居中（收礼/随礼/笔数），行内边距走令牌；summaryPair 删除 |
| 年度报告 AnnualReportView 头部三指标 | HStack(spacingL) 三个内容宽左对齐 VStack，私有 headlineStat×2 | StatRow 三格等分居中；headlineStat 两重载删除 |
| 问账 AdvisorView 汇总卡（工具版） | HStack(spacingL) 两格左对齐、标签在上 | StatRow 两格等分居中、数字在上 |
| 问账 AdvisorView 时段卡（降级管线，无 focus 分支） | 同上（收礼数 primary 色） | StatRow 两格；primary 色经组件 color 参沿用现状 |
| 问账 AdvisorView 对比卡差值行 | HStack 三个内容宽 deltaItem（标签在上） | StatRow 三格等分居中、数字在上；deltaItem 删除 |

## 三、审计后不改（理由）

- 逐笔列表行（往来/礼簿流水/人物时间线/待回名单行等）：左名右额的
  列表语义，非多指标并列块，套格子会毁列表扫读。
- 图表页其余卡：趋势/净额/累计为图表本体；事由成对条、金额段、
  人物/场次 Top、按年汇总均为条形或表格行；关系环图中心是单个
  居中总额（本就居中）。均非统计格。
- 问账 figureLine（单指标英雄行，如「待回 ¥N」大字）、personCard
  底部「收 X · 随 Y · N 笔」脚注行：单指标/散文行，非并列统计块。
- 年度报告分享图卡 AnnualReportCard 内的 stat：固定画布（340×460）
  静态成品绘制，左对齐编辑排布属成品设计（衬线白名单 moment），
  不入 UI 组件口径。
- 现场模式 SceneModeView 实时汇总带：左状态文案＋右单一总额英雄数
  的横幅语义，非多指标并列；大字现场形态不动。
- 交接页 HandoverView infoRow：键值信息行，非统计块。

## 四、附带小修：麦克风权限文案（v5.3.1 审计标红项）

- 旧文案（Project.swift）：「用于语音记账，把你说的话转成文字」
  ——只覆盖 QuickSentenceView 语音记账，漏了 BlessingAudio 语音
  祝福录音（AVAudioRecorder 实存），与 v5.3.1 隐私政策 §权限清单
  所述用途对不上。
- 新文案：「用于语音记账和录制语音祝福：把你说的话转成文字，
  或把祝福原声收进礼谱」——两处实际用途如实并列、简短。
  Info.plist 由 Project.swift 生成，改源一处即同步；解包验核对
  包内新文案（见验收节）。

## 五、验收实测（2026-11-08 本机亲验）

- CI：run 42446410555 **success**（手动 workflow_dispatch 于本分支）。
  日志含 `** BUILD SUCCEEDED **`、`** TEST SUCCEEDED **`、
  `presign assertions passed (2 binaries)`。
- 单测：日志逐条去重计数 **194 个唯一用例全过、0 失败**（与
  v5.3.1 基线一例未掉；本版无新增单测，改动面为 Design 组件、
  七处统计块排版、Project.swift 文案与版本字面量、NOTES）。
- 解包验：App 与 Widget 均 **5.3.2/58**；PlugIns 只有
  LiqianWidget，**无 LiqianShare.appex**；Share target 版本保持
  4.6.0/46 未动。
- 包内核对：App Info.plist 的 NSMicrophoneUsageDescription 为
  新文案「用于语音记账和录制语音祝福：把你说的话转成文字，或把
  祝福原声收进礼谱」；主二进制含 StatCell/StatRow/StatGrid 符号。
- IPA：`~/workspace/your_files/liqian-v5.3.2/liqian-native-unsigned.ipa`
  （3,820,568 字节）。

## 六、真机待验（未验，不宣称已验）

1. 圈图两处重点看：图表页总览六指标——3 列等宽、数字与标签居中、
   两行中线对齐；首页本月往来卡——三格等分、间距均匀。
2. 其余套用页逐页扫一眼：人物详情头部、礼簿详情头部、统计页
   年度行、年度报告头部、问账汇总卡/时段卡/对比卡——格子等宽、
   居中、无挤压。
3. 大数字场景：把金额造到六位数（如 ¥888,888），总览与本月卡
   格子不挤爆、不换行（StatCell 下限缩放 0.7 兜底）；无障碍大
   字号下总览退 2 列×3 行正常显示。
4. 麦克风授权弹窗（新装或重置隐私设置后触发语音记账/录祝福）：
   弹窗文案为新版双用途表述。
