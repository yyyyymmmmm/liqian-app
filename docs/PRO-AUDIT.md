# 礼钱账本 · 专业化审校报告（PRO-AUDIT）

审校日期：2026-11-07。范围：`Sources/` 全部视图与文案、设计令牌、导出物。
本报告只审校、不改代码。所有结论可回溯到具体文件。

## 方法与依据（先声明方法，不凭感觉）

- **Hallmark**（`local-hallmark/SKILL.md` + `references/gates.md`）：Floor 门 48（颜色/字体字面量必须走令牌）、63（禁用中点拼接的元信息串）、19（文案套话黑名单）、40/41（对比度与成对墨色令牌）。
- **Unslop**（`local-unslop/SKILL.md`）：§1 间距 4px 网格、§2 一条中性色阶 + 一个强调色 + 三种文字角色、§4 文案（短标签不加句号、不用感叹号、不用 hype 词）、§5 字阶与字重（400/500 为主、600 罕用）、§7 图表与状态点。
- **花叔 Design**（`local-huashu-design/references/critique-guide.md`）：常见问题 Top 10 之 #3 颜色过多（≤1 主 +1 辅 +1 强调 + 灰阶）、#4 间距不统一（8pt 网格）、#6 字体过多（≤2 家族）。
- **Claude UI Designer**（`local-claude-ui-designer/SKILL.md`）：8pt 网格（4/8/12/16/24/32/48…）、60-30-10 色彩占比、字阶须成比例数列、最多 4–6 个字号、嵌套圆角公式（内圆角 = 外圆角 − 内边距）。
- **Claude Design System**（`local-claude-design-system/SKILL.md` + `references/audit-checklist.md`、`naming-conventions.md`）：Step 0 覆盖门（系统是否存在）、Step 1 令牌漂移扫描、三层令牌（原始→语义→组件）、语义命名优先于视觉命名、令牌覆盖率指标。

取证方式：全量 grep（283 条用户可见字符串、字号/间距/圆角/颜色字面量分布、令牌引用计数）+ 逐文件通读 `Palette.swift`、`Components.swift` 与全部视图。

---

## 一、术语表（定死口径）

现状病灶：一套概念四套叫法。以下为定版，左列是唯一正式词，右列为禁用变体及其现存位置。

### 1.1 核心对象

| 概念 | 正式词（定版） | 使用场景 | 禁用变体（现存证据） |
|---|---|---|---|
| 一场事的册子（数据对象） | **礼簿** | App 内一切指代：列表、详情、新建、删除、回收站 | 单字「簿」（BatchEntryView 同名提示「本簿已有此人」）；「账本」指代单本（App 名「礼钱账本」中的账本只指产品本身） |
| 导出的成品 PDF | **礼谱** | 仅导出语境：入口「导出礼谱（PDF）」、PDF 封面/页脚、礼谱设置项 | 在 App 数据语境里把礼簿叫礼谱（LibuExportView 的落款/设置文案需逐句核对）；反之 PDF 里自称「账本」 |
| 往来对象（人） | **亲友** | 一切指人处：往来排行、差额、搜索提示 | 「人物」（PeopleView/PersonDetailView 的内部叫法外溢到文案）；「人」单字成词（LiqianWidget.swift:108「人还没回」） |
| 往来这件事（抽象） | **人情往来**（页面/概念），Tab 与页名简作 **往来** | Tab 名、页面标题统一「往来」；「人情」只活在专名「人情年度报告」与概念句里 | Tab「人情」（ContentView.swift:30）与页内「人情往来」「人情年度报告」三级跳；拿「人情」指人 |
| App 本体 | **礼钱账本** | 关于、锁定页、导出落款 | 无（此项现行一致） |

### 1.2 方向与状态

| 概念 | 正式词 | 禁用变体（证据） |
|---|---|---|
| 收到（入） | **收礼** | 单字「收 」（Components.swift:82，带尾随空格拼标签）；「收礼（别人给我）」括号口语版（RecordFormView 分段）→ 分段只用「收礼」，解释放脚注 |
| 送出（出） | **随礼** | 单字「随 」（Components.swift:89）；「随礼（我送出去）」同上处理 |
| 已送出 / 未送出 | **已送出** / **待送出** | 「待送出（先记着）」（RecordFormView.swift:181）中的「先记着」；解释句里的「先记着」一并删 |
| 差额未结 | **待回礼**（状态与功能同名） | 「还没回的礼」（MeView.swift:162 卡片名、AnnualReportView.swift:217）；「人还没回」（LiqianWidget.swift:108）；「还没回」作小组件描述（LiqianWidget.swift:148） |
| 差额结清 | **已结清** | 「两清」（PeopleView.swift:197、StatsView.swift:167）与「往来两清」（PersonDetailView.swift:192）同义两名并存，且均为口语 |
| 对方/我方小计 | **收礼合计** / **随礼合计** | 「他给我的」「我给他的」（PersonDetailView.swift:124/126）——预设对方性别为「他」，且口语 |

### 1.3 功能名逐个评

| 现名 | 判定 | 定版与理由 |
|---|---|---|
| 备礼清单 | ✅ 保留 | 品类内有认知、语义准确 |
| 待回礼 | ✅ 保留并升为唯一正式名 | 见 1.2 |
| 回收站 | ⚠️ 改名 | iOS 系统用语是「最近删除」（文件、照片皆然），「回收站」是 Windows/Android 心智。按「与 iOS 系统用语一致」原则改 **最近删除**；MeView、TrashView、全部删除确认文案联动 |
| 示例数据 | ✅ 保留词，统一句式 | 词本身专业；但同一动作现有三种文案（「先看看示例数据」「生成示例数据，先看看效果」「生成两本示例礼簿，先看看效果」）→ 按钮统一「生成示例数据」，清除统一「清除示例数据」 |
| 现场大字 | ❌ 不专业 | 「现场」是内部场景词。改 **大字模式**（与 iOS「显示与文字大小」的口径一致） |
| 一句话记账 | ✅ 保留 | 准确、有记忆点 |
| AI 解析 / 智能粘贴解析 | ⚠️ 二选一 | 页内模式名与设置文案混用。定版：模式名 **AI 解析**，功能全称只在 AI 设置页出现一次作「智能粘贴解析（AI 解析）」 |
| 批量补录 | ✅ 保留为功能正式名 | 场景准确（席后补记）；禁止再出现「批量导入」类近名（现行未出现，立规防漂移） |
| 回礼参考 | ✅ 保留 | 「参考」二字守住了不裁判的边界 |
| 人情年度报告 | ✅ 保留为专名 | 全 App 唯一允许「人情」入名的功能 |
| 礼谱落款 / 主家 / 主家谨识 | ✅ 保留 | 礼制用语准确；「主家姓名（可空）」改「落款姓名（选填）」与全 App「（可选）」口径统一（见 1.5） |
| 记一笔礼钱（快捷指令） | ❌ 改 | 与 App 内「记一笔」体系冲突。快捷指令名改 **记一笔**（QuickRecord.swift:9、:26） |
| 统计与报告 / 数据 / 隐私与安全 / 关于 | ✅ 保留 | 与 iOS 设置的分组命名习惯一致 |

### 1.4 按钮动词统一规则

现状：全 App 无「创建」按钮（好），但规则从未成文，靠默契迟早漂移。定版：

- **领域动词优先**：记账动作一律「记一笔」（方向变体「记一笔收礼 / 记一笔随礼」）；建册一律「新建礼簿」（空状态「新建第一本礼簿」保留，是同一规则的数量变体）。
- **通用创建**：非领域对象用「新建」；往已有容器中追加用「添加」（现行「加一行」改「添加一行」）。
- **删除**：一律「删除 + 对象」（删除这本礼簿 / 删除这笔记录）；二次销毁用「彻底删除」（最近删除页内）；清空整组用「清空 + 对象」。
- **恢复**：统一「恢复」，禁止「还原」混入（现行未出现，立规）。
- **保存**：表单一律「保存」；禁止「提交」（现行 DESIGN.md 已有此规，代码未犯，保留成文）。

### 1.5 单位、日期与格式规范

| 项 | 定版 | 现状与问题 |
|---|---|---|
| 金额展示 | `¥` + 千分位；整数不带小数，非整保留两位（如 ¥10,000 / ¥66.50） | `LedgerMath.fmtMoney`（LedgerMath.swift:125-128）**无千分位**：婚礼总额常上万，`¥10000` 不成体统（违反 unslop §5「数字统一格式」与大厂账单惯例） |
| 金额输入 | 标签「金额（元）」为唯一出现「元」字处；展示区禁用「元」 | 现行基本守住，维持 |
| 选填标记 | 统一「（选填）」 | 三套并存：「备注（可选）」「主家姓名（可空）」「你和主家的关系（可空）」 |
| 日期显示 | 当年：`M月d日`；跨年记录：`yyyy年M月d日`；礼谱内：干支年 + 农历 | 现只有 `M月d日` 一处格式（跨年往来会丢年份）；存储格式 `yyyy-MM-dd` 严禁出现在用户界面（现行守住） |
| 时间计量 | 阿拉伯数字 + 单位：30 秒、30 天 | 「打开 App、从后台回来超过**半分钟**」（AISettingsView/AppLock 说明）口语计量，改「30 秒」 |
| 中英混排 | 英文词（Key、AI、PDF、CSV、Excel、DeepSeek、Face ID）与中文之间留一个空格；同一外来词全 App 只用一个写法 | 「API Key」与「Key」混用（「保存 Key」「当前 Key」「删除 Key」「换一个 Key」对「还没填 DeepSeek 的 API Key」）；定版统一 **API Key** |

---

## 二、文案审校表

全量基数：283 条字符串。其中非文案性字符串 21 条（农历月份雅称 12、示例人名 4、格式/文件名常量 5）不计审校分母；**用户文案共 262 条，本表列出问题 52 条，无问题 210 条**。

问题类型分布：报错不专业 14、口头语 13、啰嗦 9、术语不统一 9、格式/标点 4、内容过期 1、营销腔 2（与上行有重叠，按主问题计）。

依据缩写：[unslop §4]=文案规则（短标签无句号、无 hype 词、标签求短）；[hallmark 19]=套话黑名单；[hallmark 63]=模板标点；[iOS]=iOS 系统用语惯例；[术语表]=本报告第一部分定版。

| # | 文件 | 原文 | 改文 | 依据 |
|---|---|---|---|---|
| 1 | DeepSeek.swift:101 | DeepSeek 的返回看不懂：… | AI 返回内容格式异常，无法解析：… | 报错须陈述事实，不用拟人化口语 [unslop §4] |
| 2 | QuickSentenceView.swift:194 | DeepSeek 的返回看不懂，换个说法再试，或者直接在表单里手填。 | AI 返回内容格式异常，无法解析。请重试，或直接在表单中填写。 | 同上；且与 #1 必须同文（同一错误两套文案） |
| 3 | LedgerTextParser.swift:62 | 没找到金额 | 未识别到金额 | 报错用书面语 [iOS] |
| 4 | LedgerTextParser.swift:65 | 金额不对 | 金额格式不正确 | 同上 |
| 5 | RecordFormView.swift:444 | 金额不对，检查一下 | 请输入正确的金额 | 与 #4 统一错误族文案 |
| 6 | LedgerTextParser.swift:70 | 缺姓名 | 缺少姓名 | 同 #3 |
| 7 | LedgerTextParser.swift:73 | 姓名里有数字，看不懂 | 姓名不能包含数字 | 陈述规则，不说「看不懂」 |
| 8 | LedgerTextParser.swift:84 | 「X」看不懂，只认关系词 | 无法识别「X」，请填写关系（如亲戚、朋友、同事） | 给出路而非抱怨 |
| 9 | LedgerTextParser.swift:87 | 内容太多，一行只记一笔 | 每行只能填写一笔记录 | 同 #3 |
| 10 | BatchEntryView.swift:225 | 一行都没填，先填几笔再保存 | 尚未填写任何记录 | 同 #3 |
| 11 | MeView.swift:102 | 备份没能存下来，再试一次。 | 备份导出失败，请重试。 | 报错标题已是「导出失败」，正文改为事实+动作 |
| 12 | MeView（备份校验） | 备份文件有问题 | 备份文件无效 | 与「这个文件读不了…」同族统一 |
| 13 | BatchEntryView（AI 解析失败） | AI 返回的格式不对，没能解析。可以再试一次，或改用「粘贴导入」的规则解析。 | AI 返回格式异常，无法解析。请重试，或改用规则解析。 | 与 #1/#2 同族统一 |
| 14 | GreetingView | 这次没生成出可用的文字，再点一次试试。 | 未生成可用内容，请重试。 | 「试试」口语 |
| 15 | BatchEntryView（AI 解析空结果） | 没解析出记录，换段文字试试，或者用「粘贴导入」的规则解析。 | 未解析出记录。请更换文本，或改用规则解析。 | 同上 |
| 16 | LiqianWidget.swift:108 | 人还没回 | 待回礼 | [术语表 1.2]；小组件与 App 内必须同名 |
| 17 | PeopleView.swift:197；StatsView.swift:167 | 两清 | 已结清 | [术语表 1.2] |
| 18 | PersonDetailView.swift:192 | 往来两清 | 已结清 | 与 #17 合并为一名 |
| 19 | PersonDetailView.swift:124/126 | 他给我的 / 我给他的 | 收礼合计 / 随礼合计 | 预设性别 + 口语 [术语表 1.2] |
| 20 | MeView.swift:162；AnnualReportView.swift:217 | 没有欠着的人情，轻松。 | 暂无待回礼记录 | 口语「轻松」；短标签带句号 [unslop §4] |
| 21 | MeView.swift:326 | 两本示例礼簿和里面的记录都清掉了，你自己的数据没动。 | 示例数据已删除，你的数据未受影响。 | 啰嗦 + 口语 |
| 22 | AISettingsView.swift:57 | 关掉后，智能解析、一句话记账、贺词生成的入口点了会先提醒，不会偷偷调用。 | 关闭后，AI 功能将不可用。 | 52 字一句到底；「偷偷」口语；且与实际行为（点了给引导）不符——文案须与行为一致 |
| 23 | AISettingsView.swift:49 | 去 platform.deepseek.com 申请，费用走你自己的 DeepSeek 账户。 | 在 platform.deepseek.com 申请 API Key，费用计入你的 DeepSeek 账户。 | 「走」口语；Key 口径不一 [术语表 1.5] |
| 24 | BatchEntryView.swift:96 | 照着旧礼簿一行行填就行。关系先按「朋友」、方式先按「现金」记，日期是今天，记完点开单笔可以再改。 | 按旧礼簿逐行填写。关系默认「朋友」、方式默认「现金」、日期为今天，保存后可逐笔修改。 | 49 字长句 + 「就行」口语 |
| 25 | RecordFormView.swift:181/185 | 待送出（先记着）/ 待送出的先记着，不算进往来差额，送出去后改成「已送出」。 | 待送出 / 待送出记录不计入往来差额，送出后请改记为「已送出」。 | [术语表 1.2] |
| 26 | BatchEntryView.swift:397 | 查看原始返回（报障用） | 查看原始返回（用于反馈问题） | 「报障」是运维黑话 |
| 27 | QuickSentenceView（语音权限三连） | …直接打字就行；要用的话去系统设置里打开。 | …可直接输入文字；如需使用，请在系统设置中开启。 | 「就行」口语 ×3 处同改 |
| 28 | QuickRecord.swift:9/26 | 记一笔礼钱 | 记一笔 | [术语表 1.3] |
| 29 | LiqianWidget.swift:122 | 点一下打开，记一笔新的 | 点按打开，记一笔 | 残句 |
| 30 | LiqianWidget.swift:148 | 还没回的礼，一眼看清。 | 待回礼汇总 | 营销腔 + 与正式名不一致 [hallmark 19] |
| 31 | MeView.swift:393 | 原生版 v1.0 | 版本 2.1（应改为动态读取 App 版本号） | **内容过期**：当前已是 v2.1，写死版本号必再次过期 |
| 32 | MeView（数据说明） | 数据只存在这台手机上，不联网、不上传。换手机或重装前，先用上面「数据」里的导出备份存一份。 | 数据仅保存在本机，不联网、不上传。换手机或重装前，请先导出备份。 | 「上面」指代依赖版式位置；啰嗦 |
| 33 | MeView（待回礼说明） | 按「最近一次收礼之后还没送出」自动算的，不用手动标。 | 按最近一笔收礼之后是否已送出自动计算，无需手动标记。 | 「标」口语；引号内长句作术语不成立 |
| 34 | TrashView（清空确认） | 清空后就真的恢复不了了。 | 清空后无法恢复。 | 「真的」口语强调 |
| 35 | TrashView / MeView（回收站说明两处） | 删掉的礼簿和记录，30 天内能恢复 / 删掉的礼簿和记录会在这里保留 30 天，过期自动清掉。 | （两处统一为）删除的礼簿与记录保留 30 天，过期自动清除，期间可恢复。 | 同一事实两套文案 [hallmark 69 echo] |
| 36 | AISettingsView（状态行） | Key 已填，开关还没打开 | 已保存 API Key，AI 功能尚未启用 | 与 #23 同族统一 |
| 37 | AISettingsView / 其他 | 保存 Key / 删除 Key / 换一个 Key / 当前 Key | 保存 API Key / 删除 API Key / 更换 API Key / 当前 API Key | [术语表 1.5] |
| 38 | Components.swift:82/89 | 收 / 随（单字带空格） | 收礼 / 随礼 | [术语表 1.2] |
| 39 | MeView 总览 vs LedgersView 汇总 | 总收礼 / 总随礼 ∥ 累计收礼 / 累计随礼 | 统一「累计收礼 / 累计随礼」 | 同一指标两名 |
| 40 | AnnualReportView（两处同功能描述） | 把这一年的人情往来做成一张图，发给家人一起看看… / 按年看往来，做一张能发给家人的报告图 | 生成年度报告图卡，仅含汇总数据，不含个人明细。 | 同一功能两种说法且口语 [hallmark 69] |
| 41 | MeView（示例按钮组） | 先看看示例数据 / 生成示例数据，先看看效果 / 生成两本示例礼簿，先看看效果 | 生成示例数据（统一）；结果提示统一「示例数据已生成」 | [术语表 1.3] |
| 42 | PeopleView（搜索提示） | 搜姓名，或者搜礼簿、事由 | 姓名、礼簿或事由 | 搜索框占位用名词短语 [iOS] |
| 43 | MeView（备份行副文） | 全量备份：礼簿和记录都在，换手机靠它恢复 | 包含全部礼簿与记录，可用于换机恢复 | 「靠它」口语 |
| 44 | MeView（CSV 行副文） | 全部记录导出成表格，Excel 能打开 | 导出为 CSV 表格，可用 Excel 打开 | 句式书面化 |
| 45 | AppLock 说明（设置内） | 打开 App、从后台回来超过半分钟，都要先用 Face ID 或密码解锁；切到后台时内容会模糊。 | 从后台返回超过 30 秒需重新解锁；App 在后台时界面自动模糊。 | [术语表 1.5] 计量规范 |
| 46 | LedgerFormView / RecordFormView | 备注（可选）/ 主家姓名（可空）/ 你和主家的关系（可空） | 统一「（选填）」 | [术语表 1.5] |
| 47 | RecordFormView.swift:142 | 说一句，自动填好 | 一句话填写姓名与金额 | 「自动填好」含混且近 hype [unslop §4] |
| 48 | QuickSentenceView（发送提示） | 将把这句话发送至 DeepSeek 解析，解析完只预填表单，你核对后自己保存。 | 将把这句话发送至 DeepSeek 解析。结果仅预填到表单，请核对后保存。 | 「自己」多余；长句拆分 |
| 49 | GreetingView（生成按钮组） | 生成 3 条候选 / 再生成 3 条 | 生成 3 条（首次）；重新生成（再次） | 「候选」是内部词，用户侧不说候选 |
| 50 | BatchEntryView（同名提示） | 本簿已有此人，导入后并列保存 | 本礼簿已有同名记录，导入后将并列保存 | [术语表 1.1] 禁单字「簿」 |
| 51 | LedgersView（空状态） | 这本礼簿还空着，记第一笔吧。 | 还没有记录，记第一笔。 | 与其他空状态句式统一（「吧」语气词全 App 仅此一处） |
| 52 | PersonDetailView / StatsView（待回礼口径注） | 待回礼（至今） | 待回礼（累计） | 「至今」含混；与 MeView 卡片名统一后此处注为累计口径 |

**报错与 AI 文案专项结论**：AI 相关报错现有 4 套说法（DeepSeek.swift 的 `badResponse`、QuickSentenceView 的 `incomplete`、BatchEntryView 的格式错误、GreetingView 的生成失败），同一个「模型返回不可用」事件，用户在不同入口读到不同口吻。定版错误族三句，全 App 共用：网络类「网络连接失败，请检查网络后重试」／限流类「请求过于频繁，请稍后重试」（现行「DeepSeek 正在限流（HTTP 429），等一会儿再试」把 HTTP 状态码直接抛给用户，改后状态码只进日志）／格式类「AI 返回内容格式异常，无法解析」。现行做得对的保留：全部 AI 文案无感叹号、无 hype 词（合 [unslop §4]、[hallmark 19]），「AI 生成，请核对后再用；人名、称谓最容易出错」是全 App 最专业的一句 AI 文案，可作族内范式。

---

## 三、配色与令牌审计

### 3.1 令牌清单与实际用法（Palette.swift，共 17 个语义令牌 + 度量/字阶）

| 令牌 | 浅 / 深值 | 全仓引用数 | 判定 |
|---|---|---|---|
| paper | FAF9F6 / 171716 | 19 | 在用；与系统 `systemGroupedBackground` 语义重复（见 3.3） |
| card | FFFFFF / 1F1F1D | 15 | 在用；与 `secondarySystemGroupedBackground` 重复造轮 |
| ink | 262520 / EBE9E3 | 84 | 在用；即 `label` 的暖调复刻 |
| stone | 6F6C64 / A6A29A | 108 | 全仓第一高频；即 `secondaryLabel` 的暖调复刻 |
| primary（朱砂） | A62B1F / D96A5C | 33 | 唯一品牌强调色，保留 |
| primaryPressed | 8E241B / B85547 | **0** | **死令牌**：DESIGN 附录承诺的按下态从未接线 |
| primaryTint | F3E2DC / 38251F | 2 | 在用（选中衬底/快捷金额） |
| primaryDisabled | C9A79E / 71544C | **0** | **死令牌**：禁用态实际靠系统按钮外观，无人引用 |
| gold | B98A2F / C9A24D | **0**（仅注释提及） | 按 v3 纪律本就禁止视图引用；但令牌仍挂在 Palette 里，且 GiftBookPDF 另起一份同值常量（见 3.2），形成「名义集中、实际两处」 |
| hairline | E3E1DA / 2E2D2A | 21 | 在用；与系统 `separator` 重复造轮 |
| baiPaper / baiCard / baiInk / baiStone / baiPrimary / baiLine | 白事六件套 | 5 / 6 / 12 / 19 / 12 / 8 | 产品特有语义（整页礼制切换），系统无对应，**保留** |
| givenTag | 5B6770（**非动态色**，写死单值） | 1 | 唯一非动态令牌：深色外观下不随令牌体系变化，与 baiPrimary 同值却另立门户，应并入 baiPrimary 或补动态定义 |
| LiqianMetrics | minTapTarget 44 / cardCorner 18 / coverCorner 20 / cardPadding 16 / spacing 8·16·24 | — | 声明了，但执行率低（见第四部分） |
| 反馈色（成功/警告/错误） | — | — | **令牌缺位**（design-system Step 0 覆盖门：Feedback 行 absent）→ 各视图直接借系统色，见 3.2 |

三层令牌结构（design-system：原始→语义→组件）：本仓只有语义一层，且语义层直接写死 hex 在 `dyn()` 工厂里——改品牌色要动 17 处定义而非一处原始值。属可接受的小型项目简化，但须在 DESIGN.md 里明说，别假装有三层。

### 3.2 绕过令牌的硬编码色（grep 实测）

| 位置 | 内容 | 性质 |
|---|---|---|
| GiftBookPDF.swift:42-51 | 自带 10 个颜色常量：paper `0xF6F1E7`、cardInk `0x2B2620`、stone `0x6B6353`、cinnabar、cinnabarDeep、gold、白事四色 | **令牌漂移（最严重一处）**：PDF 用的仍是 **v3 已废弃的 v0.2 色值**——纸色 F6F1E7 正是 DESIGN.md 点名废弃的「米黄过饱和」原值。App 内再克制，导出物仍是旧色板，等于品牌两张脸。PDF 是静态成品可有自己的印刷色定义，但必须与现行令牌同值并注明出处 |
| GiftBookPDF.swift:534 | 噪点用 `UIColor(red: 0.45, green: 0.38, blue: 0.25, alpha:)` 裸值 | 同上文件内的二次漂移 |
| LiqianWidget.swift:17-20 | WPalette 私自复制 paper/ink/stone/primary 四个令牌（含 dyn 工厂复刻） | 小组件无法链接 LiqianDesign 尚可理解，但复制即漂移源：v3 改色时 Widget 靠人肉同步。应改为从共享文件/编译期常量单点定义 |
| BatchEntryView.swift（13 处）、LedgerFormView.swift:55、RecordFormView.swift:198/234、QuickSentenceView.swift:64 | 状态色直用 `.red`（约 13 处）、`.green`（2 处）、`.orange`（约 6 处） | **语义不清的裸系统色**：红=失败行、绿=成功行、橙=同名提示，三种含义没有令牌名，深色外观下饱和度也未校准。Palette 须补 `success/warning/danger` 三个语义令牌再统一替换 |
| Components.swift:20/142/207 | `.white` 与 `.white.opacity(0.28/0.4/0.55)`（方向签字、封面高光与竖线、印面内框） | 彩色底上的白字属合法用法；但封面块的白色 0.28→0 线性渐变是「光泽拟物」残留，与 DESIGN「不用 SaaS 默认件」自相矛盾，且中 unslop「richness 只许进 moment、chrome 保持安静」——封面块本身就是 moment，可保留朱砂满底，但高光渐变建议随整改一并评估 |
| AppLock.swift:74、PeopleView.swift:213 | `.white` | 彩色底白字，合法 |

统计：**真正的硬编码色共 3 组 32 处**（PDF 11、Widget 4、状态色约 21，其中状态色与 PDF 漂移是性质问题，白字类不计）。按 design-system 令牌覆盖率口径：颜色类取值约 260 处，令牌外 32 处，**覆盖率约 88%**——在「70–89% 漂移积累期」上沿，问题不在量而在三处全是成组漂移（一个文件/一个子系统整体脱钩）。

### 3.3 目标映射：哪些改走系统语义色，哪些保留品牌令牌

| 现令牌 | 目标 | 理由 |
|---|---|---|
| ink | → `Color.primary`（即 label） | 与系统一致，深浅自动、对比 guaranteed；暖调个性损失可忽略（262520 与 label 几乎不可分辨） |
| stone | → `Color.secondary`（secondaryLabel） | 同上；现 stone 对纸面对比约 5.0 是手工实算维护的，系统色免维护 |
| hairline | → `Color(uiColor: .separator)` | 发丝线正是 separator 的职责；现值在深色下 2E2D2A 与系统值有可见差异 |
| card | → `Color(uiColor: .secondarySystemGroupedBackground)` | 分组列表的标准卡面 |
| paper | **保留品牌令牌** | 纸白底是本产品的「世界」（unslop 的 World：纸与墨），FAF9F6 的一丝暖意是刻意签名；但保留意味着 DESIGN.md 要明说它与 systemGroupedBackground 的关系，别再让后人以为是疏忽 |
| primary / primaryTint | **保留**（唯一品牌强调 + 其 tint） | 朱砂是产品签名 |
| primaryPressed / primaryDisabled | **二选一：接线或删除** | 死令牌比没有令牌更糟——它谎报系统完整度（design-system Step 0：declared 实为 absent） |
| bai* 六件套、gold（限 PDF/印章） | **保留** | 产品特有语义，系统无对应 |
| givenTag | 并入 baiPrimary 动态定义 | 消除唯一非动态令牌 |
| （新增）success / warning / danger | 新建语义令牌（朱砂系与石墨系内取色，不引新色相） | 堵住状态色裸奔；warning 可用 stone 加深，danger 与 primary 同色相不同角色须分名（命名按角色不按外观，design-system naming §1） |

### 3.4 60-30-10 逐屏核查（ui-designer 规则；unslop「一屏一个亮点」并用）

| 屏 | 60 中性 | 30 表面 | 10 强调 | 结论 |
|---|---|---|---|---|
| 首页（礼簿列表） | ✓ 纸白底 | ✓ 白卡 | ✗ | **朱砂超标的一屏**：每本礼簿一块 56×92pt 朱砂满块（约 5,150pt²/行），4 本即约占屏面积 14%，且为满饱和大色块，视觉权重大于面积比；另有 Tab 选中、主按钮、待回礼朱砂字叠加。封面块是 DESIGN 定的唯一记忆点（unslop 允许一个 rich moment），但**逐行重复 N 次后 moment 贬值为 wallpaper**——建议整改方向：封面块降为小尺寸（或列表行只留竖排事由的朱砂小签），满块只出现在礼簿详情页头部一次 |
| 礼簿详情 | ✓ | ✓ | ✓ | 封面块在此出现一次，正是 moment 的正确用法 |
| 人情（往来列表） | ✓ | ✓ | ✓ | 方向签为小面积点缀；差额已回墨色（v3），达标 |
| 记一笔 | ✓ | ✓ | △ | 快捷金额 chips 的朱砂字+tint 底成排出现，面积受控但密度高；属可接受的「功能性强调」，维持观察 |
| 我的 | ✓ | ✓ | ✓ | 朱砂仅开关与个别图标，达标 |
| 批量补录 | ✓ | ✓ | △ | 状态色（红/绿/橙裸色）面积不大但色相数=3，违反「强调色唯一」观感；补令牌后收敛 |
| 白事礼簿内页 | — | — | — | 素灰蓝整页替换朱砂，属已声明的整页礼制姿态（hallmark gate 23 的 declared posture 豁免），合规；但须在 DESIGN.md 登记为姿态，避免日后被当漂移误改 |
| 锁定页 | ✓ | ✓ | ✓ | 朱砂印记 + 主按钮，一屏一亮点，达标且是全 App 执行最好的一屏 |

---

## 四、版式与组件一致性

### 4.1 间距：声明的梯队与实际的野蛮生长

LiqianMetrics 只声明 spacing 8/16/24 与 cardPadding 16。全仓实测（VStack/HStack `spacing:` 与 `.padding` 字面量）：

- 栈间距共 **13 种取值**：8(×24)、2(×17)、12(×13)、4(×11)、6(×8)、10(×7)、0(×4)、16(×2)、14(×2)、3、18、20、24(各 ×1)。
- **2pt 间距用了 17 次**，是第二高频值——unslop §1 只允许 2px 在小控件内部作微调，17 次已是系统性用法；且 2/3/6/10/14/18 均不在 DESIGN 自称的「4/8/12/16/24」梯队内（hallmark gate 24a/24b：有令牌处必须用令牌、离格值至多 3 处光学微调，本仓离格值数以十计）。
- 内边距字面量 **16 种**（2/3/4/5/6/8/9/10/12/14/16/24/32/40/48/52）；最刺眼的是 LedgerCoverCard（Components.swift:118）卡片内边距写死 12，而系统令牌 cardPadding=16 就在同一文件体系里——**令牌存在、同类组件不用**，是 drift 的教科书形态（design-system Step 1）。
- 内部间距 > 外部间距的反例：封面卡内 HStack spacing 14 > 卡片间列表行距（List 默认），违反 ui-designer「internal ≤ external」。

统一方案：梯队收敛为 4/8/12/16/24/32 六档写入 LiqianMetrics（补 spacingXS=4、spacingXL=32），栈间距与 padding 全量改走令牌；2pt 只许留在 DirectionTag 这类签形控件内部并注释。

### 4.2 字阶：14 个写死字号对 1 个语义样式

- `.system(size:)` 共 **127 处、13 种字号**：12.5(×41)、12(×27)、16(×17)、11(×10)、15(×9)、13(×8)、14(×4)、13.5(×4)、17(×3)、22(×2)、24、20、10(各 ×1)；另 liqianSerif 8 种尺寸（12–28）、liqianMoney **10 种尺寸**（14/15/16/17/19/20/22/26/34/40，其中 15 用了 10 次）。
- 语义字体样式（`.headline/.body/.footnote` 等）全仓只有 `.footnote` ×13。**Dynamic Type 适配为零**：127 处写死字号意味着系统字体调大时全 App 无一处响应（见第五部分 Accessibility）。
- **12.5pt 是全 App 第一高频字号**（41 次、横跨 14 个文件）——非整数、不在任何比例数列、不是 Dynamic Type 档位。它是 DESIGN.md 字阶表里「辅助 12.5」的遗产：文档把一个随手值封为规范，代码再忠实执行。花叔 critique #6/#2 与 unslop §5 都指向同一件事：字号必须来自一条数列。
- 字重失控：`.system` 调用里 bold ×17、semibold ×12、medium ×5，衬线函数默认又是 bold——层级靠字重堆（unslop §5：层级靠字号与颜色，字重 400/500 为主、600 罕用）。
- DESIGN 与代码互相打架：DESIGN 字阶写「金额大数 22–26」，实际金额第一高频是 liqianMoney(size: 15)；DESIGN 写「正文 15」，实际正文位 16(×17) 与 15(×9) 并存。文档与实现谁也不是对方的真相（design-system：文档不存在等于系统不存在，反之亦然）。

统一方案（字阶映射表，整改时逐处替换）：

| 现散值 | 目标语义样式 | 备注 |
|---|---|---|
| 28 衬线（大标题） | `.largeTitle` + serif design | 保留衬线气，用 Font.system(.largeTitle, design: .serif) |
| 16 semibold（列表标题） | `.headline` | |
| 15 / 16 regular（正文） | `.body` | 二选一本就是漂移证据，语义样式自动统一 |
| 12.5 / 12 / 13（辅助） | `.footnote` | 12.5 整批迁移，单这一项覆盖 41+ 处 |
| 11（方向签） / 10 | `.caption2`，且只许签形控件 | 10pt 整批淘汰（低于 iOS 最小可读档） |
| 13.5 / 14 | `.subheadline` | |
| 金额各尺寸 | `.title3`（列表）/ `.title2`（汇总）/ `.largeTitle`（记账键盘 40→此档） + `.monospacedDigit()` + serif | 金额字号从 10 种收敛到 3 档 |

### 4.3 圆角：三套规格打架，一处嵌套反而是对的

- 文档层：DESIGN.md 正文写「圆角统一 10」、附录写「主表面大圆角 18–24」、LiqianMetrics 写 cardCorner 18 / coverCorner 20——**同一产品三套圆角规格**。
- 代码层：令牌外字面量 RoundedRectangle 共 14 处：12(×5)、8(×4)、4(×3)、18(×2)；DirectionTag/PendingTag 的 4、印章的 `size*0.16` 比例式各行其是。
- 唯一的好消息：封面块圆角 8 嵌在圆角 20、padding 12 的卡片里，20−12=8，恰合 ui-designer 的同心圆角公式——是全仓唯一可举证的嵌套圆角正确案例，应写进 DESIGN.md 当范式，而不是让它继续当巧合。
- 统一方案：规格定版为 卡片 18 / 封面 20 / 签 4 / 控件 10（胶囊按钮除外），删 DESIGN.md 中「统一 10」与附录 18–24 的旧文，字面量全量收编令牌。

### 4.4 组件层其他一致性问题

- **卡片两套皮**：`liqianCardSurface()`（Components.swift:168）已提供统一卡面，MeView 等新页在用；但 LedgerCoverCard 自己手写 background+overlay（同文件 :122-129），StatsView/AnnualReportView 又有各自写法。同一种「白卡 + 发丝线」至少三种实现（design-system Step 3：同一模式多处不同实现）。
- **中点拼接元信息**：封面卡副标题 `"\(date) · \(农历) · \(note)"`（Components.swift:145-148）是 hallmark Floor 门 63 明禁的 middle-dot-joined meta string——移动端虽非 hallmark 的主场，此条与 unslop 的「meta 用安静分行/分列」同向，建议改两行或分段排布。
- **阴影**：DESIGN 定「卡片无投影」，全仓唯一 `.shadow` 在 SealStampOverlay（Components.swift:238）——落印动效的投影属动效语境可豁免，但应在 DESIGN.md 登记为例外，否则下次审计继续报。
- **图标**：全仓 SF Symbols 单一体系、尺寸随字号走，此项健康（unslop §3 达标），是少数不用动的。

---

## 五、CLEAR 评分（整改前基线）

按 design-system 审校框架的 CLEAR 五维（Copy 文案 / Layout 版式 / Emphasis 强调 / Accessibility 无障碍 / Reward 反馈与愉悦）打分，1–5。

| 维度 | 分 | 最关键三条扣分理由 |
|---|---|---|
| **Copy 文案** | **2** | ① 一套概念四套叫法（礼簿/礼谱、两清/往来两清、总收礼/累计收礼、Key/API Key），术语表此前不存在；② 报错口语化成族（「看不懂」×3 文件、「没能存下来」「试试」「就行」），且同一错误多套文案；③ 内容过期无人管：「原生版 v1.0」挂在 v2.1 的关于页，写死版本号是必然过期的写法 |
| **Layout 版式** | **2** | ① 间距 13 种取值、2pt 用了 17 次，声明的梯队（8/16/24）执行率不足三成；② 字号 13 种写死值 + 衬线/金额另 18 种尺寸，语义样式几乎为零；③ 圆角三套规格（文档 10 / 文档附录 18–24 / 令牌 18·20 / 字面量 12·8·4）并存 |
| **Emphasis 强调** | **3** | ① 首页朱砂封面块逐行重复，唯一亮点被摊薄成底纹，10% 强调预算超支（本维最大扣分）；② 字重滥用：bold+semibold 占字重调用 85%，层级靠「更粗」而非大小与颜色；③ 加分项真实存在：v3 已把金额拉回墨色、朱砂纪律成文，方向是对的——扣分在执行未到底（状态色三色相裸奔又把强调色唯一性破了） |
| **Accessibility 无障碍** | **2** | ① **Dynamic Type 零支持**：127 处写死字号，用户调大系统字体全 App 无响应——对中老年主力用户（记礼人群）这是功能性伤害，不只是分数；② **accessibilityLabel 全仓 0 处**，图标按钮（麦克风、复制、解锁）对 VoiceOver 无名；③ 加分项：对比度有脚本实算记录且达标（stone 5.0、朱砂 7.03）、Reduce Motion 三处适配、触摸目标有 44pt 令牌——底子不是零，是没系统化 |
| **Reward 反馈与愉悦** | **3** | ① 落印动效（盖印 + 触觉 + Reduce Motion 降级）是真记忆点，且与产品世界（纸、印）同源，是全 App 最「非 AI 模板」的一处；② 但成功反馈文案不统一（已保存/已复制/恢复完成/示例数据已生成各说各话），反馈语族缺位；③ 空状态只给「一句人话 + 动作」过于素（DESIGN 自定），示例数据这个最好的上手奖励被埋在「我的 → 数据」三级深处，首页空状态虽有入口但视觉权重最低 |

**总评：2.4 / 5。** 结论一句话：这个 App 的问题不是「某个颜色不对」，是**系统只建了一半**——令牌、纪律、术语都写过文档，但执行率（间距约三成、字阶近零、文案无表）撑不起文档的自我描述；用户感到的「AI 味」，在代码里的对应物就是这种「规范与实现之间的落差」。

### 整改清单（按影响排序，前 15 项）

| # | 整改项 | 预计改动面 |
|---|---|---|
| 1 | 字阶全量语义化：127 处 `.system(size:)` 按 4.2 映射表迁 `.body/.headline/.footnote/.caption2` 等，12.5 整批消灭，顺带获得 Dynamic Type | 全部 20 个视图文件 + Components.swift、Palette.swift 字阶区 |
| 2 | fmtMoney 加千分位（¥10,000），金额字号从 10 种收敛到 3 档语义样式 | LedgerMath.swift 1 函数 + 全部金额显示点（grep `liqianMoney(` 约 24 处） |
| 3 | 术语表落码：待回礼/已结清/收礼合计等定版词替换全部禁用变体（约 20 处），回收站改名「最近删除」联动 4 个文件 | PeopleView、PersonDetailView、StatsView、MeView、LiqianWidget、TrashView、全部删除确认文案 |
| 4 | 报错错误族统一：AI 三句 + 解析八字 + 备份两句，按第二部分逐条替换（约 25 处） | DeepSeek.swift、QuickSentenceView、BatchEntryView、LedgerTextParser.swift、MeView |
| 5 | 间距收编：梯队补 4/32 两档入 LiqianMetrics，栈间距与 padding 字面量全量改令牌，2pt 仅留签形控件 | 全部视图（机械替换为主，约 90 处取值点） |
| 6 | 首页封面块降权：列表行朱砂满块改小签/小尺寸，满块只留详情页头部（60-30-10 回正） | Components.swift（LedgerCoverCard）+ LedgersView |
| 7 | 状态色令牌化：Palette 补 success/warning/danger，替换约 21 处 `.red/.green/.orange` | Palette.swift + BatchEntryView、RecordFormView、LedgerFormView、QuickSentenceView |
| 8 | GiftBookPDF 色值与现行令牌对齐（废弃 F6F1E7 等 v0.2 值），并在文件头注明印刷色出处 | GiftBookPDF.swift:42-51、:534 |
| 9 | 「关于」版本号改动态读取 CFBundleShortVersionString，删写死「原生版 v1.0」 | MeView.swift:393 一处 |
| 10 | accessibilityLabel 补齐全部图标按钮（麦克风、复制、解锁、清除等），方向签/印章加 accessibilityHidden 或标签 | 约 10 个视图文件的图标按钮点（逐个点位补） |
| 11 | 圆角规格定版并删 DESIGN.md 冲突旧文（统一 10 / 18–24 两段），字面量 14 处收编令牌 | DESIGN.md + Components.swift、各视图 RoundedRectangle 点 |
| 12 | primaryPressed/primaryDisabled 接线或删除；givenTag 并入动态令牌 | Palette.swift + 按钮样式定义处 |
| 13 | 封面卡副标题去中点拼接（改两行/分段），「收 /随 」单字标签改全称 | Components.swift:82-108、:145-148 |
| 14 | Widget 的 WPalette 改单点定义（与 LiqianDesign 同源常量），防下次改色再漂移 | LiqianWidget.swift + 共享常量落点（需一次小型工程决策） |
| 15 | DESIGN.md 瘦身对账：删 Flutter 附录等过期段落，把本报告的术语表与字阶/圆角定版回写为唯一规范 | docs/DESIGN.md 一份文档 |

（基线备注：本报告所有计数来自 2026-11-07 工作区快照的 grep 实测；整改后复审应以同一组 grep 口径重跑，数字对数字。）

---

## 附：整改落实记录（2026-11-07，同日执行）

执行口径：以本报告定版为准逐项落码，未在审校表内的文案/设计不动。
复审数字均为同一组 grep 口径的整改后实测（基线见正文）。

| # | 整改项 | 状态 | 落实说明与复审数字 |
|---|---|---|---|
| 1 | 字阶全量语义化 | ✅ 已落 | `.system(size:)` 130 → 11 处；12.5pt 41 → 0（界面内）。语义字阶 `.font(.footnote/.body/.headline/.subheadline/.caption/.caption2/.title*/.largeTitle)` 共 130 处。剩余 11 处固定字号均为已登记功能位：Palette 的 Fixed 实现 1、金额键盘按键 2、大字模式 3、分享图卡静态成品 5；衬线/金额改走 `liqianSerif(_:)`/`liqianMoney(_:)` 语义 API，固定位走 `liqianSerifFixed/liqianMoneyFixed`。Dynamic Type 随之生效（见下方布局风险注） |
| 2 | fmtMoney 千分位 + 金额三档 | ✅ 已落 | `LedgerMath.fmtMoney` 重写为手工千分位（整数无小数、非整两位、负数沿旧口径 ¥-N），新增单测：¥10,000 / ¥1,234,567.89 / ¥-10,000 / ¥-100.50 全过断言（待 CI 验证）；小组件私有 fmtMoney 同步同口径。金额字号 10 种 → `.title3/.title2/.largeTitle` 三档（大字模式 34pt 为 Fixed 例外） |
| 3 | 术语表落码 | ✅ 已落 | 禁用变体用户可见残留 0（grep：两清/还没回/人还没回/先记着/他给我的/我给他的/单字标签等）。「回收站→最近删除」联动 MeView、TrashView、RecordFormView、LedgerDetailView 共 4 文件及相关注释；Tab「人情」→「往来」、页名→「往来」；示例按钮统一「生成示例数据」；日期显示新增 `LiqianDate.displayString`（当年 M月d日/跨年 yyyy年M月d日，补单测），各列表裸 `yyyy-MM-dd` 显示已全部改走该函数 |
| 4 | 报错错误族统一 | ✅ 已落 | 审校表 52 条逐条替换完成（含解析器 6 条、DeepSeek 错误族定版三句、429/401 不再直抛 HTTP 状态码、AI 设置与状态行 Key 口径、Widget 三处、语音权限三连）。附带同族一致性修正（表外但同族）：行金额错误「第 X 行金额不对」→「第 X 行金额格式不正确」、年报/人物页的「礼没回/还没回」表述归入待回礼定版词、balanceText 的性别预设「他多给」→「对方多给」 |
| 5 | 间距收编 | ✅ 已落 | LiqianMetrics 补 spacingXS=4 / spacingSM=12 / spacingXL=32，梯队定版 4/8/12/16/24/32。迁移：spacing 字面量 86 处、padding 39 处、EdgeInsets 9 处改令牌（`LiqianMetrics.spacing*` 全仓引用 159 处）。剩余字面量均已定性：spacing 0（语义为无间距）×5、签/徽标内部微调、分享图卡静态成品内部、超梯队版式常量（页顶 40/48、分组对齐 leading 52） |
| 6 | 首页封面块降权 | ✅ 已落 | 列表行 56×92 朱砂满块改 30×64 事由小签（竖排事由＋印点，高光拟物渐变一并去除）；满块只保留在礼簿详情页头部。前置项（内边距 cardPadding、圆角、副标题分段）同轮完成（见 #11/#13） |
| 7 | 状态色令牌化 | ✅ 已落 | Palette 新增 success/warning/danger（取系统语义色），裸 `.red/.green/.orange` 21 → 0（含录音态三元式 1 处） |
| 8 | GiftBookPDF 色值对齐 | ✅ 已落 | paper F6F1E7 → FAF9F6、cardInk 2B2620 → 262520、stone 6B6353 → 6F6C64，与 Palette v3 逐项同值并在文件头注明对应关系与同步顺序；纸纹噪点裸 RGB(0.45,0.38,0.25) 改为 stone 同值＋alpha。cinnabarDeep/baiDeep 为 PDF 印刷专用深阶，保留并注明 |
| 9 | 关于版本号动态化 | ✅ 已落 | MeView 改读 `CFBundleShortVersionString` 显示「版本 X」，写死的「原生版 v1.0」已删 |
| 10 | accessibilityLabel 补齐 | ✅ 已落 | 基线 0 → accessibilityLabel 2 处（批量删行按钮、金额键盘删除键，后者另补 accessibilityElement/AddTraits）+ accessibilityHidden 9 处（装饰性 chevron ×6、设置入口图标、锁定遮罩锁图标、落印浮层）。审计点名的麦克风/复制/解锁按钮本就有 Label 文字，VoiceOver 可读，未另加 |
| 11 | 圆角定版 | ✅ 已落 | 定版 卡片 18 / 封面 20 / 签 4 / 控件 10 写入 DESIGN.md 并新增 tagCorner/controlCorner 令牌；字面量收编：键盘 12 → controlCorner ×5、图卡 18 → cardCorner（值不变）、签 4 → tagCorner ×3。封面卡 padding 改 cardPadding 16 后，封面块圆角按同心公式 20−16＝4 改为 tagCorner（原 8 是配 12 内边距的同心值，见取舍注）。DESIGN.md「圆角统一 10」与附录「18–24」旧文已删改 |
| 12 | 死令牌处理 + givenTag 并入 | ✅ 已落 | primaryPressed/primaryDisabled 删除（按下/禁用态由系统按钮外观处理，DESIGN 已同步）；givenTag 删除，DirectionTag 改引 baiPrimary（见取舍注） |
| 13 | 封面副标题去中点拼接 + 收/随全称 | ✅ 已落 | 副标题改 HStack 分段排布（公历走 displayString / 农历 / 备注），中点拼接串消除；封面卡与表单分段的「收 /随 」单字及括号口语版已改「收礼/随礼」全称 |
| 14 | Widget WPalette 单点化 | ⚠️ 部分落实 | 四色与 v3 逐项核对一致；ink/stone 已改为与 App 相同的系统语义色（Color.primary/.secondary，字面同源）。但 WPalette 仍是独立声明：Widget 目标不依赖 LiqianDesign，把 Palette.swift 加入其源文件需改 Project.swift 并重新生成工程，属工程决策未在本轮动。paper/primary 仍靠注释口径人工同步 |
| 15 | DESIGN.md 对账回写 | ✅ 已落 | 升版 v0.3：字阶/间距/圆角/色彩四章按整改后代码重写，术语与文案定版、令牌单层结构说明、例外与姿态登记（白事整页姿态、落印投影、封面高光、固定字号功能位、签内微调）全部回写；Flutter 附录实现说明与过期深色值已清理 |

### 执行中的取舍与风险（如实记录）

1. **givenTag 并入 baiPrimary 的深色模式对比度**：随礼签底色在深色外观下随 baiPrimary 变为 #93A1AD，白字（11pt）在其上对比约 2.6:1，低于整改前 givenTag 两套外观恒定 #5B6770 的可读性。按审校 §3.3 执行了并入，但这是全轮唯一一处可读性倒退，建议真机深色模式目视后决定是否给签文字改深色字或恢复恒定值。
2. **封面块同心圆角 8 → 4**：封面卡 padding 按审校 §4.1 改 cardPadding 16 后，按 §4.3 同心公式内圆角应为 20−16＝4（原 8 与 §4.3 所举「唯一正确案例」是配 12 内边距的）。两节口径冲突时优先保公式，封面块圆角随之变小，真机需目视确认观感。
3. **Dynamic Type 布局风险点**（字阶语义化后新增，默认字号下无变化，大字号下需真机查）：
   - 首页待回礼卡/最近往来行、人物行：金额与人名同行，AX 大字号下可能挤压人名截断（行高由 minTapTarget 44 托底，不会重叠，但人名 lineLimit 1 截断概率上升）。
   - 礼簿封面卡：标题 .headline + 副标题 .footnote 在固定高 92 的封面块旁排列，大字号下副标题分段（日期/农历/备注）可能溢出——备注已 lineLimit 1，日期与农历段无截断保护，是首要观察点。
   - 记一笔金额区：金额 .largeTitle 有 minimumScaleFactor 0.6 托底；快捷金额 chips .subheadline 在大字号下六枚一行可能拥挤。
   - 批量补录行：姓名/金额 TextField 默认字号随 Dynamic Type 变化，行高 minTapTarget 托底；大字模式为固定字号不受影响。
   - 锁定页标题 .headline、统计页金额 .title3 等单列排布风险低。
4. **间距 snap 的视觉微变**：离格值按就近档归并（2→4、6→8、10→12、14→12、18→16、20→24、3→4），共约 40 处间距有 ±2–4pt 变化，属梯队收敛的应有代价，需整体目视一轮。
5. **Widget 大数字字号变化**：待回礼计数由固定 40/34pt 改 `.largeTitle` 衬线档（默认约 34pt），中号组件视觉略小，换取与系统字阶一致。
6. 未动的表外文案：LibuExportView 的「礼谱没能生成出来，再试一次。」、BatchEntryView 的「AI 拿不准」提示、导入覆盖确认长文等不在审校 52 条内，按「表里没写的别动」保留，其中个别仍带口语色彩，留待下一轮审校立项。
