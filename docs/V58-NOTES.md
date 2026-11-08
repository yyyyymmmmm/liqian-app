# v5.8（片一 P0）：问账「半路丢单」根治——会话页面无关化＋提问即落占位＋全链 45 秒总时限

分支 `feat/v58-advisor-delivery`（基线 feat/v58-audit），版本 5.8.0/66。
根因与修复方向以 docs/V58-AUDIT.md #11 为准：回复只在串行链全部跑完后
一次性 append、回写绑发起视图 @State＋onChange 落盘，用户中途离页或
App 被杀，回复落进已销毁状态永不落盘，只剩提问气泡；最坏时延约 180 秒。
本片只修「交付机制」——v5.7 的回答政策、提示词、收敛裁决与文案逐字
未动；卡片体系、键盘三件套、语音面板、AnalyzerFeeder 均未动。

## 一、会话持有者设计（页面无关化）

新增 `Sources/LiqianApp/AdvisorSession.swift`：
`@MainActor final class AdvisorSession: ObservableObject`，由 App 根
（LiqianApp）以 @StateObject 持有、environmentObject 注入，与
CloudSyncManager/EntitlementCenter 同一模式。AdvisorView 的两个入口
（HomeView/PeopleView 的 navigationDestination）经环境自动获得同一
实例，页面销毁/重建/切 Tab 都不影响它。

持有者职责（原 AdvisorView 的 @State＋管线整体搬入）：
- `@Published messages / isAsking / activityText / answerTrigger`：
  视图改为订阅（ForEach(session.messages)、发送键与 chips 读
  session.isAsking、过程文案读 session.activityText、触感 trigger
  读 session.answerTrigger）。
- 落盘单点化：每次变更（提问 append、完成原位替换、草稿卡回写、
  清空）由持有者直接调 AdvisorChatStore.save/clear；删去视图侧
  `.onChange(of: messages)` 回写与 onAppear 历史恢复——历史在
  持有者 init 里一次性读入（含遗孤占位收敛，见第三节）。
- 管线搬入：ask 的完整链（answerWithTools / resolveIntent /
  answerGenerally / 三条系统提示词 / activityLabel）逐字搬入持有者，
  顺序与 v5.7 完全一致（工具 → 意图 → 通用 lane → 收敛裁决）。
  视图侧 ask 只剩薄包装：停语音、清输入框、把 @Query 的账目快照
  （entries/ledgers/people）交给持有者。
- 在途任务由持有者以 askTask 持有，并以 inFlightPendingID 认领
  回写：完成回写（settle）先核对 id 才复位状态，清空对话时取消
  任务＋清认领，旧链即便跑完也写不回来、不复活回复。

## 二、占位生命周期（提问即落、原位收敛）

AdvisorChatMessage.Kind 新增 `.pending`（无关联值，老文件解码不受
影响；新 kind 的呈现分支只在问账消息行）。

```
提问 ──► append .user ＋ append .pending（同批落盘）
          │  占位行呈现＝v5.3 过程行样式（转圈＋持有者发布的
          │  当前工具人话状态），独立过程行 activityRow 随之退役
          ▼
链完成 ──► settle：按 id 找到占位，kind 原位换成正式结果
          （.answer/.result/.note 按 v5.7 收敛出口），id 不变、
          列表身份与滚动位置稳定；同步落盘、复位 isAsking
失败/超时 ─► 同一 settle 路径，kind 换成收敛兜底（致歉 note 或
          .unsupported 卡）——不存在第四种结局
清空对话 ─► 任务取消＋占位随列表一并清掉，不留残影
App 被杀 ─► 见第三节
```

占位行是消息列表的一员：离页再回来它还在原位转圈（状态文案是
持有者的最新值），完成一刻原地变正式回复，不跳行、不重排。

## 三、杀进程/离页两场景的判读法

- **离页（含切 Tab、进人物详情、锁屏后回来）**：持有者与任务都活着，
  回复照常在占位处落地并落盘；用户回到问账页直接看到正式回复。
  判读：提问后立刻离开，等半分钟回来——回复已在对话里、占位消失。
- **App 被杀（强退/系统回收）**：在途任务随进程消亡，但提问与占位
  已在提问瞬间落盘。重进时持有者 init 把读回的 pending 收敛为
  提示文案「上次这个问题没答完（App 中途被关掉了），再问我一次
  就好。」（AdvisorChatStore.reconcilingOrphanedPending，纯函数＋
  单测），收敛结果回写磁盘——不留死占位、不留永久转圈。
  取舍说明：不做「重启自动续答」——重启后账目快照与模型上下文都
  已过期，自动重跑一条用户没在看的旧问只会添乱；一句人话＋用户
  重问，是与「对话是辅助、不是账本」定位一致的最小收敛。
- **清空时在途**：任务被取消，各腿 await 抛错后由 Task.isCancelled
  守卫逐段退出；settle 的 id 守卫是第二道保险。
- 旧版本（≤5.7）写下的对话文件只有四种 kind，解码与呈现不受
  影响；5.8 写出的 pending 若被旧版本读到会整表解码失败——侧载
  只升不降，不做跨版本降级兼容（与既有基线口径一致）。

## 四、全链 45 秒总时限：分配表

纯逻辑在 LiqianCore/AdvisorTimeBudget.swift（无状态函数，elapsed
由持有者用单调时钟 systemUptime 量好传入），单测 8 例钉死：

| 段 | 封顶 | 每腿实际超时 | 预算尽时行为 |
| --- | --- | --- | --- |
| 工具阶段（≤4 轮合计） | 27s | min(30, 阶段剩余, 总剩余) | 不起新一轮 → 落意图段 |
| 意图腿（AI 解码 1 次） | 8s | min(8, 总剩余) | 跳过 AI 解码 → 直接规则兜底 |
| 通用 lane（1 次） | 吃满总剩余 | 总剩余（前两段封顶后最坏仍剩 10s） | 不调用 → 收敛器落兜底 |

总账：27＋8＋10＝45s 封顶，旧链 4×30＋30＋30 ≈ 180s 的叠加在
分配数学上不存在。执行双路：①DeepSeekClient 的 chatTurn/chatJSON/
chatText 新增 timeout 参数（缺省 30，既有调用方不变），按腿值写入
URLRequest.timeoutInterval（与既有 30 秒口径同一机制，超时错误
文案按实际秒数呈现）；②持有者 withLegTimeout 看门狗到点取消在途
任务（URLSession data 请求响应取消抛错），防个别请求不按时限返回
时管线陪等。本地执行段（工具计算、规则兜底、引擎算数）是同步
快路径，不占网络预算。

## 五、不许动清单（自查）

- v5.7 提示词三条（工具/意图/通用）逐字搬家未改一字；账外 lane、
  铁律 1–6、draft_record 纪律原文保留（git diff 可验：文本块只在
  文件间移动）。
- AdvisorReplyConvergence 裁决与 failureApologyText 未动。
- 卡片体系（AdvisorCards/呈现）、键盘三件套（FocusState 三件均在
  视图侧原样）、语音面板与 AnalyzerFeeder 零改动。
- 持久化格式：文件路径、上限 120 条、清空语义不变；新增 .pending
  一种 kind（见第三节兼容说明）。

## 六、验收

- CI：run 42458946547 **success**（Build/单测/预签断言/打包全绿，
  日志含 `presign assertions passed (2 binaries)`）。
- 单测：**248 个、0 失败**（236 基线＋新增 12：AdvisorTimeBudget 8
  ＋占位落盘/收敛 4，AdvisorDeliveryTests）。
- 解包验：App 与 Widget 均 **5.8.0/66**；PlugIns 只有 LiqianWidget，
  **无 LiqianShare.appex**。
- AnalyzerFeeder.swift 相对基线零改动（git diff 核对）。

## 七、真机待验（不宣称已修好，装机后按此判读）

1. 提问后立刻切去别的页，等半分钟回来——回复已在对话里（账内、
   账外各一问）。
2. 提问后立刻杀 App 重进——占位已收敛成「上次这个问题没答完…」
   文案，无转圈残影。
3. 弱网/4G 下问天气与查某人：45 秒内必有回复落地（过程行文案会
   随工具推进变化）。
4. 提问在途时清空对话：不复活回复；随后新问正常。
5. 草稿记账卡回归：出卡 → 改选礼簿 → 确认入账 → 回执可点进详情；
   「算了」不留痕。
