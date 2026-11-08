# v5.10 施工笔记（片四：#7 人情总览重构＋#5 关系管理重构）

分支 `feat/v510-stats-relations`（基线 feat/v59-appearance@2be48b9），
版本 5.10.0/70（Project.swift 六处字面量）。

> **状态：代码完成并已推送，CI/IPA 未完成——被 GitHub 账户计费拦截。**
> 两次触发 workflow_dispatch（run 42461783875 及 rerun），job 均在 1–3 秒
> 内被平台拒绝启动，annotation 原文：「The job was not started because
> recent account payments have failed or your spending limit needs to be
> increased.」——不是代码失败。计费恢复后对本分支重跑 workflow 即可续完：
> CI 真绿核验、单测数核验、解包验 5.10.0/70×2 与无 LiqianShare.appex、
> IPA 归档到 ~/workspace/your_files/liqian-v5.10/。本机无 Swift 工具链，
> 本地编译/单测未跑，以上验收项全部待 CI 恢复后回填。

## #7 人情总览（StatsView 整页重写）

分工定版：图表 Tab 管图、人情总览管数＋下钻、年度报告管讲。

| 审计问题 | 改法 |
| --- | --- |
| 入口名「人情总览」与页题「统计」不一致 | 页题改「人情总览」（MeView 入口名本就是人情总览） |
| 与图表 Tab 三面重叠（关系分布两处实现） | 本页删关系分布图与 Charts 依赖；图表 Tab 保留唯一一份 |
| 写死当前年、无年份切换 | 加年份 Picker（年份集合＝有记录的年份倒序，与年度报告同一选择口径：选中失效时当前年优先、再退最近年份）；切换后结论/三格/待回/事由/排行全页随年走 |
| 纯罗列无结论层 | 顶部结论条：一句自动结论「X 年与 N 位亲友有往来，共 M 笔。待回 K 人，合计 ¥…。」 |
| 按事由行信息挤压 | 行改两行排版（名＋笔数 / 收·随金额），下加占比条（以最大事由总额为满格，金额仍墨色、条只作视觉编码） |
| 排行截断无出口、文案不合定版术语 | Top 5＋「查看全部 N 人」进全名单页（同一数据源、同一排序：收+随总额倒序，点人下钻）；差额文案改「待回 ¥X／多随 ¥X／已结清」（旧「对方多给/我多给」废除） |
| 口径混排（全时段总量挂年度段尾） | 全时段总量独立成「全部时段」段放页尾 |
| 空态不规范 | 无任何记录时整页 ContentUnavailableView；某年无事由/排行时段内一行石色「这一年还没有记录」 |

下钻三路：待回名单点人 → PersonDetailView；按事由点行 → 该事由在该年
有记录的场次（礼簿）列表 → LedgerDetailView（归属按记录年份而非礼簿
日期算，与总览聚合严格一致；排除示例账本）；排行点人 → PersonDetailView。

金额呈现守 v5.0.2 定版：本页全是汇总数字，走 StatCell（年度三格）＋
fmtMoney 墨色；SignedMoneyText 只给逐笔金额，本页刻意不用，不是遗漏。
待回口径：pending = max(balance, 0)，按所选年份内的记录算差额，
段 footer 已写明「该年收随差额」。

## #5 关系管理（RelationsManageView 整页重写）

对标微信标签管理：不再是「系统/我添加的」两段目录，而是一张平铺表
（顺序与记账选择器完全一致：预置在前、自定义按目录序在后）。

| 审计问题 | 改法 |
| --- | --- |
| 行无用量信息 | 每行右侧「N 人 · M 笔」（LedgerMath.relationUsage 现算，与 relationSummary 同口径：待送出不计；人数不重名、同一人可出现在多个关系下分别计数） |
| 不能改名 | 行尾菜单＋左滑双通道进改名弹窗；级联见下节 |
| 不能排序 | 工具栏 EditButton 进编辑模式拖动（预置行 moveDisabled）＋onMove；持久化的是自定义段相对顺序（RelationCatalog.applyOrder/extractCustomOrder），段 footer 明示「排序就是记账时选项的顺序，预置关系固定在前」 |
| 删除只藏左滑 | 行尾可见菜单（改名/删除）＋左滑＋编辑模式三通道；系统行菜单只有一条 disabled 说明「预置关系，不能改名或删除」 |
| 规则后置 | 规则 caption 移到输入框正下方，同行右侧加字数计数「n/6」；快捷候选降权为「常用的：」一行小签；改名/删除的影响写进各自确认弹窗、总规则写进列表段 footer |
| 空态不规范 | 平铺一表后不存在「自定义为空」的伪空态行；下钻页无人物时用 ContentUnavailableView |
| 点行无下钻 | 点行 → RelationPeopleView：该关系口径的人物列表（总额倒序＋差额定版术语），点人 → PersonDetailView |

### 改名级联实现与校验（用户拍板：级联改变）

- Core 纯逻辑（RelationCatalog.swift / LedgerMath.swift）：
  - `validateRename(from:rawNew:existing:)`：去空白、≤6 字；重名判定
    排除旧名自身（改回原名＝不改，放行），与系统词表或其他自定义重名
    仍判 duplicate；先于任何写入做一致性校验。
  - `renameCustom(from:to:)`：目录原位换名保序；旧名不在自定义列表
    （系统关系/不存在）返回 false 不动目录；写后回读确认新名在册。
  - `RelationCascade.map/applied`：值映射唯一口径——恰好等于旧名才换
    新名。App 层四处引用全部套这一口径：GiftRecord.relation、
    ReminderDay.relation、回收站快照 BackupRecord.relation（单条与
    整簿两种快照，TrashStore.renameRelation 新增）。
  - `relationReferenceCount(of:in:)`：引用计数不分状态（含待送出），
    改名/删除弹窗的影响笔数与级联实际改写范围严格一致。
- App 层 performRename 顺序：校验 → 目录改名 → 记录/提醒逐条映射 →
  回收站快照 → save → 复查残留（recordRefs＋reminderRefs 仍 >0 则
  弹窗报错，不静默）。系统关系在 UI 层无改名入口，Core 是第二道防线。
- 单测（Tests/LiqianCoreTests/RelationRenameTests.swift，新增 13 例）：
  改名校验五例、目录原位改名与系统名拒绝、整表拖动提取顺序与落盘、
  级联三类引用合并验零残留（旧名计数 0、无关值一位不动）、引用计数、
  用量人数/笔数口径（含与 relationSummary 笔数对齐、待送出排除）。

### 删除语义

只删目录选项（RelationCatalog.remove），已记记录与提醒上的关系名
保留不变（pickerOptions 的临时并入口径保证旧记录编辑时选中态不丢）。
确认弹窗按引用笔数说话：「『X』正被 N 笔记录使用。删除后，这些记录
上的关系名保留不变，之后记账将不再有此选项。」（审计原文口径）；
0 笔时单说「还没有被任何记录使用」。与改名的区别是刻意的：改名是
「把这个关系改对」，删除是「以后不再提供这个选项」。

### 其余取舍

- 管理页用量/引用计数按全部记录算（含示例账本与待送出），不做
  StatsView 那种统计隔离：管理页管的是数据本身，行内数字必须与
  改名/删除真正触及的范围一致。
- 人情总览「查看全部」落点是页内全名单而非跨 Tab 跳往来页：总览在
  「我的」Tab 的导航栈内，跨 Tab 切换不在本页职权；页内名单的数据源
  与排序与往来页总额口径一致，点人同样进往来详情，目标达成。

## 改动文件

- Sources/LiqianCore/LedgerMath.swift：RelationUsage＋relationUsage＋
  relationReferenceCount（纯增量）
- Sources/LiqianCore/RelationCatalog.swift：validateRename/renameCustom/
  extractCustomOrder/applyOrder＋RelationCascade（纯增量）
- Sources/LiqianApp/StatsView.swift：整页重写（含 AllRankingView、
  OccasionLedgersView）
- Sources/LiqianApp/RelationsManageView.swift：整页重写（含
  RelationPeopleView）
- Sources/LiqianApp/TrashStore.swift：新增 renameRelation 级联一站
- Tests/LiqianCoreTests/RelationRenameTests.swift：新增 13 例
- Project.swift：5.10.0/70

零改动确认：AnalyzerFeeder.swift、AdvisorView.swift（含
TypewriterMarkdownText）、问账全链、语音链、主题/图标、法务文本、
金额与待回口径本身均未触碰（git diff 文件清单可证）。

## 验收（待 CI 恢复后回填）

- [ ] CI run：待重跑（计费拦截，见文首状态）
- [ ] 单测：预期 271＋13＝284、0 失败（以 CI 日志最大 Executed 行为准）
- [ ] 解包验：App/Widget 均 5.10.0/70、PlugIns 无 LiqianShare.appex
- [ ] IPA：~/workspace/your_files/liqian-v5.10/liqian-native-unsigned.ipa
- [ ] 真机待验：总览切年份全页口径随动、事由下钻场次对得上、排行
  查看全部与点人下钻；关系改名后旧记录/提醒/回收站恢复的记录全变
  新名、拖动排序后记账选择器顺序跟随、删除弹窗笔数与实际引用一致
