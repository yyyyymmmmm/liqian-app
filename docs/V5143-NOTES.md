# v5.14.3 止血热修说明（救援门禁收口＋出启动关键路径）

## 为什么出这个版本

v5.14.2 装机必崩（用户真机实报「闪退」）。定因见
`~/workspace/liqian-review/v5142-crash-diag.md`（本仓外报告，要点如下）：

- StoreRescue 首启在 CloudSyncManager.init 尾部派发，第一个候选就是
  带 CloudKit 选项的默认配置，**无 entitlement 门禁直建容器**；
- 本仓 v4.0 注释已实锤：无对应 entitlement 强建 CloudKit 容器触发
  **不可捕获异常**（Swift do/catch 接不住），启动即崩；
- 救援完成标志只在跑完后才写——崩在第一候选＝标志永不置位＝
  **每次启动必崩的死循环**；
- 用户是万能签（别人证书）重签、无 iCloud entitlement，必中。
  主启动链本身有 hasCloudKitEntitlement() 门禁、安全，本版未动其判定。

## 本版改动（止血方案 1＋2 合并）

1. **门禁收口（唯一入口）**：`CloudSyncManager.makeCloudKitContainer`
   成为全仓唯一「建 CloudKit 容器」入口——入口内先过
   `hasCloudKitEntitlement()`，探针不过直接拒建（返回 entitled=false），
   绝不真去构造；创建错误原样交出不吞。主启动链原 makeCloudContainer
   收敛为它的薄封装，launch 判定逻辑一字未改。StoreRescue 的 CloudKit
   候选只许经此入口拿容器，且调用方先判 `rescueCloudKitAllowed`
   （探针不过、或本次锁定依据为 noEntitlement / cloudKitCreateFailed
   即关门）——门关着直接跳过 CloudKit 候选，只扫本地两候选
   （无选项默认配置、显式 URL 配置）。
   源码守卫单测钉死：递归扫 Sources，`cloudKitDatabase: .private`
   只许出现在 CloudSync.swift；StoreRescue 必须经入口且带 allowCloudKit。
2. **救援出启动关键路径**：触发点从 CloudSyncManager.init 尾部挪到
   ContentView 首帧后 `.task` 调 `cloudSync.runRescueIfNeeded()`；
   回执仍走 `rescueReceipt`（首帧后置位、真找回才报数，口径不变）。
3. **防死循环（尝试计数先行）**：开扫**之前**先把
   `storeRescueAttempts` 自增落盘；未完成且计数 ≥2 → 不再自动跑，
   诊断行追加「旧数据查找已暂停」显形（「我的 → 数据」存储诊断行）。
   跑完才写完成标志 `storeRescueV5142Done`（键名未改，语义沿用）。
   键兼容：装过 5.14.2 的用户只可能写过 done（崩在半途则未写），
   attempts 键缺失按 0 读、半写容忍。
4. **其余 v5.14.2 成果全部保留不动**：模式锁定、本地显式 store URL、
   决策留痕与诊断行、落盘自检（StorageProbe）与硬显形
   （固定红条＋五入口阻断）、iCloud 开关诚实化。
   performImport 未动；AnalyzerFeeder 零改动；SaveFlow/日期/倒计时/
   扫码随礼零回归（diff 文件面：CloudSync/StoreRescue/ContentView/
   StoreLockGuardTests/Project/zh-Hant，共 6 文件）。
5. 版本 5.14.3/84（Project.swift 六处字面量）；新文案
   「旧数据查找已暂停」简体＋zh-Hant 同步。

## 验收（已补实数）

- CI run 43442717338（workflow_dispatch，head c55c53b）：
  attempt 1 经 API 实查 `completed / success`
  （监视全程稀疏单发查询，中途两次遇 GitHub API 限流、拉长间隔后恢复）
- 单测：**Executed 400 tests, 0 failures**（398 基线＋本版新守卫 2 例）
- 解包验：App 与 Widget 的 Info.plist 均为 **5.14.3 / 84**；PlugIns
  只有 LiqianWidget.appex，**无 LiqianShare.appex**；
  IPA 4,515,935 字节，md5 `ea4b1ce61c9712787e7a529bd9e09c89`

## 真机验收口径

**第一验收线**：装过 5.14.2 必崩的用户，覆盖装本版后应能**正常打开**
App 并停留在首页——救援在首帧后安全跑（其环境下 CloudKit 候选被门禁
直接跳过）或按计数上限停跑，不再每启必崩、不再闪退。

其余判读（沿用 v5.14.2 口径）：
- 若本地候选店面里有搁浅数据，首帧后应弹「找回 N 本礼簿、M 笔记录，
  已并入本机」回执；无回执＝本地候选无数据或救援已停跑，看诊断行。
- 「我的 → 数据」诊断行应为本机模式＋LiqianLocal.store＋字节数；
  若带「旧数据查找已暂停」后缀，说明救援两次未完成已停自动跑。
- 模式锁定后新记数据：杀 App 重开不丢，为数据线最低验收线。
