# V40 iCloud 同步落实记录（feat/icloud）

目标：SwiftData + CloudKit 私有数据库自动同步——用户换机/重装后数据自动回来，
这是「永不丢」地基。本分支未 commit/push/merge；本机无 Swift 工具链，未真编译，
待父级走 CI 验证（已做括号配平与 grep 自查，改动 5 文件全平、残留 grep 见下）。

## 改动清单

| 文件 | 改动 |
|---|---|
| `Project.swift` | App target 加 iCloud entitlement（见下）＋ InfoPlist `UIBackgroundModes: [remote-notification]` |
| `Sources/LiqianCore/Models.swift` | 三模型 CloudKit 兼容改造：去 `.unique`＋非可选属性补声明默认值（逐项审计见 §3） |
| `Sources/LiqianApp/CloudSync.swift` | **新增**：同步管理器（容器分级回退、账号探测、同步事件状态、界面文案） |
| `Sources/LiqianApp/LiqianApp.swift` | 容器改为 `CloudSyncManager` 持有的一份，`.modelContainer(cloudSync.container)`，管理器经 environmentObject 注入 |
| `Sources/LiqianApp/MeView.swift` | 「数据」组首行加 iCloud 同步开关行（状态副标题＋未登录时「打开系统设置」行）＋组 footer 说明；「关于」页旧文案「数据仅保存在本机」同步更正 |

## 1. 工程配置（Project.swift）

- 容器 ID：`iCloud.site.didichou.liqian`（iCloud. + 现有 bundle id `site.didichou.liqian`）。
- Entitlements 新增三项（原 App Groups 保留不动）：
  - `aps-environment` = `development`（CloudKit 静默推送；
    上架时由正式分发描述文件覆盖为 production，工程里保持 development 即可）；
  - `com.apple.developer.icloud-container-identifiers` = `[iCloud.site.didichou.liqian]`；
  - `com.apple.developer.icloud-services` = `[CloudKit]`。
- 只用 CloudKit 数据库，不用 iCloud Documents，因此没有加 ubiquity 容器相关 entitlement。
- InfoPlist 加 `UIBackgroundModes: [remote-notification]`（镜像变更的静默推送唤醒）。

**仓库外前置条件（代码给不了，父级/上架前必须办）**：
1. 开发者后台为 App ID `site.didichou.liqian` 启用 iCloud 能力并关联容器
   `iCloud.site.didichou.liqian`（或用 Xcode Capabilities 自动创建）；
2. 首次真机以 Development 环境运行会自动生成 CloudKit schema（记录类型
   Ledger/GiftRecord/ReminderDay）；**上架前须在 CloudKit Console 将 schema
   部署到 Production 环境**，否则正式版同步不工作；
3. 侧载（SideStore 等）重签通常会剥掉 iCloud entitlement 并把 aps 换成重签方
   的配置——那种安装下本功能按设计走回退路径（§4），属预期行为，不是 bug。

## 2. 容器与存储位置（数据连续性）

- 旧实现：`.modelContainer(for: [Ledger, GiftRecord, ReminderDay])`（默认配置）。
- 新实现：显式 `ModelConfiguration(schema:, cloudKitDatabase:)`，除 cloudKitDatabase
  外其余参数（name、groupContainer=.automatic、默认存储位置）与旧默认配置完全一致
  ——**同一个存储文件原地沿用**，存量用户升级不搬家、不丢数据；CloudKit 首次启用时
  由系统镜像把本地存量记录上传（这是苹果官方的存量库接入路径）。
- 小组件不读 SwiftData（走 App Group UserDefaults 速览），本次未动、不受影响。

## 3. 模型 CloudKit 兼容性审计（Models.swift）

CloudKit 镜像的硬要求：① 不支持 `@Attribute(.unique)` 唯一约束；
② 每个存储属性必须可选、或带声明默认值；③ 关系必须可选（本仓无关系，见下）；
④ 计算属性不存储、不受影响。逐模型结论：

### Ledger（9 个存储属性）
| 属性 | 原状 | 结论/改动 |
|---|---|---|
| id UUID | `@Attribute(.unique)` | **去 .unique**。唯一性仍由 UUID 生成保证，本地行为不变；去约束属轻量迁移 |
| title / type / date / note String | 非可选、无声明默认值 | 补 `= ""`（init 仍显式赋值，默认值仅作 CloudKit schema 兜底） |
| hostName / scribe / verifier / location String? | 可选 | ✅ 本就兼容，不动 |
| isBai | 计算属性 | ✅ 不存储，无影响 |

### GiftRecord（11 个存储属性）
| 属性 | 原状 | 结论/改动 |
|---|---|---|
| id UUID | `@Attribute(.unique)` | 同上，去 .unique |
| ledgerID UUID | 非可选、无默认值 | 补 `= UUID()`（init 必传真实值，兜底仅形式） |
| person / direction / date / note String | 同上 | 补 `= ""` |
| relation / method / status String | 同上 | 补与 init 默认一致的值：`"朋友"` / `"现金"` / `已送出` |
| amountCents Int | 同上 | 补 `= 0` |
| returned Bool | 同上 | 补 `= false` |
| isPendingSend | 计算属性 | ✅ 无影响 |

### ReminderDay（10 个存储属性）
| 属性 | 原状 | 结论/改动 |
|---|---|---|
| id UUID | `@Attribute(.unique)` | 同上，去 .unique |
| person / relation / note String | 非可选、无默认值 | 补 `= ""` |
| kind / calendarKind String | 同上 | 补与 init 默认一致：`生日` / `公历` |
| month / day Int | 同上 | 补 `= 1` |
| leadDays Int | 同上 | 补 `= 3`（同 init 默认） |
| enabled Bool | 同上 | 补 `= true`（同 init 默认） |
| value | 计算属性 | ✅ 无影响 |

### 共通结论
- 模型间**无 @Relationship**（靠 ledgerID 等 UUID 外键关联），天然满足
  CloudKit「关系全可选」要求，无需改；
- 全仓 grep 确认除上述三处 `.unique` 外无 `#Index`/`#Unique`/`.transient`
  等 CloudKit 不兼容修饰（`@Attribute` 残留命中仅 Models.swift 审计注释一处）；
- 本轮改动均为「放宽约束＋补默认值」，属 SwiftData 轻量迁移范畴，
  本地模式打开老库行为不变；备份 JSON 的编解码不经过模型默认值，不受影响。

## 4. 降级设计（CloudSync.swift）——绝不闪退、绝不丢数据

- **启动一次性决策**（`CloudSyncManager.init`，存储模式启动后不变）：
  1. 开关关（UserDefaults `icloudSyncEnabled`，默认开）→ 本地配置；
  2. 开关开 → 试 `ModelContainer(cloudKitDatabase: .private(容器ID))`，
     `do/catch` 抛错 → 回退本地配置（同一存储文件，数据原地保留）；
  3. 本地文件配置再失败 → 内存存储兜底（App 至少能打开，状态明示数据异常）。
- **账号探测只影响展示**：`CKContainer(identifier:).accountStatus()` 异步探测
  （启动、回前台、CKAccountChanged、打开「我的」页时各刷一次）。未登录/受限时
  本地读写照常；CloudKit 镜像会在账号可用后自动补同步，不需要 App 干预。
- **同步状态来源**：`NSPersistentCloudKitContainer.eventChangedNotification`
  的 import/export 事件 → 同步中/已同步；单次事件失败多为网络抖动、镜像自动
  重试，不据此翻成「不可用」。
- **侧载预期路径**：entitlement 被剥 → CloudKit 容器创建抛错回退本地
  （或账号探测报错）→ 状态 `.unavailable`，文案「当前安装方式不支持
  iCloud 同步，数据保存在本机」，并保留导出备份这条手动线。
- **开关语义**：Toggle 写 UserDefaults，**下次启动才切换存储模式**
  （运行中重建容器会牵动全 App 的 @Query，不做）；改动待生效时副标题明示
  「已开启/已关闭，下次打开 App 时开始/停止同步」。

## 5. UI（MeView「数据」组）

- 首行 `iCloud 同步` Toggle，副标题随状态变化（人话）：
  同步中「正在同步到你的 iCloud…」/ 已同步「已开启，换手机或重装后数据
  自动回来」/ 未登录「未登录 iCloud，先存在这台手机上」/ 受限「iCloud 账号
  受限，暂时无法同步」/ 不可用「当前安装方式不支持 iCloud 同步，数据保存在
  本机」/ 已关闭「已关闭，数据只存在这台手机上」/ 待生效见 §4。
- 未登录时多一行「打开系统设置」（跳系统设置，文案说明在顶部登录 iCloud）。
- 组 footer 说明 iCloud 线与导出备份线互不影响；「关于」页数据说明文案已
  按双模式更正（旧文案称「不联网、不上传」，开启同步后不属实）。

## 6. 不受影响的既有链路

- JSON 备份/恢复（Backup.swift、MeView 导出/导入）：未动，与 iCloud 并行可用；
- CSV 导出、最近删除（TrashStore 快照式）、提醒调度（ReminderScheduler）：
  都走同一个 modelContainer，未动；
- 礼谱 PDF、AI、OCR：不依赖存储模式，未动。

## 7. 真机/CI 待验（本机无工具链，未验证）

1. CI 编译（Tuist 生成工程后 xcodebuild）：重点看 CloudSync.swift 的
   CloudKit 事件类型与 `CloudKitDatabase.private` 引用、MeView 的
   `$cloudSync.syncEnabled` 绑定；
2. 正式签名包：登录 iCloud 的设备上杀 App 重开，数据在；卸载重装后数据
   自动回来；第二台设备同账号能看到同一批数据；
3. 未登录 iCloud 冷启动：不崩、状态行显示「未登录」，登录后回前台自动转「已开启」；
4. SideStore 重签包冷启动：不崩、状态行显示「当前安装方式不支持」，本地记账正常；
5. 升级路径：装 v3.1（本地版）记几笔 → 覆盖装本版 → 数据在且被镜像上传；
6. 开关关闭后冷启动：本地模式记账正常，状态行显示「已关闭」。
