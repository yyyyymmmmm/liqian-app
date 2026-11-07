# 礼钱账本（liqian-app）

人情往来礼金管理 App：记下亲友在各类事上给了多少钱，方便日后回礼。

- 一件事一本礼簿（婚礼、满月、乔迁、生日、升学、白事…），收礼 / 随礼双向记账
- 按人查往来：他给我多少、我给他多少、差多少、还有哪些没回礼
- 数据只存手机本地（JSON 文件），不联网、不上传；可导出 CSV 备份

## 技术

Flutter 一套代码双端（Android / iOS）。iOS 未签名 IPA 由 GitHub Actions
（.github/workflows/ios-ipa.yml）在 macOS runner 上打包，产物在 Actions 的
Artifacts 里。未签名包需用 SideStore / AltStore 侧载安装。

需求文档（PRD）见交付记录：礼钱管理软件 PRD V1.1（BMAD 模板）。
