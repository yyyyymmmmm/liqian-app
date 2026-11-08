# v5.11.2 问账页打开停在中间消息——两层修复

- 分支：`feat/v5112-advisor-scroll`（基线 feat/v5111-widget-diag 顶端 77fee0d）
- 症状（用户原话）：「点击 AI 之后为什么不是最新的消息，是中间的消息？」
- 根因定版见 docs/ADVISOR-SCROLL-DIAG.md（两层叠加）：①问账页没有任何
  「出现时滚到底」逻辑，仅有 messages.count 与 answerTrigger 两路数据
  变化触发，进页数据未变时都不响；②历史回答每次进页全员重播打字机，
  每条重播时周期性把列表滚到自己那一行，最长的一条最后播完、落点
  被它抢走，停在中间。

## 修法落点

### 第一层：出现即滚底（一次性补滚）
- 落点：AdvisorView 的 ScrollView（ScrollViewReader 内）在既有两路
  onChange 之后新增 `.onAppear`：messages 非空时，推迟一拍
  （DispatchQueue.main.async，等首帧布局完成）以
  `proxy.scrollTo(last.id, anchor: .bottom)` 落位。
- **不用 .defaultScrollAnchor(.bottom)**（简报首选、此处不用，理由
  两条）：其一，它是常驻锚点，内容高度变化时会反复重锚——页内新
  回答的打字机逐字变高即是持续的高度变化，用户在回答生成期间上滑
  读历史仍可能被重锚拽回，与本版「补滚只在出现那一刻发生一次」的
  硬要求冲突；其二，空态（只有欢迎卡）时小内容的落位不受控。
  onAppear 一次性补滚与既有两路同目标（last.id）同锚点（.bottom）、
  无重复副作用。
- **不带动画**：进页是「落位」不是「滚动」——带动画会从顶部一路扫过
  全部历史才停。页内两路（count/answerTrigger）的动画滚动口径不变。
- 一次性保证：onAppear 在一次呈现（首页 sheet / 往来 push 均为冷建
  视图）内只发生这一回；其后用户上滑读历史，只能被新消息发送
  （count 路）或新回答原位落地（answerTrigger 路）带回底部——那是
  既有设计，不是本补滚。Reduce Motion 下同样直达（本就无动画）。

### 第二层：历史回答不重播（animate 判定口径）
- 持有者发布：AdvisorSession 新增 `@Published lastSettledID`，在
  settle 内与 answerTrigger **同点位**赋值（messages 原位改 kind 的
  同一 if 块内、先于 answerTrigger += 1）。管线/时限/持有机制未动；
  pulseAnswerFeedback（草稿确认回写）不发布此 id——那不是新落地
  的回答，其文字本就不该重播。
- 视图判定：AdvisorView 新增 @State `hasAppeared` 与
  `settleBaseline`，在既有外层 onAppear 里落定（hasAppeared=true、
  settleBaseline=session.lastSettledID）。answerBlock 的资格公式：
  `animate = hasAppeared && session.lastSettledID == messageID
  && settleBaseline != messageID`。逐情形：
  - 首帧求值（onAppear 之前）：hasAppeared=false → 全部历史行
    animate=false，不存在「基线未落先误判」的窗口；
  - 出现前就已落地的最新一条：id == 基线 → false，进页直出全文；
  - 出现后页内新问的回答：settle 发布新 lastSettledID != 基线 →
    true，打字机照常（行在 kind 由 .pending 翻 .answer 时以
    animate=true 出生，task 从 0 揭示）；
  - 同页连问第二题：上一题的 lastSettledID 资格随新 settle 转移，
    其 TypewriterMarkdownText 的 .task(id: markdown) 不重跑
    （id 未变、revealed 已是终态），新旧交接无闪烁；
  - 离页期间在后台 settle 的回答（v5.8 持有者机制）：重进页时它
    已是「出现前落地」，基线即它 → 直出全文＋第一层补滚落位，
    「问完切走再回来第一眼看到答案」成立；
  - 再次进入（新视图实例）：@State 重置，基线按当次 onAppear
    重捕，上一轮的最新回答不再重播。
- 组件改法：TypewriterMarkdownText 新增 `animate: Bool = true`
  入参（全仓唯一调用点 answerBlock 显式传判定值）。animate=false
  时 body 直接渲染全文（不经 revealed 切片，行高自第一帧即终态）、
  .task 直接 revealed=total 返回——不重播、不发 onReveal。

### 防御：onReveal 加闸
- answerBlock 的 onReveal 闭包首行加
  `guard messageID == session.messages.last?.id else { return }`：
  揭示期钉底只许当前最后一条执行。历史行已不重播，此闸是双保险，
  杜绝任何残余的中间行滚动获胜。

## 红线自查
- v5.8.2 去门控未回退：全文仍在 body 内同步算出、Text 常驻；
  animate=true 路径与旧版逐字一致（切片、3 字/16ms、每 24 字
  onReveal、取消即全显），新落地回答的打字机手感保持。
- 未动：问账管线/提示词/收敛器、AdvisorSession 的时限与持有机制
  （仅新增一个 @Published 发布点）、语音链与 AnalyzerFeeder、
  组件数据链、主题/图标、法务文本。diff 仅 3 文件
  （AdvisorView / AdvisorSession / Project.swift 版本字面量）。

## 验收（实测回填）
- CI run：待回填
- 单测：待回填（基线 301，预期不低于 301）
- 解包验：待回填（预期 App/Widget 均 5.11.2/73、无 LiqianShare.appex）
- IPA：~/workspace/your_files/liqian-v5.11.2/liqian-native-unsigned.ipa

## 真机待验（不宣称已验）
1. 冷进问账页（首页「问管家」sheet、往来「问账」push 两入口各一次）：
   第一眼即最后一条消息、无后续自动漂移；
2. 连进数次落点稳定（每次都停在最新消息处）；
3. 页内新问一轮：打字机逐字呈现＋钉底如常，回答带卡片时图卡浮入
   不受影响；
4. 回答生成期间及生成后上滑读历史，不被拽回底部；
5. Reduce Motion 下冷进同样落底、历史行直出全文；
6. 离页提问、等落地后重进：第一眼即该回答全文（不重播）。
