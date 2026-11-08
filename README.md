# 礼记（liqian-app）

人情往来礼金管理 App：记下亲友在红白事上给了多少钱，方便日后回礼。

- 一件事一本礼簿（婚礼、满月、乔迁、生日、升学、白事…），收礼 / 随礼双向记账，待回礼按净差额算
- 按人查往来、待回清单、人情总览与年度报告
- 礼谱 PDF 导出（竖排传统式样）、家族汇册、印刷版礼谱；CSV 导出与 JSON 备份
- AI 管家：语音记账、文件记账、问账（账内问题按账本精确作答，数字不编造）
- 小组件：待回礼、份子速记等六件套
- 数据存本机（SwiftData），可开 iCloud 同步；AI 为可选功能，自备 DeepSeek API Key

## 技术

- 原生 iOS：Swift 6 + SwiftUI + SwiftData，最低 iOS 26；Tuist 管理工程（Project.swift）
- CI：GitHub Actions（.github/workflows/ios-native.yml，macos-26 + Xcode 26）出未签名 IPA 与单测
- 安装：未签名 IPA 用万能签等工具签名安装；付费开发者账号 / TestFlight 规划中
- 会员：StoreKit 2 一次性买断（产品 id site.didichou.liqian.pro），基础记账、基础礼谱 PDF 与备份免费

当前版本 v5.11.2。各版本开发记录与审计文档见 docs/。

flutter-legacy/ 为早期 Flutter 版本的冻结存档，不再维护。
