# v5.2 AI 管家问账全面升级（工具调用）

## 一、盘点：v4.4 管家到底能答什么、为什么许多问题回不了（以代码为准）

现行实现三件套：`Sources/LiqianApp/AdvisorView.swift`（UI＋管线）、
`Sources/LiqianApp/DeepSeek.swift`（客户端）、`Sources/LiqianCore/Advisor.swift`
（意图解析＋规则兜底＋本地执行引擎）。实际数据流：

**喂给模型的上下文＝只有问题原文本身。** 模型不看任何账目数据，只把问题
翻成一个结构化意图 JSON：`{intent, person, year, direction, type}`，其中
intent 是 5 类枚举（balance/person/pending/period/type）。解码结构
`AdvisorIntentParse.RawIntent` **故意不声明任何金额字段**，模型夹带的数字
会被 Decodable 直接丢弃。金额随后由 `AdvisorEngine` 在本地对 `EntrySnapshot`
快照（person/relation/amountCents/direction/date/status/ledgerType/ledgerID）
用 LedgerMath 口径计算，UI 渲染成 5 种结构化卡片。

AI 未就绪/解析失败时，`AdvisorRules` 用关键词表兜底同一套 5 类意图；
再兜不住返回 `.unsupported` 卡（「这个问法我还不会」）。

**必然回不了的问题（逐类举例，根因都在意图枚举与参数形状上）：**

| 缺口 | 例问 | 为什么回不了 |
|---|---|---|
| 时段只能按「年」 | 「最近三个月随了多少」「三月份收了多少」 | 意图参数只有 year（整年），没有日期范围；规则层同样只有年份解析 |
| 两时段对比 | 「今年和去年比哪个多」 | 意图是单次查询、无对比结构；period 卡只汇总一个时段 |
| 趋势/序列 | 「最近半年每月收随怎么样」 | 没有按月分组的意图与卡片（数据在 Charts 的 monthlyAggregates 里，管家用不上） |
| 关系维度 | 「亲戚一共随了多少」「同事收了多少」 | 意图参数没有 relation；relationSummary 存在但管家无路径调用 |
| 按礼簿查 | 「我婚礼那本收了多少」 | 参数只有事由 type，没有礼簿标题/实例维度 |
| 逐笔筛选组合 | 「婚礼上随了 1000 以上都有谁」「上个月都有谁来随礼」 | person 意图只查单人；没有任意组合筛选＋逐笔返回的通道，金额门槛更无处表达 |
| 下一场/安排 | 「下一场是什么时候」「备礼备了哪些」 | 意图枚举里根本没有事件类；备礼（待送出）在合计口径里被排除，管家无从谈起 |
| 回礼建议 | 「大舅孩子满月我该回多少」 | 没有「先查差额与最近往来、再组织建议」的路径；ReplyAdvisor 规则在人物详情页，管家接不上 |
| 排序/极值追问 | 「待回最多的是谁」「随得最多的人是谁」 | pending 卡给全名单但意图层没有排序/极值语义，问法稍变就落 unknown |

**根因坐实**：不是「塞给模型的汇总上下文不够多」，而是更前一层——
v4.4 是「单次意图分类」模式：问题空间被 5 类枚举×（人/年/方向/事由）
四个参数锁死，枚举外的问法在结构上无处落地。任务书预判的「一次性塞
汇总上下文」与实况略有出入（现行连汇总都不塞、只塞问题），但结论一致：
要扩覆盖，必须换成「模型自主查询」而非继续加意图。

## 二、升级路线：function calling（工具调用）

DeepSeek 官方 API（api.deepseek.com，deepseek-chat）支持 function
calling：请求体带 `tools`（函数定义数组）与 `tool_choice`，模型需要
数据时返回 `message.tool_calls`，应用本地执行后以 `role:"tool"` 回填
结果再请求。本实现按此文档口径落地（`DeepSeekClient.chatTurn`）。

**未能实测的部分（如实标注）**：本机没有用户的 DeepSeek Key，无法对
真实接口做一次带 tools 的实调；接口若在真机返回 400（不支持/参数被拒）
或异常，`AdvisorView.ask` 会捕获并**降级回 v4.4 意图＋卡片管线**，
用户侧最差退化为现行体验，不白屏。真实问答效果列入真机待验。

## 三、实现结构

- `Sources/LiqianCore/AdvisorTools.swift`（新增）：
  - `AdvisorTools.definitionsJSON()`：五个工具的 function 定义
    （参数只有筛选条件，没有任何金额入参）；
  - `AdvisorToolEngine.execute`：本地执行，结果以 JSON 文本回模型；
    失败也回 `{"ok":false,"error":"人话"}`，让模型换问法或如实告知；
  - 金额口径全走 LedgerMath：待回＝max(balance,0)、待送出不计入任何
    汇总（与全 App 一致）；金额以「元」数值回给模型。
- 五个工具：
  - `query_person(name)`：收/随/差额/待回/笔数/最近日期/关系＋最近 5 笔；
  - `query_records(person?, ledgerType?, ledgerTitle?, dateFrom?, dateTo?, direction?, limit≤50)`：组合筛逐笔，返回总数＋最近若干笔（待送出带状态标注）；
  - `aggregate(groupBy=month/year/type/relation/ledger/none, dateFrom?, dateTo?, compareFrom?, compareTo?)`：分组汇总＋可选两时段总计对比与差值；
  - `pending_list(limit≤30)`：待回名单按金额降序＋总人数/总额；
  - `upcoming_events(limit≤10)`：date≥今天的礼簿场次（标题/事由/日期/剩余天数）＋待送出备礼清单。
- `Sources/LiqianApp/DeepSeek.swift`：新增 `chatTurn(messages:toolsJSON:)`
  与消息/工具调用值类型；Keychain 与既有 chat 路径未动。
- `Sources/LiqianApp/AdvisorView.swift`：
  - 主路径：AI 就绪 → 工具问答循环（**最多 4 轮工具调用**防死循环，
    轮尽落卡片管线）；失败/未就绪 → 原 resolveIntent＋卡片管线原样；
  - 模型文字答复走新消息形态 `.answer`（卡面正文），与结构化卡片共存；
  - 示例 chips 扩为 6 个（见覆盖表）；输入区隐私文案改为如实口径。

## 四、问答纪律（系统提示词写死，`toolSystemPrompt`）

1. 数字只能来自工具结果；工具没查到就说「账里查不到」，禁止编数；
2. 相对时间换算成绝对日期再调工具；
3. 回答带口径出处（「据你 2026 年的账」式）；
4. 回礼建议必须先 query_person 查差额与最近往来，建议金额只能引用
   工具数字或其明确加减；
5. 工具报错回读 error、可换参数重试，总轮数 ≤4；
6. 只答人情账目问题。

## 五、问题覆盖表（七类 × 示例 × 预期工具路径）

| 类别 | 示例问法 | 预期工具路径 |
|---|---|---|
| 查人 | 「我和大舅谁欠谁」 | query_person(大舅) → 差额/待回成答 |
| 查人 | 「张三最近一次往来是什么时候、多少钱」 | query_person(张三) → lastDate＋recentRecords |
| 查账 | 「今年三月都有谁随了礼」 | query_records(dateFrom/dateTo=三月, direction=given) |
| 查账 | 「婚礼那本簿里收的都有谁」 | query_records(ledgerType=婚礼 或 ledgerTitle) |
| 对比 | 「今年和去年比，收礼哪个多」 | aggregate(2026 全年, compare=2025 全年) → delta |
| 对比 | 「亲戚和朋友哪边往来多」 | aggregate(groupBy=relation) |
| 待回 | 「谁还没回礼」 | pending_list |
| 待回 | 「待回最多的是谁、一共欠我多少」 | pending_list → 首行＋totalPendingYuan |
| 趋势 | 「最近三个月每月随了多少」 | aggregate(groupBy=month, 近三月范围) |
| 趋势 | 「这几年每年收随走势怎么样」 | aggregate(groupBy=year) |
| 回礼建议 | 「大舅孩子满月，我该回多少合适」 | query_person(大舅) 查差额与最近收礼 → 按纪律 4 组织建议 |
| 回礼建议 | 「王五随过我 800，他家办寿我回多少」 | query_person(王五) → 以其差额/最近往来为据 |
| 场合统计 | 「婚礼一共收了多少」 | aggregate(groupBy=type) 或 query 侧证 |
| 场合统计 | 「白事一共随出去多少」 | aggregate(groupBy=type) 取白事行 |

## 六、隐私口径

数据仍只发用户自己在「我的 → AI 智能助手」里配置的 DeepSeek 接口。
工具模式下发出的内容＝问题文字＋**本次问题实际调用工具后返回的结果**
（按需查询的子集），不带与问题无关的全量账目——相比「塞全量上下文」
方案泄露面小一个量级；相比 v4.4（只发问题）多出的部分仅是组织回答必需
的查询结果，且仍在用户自选接口内。管家页输入区文案已同步改成此口径。

## 七、未动清单（硬规矩核对）

- AI 设置页（AISettingsView）与 Keychain 存取零改动；
- 结构化卡片渲染路径（resultCard 全套）零改动，工具答复与其共存；
- LedgerMath 既有口径零改动；意图解析/规则兜底零改动（降级依赖它们）。

## 八、验收实测（2026-11-08 本机亲验）

- CI：run 42443484957 **success**（手动 workflow_dispatch 于本分支；
  工作流仅 main 推送自动触发——与历版同口径）。日志含
  `** BUILD SUCCEEDED **`、`** TEST SUCCEEDED **`、
  `presign assertions passed (2 binaries)`。
- 单测：日志逐条去重计数 **175 个唯一用例全过、0 失败**（基线 163
  ＋新增 AdvisorToolsTests 12 例：五工具各有正常例与空/错例）。
- 解包验：App 与 Widget 均 **5.2.0/54**；PlugIns 只有 LiqianWidget，
  **无 LiqianShare.appex**；二进制 strings 抽查含 query_person /
  query_records / aggregate / pending_list / upcoming_events。
- IPA：`~/workspace/your_files/liqian-v5.2/liqian-native-unsigned.ipa`
  （3,646,128 字节）。

## 九、真机待验（未验，不宣称已验）

1. 七类问题各实测一例（覆盖表问法照问）：查人（大舅差额）、查账
   （三月随礼名单）、对比（今年 vs 去年）、待回（名单与总额）、
   趋势（按月）、回礼建议（先查后建议）、场合统计（婚礼汇总）——
   核对数字与 App 内页面一致、无编造；
2. 工具调用失败时的表现：故意断网问一句 → 应落回结构化卡片或规则
   答复，不白屏不转圈到底；接口侧若不支持 tools（400），同理验降级；
3. 无 Key / 未开启 AI 时的引导：清掉 Key 问一句 → 仍走规则兜底，
   且「我的 → AI 智能助手」引导文案正常；
4. 轮数上限：问需要多轮组合查的问题（如先筛人再比时段），确认 4 轮
   内出答复、超限时降级而非死循环；
5. 隐私文案与实际行为一致：输入区新文案显示正确。
