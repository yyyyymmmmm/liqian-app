# V582-NOTES 礼记 v5.8.2 热修（问账纯文本回复被呈现层吞掉）

版本：App/Widget 5.8.2/68（Project.swift 三处字面量：工程设置＋App plist＋Widget plist）
分支：feat/v582-typewriter-fix（基线 feat/v581-quick-pack 顶端）
根因与方案以 docs/V58-WEATHER-DIAG.md 为准，本文件只记施工对照与验收。

## 病灶回顾（一句）

回复数据完好、已原位落地并落盘，死在呈现：TypewriterMarkdownText
把文本的「存在」押在 `.task(id:)` 异步填充的 @State `full` 上，
body 是 `Group { if let full { Text } }`——task 被 settle 同轮的
滚动/布局反馈取消或迟迟未调度时，该行永远零高、无重试无兜底。
账内回答带卡片兜底照出，账外纯文本回答（cards == []）全损，
即真机「账内正常、问天气消失」的分野。

## 修复 1（根治）：TypewriterMarkdownText 去门控（AdvisorView.swift）

改前结构：

```swift
@State private var full: AttributedString?
@State private var revealed = 0
var body: some View {
    Group { if let full { Text(slice(full)) } }   // full==nil 即零高空行
    .task(id: markdown) {
        full = Self.render(markdown)              // 存在性由异步任务决定
        ...
        while ... {
            revealed = count ...
            if Task.isCancelled { return }        // 取消即弃，半途/全空定格
        }
    }
}
```

改后结构：

```swift
@State private var revealed = 0                   // 只剩化妆层状态
var body: some View {
    let full = Self.render(markdown)              // body 内同步计算
    return Text(slice(full))                      // Text 永远在场
        .task(id: markdown) {                     // task 只管揭示动画
            ...
            if Task.isCancelled {
                revealed = total                  // 取消即全显
                return
            }
        }
}
```

对照要点：

- 文字的存在与任何异步任务解耦：body 求值即有全文（短文本解析
  成本可忽略，随 body 重算）；`full` 的 @State 删除。
- 打字机手感不变：仍按渲染后 AttributedString 裁剪、每 16ms 推
  进 3 字、每 24 字回调 onReveal 钉底、Reduce Motion 整段直出、
  Markdown 完整语法解析与去标记兜底（render/stripped 逐字未动）。
- 取消语义翻转：旧实现取消＝定格半途（停在赋值前即全空）；新实现
  取消＝revealed 置 total 全显。task 迟迟未调度时 Text 亦在场，
  最坏只是没动画，不再是没文字。

## 修复 2（防御纵深）：settle 落地断言

- 纯函数落 LiqianCore：`AdvisorChatStore.ensuringNonEmpty(_:)`
  （与遗孤占位收敛 reconcilingOrphanedPending 同文件、同单点口径）。
  规则：kind 为 .answer 且 text 去空白为空且 cards 为空 →
  改落 `.note(AdvisorReplyConvergence.failureApologyText)`；
  其余 kind 与「有字或有卡」的 .answer 原样通过。
- 接线：`AdvisorSession.settle` 在 `messages[index].kind =` 前
  唯一一道过此断言，落盘与呈现同吃收敛后的 kind。
- 单测 +4（AdvisorDeliveryTests）：空 text 无卡→兜底 note（含纯
  空白变体）、有 text 无卡→原样、空 text 有卡→原样、其余 kind→原样。

## 修复 3（观感加固）：settle 原位落地补滚（AdvisorView.swift）

- 触发口径：新增 `.onChange(of: session.answerTrigger)`——
  answerTrigger 只在 settle 原位落地（及草稿确认回写）时 +1，
  是「原位替换完成」的精确信号；原有 `.onChange(of: messages.count)`
  继续管新增消息（提问/占位上屏）。两路滚动体一致：滚到最后一条、
  anchor .bottom，Reduce Motion 无动画、否则 withAnimation。
- 解决：原位替换不增条数时不再漏滚——「问完切走再回来/答完停在
  半屏」时第一眼落在对话底部，能直接看到答没答完。

## 不动清单（自查）

- 问账管线/提示词/收敛器裁决、AdvisorSession 持有与 45 秒时限
  机制：除 settle 写入点过断言外逐字未动。
- 卡片体系、语音链（AnalyzerFeeder.swift 相对基线零改动，
  git diff 核对）、其余页面未动。
- 工作区另有 v5.9 外观线的未提交改动（Palette/CustomTheme 等），
  非本片文件，未纳入本片提交。

## 验收（回填）

- CI：（待回填）
- 单测：（待回填，基线 255＋新增 4）
- 解包验：（待回填）

## 真机待验

- 连问多个账外问题（天气/常识）条条可见、纯文本回复不再消失；
- 打字机手感不退化（逐字呈现、Markdown 格式、滚动追随）；
- 账内问题出卡如常；杀 App 重进后历史里的纯文本回复都在。
