# v4.5 家族协作与传承（第一期）落实记录

分支 `feat/family`（worktree liqian-wt-family），基于 v3.1。未 commit，待主线按合并顺序（icloud→reply→scene→advisor→libu-live→family）串行合并过 CI。

## 1. 礼簿班子（已落地）

- 新模型 `LedgerMember`（`Sources/LiqianCore/Family.swift`）：`id`（unique）、`ledgerID`、`name`、`role`（中文串：主家/书记/核实/只读）、`createdAt`。靠 `ledgerID` 挂礼簿、不用关系宏，与 GiftRecord 同口径，保证备份/回收站快照式处理一致。
- **模型注册改动**：`Sources/LiqianApp/LiqianApp.swift` 的 `modelContainer(for:)` 数组加 `LedgerMember.self`（全仓仅此一处容器）。新文件均在 `Sources/**` glob 内，Project.swift 无需改。
- 角色枚举 `MemberRole`：`sortOrder`（主家 0 → 只读 3）、`canEdit`（只读为 false）、`sharePermission` 权限映射（见 §3）。
- 管理页 `Sources/LiqianApp/LedgerMembersView.swift`：详情页头部之下、记录之上独立一组入口（「礼簿班子」＋「交接与纪念版」），**未动 v2.5 定版的「更多」菜单**。成员增/改（姓名＋角色 Picker）/左滑删（带确认，文案明示落款连带影响）。

### 班子 ↔ 礼簿字段同步规则（定版，纯函数在 Core `MemberSync`，单测覆盖）

- **书记 / 核实：班子是唯一真源。** 任何班子变更后，`Ledger.scribe` / `verifier` 由班子推导覆盖；班子无此角色成员 → 字段清空。保证礼谱 PDF 落款（走字段口径）与班子永远一致。
- **主家：不对称。** 班子有主家成员 → `hostName` 跟随班子代表；没有 → 字段保持现值不清空。原因：`hostName` 除「本簿主家」外还兼全局落款回退链（礼簿主家→全局设置→字面「主家」）与建簿预填语义，随班子清空会误伤老数据。
- **代表推导**：同角色多人时取 `createdAt` 最早者，并列按姓名定序，结果确定。
- **反向种子**：首次打开班子页且班子为空、礼簿字段有值时，按字段生成种子成员（顺序主家→书记→核实，`createdAt` 按序递增保代表推导稳定；同名一人多职生成多个成员）。用 `UserDefaults` 键 `membersSeeded.<礼簿id>` 标记已管理，防止用户主动删空班子后种子「复活」。

## 2. 备份与回收站（已落地）

- `BackupFile` 新增可选段 `members: [BackupMember]?`（`Sources/LiqianCore/Backup.swift`）：`id`/`ledgerId`/`name`/`role` 均为 String（与 BackupRecord 同口径），`createdAt` 用 ISO8601 串；解码对 `role`/`createdAt` 用 decodeIfPresent 兜底。旧备份无此段 → 解析为空数组；旧版 App 读新备份按未知键忽略，向前兼容。
- `LiqianBackup.makeBackup` 加 `members: [LedgerMember] = []` 参数（既有调用方不传即旧行为）；`parseBackupFull` 返回值扩为四元组 `(ledgers, records, reminders, members)`，既有调用方按 label 取值不受影响。
- 「我的」导出传全部 members；恢复（MeView.performImport）先清现有 members、再按 idMap 重挂，成员 `id` 与 `createdAt` 原样保留（代表推导不失真），完成文案带班子计数。
- 回收站：`TrashItem` 加 `ledgerMembers: [BackupMember]?`（旧快照 nil 视为无班子）；删礼簿（LedgersView）时班子随簿归档并删除，恢复时挂回新礼簿 id、同 id 不重复插。

## 3. 协作邀请（UI 已落地，CloudKit 接通留 TODO —— 如实标注，未伪造完成）

- `Sources/LiqianApp/Sharing.swift`：
  - `SharingAvailability` 五态（available / noAccount / restricted / storeNotCloudKit / couldNotDetermine），每态有面向用户的人话文案；班子页协作区按状态展示，不可用时「邀请家人协作」按钮禁用，绝不尝试创建共享。
  - 权限映射逻辑完整：Core `MemberRole.sharePermission`（主家=.owner、书记/核实=.readWrite、只读=.readOnly），App 层 `LedgerSharing.permissionText(for:)` 翻成人话，班子页逐角色列出。
  - `UICloudSharingController` 的 `UIViewControllerRepresentable` 桥（`CloudSharingView` ＋ Coordinator）已写好，但当前构建不可达。
- **未接通的根因（两条，任一成立即不可用）**：①当前 `modelContainer` 是纯本地 SwiftData，未启用 CloudKit 镜像，CKShare 无可挂的持久化存储；②SideStore 侧载未签名构建无 iCloud entitlement。另：SwiftData 至今无公开的对象级共享 API，接通路径需在 coordinator 层用 NSPersistentCloudKitContainer 取/建 CKShare。
- **接通点（TODO 已写在 Sharing.swift 文末）**：feat/icloud 落地 CloudKit 容器后，把 `LedgerSharing.storeIsCloudKitBacked` 置 true → `accountStatus()` 真实检查生效 → 按班子名单逐个加参与者（权限取 `sharePermission` 翻译为 `CKShare.ParticipantPermission`，主家不入参与者名单）→ 呈现 `CloudSharingView`。UI 与映射无需再改。

## 4. 传承（已落地，不依赖 iCloud）

- 交接页 `Sources/LiqianApp/HandoverView.swift`（入口在详情页班子同组）：
  - **传承包**：`makeBackup(ledgers: [本簿], records: 本簿记录, members: 本簿成员)` 写临时文件「<簿名>-传承包.json」，ShareLink 分享；格式即全量备份的单簿切片，接收方可用现有「从备份恢复」接手（注：现恢复为整库覆盖口径，单簿合并导入是后续项，本期如实按整库恢复用）。
  - **交接说明**：独立一页 A4 横排 PDF（`HandoverNotePDF`）：簿名、事由、日期（含干支）、地点、收礼/随礼笔数与总额（口径排除待送出，与统计/礼谱一致）、主家（回退链：礼簿主家→全局设置→「主家」）、书记/核实、班子名单、交接日期（公历＋农历）、恢复方法说明与落款。
  - **纪念版礼谱**：`GiftBookPDF.makePDF` 新增 `memorial: Bool = false` 参数并透传 `drawCover`；为 true 时封面右上加竖排「紀念」题签（细白框＋白字，楷体 19pt，位于 pageW-64、top 54，避开居中题字与题字右 +70 的闲章）。页内 PDFKit 预览＋ShareLink，只读导出物不回流数据。

## 5. 单测

`Tests/LiqianCoreTests/FamilyTests.swift`（9 例）：代表取最早加入者；fields 推导（书记/核实由班子定、无角色清空、主家有成员跟随/无成员保留）；seed 顺序与跳空、空白修剪；sharePermission 映射与 canEdit；备份带 members 往返（id/createdAt 保真）；旧备份（无 members 键）解析为空。

## 6. 真机待验

- 班子页：种子生成（用一本已填书记/核实的老礼簿首开）、增删改后详情页副标题与礼谱落款同步、删空班子不复活。
- 传承包：生成→分享→另一台/重装后恢复，班子随簿回来且落款代表不变。
- 纪念版：封面「紀念」题签位置观感（与闲章距离）、白事簿题签在素蓝封面上的对比。
- 协作区：当前构建应恒显「需要正式版 iCloud 环境」文案且按钮禁用、不闪退。
