# 鸿蒙 Alpha 侧载安装与升级

从 [DanXi_HarmonyOS Releases](https://github.com/GoodNima/DanXi_HarmonyOS/releases) 下载 HAP 后，可用 **小白调试助手**或 **HoKit** 完成调试签名及侧载，无需为了安装应用而先编译整个工程。开发者也可使用 DevEco Studio。

当前下载包为 `DanTa-HarmonyOS-0.1.35.3-Alpha-build155-unsigned.hap`，版本 **0.1.35.3 Alpha**，升级编号 `1000154`，构建号 `155`，应用标识 `com.danxi.ohmo`。它是 **未签名开发包**（`debug=true`），先完成适用于自己设备的签名，再安装签名后的文件；直接打开或直接侧载 unsigned 文件不会完成签名。

应用现名为“旦挞”，应用标识仍为 `com.danxi.ohmo`。从旧版升级时继续使用原有兼容签名；名称更改本身无需卸载。

## 先确认设备与下载文件

1. 本包只声明 **phone**，目标及最低兼容 SDK 均为 **26.0.0 / API 26**。包内 `minAPIVersion` 和 `targetAPIVersion` 为 `260000026`。工具支持 HarmonyOS NEXT 并不表示本包支持所有 NEXT 系统；没有低 API 兼容包，也没有平板或手表支持承诺。
2. 在 Releases 的 **Assets** 下载上述 `.hap`；`SHA256SUMS.txt` 可选，用于核对下载文件，不是安装所需组件。Alpha 是 Pre-release，请使用发布列表；自动生成的 Source code ZIP/TAR.GZ 是源码，不是安装包。
3. 可选：在电脑校验未签名原始下载文件。SHA-256 是文件摘要，相同下载原件应得到相同结果；它不代替签名，也不能单独证明应用安全。Windows 可使用下面的命令。签名后文件会改变，不应再拿签名产物与原 unsigned 哈希比较。

```bat
certutil -hashfile DanTa-HarmonyOS-0.1.35.3-Alpha-build155-unsigned.hap SHA256
```

原文件大小 **10708731 字节**，SHA-256：

```text
43b966142d818529d8838a35968f1e09dd683350e4de5f2b9275115db3fec323
```

## 准备调试连接和签名

- 在手机设置中开启开发者选项，按系统要求完成 PIN 验证或重启，再开启 USB 调试。菜单位置以当前系统为准。用支持数据传输的 USB 线连接电脑，解锁手机并确认调试授权。首次安装建议使用 USB。
- 无线调试时，手机和电脑应在可互通的局域网；开启无线调试，使用手机当前显示的 IP、端口和授权方式。IP 或端口变化后重新连接，不固定套用其他人的地址。
- 自动调试签名需要自己的华为开发者账号、联网以及账号所需的认证/授权。证书、私钥和 Profile 应匹配应用身份及目标设备。调试 Profile 必须覆盖该设备的 UDID，别人的设备专用包不能直接代替。
- 只在工具提供的登录页面完成账号登录。证书、私钥、Profile 和工具产生的账号缓存留在自己的电脑，不上传到 Issue、PR 或公开仓库。

连接后可用 SDK 或工具提供的 HDC 查看设备及 API：

```text
hdc list targets
hdc -t <设备标识> shell param get const.ohos.apiversion
```

将尖括号内容换成实际值，不保留尖括号。有多个设备时必须明确选择目标；设备 API 应满足本包 API 26 的要求。手机的市场系统版本名不能代替 API 检查。官方指引见 [真机运行](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-hmos-run-device)、[申请调试 Profile](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-profile-0000002248181278)。

## 方式一 小白调试助手

### 下载与启动

从作者的 [发布页](https://github.com/likuai2010/auto-installer/releases) 下载适合电脑的版本，解压后启动。2026-10-14 查询到的最新版为 [3.1.0](https://github.com/likuai2010/auto-installer/releases/tag/3.1.0)，该发布提供 Windows ZIP、Mac ZIP 和 HarmonyOS HAP；不要把 README 历史平台列表当作本版附件列表。

作者在 [2.5.0 发布说明](https://github.com/likuai2010/auto-installer/releases/tag/2.5.0)中说明新签名算法不再需要 Java，因而不把旧版“先安装 Java”作为当前必做步骤。后续版本按其发布说明处理。

### 连接与安装

1. USB 连接并授权后，在工具中确认识别到目标手机。USB 方式不填写无线 IP，见[作者答复](https://github.com/likuai2010/auto-installer/issues/29#issuecomment-2503322875)。无线方式则按手机当前 IP、端口连接；3.1.0 的自动端口默认值不能代替设备实际连接信息。
2. 在工具的账号入口登录自己的华为账号，完成页面提示的认证、验证码或授权，并检查当前目标设备。
3. 选择下载的 DanXi unsigned HAP，核对包名 `com.danxi.ohmo` 和版本。进入工具的自动签名/调试流程，根据提示为该包名和设备申请或刷新调试材料，再进行签名安装。
4. 对这个 unsigned HAP，不使用仅供已签名 HAP 的直接安装流程。签名或设备授权失败时先处理具体错误，再重试；不要反复直接安装未签名文件。
5. 等待工具显示安装完成，在手机启动 DanXi。保留之后更新所需的签名身份和账号材料；到期时按工具的续期流程处理。

以上按作者公开功能说明整理；不同版本的按钮名称和界面顺序可能变化，以所用版本的教程及提示为准。[3.1.0 说明](https://github.com/likuai2010/auto-installer/releases/tag/3.1.0)提供已签名 HAP 直接安装和续期功能，并说明工具会在本地建立账号、备份文件。HarmonyOS 版小白本体首次安装仍需另一个已能签装的平台，不能用尚未装入手机的助手完成它自己的首次安装。

## 方式二 HoKit

### 下载与连接

从作者的 [发布页](https://github.com/yabi-zzh/HoKit/releases) 下载适合电脑的平台和架构。2026-10-14 查询到的最新版为 [v1.8.10](https://github.com/yabi-zzh/HoKit/releases/tag/v1.8.10)，提供 Windows x64 EXE、macOS arm64/x64 DMG、Linux x86_64 AppImage。安装或解压启动后连接已开启调试并授权的手机。

HoKit 的[作者说明](https://github.com/yabi-zzh/HoKit)称内置 HDC 和重签名所需 JRE；若电脑已有 HDC，可能优先使用系统版本。先确认目标设备在线。无线连接可在能调用 HDC 的终端执行：

```text
hdc tconn <手机当前IP>:<当前无线调试端口>
hdc list targets
```

### 重签名与安装

1. 登录自己的华为开发者账号。确认账号有有效调试证书和 Profile，并已注册目标设备；可在重签名页面的已注册设备页检查、注册自己的设备。
2. 进入 **应用重签名**，选择 DanXi unsigned HAP。核对包名、版本和应用信息，使用匹配本应用与设备的调试材料执行重签名。
3. 查看日志，成功后打开输出目录，找到新生成的**已签名 HAP**。不要误选输入目录中的原 unsigned 文件。
4. 作者说明没有承诺重签名成功后自动安装。使用能调用 HDC 的电脑终端安装输出文件；未加入 PATH 时使用工具或 SDK 的 HDC 完整路径。HoKit 的设备 Shell 终端不能代替电脑侧 HDC 命令行。

```text
hdc list targets
hdc -t <设备标识> install "<已签名HAP路径>"
```

5. 安装成功后在手机启动 DanXi。有多个设备时，`-t` 必须对应本次签名 Profile 包含的目标。准备覆盖更新时，也先核对下面的数据保留条件。

连接和安装命令依据 [OpenHarmony HDC 指导](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/dfx/hdc.md)。调试连接成功和重签名成功是两个独立步骤；仅看到在线设备并不能证明该 HAP 已签名或设备已获授权。

## 方式三 DevEco Studio

开发者可以克隆本仓库，在 DevEco Studio 中安装 SDK 26、同步依赖，并通过 **Project Structure → Signing Configs** 配置自己的自动或手动签名后运行。也可按匹配 SDK 的签名工具说明签名下载的 HAP。构建步骤见 [维护手册](MAINTAINING.md#构建与签名)，官方入口见 [应用签名](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-signing)。本仓库不提供维护者的签名材料。

## 更新与数据保留

保留原应用数据需要兼容的应用标识与签名身份，且新包的升级编号满足系统更新规则。换电脑、工具或重新生成证书时，尽量继续使用原来的签名身份；不同工具不保证使用相同身份。首次从维护者的测试包改为自己的签名，可能无法直接覆盖。

在 HDC 帮助确认当前版本支持更新参数后，可用 `hdc -t <设备标识> install -r "<新已签名HAP路径>"` 覆盖安装。签名冲突时优先找回原签名材料。必须卸载重装前先处理可导出的数据；卸载可能清除本地数据，不能称为保留数据升级。不要用相同旧包反复覆盖来验证版本升级。

## 安装失败排查

| 现象或代码 | 处理方向 |
| --- | --- |
| 无设备、离线或连接失败 | 检查数据线、调试开关、解锁及手机授权；无线检查当前 IP/端口和局域网；多设备核对 `-t` |
| 无签名 / `9568320` | 安装前完成签名，选择签名后的输出文件 |
| 未授权设备 / `9568322` | 检查 Profile 是否包含当前设备，重新生成匹配包名和设备的调试材料 |
| 系统 API 过低 / `9568297` | 核对设备 API 与本包最低 API 26；重签名不会降低 API 要求 |
| 新旧签名不同 / `9568332` | 继续使用兼容的原签名身份；卸载重装前处理数据保留问题 |
| 版本降级 / `9568263` | 对比已安装升级编号，下载合适的新版本，不降低 `versionCode` |
| 设备类型不支持 / `9568304` | 本包只声明 phone；不能凭工具可连接就认为该设备受支持 |
| 开发者模式关闭 / `9568401` | 按设备系统流程开启开发者模式及调试 |
| 账号、证书或 Profile 申请失败 | 看工具具体错误、账号认证、网络和材料有效期；必要时到作者仓库查询对应版本问题 |

错误码含义参考华为 [bm 工具说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-v5/bm-tool-V5)，实际先以设备返回的完整错误为准。反馈时提供系统/API、工具版本、应用版本与脱敏错误；不要提交设备完整标识、账号、验证码、Cookie、Token 或签名文件。

## 资料与验证范围

本文依据 2026-10-14 查询到的工具作者说明与华为/OpenHarmony 文档。**尚未使用上述两个工具，在真实手机上对本版 DanXi HAP 完成签名安装验证。** 工具资料描述的是操作路径；不承诺云端签名服务、所有账号和所有设备在任意时间可用。项目已记录的构建及历史模拟器验证范围见 [版本说明](RELEASE_NOTES.md)。
