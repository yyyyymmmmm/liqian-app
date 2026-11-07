# V29-NOTES · 拍照识别礼单（v2.9）

竞品对标功能（礼小记头牌）：对着纸质礼单/红包名单拍照或相册选图，
识别姓名＋金额多笔 → 待确认列表 → 一次导入当前礼簿（收礼）。
范围纪律：未动数据模型与备份格式（识别结果走既有 GiftRecord 保存
通道）；未 commit/push；本机无 Swift 工具链，真编译走 CI。

## 1 入口（两处同一 flow）

- 礼簿详情「更多」菜单加「拍照识别礼单」，紧随「批量补录」之后
  （同为成批录入）；菜单顺序注释已同步更新，删除仍垫底。
- 批量补录页顶部加同名入口 Section（说明行＋导入回执行），打开
  同一个 `PhotoOCRView` sheet；大字模式下入口 Label 字号同步放大
  （现场登记场景一致）。回执两处形态：详情侧走 alert「识别导入
  完成／共导入 N 笔收礼」，批量页内走入口区一行消息（不打断补录）。

## 2 识别管线（两段）

- 第一段设备端：`GiftListOCR`（PhotoOCRView.swift）——照片先抹
  方向、最大边限 2048、重编码 JPEG，只把 Data 传进后台
  Task.detached，CGImage 解码与 VNRecognizeTextRequest 都在任务
  内部构造（Swift 6 下不跨并发域传图）。accurate 模式、
  recognitionLanguages = ["zh-Hans", "en-US"]、语言纠错开。
  识别全程 on-device，照片不联网、不上传。
- 第二段规则解析：OCR 文本行走新增 Core 组装层
  `OCRCandidateBuilder`（Sources/LiqianCore/OCRCandidates.swift），
  内部复用与粘贴导入共用的 LedgerTextParser：成功行→候选，
  失败行→skipped（原文＋原因＋真实行号），任何一行不静默吞。
- AI 增强：确认页（规则结果时）有「AI 增强识别」按钮，把 OCR
  原文走 DeepSeek＋Core `AIParse.decode` 多笔管线再解析，结果
  **替换**候选并标注来源（本地规则解析／AI 增强）。口径与智能
  粘贴一致：随礼条目不混入（本页固定收礼），无效条目与
  uncertain 行号一并计入「另有 N 条没有列进来」明示。AI 失败时
  保留规则结果、只报错。按钮点下先查 AIAccess 就绪状态，未就绪
  走既有引导 alert（与一句话记账/智能粘贴同款）。
- 两段为空：候选为 0 进 empty 态，明示「没认出姓名和金额，换一
  张更清晰的照片，或用粘贴导入」＋拍摄建议，不静默；Vision 本身
  抛错则回选图态并在选图区红字说明。

## 3 确认列表（复用 v2.7 待确认模式）

- 原图缩略图置顶（限高 180，带「换一张图」重置回选图态）。
- 每行：姓名 TextField＋¥ 金额 TextField（decimalPad）可改、
  xmark 删行；关系随行带走并以小字展示（行内不编辑，与 v2.7
  口径一致）；同名行给「本礼簿已有同名记录，导入后将并列保存」
  提示（查本礼簿 @Query 姓名集，与批量粘贴同款）。
- 「识别原文」DisclosureGroup 默认折叠，行号＋原文可选中复制，
  方便对照原图逐行核对；skipped 计数在待确认 Section footer
  明示（规则/AI 两种文案）。
- 底部「导入全部（N 笔）」：落库口径与批量补录一致——方向
  received、关系默认「朋友」（解析带了关系则用解析值）、方式
  默认「现金」、日期今天；行校验（姓名非空、金额 >0）在导入时
  复查，不合格整单拦下并红字定位说明，不部分落库。

## 4 权限与说明文案

- Project.swift 补 NSCameraUsageDescription「用于拍摄纸质礼单，
  识别姓名与金额」。相册走 PhotosPicker 系统选择器，无需权限。
  相机不可用（模拟器等）时拍照钮禁用并给一行说明。
- 相机用 UIImagePickerController 桥接（SwiftUI 至今无原生相机
  拍摄控件）；入口页如实写明「适合印刷体和工整手写的礼单；字迹
  潦草可能认不准」，不夸大识别能力。

## 5 单测

- 新增 Tests/LiqianCoreTests/OCRCandidatesTests.swift（3 例）：
  多行礼单文本→多笔候选（金额换算/关系/行号/原文）；含噪声行
  （标题、空行、中文数字金额「五百」——规则解析只认阿拉伯数字，
  这类正是 AI 增强的用武之地）→ skipped 带原因且不吞行；空文本
  → 两堆皆空。LedgerTextParser 本体测试未动（已覆盖）。

## 6 自查

- 改动/新增 6 文件括号配平全过（递归扫描器，识别字符串与插值，
  以未改动的 QuickSentenceView 为对照同法验证）。
- grep：NSCameraUsageDescription 落位、两处入口 Label、两段管线
  关键调用（VNRecognizeTextRequest/accurate/zh-Hans/
  OCRCandidateBuilder.build/AIParse.decode/photosPicker）齐。

## 7 真机待验（CI 出包后）

- 真机相机拍摄全流程（授权弹窗文案、拍完回 sheet 的衔接）。
- 印刷体礼单照片与工整手写礼单各一张的识别率；潦草手写下
  AI 增强的实际改善幅度。
- 大图（相机原图）识别耗时与缩略图显示；SideStore 重签下
  相机权限是否正常授予。
