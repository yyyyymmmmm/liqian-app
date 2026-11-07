# v4.5 第二组：Share Extension（微信接龙分享进来直接解析）

分支 `feat/v45-share`（worktree 落码，未 commit，父级串行合并过 CI）。
目标链路：微信接龙里长按/转发 → 系统分享面板选「礼记」→ 扩展里预览文本、
选目标礼簿 → 暂存进 App Group → 打开主 App → 自动弹出既有批量解析
待确认流（粘贴模式、预填文本、预选礼簿）→ 用户核对确认后落库。

## 落点

| 文件 | 改动 |
|---|---|
| `Project.swift` | 新增 target `LiqianShare`（appExtension，bundleId `site.didichou.liqian.share`），挂为 LiqianApp 依赖（随 App 嵌入）；entitlements 只给 App Group；Info.plist 版本字面量直写 4.5.0/45 |
| `Sources/LiqianShare/ShareViewController.swift` | 扩展本体（新文件）：`ShareViewController`（NSExtensionPrincipalClass，UIHostingController 宿主）＋ `ShareImportModel` ＋ `ShareImportView` ＋ `ShareChannel`（通道键与礼簿镜像结构） |
| `Sources/LiqianApp/WidgetSummary.swift` | `WidgetSummaryWriter` 新增：`LedgerListItem`（id/title/date）、`writeLedgerList(ledgers:)` 写礼簿清单快照；新增三个键常量 |
| `Sources/LiqianApp/ContentView.swift` | `refreshWidgetSummary()` 末尾顺手写礼簿清单快照；新增 `checkShareImport()` 承接＋深链分支＋sheet/alert；`.task`、scenePhase 回前台、解锁（isLocked onChange）三处触发补检 |
| `Sources/LiqianApp/BatchEntryView.swift` | 仅加呈现层入口：`initialPasteText`（默认 nil）＋ onAppear 时切粘贴模式并预填。解析引擎（LedgerTextParser）、预览/校验/确认导入一字未改；详情页既有入口不传参、行为不变 |

## 激活规则

`NSExtensionActivationRule = { NSExtensionActivationSupportsText: true }`：
只对纯文本出现，图片/文件/链接不接（批量解析只吃文本）。

## 深链与暂存键清单（App Group：`group.site.didichou.liqian`）

| 键 / URL | 写方 | 读方 | 语义 |
|---|---|---|---|
| `ledgerList`（Data，JSON `[{id,title,date}]`） | 主 App `WidgetSummaryWriter.writeLedgerList`（启动/回前台刷新，顺序＝礼簿日期倒序） | 扩展 `ShareChannel.loadLedgers` | 礼簿清单快照，不含任何金额/记录；第一本＝最近一本，扩展默认选中 |
| `shareImportText`（String） | 扩展「存入并打开礼记」 | 主 App `checkShareImport` | 待解析全文；主 App 确定能弹确认流时读后即清 |
| `shareImportLedgerID`（String，UUID） | 扩展（用户所选；无清单时不写） | 主 App `checkShareImport` | 目标礼簿；已删/缺失时主 App 落最近一本 |
| `liqian://share-import` | 扩展 `extensionContext.open` 尝试唤起 | 主 App `ContentView.onOpenURL` | 仅作唤起信号，数据全走暂存键，不走 URL 参数 |

## 承接守卫（主 App）

- 隐私锁锁定中：不读不弹（与 blessing/person 深链同一守卫）；解锁瞬间
  由 `isLocked` 的 onChange 补检，不必退后台再回来。
- 暂存为空/纯空白：静默作罢。
- 没有任何礼簿：**不清暂存**，等建好礼簿后下次触发再承接（防文本丢失）。
- 已有导入 sheet 在弹：不重复弹。
- 导入完成：沿用详情页口径弹「共记 N 笔」alert。

## 降级口径

- **App Group 不通**（SideStore 等重签剥掉 group entitlement）：判据用
  `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` 为 nil
  （`UserDefaults(suiteName:)` 本身永远非 nil，不能当判据）。扩展直接显示
  明示空态：「当前安装方式不支持分享导入，请复制文本后在 App 内用批量补录」，
  不暂存、不假装成功；主 App 侧读不到暂存即静默无事。
- **扩展 open 主 App 失败**（分享扩展的 open 常被系统拒绝）：文本已暂存，
  界面改示「已经存好了。打开『礼记』就会接着让你核对导入。」＋「完成」钮；
  用户手动打开 App 后由回前台/冷启动的 checkShareImport 接上。
- 扩展激活进来却没读到文本：安全口空态提示重新分享，不崩。

## 红线自查

- 解析引擎与待确认流本身未改（BatchEntryView 只加入口参数与 onAppear 预填）。
- 数据模型/待回口径未动；扩展不碰 SwiftData，只写 App Group 暂存。
- 扩展 UI 极简且不链 LiqianDesign（与 Widget 先例一致，朱砂镜像一处常量）。

## 真机待验项

1. 微信内对接龙文字走系统分享，面板里出现「礼记」（图标+名称），且只对
   文本出现、对图片分享不出现。
2. 扩展里礼簿清单与 App 内一致、默认选中最近一本；改选后导入落到所选簿。
3. 点「存入并打开礼记」：能自动打开主 App 并直接弹批量补录（粘贴模式、
   文本已填）为最佳路径；打不开时出现手动打开提示，手动打开后自动承接。
4. 隐私锁开启时分享导入：锁定时不弹，解锁后立即补弹。
5. SideStore 重签包上验 App Group 互通：不通时扩展显示明示空态、主 App
   无异常弹窗；通时全链路同官方签名表现。
6. 暂存礼簿已被删：导入落到最近一本，不丢文本。
7. 完全没有礼簿时分享：暂存保留，建第一本礼簿后回前台能承接。
8. 大段文本（整本旧礼簿数千字）：扩展预览截断正常、全量暂存不丢字，
   主 App 解析预览行数正确。
