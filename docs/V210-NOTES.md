# v2.10 礼谱第二轮修正 · 落实记录

用户反馈五点，本轮逐项落地。**规格中途纠正（用户拍板）**：书记/核实人/婚期/
地点/主家不是导出设置，而是**礼簿自身属性**——在新建/编辑礼簿时设置，PDF
直接读礼簿，导出 sheet 不出现这些字段。下文按纠正后的规格记。

## 导出先预览（LibuExportView 两步式）

- sheet 结构改为：谱序文体 → 预览区 → 底部「分享 / 保存」。
- 点「生成预览」后在本 sheet 内用 PDFKit（`PDFView`，singlePageContinuous
纵向）整谱翻页预览（`PDFPreviewView`，UIViewRepresentable，高 480 占满行宽）；
生成中是 ProgressView；生成失败在预览区以红字（Palette.danger）明示
「礼谱生成失败，请重试。」，不出空白页。
- 分享改为底部 safeAreaInset 栏的 ShareLink，仅在已有预览且非生成中时出现。
- 切换谱序文体会作废旧预览（pdfURL 清空），避免分享出与所选文体不一致的谱。
- 既有导出入口（详情「更多」→ LibuExportView）与调用方式不变。

## 礼簿属性字段（改版规格）

### 模型（Models.swift · Ledger）
新增四个可选属性，默认 nil：`hostName`（主家）、`scribe`（书记）、
`verifier`（核实人）、`location`（举办地点）。婚期/日子即既有 `date` 字段，
口径不变，PDF 一直读它。工程内无 VersionedSchema/MigrationPlan，SwiftData
对可选新增属性走轻量迁移，老库自动兼容。

### 备份格式（Backup.swift · BackupLedger）
- 四字段以可选键加入（键名同属性名）。nil 时合成 encode 走 encodeIfPresent
不出键；解码一律 decodeIfPresent，旧备份（Flutter 旧导出与原生旧备份）
缺键 → nil，向后兼容。
- 兼容性结论：新备份带键，旧版 App 解码时未知键被忽略（其 BackupLedger 无
对应属性，合成解码不因多余键失败），可正常导入，只是丢弃这四个字段。
- 接线：`LiqianBackup.makeBackup` 映射带上四字段；导入恢复（MeView
performImport）与回收站归档/恢复（TrashStore）同样往返携带，不丢。

### 表单（LedgerFormView）
- 新增「礼谱信息」一组：主家/书记/核实人/举办地点四行选填，标签行样式与
本表单一致（行首标签＋TextField），组脚注说明用途。
- 主家预填：新建礼簿时以全局「礼谱落款姓名」设置（UserDefaults 键
`hostName`）预填；编辑时用礼簿自带值。存时去空白、空串存 nil。
- 全局「礼谱落款姓名」设置项**保留**（MeView 的 HostNameEditView 不删），
角色变为：新礼簿主家的预填默认值＋导出回退链第二级。老用户设置不丢。

### PDF 读取与回退链（GiftBookPDF.makePDF）
- makePDF 签名不变（保留 hostName 参数作兜底，缺省读全局设置），内部解析：
**礼簿 hostName（非空）→ 参数/全局设置 → colophonName 回退「主家」**。
- 谱序侧（LibuExportView.generate）用同一条链算主家名传给 LibuPreface，
保证谱序落款与封面/汇总落款是同一个人。
- 汇总页落款区（末页左下，校對行之下）：
- 主家：右侧既有「○○○謹識」竖排落款＋主家印＋纪年印（现状不变）；
- 「書記 ○○○」「核實 ○○○」各一行小字（楷体 13.5），行尾带一个 25pt
小方印位，印文＝该人姓名首字；未设则整行不出；两行皆无时即现状。
- 地点：非空时——封面信息列末缀「 · 於＋地点原文」；谱序正文带上地点
（模板以「於＋地点」缀在岁在句后；AI 撰序素材新增举办地点）。地点是
用户数据，照原样、不转繁体；固定词「於」为繁体。
- 书记/核实姓名同为用户数据，照原样输出（PDF 里无对用户字段的转换函数，
红线同 v2.8）。

## 双字名间字（内页姓名列）

- 新增绘制层 helper `drawNameColumn`：竖排逐字绘制，按 3 字位归一——
3 字及以上自然排；恰 2 字时两字落在第 0、2 字位（中间让出一个字距，
总跨度＝3 字位，与三字名底边齐）；1 字名落在中间字位居中。
- 返回底边＝topY + max(3, 字数) × step，金额列、日期小字仍自底边往下接，
对齐口径不变。同人并列多列逐列同规。只改绘制层，不动数据；姓名仍取
前 4 字上限（4 字名自然排 4 字位）。

## 白事小节

- 奠儀大写不缀「整」：MoneyText 新增 `chineseUppercaseTraditionalBai`
（字表同繁体正式版，zheng 取空），如 500 元→「伍佰圓」、0→「零圓」。
GiftBookPDF 内页逐笔与汇总总计的大写经 `upperAmount(cents:bai:)` 分派，
白事全谱走奠儀版，红事仍「圓整」。
- 白事谱序模板复查：baiType 模板全文无「賀/喜」字眼（脚本 grep 验证）；
答谢辞白事版（銘謝）同样无賀/喜。白事不用吉语闲章为 v2.8 现状，保持。
- 汇总页题「奠儀總計」保持。

## 答谢辞页

- 页面顺序：封面 → 谱序 → 内页 → 汇总 → **答谢辞** → 補記。
- 页题：红事「答謝」、白事「銘謝」。正文为繁体固定模板写死在 PDF 层
（`thanksText`），红事版谢来宾厚礼、白事版素语谢弔唁扶持（无賀/喜）；
插值仅主家名与事由原文（用户数据，不转繁体）。
- 版式与谱序页同流：竖排右起分列、空一列、落款列「○○○ 謹謝」＋干支
全日期，下方钤主家印。分页绘制抽出共用 helper `drawColumnPages`
（谱序改走同一 helper，行为不变）。

## 单测

- 新增 `Tests/LiqianCoreTests/BackupFieldsTests.swift`：四字段编解码往返、
模型→makeBackup 映射携带、旧格式（无四键）解码为 nil，共 3 例。
- `LibuTextTests.swift` 新增 `MoneyTextTraditionalBaiTests`：不缀整
（整额/零额）、带角分与红事版一致、红事版仍缀整，共 3 例。

## 未做（按规格）

- 分段题签（按村组/关系分段登记）：本轮不做，等用户拍板。
- 本机无 Swift 工具链，未做真编译；全量括号配平与 grep 自查已过
（白事模板/答谢辞賀喜字检查、调用点收敛），真编译与单测执行等 CI。
PDF 版面（落款三行位置、双字名间距、答谢辞页）待出包后真机目检。
