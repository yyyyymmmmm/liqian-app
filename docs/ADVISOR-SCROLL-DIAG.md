# 问账页打开时停在中间消息——诊断（2026-11-08，只读诊断，未施工）

症状（用户原话）：「点击 AI 之后为什么不是最新的消息，是中间的消息？」
即进入问账页时，对话列表不停在最后一条，而是停在历史中间某处。

## 定版结论（两层叠加）

**第一层（地基缺陷）：问账页根本没有「出现时滚到底」的逻辑。** 全视图只有
两个滚动触发，都是数据变化驱动的，进入页面、数据未变时一个都不会响——
冷启动的默认位置是列表顶部（欢迎卡＋最旧消息）。

**第二层（落点为何是中间）：历史回答每次进页都会全员重播打字机动画，**
每条回答重播时都周期性地把列表滚到「它自己那一行」，谁的文本最长谁
最后播完、谁的滚动就赢——落点由最长的那条历史回答决定，与它在列表
里的位置无关，于是经常停在中间某条长回答处。

两层缺一不可单独解释症状：只有第一层会停在最顶部；只有第二层（若有
出现滚动兜底）落点会被兜底修正。修复也须两层都动，见文末方案。

## 逐项证据

### 1. 入口路径（简报口径先纠正：问账页不是底部 Tab）

- ContentView.swift:72 的 TabView 只有四栏：首页 0 / 往来 1 / 图表 2 /
  我的 3，**没有问账 Tab**。
- 全仓 `AdvisorView()` 实例化只有两处，两处都是每次进入新建实例、
  都不带任何滚动初始化：
  - 首页快捷动作「问管家」（HomeView.swift:265-267）：
    `.sheet(isPresented: $showAdvisor) { AdvisorView() }`——sheet 呈现；
  - 往来页顶部「问账」行（PeopleView.swift:187）：
    `.navigationDestination(isPresented: $showAdvisor) { AdvisorView() }`
    ——导航 push。
- 用户说的「点击 AI」即这两处之一（sparkles 图标）。两条路径的滚动
  行为完全一致（同一个视图、同样的零初始化）。

### 2. 初始滚动与加载时序

- AdvisorView 里与滚动有关的只有两处触发（AdvisorView.swift:104-128）：
  `.onChange(of: session.messages.count)` 与
  `.onChange(of: session.answerTrigger)`（v5.8.2 补滚），都
  `proxy.scrollTo(last.id, anchor: .bottom)`。全文件无 onAppear 滚动、
  无 .task 滚动、无 defaultScrollAnchor/scrollPosition。
  `.onAppear`（:196-205）只驱动欢迎卡的 `entered` 淡入。
- 加载时序排除：AdvisorSession 是 App 根 @StateObject
  （LiqianApp.swift:20,30），其 init 同步解码 JSON 文件
  （AdvisorSession.swift init；AdvisorChatStore.load 为同步读盘）。
  视图被创建时 messages 已是完整历史，不存在「先滚后加载、加载完
  没补滚」的竞态。
- 行身份排除：AdvisorChatMessage.id 是随消息落盘的 UUID
  （AdvisorChatStore.swift），ForEach 走 Identifiable、行
  `.id(message.id)`、scrollTo 目标 `session.messages.last.id` 三者同源，
  不存在目标 id 对不上行的问题。

### 3. 状态保持

- 简报设想的「常驻 Tab 保持旧偏移」不字面成立（无此 Tab）；等价事实
  更糟：sheet/push 每次都是冷建视图，ScrollView 默认偏移为顶部，
  且出现时没有任何逻辑把它纠正到底部。在页内提问时 count/
  answerTrigger 两路触发工作正常（发送→滚底、settle→补滚），缺口
  只在「进入页面」这一刻。

### 4. 打字机重播与滚动争夺（落点在中间的直接机制）

- TypewriterMarkdownText（AdvisorView.swift:1302-1337）：
  `@State revealed = 0` ＋ `.task(id: markdown)`——**每条 .answer 行
  在视图层级（重）建时都从 0 无条件重播全程**，不区分「刚落地的
  新回答」与「历史回答」；消息模型也无时间戳/已读标记可供区分
  （AdvisorChatMessage 只有 id 与 kind）。
- 重播期间每 24 字调用一次 onReveal，及播完时再调一次；answerBlock
  的回调（AdvisorView.swift:410-417）执行
  `proxy.scrollTo(messageID, anchor: .bottom)`——**滚到的是那条回答
  自己的行**，且带 withAnimation。
- 列表是普通 VStack（AdvisorView.swift:79，非 LazyVStack），全部行
  同时在层级里，**所有历史回答的打字机并发重播**；播完顺序由文本
  长度决定（3 字/16ms），与行位置无关。最后执行的一次 scrollTo
  决定静止落点：只要中间某条回答比最后一条长（极常见：账外长答、
  多卡回答在中间、最新一条是短回复），它的收尾 onReveal 最后响，
  列表就停在那条中间消息的底部。重播期间视口还会被反复拉扯，
  且每行高度从 0 增长（revealed 切片），内容高度持续变化助长漂移。
- 附带：Reduce Motion 用户不重播（task 直接 revealed=total 且不调
  onReveal），他们命中纯第一层——进页停在顶部。

### 5. 历史量与 LazyVStack

- 「LazyVStack 行高估算致落点偏移」**排除**：列表是普通 VStack，
  全部行按真实高度布局，不存在估算误差。
- 历史量经第 4 项起作用：回答行越多、并发重播越多，中间长回答
  「夺冠」概率越高；上限 120 条（AdvisorChatStore.maxMessages）。
  用户实际历史（连日多轮问答）远超触发所需——三四条回答、且中间
  有一条最长，即可复现。

### 排除项汇总

- 历史异步加载/半量加载竞态（根持有者同步加载，先于视图存在）；
- 行 id 与 scrollTo 目标不一致（三者同源 UUID）；
- LazyVStack 高度估算（无 lazy 容器）；
- Tab 滚动位置恢复（无此 Tab，入口是 sheet/push 冷建）；
- CardInModifier 的 .task（只做卡片淡入，不滚动）。

## 最小修复方案（建议，未施工）

1. **出现即滚底（治第一层）**：AdvisorView 出现且 messages 非空时
   显式滚到 `messages.last.id` 锚 .bottom——优先考虑
   `.defaultScrollAnchor(.bottom)`（iOS 26 下限内可用，聊天类列表
   的标准解法，初始落位由系统保证）；或在 onAppear 后一拍
   （等首帧布局完成）调用与现有两路同款的 scrollTo。两者取一，
   与既有 count/answerTrigger 触发不冲突（同目标同锚点，重复滚
   无副作用）。
2. **历史回答不重播（治第二层，与 1 同等重要）**：
   TypewriterMarkdownText 加 `animate` 入参（或改为由父级传入
   「是否本页在场时新落地」标识）：AdvisorView 只对「本次出现
   期间经 settle 落地的那一条」传 true，其余行初始
   revealed=total、直出全文、不发 onReveal。落地标识可由会话
   持有者发布最近 settle 的消息 id（与 answerTrigger 同点位
   维护），视图侧比对 lastSettledID 决定。只修 1 不修 2：进页
   滚动会被随后数秒的重播逐条抢走，落点仍不稳；只修 2 不修
   1：进页仍停顶部。
3. **防御（可选）**：onReveal 的 scrollTo 加一道闸——仅当
   messageID == 当前最后一条消息 id 时才执行，杜绝任何残余的
   中间行滚动获胜。

真机判读（修复后）：冷进问账页（分别从首页问管家、往来问账两
入口）→ 第一眼即最后一条消息、无后续自动漂移；页内新问一轮，
打字机与钉底如常；Reduce Motion 下冷进同样落底。
