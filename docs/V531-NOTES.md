# v5.3.1 隐私政策与用户协议专业重写（政策/协议 v2.0）

用户指令：隐私与用户协议也不专业，对标专业写法、结合实际重写。此指令
重开此前定稿，旧稿（Legal.swift v1.x 全文）作废，本版整体替换。

## 一、事实审计（政策每句话的依据，2026-11-08 全仓实查）

### 1. 系统权限（App Info.plist 实声明，源在 Project.swift）

| 声明键 | plist 文案 | 实际用途（代码出处） |
|---|---|---|
| NSCameraUsageDescription | 用于拍摄纸质礼单，识别姓名与金额 | PhotoOCRView 用 UIImagePickerController 拍照 → Vision 本机 OCR |
| NSMicrophoneUsageDescription | 用于语音记账，把你说的话转成文字 | QuickSentenceView 语音记账；BlessingAudio 语音祝福录音（AVAudioRecorder，m4a） |
| NSSpeechRecognitionUsageDescription | 用于将语音转写为记账文字 | QuickSentenceView 语音记账转写；BlessingAudio 语音祝福转写 |
| NSFaceIDUsageDescription | 用 Face ID 保护你的人情账本不被旁人看到 | AppLock.swift（LAContext）隐私锁 |
| NSSupportsLiveActivities | （布尔键） | 现场模式本地 Live Activity，仅本地启动/更新，不走 APNs |
| UIBackgroundModes: remote-notification | （模式键） | CloudKit 静默推送唤醒同步 |

- 相册：走 PhotosPicker 系统选择器（PhotoOCRView），制度上无需 plist
  声明、App 无整库相册访问能力，政策按「系统选择器逐张选取」如实写。
- 通知：UNUserNotificationCenter 运行时授权（ReminderScheduler），
  无 plist 键（制度如此）；提醒全部本地排定。
- 通讯录/定位/跟踪：全仓无 CNContact、无 CoreLocation、无 ATT/IDFA。

### 2. 数据存储

| 载体 | 存什么 |
|---|---|
| SwiftData 本地库 | 礼簿、记录、自定义关系、提醒、签名图片（imageData，externalStorage） |
| CloudKit 私有库（容器 iCloud.site.didichou.liqian） | 开启同步时同上，经 ModelContainer cloudKitDatabase .private；不可用自动回退本地（CloudSync.swift） |
| CloudKit 共享（CKShare） | 家族协作：Sharing.swift 经 NSPersistentCloudKitContainer 为礼簿取/建 CKShare，受邀成员按角色可见/可协助记录 |
| App Group UserDefaults（group.site.didichou.liqian） | 小组件精简摘要（待回人数/总额/top 姓名与逐人待回额、本月收送、下一场提醒的标题/人名/日期、往来人数）＋记一笔标记通道；经 AppGroupResolver（含侧载 ALTAppGroups 回退读取） |
| 本机文件区 | 语音祝福录音 blessing-<uuid>.m4a（文件名记在 SwiftData 模型中） |
| Keychain | 仅 DeepSeek API Key 一项（service site.didichou.liqian.deepseek，未设 synchronizable，不进备份、不同步） |
| UserDefaults.standard | 设置与标记；AI 验证记录（AIVerification 只存结论/时间/Key 尾号指纹/失败原因，不存 Key 本身） |
| 导出文件 | JSON 备份（账目＋签名/祝福元数据段，**不含签名图片与录音的二进制本体**；文件未加密）/ CSV / 礼谱 PDF / 家族汇册 PDF——全部本机生成、经系统分享或文件导出由用户自选去向 |

### 3. 网络出口（全仓 URLSession/URLRequest 实测）

唯一业务出口：`https://api.deepseek.com/chat/completions`（DeepSeek.swift
的 chat 与 chatTurn 两处）。其余网络均为 Apple 系统服务（CloudKit 同步、
StoreKit 购买/恢复、系统评分请求）。逐条 AI 路径发送内容：

| 路径 | 触发 | 实际发送 |
|---|---|---|
| 问账管家（chatTurn 工具循环） | 用户提问 | 问题文字＋本机工具按需查到的结果子集（AdvisorView/AdvisorTools） |
| 问账降级（v4.4 意图解析） | 工具路径失败回退 | 仅问题文字 |
| 一句话记账解析 | 用户输入/语音转写后 | 那句话的文字 |
| 批量补录/接龙导入 | 用户粘贴后点 AI 解析 | 粘贴原文（BatchEntryView） |
| 拍礼簿 AI 增强 | OCR 后点 AI 增强 | OCR 识别出的**文字**（照片不发，PhotoOCRView.runAIEnhance） |
| 贺词生成 | 用户点生成 | 场合、礼簿名、用户填的主家姓名与关系、口吻（GreetingView） |
| 礼谱谱序 | 导出礼谱时 | 事由、干支日期、地点、主家姓名、到场人数——无金额、无名单（LibuExportView） |
| Key 验证 | 保存/手动验证 | 一次极小的测试对话请求（AISettingsView） |

全部前提：用户已在「我的 → AI 管家」开启 AI 并填入自备 Key；直连、
不经开发者服务器，开发者不保存发送内容。

### 4. 第三方 SDK / 依赖

Project.swift 全部 target 只依赖内部 target（LiqianCore/LiqianDesign/
LiqianWidget），无 .external 依赖、无 Package.swift/Package.resolved。
**第三方 SDK 数量为 0**：无统计、无广告、无崩溃上报、无第三方推送。
其余均为 Apple 系统框架（Vision、Speech、AVFoundation、
LocalAuthentication、UserNotifications、CloudKit、StoreKit、
WidgetKit、ActivityKit）。

### 5. 其他功能事实

- OCR：Vision VNRecognizeTextRequest，本机识别，照片不上传。
- 删除：记录/礼簿进「最近删除」保留 30 天自动清除（TrashStore 实测）。
- 买断：StoreKit 2，产品 site.didichou.liqian.pro，一次性买断；
  门控四处＝CSV 导出/纪念版礼谱/家族汇册/印刷版礼谱（EntitlementCenter）。
- 成书：App 内仅意向登记（本地留痕＋预填 mailto），人工履约内测，
  无在线下单与在线支付。

### 6. ⚠ 审计差异（标红项，只标不擅改代码/配置）

1. **麦克风 plist 文案窄于实际用途**：文案只写「语音记账」，实际还用于
   语音祝福录音（BlessingAudio.swift 注释自承「权限文案复用既有麦克风
   说明」）。新政策已按实际用途写全；建议后续版本把 plist 文案扩为
   「用于语音记账与录制语音祝福」，本版未动工程配置。
2. **语音识别两条路径口径不同**：语音祝福转写强制本机识别
   （requiresOnDeviceRecognition = true）；语音记账（一句话）未设该
   标志，走 iOS 系统语音识别服务、可能经 Apple 服务器。旧政策一句
   「语音输入使用 Apple 的系统语音识别服务」混写两者。新政策第四节
   已分开如实表述；代码未动。
3. **旧用户协议与现状硬冲突（旧稿作废主因之一）**：旧稿称「礼记目前
   免费提供、未来收费会告知」，与 v5 已落地的买断会员直接矛盾；旧稿
   亦未覆盖家族共享可见性、小组件摘要、成书内测等现行功能。

## 二、重写说明

- 两份文档整体替换 Legal.swift 旧全文，版本记为 **v2.0**，生效日期
  **2026 年 11 月 16 日**，运营者知和数智，联系邮箱
  inkroot001@gmail.com；旧称「AI 智能助手」统一为「AI 管家」
  （全仓已无旧称残留）。
- 隐私政策 13 节：运营者→信息清单（行式）→不收集清单→权限逐项
  （用途＋拒绝影响）→存储与期限→第三方清单（单列 Apple/DeepSeek，
  并明示此外无第三方、无广告无统计 SDK）→AI 发送明细（行式）→
  家族协作→用户权利（含 App 内具体路径）→未成年人→安全措施→
  更新方式→联系我们。
- 用户协议 12 节：服务与无账号→数据归属→免费与买断（权益以付费墙
  为准、价格以 App Store 为准、退款依 Apple 政策、已购权益不因版本
  更新取消）→AI 条款（第三方/自备 Key/费用自担/输出仅供参考/金额以
  本地账目为准）→成书内测（人工履约、确认价格后付款、参考价
  299–399 与周期约 10 天仅预估、定制印制不适用七日无理由退货、质量
  问题重印或退款）→使用须知→知识产权→变更中断→责任限制→协议
  更新→法律适用与争议解决（协商不成向运营者所在地法院起诉）→联系。
- 逐句依据纪律：凡审计里没有的能力不写（如未承诺端到端加密；只写
  审计坐实的「AI 请求 HTTPS 直连」「Key 存钥匙串」等）。

## 三、呈现结构扩展（最小改动）

现 LegalView 只有「标题＋段落」，装不下表格化清单，作两处最小扩展
（Legal.swift 内）：LegalSection 新增 `items: [String]` 行式清单
（渲染为细线分隔的逐行列表），LegalDoc 新增 `summary` 文首一句话
摘要（渲染在版本行下方）。无清单的节渲染与旧版一致；MeView 两处
入口（我的页与关于页）路径不变。

## 四、PrivacyInfo 交叉核对

- App PrivacyInfo.xcprivacy：NSPrivacyTracking=false；收集类型仅
  OtherUserContent（AppFunctionality、未关联、未跟踪），对应 DeepSeek
  直连，与新政策一致；UserDefaults 必备理由 CA92.1＋1C8F.1 与实际
  用法一致。
- Widget PrivacyInfo.xcprivacy：收集类型空数组、UserDefaults 1C8F.1，
  与实际一致（扩展只在本机读 App Group 摘要）。
- 结论：两份清单与新政策口径一致、无明显错误，**本版不改清单文件**。

## 五、验收实测

（CI 完成后回填。）

## 六、真机待验（未验，不宣称已验）

1. 「我的 → 隐私与协议」两份文档从头滑到底：摘要、清单行细线分隔、
   长节排版正常，无截断无重叠；
2. 关于页内两处入口打开的仍是新版文档，路径与标题不变；
3. 深色模式与五套主题下文字对比正常。

## 七、给用户的提醒

本版文本按专业范式与代码实情写成，但未经律师执笔。**正式上架前
建议请律师复核一遍，买断会员条款与装订成书条款为复核重点。**
