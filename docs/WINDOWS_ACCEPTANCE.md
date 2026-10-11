# Windows 11 本机验收（尚未执行）

请在自己的交互用户会话、Windows 11 x64 + Windows PowerShell 5.1 下执行。准备至少一个白名单 SSID 和两个不同网关的测试 Wi-Fi；不能修改 SSID 的场景用模拟套件覆盖，标记为**未实测**。不得把未执行用例写成通过。使用可靠的测试网络，网关上没有代理是允许观察的失败场景。

## 准备与记录

1. 记录 Windows 版本、PowerShell `$PSVersionTable`、安装路径、当前代理开关/地址/绕过、PAC 与自动检测状态；不分享凭据。
2. 在源码目录运行 `tests\Run-Tests.bat`，应所有测试通过；保存完整输出和结果。该套件不改真实代理。
3. 分别在含中文、空格、`!` 的源目录安装到专用中文/空格路径，例如 `Install.bat -InstallDir "D:\WiFi 工具!\测试代理"`。确认普通用户安装；权限被策略禁止时记录阻塞，不假称通过。
4. 检查专属任务的触发器、交互用户 SID、有限权限、电池条件、IgnoreNew、无时间限制和重启策略；确认不是 SYSTEM。
5. `Status.bat` 显示最新心跳和 WatcherRunning=true；日志没有无限重复。用 `Get-NetAdapter` 查询 Wi-Fi InterfaceGuid/ifIndex，用 `Get-NetRoute -AddressFamily IPv4` 和 `ipconfig` 对照同一接口网关；不要分享全部环境变量或认证文件。

## 第二轮新增：只读诊断与回归验收

从新版完整包运行：

```bat
Diagnose.bat
Diagnose.bat -Probe -OutputPath "%USERPROFILE%\Desktop\WiFi-diagnostics.json"
tests\Run-Tests.bat -ResultPath "%USERPROFILE%\Desktop\WiFi-test-results.json"
```

`Diagnose.bat` 默认只读，不写代理、不创建/启停任务、不修改权限。`-Probe` 才尝试连接当前有效非白名单网关，按配置区分 TCP 和 HTTP。报告检查真实系统版本、用户会话、PowerShell、执行策略、WSH、代理策略、WinINet/HKCU 回读、WLAN 快照、任务归属和心跳。网络目标是当前快照计算值，Safe 的历史失败状态请结合心跳与日志查看。默认报告位置是 `%LOCALAPPDATA%\WiFiProxySwitcher-Control\diagnostics.json`；Warn、Fail 和 NotRun 不能当作通过。

静默诊断用 `wscript.exe //B //Nologo "完整包路径\SilentLauncher.vbs" Diagnose`，报告仍保存到同一默认位置。静默 Status 输出在安装目录 `state\control-status.json`。

### 安装报任务所有者/权限不匹配时

从最新完整包运行 `Install.bat`，不删除旧任务或 `state`，不切换到其他账户。新版按 Windows 解析后的 SID 判断账户，接受 `Interactive (3)`、`Limited (0)` 的 CIM 数字或枚举名称形式。安装成功后 `Status.bat` 应有 `WatcherRunning=true`，并检查 UI 的实际代理结果。若仍失败，从**新包**运行 `Diagnose.bat`；报告的“任务原始身份字段”会在归属检查前记录原始 UserId、解析 SID、LogonType/RunLevel 值与 CLR 类型，即使后续校验失败也保留。核对任务运行账户 SID 等于当前用户、没有 GroupId、没有 Highest/服务登录、动作与安装路径正确。参见 [修复与恢复说明](TASK_OWNERSHIP_FIX.md)。真实 Windows 名称到 SID 的解析与任务注册后回读仍须此处验收，云端替身无法替代。

重点重测以下本机边界（云端对应回归全部使用明确测试替身）：

1. 重复 Start 至少 20 次，特别留意首次启动是否退出 0 却没有监控；最终只有一个 Watcher，登录任务保持启用。
2. WLAN 服务恢复/位置权限恢复后，不手工重启工具也能重新读取；日志不能持续卡在同一失效句柄。
3. A→B、短暂断开、同 SSID DHCP 更新时，对照接口 GUID 与 ipconfig，不能把 A 的网关写给 B；记录驱动/DHCP 实际过渡状态。
4. Safe 已关闭后制造 HTTP 503 或不完整状态行，Unknown 不能被当成恢复；代理恢复成功后自动启用。Strict 不等待探测成功。
5. 修改已安装 config，升级后配置保留；修改一个脚本后升级，旧脚本应出现在 user-backups。卸载不能删除这些用户备份或无关文件。
6. 在测试机受控制造卸载文件锁/任务删除失败，确认失败可见且可重试。必要时从完整包执行 `Uninstall.bat -InstallDir "原安装目录"`。不要在有重要代理配置的生产机器上人为破坏备份。
7. 在 PowerShell 5.1 原生执行完整测试；检查 BAT/VBS 的中文、空格、`!`、`&`、方括号路径。成对 `%NAME%` 安装路径应被明确拒绝，不得悄悄解析成另一个目录。
8. 分别观察登录、唤醒、锁屏和异常重启中的窗口行为。WSH 文件存在与静态 Hide 参数不等于已验证零闪烁。

## 核心验收矩阵

| 编号 | 操作 | 必须观察的结果 |
|---|---|---|
| 1 | 连接 MC-Office | 手动代理关闭，旧地址保留 |
| 2 | 连接 Meituan | 关闭 |
| 3 | 连接 mc-office | 关闭，大小写不影响 |
| 4 | 连接 MEITUAN | 关闭 |
| 5 | 连接 MC-Office-Guest | 开启，不能模糊匹配白名单 |
| 6 | 连接普通 Wi-Fi | 开启，当前接口网关:7890，本地绕过勾选 |
| 7 | 普通 A→B，不同 IPv4 网关 | 即使开关已开，地址更新为 B，不保留 A |
| 8 | 普通→MC-Office | 关闭 |
| 9 | MC-Office→普通 | 开启且地址为当前网关 |
| 10 | Wi-Fi 真正断开，仍连以太网 | 断开确认后关闭，不使用以太网代理地址 |
| 11 | 测试 Wi-Fi 只有 IPv6 / 无 IPv4 网关 | Keep；不写 IPv6、空地址、自身 IP 或历史值 |
| 12 | DHCP 延迟，随后提供 IPv4；同 SSID 网关变化 | Keep 后自动设置新网关，日志可解释 |
| 13 | 同时有 VPN、Hyper-V、WSL/Docker、以太网 | 只用关联 Wi-Fi 接口网关 |
| 14 | 两个真实无线接口连接 | 最小唯一总成本；同成本 Keep；指定首选 GUID 后选对应接口 |
| 15 | 网关 7890 未监听 / 监听但非 HTTP | Strict 仍开启并记录失败；Safe 连续失败阈值后关闭并重试；TCP 开放不标成 HTTP 可用 |
| 16 | 快速 A/B/白名单切换及短暂断开 | 最终稳定状态正确，临时读取失败不误判，无高频重写 |
| 17 | 多次 Start；同时 Start/Stop | 每用户一个 Watcher；控制命令串行，最终 Stop 后不继续改代理 |
| 18 | 注销/登录，重启后登录 | 当前用户任务自动启动；安装立即启动；Stop 后登录仍保持停止，Start 可恢复 |
| 19 | 睡眠/唤醒，醒后更换网络，锁屏 | 不用日常人工启动，恢复检测；锁屏持续运行；测量唤醒后的实际延迟 |
| 20 | Uninstall + 重复 Uninstall | 无进程、无专属任务/启动指针；恢复最初值；默认日志保留；其他任务/文件无影响 |

每项检查 Windows 设置 UI、Status 与时间戳日志，记录通过/失败/未执行及观察延迟。不要只凭任务 Running 或端口开放判定通过。

## 保护、故障与无窗口体验

- **位置权限**：停止监控，按系统允许的方式关闭位置权限再启动。访问拒绝应 Keep 并明确记录；重新允许权限后应自动恢复，不把权限失败当白名单或断网。Windows 自身权限提示/位置图标不能当成本工具窗口。
- **WLAN 服务**：只在测试机按管理员允许的方式暂时停止服务，确认错误与重试；服务恢复后监控恢复。不要关闭企业安全服务。
- **策略/访问拒绝**：受管代理环境应阻止写入并有日志；恢复被策略阻止应保持备份和安装记录。若公司禁用 WSH/PowerShell/任务创建，标记外部阻塞。
- **PAC/WPAD**：有自动代理时记录警告，比较安装前后 URL 与自动检测勾选，二者不能被改变。访问实际目标确认是否被 PAC 优先选路；此冲突不会被工具偷偷消除。
- **外部手动变更**：运行时修改手动代理，下次检测应纠正。先 Stop 后修改，Uninstall 应拒绝覆盖并保留备份；明确用 ForceRestore 才恢复，或 KeepCurrentProxy 卸载保留新值。
- **异常退出**：用任务管理器终止属于本工具的 watcher（确认命令行路径和 SID）；约 1 分钟后任务应重新运行且仍只有一个实例。不要终止别的软件 PowerShell。
- **幂等安装**：改 installed config，重复安装，验证配置及最初备份保留，任务仅一个；在安装目录放无关文件，卸载不能删它。改过的项目文件应按哈希保留。
- **备份恢复**：先比较安装前三个值，包含值不存在时的情形。恢复后核对注册表存在性/类型、WinINet/设置 UI。ProxyEnable=0 时地址不得因普通关闭而被清空。
- **静默**：使用 VBS 而非 BAT 启动，持续观察连接/断开、唤醒、登录、故障重启过程，不应出现 CMD/PowerShell 窗口或闪烁。WSH/执行策略失败查 quiet control log 和任务历史。
- **长期**：运行至少 24 小时并反复切换网络，记录 CPU/内存范围、日志增长和归档数量。默认约 4 MiB watcher 日志总容量（允许单条略越阈值）；不能无限刷每 5 秒重复状态。
- **清理**：`Uninstall.bat -DeleteLogs` 删除本工具日志；被改文件/无关文件保留。独立 control-errors.log 可手动清理，不是自启残留。

## 判定

核心网络与生命周期场景、代理 API/注册表/UI 一致性、静默和长期运行全部实测通过后，才能宣称该 Windows 机器验收完成。Linux 模拟通过只是开发证据。任何失败需记录 Windows 版本、脱敏日志、任务退出码和重现步骤，保留备份后再修复。
