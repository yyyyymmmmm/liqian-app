# 礼记 v5.0.0（50）交付说明 · 尖刀定版

分支 `feat/v5-jiandao`（基线 `feat/v471-charts-fix` 顶端 655a343）。
定版依据：整产品竞品审计（主尖刀＝「把你家的礼簿，做成一本能传下去的
礼谱」）、2026 前沿设计审计（融合句「纸墨为体，玻璃为用」）、
docs/V471-NOTES.md、docs/DESIGN.md。
砍单纪律已守：不新增通用图表功能、不做平台表面扩张（无 Spotlight/
控制中心控件）、家族协作不深化、AI 礼官不扩。

四笔提交对应四块：0a0cc52 设计一期 / 8233044 买断闭环 /
703f813 成书做实 / f60712a 首开引导。

---

## ⚠️ LIQIAN_OWNER_BUILD（侧载机主旗，上架前必读）

CI 侧载构建在 Build 步注入
`SWIFT_ACTIVE_COMPILATION_CONDITIONS=LIQIAN_OWNER_BUILD`。
此旗开启时 `EntitlementCenter.isPro` 恒真——CI 产物是机主自用侧载包，
机主自己的纪念版礼谱/家族汇册/印刷版导出不能被自己的付费墙拦住
（婚礼当天要用）。付费墙在此构建下显示「已开通」，并有一行小字
注明机主构建（该文案由 `#if LIQIAN_OWNER_BUILD` 包裹，商店构建
不编译进去）。

**上架前移除步骤（缺一不可）：**
1. `.github/workflows/ios-native.yml` 的 Build 步去掉
   `SWIFT_ACTIVE_COMPILATION_CONDITIONS=LIQIAN_OWNER_BUILD` 一行
   （App Store 构建走独立流水线时同理：任何商店构建都不得带此旗）；
2. 全仓 grep `LIQIAN_OWNER_BUILD` 复核只剩 StoreKitManager.swift 与
   PaywallView.swift 的条件编译（它们在无旗时自动走商店口径，无需删）；
3. 用不带旗的构建装真机验证：付费墙显示价格（Product.displayPrice）、
   四个门控面未购时全部拦截到付费墙，再走沙盒购买验开通。

## 一、设计一期：令牌层＋外壳

- 新文件 `Sources/LiqianDesign/DesignTokens.swift`：
  - **Mat 三档**：clear / regular / tinted；`liqianGlassButton(_:)` 与
    `liqianGlassSurface(_:in:)` 两入口。染色只走五主题强调令牌
    （tinted 按钮走 Palette.primary、tinted 表面走 primaryTint），
    **无一处写死朱砂 hex**。
  - **Elevation 两档**：LiqianElevation.card（0.06/12/4）/ .floating
    （0.18/14/6）转正。FAB 旧自绘投影随玻璃化移除；现存 UI 阴影只剩
    两处登记例外：落印浮层阴影（落印动效本体）、图表范围指示器的
    3pt 微投影（低于卡档下限，套档会糊指示器——审计后保留并在此留账）。
  - **圆角同心机制**：LiqianRadius.concentric（容器圆角−内边距）；
    封面小签旧手算 20−16=4 已改走推导。
  - **Motion 四档**：press（snappy 0.22）/ liquidSpring
    （interactiveSpring 0.34/0.72）/ pageCrossfade（easeInOut 0.25）/
    sealIn（bouncy 0.45，落印登记值不变）；ScaleOnPress、落印、图表
    范围指示器的散落曲线已收敛到令牌，`MotionTokens.resolved` 统一
    Reduce Motion 降级口径。
- 外壳采用面：
  - FAB（AddFloatingButton）改玻璃主按钮：glassProminent＋主题染色＋
    `.buttonBorderShape(.circle)`，56pt 不变；系统玻璃自带按压形变，
    取代旧 ScaleOnPress＋自绘投影。
  - 标签栏 `.tabBarMinimizeBehavior(.onScrollDown)` 下滑最小化；
    `.scrollEdgeEffectStyle(.soft, for: .top)` 顶部柔边。
  - Tab 图标改 label 闭包：选中 .bounce 一次＋线面形变（往来
    person.2↔.fill、我的 person.crop.circle↔.fill）。
  - safeAreaBar 两处：人物详情底部行动条、礼谱导出分享条（后者分享钮
    同步改玻璃主按钮、撤 ultraThinMaterial 底板——二选一取玻璃）。
    汇册页分享条同口径新建。顶部紧急存储红条仍是 safeAreaInset
    （属警示条、非行动条，不在迁移面）。
  - 符号动效其余枚举点：双录音面麦克风录制中 .pulse；备礼「已送出」
    勾选 checkmark.circle→.fill（PeopleView 两处滑动动作）；落印沿用
    sealIn。枚举点 ⑨「同步 ✓」未新增符号：同步状态现为 MeView 文字
    口径、无独立符号位，造新符号面超出本期范围，留账二期评估。
- 内容层零玻璃自查：卡/列表/图表/表单无新增 glass/glassEffect 调用；
  玻璃只出现在 FAB、行动条、引导页继续钮（功能层）。
- **DESIGN.md 附录已换 v5 定版稿**：撤销两条错令并留痕注明理由——
  ①手画 1px 高光模拟镜面（仿玻璃塑料感、与去 AI 味纪律冲突）；
  ②主 Tab 衬线大字标题（与衬线白名单六处冲突）。附录同步写入
  Mat/Elevation/同心/Motion/符号枚举/不改清单 10 条。
- 不改清单 10 条逐条守：浅色默认（主题系统未动）/单强调（玻璃染色
  只走主题令牌）/金不入 UI（未引用 Palette.gold）/衬线白名单六处
  （新页只用封面小签与印章两个既有 moment，未新增衬线面）/礼谱形制
  （GiftBookPDF 未动）/金额墨色/白事克制（成书页对白事簿同样克制
  配色）/落印签名动效（值不变、仅收敛令牌）/对比地板/双 Reduce
  降级（Motion 走 resolved、玻璃由系统回退）。
- 二期未做（审计分期，不在本期）：次按钮 .bordered→.glass 逐屏迁移、
  ToolbarSpacer 逐页适配、图标 Icon Composer 分层制式核实。

## 二、买断闭环（StoreKit 2 真代码）

- 产品 id：`site.didichou.liqian.pro`（LiqianConstants.proProductID）。
  价格在 App Store Connect 侧维护；代码零价格文案，付费墙读
  `Product.displayPrice`，读不到就不显示价格后缀。
- `StoreKitManager`（App 层）：Product.products 查询、purchase
  （.verified 才 finish＋刷新；取消静默；pending 明示待确认）、
  Transaction.updates 监听、AppStore.sync 恢复购买、
  currentEntitlements 刷新（只收 .verified 且 revocationDate 为空）。
- 权益单点：`EntitlementCenter`（LiqianApp 注入 environmentObject）。
  判定纯函数在 Core `ProEntitlement.isPro(verifiedProductIDs:ownerBuild:)`
  ——已单测（机主旗优先/产品 id 精确匹配/四门控面同口径）。
  各门控面只问 `entitlements.canUse(_:)`。
- 门控面（只此四处）：MeView「导出 CSV」（整行改走付费墙，CSV 文件
  生成不拦截、分享动作才门控）、HandoverView 纪念版礼谱（生成钮
  先门控、未购直达付费墙）、家族汇册（导出页入口门控）、印刷版礼谱
  （同上）。**基础礼谱 PDF 与全量 JSON 备份（机器可读、能带走）
  保持免费**，付费墙页脚明示此口径。
- PaywallView：权益清单只写已实现四项＋一行「装订成书即将开放」
  （clock 图标区分未上线）；购买/恢复双按钮同规格同级
  （.borderedProminent 并列）；购买中/恢复中/失败/待确认/已购
  状态齐全；购买或恢复成功自动离开；MeView 新增「礼记 Pro」组
  常驻入口（状态文案随权益）。
- 前置欠账（上架时才发生，本期无法验）：App Store Connect 建产品、
  公司主体邓白氏编码开发者账号、沙盒购买全链路——见真机待验清单。

## 三、成书做实

- **印刷版礼谱**（`GiftBookPrintPDF`，新文件；屏幕版 GiftBookPDF
  一字未动）：以已生成预览的同一份屏幕版 PDF 为谱面来源（谱序与
  预览一致）——①第 1 页封面展开图：封面＋书脊＋封底一页、含 3mm
  出血、**右开本排版（左封面/右封底）**、书脊深档底＋竖排簿名（书脊
  <12pt 时不塞字）；②内页逐页套出血页盒，内容以 4 倍分辨率栅格化
  嵌回，出血环同纸色延展；③末页「印刷参数说明」：右开本书面确认、
  3mm 出血勿二次裁切、RGB 打样认色、书脊复算、锁线精装与纸张
  建议（米白胶版/轻型纸 80–100g）、页序说明。书脊宽＝Core
  `PrintBookSpec.spineWidthMM`（页数×0.05＋4、下限 6mm，已单测），
  导出页以 Stepper 做成可见参数（4–40mm、0.5 步进），生成预览后
  按真实页数自动估算、改完重新生成生效。
- **家族汇册**（`FamilyAlbumPDF`＋`FamilyAlbumView`）：导出页入口
  →多选礼簿（示例簿不入候选）→汇册 PDF：卷首总目（章号＋簿名＋
  事由年份＋笔数人数，16 行/页分页）→按簿分章（章题页：竖排簿名＋
  干支日期列＋印＋章脚注；正文＝GiftBookPDF 屏幕版管线＋内置模板
  谱序，保证整册确定性、不调 AI）→卷末跨簿人物总索引（姓名→出现
  的簿与笔数，Core `FamilyAlbum.personIndex` 已单测：跨簿聚合、
  按簿日期升序、空白名剔除、总笔数降序＋同名次姓名升序）。
- **成书入口**（导出页「成书」组第三行 → `BookBindingView`）：
  尖刀句＋工艺/价格带/周期口径（299–399 元、约 10 天，均注明引
  POD 调研的预期口径、终价以印厂书面报价确认为准）；意向登记＝
  存本机 UserDefaults 留痕＋打开预填 mailto 到
  inkroot001@gmail.com（主题/正文含簿名、事由、笔数与联系方式
  留空行）；文案明示首批人工履约内测、不在 App 内下单收款、
  不点发送不算登记成功。**没有任何伪造的在线下单元素。**

## 四、首开讲尖刀

- `OnboardingView`（单份实现）：TabView 三页＋右上「跳过」（前两页；
  第三页有「先不建」出口），玻璃「继续」钮（Mat.tinted），纸墨底。
  ①尖刀页：大标题「把你家的礼簿，做成一本能传下去的礼谱」＋礼谱
  意象（封面小签竖排「婚禮」＋「禮譜」题字＋SealStampView 印章，
  全是既有白名单 moment，不新造插画）；②信任页：无账号/自有
  iCloud/备份可带走三行＋免费口径一句；③起簿页：婚礼（婚礼）/
  生日（寿宴）/白事（白事，素蓝克制）/通用（其他）四模板，选完
  以今日日期建簿、insert＋save 后直接关闭进首页；不建则关闭进
  现有空态。
- 呈现（ContentView）：`UserDefaults` 键 `liqian.onboarding.v5.done`
  未置位才呈现（fullScreenCover）；完成/跳过即置位；隐私锁开启且
  未解锁时绑定恒 false（不盖锁屏），解锁后自动呈现；示例数据路径
  不受影响（引导可跳过、示例生成入口照旧）。
- **重看引导（追加定版）**：「我的 → 关于」组新增「重看引导」行，
  点击以同一 fullScreenCover 呈现同一 OnboardingView（可跳过、
  可完成、第三页照样能建簿），关闭不改一次性标记。覆盖安装
  （数据与标记保留）后这是重看引导的唯一路径。

## UI 层自审代偿说明（无 UI 单测的部分）

StoreKit 权益判定与汇册聚合的纯逻辑已进 Core 并有单测；UI 层
（Paywall/成书/引导/外壳）按逐文件自审交付：全仓 grep 复核玻璃
只落功能层、门控面只四处、无写死朱砂 hex 新增（PDF 印刷色板除外，
那是 GiftBookPDF 同源的留存物色值）、价格文案零出现。真机表现
以下方待验清单为准，本 NOTES 不宣称已验。

## 真机待验清单（装机后逐项过，结果回填本节）

1. 侧载包付费墙：MeView「礼记 Pro」行显示「已开通」（机主旗放行）
   ＋机主构建小字行可见；四个门控面（CSV 行无 Pro 角标、纪念版
   直接生成、汇册可进、印刷版可导）全部放行。
2. 印刷版 PDF：生成一份真实礼谱的印刷版——封面展开图页序与方向
   （左封面/右封底）、书脊字、内页出血边、末页参数页文字无溢出；
   Stepper 改书脊宽后重新生成，展开图宽度随之变化。
3. 家族汇册：选 2 本以上真实礼簿生成——总目章号与年份序、章题页
   版面、跨簿索引与实际人名笔数对账抽查 3 人；白事簿入册时章题页
   素蓝口径。
4. 首开三页：清标记（或新装）后首开——三页滑动、跳过、第三页
   四模板各建一本回首页核对簿名/事由/日期；隐私锁开启时先解锁
   再出引导。
5. **重看引导**：「我的 → 关于 → 重看引导」点击即全屏出三页引导，
   跳过/完成均可正常关闭回「我的」，数据无变化。
6. 玻璃外壳观感：FAB 玻璃钮（圆形、染色随主题——切腾讯蓝/黄色
   主题看染色跟随）、下滑标签栏最小化、顶部柔边、人物页与导出页
   行动条 safeAreaBar 滚动穿行、Reduce Transparency 开启时回退。
7. 成书意向：登记按钮→本机留痕＋邮件预填（收件人/主题/正文完整），
   不点发送无任何后续动作。
8. 上架前专项（非本期）：去旗构建＋沙盒账号购买/恢复/退款全链路、
   App Store Connect 产品价显示、TestFlight 包付费墙价格读取。

## 验收记录（2026-11-08 实测）

- 分块中间验：块一提交 0a0cc52 单独派 CI run 42409644749 —— success。
- 全量 CI：run 42410256249（head f60712a）—— **success**：
  BUILD SUCCEEDED / TEST SUCCEEDED；日志含
  `LIQIAN_OWNER_BUILD=ON` 注入回显与
  `presign assertions passed (2 binaries)`。
- 单测：唯一用例计数 **158 个全过、0 失败**（v4.7.1 基线 150＋
  本版新增 8：EntitlementsTests 4＋FamilyAlbumTests 4）。
- 解包验（产物 liqian-native-unsigned.ipa，3,470,654 字节）：
  - App Info.plist = **5.0.0 / 50**，Widget appex = **5.0.0 / 50**；
  - PlugIns 内只有 LiqianWidget.appex，**无 LiqianShare.appex**；
  - 主 App 与 Widget 二进制均含预签 entitlements blob
    （application-groups＋group.site.didichou.liqian）；
  - 类名抽查全在：PaywallView / BookBindingView / OnboardingView /
    EntitlementCenter / StoreKitManager / FamilyAlbum；
    关键文案抽查全在（装订成书×5、印刷版礼谱×7、inkroot001@gmail.com×2、
    尖刀句、信任页标题、买断副标题等）；pro 产品 id 在 LiqianCore
    二进制内命中。（「重看引导」「导出 CSV」等 ≤15 字节短串是 Swift
    小字符串内联编码、二进制内不以连续字节出现，已以其所在行的
    长副标题命中作旁证。）
- 交付物：`~/workspace/your_files/liqian-v5/liqian-native-unsigned.ipa`
- 真机待验：见上方清单 8 项，**未宣称已验**（含首开三页、重看引导、
  印刷版出图、汇册版面、玻璃观感、侧载付费墙机主放行）。
