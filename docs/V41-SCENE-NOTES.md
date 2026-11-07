# V41 现场模式落实记录（feat/scene，未提交）

## 改动文件
- 新增 `Sources/LiqianApp/SceneModeView.swift`：现场模式全部（主页面＋播报器＋脱敏视图＋外接屏呈现器＋复核单）。
- 改 `Sources/LiqianApp/LedgerDetailView.swift`：详情「更多」菜单在「拍照识别礼单」后加「现场模式」（顺序注释已同步），`.fullScreenCover` 呈现；新增 `@State showSceneMode`。
- 未改数据模型、未改 Project.swift（Tuist sources 是 `Sources/LiqianApp/**` glob，新文件自动入工程）。

## 四件套落实

### 1. 连续登记
- 大字输入：姓名 26pt semibold、金额 ¥＋44pt bold 等宽数字（系统 decimalPad）；常用金额 chips（100/200/300/500/800/1000/2000）点选即填；方式/关系 chips 单选、本场内保持上次选择（现场成串同类居多，减少点按）。
- 保存走既有口径：姓名/金额校验（与 RecordFormView 同规则：去空白、金额 >0、四舍五入到分）＋ `isSaving` 防重入；`modelContext.insert(GiftRecord(...))` 既有保存通道，方向固定「收礼」、日期今天、status 默认已送出（收礼忽略）。
- 存后不退出：清姓名/金额、焦点自动回到姓名框续记；成功/失败走既有 sensoryFeedback 口径。
- 顶部实时汇总带：本场笔数＋总额（largeTitle 金额字体、numericText 过渡）＋上一笔姓名/方式。
- 本场 session＝本页落库的本地快照数组（SceneEntry 值类型），汇总/播报/复核只认它，不被其他入口同时记账污染（污染只会在对账环节显形，见 4）。
- 在场期间 `isIdleTimerDisabled`（收礼台不息屏），离开恢复；进页 350ms 后自动聚焦姓名。

### 2. 语音播报
- `SceneAnnouncer`（@MainActor ObservableObject，形态对齐仓内 SpeechTranscriber 先例）：AVSpeechSynthesizer，zh-CN 语音，略低于默认语速。
- 文案：红事「收到，〈姓名〉，礼金〈金额〉」；白事换「奠仪」。每笔落库后播；连记时 `stopSpeaking(.immediate)` 打断上一笔只播最新，不积压。
- **金额读法选阿拉伯读法**（任务书二选一）：如 1000 元由中文 TTS 读作「一千元」；Core 的金融大写 `MoneyText.chineseUppercase`（壹仟元整）是礼谱书面口径、播报拗口且慢，不用于语音。带角分依次读「X元Y角Z分」，不满 1 元省「0元」。读法组装在 `SceneAnnouncer.spokenAmount`，纯函数可单测（本轮未加测试文件，见待验）。
- 开关：页头「播报」Toggle（button 样式），`@AppStorage("sceneAnnounceEnabled")` 默认开、记住选择；离开本页停播。

### 3. 投屏脱敏
- `ExternalDisplayPresenter`：监听 UIScreen.didConnect/didDisconnect，连接时把 `MaskedDisplayView` 以 UIWindow 挂到外接屏（window.screen＝外接屏），每次新登记 `update` 换 rootView；进入本页时若已连接立即 attach 并回放最近一笔快照。页内状态行实时显示连接状态。
- **代码层脱敏保证**：`MaskedDisplayView` 入参只有 `latestName / registeredCount / isBai`——根本不接收金额，不存在遮罩失效或过滤遗漏的可能；副屏内容＝最近姓名（96pt 大字）＋「已登记」＋「本场累计 N 笔」。
- 无副屏时：状态行提供「脱敏预览」开关，主屏内以同一 MaskedDisplayView 渲染预览卡（所见即副屏所得）。

### 4. 事后复核
- 页头「结束」出复核单（sheet）：本场笔数/总额、按方式小计（LiqianConstants.methods 顺序、只列本场出现过的方式）、与礼簿对账三行（入场前已有／应有总数＝基线＋本场／礼簿现有＝实时 @Query 收礼数）。
- 对账一致显绿勾；有差额显差额笔数/金额＋人话说明（可能有人在本页外同时记账或记录被改动），**只报告不自动修正**。
- 复核单「导出礼谱」：关单后经 onDismiss 链直接拉起既有 LibuExportView（records＝本礼簿全部记录）；「完成」退出复核并关闭现场模式；「继续登记」只关复核单。

## 取舍与口径
- 方向固定收礼：现场模式定位是礼房**收礼台**；随礼不在现场发生，表单不给方向切换（与批量补录收礼口径一致）。
- 未做撤销上一笔：误记可在详情列表侧滑删除/编辑，复核单差额会显形；现场页保持单向前进、零多余按钮。
- 现场页字体走大字字面量（26/44/64/96）而非 Dynamic Type 令牌：收礼台是固定工况（举着看、隔桌看），与批量页大字模式的既有做法一致（bigMode 亦为字面量放大）。

## 自查
- 两改动文件括号配平（{}／()／[] 全零差）。
- grep 核对：Palette 引用（pageBG/ink/stone/primary/primaryFill/primaryTint/danger/hairline/baiPrimary/baiPrimaryFill）均在 LiqianDesign 有定义；MaskedDisplayView 定义与调用处均无 amount 字样入参。
- 本机无 Swift 工具链，未做真编译，需父级走 CI 验证。

## 真机待验
1. 外接屏（转接线/AirPlay 非镜像）连接时副屏窗口挂载与断开回收；镜像模式下系统行为以真机为准。
2. TTS 播报在礼房嘈杂环境的音量与打断手感；播报开关持久化。
3. 长时运行（数小时）内存与不息屏发热；连记百笔以上汇总/对账数字。
4. fullScreenCover 下 @Query 在新登记后的实时刷新（复核单「礼簿现有」一行）。
