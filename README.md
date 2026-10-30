<div align="center">
  <img src="docs/images/app-icon.svg" width="100" alt="旦挞应用图标" />
  <h1>旦挞 · HarmonyOS</h1>
  <p>面向复旦大学学生的校园服务应用，使用 ArkTS / ArkUI 适配 HarmonyOS。</p>
  <p>
    <a href="https://danxi.fduhole.com">官方网站</a> ·
    <a href="https://github.com/DanXi-Dev/DanXi">移植参考项目</a> ·
    <a href="https://github.com/GoodNima/DanXi_HarmonyOS/releases">下载 Alpha 内测包</a> ·
    <a href="docs/INSTALLATION.md">安装与签名</a> ·
    <a href="CONTRIBUTING.md">参与开发</a> ·
    <a href="docs/MAINTAINING.md">维护手册</a>
  </p>
</div>

<p align="center">
  <a href="docs/RELEASE_NOTES.md"><img src="https://img.shields.io/badge/阶段-Alpha-orange" alt="阶段" /></a>
  <a href="build-profile.json5"><img src="https://img.shields.io/badge/HarmonyOS-API%2026-blue" alt="HarmonyOS" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/上游许可-GPL--3.0-blue" alt="源码许可" /></a>
</p>

本仓库维护 **旦挞（DanTa）——基于 DanXi 的原生鸿蒙移植版本**。当前版本为 **0.1.43.6 Alpha**，升级编号 `1000186`，构建号 `187`。应用仍处于内部测试阶段；功能清单表示当前源码已实现的范围，实际服务可用性取决于账号权限、校园网络及服务端状态。

## 功能

| 模块 | 当前实现 |
| --- | --- |
| 校园 | 可编辑的校园服务卡片，校区切换、搜索、刷新与缓存；校园卡、入校权限、食堂、空教室、图书馆、校车、宿舍电费、体育与场馆预约等入口 |
| 学业与课表 | 教务通知、考试与成绩、GPA、历史学期课程、课表与手动课程；系统日历导出 |
| 茶楼 | 分区与排序、帖子列表、楼层及引用、发帖与回复、投票、收藏、图片浏览、富文本及 AI 总结状态展示 |
| 课评 | 独立课程评价页、同账号目录缓存、滚动摘要预加载与后台解析；课程搜索、评分摘要、课程详情及评价撰写入口 |
| 桌面卡片 | 课表、校车支持半高、方形、大卡片；一卡通、寝室电费支持半高和方形；读取应用已缓存的摘要，点击进入对应功能刷新 |
| 设置 | 账号与会话管理、安全凭据与加密会话恢复、原生额外身份验证、明暗主题、多语言、触觉与辅助功能、简洁报错及脱敏读取诊断 |

使用系统日历时按需申请日历权限；网络服务需要联网和相应账号授权。服务请求、会话接续与 UI 状态由原生 ArkTS 工程维护，富文本渲染资源随应用离线打包。

桌面卡片复用主应用已读取的数据，不在桌面独立登录或请求校园服务。账号、校区变化时清除旧私人摘要，过期信息提示更新。

本版相对上一公开版本 0.1.35.3 的完整更新见 [版本说明](docs/RELEASE_NOTES.md)。应用名称已更改，应用标识仍为 `com.danxi.ohmo`。

## 下载与安装

前往本仓库的 [Releases](https://github.com/GoodNima/DanXi_HarmonyOS/releases)，下载 `DanTa-HarmonyOS-…-unsigned.hap`。`SHA256SUMS.txt` 是可选的下载校验文件，安装不依赖它。Alpha 版本发布为 GitHub **Pre-release**，请使用完整发布列表查找。

推荐使用 [小白调试助手](https://github.com/likuai2010/auto-installer/releases) 或 [HoKit](https://github.com/yabi-zzh/HoKit/releases) 侧载。**当前公开资产是未签名开发 HAP**：小白可按自动签名/调试流程签名安装；HoKit 先使用自己的华为开发者账号、证书和设备授权 Profile 重签名，再安装输出的 HAP。无需先编译源码，但不能直接安装 unsigned 文件。

具体下载、USB/无线连接、签名、安装、升级及故障排查见 [安装文档](docs/INSTALLATION.md)。当前尚未在上述两种工具上完成本版真实手机安装验证。维护者的设备专用签名材料不公开，应用尚未在应用市场发布。

当前工程的目标与最低兼容 SDK 均为 **26.0.0 / API 26**，模块声明的设备类型为 **phone**。设备系统必须支持该 API；不承诺低版本系统、平板、手表或其他设备适配。详细步骤、升级数据保留条件和常见签名问题见 [安装文档](docs/INSTALLATION.md)。

## 界面示例

以下展示校园卡片、茶楼信息流和课评列表的常规使用界面，保留当前版本的原生底部导航。示例采集于 0.1.35.3，由当时的正式页面组件渲染，供界面风格参考；当前版本局部显示可能不同。课程、金额、帖子和评分采用演示数据，不含真实账号资料。

**浅色模式**

| 校园 | 茶楼 | 课评 |
| :---: | :---: | :---: |
| <img src="docs/images/campus.jpeg" width="230" alt="校园页，演示数据" /> | <img src="docs/images/teahouse.jpeg" width="230" alt="茶楼页，演示数据" /> | <img src="docs/images/reviews.jpeg" width="230" alt="课评页，演示数据" /> |


**深色模式**

| 校园 | 茶楼 | 课评 |
| :---: | :---: | :---: |
| <img src="docs/images/campus-dark.jpeg" width="230" alt="校园页，深色模式，演示数据" /> | <img src="docs/images/teahouse-dark.jpeg" width="230" alt="茶楼页，深色模式，演示数据" /> | <img src="docs/images/reviews-dark.jpeg" width="230" alt="课评页，深色模式，演示数据" /> |

## 开发

- 使用 **DevEco Studio 26.0.0.851** 或经验证兼容的版本，安装 HarmonyOS SDK 26。
- 从本仓库克隆 `main`，在 DevEco Studio 打开根工程并同步依赖。根目录使用 Stage 模型；构建插件为 `@ohos/hvigor-ohos-arkui-x-plugin` `4.26.8`，当前构建忽略跨平台目标。
- 公共 `build-profile.json5` 不包含签名材料。需要安装时，在自己的工作区通过 DevEco Studio 配置签名，避免提交本地配置。
- 修改后通过匹配 SDK 完成原生构建，并按影响范围验证设备上的实际流程。仓库仅保留应用工程及使用维护资料；本机测试脚本、夹具和开发助手配置不提交。

```text
AppScope/          应用标识、版本与全局资源
entry/src/main/    正式 ArkTS 源码、页面、服务和资源
hvigor/            构建工具配置
docs/              安装、版本、许可与多人维护文档
.github/           问题及 PR 模板
```

目录职责、环境配置、协作规则、模块维护及完整发布流程见 [维护手册](docs/MAINTAINING.md) 和 [贡献指南](CONTRIBUTING.md)。ArkTS/API 使用以项目 SDK 26 声明及华为官方开发文档为准。

## 验证与已知限制

- 本版从公开源码完成 SDK 26 构建，本轮本地回归 2097 项通过；开发交付另有原生合成滚动、TaskPool、三次冷启动与同签名覆盖升级记录。验证条件和未验证项见版本说明。
- 本次公开源码同步至 0.1.43.6，沿用已完成开发交付的版本与构建编号。历史整理记录仍见 [历史净化记录](docs/HISTORY_CLEANUP.md)。
- 真实账号下全部校园服务、不同手机与网络条件尚未完整验证。宿舍用电记录的真实账号超时原因仍需补充验证。
- Alpha 版本可能受上游服务变更影响。遇到问题请在 [本仓库提交 Issue](https://github.com/GoodNima/DanXi_HarmonyOS/issues/new/choose)，附上复现步骤、设备系统、展示版本、升级编号、构建号及脱敏诊断。

详见 [本版说明与验证边界](docs/RELEASE_NOTES.md)、[版本历史](docs/VERSION_HISTORY.md)。

## 来源、参考与许可

官方网站：[danxi.fduhole.com](https://danxi.fduhole.com)。

移植参考项目：[DanXi-Dev/DanXi](https://github.com/DanXi-Dev/DanXi)，并在功能流程和原项目贡献记录适配时参考 [DanXi-Dev/DanXi-swift](https://github.com/DanXi-Dev/DanXi-swift)。其他平台的下载与开发情况请参阅对应原项目；本仓库首页与 Release 专注鸿蒙版本。


经历史净化的 Flutter 来源快照保留在本仓库的 [upstream-flutter-baseline](https://github.com/GoodNima/DanXi_HarmonyOS/tree/upstream-flutter-baseline) 快照分支，提交关系、作者与日期继续保留；净化后的编号与版本对应见 [历史净化记录](docs/HISTORY_CLEANUP.md)。`main` 用于鸿蒙版维护；上游改动应经评审后按功能移植，维护流程见 [贡献指南](CONTRIBUTING.md)。

保留 DanXi 上游 [GPL-3.0 许可全文](LICENSE)、原作者与资源致谢。iOS 参考项目及第三方资源的各自许可说明随应用保留，见 [第三方材料说明](docs/THIRD_PARTY_NOTICES.md)。原项目标识、贡献者头像、字体、表情和渲染依赖分别注明来源；新增或替换资源须核对其许可。
