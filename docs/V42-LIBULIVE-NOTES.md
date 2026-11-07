# V42 活礼谱落实记录（feat/libu-live，未提交，待父级合并）

分支 `feat/libu-live`（worktree `~/workspace/liqian-wt-libu-live`）。本轮只改文件、
未 commit/push/merge。实现：来宾签名＋语音祝福入谱（数据模型、采集、电子礼谱、
礼谱 PDF 标记/簽名頁/祝福索引、备份元数据段与诚实文案）。

## 新增文件

| 文件 | 内容 |
|---|---|
| `Sources/LiqianCore/LiveModels.swift` | `GuestSignature`、`VoiceBlessing` 两个 @Model；`LiqianDeepLink`（liqian://blessing/<id> 构造/解析）；`LiqianISO8601` |
| `Sources/LiqianApp/BlessingAudio.swift` | `BlessingAudioStore`（Application Support/Blessings/，库里只存文件名）、`BlessingPlayer`、`BlessingRecorder`（AVAudioRecorder/AAC）、`BlessingTranscriber`（文件型 SFSpeechRecognizer 转写）、`blessingDurationText` |
| `Sources/LiqianApp/SignatureCaptureView.swift` | PencilKit 签名画布（`.anyInput` 手指可签、白纸黑笔固定口径、PNG 透明底出图）、`SignatureThumbnail`、`RecordLiveMediaSection`（记录编辑页「签名与祝福」区） |
| `Sources/LiqianApp/VoiceBlessingView.swift` | `RecordBlessingsView`（一笔的祝福：录/播/删/自动转写）、`BlessingPlayerView`（深链扫码落点播放页） |
| `Sources/LiqianApp/ElectronicLibuView.swift` | 电子礼谱阅读页（原生排版，见下「选型」） |
| `Tests/LiqianCoreTests/LiveBackupTests.swift` | 元数据往返、二进制不入 JSON、空段不写键、旧备份兼容、深链往返，共 5 例 |

## 模型

- `GuestSignature`：id(.unique)、ledgerID、recordID（可空：现场可先签后挂笔）、
  person（原文）、`imageData`（PNG，`@Attribute(.externalStorage)`）、createdAt。
- `VoiceBlessing`：id(.unique)、recordID（非空）、fileName（仅文件名，相对路径入库）、
  duration（秒）、transcript（可空）、createdAt；`deepLink` 计算属性。

## 入口（采集 flow）

- 礼簿详情：记录行**长按 contextMenu**「请来宾签名」「语音祝福」；
  头部下方独立一行 **电子礼谱** 入口（不藏「更多」，副文案报真实签名/祝福数）。
- 记录编辑页（仅编辑态，新建笔先保存才有 id 可挂）：「签名与祝福」卡
  （签名缩略/再签/删签、祝福段数入口）。
- 人物页：时间线行长按同样两个动作（与详情页一致）。
- 语音祝福 sheet 内录制：点「录一段祝福」→ 权限（复用既有麦克风文案）→
  录/停；<0.5 秒视作误触不落库；落库后异步文件转写回填 transcript，
  转写不可达留空，不阻塞、不编造。删除 = 删行＋删音频文件。

## 电子礼谱（选型：原生排版，不用 PDF 页图）

理由：PDF 页图点不动、播不了声，「活」的价值在逐笔交互。TabView 分页：
封面 → 记录页（每页 6 笔；有祝福带「聲」标＋听祝福钮、有签名显缩略图）→
签名页（网格）→ 答谢页。成册口径与 PDF 一致（排除待送出、日期升序＋同日姓名序）。
纸礼谱 PDF 仍是导出存档正本，电子礼谱是随身翻看本。

## 礼谱 PDF（GiftBookPDF）

- `makePDF` 新增默认参数 `signatures: [GuestSignature] = []`、
  `blessings: [VoiceBlessing] = []`（LibuExportView 透传，详情页按本簿过滤后传入）；
  两者为空时出谱与旧版逐页一致。
- 内页标记：有祝福的笔在姓名列右上出主色方框「聲」小印记（楷体 10.5，
  白事走素蓝主色 baiPrimary）；`drawContentPage` 加 `blessedRecordIDs` 参数。
- 「簽名頁」：**汇总之后、答谢之前**（满足「内页之后、答谢之前」）；两列网格，
  签名图等比居中＋姓名小字（用户数据原样）＋格下细线；只排已签名的，
  无签名的笔不占位。排序：挂笔的跟成册记录序，未挂笔（recordID 空）按
  createdAt 附后；recordID 不在成册口径内的签名不入谱。
- 「祝福索引」：卷末補記之后（全谱最后）。一段一行：二维码（CIQRCodeGenerator
  整倍率放大＋关插值）＋姓名＋日期/时长＋转写节录（24 字截断）。二维码内容
  `liqian://blessing/<voiceBlessingID>`；页题下注记如实写明
  「掃碼聆聽來賓祝福（需安裝『禮錢賬本』App 方可打開）」，不承诺外部可用。
- 既有口径未动：固定文字繁体、用户数据严禁转换（签名页姓名/索引姓名与
  转写均原样）、白事无賀字（新页固定串为簽名/祝福索引/聲，均无賀）、
  金额大寫规则不变。

## 备份（诚实口径）

- `BackupFile` 加可选段 `signatures` / `voiceBlessings`（**仅元数据**；
  签名 PNG 与祝福音频二进制不进 JSON）。两组为空时写 nil，没用过活礼谱的
  备份与旧格式同构；旧备份无此二键解码为 nil；新备份被旧版 App 读时按未知键忽略。
- `makeBackup` 加默认参数 `signatures/blessings`（原调用点可不改照样编译）；
  新增 `LiqianBackup.parseBackupLive(_:)` 容错解析（坏段回退空，不拖垮主校验）。
- 恢复策略（MeView.performImport）：覆盖恢复时旧签名/祝福行一并清除；
  **祝福元数据行恢复**（记录 id 对得上才挂；转写文字随之回来；录音文件不在
  新设备上时，播放处如实提示「保存在录制的那台设备上」）；
  **签名不恢复成行**（无图，重建即空行）——备份里的签名段是「谁签过」的存档清单。
  旧录音文件恢复时不删除（元数据可能引用同名文件），可能留少量孤儿文件。
- 文案（已改）：导出备份行副文案与「关于」页脚均注明「签名图片与祝福录音
  不在备份内（保存在本机与 iCloud）」。

## 注册点清单（合并时父级处理）

1. `Sources/LiqianApp/LiqianApp.swift`：modelContainer 数组追加
   `GuestSignature.self, VoiceBlessing.self`（已在行内注释提醒：若 icloud 等
   分支也改了这一行，取并集勿覆盖）。
2. `Project.swift`（LiqianApp target infoPlist）：新增 `CFBundleURLTypes`
   注册 scheme `liqian`——**此前全仓未注册**（小组件 liqian://quick-record
   一直靠系统宽容在跑），祝福深链依赖它；若其他分支已注册，保留一份即可。
3. `Sources/LiqianApp/ContentView.swift`：onOpenURL 在 quick-record 之外加
   blessing 分支（命中后弹 BlessingPlayerView；隐私锁锁定时不弹，不绕过锁定页）；
   新增 `@Query allBlessings` 与 `@State deepLinkBlessing`。
4. 其余改动文件（调用点/透传，非注册点）：LedgerDetailView（@Query×2、长按菜单、
   电子礼谱入口行、导出透传）、LibuExportView（透传参数，带默认值）、
   RecordFormView（编辑态插入 RecordLiveMediaSection）、PersonDetailView
   （modelContext＋长按菜单＋两 sheet）、MeView（@Query×2、导出入参、导入
   pendingLive 与恢复段）、GiftBookPDF、Backup.swift。

## 已知边界

- 记录被删（进回收站）后，其签名/祝福成孤儿：读者与 PDF 都按「记录还在」
  过滤，孤儿不显示、不入谱，但行与音频文件不随删（与 ReminderDay 的既有
  口径一致）；回收站恢复记录后签名/祝福自然回归。礼簿整本删除同理。
- 签名缩略与 PDF 签名图均为笔迹原图（透明底），签名页/缩略以白/纸面衬底呈现。
- 转写用文件型识别（SFSpeechURLRecognitionRequest，zh-CN，支持时强制本地）；
  与 QuickSentenceView 的实时麦克风转写是两条路（一个对文件、一个对麦克风流），
  共用 Speech 框架与授权，互不影响（含其 isStarting 闸门加固未动）。

## 自查

- 全仓括号配平脚本：本次新增/修改的 16 个文件全部配平（4 个存量文件因字符串
  内括号计数不平，与本次无关，未动）。
- 符号自查：新代码引用的 Palette 令牌（primaryTint 等）、语义字阶、
  LiqianDate.displayString、LibuText.traditionalGenerated 等均已逐个 grep
  对照本分支源码（注意：本分支无 .serifBody/.bodyMedium/Palette.fill/
  Palette.onPrimary 等令牌，初稿误用已全部改正）。

## 真机待验（合并出包后）

1. 签名画布手指书写流畅度与出图清晰度；簽名頁在 PDF 预览里的版面（图比例/姓名位）。
2. 录音→转写回填是否生效（中文短句）；深链：用另一台设备扫礼谱索引页
   二维码 → 是否唤起 App 并弹出播放页（依赖 scheme 注册，SideStore 重签后复验）。
3. 电子礼谱翻页与播放钮；白事簿全程素蓝口径目检（聲标/签名页/索引页）。
4. 旧备份恢复不回归（无 live 段）；新备份恢复后祝福转写可见、录音缺失提示正确。
