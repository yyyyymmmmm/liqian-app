# v5.8.1（片二·小快打包）：删引导＋示例只留空态＋往来添加按钮/默认上次礼簿

分支 `feat/v581-quick-pack`（基线 feat/v58-advisor-delivery），版本 5.8.1/67。
三件均以 docs/V58-AUDIT.md #4/#6/#10 的结论为准，互不耦合、一版验完。
不许动清单自查：问账管线与提示词、AdvisorSession 持有者语义、语音
面板、AnalyzerFeeder（零改动）、卡片体系、金额与待回口径——均未动。

## 一、#4 设置页去引导（MeView）

删除两行＋一处接线，逐组对照：

| 位置 | 删前 | 删后 |
| --- | --- | --- |
| 「帮助」组 | 「重看引导」Button（sparkles，拉起 fullScreenCover 的 OnboardingView）＋「意见反馈」Link | 只剩「意见反馈」Link |
| 「数据」组 | 同步开关/系统设置捷径/导出备份/导出 CSV/从备份恢复/最近删除/「示例礼簿」Button | 只少最后一行「示例礼簿」，其余六行原样 |
| 接线 | `@State showOnboardingReplay`＋`.fullScreenCover(isPresented:)` | 一并删除 |
| 连带清理 | MeView 私有 `hasSamples`/`toggleSamples()` 只为示例行服务，随行删除 | SampleData 本体未动 |

保留与防误删：
- **首开引导本体不删**：OnboardingView 与 ContentView 的首开呈现
  （一次性标记、`onboardingPresentation`）原样；删后全仓再无设置内
  重看入口，ContentView/OnboardingView 中三处提到旧入口的注释已
  同步改口径（仅注释）。
- **生成示例数据的能力不删**：入口仍在三处空态——首页（HomeView）、
  往来（PeopleView）、礼簿列表（LedgersView）均直调
  `SampleData.generate(into:)`；清空示例走 SampleData.clearSamples
  既有路径，未受影响。
- **非引导元素未误伤**：各组 footer 规则说明（数据组 iCloud 说明、
  外观组主题/落款说明）、「提醒」组备份提醒行（条件出现）、AI 管家
  行状态副标题、会员卡、关于行——逐组核对，全部在位。

## 二、#6 示例 chips 只留空态（AdvisorView）

- chips 行从 `composer`（输入坞上方常驻横滚行）整体移出，抽为
  `exampleChips` 视图，挂进欢迎卡 `introBlock`（说明文字之后、
  隐私脚注 Divider 之前），呈现条件 `session.messages.isEmpty`。
- 时序：无对话时卡内可见（点即问，行为与样式不变——Mat.tinted
  染色玻璃签＋主题染色＋令牌间距，沿 v5.3 样式语言）；用户发出
  第一条消息，ask() 即 append 用户消息，messages 非空，chips 随
  欢迎卡内容更新整体消失，此后对话再长也不回输入区上方。
- chips 原先自带的首屏入场偏移（entered/offset）随迁入并入欢迎卡
  自身的淡入上浮，不再单独一份动画。
- 不动：欢迎卡其余文案（标题/说明/隐私脚注逐字未改）、草稿记账卡、
  发送/语音/键盘三件套、会话持有者语义。

## 三、#10 往来添加按钮＋默认上次礼簿

### 往来页 FAB（PeopleView）
- 根视图 List 加 `.overlay(alignment: .bottomTrailing)` 挂
  `AddFloatingButton(label: "记一笔", bottomPadding: .tabBarClearance)`
  ——与首页/礼簿列表/礼簿详情**同一个设计系统组件**（玻璃主钮
  Mat.tinted、56pt、令牌一致），不是新造按钮。
- 避让沿首页口径：List 加 `.contentMargins(.bottom, 72, for:
  .scrollContent)`；备礼清单区在场时同样生效（FAB 悬在列表之上、
  底部留白防遮最后一行）。
- 点开形态与首页「记一笔」一致：`.sheet` 呈现
  `RecordFormView(personName: "", presetDirection: .received)`
  （全局入口形态，走下面的统一默认逻辑）。PrepListView（备礼清单
  独立页）不在本项范围，未加。

### 默认礼簿决策顺序（全入口统一）
纯逻辑落 LiqianCore `DefaultLedgerPicker.pick`（新文件
Sources/LiqianCore/DefaultLedger.swift），单测 7 例钉死：

```
1. 上次使用：lastUsedLedgerID 命中且仍存在、且非示例礼簿
2. 日期最新的非示例礼簿（v4.2 现行兜底口径）
3. 日期最新的礼簿（只剩示例簿时；与现行口径一致）
4. 无礼簿 → nil（表单「先建一本礼簿」文案）
```

- **回写点**：RecordFormView 新建保存成功后回写——`save()` 新建
  分支与 `saveAIResults()`（一句话记账批量落库）各一处，均在
  `modelContext.save()` 之后、`lid` 即本次实际所记礼簿；键
  `DefaultLedgerPicker.lastUsedKey`（"lastUsedLedgerID"），
  @AppStorage 存 UUID 字符串。
- **不回写**：编辑既有记录（不做选簿动作，不算「使用」）；删除。
- **读取点**：只在 RecordFormView 的 `onAppear` 默认选择一处
  （`needsLedgerPicker` 时），故所有走「未指定礼簿」形态的入口
  ——首页记一笔、往来 FAB、人物详情记一笔、长按快捷菜单记一笔
  ——自动共用同一默认逻辑；礼簿内记账（fixedLedger）、批量录入、
  拍礼簿的目标簿由所在礼簿决定，不经此逻辑，未动。
- **示例约束保持**：示例礼簿在第一档被排除（有真礼簿时上次使用
  若是示例簿也跳过），只在只剩示例簿时经第三档兜底命中，与
  v4.2「默认不落示例簿」定版一致；统计隔离、待回口径未动。

## 四、验收

- CI：run 42459462901 **success**（Build/单测/预签断言/打包全绿，
  日志含 `presign assertions passed (2 binaries)`）。
- 单测：**255 个、0 失败**（248 基线＋新增 7：DefaultLedgerPickerTests，
  覆盖上次使用命中/已删兜底/示例约束跳过/只剩示例/无历史/全示例/空）。
- 解包验：App 与 Widget 均 **5.8.1/67**；PlugIns 只有 LiqianWidget，
  **无 LiqianShare.appex**。
- AnalyzerFeeder.swift 相对基线零改动（git diff 核对）。

## 五、真机待验（不宣称已验）

1. 「我的」页：帮助组只剩意见反馈、数据组无示例礼簿行；其余组
   （会员卡/总览/提醒/外观/AI/协作/隐私/关于）逐组无缺失；首开
   引导在全新安装时照常出现。
2. 问账：全新对话欢迎卡内有示例 chips，点任一签即问且 chips
   消失；有历史对话进入时欢迎卡无 chips、输入区上方干净。
3. 往来页：右下 FAB 点开记账表单；在 B 簿记一笔保存后，回到
   往来再点 FAB，表单默认礼簿为 B；删掉 B 后再记，默认回落到
   日期最新真礼簿；全程不默认落到示例礼簿（有真礼簿时）。
