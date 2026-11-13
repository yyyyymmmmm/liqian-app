# v5.14.2 紧急热修说明（存储模式锁定＋显式 URL＋落盘自检＋搁浅数据救援）

基线：feat/v5141-save-chain @ 71017bf（v5.14.1）。分支 feat/v5142-store-lock。
起因：用户 2026-11-13 21:08 实报——v5.14.1 装后仍现「记好过一会
重开全失」，且旧版就有、从无警示条；21:14 探针回收：当前启动为
本地文件模式（截图小字实证）、示例似在只是真实数据不行；21:16
「最近删除」为空；21:25 用户确认从未点过「从备份恢复」，硬删排除。
四线会诊（内部二轮＋Codex＋Claude，OpenCode 线未及回收）定因：
CloudSyncManager.init 每启重判存储模式（开关缺省开＋重签环境
entitlement 探针恒放行＋CloudKit 容器创建 try? 静默回退本地，
CloudSync.swift:93-168），两配置均未显式指定 store URL、无模式
锁定——用户数据疑写进一种配置的店面、后续启动读另一种而「消失」。
两配置是否不同物理文件属平台行为未证：本版的日志与救援按「可能
不同」设计，装机后由诊断行坐实。
诊断全文：~/workspace/liqian-review/persistence-sweep2.md、
persistence-diag-codex-line.md、persistence-diag-claude-line.md（仓库外）。

## 施工清单（与派工单逐项对账）

1. **模式锁定**（CloudSync.launch）：决策只在无锁（首启/升级）或
   用户显式改开关（开关状态与锁定依据矛盾＝显式改锁）时做，结果
   写 UserDefaults `storeModeLock`/`storeModeLockBasis` 落锁；后续
   启动直接用锁定模式。无 entitlement（探针判定）→本地锁定
   （basis=noEntitlement）；CloudKit 创建抛错→本地锁定
   （basis=cloudKitCreateFailed）；开关关→本地锁定（userChoiceOff）。
   锁定 CloudKit 而某次创建失败：只本次回退本地、锁不动、日志留痕、
   诊断行以模式翻转后缀显形，不许静默改锁。
2. **显式 store URL**：本地配置显式指定 Application Support 下
   `LiqianLocal.store`（CloudSyncManager.localStoreURL 单点定义）；
   CloudKit 配置保持平台形态不传 URL，其实际店面位置由诊断行与
   启动日志暴露（configurations.first?.url）。
3. **决策留痕**：makeCloudContainer 改 do/catch，错误原样交出并记
   os.Logger（category=store）；每次启动记一行 launch 日志（模式
   token/依据/store 路径/字节数/上次模式）；「我的 → 数据」页加
   诊断小字一行（diagnosticLine：模式＋文件名＋大小，与上次启动
   不同后缀「与上次启动不同」）。
4. **启动落盘自检**：新 Core 实体 StorageProbe（独立轻量实体，
   不进备份/任何列表/统计）；容器建好后写一条带随机 token 的探针
   →save→换新 context 回读核对→删除→save（先清历史残留）。
   探针失败或内存模式 → storageUnsafe：ContentView 顶部固定红条
   （Color.red，不随主题——旧版主题色蓝条是用户没认出警示的原因
   之一）、启动弹窗（「数据现在存不住，先导出备份并联系支持」＋
   去导出备份直达我的 Tab）、五个记账入口整页阻断
   （.storageBlockGuard()：记一笔/建簿/批量含 OCR 入口/现场/
   一句话记账；问账与宾客回执入账都经记一笔表单，同样被盖住）。
5. **搁浅数据救援**（StoreRescue＋Core StoreMergePlanner）：首启
   （UserDefaults `storeRescueV5142Done` 守门、幂等；内存模式不跑）
   依次尝试候选配置打开店面——CloudKit 默认配置、无选项默认配置
   （旧本地店面）、显式 URL 本地店面（文件不存在或与主店同 URL
   跳过；开后 URL 与主店相同跳过）。按 Core 纯函数计划（ID 去重＋
   挂靠过滤：记录/成员/签名/绑定/回执须挂靠主店已有或一并并入的
   礼簿，祝福须挂靠已有或一并并入的记录，孤儿不并入）复制礼簿＋
   记录＋成员/签名/祝福/场次绑定/宾客回执/重要日子进主店，源店
   只读不删；统一 save 一次，失败不置完成标志、下次启动重试。
   真找回才在 App 内弹回执「找回 N 本礼簿、M 笔记录，已并入
   本机」，没找到安静无打扰。
6. **iCloud 开关诚实化**：syncToggleLockedOff＝内存应急或本地
   回退落定时为真——MeView 开关强制呈关＋.disabled，小字文案
   保持实情；用户主动关的本地与 CloudKit 模式开关照常可拨
   （拨动＝显式改锁，下次启动重决）。
7. performImport 覆盖恢复维持现状，未动（Codex 线已核：需用户
   选文件＋破坏性确认）。

## 纪律对账
- 版本 5.14.2/83：Project.swift 六处字面量（工程设置 2＋App
  plist 2＋Widget plist 2），Share 扩展维持 4.6.0/46 基线不进包。
- 新文案简体＋zh-Hant 同步 12 条（阻断弹窗/回执/诊断模板/模式词等）。
- AnalyzerFeeder 零改动（diff 名单核对不在内）。
- v5.14.1 的 SaveFlow/日期/倒计时、扫码随礼、统计隔离、礼谱链路
  未触碰；SaveSupport 与六入口保存链原样。
- 新增单测：StoreMergePlannerTests 8 例（整本并入/同 ID 不重入/
  二次运行零新增/孤儿不并入/祝福随记录/子实体去重过滤/重要日子/
  空源店）＋StoreLockGuardTests 5 例（锁定与 URL 在位/创建错误
  不吞/自检与硬显形链/救援与开关与诊断行在位/五入口守卫全挂）。

## 验收状态（如实，2026-11-13 夜）
- CI run 43434300728（workflow_dispatch @ feat/v5142-store-lock，
  head aad7180）：监视过程中已亲见 **Build (no codesign) 步骤通过**
  （全部新代码编译成功），随后 Unit tests 步骤进行中时，监视端
  触发 GitHub API 限流（HTTP 403 rate limit，request ID
  855B:17FD3E:58FB882:11B17E45:6AF713EC，2026-11-13 13:43 UTC），
  按纪律停手未再请求——**attempt 级最终结论、单测实数（预期
  385＋13＝398、0 失败）、IPA 下载与解包验（5.14.2/83×2、无
  LiqianShare.appex、IPA 落 ~/workspace/your_files/liqian-v5.14.2/）
  三项待限流恢复后由主线补验，本文件届时追记**。
- 真机未验（如实声明）：救援能否真找回数据，取决于搁浅数据是否
  真实存在于另一店面——装机后请用户看两处即可判读：①「我的 →
  数据」诊断行（模式/文件名/大小，模式翻转有后缀）；②有没有
  「找回数据」回执弹窗。模式锁定后新记数据应稳定落在同一店面，
  杀 App 重开不丢为最低验收线。
