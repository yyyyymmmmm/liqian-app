# V46 自定义关系（feat/relations）落实记录

需求：关系不再限于系统词表（亲戚/朋友/同事/同学/邻居/其他），用户可新增
系统之外的关系（如闺蜜、战友），全 App 的关系选择器、解析、礼谱排序与
备份都认自定义关系。

## 1. Core：RelationCatalog（新文件 Sources/LiqianCore/RelationCatalog.swift）

- 数据源：`all()` ＝ `LiqianConstants.relations` ＋ 自定义列表，**每次调用
  动态读**，管理页改完返回选择器即生效，无缓存需失效。
- 存储：UserDefaults 键 `"customRelations"`（常量
  `RelationCatalog.customRelationsKey`，备份恢复写回共用同一常量），
  值是 JSON 编码的 `[String]`。
- 读时清洗（`sanitized`）：去空白、去空、去掉与系统词表重名者、自身去重
  保序——存储被外部写坏也不会污染目录。
- 校验纯函数 `validate(_:existing:)`：去空白 → 非空 → ≤6 字
  （`maxLength`）→ 与 existing（传 all()，含系统）不重名；失败原因枚举
  `RelationValidationError`（empty/tooLong/duplicate），管理页据此给人话。
- 写入口：`add`（校验后追加）、`remove`（按名删自定义，系统关系不在
  自定义列表里、删它无效果）、`setCustom`（整体覆盖，备份恢复用，写前
  同样清洗）。
- `pickerOptions(including:)`：选择器专用数据源——all() 之外临时并入
  current（非空且不在目录内时），解决「编辑一条关系已被删除的旧记录时
  Picker 选中态丢失」的问题。

## 2. 管理页（新文件 Sources/LiqianApp/RelationsManageView.swift）

入口：「我的 → 记录」组新增一行「关系管理」（icon person.2，与既有
entryLabel 同风格），副标题动态显已自定义数（0 个时显引导文案）。

- 添加区：输入框＋添加钮（空输入禁用、回车也可提交）；失败按校验原因
  红字提示；快捷 chips 一行（闺蜜/战友/发小/老乡/师长，已在目录内的
  不显），点即添加；footer 说明字数/重名规则与生效范围。
- 系统关系区：六个系统关系逐行列出，右侧标「系统」，不可删。
- 我添加的区：自定义关系左滑删除（无确认弹窗，与全 App 左滑删除风格
  一致）；空时显引导文案；footer 明示「删除不影响已记的记录，记录上的
  关系照原样保留」。

## 3. 选择器换数据源（全部动态读 RelationCatalog）

| 文件 | 改动 |
|---|---|
| RecordFormView | 人物联想 contains 判断改 `RelationCatalog.all()`；关系 Picker 改 `pickerOptions(including: relation)`（编辑兜底） |
| RemindersView | 关系 Picker 同上（「不选」空 tag 保留） |
| SceneModeView | 关系 chips 改 `pickerOptions(including: relation)`（横滑行，数量增长不溢出） |

其余 grep `LiqianConstants.relations` 的出现：Models/Reminders 的字段
文档注释已同步改口径（目录值：系统或自定义）；RelationCatalog 本体与
§4/§5 的改动点除外，无其他 UI 引用。

## 4. 解析放宽

- LedgerTextParser：关系 token 的判定由常量表改 `RelationCatalog.all()`
  （原有「任意 2 字」兜底不变）——3 字及以上的自定义关系（如老战友）
  靠目录命中被认出。
- AIParse.decode：relation 白名单改 `RelationCatalog.all()`，AI 认出
  用户的自定义关系不再被过滤成 nil。文档注释同步。

## 5. 礼谱排序（目录序）

- LibuSections.groupByRelation：段序改 `RelationCatalog.all()` 顺序
  （系统在前、自定义按添加序随后），目录外关系仍按字符串序附后。
- GiftBookPDF 汇总「按關係小計」：排序同改目录序＋目录外附后。
- 繁体映射（段题签 traditionalRelations）**不动**：自定义关系不在
  映射表内、照原样出，符合「用户数据不做繁简转换」红线。

## 6. 备份带走（Backup.swift + MeView 最小改动）

- BackupFile 加可选段 `customRelations: [String]?`（旧备份无键解码为
  nil；makeBackup 空时写 nil 不出空段，旧版 App 按未知键忽略）。
- LiqianBackup.makeBackup 加参数 `customRelations: [String] = []`
  （默认参数，其余调用方 HandoverView/既有单测源码兼容）；
  新增 `parseBackupRelations(_:)`，容错口径同 parseBackupLive。
- MeView 只碰三处：导出调用点多传 `customRelations:
  RelationCatalog.custom()`；handleImport 多解析一行存入
  `pendingCustomRelations`；performImport 在一并写回
  `RelationCatalog.setCustom(...)`（**覆盖式**，与礼簿/记录/班子等段的
  恢复口径一致：备份无此段即清空本机自定义）。导入确认文案未动。

## 7. 单测（新增 RelationCatalogTests.swift，LibuSectionTests 追加）

- 校验：trim/空/超长（7 字拒、6 字过）/与系统重名/与自定义重名。
- 存储（隔离 UserDefaults suite）：all 顺序、setCustom 清洗、add/remove、
  pickerOptions 四态（在目录内/系统/空串/已删值并入）。
- 备份：往返、空不写段、旧备份（无键）解码与段解析为空。
- 解析：粘贴解析 3 字自定义关系加目录前后对照；AI 解析自定义关系
  加目录前后对照（两处走 .standard，测试内保存/还原原值防污染）。
- 礼谱分段：目录序用例（自定义按添加序在系统之后、目录外附后）。

## 8. 不做（本期）

- 关系改名（改名会让历史记录的字符串对不上，需要迁移语义，单独立项）。
- 排序拖拽（目录序＝添加序，已够用）。
- iCloud 同步该列表：UserDefaults 不随 CloudKit 容器同步；后续可走
  NSUbiquitousKeyValueStore 或把列表纳入 SwiftData 模型后再议。
- 示例数据、StatsView 关系分布等只读展示读的是记录字符串本身，
  天然显示自定义关系，无需改动。

## 9. 真机待验（合并后）

- 管理页添加闺蜜 → 记一笔关系选项立即出现；删掉后编辑一条旧的闺蜜
  记录，Picker 仍选中「闺蜜」不变空。
- 快捷 chips 在全部添加后整行消失。
- 导出备份 JSON 里有 customRelations 段；换机恢复后目录一致；
  用旧版备份（无此段）恢复后本机自定义被清空（覆盖口径，属预期）。
