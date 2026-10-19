# 参与旦挞 HarmonyOS 开发

本仓库的 `main` 维护 Stage 模型的原生 ArkTS / ArkUI 鸿蒙工程。开始前请阅读 [维护手册](docs/MAINTAINING.md)、[版本政策与发布记录](docs/VERSION_HISTORY.md) 和 [安装说明](docs/INSTALLATION.md)。

2026-10-14 整理后，公开工作树保留应用源码、运行资源、必要构建配置以及使用、协作、发布和许可资料。个人开发环境配置、历史任务档案、测试工程和辅助脚本不作为当前公开工程的一部分。

## 贡献范围与协作

欢迎提交有明确复现条件的功能修复、HarmonyOS 能力适配、性能及无障碍改进、翻译和文档修正。较大功能、服务接入或新依赖先在 Issue 中说明使用场景、涉及模块、来源和验证计划，便于维护者协调。

一个 PR 聚焦一个可审阅目标。先确认实际实现和失败证据，写清账号状态、网络、缓存和 SDK 等必要假设，再实施直接相关的修改；不要混入无关重构、配色或动画调整。共享认证、网络、存储和通用组件有多人同时修改时，先协调接口与合并顺序。

## 获取与构建工程

```sh
git clone https://github.com/GoodNima/DanXi_HarmonyOS.git
cd DanXi_HarmonyOS
git switch -c fix/short-description
```

没有写入权限时，先 fork，再从自己的分支向本仓库 `main` 提交 PR。分支可使用 `fix/`、`feat/`、`docs/` 前缀。

用 DevEco Studio **26.0.0.851** 或经验证兼容的版本打开仓库根目录，安装 **HarmonyOS SDK 26.0.0 / API 26** 并同步依赖。当前设备目标为 `phone`。工程使用 `@ohos/hvigor-ohos-arkui-x-plugin` **4.26.8**，并通过 ArkUI-X 配置忽略跨平台构建；这不表示 Android / iOS 构建已获支持。

公开构建配置不含签名。真机运行需在自己的开发环境配置适用的证书和设备授权；下载 HAP 的小白调试工具、HoKit 侧载流程见 [安装说明](docs/INSTALLATION.md)。开发构建流程和依赖仓库见 [构建与签名](docs/MAINTAINING.md#构建与签名)。

## 实现与验证

| 内容 | 主要位置 | 重点检查 |
| --- | --- | --- |
| 页面及交互 | `entry/src/main/ets/pages/`、`components/` | 生命周期、返回位置、焦点、触控和明暗显示 |
| 通用逻辑与模型 | `common/`、`model/`、`util/` | 类型、边界、缓存与存储兼容性 |
| 服务读取 | `repository/` 及相关通用模块 | 认证接续、超时、取消、错误与重复请求 |
| 桌面卡片 | `widget/`、`resources/base/profile/campus_forms.json` | 尺寸注册、实例路由、过期缓存与账号切换清理 |
| 资源 | `entry/src/main/resources/` | 所有已有语言、深色资源、引用和来源许可 |
| 能力与权限 | `entry/src/main/module.json5` | 当前 SDK、设备支持、权限理由与使用场景 |
| 版本 | `AppScope/app.json5`、`common/Constant.ets` | 展示版本、升级编号、构建号一致 |

表中源码子目录相对 `entry/src/main/ets/`。ArkTS 语法和 API 以匹配的 SDK 声明与华为官方文档为准；普通 TypeScript 或其他语言文件按其实际运行环境处理。不要用普通 TypeScript 转译成功代替 ArkTS 原生编译。

按改动选择有意义的验证：文档检查文字和链接；源码检查 SDK 构建与相关边界；交互在设备上检查实际流程；网络问题记录授权账号和真实网络下的成功、失败及接续路径；发布检查包内版本、哈希和安装升级。

当前仓库不提供历史测试工程或 Node 回归入口。PR 应提交能复核的步骤与结果，并区分“通过”“失败”“未验证”。未登录模拟器界面不能证明真实账号服务可用，模拟请求不能证明服务端接受实际请求。纯文字修正不要求新增测试代码。

## 反馈与 Pull Request

反馈 Bug 请提供应用展示版本、`versionCode`、`buildVersion`、设备型号、系统/API、安装来源、复现步骤、预期和实际结果。网络问题补充网络类型及发生时间；诊断与截图上传前需脱敏。

不要公开账号、密码、Cookie、Token、设备 ID、签名材料、校园个人记录或私人帖子。签名及账号凭据通过团队批准的私有渠道管理，不放入 Issue、PR 或仓库。

提交与审阅流程：

1. 在自己的分支实施约定范围，完成适用的构建和实际流程验证。
2. 检查待提交文件，排除个人配置、SDK 绝对路径、缓存、生成包、签名和原始日志。
3. 提交并向本仓库 `main` 发起 PR，说明问题、行为变化、影响模块、来源、验证及剩余限制。
4. 按审阅修正；维护者集中处理合并、版本和 Release，避免并行 PR 争用同一版本字段。

提交标题采用 `短前缀: 英文动作与结果`，前缀为 `app:`（应用）、`docs:`（文档）、`history:`（历史追溯）、`release:`（发布）。例如 `app: Fix quoted floor navigation`、`app: Add venue reservation entry`、`release: Document the version update workflow`；前缀不带括号模块名。GitHub 文件列表使用路径最近一次变更的提交标题；说明应准确概括该次修改，便于维护者查阅。不要改写他人的在途提交或已发布 tag；应用交付的版本更新按 [版本政策](docs/VERSION_HISTORY.md) 执行。

## 上游移植与许可

`upstream-flutter-baseline` 保存移植前的 Flutter 基线。不要用 GitHub **Sync fork** 覆盖原生 `main`，或直接合并 Flutter 平台目录来更新鸿蒙工程。上游变化应记录具体仓库、提交或 PR，并按功能、协议和资源选择必要适配；步骤见 [上游变化的移植流程](docs/MAINTAINING.md#上游变化的移植流程)。

本仓库提交不会自动修改 DanXi 上游；向上游贡献须另行提出 PR，并遵守目标项目规范。引入源码、图标、字体、头像、表情或其他资源时，分别核对来源和许可，保留版权与署名。贡献须遵守 [LICENSE](LICENSE) 和 [第三方材料说明](docs/THIRD_PARTY_NOTICES.md)。

2026-10-20 已统一净化全部历史。持有旧克隆的协作者应先阅读 [迁移要求](docs/HISTORY_CLEANUP.md#协作者迁移)，重新克隆后迁移必要代码，不合并或推送旧历史。
