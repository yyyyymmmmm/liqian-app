# v5.11.5 NOTES — 印刷版礼谱封面重复修复＋補記页新口径

版本 5.11.5 / build 76。基线不变（不带 Share 扩展、CI 预签断言）。
本版两件事，都出自用户实报的导出 PDF 毛病（诊断定案见
~/workspace/liqian-review/pdf-bugs-diag.md）；家族汇册章题页本版不动。

## 1. 印刷版封面重复（修复）

病灶：`GiftBookPrintPDF.makePrintPDF` 的封面展开图左区已绘屏幕版
第 0 页封面（drawCoverSpread），随后「内页套出血」循环
`for index in 0..<doc.pageCount` 又从第 0 页起全嵌回——封面逐像素
出现两次；连带参数页「内页 N 页」与书脊估算页数都把封面多算 1 页。
基础礼谱/纪念版走 makePDF 单封面，不受影响。

修法（取页口径收敛到 Core 单点，装配层不许再自己数页）：
- `PrintBookSpec`（LiqianCore/FamilyAlbum.swift）新增装配计划三件：
  `interiorSourceIndices(sourcePageCount:)`（＝1..<页数，跳过封面）、
  `interiorPageCount(sourcePageCount:)`（＝页数−1）、
  `assembledPageCount(sourcePageCount:)`（＝展开图 1＋内页＋参数页 1）。
- `GiftBookPrintPDF`：内页循环改走 `interiorSourceIndices`；
  参数页 `interiorPages` 改走 `interiorPageCount`。
- `LibuExportView` 书脊估算：入参页数改走 `interiorPageCount`
  （取印刷源谱口径，见 §2），与参数页同口径。

## 2. 補記页新口径（用户 2026-11-09 拍板，修订 v2.8 定版）

**新口径：屏幕导出去掉補記页、只印刷版保留。** v2.8 起補記页无条件
排在每册卷末，电子版翻到末页只见版框与空栏线，被用户读成「最后一
页是空白的」；成书打印后手写补记才是它的真实用途。

落法（補記包含与否成为生成参数）：
- `GiftBookPDF.makePDF` 新增必填参数 `includesSupplement: Bool`；
  `drawSupplementPage` 本体保留，调用改为条件执行，位置不变
  （答谢之后、祝福索引之前）；GiftBookPDF 文件头已记修订。
- 调用点逐个显式传参：
  - 导出页屏幕版生成：`false`；纪念版（HandoverView）：`false`；
    家族汇册各簿（屏幕版礼谱管线）：`false`；
  - 印刷源谱：`true`。
- **耦合处理（印刷不能跟着丢補記）**：印刷版原本是嵌屏幕版产物装配
  的，屏幕版去掉補記后印刷会连带丢页。改为 `LibuExportView.generate()`
  在同一次谱序解析下生成两份谱：印刷源谱（含補記）与屏幕版（不含）。
  makePDF 按簿名写同一临时文件，故印刷源谱生成后**立刻转存**到
  `print-source-<礼簿ID>.pdf` 独立文件名，再生成屏幕版；装配
  （assemblePrint）改用印刷源谱（printSourceURL），谱序变了随预览
  一并作废。书脊估算按印刷源谱内页数（含補記、不含封面）计，与
  参数页显示的内页数一致。
- 印刷内页下标复核：印刷源谱里補記位于答谢后、祝福索引前，即内页
  序列的末位（无祝福时）或次末位（有祝福时）；内页循环跳过封面后
  補記仍落在参数页之前，`interiorPages` 按源谱总页数−1 计，含補記
  在内，与实物一致。

## 3. 测试（新增 6 个，总数 300 → 306）

新增 `Tests/LiqianCoreTests/PrintBookAssemblyTests.swift`。这条 bug
是「代码看着对、产物才露馅」型，断言分三层写死（方法即防回归口径）：
- **计划层**：`interiorSourceIndices` 对多档页数断言＝1..<N 且不含 0；
  `interiorPageCount`/`assembledPageCount` 边界值；书脊按内页计 <
  按全页数计。
- **产物层**：离线合成 5 页纯色指纹 PDF（第 0 页封面＝纯红、末页
  補記＝紫），按生产同构装配（展开图占位＋计划内页栅格化嵌回＋
  参数页占位）后逐页取 1×1 平均色指纹断言：总页数＝1＋(5−1)＋1；
  第二页起无任何一页与封面指纹接近（L1 距离 >0.45）；内页顺序与
  源 1…4 页逐页对应；補記指纹落在内页末位（末页参数页之前一页）。
  生产内页嵌回本身就是栅格化，模拟同构；展开图/参数页绘制在 App
  target 测面够不着，以占位页替，断言只落内页序列这一病灶。
- **源码守卫层**：App target 渲染不了（LiqianCoreTests 只链 Core），
  以调用序列守卫钉住——印刷装配源码必须消费 PrintBookSpec 计划且
  不含 `0..<doc.pageCount`；基础版 makePDF 窗口内 `drawCover(` 只
  出现一次、页序为封面→答谢→補記→祝福索引、補記调用被
  `if includesSupplement` 包住；四个生成调用点的开关传参逐个断言
  （屏幕 false／印刷源 true／纪念 false／汇册 false）。守卫读不到
  源码时 XCTSkip 留痕，验收须在 CI 日志确认本组用例实际 executed。

AnalyzerFeeder 零改动（diff 名单实查不在内）。

## 验收（实测）

- CI：run 42535658738（workflow_dispatch @ feat/v5115-print-cover-fix），
  attempt 1 经 API 逐 attempt 实查 completed/success，job build-native
  全部步骤 success（一次通过、无重跑）；日志实查「** BUILD
  SUCCEEDED **」「presign assertions passed (2 binaries)」。
- 单测：日志总计行「Executed 306 tests, with 0 failures」＋
  「** TEST SUCCEEDED **」（300 ＋ 本版新增 6，与预期一致）。
  新增 6 个用例逐个实查 passed、无一 skipped：产物指纹用例
  testAssembledPrintPDFCoverOnceSupplementLastInterior（0.205s）、
  源码守卫两件（testPrintAssemblyConsumesPlanAndSkipsCover /
  testBasePDFPageOrderAndSupplementSwitch）与调用点开关断言
  （testSupplementSwitchAtCallSites）均实际 executed——守卫读到了
  CI 工作区内的仓库源码，不是跳过。
- 解包验（IPA 4,083,483 字节）：App 与 Widget 的 Info.plist 均为
  5.11.5/76；PlugIns 仅 LiqianWidget.appex，无 LiqianShare.appex。
- AnalyzerFeeder 零改动：本版 diff 文件名单实查不含该文件。

## 真机未验（待用户验）

- 导出印刷版礼谱：封面只出现一次（展开图左区），无第二张封面内页；
- 参数页「内页 N 页」与实际内页一致；书脊宽度目测合理；
- 屏幕版/纪念版导出：末页不再是補記空栏页（无祝福时末页为答谢辞，
  有祝福时末页为祝福索引）；
- 印刷版导出：補記页仍在，位于内页末位（有祝福时为次末位）、
  参数页之前。
