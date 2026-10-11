# 安装时报“同名任务的所有者/权限不匹配”

用户提供了 Windows 本机错误截图。旧版把多个校验项合并到同一条错误，因此仅凭截图不能判断究竟是哪一个字段失败，也不能推断必须使用管理员权限。

## 已复现并修复

| 编号 | 原因与影响 | 修复 |
|---|---|---|
| B25 | `Principal.UserId` 直接与当前 SID / 完整账户名字符串比较。Windows 可返回短用户名或其他合法账户表示；同一用户会被误判，导致任务刚注册就启动失败、后续重装也被拒绝 | 使用 Windows `NTAccount.Translate(SecurityIdentifier)` 解析账户；SID 字符串用 `SecurityIdentifier` 验证，之后比较 SID。不去掉域名，不因显示用户名相同而放行。解析失败仍拒绝并报告 |
| B26 | 只接受字符串 `Interactive` / `Limited`，忽略 `MSFT_TaskPrincipal` 的 CIM 数字形式 `3` / `0` | 接受对应的枚举名称、CLR 枚举和数字表示；仍拒绝其他值、空值、服务登录、用户组主体与最高权限 |

修改在 `lib/Lifecycle.ps1`。任务描述、归属目录、执行程序、参数和动作数量的原有约束保留。`Get-ProductTask` 只用于读取候选任务，所有启动/停止/覆盖/删除路径继续经过 `Get-OwnedTask` 验证。错误现在分别列出具体不匹配项，并附账户与枚举字段。`Diagnose.ps1` 在归属验证前独立记录任务身份，因此失败也不会吞掉排查所需字段。

字段规范参考：[MSFT_TaskPrincipal](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/taskschd/msft-taskprincipal)、[NTAccount.Translate](https://learn.microsoft.com/en-us/dotnet/api/system.security.principal.ntaccount.translate)。本轮云端访问 Microsoft 文档端点返回 HTTP 403；未把联网查阅或真实 Windows 调用计作测试通过。

## 如何重试，不丢原代理备份

1. 从 GitHub `codex/wifi-proxy-round2` 分支重新下载**最新完整 ZIP**，解压到新的源目录。不要仅运行以前下载的 `Install.bat`，它仍加载旧代码。
2. 用原来安装的同一个普通交互用户运行新目录中的 `Install.bat`。新版会读取原安装记录，保留 `config.json`、`state/proxy-before-install.json` 和后续恢复所需状态，再更新本工具代码与任务。
3. 运行 `Status.bat` 确认 `WatcherRunning=true` 与新心跳；到 Windows 设置核对实际手动代理。控制成功或任务 Running 不等于网络功能验收全部通过。
4. 若仍报错，从新包运行 `Diagnose.bat`。报告默认为 `%LOCALAPPDATA%\WiFiProxySwitcher-Control\diagnostics.json`。只需反馈“任务原始身份字段”和“安装记录/任务归属/心跳”部分；完整报告包含个人网络信息，分享前检查。

不要通过删除备份、取消归属验证、使用 SYSTEM 或全局修改执行策略解决此问题。若诊断显示另一个 SID、任务动作被改、Highest 权限或另一个安装目录，继续拒绝是保护行为，应根据具体证据处理，不自动删除同名任务。

新版仍支持 `RestoreProxy.bat` 紧急停止并恢复、`Uninstall.bat` 卸载恢复。若当前代理已由用户改动，原有显式 `-ForceRestore` / `-KeepCurrentProxy` 冲突处理保持不变。

## 回归与验证边界

新增 `tests/TaskOwnership.Tests.ps1`，由原 `tests/Run-Tests.bat` / `.ps1` 统一执行。10 项覆盖：账户表示、CIM 数字/CLR 枚举、无效运行方式、错误 SID/用户组、同显示名不同 SID、任务篡改、拒绝时诊断、准确任务查询、真实 Start/Stop 校验调用链，以及失败安装后重装保留备份与配置。文件操作真实执行；Windows SID 解析、任务计划程序与进程状态使用明确测试替身。

修复前，向生产校验函数注入短用户名和数值字段，两类均重现同一报错。新测试最初使用 Windows `C:` 测试目录，Linux 上 4 项因没有该盘符失败；改为平台临时目录后，全部针对性测试通过。未放宽产品目录校验或删除断言。完整套件结果见 [测试结果](TEST_RESULTS.md)。

真实 Windows 11 的 `NTAccount` 解析、CIM 回读形式、任务注册及首次启动仍未由云端执行；需要用户按上述步骤验证。这次改动不改变 SSID、网关或 Strict/Safe 代理规则。
