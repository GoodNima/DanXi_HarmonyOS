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

原 Flutter 基线为 [551a88c7](https://github.com/GoodNima/DanXi_HarmonyOS/commit/551a88c7bda36fe48f5fb92b478c0bcc72b4c3c9)，保存在 [快照分支](https://github.com/GoodNima/DanXi_HarmonyOS/tree/upstream-flutter-baseline)。工作树整理之后，2026-10-14 按项目所有者授权净化两次鸿蒙提交并调整 Alpha tag。3403 个上游原始提交及其基线编号保持不变；同版本源码、作者、日期和安装包摘要保留。新旧编号与操作边界见当前 main 的 [历史净化记录](https://github.com/GoodNima/DanXi_HarmonyOS/blob/main/docs/HISTORY_CLEANUP.md)。

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

## 版本与升级编号

当前发布基线为 **0.1.33.30 Alpha**，`versionCode=1000124`，`buildVersion=125`。数字版本位于 AppScope/app.json5 和 Constant.ets；应用显示为数字版本加 Alpha。

四段式 `A.B.C.D` 及字段规则见 [版本政策](VERSION_HISTORY.md)。新可安装交付需同步版本字段，并保证 versionCode、buildVersion 高于上一交付和已安装版本。纯仓库清理、安装说明和本次文档维护没有生成新 HAP，沿用现有发布基线。

## Release 发布流程

### 发布前

1. 选定可交付源码，核对清单与常量的版本、升级编号、构建号和 Alpha 状态。
2. 核对 HAP 包内元信息、构建模式、来源与哈希，不使用来源不对应的旧包替代新实现。
3. 检查工作树和资产，排除凭据、签名、设备授权资料、私人配置及日志。
4. 记录实际完成的构建、设备、真实账号及升级验证；没有执行的项目列为未验证。
5. 准备 Release 正文和 SHA256SUMS.txt，由负责人复核。

资产命名使用 `DanXi-HarmonyOS-A.B.C.D-Alpha-buildN-unsigned.hap`，正文同时列出 versionCode。Alpha Release 勾选 **pre-release**；当前示例为 [v0.1.33.30-alpha](https://github.com/GoodNima/DanXi_HarmonyOS/releases/tag/v0.1.33.30-alpha)。

### 发布与复核

发布 tag 对应包的来源提交，正常发布后不移动。2026-10-14 的授权历史净化为例外：保留 tag 名称、应用版本及资产摘要，同时公开新旧提交映射。上传 HAP 与校验文件后，检查 Release 状态、资产名称和大小，再下载公开资产计算 SHA-256，与上传前值及 SHA256SUMS 一致性核对。

正文至少包括版本三项、tag/commit、签名类别、用户可见变化、系统和设备条件、[侧载步骤](INSTALLATION.md)、验证范围、已知问题、文件哈希及来源署名。同步 README、发布说明和版本历史。

GitHub latest Release 不包含 pre-release（[官方说明](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)），Alpha 下载入口使用明确 tag 或完整 Release 列表。

### 发布后与恢复

问题关联具体版本与脱敏证据。说明文字可更正；应用行为变化应发布新版本，不用相同升级编号替换已分发交付。源码回退后重新交付仍使用更高的 versionCode 与 buildVersion。

需要停止推荐有问题的资产时，记录原因与替代版本，并保留源码/tag/哈希追溯。历史净化不修改已分发安装包；核对所有分支和 tag 的可达历史，并在记录中区分干净引用与 GitHub 可能保留的旧编号缓存。已有旧克隆应重新克隆或只迁移必要差异，不将旧历史合并回新主线。

## 文档与许可维护

README 保持鸿蒙用户视角：功能、支持条件、截图、下载、侧载及已知限制。其他平台只在来源、行为对照、许可和致谢等有关内容中展开。

安装方式变化更新 INSTALLATION；构建或协作变化更新本手册、CONTRIBUTING 和模板；应用发布更新 RELEASE_NOTES 与 VERSION_HISTORY。相对链接必须在当前树有效，不指向个人档案或私人绝对路径。

资源替换、依赖引入和功能移植均更新 [第三方材料说明](THIRD_PARTY_NOTICES.md)，保留 [LICENSE](../LICENSE) 及随应用打包的许可全文。
