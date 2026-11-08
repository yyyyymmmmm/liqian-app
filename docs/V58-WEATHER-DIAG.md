# V58-WEATHER-DIAG 问账「11.16 天气咋样」零回复诊断（只诊断，未改产品代码）

## 症状（用户确认版）

- 版本确认为 v5.8（feat/v58-advisor-delivery 交付的 5.8.0/66）。
- 问「11.16 天气咋样」，等了整整 1 分钟：零回复、零提示；pending 占位行从头到尾没出现过（用户原话「就算等也要有提示呀，他啥都没有」）。
- 截图终局状态：问题气泡在屏，其下无占位、无转圈、无任何回复，输入区可用态（发送钮呈未发送的常态）。
- 同期账内问题（「谁还没回礼」「婚礼一共收了多少」）能正常出卡。

## 结论先行（终端状态排除法）

在 v5.8 代码里，这个终局状态只能由一条路径产生，逐步排除如下（每步附代码位置）：

1. **气泡在屏 ⇒ ask() 真的跑了。** 全仓只有 `AdvisorSession.ask()`（Sources/LiqianApp/AdvisorSession.swift）append `.user` 消息；视图薄包装 `AdvisorView.ask(_:)`（AdvisorView.swift:1238）在转交前还有一道 `!session.isAsking` 守卫，被挡下时连气泡都不会出现。
2. **气泡与占位是同批原子 append。** `ask()` 内先后 `messages.append(.user)`、`messages.append(.pending)`，中间无 await、无分支，随后 `persist()` 一起落盘（AdvisorSession.swift ask 函数体）。不存在「气泡已上屏但占位没 append」的路径。
3. **输入区可用（isAsking == false）⇒ settle() 必已执行。** `isAsking` 置 true 只在 ask()，复位 false 只有两处：`settle()` 与 `clear()`。`clear()` 会把消息清成空表——截图里历史与本次气泡都在，排除。**所以回复不是「没送到」，是已经原位落地了。**
4. **占位不在列表里 ⇒ settle 找到了索引并替换了 kind。** settle 的另一分支（`firstIndex` 找不到占位）只复位状态不写回复，但全会话没有任何删除单条消息的代码（只有 clear() 整表清，且它先把 `inFlightPendingID` 置 nil，settle 的 guard 会先一步挡下、且 isAsking 不会由 settle 复位——与终局矛盾），此分支在现网不可达，排除。
5. **落地 kind 只能是 `.answer`。** settle 的 kind 只有三种来源：`.answer`（工具 lane / 通用 lane）、`.result`（意图腿，含 .unsupported）、`.note`（致歉兜底）。逐一核对渲染（AdvisorView.swift messageRow）：
   - `.result` → resultCard：所有子类型都是带文字的卡片；`.unsupported` 的文案 `unsupportedText` 是非空常量（「这个问法我还不会…」）。
   - `.note` → noteCard：文案是 `AdvisorReplyConvergence.failureApologyText` 非空常量；遗孤占位收敛文案 `orphanedPendingNoteText` 同样非空。
   - `.answer(text:, cards:)` → answerBlock：文字与卡片是两个独立渲染件。
6. **cards 必为空。** 若模型先调过任何工具，settle 的 .answer 会带上同源卡片（待回/场次/汇总等），截图中气泡之下无任何卡片。故本问的走向是：工具第一轮直接出文字（提示词账外 lane 第 6 条生效）或整链降级后走通用 lane——两条都是 **cards == [] 的纯文本 .answer**。
7. **纯文本 .answer 的唯一渲染者就是 TypewriterMarkdownText，而它输出了空白。** 数据层无问题：chatTurn 对空 content 直接抛错（DeepSeek.swift chatTurn 末尾 guard），answerGenerally 去空白后为空即返回 nil，收敛器再验一次非空——**落进 .answer 的 text 必然非空**。消息在状态与磁盘里是完好的，死的是呈现。

**定版根因：TypewriterMarkdownText（AdvisorView.swift 文件尾）的「存在性门控」缺陷。**

```swift
@State private var full: AttributedString?
@State private var revealed = 0
var body: some View {
    Group { if let full { Text(slice(full)) } }   // full == nil 时渲染零高度空 Group
    .task(id: markdown) {
        let rendered = Self.render(markdown)
        full = rendered                            // 文字的「存在」只由这个 .task 赋值
        ...
        while count < total {
            ... revealed = count ...
            if Task.isCancelled { return }          // 取消即弃，不回滚全显
        }
    }
}
```

- 文本不是 body 同步算出来的，而是靠 `.task(id:)` 异步填进 @State：**task 没跑到 `full = rendered` 这一行，屏幕上就永远是空**，且没有任何重试/兜底分支（full 为 nil 时 body 是空 Group，外层 liqianCardSurface 随零高内容塌缩到近不可见，截图中不可辨）。
- task 在循环中途被取消时直接 `return`，`revealed` 停在半途（本例若停在赋值前就是全空，停在中途就是半截字——同族缺陷）。
- 可信的触发环境（静态代码能定的到此为止）：settle 是**原位改 kind**（id 不变、count 不变），行子树在同一轮状态翻转里由 pendingRow 整体换成 answerBlock，叠加 isAsking/activityText 同批变化与 answerTrigger 触感、以及打字机自己的 `onReveal` 回调每 24 字就 `proxy.scrollTo(..., anchor: .bottom)`（带动画）去追一个**高度还在逐帧变**的卡片——滚动与布局反馈足以让该行的 .task 被取消或迟迟得不到调度。账内回答同样经过这个组件，但它们带卡片：文字那块塌了，卡片照样出，用户席上就是「正常出卡」——这正是本次「账内正常、账外纯文本消失」的分野所在。

## 逐项核查（对任务书 (a)(b)(c) 的回答）

### (a) .pending 的渲染条件——没有任何隐藏路径

- v5.8 与 v5.8.1 的 messageRow 对 `.pending` 都是无条件 `pendingRow`（已 diff 两分支核对：占位渲染代码逐字一致；v5.8.1 只动了 chips 位置）。
- pendingRow 是 ProgressView＋Text 的 HStack：文案读 `session.activityText ?? "正在查账…"`，activityText 只决定**写哪句**，为 nil 也有默认句，**不存在靠它显隐的开关**；行上只有 transition/animation 修饰，不影响终态可见性；列表身份是消息自带 UUID（每次新建，无碰撞面）。
- 接线核查：AdvisorSession 全 App 只有一个实例（LiqianApp.swift @StateObject＋单次 environmentObject 注入），`AdvisorChatStore.load()` 只在 session init 被调用，会话中途没有重读覆盖。双实例/中途重读均排除。
- **「占位不可见」与「回复不落地」不是同一根因。** 回复其实落地了（见结论 3）；占位在飞行那几秒里必然在列表中存在（与气泡同批 append、渲染无门），用户没看到它，与「发送后键盘未收、视线不在列表底部、且工具第一轮直答的 settle 只需数秒」相容——他决定「死了」并截图时，占位早已被那条空白回复原位替换。占位机制本身无病，不需要为它立项；真要改善观感是另一回事（见修复 3）。

### (b) 哪条腿能绕过 withLegTimeout 真挂死——逐腿核对，无一成立

每腿都是双保险：URLRequest.timeoutInterval 按腿写死＋withLegTimeout 看门狗到点 cancel（AdvisorSession.swift withLegTimeout）。

| 腿 | 等待物 | 取消响应性 | 核对结果 |
|---|---|---|---|
| 工具轮 chatTurn | URLSession.data(for:) | 抛 URLError（含 .cancelled/.timedOut）→ answerWithTools catch 后 return nil | 有界：单轮 min(30, 工具阶段剩余 27, 总剩余 45) |
| 意图腿 chatJSON | 同上 | 同上 → resolveIntent catch 后落规则 | 有界 8 秒 |
| 通用 lane chatText | 同上 | 同上 → answerGenerally catch 后 return nil | 有界：吃满总剩余 |
| 工具本地执行 executeDetailed | 同步计算（@MainActor） | 不涉及取消 | AdvisorTools.swift 仅两处按条目数的 for 循环（:469、:506），无 while/递归/日期逐日迭代；用户账目量级下毫秒级，不可能 60 秒 |
| DeepSeekClient() 构造 | Keychain 同步读 | 前台运行不阻塞，失败即抛 | 毫秒级 |
| persist() 落盘 | 同步文件写 | — | 毫秒级 |
| 链内 continuation | 全链无 withCheckedContinuation 等手写 continuation | — | 不存在永不 resume 的等待原语 |

预算数学：工具 27＋意图 8＋通用吃满剩余 ⇒ settle 最迟在约 45 秒被调用（预算回 nil 的腿直接跳过、交收敛）。唯一口径注记：`elapsed()` 用 `ProcessInfo.systemUptime`，该时钟不计设备息屏时间——用户若中途锁屏，墙钟可超 45 秒；本次用户全程亮屏注视，不适用。**「某条腿真挂死」排除；60 秒无回复的原因是回复早已落地但不可见，不是链还在跑。**

### (c) `if Task.isCancelled { return }` 不 settle 的路径——唯一触发源是 clear()，且与终局矛盾

- runPipeline 里共三处取消检查：工具腿后、意图腿后、通用 lane 后，任一命中都直接 return、**不 settle**——若被命中，终局会是：占位永留 .pending（转圈不止）、isAsking 永真（发送钮锁死）直到杀进程重进（重进时遗孤收敛成提示文案）。这与截图终局（无占位、输入可用、无提示文案）**处处相反**。
- askTask 的取消源全仓只有 `clear()` 一处（`askTask?.cancel()`）。clear() 同时置 inFlightPendingID=nil、isAsking=false、messages=[] 并删档——它留下的终局是「空表」，不是截图里的「满历史＋气泡无回复」。用户未清过对话，此路排除。
- 附带隐患（现网不可达，记录在案）：settle 开头 `guard inFlightPendingID == pendingID else { return }` 若失败，是在复位 isAsking **之前** return 的——理论上存在「guard 挡下→永久转圈＋输入锁死」的形状；但能让 guard 失败的只有 clear()（它自己复位全部状态），故不可达。修复时可顺手把状态复位移到 guard 之前，属防御纵深、非本案病因。

## 被排除的假设（及依据）

- **卡片限制**：纯文本 .answer 与 .note 都是既有渲染路径，不依赖卡片；本案恰是「无卡可挂」才全损，反证卡片无关。
- **忙态闩锁吞问**：守卫在 append 之前（AdvisorSession.ask 首行），气泡能上屏即证明发送瞬间 isAsking 为 false（与 V58-AUDIT 排除口径一致）。
- **意图腿把天气问句误判为场次问题、在 .unsupported 处绕过通用 lane**：规则层已验算——AdvisorRules.intent 对「11.16 天气咋样」逐条不命中（无人名、无待回词、无事由词、无统计语气）返回 nil；AI 解码腿若误判成 period/type，settle 的是带数字的可见卡片，不是空白。故意图腿无论对错都产生**可见**结果，与本案无关。工具循环方面：账外 lane 在系统提示词第 6 条、模型第一轮即可直接出文字；若模型反复调工具，4 轮上限＋27 秒阶段封顶双闸，退出后进意图腿，不存在死循环。
- **通用 lane 抛错→收敛器拿到空 outcome→settle 成空消息**：不存在「空 outcome」这个值——收敛器输入只有 aiReady 与 generalAnswer 两件，general 为 nil/空白时裁决是 .failureApology（非空文案）或 .unsupportedWithoutAI（非空卡片）；answerGenerally 自身也先 trim 验空。组合不成立（AdvisorReply.swift resolve 全文已核）。
- **settle 原位替换时 index 丢失**：见结论 4，无删除单条消息的代码路径。
- **用户其实在 v5.7**：已由用户确认装的是 v5.8，作废。附带说明同源性：v5.7 的死法是审计定的「半路丢单」（回写绑视图 @State、离页即丢），与本案**不同源**——v5.8 的持有者机制在真机上恰恰是生效的（settle 落地可由 isAsking 复位反证）；本案是 v5.8 之后才暴露的呈现层缺陷，且它在 v5.7 时代同样潜伏（v5.7 的纯文本回复也走 TypewriterMarkdownText，只是当时先被丢单问题盖住了）。

## 修复方案（最小改动面，仅建议、未施工）

1. **根治（一处文件）：TypewriterMarkdownText 去存在性门控。** `full` 改为 body 内同步计算（`let full = Self.render(markdown)`，短文本解析成本可忽略），Text 永远在场；打字机只保留为 `revealed` 的化妆动画；`.task` 被取消时把 `revealed` 直接置 total（取消即全显），且 revealed 的推进不再是文字出现的必要条件。这样文字的存在与任何异步任务解耦，本类故障整体消失。改动范围：AdvisorView.swift 内该 struct 一处。
2. **防御纵深（可选，一处小改）：** AdvisorSession.settle 前加断言——若将落的 kind 是 `.answer` 且 text 去空白为空且 cards 为空，改落 `.note(AdvisorReplyConvergence.failureApologyText)`。数据层本已三重验空，此为防未来新路径再造空回复。
3. **观感加固（可选）：** settle 落地后补一次滚到底（现仅 messages.count 变化时滚动，原位替换不触发），顺带解决「问完切走再回来不知答没答完」的一半观感；占位行本身不需改。

## 复现判读法（修复前想再确认可用）

同一问题再问一次、等它「死」后，**杀掉 App 重进问账页**：若那条天气回复在重进后显示出来（新进程里 TypewriterMarkdownText 重新创建、.task 在安静环境重跑），即从真机侧坐实「数据完好、死在呈现」；若重进后仍空白，则需回头查 render 对该文本的解析结果（把原文发回比对）。
