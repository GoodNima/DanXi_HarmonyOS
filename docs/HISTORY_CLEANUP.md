# 鸿蒙历史净化与版本追溯

2026-10-14 经项目所有者明确要求，对本 fork 的旧鸿蒙提交与 Alpha tag 进行历史净化。此操作属于正常 tag 不移动政策的明确例外，不是应用新版本发布。

## 范围与结果

- 完整备份并检查改写前 3405 个可达提交、两个分支和一个 Alpha tag。
- 移除本仓库导入的 191 个个人开发规则、历史工具/夹具、测试工程及任务核验文件，修正对应测试构建目标和依赖。
- 保留 3403 个上游原始提交的编号、作者、日期、源码和许可；Flutter 来源基线仍为 551a88c7bda36fe48f5fb92b478c0bcc72b4c3c9。上游原始工程史中的源文件与其测试记录不作为鸿蒙个人档案改写。
- 同版本净化 tag 保留 396 项正式应用源码与资源，字节与首次发布对照范围一致；运行代码、资源及安装包版本不变。
- 保留两个鸿蒙历史节点的作者、日期和提交说明，即使文件过滤使后续整理节点的差异为空，也保留该节点供追溯。
- 清理旧 Node 回归 Actions 运行日志及其 npm 缓存；保留首发 38 项通过的验证摘要，此处不是重新运行测试。

## 新旧提交对应

| 历史节点 | 改写前编号 | 净化后编号 |
| --- | --- | --- |
| 首次鸿蒙导入与 Alpha tag 来源 | 3f196ed1b9411e1fb686853104751bf8fc19a0f6 | 1e7390848306b19bd7d5df5d97e6e33486db9787 |
| 侧载说明与工作树整理历史节点 | 98188b5fc3afa150db5c00e319ac9be7672df2b9 | 09e0aa7694fa89827549224796f76cbfcc8b682d |
| Flutter 来源基线 | 551a88c7bda36fe48f5fb92b478c0bcc72b4c3c9 | 保持原编号 |

main 在净化后历史节点上另有本记录的文档提交。tag 名称仍为 v0.1.33.30-alpha，指向表中净化后的首次鸿蒙节点；Release 正文和来源字段同步更新。新旧编号仅用于审计对应，不建立包含旧开发档案的公开备份分支或 tag。

## 文件列表提交备注规范化

2026-10-14 按项目所有者最终要求，main 上本项目的提交标题使用简洁英文说明，并加短类别前缀：`app:`、`docs:`、`history:`、`release:`。前缀不带括号模块名。GitHub 文件列表显示对应路径最近一次实际变更的提交标题，不提供独立文件备注字段。

本次为七个本项目提交增加前缀；各自 Git tree、作者、提交者、日期和时区逐项保持一致，仅修改说明和后继父编号。随后更新本追溯记录及协作规范。

| 原记录编号 | 无前缀英文阶段 | 当前 main 对应编号 | 英文说明 |
| --- | --- | --- | --- |
| 1e7390848306b19bd7d5df5d97e6e33486db9787 | d36f4e62632559a570a49cc63557fcea0d2ac5db | a6e2ada00d4c3d250236a99fbd1718dfbfd7d3a1 | app: Initialize HarmonyOS app sources and build configuration |
| 09e0aa7694fa89827549224796f76cbfcc8b682d | 5755a285731d10c767b1a60eb977aa89ae7b02f2 | 0d585b0856e083bc4fc49066bae4ac070fb0926c | history: Preserve sideload guidance and cleanup history |
| a0e8c17ccba4cc29c85afe9e2fb047b47d8bf3fa | 6361cbd969e20757385e8905b94842e101923d7d | 983bb1d01424ad7a771bd3923a056a689024d612 | history: Record cleanup mapping and release provenance |
| 120293030276a4f41154766d1e86cb31489e7739 | 6ca15bedee82ac9be9f181aa4e3ea329e5614ebd | 99f7597776f79a6f271fc45478f985711e90fa29 | history: Clarify GitHub retention of old commit objects |
| c83ff6d188e43e6c8dc8b87e80cc6451463c206b | 20cf492c43eabe94a51afbedd4098ad28a9006a2 | 8931f023482f44b33be31275cf7e5a522b07e641 | release: Simplify release notes and document the update workflow |
| 419f1f5957c3e0ffeee97a692eaf94159dcd0b26 | 1f6553cbd32c8d863914b08d5abf0e5af2b71790 | bd9ff87b91f720b93dbd2da27262eaee5c7f0f0c | docs: Document repository commit messages and provenance |
| 09f537266a3c73b14b60262ce86dc057479c7a46 | 09f537266a3c73b14b60262ce86dc057479c7a46 | e453e2fbd9a8339f86289800ac56b84d3dc623ec | docs: Use clear English commit messages for repository files |

此前净化及备注维护的对应关系继续保留。3403 个上游原始提交保持原编号，LICENSE 的原上游说明继续保留。已发布 `v0.1.33.30-alpha` 仍指向 `1e7390848306b19bd7d5df5d97e6e33486db9787`，Release 来源和安装包不变；其文件树与无前缀英文导入节点及当前 `a6e2ada00d4c3d250236a99fbd1718dfbfd7d3a1` 一致。已发布 tag 不再是调整后 main 的祖先，继续保留用于原包来源追溯。

此次备注维护没有恢复已移除的191项目标材料，不增加应用交付次数。后续按真实变化选用短前缀并写明动作与结果；协作者按下方要求保留本地工作后重新克隆。完整回退备份仅保存在维护者本机。

## 安装包与版本

应用保持 0.1.33.30 Alpha，versionCode=1000124，buildVersion=125。已有 unsigned HAP 不重新上传或换包，大小 10408732 字节，SHA-256 为：

```text
957083f41c705a080054c449e513a2fc60f62995e4625e056df40e755e99dc17
```

源码 tag 已净化，自动生成的 ZIP/TAR.GZ 对应该 tag 的新快照；这些是源码归档，不是可直接安装的包。签名侧载见 [安装文档](INSTALLATION.md)，版本字段见 [版本政策](VERSION_HISTORY.md)。

## 协作者迁移

此次 main 历史与旧克隆分叉。需要继续工作时，保留自己的未提交修改及本地分支备份，重新克隆当前仓库，再仅迁移需要的代码差异；不要普通 pull 后合并或推送旧历史，以免把已过滤文件恢复到公开引用中。

```sh
git clone https://github.com/GoodNima/DanXi_HarmonyOS.git
```

已有工作应对照新旧编号选择需要迁移的变更，再按维护手册构建、审阅和发布。原始完整 bundle、旧报告和原始核验资料只在维护者本机保存，不上传公开仓库。

## GitHub 保留边界

本次净化针对本仓库可控制的分支、tag 及其可达历史。GitHub 的旧编号对象、缓存页、外部 fork 和他人克隆可能仍保存旧内容；不能将引用净化声明为所有旧对象已永久抹除。本轮实测按原鸿蒙导入编号读取旧 AGENTS.md，GitHub 仍返回 HTTP 200；这并非当前分支或 tag 重新包含该文件。GitHub 官方说明其支持渠道不清除非敏感的多余文件缓存，因此不承诺旧编号已不可访问。

依据：[历史改写与旧对象访问](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)、[源码归档及缓存](https://docs.github.com/en/repositories/working-with-files/using-files/downloading-source-code-archives)。
