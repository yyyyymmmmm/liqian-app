# v5.3 问账（管家对话）页体验重做

## 一、病灶（用户截图实锤，逐条对账）

| # | 病灶 | 本版治法 |
|---|---|---|
| 1 | 回答把 Markdown 原样印上屏（「- **2026 年（今年）**」星号横杠全露） | 结论文字走 Markdown 渲染（AttributedString 完整语法）＋兜底去标记，任何路径下不露标记（见三） |
| 2 | 工具查到结构化数据、页面只剩文字墙；v4.4 意图管线本来有卡片，v5.2 工具路径呈现退化 | 工具执行同一路径加挂结构化卡片模型（AdvisorCard），五工具各出其卡，模型文字退为结论引子（见二） |
| 3 | 查账过程黑箱：只有一句「正在查账…」到底；消息整块蹦出、无入场 | 按工具映射的人话过程状态＋结论打字机揭示＋消息入场/卡片依次浮入（见四） |
| 4 | 气泡/示例签/麦克风/发送键是系统默认样式与默认蓝，没走 v5 令牌 | 全页令牌扫尾：气泡 Mat.tinted 染色玻璃、示例签 Mat.tinted、麦克风 Mat.regular 玻璃圆、输入栏整栏 Mat.regular 玻璃、发送键三态（见五） |

注（任务书口径）：着色一律走 DesignTokens 的 Mat＋主题染色令牌——用户当前
主题若是腾讯蓝，令牌色本就是蓝；治的是「默认样式感」，不写死任何颜色。

## 二、卡片化呈现（Core 挂 UI 侧结果，不另查一遍账）

- 新增 `Sources/LiqianCore/AdvisorCards.swift`：卡片模型
  `AdvisorCard`（七形）＋负载结构（AdvisorMoneyTotals / AdvisorRecordRow /
  AdvisorPersonCard / AdvisorRecordsCard / AdvisorComparisonCard /
  AdvisorGroupsCard / AdvisorTotalsCard / AdvisorPendingCard /
  AdvisorEventsCard）＋双产出容器 `AdvisorToolOutcome`（json＋card）。
- `AdvisorToolEngine.executeDetailed`：在每个工具算出数据的**同一作用域**
  里把同一份数据组装成卡（分口径，与回模型的元口径 JSON 同源换算）；
  `execute` 改为委托它取 json，模型侧返回语义不变（单测对象级比对把守）。
- 映射定版：
  - query_person → 人物卡（复用 v4.4 人物卡外壳：差额大字＋收随笔数行，
    内容加最近 5 笔；点头像行进人物详情）；
  - query_records → 逐笔流水卡（限量行走 SignedMoneyText，白事降饱和、
    待送出行挂 PendingTag；卡尾给总数提示）；查无结果不出卡；
  - aggregate → 对比卡（两期各一组收/随双条＋收礼差/随礼差/净差三项，
    差值为主 − 对比）/ 分组条卡（按月/年/场合/关系/礼簿，一组一节双条）/
    汇总卡（不分组无对比时）；三者优先级：对比 > 分组 > 总计；
  - pending_list → 待回名单卡（逐行姓名＋SignedMoney 待回额，点行直达
    人物；卡头给总人数与合计；空名单照常出卡给「都结清了」空态）；
  - upcoming_events → 场次卡（名称/事由日期/剩余天数＋备礼进度区：
    待送出总数与逐笔行）；全空照常出卡给空态。
- 失败/查不到（ok == false）一律不出卡，模型按既有纪律如实说明。
- 一张回答可带多卡：多工具/多轮的卡按调用顺序 append，视图依次呈现。
- 轮数耗尽降级时，半成品卡片随 nil 一起丢弃，整条回答完整落回 v4.4
  卡片管线，不拼半截。
- 金额分界守 v5.0.2 纪律：逐笔走 SignedMoneyText（符号＋语义双色）；
  差值/合计/汇总数字保持墨色；条形只是视觉编码（收随双色与图表系列
  同口径），条旁数字仍墨色。

## 三、文本渲染（不露标记）

- `TypewriterMarkdownText.render`：`AttributedString(markdown:)` 完整
  语法解析（粗体/列表/链接正常呈现）；解析失败兜底 `stripped`——剥
  `**`/`__`/反引号与行首标题符、列表符后的纯文本。两条路径都不露标记。
- 结论引子、note 文案分工不变：note 是本地拼的纯文案，本就不走 Markdown。

## 四、过程与动效（Motion 令牌，Reduce Motion 全降级）

- 过程状态：查账行＝转圈＋当前动作人话文案，按工具映射——
  query_person「正在查「X」的账…」（人名从参数解析，失败回通用文案）、
  query_records「正在逐笔翻记录…」、aggregate「正在汇总对比…」、
  pending_list「正在翻待回名单…」、upcoming_events「正在看近期场次和
  备礼…」；工具执行完等待模型组织语言时「正在整理答案…」；
  状态切换走 pageCrossfade 交叉淡化。
- 打字机揭示：DeepSeek 客户端无流式协议（不为流式重构客户端），本地
  揭示——**先整段 Markdown 解析、再按字数裁剪渲染后的 AttributedString**
  （经 NSAttributedString 子串），格式在每一帧都完整，不存在半个 `**`
  的中间态；约 3 字/16ms，揭示期间节流回调把本条钉在滚动底部。
  Reduce Motion 时整段直出、不回调滚动。
- 入场：页面打开时欢迎卡淡入上浮、示例签随之入场；消息行插入走
  淡入＋上浮 8pt 的 transition（栈上以 messages.count 驱动
  pageCrossfade）；回答的卡片走 CardInModifier 按序错开（首卡 0.12s、
  每张 +0.12s）淡入上浮。以上全部经 MotionTokens.resolved /
  reduceMotion 分支降级（Reduce Transparency 由系统玻璃自动回退实色）。

## 五、令牌扫尾（与 v5.2.1 AI 管家设置页成一套）

- 用户气泡：primaryTint 平面填充 → Mat.tinted 染色玻璃（controlCorner）。
- 示例签：平面浅染 Capsule → Mat.tinted 玻璃 Capsule，文字仍主题主色。
- 麦克风：裸图标 → Mat.regular 玻璃圆底（录音态仍 danger＋.pulse 不变）。
- 输入栏容器：Palette.surface 平面底 → Mat.regular 整栏玻璃
  （liqianGlassSurface，功能层玻璃定版位置）。
- 发送键：原「问」字圆钮（石色/填充两态）→ 三态：空输入＝line 圆＋
  石色上箭头（禁用）、可发＝primaryFill 圆＋白色上箭头、发送中＝
  同填充＋白色转圈。着色全部来自令牌、无系统默认蓝残留（主题是
  腾讯蓝时填充即随主题为蓝，属令牌而非默认样式）。

## 六、未动清单（硬规矩核对）

- 工具集与定义（AdvisorTools.definitionsJSON）、问答纪律、两套系统
  提示词（toolSystemPrompt / intentSystemPrompt）——本版 diff 逐字校验
  与 v5.2.1 一致（脚本比对 IDENTICAL）；
- 工具问答 4 轮上限、失败降级 v4.4 意图＋卡片管线（resultCard 全套
  函数体未动，diff 校验 HEAD-SAME）；
- AI 设置页、Keychain 与 DeepSeek 客户端协议（chatTurn 未动，
  不引入流式）；LedgerMath 口径未动。

## 七、验收实测（2026-11-08 本机亲验）

- CI：首跑 run 42444970197 红——唯一失败是本版自加的 JSON 一致性
  测试用了逐字字符串比对（JSONSerialization 键序每次随机，内容
  全同、顺序不同，属测试口径 flaky，非实现问题）；改为解析后对象
  比对后重跑 run 42445233632 **success**：日志含 `** BUILD SUCCEEDED **`
  （×2）、`** TEST SUCCEEDED **`、`presign assertions passed (2 binaries)`。
- 单测：日志逐条去重计数 **194 个唯一用例全过、0 失败**（基线 181
  ＋新增 AdvisorCardsTests 13 例：五工具卡片映射、对比优先于分组、
  空名单出卡、查无不出卡、JSON 对象级一致各有断言）。
- 解包验：App 与 Widget 均 **5.3.0/56**；PlugIns 只有 LiqianWidget，
  **无 LiqianShare.appex**；App 二进制 strings 抽查含
  TypewriterMarkdownText / AdvisorCard，Core 框架含
  AdvisorComparisonCard / AdvisorPendingCard / AdvisorEventsCard。
- IPA：`~/workspace/your_files/liqian-v5.3/liqian-native-unsigned.ipa`
  （3,812,478 字节）。

## 八、真机待验（未验，不宣称已验）

1. 五类问题各出一卡：查人（「我和大舅谁欠谁」→ 人物卡）、流水
   （「三月份都有谁随了礼」→ 逐笔卡）、对比（「今年和去年比，收礼
   哪个多」→ 对比卡双条与差值）、名单（「谁还没回礼」→ 名单卡点行
   进人物页）、场次（「下一场是什么时候，备礼备了吗」→ 场次卡
   剩余天数与备礼行）；分组问法（「最近三个月每月随了多少」→
   按月分组条卡）与纯汇总问法各验一例；
2. Markdown 不露标记：让模型答出带粗体与列表的长答案，确认屏上
   无 `**`、无行首 `- ` 原样残留，粗体/分行正常；
3. 流式手感：打字机速度是否舒服（长答案约 3 字/16ms 全程时长）、
   揭示期间自动钉底不跳、手动上滑看旧消息时不被强拉（若被拉回，
   记为待修）；
4. 过程状态：多工具问题（如先查人再对比）看状态文案随工具切换、
   「正在整理答案…」衔接正常；断网/接口 400 时仍完整降级 v4.4 卡片；
5. 减弱动效降级：系统开 Reduce Motion 后——打字机整段直出、卡片
   无错峰浮入、消息无入场位移、入场动画全无；Reduce Transparency
   开时玻璃回退实色且文字可读；
6. 主题一致性：逐个切换五主题，气泡/示例签/发送键/输入栏玻璃染色
   随主题走（腾讯蓝主题下为蓝令牌、非系统默认蓝观感），与「我的 →
   AI 管家」设置页并排看是否成一套；
7. 发送键三态：空输入禁用态、可发态、发送中转圈各看一眼；
   语音输入（录音脉冲、转写回填）不回归。
