# v5.11.6 NOTES —— 成书路径缩层（审查整改第 2 件）

- 分支：`feat/v5116-book-path`（基线 `feat/v5115-print-cover-fix` 顶端 34f1926）
- 主体提交：395e5e3；版本：App/Widget 均 5.11.6/77
- 背景：PM 线审查第一维定案——成书旗舰卡在首页第 1 层可见，但旧落点先进礼簿详情（HomeView `ledgerRoute`），再经详情页导出 sheet 的「装订成书」行才到 BookBindingView，首页到成书说明共 **4 层**，是全产品最深的高价值路径。用户已批准整改，本版只动导航落点，不动任何口径/文案/卡片形态。

## 两态落点（本版新口径）

| 卡态 | 出现位置 | 旧落点 | 新落点 | 呈现 |
|---|---|---|---|---|
| 升位态（场次日期已过＋成册笔数 ≥20） | 礼簿段顶部 | 礼簿详情 | **BookBindingView（成书说明/登记页）直达** | NavigationStack push（`bookRoute` + `navigationDestination(item:)`，沿现有 ledgerRoute 模式） |
| 常驻态 | 礼簿段下方 | 礼簿详情 | **LibuExportView（导出礼谱页）直达**，装订成书行就在该页内 | sheet（`exportTarget`，与详情页导出同一呈现；LibuExportView 自带 NavigationStack 与「取消」，不嵌套 push） |

路径：首页 → 成书页由 4 层缩为 **2 层**（升位态点卡即达；常驻态点卡直达导出页，成书行在页内）。

## 落点决策（Core 纯函数，单测钉死）

- 新增 `Sources/LiqianCore/BookFlagshipRoute.swift`：
  - `BookFlagshipCardState`（`.promoted` / `.standing`）——只承载卡态，判定规则仍在 HomeView（依赖账面数据）；
  - `BookFlagshipDestination`（`.bookBinding(ledgerID:)` / `.export(ledgerID:)`）——只定去哪页、为哪本簿，导航机制留 App 层；
  - `BookFlagshipRouter.destination(state:ledgerID:)` 纯函数。
- 新增 `Tests/LiqianCoreTests/BookFlagshipRouteTests.swift` 4 个用例：升位→成书页、常驻→导出页、礼簿 ID 原样透传（换簿跟换）、两态落点永不相同（防回归同落点）。CI 日志逐个实查 passed。
- HomeView 旗舰卡点按改为消费该决策：升位置 `bookRoute`、常驻置 `exportTarget`；卡的文案、视觉、出现/升位规则（`promotedBookLedger` / `flagshipBookLedger` / `bookPromotionMinCount`）一字未动。

## 数据透传口径（常驻态直达导出页）

直达导出页与「详情页→导出」必须生成同一份谱，故 HomeView 新增与 LedgerDetailView 逐行同口径的透传：本簿记录（按日期倒序）、本簿签名、本簿祝福（只算挂在现存记录上的）。为此 HomeView 新增 `@Query allSignatures / allBlessings` 两条查询。LibuExportView、BookBindingView 内部零改动。

## 路由改动面

-  HomeView 新增状态：`bookRoute: Ledger?`（push）、`exportTarget: Ledger?`（sheet）。
- 新增一条 `navigationDestination(item: $bookRoute)` 与一条 `sheet(item: $exportTarget)`，均按 HomeView 现有模式加，未重构导航、未引入路由枚举改造。

## 保留的旧路径清单（全部原样可用）

1. 首页礼簿行点按 → 礼簿详情（`ledgerRoute`＋zoom 转场不变）。
2. 礼簿详情页「导出礼谱」→ LibuExportView sheet（详情页入口不变）。
3. LibuExportView 内「装订成书」NavigationLink → BookBindingView（导出页内入口不变）。
4. 详情页其余入口（批量补录/拍照识别/现场模式/生成贺词等）全部未动。

即：4 层旧路不删，只是旗舰卡不再绕它。

## 红线自查

- 成书卡文案/视觉/升位规则：diff 逐行核，未动（仅点按动作与一条落点注释更新）。
- 导出页/成书页内部：零改动。问账/组件/主题：零改动。AnalyzerFeeder：不在本版 diff 名单内（实查）。
- 基线不变：不带 Share 扩展、CI 预签断言照旧。

## 验收实测（非宣称）

- **CI run 42536383559**：经 API 逐 attempt 实查，attempt 1 completed/success；job build-native 全部步骤 success（SwiftLint／Build／单测／预签断言／打包／上传一次绿、无重跑）。
- **单测 310 个、0 失败**（基线 306＋新增 4），TEST SUCCEEDED；新增 4 用例逐个 passed、无 skipped。
- **解包验**：App 与 Widget 均 **5.11.6/77**；PlugIns 仅 LiqianWidget.appex、**无 LiqianShare.appex**；App 二进制含 BookFlagship 符号（新代码确进包）。
- IPA：`~/workspace/your_files/liqian-v5.11.6/liqian-native-unsigned.ipa`（4,092,341 字节，未签名侧载包，覆盖安装、数据不动）。

## 如实声明：真机未验

待验＝①升位卡（已过场次＋记满 20 笔的礼簿）点按直达 成书说明页、且登记笔数显示正确；②常驻卡点按直达导出页，生成的礼谱与走详情页导出的逐页一致（签名/祝福不缺）；③礼簿行点按仍进详情（zoom 转场照旧）；④详情页内导出/成书入口照旧可用；⑤两条新路返回首页后，另一条路再点不串簿。
