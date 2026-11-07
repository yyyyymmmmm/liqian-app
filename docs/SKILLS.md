# 礼钱账本 · 专业技能栈（每个阶段用专门 skill，不手写凑合）

用户要求（2026-11-07）：需求、设计、评估都要用专业 skill 对口执行。本表是项目的
固定流程，任何一版迭代按此走，缺环要在交付说明里写明原因。

| 阶段 | Skill | 用途与产物 |
|---|---|---|
| 需求剖析 | BMAD-METHOD（bmad-prd 模板） | PRD V1.1（已交付，单一事实来源） |
| 产品评估 | PM 评审（对照 PRD 的 FR 逐项验收） | docs/PM-REVIEW-*.md，差距表+版本排期 |
| 视觉设计 | frontend-design | 题材锚点与令牌系统 → docs/DESIGN.md（现代礼簿） |
| 图标 | app-icon（2026 修正版质感：扁平+渐变+粗剪影） | icon-src/icon-1024.png，已入包 |
| 表单设计 | form-design（原则层） | 记账表单：只问必需、按登记顺序、校验含不完整输入 |
| UI/UX 设计情报 | ui-ux-pro-max（nextlevelbuilder，GitHub ★146k） | 192 产品色板/74 字体配对/119 UX 规则，配色与排版决策查它 |
| 设计评审词汇 | impeccable（pbakaus，GitHub ★105k） | 设计评审与细化口径，配合 ui-checker 审计 |
| 配色构建/对比度 | Refactoring UI 技能组 03/09（gnurio，GitHub） | 色阶构建法 + 对比度管理，配色复核见 DESIGN.md 附录二 |
| SwiftUI 视觉设计 | swiftui-design-skill（Wholiver，GitHub） | 反 AI 模板味 6 原则 + 5 维评审，docs/DESIGN.md 原生补充 |
| Liquid Glass | swiftui-liquid-glass（dpearson2699/swift-ios-skills，GitHub） | glassEffect/GlassEffectContainer/玻璃按钮/形变转场，只给功能控件 |
| 动画 | swiftui-animation（同上） | 弹簧、PhaseAnimator、数字滚动过渡、导航缩放、Reduce Motion |
| 交互手势 | swiftui-gestures（同上）+ 系统触觉 | sensoryFeedback（保存成功/删除警告/选择）、左滑、按压反馈 |
| 导航/模式/数据 | swiftui-navigation / swiftui-patterns / swiftdata（同上） | NavigationStack 口径、MVVM 模式、SwiftData 建模 |
| 工程化 | Tuist + fastlane + SwiftLint（大厂流程，非 skill） | Project.swift / Fastfile / .swiftlint.yml / CI |
| UI 评估 | ui-checker（15 维审计，适配 App 屏幕） | docs/UI-AUDIT-*.md，逐屏问题+改进，修完才交付 |
| 实测验收 | local_hands_on_review（实测口径） | 只报实际验证过的：CI 编译/单测/真机或模拟器结果 |

## ui-checker 15 维 → App 适配映射

视觉层级与排版 / 间距与布局（4-8 倍数） / 对齐 / 色彩与对比（白事克制另查） /
导航与寻路（Tab 语义、返回路径） / 组件可供性（触摸目标 ≥44pt） / 反馈状态
（保存、删除、导入都有可见反馈） / 模态行为（sheet 关闭与确认） / 适配
（iPhone 各尺寸、深色外观不破相） / 跨页一致性（卡片、字阶、签样式统一） /
空状态与错误状态 / 加载体验（本地应用以即时性为准） / 信息架构（人物页先给结论） /
微交互（系统原生动效为准，不自造） / 大视口（iPad 不强求，TARGETED_DEVICE_FAMILY=1）。

## 2026-11-07 追加：专业设计审校栈（用户点名「看看 GitHub、不要自己想象」后安装）

| Skill | 来源 | 用途 |
|---|---|---|
| hallmark | Nutlope/hallmark（★约 5 万） | 反 AI 味设计：令牌化一切颜色/字体、AI 默认毛病清单、audit 模式 |
| huashu-design | alchaincyf/huashu-design（★约 2.9 万） | 中文设计 skill：设计体检（critique）流程、风格库 |
| unslop | heydamir/unslop（★约 1.1 万） | 把「AI 生成感」界面改回设计过的样子：richness 只进 moment、chrome 保持安静 |
| claude-design-skills | Gustavosilveira23/claude-design-skills | ui-designer（8pt 网格/字阶/60-30-10）、design-system（令牌审计）、CLEAR 审校表（Copy 第一维） |

本地副本：~/workspace/custom-skills/local-{hallmark,huashu-design,unslop,claude-ui-designer,claude-design-system,claude-ux-designer}/。首战成果：docs/PRO-AUDIT.md（CLEAR 基线 2.4/5、术语表定版、52 条文案审校、整改 15 项已全量落码）。
