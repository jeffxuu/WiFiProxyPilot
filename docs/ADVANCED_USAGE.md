> 本页包含当前 v3.2 的配置约定，以及为排障保留的 v3.0 脚本包操作细节。普通用户先阅读 [产品首页](../README.zh-CN.md)。v3.2 仍在开发；不要把旧版安装流程、历史测试结果或脚本命令等同于候选版已完成实机验收。BAT 命令从安装目录的 `tools` 文件夹运行。

# WiFi Proxy Pilot：高级使用与历史脚本说明

根据真实 Wi-Fi SSID 和该物理接口的当前 IPv4 默认路由，控制**当前用户的 Windows 手动代理**。运行端仅依赖 Windows 11 x64 自带的 Windows PowerShell 5.1、WLAN API、WinINet、任务计划程序与 Windows Script Host，不需要 Python、Node.js 或第三方组件。

当前 v3.2 的新安装默认为空免代理名单、`ManagementIntent=Paused`、`SetupComplete=false`，不会预置个人或企业 Wi-Fi。打开界面本身不会开启自动管理。用户启用自动切换后，自定义免代理规则按完整名称 `OrdinalIgnoreCase` 匹配时关闭手动代理；其他 Wi-Fi 使用该接口 IPv4 默认网关和指定端口（默认 `7890`），绕过列表保留现有条目并加入 `<local>`。所有规则均可编辑或删除，删除后不会自动重新加入。确认断网关闭；SSID/路由读取失败时保持现状并重试。关闭手动代理不会清空代理地址或绕过列表。

**验证边界：历史 Linux 检查、旧版本 Windows 验收及 v3.2 隔离回归属于不同范围。当前候选版真实网络、安装升级、登录/休眠及卸载验收以 [v3.2 测试记录](TEST_RESULTS_V3_2.md) 和 [发布清单](RELEASE_CHECKLIST.md) 为准。** 网关本身不保证有代理服务；Strict 模式可能使没有代理的网络无法上网。本程序不提供代理服务器或 VPN。

下文保留的第二轮源码修复与压力测试说明针对历史脚本版本；Bug 清单、15 项审查对应关系和当时的验证边界见 [第二轮审查记录](REVIEW_ROUND2.md)，不能作为 v3.2 发行验收结果。

**安装报“同名任务的所有者/权限不匹配”**：已修复旧版把任务短用户名、CIM 数字枚举误判为不匹配的问题。从最新完整包重新运行 `Install.bat` 即可重试，保留现有配置与最初备份；不需要先删任务、删安装目录或改用管理员账户。具体原因、保护边界和诊断见 [任务身份校验修复](TASK_OWNERSHIP_FIX.md)。截图中的旧通用错误无法单独证明实际触发字段；若新版仍拒绝，请按诊断中的具体字段处理。

## 历史脚本包安装入口

本节记录旧脚本包的安装命令与保护边界。已有安装的候选版升级应使用 EXE 的“设置 → 高级操作 → 修复安装 / 升级”，保留用户规则与最初备份；不要先卸载。首次启用前检查当前 v3.2 的暂停意图及配置向导。安装/启动进程与允许代理写入是不同操作。

1. 解压完整项目到本地目录，支持中文、空格和 `!`。如果 Windows 将下载文件标记为来自 Internet，确认来源和内容后在 ZIP 属性中解除锁定，再解压；组织策略禁止脚本/WSH 时联系管理员，不关闭安全防护。
2. 使用自己的普通交互用户双击 `Install.bat`，不要以 SYSTEM 或另一管理员账户安装。默认复制到 `%LOCALAPPDATA%\WiFiProxySwitcher`。BAT 安装控制台可见，正常监控完全由隐藏的 VBS 入口启动。
3. 安装会保存原代理三个注册表值、创建该用户专属登录任务并立即启动，收到监控心跳后返回。用 `Status.bat` 查看 `WatcherRunning`、任务退出码、心跳及实际代理状态，检查日志中的 `Keep` / `Retry` 原因。
4. 在 Windows 设置 → 网络和 Internet → 代理，确认手动开关、网关地址、7890 和本地地址绕过复选框。权限错误时按下文处理。

自定义**专用空目录**安装：

```bat
Install.bat -InstallDir "D:\我的工具\WiFi 代理"
```

重复安装保留原始备份、已安装 `config.json` 及它原有的归属哈希，修复/更新本工具脚本与任务。改过的脚本在覆盖前保存到 `user-backups`；新版本文件与非工具文件同名时拒绝覆盖。首次安装使用相邻暂存目录，完整预检后移入目标；中途复制失败不留下半安装目标。已有安装不能直接迁移；先卸载再指定新目录。安装拒绝覆盖普通非空目录、网络共享、链接及联接点；专用安装目录 ACL 仅给当前用户、SYSTEM 和 Administrators 完全控制。任务创建失败时保留备份和安装记录，可修复策略后重试。安装文件不需要联网下载。安装路径支持中文、空格、`!`、`&`、括号等；成对 `%NAME%` 形式的安装路径因任务计划程序会展开环境变量而明确拒绝，请使用其他目录。VBS 自身用当前目录中的固定相对脚本名，避免把源目录插入可展开的 Run 命令。

## 操作入口

| 文件 | 行为 |
|---|---|
| `Install.bat` | 安装、保存原配置、注册登录任务、立即启动 |
| `Start.bat` | 启用并启动现有任务；已运行则不重复启动 |
| `Stop.bat` | 禁用登录任务、停止监控；保留当前代理状态 |
| `RestoreProxy.bat` | 紧急停止、禁用任务并恢复安装前手动配置 |
| `Uninstall.bat` | 停监控、恢复、删除专属任务和启动指针、按清单移除文件 |
| `Status.bat` | 当前用户安装、任务、进程锁、心跳、实际代理和自动代理标志 |
| `SilentLauncher.vbs` | 真正隐藏的控制/后台启动入口 |
| `Diagnose.bat` | 只读本机诊断，默认不连接代理端口；`-Probe` 明确开启诊断连接 |
| `tests\Run-Tests.bat` | 不改真实代理的测试套件 |

BAT 双击可能短暂出现控制台，不保证零闪烁。可双击 `SilentLauncher.vbs` 静默启动；所有日常控制也支持 VBS 参数：

```bat
wscript.exe //B //Nologo "D:\项目 中文\SilentLauncher.vbs" Install
wscript.exe //B //Nologo "D:\项目 中文\SilentLauncher.vbs" Start
wscript.exe //B //Nologo "D:\项目 中文\SilentLauncher.vbs" Stop
wscript.exe //B //Nologo "D:\项目 中文\SilentLauncher.vbs" Restore
wscript.exe //B //Nologo "D:\项目 中文\SilentLauncher.vbs" Uninstall
```

VBS 白名单参数不支持任意命令拼接。需要自定义目录/强制恢复等选项时使用 `Control.ps1 -Quiet` 搭配 `powershell.exe -WindowStyle Hidden`，或可见 BAT 入口。静默失败写入 `%LOCALAPPDATA%\WiFiProxySwitcher-Control\control-errors.log`（256 KiB，1 个归档）；静默 Status 将完整状态写入 `state\control-status.json`，监控心跳仍在 `state\status.json`。`SilentLauncher.vbs Diagnose` 将只读报告写入 `%LOCALAPPDATA%\WiFiProxySwitcher-Control\diagnostics.json`。批处理自动化设置 `WIFI_NO_PAUSE=1` 可关闭结尾 pause；退出码保留底层 PowerShell 的成功/失败。

## 后台引擎与历史脚本启动行为

任务名称为 `WiFiProxySwitcher-<当前用户 SID>`，根任务目录，仅当前用户 `Interactive` / `Limited`，不保存密码、不使用 SYSTEM、不请求不必要的提权。登录触发，启动目录为安装目录；电池允许、不因切换电池停止、无执行时限、`IgnoreNew` 防重复、异常退出间隔 1 分钟最多重启 999 次。VBS 等待真实监控进程退出并传递退出码，任务不会把正常启动后还在运行的脚本误认为完成。

WLAN ACM 通知和 .NET 网络地址变化事件唤醒检测，默认 5 秒轮询兜底覆盖 DHCP 与休眠唤醒。普通变化需两次一致快照且至少 400 ms；断开确认 2 秒。启动立即读取，路由采集前后核对 WLAN SSID 原始身份与事件 Generation，写入前再读一次防止混合快照和过期事件。DHCP/读取失败前 15 秒按 1 秒快速重试，随后按轮询间隔继续；事件可提前唤醒。Strict 完成稳定目标处理后才诊断。长时间暂停会使旧稳定状态和诊断失效；等待按最多 500 ms 小段检查停止请求。实际延迟还包括 NetTCPIP 查询时间与诊断限时，需实机测量。锁屏可运行，注销后任务终止，下次登录重启；跨进程用户命名互斥锁保证每用户单监控实例。

历史脚本命令 `Stop` 为持久停止（下次登录也不启动），`Start` 恢复登录自启；这与 v3.2 界面的“暂停”不同。界面暂停只停止自动代理写入并保留当前值，“直连”还会关闭手动代理；这些意图会持久保存。后台监控登录启动与托盘登录启动为独立设置。启用自动管理时，引擎会在下次检测纠正其他软件或手工对**手动代理**的修改；想保留手工设置，先暂停管理。

## 配置

源目录 `config.json` 仅用于首次安装，已有安装不得用仓库默认配置覆盖用户文件。v3.1/v3.2 后台支持验证后的配置热重载：界面保存时检查版本冲突并原子写入；“已保存”表示文件写入成功，“已应用”还要求同一配置 revision 的新鲜、兼容后台心跳及稳定网络。后台未应用时继续显示等待，不制造成功状态。无效配置保留上一份有效设置并给出错误。详情见 [配置热重载](CONFIG_HOT_RELOAD.md) 与 [迁移说明](CONFIG_MIGRATION.md)。历史旧引擎若不支持此协议，应先按升级流程更新，不能因磁盘脚本已更新就认为驻留旧进程具备新能力。

| 字段 | 默认值 / 含义 |
|---|---|
| `Whitelist` | 默认空数组；用户自定义免代理网络，完整名称匹配、忽略大小写，所有规则可编辑/删除 |
| `SchemaVersion`, `ManagementIntent`, `SetupComplete` | `2` / `Paused` / `false`；新安装先配置，再由用户启用管理 |
| `Port`, `Mode` | `7890`, `Strict`；可选 `Safe` |
| `PollSeconds` | 5 秒，允许 1–300 |
| `DebounceMilliseconds` | 400，允许 100–5000 |
| `DisconnectConfirmSeconds` | 2，允许 1–30 |
| `RetrySeconds`, `FastRetryWindowSeconds` | 1 / 15；快速重试间隔和窗口 |
| `PreferredInterfaceGuid` | 默认空；多无线网卡时可指定 GUID |
| `Diagnostics` | `Tcp`；可选 `None` / `Http` |
| `DiagnosticIntervalSeconds` | 60；同一链路诊断限频 |
| `DiagnosticTimeoutMilliseconds` | 1200；TCP 和 HTTP 状态行分别限时 |
| `HttpProbeUrl` | 默认空；仅 Http 模式要求，用户自己配置可信的 `http://` 测试 URL，不含凭据/查询/片段 |
| `SafeFailureThreshold` | 2 次连续明确失败后 Safe 关闭代理；检测恢复再开启 |
| `LogMaxBytes`, `LogArchives` | 每文件约 1 MiB，3 个归档；单条日志可能略越阈值 |

**Strict**：只要有效非白名单网关就设置，不等待诊断成功，也不因端口失败改规则。

**Safe**：未知诊断不改变原 SSID 规则；两次连续 TCP 拒绝/超时、无有效 HTTP 状态行或认证 407 才判不可用并关闭，继续限频重试。TCP 开放仅表示端口可连接，不能证明 HTTP 代理；Http 模式发送无凭据的显式 HTTP GET，2xx/3xx 表示该请求收到响应，不能证明所有网站或 HTTPS CONNECT 可用。5xx/其他失败可能来自目标站点，记为 Unknown，避免错误宣称代理坏了。已经确认不可用并关闭的 Safe 状态，不会因一次 Unknown 就重新启用；同一网络须等到积极检测成功，或链路身份变化后重新判定。Safe 可能绕过期望的代理，需用户明确选用。

多物理 Wi-Fi：指定首选 GUID 优先；否则所有候选都具有就绪路由时按 `RouteMetric + InterfaceMetric` 最小唯一值选取。相同成本或未就绪不猜测。每接口多默认路由按 RouteMetric 最低值选取；同成本不同网关拒绝。以太网、VPN、WSL 等默认路由不会参与 Wi-Fi 选择。纯有线、无无线连接按本项目规则关闭手动代理。

## 代理保存、恢复与卸载

`state\proxy-before-install.json` 保存安装前 `ProxyEnable` / `ProxyServer` / `ProxyOverride` 的存在性、值和注册表类型，首次备份不被重复安装覆盖。正常更新使用 LAN 的 WinINet per-connection options，保留 PAC/自动检测位，设置 `<local>`，通知、刷新后同时回读 WinINet 与注册表。恢复只恢复这三个手动值，**不恢复/覆盖运行期间用户改动的 PAC 或自动检测**；不改变 WinHTTP、DNS、路由、防火墙或适配器 IP。

卸载/紧急恢复先确认监控锁已释放，再比较当前手动值与工具最后一次成功写入。若检测到后来修改或崩溃导致写入记录未完成，**先停止并保留安装与备份，返回失败**，不会静默覆盖。检查备份与现设置后显式选择：

```bat
RestoreProxy.bat -ForceRestore
Uninstall.bat -ForceRestore
Uninstall.bat -KeepCurrentProxy
Uninstall.bat -DeleteLogs
```

`-ForceRestore` 明确允许覆盖当前手动值；`-KeepCurrentProxy` 明确卸载但保留当前值，二者互斥。默认保留轮转日志和被用户修改过的项目文件；`-DeleteLogs` 仅删工具日志，**不递归删除整个安装目录**。已安装 config 后来修改会按哈希保留。重复卸载无安装指针时无副作用。卸载用持久化 Uninstalling 阶段支持中断后重试；若指针已删除但清理中断，从完整新包执行 `Uninstall.bat -InstallDir "原安装目录"`。空目录、默认保留日志、用户修改文件与 user-backups 可保留，均不启动进程。专属启动项仅为本工具任务和 HKCU 安装指针，没有 Run 项或启动文件夹残留；静默控制错误日志不属于后台启动项，可手动删除。

不要删除/编辑 state 备份和清单。这里保存原代理及网络元数据，应按个人配置保护，分享日志前注意 SSID / GUID / IP 隐私。日志不记录密码、PAC URL、代理凭据或任意原有代理字符串；原始备份必须保留原手动值，受安装目录 ACL 保护。

## 诊断与限制

- Windows 11 新版本 WLAN 当前连接查询可能需要位置权限。错误 5 / `ERROR_ACCESS_DENIED` 时打开 设置 → 隐私和安全性 → 位置，按系统/组织政策允许位置及桌面应用访问，重启监控。权限不足不是断网，程序不写代理。位置图标/系统首次权限提示由 Windows 控制；本工具不自行弹窗、不绕过权限。只订阅 ACM，避免 MSM 的附加能力要求。
- WLAN AutoConfig 服务不可用、接口在关联中、网关尚未完成 DHCP、IP 不是 Preferred、默认路由过期/歧义：Keep + 日志 + 重试，不使用历史值。
- 不提供 netsh 文本或配置文件名兜底；非 UTF-8 SSID 以原始字节的十六进制身份表示，按非白名单处理；该显示文本禁止命中字符串白名单，避免编码替换或伪造显示文本误判。
- 检测 HKCU/HKLM 的常见代理管理策略；只要发现受管就拒绝写入。未涵盖所有 MDM/安全软件策略，API/注册表回读进一步发现不一致。组织禁止 WSH、PowerShell、Add-Type 或任务注册时不能承诺运行；交由管理员处理所需权限，不永久改执行策略。Bypass 仅限该进程，不绕过组策略、WDAC/AppLocker 或防病毒。
- PAC/自动检测保持不变并写警告；它们可能优先于手动代理，本工具不承诺消除这样的选路冲突。未修改 RAS/VPN 的独立拨号连接设置。
- 使用自身代理实现、忽略系统代理的程序不受本工具控制。需要认证的网关代理不在本工具功能范围内。
- 原生 API 和注册表变更不是跨程序事务；本工具验证回读、异常记录并重试，不能阻止其他代理管理程序同时写入。建议仅保留一个管理工具。
- PowerShell 进程内存、事件延迟、24 小时稳定性、用户任务创建权限和无窗口体验尚需 Windows 实测。没有承诺基于未测数据的资源指标。

## 历史测试说明与脚本包结构

在 Windows 5.1：双击 `tests\Run-Tests.bat`。测试只操作模拟对象、测试互斥锁、临时文件及 loopback TCP 服务，不触碰真实代理。Linux 云端：`bash tools/cloud-setup.sh`，工具下载固定 PowerShell 7.4.6 官方包并验证 SHA256，仅供开发验证。Linux 无法替代 Windows PowerShell 5.1 实机兼容测试。

```text
WiFiProxyPilot/
  Install.bat / Start.bat / Stop.bat / Uninstall.bat
  RestoreProxy.bat / Status.bat
  Control.ps1              安装、任务管理、恢复、卸载入口
  Diagnose.ps1 / Diagnose.bat  只读本机诊断
  ProxyWatcher.ps1         常驻监控、去重、防抖、诊断、代理验证
  SilentLauncher.vbs       隐藏启动并传递退出码
  config.json
  lib/Core.ps1             可注入纯规则、配置、文件与日志
  lib/Windows.ps1          结构化网卡/路由、注册表、诊断、互斥锁
  lib/Native.cs            WLAN/WinINet PInvoke 与事件
  lib/Monitor.ps1          实际监控循环，可注入系统边界测试
  lib/Lifecycle.ps1        实际安装/启动/恢复/卸载函数
  tests/Run-Tests.ps1 / Run-Tests.bat / Round2.Tests.ps1 / TaskOwnership.Tests.ps1 / ProbeServer.cs
  tools/cloud-setup.sh
  docs/ARCHITECTURE.md / WINDOWS_ACCEPTANCE.md / TEST_RESULTS.md
  docs/REVIEW_ROUND2.md / test-results.json
  docs/TASK_OWNERSHIP_FIX.md  安装时任务身份校验误判的修复与重试
  state/                  安装时生成：备份、清单、心跳、停止标志
  logs/                   安装时生成：有界 JSONL 日志
  user-backups/            更新时生成：被用户修改过的旧脚本
```

架构与官方资料见 [设计说明](ARCHITECTURE.md)，云端证据见 [测试结果](TEST_RESULTS.md)，20 个场景的实机操作见 [Windows 验收](WINDOWS_ACCEPTANCE.md)。
