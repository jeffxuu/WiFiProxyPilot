# 公开仓库审计

审计日期：2026-10-14（Asia/Shanghai）。此报告记录已执行的只读检查与公开前的剩余事项；不代表已获公开或历史重写授权。

## 仓库与基线

GitHub 连接器重新读取仓库、分支和 Release：

| 项目 | 实际结果 |
| --- | --- |
| 当前仓库 | 已沿用历史改名为 `jeffxuu/WiFiProxyPilot`，Private，0 Star |
| 最新 v3.1 分支 | `feature/ui-tray-performance-v3.1`，`2244a02ca21a251ea4fcf15313e1ccb8c62d4064` |
| main | `38799dcad92646ad11b6c2f3f1fc6afc2808bd95`，Initial commit；未包含 v3.1 |
| 开发基线 | 从完整 v3.1 新建 `feature/v3.2-product-experience`，未从旧 main 重写 |
| 已上传 UI checkpoint | `08c224c59018fbda197c91c4ffbbe45d4e0b44f2`；本地 HEAD 与远端 v3.2 跟踪分支一致 |
| v3.1 Release | id `411724477`，draft=true、prerelease=true，target 为上述 v3.1 SHA；EXE/ZIP/SHA256 附件已上传 |
| v3.0 Release | 正式 Release 保留，未修改 |

本次同步已解除浅克隆，`git rev-parse --is-shallow-repository` 返回 `false`。对全部已获取分支/tag 的 **18 个可达提交**逐一扫描文本树，而非只检查 changed-files patch。审计开始时 main 仍为 Initial commit；后续 PR 合并结果须另行直接读取远端核验。旧名称重命名沿用原仓库历史；本地 origin 的 fetch/push 地址均为新名称。未 reset/clean、改可见性或强制重写。

## 隐私发现

基线及历史存在旧企业网络名和题目指出的实际私有 IPv4 示例。为了避免再次把这些值打进新发布材料，本报告只记录类型及可定位位置。

| 历史位置 | 发现 | 处理要求 |
| --- | --- | --- |
| `2e51d51b7a567212804f98df2d782fc32834abf8` 的 `config.json:2`、`README.md`、`docs/WINDOWS_ACCEPTANCE.md` | 两个企业 SSID 被当作默认规则及宣传 | 新默认为空，当前用户文档改为用户自主规则；历史值仍存在 |
| 同提交起的 `tests/Run-Tests.ps1` | 私有 IPv4 示例及企业 SSID 测试词条 | 当前保留的历史回归夹具仍有这些值；没有宣称已全部匿名化，历史不自动重写 |
| `842e5059620517ee483aea0b45861b728372029c` 的 `tests/Round2.Tests.ps1` | 相同私有 IPv4 与企业 SSID 示例 | 同上 |
| `08c5e74faff970745484fb2b37943357ba246e99` 的 `src/WiFiProxySwitcher.Core/ConfigurationStore.cs`、`lib/Core.ps1`、`src/WiFiProxySwitcher/DesktopSmoke.cs` | 硬编码规则及旧桌面夹具 | 新版本解除全部内置保护；当前生产实现不能再补回名称 |
| 同提交的 `release/NOTES-v3.1.0.md`、旧文档、`docs/evidence/engine-v30.json` | 名称进入发布说明和测试证据 | 保留历史记录时明确旧版本；不得重新作为新产品行为宣传或打包 |
| `release/ci-latest.json`、`release/ci-v3.0.0.json` 的多个历史提交 | 旧测试名、构建环境路径/身份和网络夹具 | 新包不携带旧 CI 回执；公开历史仍需人工确认 |

删除当前文件中的值不能删除 Git 历史中的值；旧 Release 说明和附件同样可能包含这些内容。公开前必须由仓库所有者决定：接受这些历史数据公开，或授权进行完整备份、历史过滤、所有分支/tag 更新及旧附件重建。此轮没有执行历史重写，也没有自动删除旧 Release。

## 凭据、调试文件和依赖

已对 18 个完整可达文本树检查 GitHub token 指纹、常见云访问密钥、私钥头、JWT 和字面凭据赋值；该范围内未发现匹配。历史 tracked 路径未发现 `.env`、私钥/证书包、日志、状态目录、转储、PDB、EXE/DLL/ZIP 或 bin/obj 编译缓存。此为模式扫描结果，不能证明所有未知格式凭据不存在；二进制内容、外部 Actions Secrets 和本地忽略文件未按秘密全文导出。私有地址和网络词条的模式匹配也不能证明每个值均为真实秘密，应交由所有者审阅。

基线 `.gitignore` 排除了 state、logs、artifacts、bin/obj、publish 和 release/dist/generated。发布工程应继续禁止打包本机安装配置、原始代理备份、日志、诊断报告或调试符号。SHA256 清单及资源完整校验继续保留。

基线根目录没有开源 LICENSE 或第三方许可说明。本次准备了项目 MIT `LICENSE` 和 `docs/THIRD_PARTY_NOTICES.md`。已评估 WPF UI 4.3.0 的兼容 .NET 8 资产和许可，原始 MIT/ThirdPartyNotices 已逐字保存在 `docs/licenses` 并核对哈希；当前 UI 方向为自定义 WPF 模板/矢量，不要求引入该库默认控件或图标字体。依赖与许可最终以实际候选构建为准，不能仅凭计划认定完成。

旧图标由 `tools/Generate-Icon.ps1` 使用几何绘图生成，未引用 Apple 品牌素材。新版参考 macOS 的简洁信息层级，控件/矢量自行实现，不能复制 Apple 素材。新图标、截图与字体需在最终构建核对来源。软件真实截图可以使用隔离模拟状态，但必须标明测试环境，不伪装真实 Wi-Fi/代理测试；不得含当前开发机的真实 SSID、代理地址、账户路径或备份值。

## 当前文档匿名化与截图核对

本次只做了下列低风险文档修订，没有更改测试夹具、源代码中的历史桌面测试、旧 Release 说明或历史证据的网络值：

- `docs/ADVANCED_USAGE.md` 的当前介绍改为空用户免代理规则、暂停意图与验证后的热重载；保留的脚本包流程明确标为历史说明。
- `docs/PRODUCTIZATION.md` 的状态导出示例使用 `%LOCALAPPDATA%`，不包含具体用户目录。该页仍明确是历史 v3.0 架构。
- `docs/evidence/startup-compression.json` 和 `docs/evidence/startup-v31.json` 只匿名化 `Exe` 路径；逐字段比较确认所有时间样本、文件哈希、机器性能信息及其他测量字段保持不变。
- 当前企业网络词条仍位于保留的 `docs/TEST_RESULTS.md`、`docs/WINDOWS_ACCEPTANCE.md`、engine/test JSON 证据、旧 CI 回执、`DesktopSmoke.cs` 和相关测试文件。不能把文档匿名化误称为整个当前树或历史已清理。

当前项目未引用 WPF-UI NuGet 包；未找到复制的字体文件、第三方图片或编译二进制。产品与托盘图标由项目几何代码生成。实际候选包的 .NET/Windows Desktop Runtime 许可仍须随分发材料保留，不能用项目 MIT 许可替代。

已视觉核对 `docs/images/dashboard.png`、`rules.png`、`settings.png`、`dashboard-initial.png`、`dashboard-dark.png` 与新增 `tray.png`：都是真实应用截图，使用通用演示网络和文档 IPv4 地址，没有观察到个人网络、账户路径或原始代理备份。截图使用隔离模拟状态，**不证明真实代理连接或互联网可用**。当前主页使用新的简化 Overview；Dark Theme 图为较早布局，README 已说明。Tray 图为当前应用的真实菜单捕获，同样来自隔离夹具，没有将示意图冒充截图。

## 本机只读检查记录

开发机已有当前用户安装、运行中的旧 GUI、独立 Watcher 与登录任务。卸载记录显示 3.0.0；任务为 Interactive/Limited，状态 Running。手动代理当前开启；已有服务器及绕过设置，未发现 PAC URL。未导出真实 SSID、服务器地址、账户 SID 或用户配置值。

本轮只查询状态，没有安装/卸载、停止 Watcher、关闭代理、修改任务、重启 Explorer 或改变网络。开发机使用中的代理必须在后续验收授权后才修改。最初备份与用户规则不得因品牌改名覆盖。

## 最终确认事项

- 仓库已重命名，正式品牌为 WiFi Proxy Pilot；安装标识、注册表键、互斥锁和任务身份保留升级兼容性。
- 是否从 Private 改为 Public，以及上述历史隐私处理选择。
- 真实 Windows 网络、代理、任务、升级/卸载及 Explorer 验收授权。
- 候选 Release 是否转为正式公开版本；尚未实机验证事项需继续标明。
- Authenticode 签名是否纳入后续发布；没有签名时不得宣称已签名。
- Private 仓库与零星标状态下，外部徽章/Star History 不保证可用。公开后必须重新验证；不制造增长曲线。

候选版本构建、SHA256、PR 和实际验收状态见 `RELEASE_CHECKLIST.md`、`TEST_RESULTS_V3_2.md` 与 `PERFORMANCE_V3_2.md`。这些文档的最终结果仍应在公开前核对。
