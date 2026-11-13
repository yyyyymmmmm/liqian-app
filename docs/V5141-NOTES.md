# v5.14.1 热修说明（保存链加固＋日期补齐＋礼簿倒计时）

基线：feat/v514-native-pass @ d085a80（v5.14.0）。分支 feat/v5141-save-chain。
起因：用户 2026-11-13 实报四件事——①新建礼簿/第二笔记录「保存了不显示」；
②记账时日期藏得深、非事由日给的礼没法顺手记对日子；③礼簿想要倒计时。
审计全文：~/workspace/liqian-review/save-chain-audit.md（本仓库外）。

## 第一包 · 数据加固

病根（审计定案）：
- 六个落库入口全部 `try? modelContext.save()` 静默吞失败，成功反馈
  （落印/关页/报「共记 N 笔」/置「已入账」/回执置 accepted）却无条件
  触发。一次间歇 save 失败即可同时解释三症状。
- lastUsedLedgerID 只有记一笔回写，第一笔经批量进新簿、第二笔经
  首页记一笔会默认落回旧簿，看着像「新簿第二笔没存上」。

改法：
- Core `SaveFlow.run`：执行保存＋按成败分发反馈的纯逻辑（可注入闭包，
  单测钉死「失败时 onSuccess 绝不调用、原错误原样交出」）。
- App `SaveSupport.attempt`：真 `try context.save()`，失败记一行
  os.Logger（subsystem site.didichou.liqian / category save，错误原文
  只进日志不进 UI），统一人话文案「没存上，再试一次；内容都还在，
  没有丢。」交调用方显形。
- 六入口全部接线：失败→表单内红字/原有消息行/弹 alert 显形＋警告
  触感，不 dismiss、不落印、不报数、不置已入账、不回调回执；
  用户已填内容原样保留可重试。RecordFormView 删除既有记录的 save
  同批收敛（同文件同病）。
- lastUsed 统一回写：批量（三通道）/现场/OCR/问账入账成功后
  `SaveSupport.rememberLedger(ledger.id)`，与记一笔 @AppStorage 同键
  同 UserDefaults；DefaultLedgerPicker 决策口径不变。

**如实声明**：病根一的真机失败诱因仍未坐实（间歇失败在静态代码层
无确定触发点）。本版验收口径＝「失败必显形＋内容不丢＋成功必真存」；
诱因若再现，用户能当场看到报错文案、日志里有错误原文，据此再定位。

不在本版范围（明记）：GuestReceiptsView 的 markBooked/markRead/dismiss
三处状态写仍是 try?（状态同步类、非用户账目落库，下版或随扫码随礼
维护批处理）。

## 第二包 · 日期补齐（日粒度，用户裁定不加时分）

- 记一笔：日期行从「补充信息」折叠区提到主表单明面（金额行之后）。
  默认值：从礼簿进入＝该礼簿事由日；全局/人物入口＝今天；编辑态＝
  记录原日期；回执入账＝回执服务器提交日（新增 init 参数
  receiptDate，GuestReceiptsView 传 createdAtDate，解析不了回退今天）。
- 批量补录：新增整批日期 Section（三通道上方共用，默认今天），
  逐行/粘贴/AI 三通道落库日期统一写所选日期；相关说明文案同步改。
- 拍礼簿 OCR：确认页首节加「记录日期」整批选择，导入写所选日期。
- 模型零改动：GiftRecord.date 仍是 String「yyyy-MM-dd」。

## 第三包 · 礼簿倒计时

- Core `LedgerCountdown`：日历日差（startOfDay 口径）；未来「还有
  N 天」、当天「就是今天」、红事已过「已过 N 天」；**白事一律
  nil 不显**（未来/当天/已过全抑制，用户裁定口径）。
- 呈现两处：礼簿卡副标题（LedgerCoverCard，首页与礼簿页共用自动
  一致）＋礼簿详情头部（横排/AX 纵排两分支都接）。不进小组件、
  不进首页重要日子卡。

## 本地化

- 新增/改动文案按 v5.13 口径：简体原文＋zh-Hant 表同步（失败文案、
  「没存上」、「记录日期」、整批日期脚注；批量两处旧文案整句换键）。
- 倒计时文案为 Core 含插值拼装串，按 v5.13 既定边界：繁体档显简体
  原文、不丢字（同「共 N 笔」类）。

## 回归护栏

- SaveChainTests：SaveFlow 成败分发 3 例＋LedgerCountdown 边界 6 例
  （明天/今天/昨天/跨月/跨年已过/白事全抑制）。
- SaveChainGuardTests 源码守卫 4 例：六入口走 SaveSupport 且无静默
  save 回潮、SaveSupport 真 save 不吞错；lastUsed 四入口回写在位＋
  键字面量不漂移；日期包接线（默认事由日/整批日期三通道计数/回执
  提交日）；倒计时两处呈现接线。
- 零改动红线：AnalyzerFeeder 未动；金额双色/待回口径/统计隔离/
  扫码随礼/礼谱链路未动（本版只碰上述文件）。

## 版本与产物

- Project.swift：5.14.1 / 82（构建设置＋App plist＋Widget plist 共
  6 处字面量）。基线不变：不带 Share 扩展（CI 预签断言在位）。
- IPA：~/workspace/your_files/liqian-v5.14.1/liqian-native-unsigned.ipa
  （未签名，万能签覆盖安装，数据不动）。

## 真机待验（发版时未验，如实列明）

1. 保存失败显形：正常网络/存储下难以自然复现失败——重点验成功路径
   无回归：六入口各记一笔，落印/关页/报数/已入账/回执流转如旧。
2. lastUsed：批量进新簿后回首页记一笔，默认应落新簿。
3. 日期：礼簿内记一笔默认事由日；批量/OCR 整批日期改往日后记录
   日期正确；回执入账预填为提交日。
4. 倒计时：红事未来簿卡面与详情头部显「还有 N 天」、已过显「已过
   N 天」；白事簿两处都不显。
5. 繁体档抽查新文案（记录日期/整批日期脚注/失败文案繁体形态）。


## 验收追记（2026-11-13）

- CI run 43403302671（workflow_dispatch，head dccb886）：attempt 1
  经 API 实查 completed/success。首轮 run 43401793671 仅挂一条自家
  守卫断言（键字面量误写 liqian. 前缀，实为 lastUsedLedgerID），
  修正后重跑全绿——产品代码零失败。
- 单测：Executed 385 tests, 0 failures（372 基线＋SaveFlow/倒计时
  逻辑 9＋源码守卫 4），All tests passed。
- 解包验：App Info.plist 5.14.1/82、Widget 5.14.1/82；PlugIns 只有
  LiqianWidget.appex，无 LiqianShare.appex（基线不变）。
- IPA：4,437,240 字节，md5 d78b65878515bf08c36c82b64562d1fa，
  ~/workspace/your_files/liqian-v5.14.1/liqian-native-unsigned.ipa。
- AnalyzerFeeder 零改动（分支 diff 名单核对不在内）；全分支对基线
  d085a80 共 16 文件 +569/−36。
- 真机未验项见上节清单（1–5），照例待用户装机验。
