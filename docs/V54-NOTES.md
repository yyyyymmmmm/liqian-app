# 礼记 v5.4 · 用户真机反馈五连修

版本 5.4.0（构建 59），分支 `feat/v54-five-fixes`（自 `feat/v532-stat-align` 顶端）。
基线不变：不带 Share 扩展（包内 PlugIns 只有 Widget）、CI 预签断言、无新增第三方依赖。
五条全部来自用户 v5.3.2 真机实测反馈，逐条对账如下。

## 1. 验证 400 假失败（AI 管家页）

**根因（代码实锤）**：设置页旧验证走 `DeepSeekClient.chatJSON`——它在请求里带
`response_format: {"type":"json_object"}`，而验证提示词是「仅回复 OK」、用户消息就是「OK」，
全文没有 "json" 字样。DeepSeek 对 json_object 模式有硬约束：提示词里必须出现 "json"，
否则直接回 400。正式问账走的是另一条 `chatTurn`（不带 response_format），所以
「验证失败（400）」与「问账能用」同时成立——坏的只是验证探活自造的第二种请求形状。
（意图解析也用 chatJSON 没事，因为它的提示词里本来就写了「JSON」。）

**修法**：
- `DeepSeekClient.verifyKey()`：改走与正式问账完全同一条 `chatTurn` 路径
  （同端点、同模型、同 tools 定义），发一次极小真实请求（让模型只回「好」）；
  回文字或回工具调用都算通。不再有第二种请求形状。
- 错误带服务端真实原因：`DeepSeekError.http` 改为 `(Int, String?)`，
  `serverMessage(from:)` 解析响应体 `{"error":{"message":…}}`；chat 与 chatTurn
  的非 200 分支统一走 `httpError(statusCode:data:)`；设置页失败文案把服务端原因
  原样拼出（如「接口拒绝了这次请求（400）：…真实原因…」），不再只报状态码。
- 验证结论落盘口径不变（v5.2.1 的 `AIVerificationStore`：结论＋时间＋Key 尾号指纹）。

## 2a. 问账页底部五层堆叠 → 一坨玻璃坞

原状：示例签行＋麦克风＋输入框＋发送键＋隐私脚注＋浮动标签栏五层堆叠，
脚注被夹在输入区与标签栏之间。

- 签行仍在坞上方贴坞（示例 chips 不变，新增一条记账示例「张三随礼了 500，帮我记上」）。
- 输入区收成一个玻璃坞：`RoundedRectangle`＋`Material.regular`＋描边，只包
  麦克风／TextField／发送键一行；发送键改实心圆钮（空输入时石色禁用态）。
- 隐私脚注移出输入栈，收进欢迎卡（introBlock）底部：示例句＋分隔线＋脚注
  （含「对话记录只存这台手机、可在右上角菜单清空」一句，与第 3 条呼应）。
  输入栈与标签栏之间只剩令牌间距，不再有文字夹在两层控件之间。

## 2b. AI 不会记账 → 新增 draft_record 工具

用户原话：给 AI 说「XX 随礼了」「回礼了」它不会记。

- `AdvisorTools` 新增第六个工具 `draft_record`（走 v5.2 既有工具框架，
  查询五工具与问答纪律逐字未动）：模型解析 人名／方向（随礼·收礼=received，
  回礼·随出=given）／金额（元）／日期（缺省今天）／场合，本地组装成
  `AdvisorDraftRecordCard` 渲染在对话里——**只是草稿，工具层绝不写库**。
- 记账纪律双层落地：①系统提示词新增一段记账纪律（人名/金额不全先追问、
  金额只用原话数字、方向不清先问、不要声称已记好；查询纪律其余逐字不动）；
  ②工具本地再校验一遍：缺人名/缺方向/金额≤0 → `ok:false` 人话错误递回模型
  追问，不出卡、不猜数。场合只接受既有 9 种礼簿类型，非法值丢弃。
- 卡上字段全列：人名（带已知关系）、方向＋金额（走 `SignedMoneyText` 双色口径）、
  日期、场合、目标礼簿。目标礼簿默认＝工具建议的「与此人最近一笔往来所在礼簿」
  （按日期倒序第一笔带 ledgerID 的往来；新人无建议），卡上 Menu 可改选
  （范围＝全部非示例礼簿，示例判定 `SampleData.sampleIDs`；生效优先级
  已选＞建议（仍在候选内）＞日期最新非示例簿）。
- 「确认入账」才写库，且走既有记账同一数据路径：与 `RecordFormView.save()`
  同一个 `GiftRecord(ledgerID:person:relation:amountCents:direction:method:note:date:status:)`
  构造＋`modelContext.insert`＋`save()`；字段口径一致（随礼/回礼都是已发生的事，
  status 恒已送出，与表单对已发生记录的落法相同；方式缺省「现金」＝表单默认；
  关系缺失回退表单默认「朋友」；备注空）。不另起一套 Entry 构造。
- 写入后卡片就地变回执态（已入账＋摘要＋「查看这笔」→ 打开既有记录表单页，
  与速记保存后打开同一页）；点「算了」卡片变一行灰字，不留任何记录。
  草稿状态（pending/saved/discarded、所选礼簿、已存记录 id）随对话一并持久化
  （见第 3 条），重进页面回执仍在、仍可点进那笔。
- 单测：组装正常例（建议礼簿/关系/小数金额/日期场合）、新人无建议、
  缺人名/缺金额/金额 0/方向非法 → ok:false 且不出卡、金额字符串入参、非法场合丢弃。

## 3. 「再点击进去记录没有了」→ 对话本地持久化

**主因坐实**：问账对话只存在 `AdvisorView` 的 `@State` 里（源码注释自认
「离开即散」），退出页面再进来历史全空，用户感知就是「记录没有了」。
未发现任何真实删数据/丢数据的代码路径（账本记录走 SwiftData，与对话无关；
深链核查见下）。

- 对话消息模型抽到 Core：`AdvisorChatMessage`（Codable，含工具卡片与草稿卡
  全部负载——为此给 `AdvisorResult`、`AdvisorCard` 及各卡片负载、
  `EntrySnapshot/PersonSummary/TypeSummary` 补齐了 Codable）。
- 存储选文件不用 SwiftData：`AdvisorChatStore`（Application Support 下
  `liqian-advisor-chat.json`，上限 120 条、超出截断保留最新）；理由：对话是
  单例文档型数据、含多态卡片负载，塞进 SwiftData 模型图要为全部卡片负载建
  实体，得不偿失；文件存储与现架构（AIVerificationStore 等）同风格。
  `messages` 每次变更自动回写，页面出现时恢复。
- 管家页右上角菜单加「清空对话」（messages 为空时禁用，带确认弹窗，
  清空同时删文件）。
- **深链附带核查结论**：问账卡片点人 → `PeopleView.NameRoute`，
  AdvisorView／HomeView／PeopleView 三处均有对应的 `navigationDestination`
  注册；首页、待回清单、图表关系钻取共用同一通道，未发现落空，不需修。

## 4. 点麦克风闪退 → SpeechTranscriber 代码级审计加固

真机崩溃日志未到手，以下为逐行审计结论；v2.7 已修过的一轮（格式校验、
先摘旧 tap、isStarting 闸门）保留。本轮新发现隐患点（文件均为
`Sources/LiqianApp/QuickSentenceView.swift` 的 `SpeechTranscriber`，
问账页麦克风与「记一笔」语音共用此类，一处修复两处生效）：

| # | 隐患行为 | 修法 |
|---|---|---|
| ③ | 授权链无作废机制：stop()/页面消失后，在途的语音→麦克风两段异步授权回调仍会调 `beginSession()`，在已离开的页面上启动音频引擎，甚至与下一页的转写器抢同一 AVAudioSession | 代际计数 `generation`：stop 必递增，每段回调落地前验代际，过期丢弃 |
| ④ | tap 回调（音频线程）append 与 stop 的 endAudio 竞争：removeTap 后仍可能有一个在途 buffer，endAudio 后 append 抛 NSException（do/catch 拦不住） | `OSAllocatedUnfairLock` 接受旗：stop 先关旗→摘 tap→endAudio；tap 内先验旗才 append |
| ⑤ | `setCategory(.record, options: .duckOthers)` 组合不合法会抛 AVAudioSession 错误（被 catch 成报错、不算闪退，但属无谓失败点） | 去掉 `.duckOthers` |
| ⑥ | stop() 无条件访问 inputNode：未启动过也摘 tap 会凭空创建输入节点，极端无路由状态下有抛异常报告 | `tapInstalled` 标记，stop 幂等：没装过 tap 完全不碰引擎 |
| ⑦ | recognizer 在 init 时只建一次，系统语音服务中途掉线后 isAvailable 状态可能过期 | 每次 start 现建 `SFSpeechRecognizer` 并判空＋判 isAvailable，不可用给人话提示 |

权限时序复核：现有链路本就是「双授权都拿到才 beginSession 碰引擎」，
plist 两条权限文案（麦克风/语音识别）都在位。③–⑦ 均为**代码审计推定、
待真机验**（无崩溃日志可对）。

## 5. 图表金额别每次都滚 → 按指标存档的滚动策略

策略本体落 Core 可单测：`RollingMoneyStore`（`Sources/LiqianCore/RollingMoney.swift`），
以「指标键」在 UserDefaults 存上次显示值（分）：
- 无存档 → 从 0 滚（首次入场，保留原观感）并落档；
- 现值 == 存档 → 静态直出、不滚；
- 现值 != 存档 → 从存档旧值滚到新值，滚动开始即落档（中途退出也不重复滚）。
视图侧 `RollingMoneyText` 新增 `rollKey` 参数，onAppear／值变化／键变化
统一走 `plan` 决策；Reduce Motion 仍直出终值（但照样落档）。

**全 App 使用位置清单**（全仓仅 ChartsView 5 处，已统一套新策略；
键＝指标名＋范围，自然年档带年份，各范围存档互不串扰）：
1. 图表总览·累计收 `charts.totalReceived.<范围>`
2. 图表总览·累计送 `charts.totalGiven.<范围>`
3. 图表总览·净往来 `charts.net.<范围>`
4. 图表总览·待回礼合计 `charts.pendingTotal.<范围>`
5. 关系环图中心·关系往来总额 `charts.relationTotal.<范围>`

页内切换范围导致的值变化走同一规则：与该范围的存档比对，变了才滚。

## 版本与产物

- Project.swift：App/Widget 的 MARKETING_VERSION 与 plist 字面量同步
  5.4.0 / 59（休眠 Share target 的 4.6.0/46 按历版口径不动、不进包）。
- 单测基线 194，本版新增 9 个（draft_record 组装 5、对话持久化 2、滚动策略 2），合计 203。

## 真机待验（逐条对应五诉，未验不宣称已验）

1. **验证转已验证**：AI 管家页填 Key 点验证，应显示「已验证」；故意填错 Key，
   失败文案应带服务端真实原因（如鉴权失败原文），不再是光秃秃的 400。
2. **语音记一笔全流程**：问账页说/打「张三随礼了 500」→ 出待确认记账卡 →
   改选礼簿 → 确认入账 → 回执出现 → 点「查看这笔」进记录详情；再说一句
   缺金额的（「李四随礼了」）应被追问而不是乱记；点「算了」不留记录。
3. **点麦克风不崩**：问账页与「记一笔」两处入口反复点麦克风（含授权弹窗
   流程中途点停、录音中离开页面再回来），不闪退；拒绝授权时给人话提示。
   （④ 的隐患为代码审计推定，以本条实测为准。）
4. **退出重进对话还在**：问几句账、记一笔并确认 → 离开问账页再回来 →
   对话与回执卡都在；菜单「清空对话」确认后清空且重进仍为空。
5. **图表二进不滚**：进图表页首次金额滚动一次 → 离开再进，金额静态直出；
   新记一笔让某指标变了 → 再进图表页只有变了的指标滚动；页内切范围同理。
