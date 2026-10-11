# Windows 11 Wi-Fi 智能代理切换工具

根据真实 Wi-Fi SSID 和该物理接口的当前 IPv4 默认路由，控制**当前用户的 Windows 手动代理**。运行端仅依赖 Windows 11 x64 自带的 Windows PowerShell 5.1、WLAN API、WinINet、任务计划程序与 Windows Script Host，不需要 Python、Node.js 或第三方组件。

默认规则：`MC-Office` / `Meituan` 完整名称按 OrdinalIgnoreCase 匹配时关闭；其他 Wi-Fi 使用该接口 IPv4 默认网关和端口 `7890`，绕过列表保留现有条目并加入 `<local>`；确认断网关闭。SSID/路由读取失败时保持现状并重试。关闭时不清空代理地址或绕过列表。

**验证边界：云端 Linux 的模拟与静态检查已通过；尚未在真实 Windows 11 / PowerShell 5.1 验证 WLAN、注册表、任务或设置 UI。请先完成 [本机验收](docs/WINDOWS_ACCEPTANCE.md)。** 网关本身不保证有代理服务，Strict 模式可能使没有代理的网络无法上网。

## 快速安装

1. 解压完整项目到本地目录，支持中文、空格和 `!`。如果 Windows 将下载文件标记为来自 Internet，确认来源和内容后在 ZIP 属性中解除锁定，再解压；组织策略禁止脚本/WSH 时联系管理员，不关闭安全防护。
2. 使用自己的普通交互用户双击 `Install.bat`，不要以 SYSTEM 或另一管理员账户安装。默认复制到 `%LOCALAPPDATA%\WiFiProxySwitcher`。BAT 安装控制台可见，正常监控完全由隐藏的 VBS 入口启动。
3. 安装会保存原代理三个注册表值、创建该用户专属登录任务并立即启动，收到监控心跳后返回。用 `Status.bat` 查看 `WatcherRunning`、任务退出码、心跳及实际代理状态，检查日志中的 `Keep` / `Retry` 原因。
4. 在 Windows 设置 → 网络和 Internet → 代理，确认手动开关、网关地址、7890 和本地地址绕过复选框。权限错误时按下文处理。

自定义**专用空目录**安装：

```bat
Install.bat -InstallDir "D:\我的工具\WiFi 代理"
```

重复安装保留原始备份和已安装 `config.json`，修复/更新本工具脚本与任务。已有安装不能直接迁移；先卸载再指定新目录。安装拒绝覆盖普通非空目录、网络共享、链接及联接点；专用安装目录 ACL 仅给当前用户、SYSTEM 和 Administrators 完全控制。任务创建失败时保留备份和安装记录，可修复策略后重试。安装文件不需要联网下载。

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
| `tests\Run-Tests.bat` | 不改真实代理的测试套件 |

BAT 双击可能短暂出现控制台，不保证零闪烁。可双击 `SilentLauncher.vbs` 静默启动；所有日常控制也支持 VBS 参数：

```bat
wscript.exe //B //Nologo "D:\项目 中文\SilentLauncher.vbs" Install
wscript.exe //B //Nologo "D:\项目 中文\SilentLauncher.vbs" Start
wscript.exe //B //Nologo "D:\项目 中文\SilentLauncher.vbs" Stop
wscript.exe //B //Nologo "D:\项目 中文\SilentLauncher.vbs" Restore
wscript.exe //B //Nologo "D:\项目 中文\SilentLauncher.vbs" Uninstall
```

VBS 白名单参数不支持任意命令拼接。需要自定义目录/强制恢复等选项时使用 `Control.ps1 -Quiet` 搭配 `powershell.exe -WindowStyle Hidden`，或可见 BAT 入口。静默失败写入 `%LOCALAPPDATA%\WiFiProxySwitcher-Control\control-errors.log`（256 KiB，1 个归档）；静默 Status 的结果可直接从 `state\status.json` 和日志读取。批处理自动化设置 `WIFI_NO_PAUSE=1` 可关闭结尾 pause；退出码保留底层 PowerShell 的成功/失败。

## 自启动与运行行为

任务名称为 `WiFiProxySwitcher-<当前用户 SID>`，根任务目录，仅当前用户 `Interactive` / `Limited`，不保存密码、不使用 SYSTEM、不请求不必要的提权。登录触发，启动目录为安装目录；电池允许、不因切换电池停止、无执行时限、`IgnoreNew` 防重复、异常退出间隔 1 分钟最多重启 999 次。VBS 等待真实监控进程退出并传递退出码，任务不会把正常启动后还在运行的脚本误认为完成。

WLAN ACM 通知和 .NET 网络地址变化事件唤醒检测，默认 5 秒轮询兜底覆盖 DHCP 与休眠唤醒。普通变化需两次一致快照且至少 400 ms；断开确认 2 秒。启动立即读取，写入前再读一次防止过期事件。DHCP/读取失败前 15 秒按 1 秒快速重试，随后按轮询间隔继续；事件可提前唤醒。实际延迟还包括 NetTCPIP 查询时间与诊断限时，需实机测量。锁屏可运行，注销后任务终止，下次登录重启；跨进程用户命名互斥锁保证每用户单监控实例。

`Stop` 为持久停止（下次登录也不启动），`Start` 恢复登录自启。监控运行期间会在下次检测纠正其他软件或手工对**手动代理**的修改，这是本工具的管理行为。想保留手工设置，先停止监控。

## 配置

安装后修改安装目录 `config.json`，执行 Stop / Start 使其生效。源目录配置仅用于首次安装。

| 字段 | 默认值 / 含义 |
|---|---|
| `Whitelist` | `MC-Office`, `Meituan`，精确、无大小写区别；空数组允许 |
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

**Safe**：未知诊断不改变原 SSID 规则；两次连续 TCP 拒绝/超时、无有效 HTTP 状态行或认证 407 才判不可用并关闭，继续限频重试。TCP 开放仅表示端口可连接，不能证明 HTTP 代理；Http 模式发送无凭据的显式 HTTP GET，2xx/3xx 表示该请求收到响应，不能证明所有网站或 HTTPS CONNECT 可用。5xx/其他失败可能来自目标站点，保持 Unknown，避免错误宣称代理坏了。Safe 可能绕过期望的代理，需用户明确选用。

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

`-ForceRestore` 明确允许覆盖当前手动值；`-KeepCurrentProxy` 明确卸载但保留当前值，二者互斥。默认保留轮转日志和被用户修改过的项目文件；`-DeleteLogs` 仅删工具日志，**不递归删除整个安装目录**。已安装 config 后来修改会按哈希保留。重复卸载无安装指针时无副作用。专属启动项仅为本工具任务和 HKCU 安装指针，没有 Run 项或启动文件夹残留；静默控制错误日志不属于后台启动项，可手动删除。

不要删除/编辑 state 备份和清单。这里保存原代理及网络元数据，应按个人配置保护，分享日志前注意 SSID / GUID / IP 隐私。日志不记录密码、PAC URL、代理凭据或任意原有代理字符串；原始备份必须保留原手动值，受安装目录 ACL 保护。

## 诊断与限制

- Windows 11 新版本 WLAN 当前连接查询可能需要位置权限。错误 5 / `ERROR_ACCESS_DENIED` 时打开 设置 → 隐私和安全性 → 位置，按系统/组织政策允许位置及桌面应用访问，重启监控。权限不足不是断网，程序不写代理。位置图标/系统首次权限提示由 Windows 控制；本工具不自行弹窗、不绕过权限。只订阅 ACM，避免 MSM 的附加能力要求。
- WLAN AutoConfig 服务不可用、接口在关联中、网关尚未完成 DHCP、IP 不是 Preferred、默认路由过期/歧义：Keep + 日志 + 重试，不使用历史值。
- 不提供 netsh 文本或配置文件名兜底；非 UTF-8 SSID 字节拒绝识别，避免编码替换导致错误白名单。非 UTF-8 SSID 的设备需单独改进后使用。
- 检测 HKCU/HKLM 的常见代理管理策略；只要发现受管就拒绝写入。未涵盖所有 MDM/安全软件策略，API/注册表回读进一步发现不一致。组织禁止 WSH、PowerShell、Add-Type 或任务注册时不能承诺运行；交由管理员处理所需权限，不永久改执行策略。Bypass 仅限该进程，不绕过组策略、WDAC/AppLocker 或防病毒。
- PAC/自动检测保持不变并写警告；它们可能优先于手动代理，本工具不承诺消除这样的选路冲突。未修改 RAS/VPN 的独立拨号连接设置。
- 使用自身代理实现、忽略系统代理的程序不受本工具控制。需要认证的网关代理不在本工具功能范围内。
- 原生 API 和注册表变更不是跨程序事务；本工具验证回读、异常记录并重试，不能阻止其他代理管理程序同时写入。建议仅保留一个管理工具。
- PowerShell 进程内存、事件延迟、24 小时稳定性、用户任务创建权限和无窗口体验尚需 Windows 实测。没有承诺基于未测数据的资源指标。

## 测试与文件结构

在 Windows 5.1：双击 `tests\Run-Tests.bat`。测试只操作模拟对象、测试互斥锁、临时文件及 loopback TCP 服务，不触碰真实代理。Linux 云端：`bash tools/cloud-setup.sh`，工具下载固定 PowerShell 7.4.6 官方包并验证 SHA256，仅供开发验证。Linux 无法替代 Windows PowerShell 5.1 实机兼容测试。

```text
WiFi-test/
  Install.bat / Start.bat / Stop.bat / Uninstall.bat
  RestoreProxy.bat / Status.bat
  Control.ps1              安装、任务管理、恢复、卸载
  ProxyWatcher.ps1         常驻监控、去重、防抖、诊断、代理验证
  SilentLauncher.vbs       隐藏启动并传递退出码
  config.json
  lib/Core.ps1             可注入纯规则、配置、文件与日志
  lib/Windows.ps1          结构化网卡/路由、注册表、诊断、互斥锁
  lib/Native.cs            WLAN/WinINet PInvoke 与事件
  tests/Run-Tests.ps1 / Run-Tests.bat / ProbeServer.cs
  tools/cloud-setup.sh
  docs/ARCHITECTURE.md / WINDOWS_ACCEPTANCE.md / TEST_RESULTS.md
  state/                  安装时生成：备份、清单、心跳、停止标志
  logs/                   安装时生成：有界 JSONL 日志
```

架构与官方资料见 [设计说明](docs/ARCHITECTURE.md)，云端证据见 [测试结果](docs/TEST_RESULTS.md)，20 个场景的实机操作见 [Windows 验收](docs/WINDOWS_ACCEPTANCE.md)。
