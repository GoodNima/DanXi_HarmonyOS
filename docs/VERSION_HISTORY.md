# DanXi HarmonyOS 版本政策与发布历史

当前公开应用为 **0.1.35.3 Alpha**，`versionCode=1000154`，`buildVersion=155`。本页记录公开应用发布与后续版本规则；个人开发交付流水不属于公开发布历史。

## 已公开发布

| 发布日期 | 版本 | 升级编号 | 构建号 | tag 与说明 |
| --- | --- | --- | --- | --- |
| 2026-10-19 | 0.1.35.3 Alpha | 1000154 | 155 | [v0.1.35.3-alpha](https://github.com/GoodNima/DanXi_HarmonyOS/releases/tag/v0.1.35.3-alpha)：旦挞命名、桌面卡片及校园/茶楼交互与排版更新 |
| 2026-10-14 | 0.1.33.30 Alpha | 1000124 | 125 | [v0.1.33.30-alpha](https://github.com/GoodNima/DanXi_HarmonyOS/releases/tag/v0.1.33.30-alpha)：首次公开鸿蒙源码与既有未签名 HAP，应用构建于 2026-10-13 |

功能、包哈希及验证边界见 [RELEASE_NOTES](RELEASE_NOTES.md)，小白调试工具与 HoKit 侧载步骤见 [INSTALLATION](INSTALLATION.md)。

2026-10-14 的仓库清理和安装文档维护没有生成新 HAP，不递增应用版本、升级编号或构建号。已有包、版本和哈希保持原值；本页不把仓库文档提交计为新应用发布。后续授权历史净化调整同名 Alpha tag 的来源编号，映射见当前 main 的 [历史净化记录](https://github.com/GoodNima/DanXi_HarmonyOS/blob/main/docs/HISTORY_CLEANUP.md)。

2026-10-19 公开发布汇总此前 30 次本地开发交付（0.1.33.31 至 0.1.35.3）的最终变化，复用第 175 次交付的版本及编号；从公开源码重新构建未签名分发包属于同版本重复构建，不额外递增。中间开发包不等同于 GitHub 公开 Release。系统字号跟随曾在 0.1.35.0 尝试，随后按要求在 0.1.35.1 撤回，当前保持默认字号。

## 四段式与 Alpha

应用采用 `A.B.C.D` 四段数字：主版本、次版本、特性版本、修订版本。华为 [四段式建议](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V3/package-structure-0000001333321033-V3) 来自 FA 配置文档；当前工程使用 Stage 模型，其实际字段以 SDK 26 校验与构建结果为准。以下递增分类是本项目约定，不是华为规定的发布次数算法。

- **A** 仅经项目所有者明确确认升级。首个正式版按 `1.0.0.0` 执行，同样需明确确认。
- **B** 表示明确建立的应用开发或发布主线，不按更新次数自动递增。当前为初始 `0.1` Alpha 主线；建立新主线时清零 C 与 D。
- **C** 在完整功能、完整流程或明显多模块更新时递增，并清零 D。
- **D** 在局部修复、外观微调或随新包交付的发布元数据维护时递增。
- 问答、只读检查、同轮续接、QA 包、重复构建及没有新包的仓库文档整理不重复计次；没有连续若干次小修自动提升版本段的规则。

当前下一次小修为 **0.1.35.4 Alpha**，下一次特性更新为 **0.1.36.0 Alpha**；明确建立下一条次版本主线时为 **0.2.0.0**。

`AppScope/app.json5.versionName` 与 `Constant.APP_VERSION` 保持四段数字。应用和诊断使用 `APP_DISPLAY_VERSION` 显示数字版本加 `Alpha`，不增加 Alpha 序号，不因此修改 SDK releaseType。

## 版本字段与升级

| 字段 | 清单与常量 | 维护要求 |
| --- | --- | --- |
| 数字版本 | versionName / APP_VERSION | 四段数字一致 |
| 显示版本 | APP_DISPLAY_VERSION | 数字版本加 Alpha 阶段 |
| 系统升级编号 | versionCode / APP_VERSION_CODE | 新可安装交付高于上一交付及已安装版本 |
| 构建号 | buildVersion / APP_BUILD_VERSION | 同步清单与常量，新可安装交付不回退 |

华为的 [Stage 应用配置](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V2/application-component-configuration-stage-0000001478340869-V2) 与 [构建版本配置](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-hmos-hvigor-build-profile-app) 分别说明相关字段。展示版本变化不能代替系统升级编号；回退源码后重新交付仍需递增升级编号与构建号。

维护者在新包交付前集中分类与更新字段，防止多人 PR 争用版本。完成构建后核对包内元信息，再检查同签名覆盖升级及所需的数据保留；不同证书和卸载重装另行说明。

## 发布记录维护

每次公开新包增加一行真实发布记录，包含日期、版本、升级编号、构建号、固定 tag 和用户可见变化，并在发布说明记录资产哈希、签名类别、实际验证及未验证项。

正常发布后 tag、历史包文件名和包内版本保持不变。2026-10-14 经项目所有者授权净化历史，Alpha tag 保留名称但调整至同版本净化源码；保留新旧编号映射，不改动安装包和包内版本，也不把历史开发编号重算为公开版本。仅更正文档时保留原应用发布记录；需要改变应用行为时按新交付处理。完整发布流程见 [维护手册](MAINTAINING.md#release-发布流程)。
