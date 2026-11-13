# v5.14.4 小热修：快捷金额点选落值＋点金额弹关系（双症状合诊）

分支 `feat/v5144-preset-amounts`（基线 feat/v5143-rescue-gate @3834558，独立 worktree）。
版本 5.14.4/85（Project.swift 字面量六处）。

## 症状（用户真机实报，v5.14.3）

1. 记账时快捷金额小签（100/200/300/500/800/1000）**点哪个都变成 1000**。
2. 记账表单里**点金额区域，弹出的却是关系选择器**。

## 合诊定因（同根，代码实证）

**共同根：v5.14 把整个表单卡塞进 Form 的单个单元格。** 该笔提交（6f68d01）
把容器由 ScrollView＋手堆卡换成系统 Form，`formCard`——金额 TextField、
六颗快捷金额 Button、姓名 TextField 与联想 Button、DatePicker、关系/方式
Picker、状态 segmented、备注 TextField——全部挤在同一个 List 单元格里。
List 单元格的命中是行级的：同一行里塞多个控件，点选由行级路由分发，
不再逐控件精确命中。两个症状是同一机制的两个落点：

- **症状一落点＝amountChips**：同行六颗**默认样式** Button 的点选被行级
  路由吞并，最终由末位 Button 的动作落值——点哪颗，`amountText` 都写成
  末位面值 "1000"。旁证链：①chips 的 ForEach/闭包代码与 v5.13 可用版
  **逐字相同**（Swift 闭包逐迭代捕获，本就无捕获错位），变的只有容器
  （ScrollView→Form 单元格）与同笔被摘掉的自定义 ButtonStyle
  （ScaleOnPress）——默认样式正是行级路由接管的对象；②落值侧
  `AmountInputText.sanitized` 逐行核过为恒等净化，产生不了 1000；
  ③回礼提示行等其他 `amountText` 写入点条件均不成立；④覆盖层清白——
  落印 overlay `allowsHitTesting(false)`、存储守卫面仅 storageUnsafe
  时出现（用户能落值说明不在场）、全仓无自研点选手势侵入本页。
- **症状二落点＝关系 Picker 与金额同行**：List 行内的 Picker 是「行级
  点选呈现」型控件——它自己那一行的点选归它呈现菜单。与金额 TextField
  同处一个单元格时，点金额区会被行级路由交给关系 Picker 呈现（补充
  信息展开时成立；编辑/回执入口默认展开，与用户使用路径吻合）。方式
  Picker、DatePicker 同为同行潜在抢点者，机制相同。

## 修法

1. **body 主表单拆行**：`formCard` 巨无霸单元格退役，卡内各块逐块独占
   Form 一行（错误行/选簿行/金额/小签/回礼提示/姓名/日期/补充开关/
   补充内容各行），同组共用纸面行底＋隐藏分隔线维持「一张纸」观感；
   行距由行内边距上下各 spacingS 拼回原 spacingM 节奏（纸面上下缘
   内边距随之由 16 变 8＋组间距，真机看观感）。落印 overlay 宿主由
   formCard 改挂主表单 Group 整面，落点口径不变（纸面中央偏右）。
2. **小签自带值＋自带命中**：数据源收敛 Core 新文件 `PresetAmounts`
   （`recordForm` 六档、`scene` 七档、恒等映射 `amountText(forPreset:)`，
   单测逐一钉死）；记一笔 chips 改引用之，每颗加 `.buttonStyle(.borderless)`
   ——只许命中自身框内，不再受行级路由摆布。姓名联想 chips 同行多颗
   Button，同补 `.borderless`（麦克风钮、回礼提示行原本已 `.plain`，不动）。
3. **补充信息拆两件**：开关 `supplementsToggleRow` 独占一行；展开内容
   `supplementsRows` 逐行独占——礼簿/关系/方式/状态/备注各行，关系
   Picker 的点选呈现从此只发生在关系行自己身上。
4. **现场模式仅数据源收敛**：`quickAmounts` 改引用 `PresetAmounts.scene`。

## 同型排查（全仓「一排预设点选」与 Form/List 行内控件）

- **现场模式 SceneModeView**：容器是 ScrollView、chip 为 `.bordered`
  样式，命中逐颗精确——**免疫**，本版仅收敛数据源。
- **批量补录 BatchEntryView**：虽是 Form，但每条记录独占一行单元格，
  行内删除 Button 已 `.buttonStyle(.plain)`，其余为 TextField；方向/
  方式等 Picker 各自成行——**免疫**，未动。
- **一句话记账 QuickSentenceView**：Form 内各控件独立成行、语音钮
  `.plain`、无预设 chips——**免疫**，未动。
- **问账草稿卡（AdvisorView draftRecordCard）**：位于聊天滚动区而非
  Form/List 单元格，无预设金额 chips，金额为草稿预填值——**免疫**，未动。
- **建簿 LedgerFormView**：Picker 各自成行，Button 只在 toolbar——
  **免疫**，未动。
- **回礼区间（ReplyAdvice）**：计算值＋单颗 `.plain` 提示行，非点选
  控件组——无同型问题。
- 记一笔内其余：方向 segmented 独占 Section；DatePicker 拆行后独占
  一行，其点选呈现归本行（正确行为）。

## 测试与纪律

- 新增 `PresetAmountsTests`（4 例：双列表确切值、逐一恒等映射、
  互不相同且不全等末位）＋`PresetAmountGuardTests`（3 例源码守卫：
  小签须 Core 数据源＋borderless＋字面量不回潮、formCard 不回潮且
  关系/方式 Picker 须在 supplementsRows 区内、现场须 Core 数据源）。
  预期单测总数 400＋7＝407、0 失败（实数以 CI 回收为准，见验收追记）。
- 未碰数据层：SaveFlow/CloudSync/StoreRescue/StorageGuard（v5.14.1–
  5.14.3 成果）零改动；AnalyzerFeeder 不在本版 diff 名单内。
- 无新增 UI 文案（仅代码注释），简繁同步不涉及。

## 真机未验（如实声明）

装机后一套验三件：**点金额出数字键盘、点关系才出关系、六预设逐一
对值**。另两处观感待真机回执：拆行后纸面上下缘内边距变化（16→8＋
组间距）、落印在新宿主（整组）上的落点位置。
