# v5.12.0 扫码随礼（App 端）施工与验收记录

版本：App/Widget 5.12.0/78 ｜ 分支：feat/v512-guest-gift（基线 feat/v5116-book-path 顶端 e1daf85）
口径来源：用户 2026-11-09 在礼记旁聊拍板「扫码随礼进 App 转正」——
每本礼簿生成绑定自身的宾客码、主家分享出去、宾客扫码自填、
数据自动同步回 App；回执先进礼簿「待确认」区、主家点确认才入账
（防假数据直写账本，用户在「直落礼簿/先进待确认」中选后者）。
云端契约：liqian-guest/API.md（https://sui.inkroot.cn，上线已验）。
支付仍属后期（平台分账方向），本版只通数据闭环，金额为宾客自报。

## 功能落点

### 数据模型（Sources/LiqianCore/GuestModels.swift，进 CloudSync Schema）
- `GuestEventBinding`：礼簿↔场次绑定——eventId/publicToken/guestUrl/
  场次名日期类型快照/closed/lastSince 增量游标（createdAt 原文）。
  一本礼簿至多一个当前绑定；换绑不删旧行以外的任何数据。
- `GuestReceipt`：回执镜像——serverId（场次内自增，与 eventId 组成
  去重键）、name、amountCents 可空、blessing、createdAtRaw 原文、
  status（pending/accepted/dismissed）、linkedRecordID（入账关联）、
  handledAt。CloudKit 兼容口径与全仓一致（无 unique、全属性默认值）。
- `hostSecret` 不进任何模型：按 eventId 存 Keychain
  （App 层 GuestKeychain，service=site.didichou.liqian.guest）。
  契约明示丢了不可恢复——同步时凭证缺失落明确状态行并给出路
  （重新生成宾客码），不静默吞。

### 配发键注入（ISSUE_KEY，仓库公开前提下的落点）
- 键只存 GitHub Actions Secret `LIQIAN_ISSUE_KEY`；工作流在 checkout
  后、生成工程前跑 `scripts/gen-guest-secrets.py`：键字节 XOR 掩码
  ＋base64 写出 `Sources/LiqianApp/GuestSecrets.swift`（已 .gitignore）。
  App 侧 `GuestKeyBox` 运行时解码；生成文件与 IPA 里都只有掩码字节，
  grep 不到明文（解包验收项）。掩码是防直读不是加密——这把键的定位
  是配发门槛，真安全靠服务端限流与两把随机令牌（契约 §5），已如实
  写进 GuestKeyBox 注释。
- 断言两道：生成后断言（文件在＋标记在；Secret 在场时不得占位；
  且键明文不得出现在工作区任何文件）＋预签步内复断言一道。
- 无键构建（fork/本地未跑生成脚本时文件缺席则需先跑脚本）生成占位：
  `GuestKeyBox.isAvailable=false`，宾客码页显示「暂未开通」，
  其余功能零影响。本地生成/解码往返已验（掩码解码与原值一致、
  生成文件无明文，施工机实测）。

### 宾客码页（GuestCodeView，礼簿详情新增 Section，在电子礼谱之下）
- 落点理由：与电子礼谱同为礼簿级「对外口」，按护城河入口要可见的
  既定口径独立成组放记录之上、不进「更多」菜单（菜单顺序是定版）。
- 无绑定：一句口径文案＋「生成宾客码」（type 由礼簿红白决定：
  白事簿→white，宾客页不出现金额框，服务端亦忽略金额）。
- 有绑定：二维码（CoreImage 现生成 guestUrl）、链接（可选中）、
  分享链接/分享二维码图、收集状态、同步状态行、立即同步、
  关闭收集（确认弹窗，讲清关后宾客只见「已结束」）、
  重新生成（确认弹窗：关旧建新、旧回执本地保留、旧码失效）。

### 同步（GuestSyncCenter，@MainActor ObservableObject）
- 时机：进礼簿详情、进宾客码/回执页、App 冷启动、回前台（未锁定时；
  解锁一刻补一次）。
- 游标：lastSince 存最后一条 createdAt 原文，回传时经
  GuestSyncPlanner.encodeSince 编码（+ → %2B，契约明示坑）。
  合并规划在 Core 纯函数（去重含批次内重复；整批重复也推进游标，
  防崩溃重拉死循环），单测钉死。
- 状态行（学小组件自检口径）：「已同步 HH:mm · 新到 N 条／没有新回执」
  「同步没成功：<人话原因>」「凭证缺失，没能同步（重新生成宾客码可恢复）」，
  401 归一为「凭证对不上，没能连上云端」，不抛英文原文、不假装成功。

### 待确认区（GuestReceiptsView，详情页「宾客回执」入口，带待确认 N 条提示）
- 待确认行：姓名/金额（SignedMoneyText 收礼向，有才显示）/祝福/时间。
  - 有金额：「入账」→ 现有 RecordFormView 新预填 init（礼簿固定、
    方向收礼、姓名/金额/备注预填，备注＝「宾客扫码随礼：<祝福原文>」，
    补充信息默认展开让来历可见）→ 保存成功回调置 accepted 并关联
    记录 id（回调按 pending 状态幂等，防「保存并继续」重复触发）。
  - 无金额：只有「已阅」（置 accepted、无关联记录）与「忽略」。
  - 「忽略」：置 dismissed，并 best-effort 同步删云端那条
    （契约有 DELETE 接口；绑定已换绑/凭证不在时只删本地——
    旧场次已关收集、留底在用户自有 D1，无害）。
- 已处理区：已入账/已阅/已忽略，灰字陈列。

## 红线自查
- 既有记账/待回/出谱/成书/问账/组件链零改动：本版对既有文件的改动
  只有 RecordFormView（加一个预填 init＋save 新建分支留引用回调，
  既有三 init 与保存语义未动）、LedgerDetailView（加入口 Section
  与进页 .task）、ContentView（加 modelContext 与三处同步钩子）、
  CloudSync（Schema 加两模型）、Project.swift（版本号）。
- 婚礼独立页服务 wish.inkroot.cn 未动（两套独立服务）。
- AnalyzerFeeder 零改动（diff 名单实查，验收段回填）。

## 真链路自测（脚本层，键从 secrets 文件读、只记状态不记键值）
（待回填）

## 验收（待回填）
- CI：
- 单测：
- 解包验：
- IPA：

## 如实声明：真机未验
待验（真机）：生成宾客码并出码、微信扫码打开宾客页填写提交、
回执自动同步落待确认区、入账后该宾客待回数字正确变化、
关闭收集后宾客页显示已结束、重新生成后旧码失效新码可用、
白事簿场次宾客页无金额框。App 真机与云端联调未做，
本版只做到脚本层真链路自测（见上）。
