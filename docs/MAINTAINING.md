# DanXi HarmonyOS 维护手册

本手册面向协作开发者与发布维护者。用户侧载入口见 [安装说明](INSTALLATION.md)，参与开发见 [CONTRIBUTING](../CONTRIBUTING.md)，版本约定见 [VERSION_HISTORY](VERSION_HISTORY.md)。

## 仓库范围与分支

`GoodNima/DanXi_HarmonyOS` 的 `main` 维护 Stage / ArkTS / ArkUI 鸿蒙工程。2026-10-14 仓库整理后，当前工作树只保留应用源码、运行资源、必要构建配置、使用与维护文档、许可材料和 Issue / PR 模板。个人开发配置、测试工程、历史任务档案及辅助脚本不纳入当前公开交付。

| 分支或引用 | 用途 |
| --- | --- |
| `main` | 当前鸿蒙工程与配套文档 |
| `upstream-flutter-baseline` | 移植前 Flutter 基线，供来源追溯 |
| `feat/*`、`fix/*`、`docs/*` | 并行开发与审阅，向 main 提交 PR |
| `vA.B.C.D-alpha` | 已公开 Alpha 包对应的来源提交，正常发布后不移动；授权历史净化例外见下文 |

Flutter 来源快照保存在 [upstream-flutter-baseline](https://github.com/GoodNima/DanXi_HarmonyOS/tree/upstream-flutter-baseline)。2026-10-20 对全部分支、标签及可达历史统一净化，保留作者、日期与提交关系，提交编号已改变；完整映射、版本来源和协作者迁移要求见 [历史净化记录](HISTORY_CLEANUP.md)。

不要用 GitHub **Sync fork** 更新原生 main，不直接合并 Flutter 的根构建文件和平台目录。需要新的比较快照时使用单独参考分支。推送前确认所有者和目标分支；本 fork 的提交不会自动修改上游项目。

## 工程目录与保留原则

```text
AppScope/                         应用标识、版本和全局资源
entry/
  src/main/ets/                   页面、组件、模型、服务与工具
  src/main/resources/             多语言、明暗资源、字体和离线渲染材料
  src/main/module.json5           能力、权限与目标设备
  build-profile.json5             模块构建配置
  hvigorfile.ts                   模块构建任务
  oh-package.json5                模块依赖
  obfuscation-rules.txt            release 配置引用的混淆规则
.arkui-x/arkui-x-config.json5      现有 ArkUI-X 构建配置
hvigor/、hvigorfile.ts             构建插件配置与根任务
build-profile.json5               产品、SDK 与构建模式
oh-package.json5、锁文件            HarmonyOS 依赖及锁定
.npmrc                            公开构建依赖仓库
code-linter.json5                 源码检查配置
docs/                             安装、发布、版本、维护及许可资料
.github/                          Issue / PR 模板
README.md、CONTRIBUTING.md          使用与协作入口
LICENSE                           上游许可全文
```

应用需要的图片、字体、表情、Web 富文本脚本与样式、数据资源和对应许可均属于工程内容，不能仅因它们不是 ArkTS 文件而删除。当前保留的 ArkUI-X 配置和插件是实际构建链的一部分；更换插件或移除该配置需作为独立工程变更验证。

安装包放在 GitHub Release。依赖缓存、构建输出、编辑器和开发助手个人配置、SDK 本机路径、签名、账号数据及原始设备日志不提交。公开说明只写可复现步骤与必要的脱敏摘要，私人材料由负责人在私有环境保存。

## 协作职责与交接

维护者负责范围协调、审阅、版本、合并和发布；贡献者负责实现、来源说明及验证；测试参与者记录设备与流程条件。每次 Release 指定负责人。

修改共享认证、网络、存储和通用组件前，先在 Issue 中说明影响模块和计划，约定接口与合并顺序。PR 至少交接问题及复现条件、变化后的行为、影响范围、来源提交、验证结果、未验证项和后续事项。

维护人变更时交接当前源码/tag、版本字段、未合并 PR、已知问题、构建步骤、验证设备和账号条件、发布资产与哈希、上游参考及签名责任。签名密钥和凭据通过团队批准的私有渠道交接，公开文档不记录密钥、口令或设备授权文件。

### 文件列表备注与提交说明

GitHub 文件列表的备注来自对应路径最近一次变更的提交标题。采用 `短前缀: 英文动作与结果`，按内容选用 `app:`、`docs:`、`history:` 或 `release:`，前缀不带括号模块名；源码、配置、资源和文档按实际修改范围概括。实例和审阅要求见 [贡献指南](../CONTRIBUTING.md)。

已推送提交的说明调整或历史净化会改变提交编号，必须保留映射及协作者迁移记录。2026-10-20 的统一净化同时更新了两个 Alpha 标签，安装包保持不变；详见 [追溯记录](HISTORY_CLEANUP.md)。

## 环境基线

| 项目 | 当前配置 |
| --- | --- |
| DevEco Studio | 26.0.0.851，或经验证兼容的版本 |
| 模型与语言 | Stage / ArkTS / ArkUI |
| targetSdkVersion / compatibleSdkVersion | 26.0.0 / API 26 |
| deviceTypes | phone |
| Hvigor modelVersion | 26.0.0 |
| 构建插件 | @ohos/hvigor-ohos-arkui-x-plugin 4.26.8 |
| 跨平台目标 | .arkui-x 中 ignoreCrossPlatform=true |

保留 ArkUI-X 插件不表示 Android / iOS 构建已验证。支持条件以本工程的实际配置和设备结果为准，不照搬参考项目的适配清单。

升级 IDE、SDK 或插件前，先建立可构建基线；升级后核对 API 声明、资源、权限、包元信息及设备流程。不要将开发者自己的绝对安装路径写入公开配置。

## 构建与签名

### DevEco 构建

1. 用 DevEco Studio 打开包含 AppScope 和根 build-profile 的仓库目录。
2. 安装匹配 SDK，配置本机开发环境并完成 OHPM 与构建依赖同步。
3. 选择产品 default、模块 entry，以及 debug 或 release 模式。
4. 使用 **Build Hap(s)** 构建，或在本机配置签名后连接设备运行。菜单文字以实际 IDE 版本为准。
5. 确认日志最终成功，检查 `entry/build/default/outputs/default/` 的实际输出，并区分 unsigned 与 signed 文件。

仓库没有自带 hvigorw 包装器，不把 `./hvigorw` 写成开箱即用入口。命令行构建应配置匹配的 SDK、Hvigor、JDK、Node 和依赖仓库，再以实际任务及输出验证。

### 依赖仓库

工程 `.npmrc` 使用公开 registry：常规依赖为华为云镜像，`@ohos` 为 `https://repo.harmonyos.com/npm/`，依据 [华为环境配置文档](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-environment-config)。插件 404 时先检查生效的 registry，不随意更换插件版本。

命令行环境需提供 JDK 与 DevEco Node 工具。可在当前进程用 `NPM_CONFIG_USERCONFIG` 指向工程 .npmrc，避免覆盖其他项目的用户配置。依赖变化后由 OHPM 更新锁文件，再检查干净工作区的同步与构建结果。

### 签名与侧载

公开 build-profile 不含密钥、证书、Profile、口令及私人签名路径。开发者通过 DevEco **Project Structure → Signing Configs** 配置自己设备适用的签名，本机改动不提交。

Release 当前为未签名 HAP。使用者通过小白调试工具或 HoKit 完成适用的签名与侧载，具体前提、设备连接、安装和排错见 [INSTALLATION](INSTALLATION.md)。侧载工具不能改变包所需的 SDK、设备类型及有效签名条件。

调试 Profile 可能限制设备范围。原测试签名包、证书、私钥及设备授权资料不公开；不能把它们复制进 Release 以求通用安装。

升级须保持应用身份和兼容签名身份，且升级编号满足系统要求。自行换证书可能无法覆盖已有安装；卸载重装会移除数据，不能记作数据保留升级。官方签名入口：[自动签名](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-signing-auto)、[手动签名](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-signing-manual)。

## 验证层次与证据

当前公开工作树不包含历史测试工程、辅助脚本或 Node 测试入口，也未提供原生 HAP 构建 CI。不要把已撤下的旧工作流结果说成当前提交的验证。

| 层次 | 记录内容 | 结果边界 |
| --- | --- | --- |
| 原生构建 | Git 提交、SDK、模式、任务和最终输出 | 证明编译与打包，不证明全部服务可用 |
| 界面与交互 | 设备/模拟器、系统、账号状态、明暗、导航与触控步骤 | 仅覆盖实际执行的页面和条件 |
| 真实账号流程 | 授权账号条件、网络、认证、读取、失败与接续步骤 | 不扩展到未执行账号和服务 |
| 正常升级 | 同签名覆盖安装、前后版本、保留数据项目 | 不代表换签名或卸载重装的数据保留 |
| 文档与公开材料 | 链接、版本、哈希、来源和脱敏检查 | 不代替应用运行验证 |

每个重要变更附可复核步骤，分别列出通过、失败和未验证。测试不要写入他人的真实数据；原始账号日志、校园记录及设备 ID 不作为公开证据。历史验证如需引用，必须注明对象、日期与范围，不声称是本轮复测。

## 上游变化的移植流程

参考来源分别为 [Flutter DanXi](https://github.com/DanXi-Dev/DanXi) 与 [原生 iOS DanXi](https://github.com/DanXi-Dev/DanXi-swift)。参考平台版本与本仓库版本分别记录。

1. 为拟移植变化记录来源仓库、固定提交或 PR、文件与原因。
2. 判断涉及协议、模型、认证、逻辑、资源还是平台专属行为，仅选择鸿蒙需要的内容。
3. 核对当前实现和失败证据，明确适配假设；已经处理的变化不重复修改。
4. 在独立分支实施最小适配，保持已有缓存、存储、生命周期和交互契约。
5. 用匹配 SDK 与相关实际流程验证；真实服务、设备能力及未验证条件单独记录。
6. 更新来源、许可、功能状态及必要说明，经 PR 审阅后合并。

源码与资源分别核对许可，保留版权和来源。不要把上游应用商店入口、备案、隐私承诺和专属平台能力误写成鸿蒙版自身内容。

## 桌面卡片维护

`entry/src/main/ets/widget/` 维护 FormExtensionAbility、摘要存储与卡片组件，尺寸注册位于 `resources/base/profile/campus_forms.json`。当前共四类、十种尺寸组合。保持应用标识、存储键与既有自定义布局兼容；修改尺寸时覆盖旧实例迁移。卡片复用主应用缓存，不在系统回调中触发账号登录；账号/校区切换应清除旧私人摘要，过期及跨日课表、校车信息必须明确处理。

发布前核对系统卡片选择器、实例添加与点击路由、不同尺寸/明暗显示和缓存清理；模拟摘要验证与真实账号取数分别记录。

## 版本与升级编号

当前发布基线为 **0.1.35.3 Alpha**，`versionCode=1000154`，`buildVersion=155`。数字版本位于 AppScope/app.json5 和 Constant.ets；应用显示为数字版本加 Alpha。

四段式 `A.B.C.D` 及字段规则见 [版本政策](VERSION_HISTORY.md)。新可安装交付需同步版本字段，并保证 versionCode、buildVersion 高于上一交付和已安装版本。公开发布已有开发交付时可沿用其版本字段；同源码重复构建不计为新开发交付。应用行为发生变化时按新交付处理。

## Release 发布流程

### 标题、正文与附件

Release 标题只写四段数字版本，例如 **0.1.33.30**；不附项目名、v 前缀、Alpha 或构建号。Alpha 状态用 GitHub **Pre-release** 标识，tag 仍采用 `vA.B.C.D-alpha`，应用内展示版本继续遵循版本政策。

- 首次公开 Release 的正文只保留 **功能简介**和 **安装方法**，安装部分链接到 [完整侧载说明](INSTALLATION.md)。
- 后续 Release 正文只写本版本的 **更新日志**：只说明新增、调整和修复了什么。包元信息、验证与安装注意事项放在仓库维护文档中。不重复首发功能介绍和通用安装教程。
- 完整包元信息、来源提交、签名类别、验证范围与限制记录在 [版本说明](RELEASE_NOTES.md) 和 [版本历史](VERSION_HISTORY.md)。这些维护记录不直接复制为 Release 正文。

安装包命名为 `DanTa-HarmonyOS-A.B.C.D-Alpha-buildN-unsigned.hap`（旧版 DanXi 文件名保留）。建议同时保留可选的 `SHA256SUMS.txt` 附件，内容为上传前原始 HAP 的 SHA-256 与文件名。它用于检查下载是否完整、是否与发布原件一致；不是安装组件，也不代替应用签名。使用者可以只下载 HAP，签名后的文件不能与 unsigned 原件的哈希直接比较。

### 一次版本更新的实际步骤

1. **确定范围与分支。** 在 `fix/*` 或 `feat/*` 分支修改；多人协作先约定接口与影响范围。原生 main 的上游变化按本手册移植，不使用 Sync fork 直接更新。
2. **修改与验证。** 使用匹配的 SDK 26 构建，执行本次影响的实际页面、账号或服务流程；覆盖更新用同一兼容签名验证，记录数据保留结果，并明确未验证项。当前没有自动 HAP 构建 CI，修改 GitHub 文案不会生成安装包。
3. **确定新交付版本。** 局部修复下一版为 `0.1.35.4 Alpha`，完整功能下一版为 `0.1.36.0 Alpha`。新主版本和次版本主线按版本政策确认。若没有更高的中间交付，下一包使用 `versionCode=1000155`、`buildVersion=156`；发包前仍须核对此前全部交付和已安装版本，两个编号都必须更高。同步 AppScope/app.json5 与 entry/src/main/ets/common/Constant.ets 的数字版本、展示版本及编号。
4. **整理公开源码。** 如果开发目录含个人材料，采用独立净化 Git 工作区，只同步必要源码、运行资源、无私人签名的构建配置与公共文档。检查差异，保留公共维护文档和已经脱敏的根构建配置；不把开发目录整体加入 Git，也不复制个人助手配置、测试档案、账号日志、证书和设备授权材料。净化历史后的协作者从当前远端重新克隆，不合并旧历史。
5. **构建发布候选并记录。** 从拟发布的净化源码构建本版 unsigned HAP，核对包内版本、设备/API 条件、模式、升级编号、构建号与哈希。更新 README 版本和功能状态、VERSION_HISTORY 交付记录、RELEASE_NOTES 更新及维护元信息。检查差异，通过 PR 审阅后合并 main；单人维护也先复核差异。最终来源提交中的应用文件必须与构建输入一致，源码再变动时重新构建。
6. **创建 tag 与草稿。** 将 `vA.B.C.D-alpha` 指向该包对应的来源提交，建立 Release 草稿。标题仅数字版本，正文仅更新日志，勾选 Pre-release；上传 unsigned HAP 与建议保留的 SHA256SUMS.txt。正常发布后的 tag 不移动。
7. **复核后发布。** 检查草稿状态、附件名称与大小；下载附件重新计算 SHA-256，核对上传前原件和校验文件。核对包元信息及实际安装、覆盖升级结果，问题解决后发布。未执行的设备或账号验证在维护记录中明确列出。

纯 Release 文字、安装说明或仓库文档维护没有交付新 HAP，不递增应用版本。QA 包与重复构建按版本政策处理，不重复计数。当前示例为 [v0.1.33.30-alpha](https://github.com/GoodNima/DanXi_HarmonyOS/releases/tag/v0.1.33.30-alpha)。GitHub latest Release 不包含 pre-release（[官方说明](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)），Alpha 下载入口使用明确 tag 或完整 Release 列表。

### 发布后与恢复

问题关联具体版本与脱敏证据。说明文字可更正；应用行为变化应发布新版本，不用相同升级编号替换已分发交付。源码回退后重新交付仍使用更高的 versionCode 与 buildVersion。

需要停止推荐有问题的资产时，记录原因与替代版本，并保留源码/tag/哈希追溯。历史净化不修改已分发安装包；核对所有分支和 tag 的可达历史，并在记录中区分干净引用与 GitHub 可能保留的旧编号缓存。已有旧克隆应重新克隆或只迁移必要差异，不将旧历史合并回新主线。2026-10-14 授权历史净化是 tag 调整的特例，见 [历史净化记录](HISTORY_CLEANUP.md)。

## 文档与许可维护

README 保持鸿蒙用户视角：功能、支持条件、截图、下载、侧载及已知限制。其他平台只在来源、行为对照、许可和致谢等有关内容中展开。

安装方式变化更新 INSTALLATION；构建或协作变化更新本手册、CONTRIBUTING 和模板；应用发布更新 RELEASE_NOTES 与 VERSION_HISTORY。相对链接必须在当前树有效，不指向个人档案或私人绝对路径。

资源替换、依赖引入和功能移植均更新 [第三方材料说明](THIRD_PARTY_NOTICES.md)，保留 [LICENSE](../LICENSE) 及随应用打包的许可全文。

## 首页展示维护

README 保留官方网站、移植参考项目入口及校园、茶楼、课评三页常规界面。截图使用当前页面组件及导航；演示数据须在说明中注明，不发布真实账号、私密帖子或个人成绩。仅保留实际应用依赖和移植来源的引用及许可证，不添加无关项目介绍。
