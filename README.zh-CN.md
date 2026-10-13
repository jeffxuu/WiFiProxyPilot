<div align="center">
  <h1>WiFi Proxy Pilot</h1>
  <h3>Windows 智能 Wi-Fi 代理切换工具</h3>
  <p>轻量、现代的 Windows 工具，根据 Wi-Fi SSID、网关地址和用户自定义规则自动切换系统代理。</p>

  ![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)
  ![.NET 8](https://img.shields.io/badge/.NET-8-512BD4)
  ![WPF](https://img.shields.io/badge/UI-WPF-6557E8)
  [![Release](https://img.shields.io/github/v/release/jeffxuu/WiFiProxyPilot?include_prereleases)](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.3.0-beta.1)
  [![MIT License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
  [![GitHub Stars](https://img.shields.io/github/stars/jeffxuu/WiFiProxyPilot?style=flat)](https://github.com/jeffxuu/WiFiProxyPilot/stargazers)
</div>

**[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Tiếng Việt](README.vi.md)**

**Wi-Fi 切换，代理随行。** 在普通 Wi-Fi 上使用网关提供的代理，在你指定的网络上直连。通过现代 WPF 桌面界面或系统托盘管理。

> **v3.3.0-beta.1 是预发布候选版本。** 本轮新增 Windows 原生窗口按钮、真正的当前用户 Setup 安装程序，以及完整的英文／简体中文界面资源。请查看[验收记录](docs/TEST_RESULTS_V3_3.md)中的实际结果和待验证项；编译、预览和截图不能替代安装与代理管理验收。已有 v3.2 Release 保留。

## 软件截图

下方保留的是 **v3.2 历史布局**，网络数据为模拟；旧窗口按钮不代表 v3.3 的原生 Windows 标题栏。v3.3 完整窗口截图只会来自解锁的实际桌面或通过检查的 CI 抓图，不制作虚假的安装成功画面。实际控件操作证据见验收记录。

![Overview — 实际 WPF 应用，模拟网络](docs/images/dashboard.png)

| Wi-Fi 规则 | 设置 |
| --- | --- |
| ![Wi-Fi 规则预览](docs/images/rules.png) | ![设置预览](docs/images/settings.png) |

<details>
<summary>深色主题预览</summary>

![深色主题 — 较早的 WPF 首页布局](docs/images/dashboard-dark.png)

</details>

![系统托盘菜单 — 当前应用，隔离模拟状态](docs/images/tray.png)

所有图片都是隔离测试环境中的真实软件截图，**不能作为真实代理连通的证据**。深色截图采用较早的首页布局。托盘图片来自当前应用实际显示的菜单，使用隔离模拟状态。

## 核心功能

- 识别当前连接的 Wi-Fi，按完整 SSID 匹配用户规则，忽略大小写。
- 自动读取当前物理 Wi-Fi 接口的 **IPv4 默认网关**，结合你配置的代理端口，默认端口为 `7890`。
- 为指定网络设置直连规则。新安装**不包含内置 Wi-Fi 规则**，每条规则都能编辑或删除。
- 保留简洁 WPF 内容设计，采用 Windows 原生窗口按钮，提供浅色／深色主题、系统托盘及独立后台 Watcher。
- 根据 Windows 显示语言选择英文或简体中文，支持持久化的语言设置。
- 提供当前用户 Inno Setup 安装向导、开始菜单入口和有结果校验的卸载流程。
- 分别呈现自动管理、Windows 手动代理状态和可选 TCP／HTTP 诊断。代理开启不等于互联网可用。
- 原子保存配置，明确区分“已保存”和“后台已应用”。
- 保留最初的手动代理备份，保护用户或其他应用后续修改的设置。
- 提供 MIT 许可的源码，便于审计和参与贡献。

## 下载与安装

**[下载 Windows x64 安装程序 — v3.3.0-beta.1](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.3.0-beta.1/WiFiProxyPilot-Setup-x64.exe)**

[候选版本与发布说明](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.3.0-beta.1) · [SHA256 校验文件](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.3.0-beta.1/SHA256.txt) · [Windows 构建与验收](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml)

Setup EXE 才是安装程序，会创建开始菜单及 Windows“已安装的应用”入口，并提供可选桌面快捷方式。安装后的程序名为 **WiFiProxyPilot.exe**。候选版本上传发布后，以上 v3.3 下载链接才会可用；构建与验收状态分别记录。

目标平台为 **Windows 11 x64**，需要 Windows PowerShell 5.1、WLAN 服务和 Windows Script Host。自包含 EXE 无需另外安装 .NET、Python、Node.js 或 WebView2。不声称已验证更广泛的 Windows 兼容性。组织策略可能限制 WLAN 信息、代理设置或计划任务。当前构建未签名，请保持 Windows 安全保护开启。

下载后与随附的 `SHA256.txt` 核对哈希：

```powershell
Get-FileHash .\WiFiProxyPilot-Setup-x64.exe -Algorithm SHA256
```

请以日常使用的普通交互用户运行 Setup，默认安装到 `%LOCALAPPDATA%\Programs\WiFiProxyPilot`，不请求不必要的管理员权限。**安装和打开软件不等于启用代理管理**；首次启用仍需检查端口、Wi-Fi 规则，并确认开启。不要使用另一管理员的账户替你的日常账户安装。

[便携包](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.3.0-beta.1/WiFiProxyPilot-Portable-x64.zip)用于解压运行，是次要下载选项。它不是安装器，解压本身不注册“已安装的应用”或创建快捷方式。确认启用后台时沿用原有当前用户引擎安装机制；需要统一安装、升级和卸载管理时请使用 Setup。详见[安装、升级与卸载说明](docs/INSTALLATION_V3_3.md)。

## 快速开始与首次配置

1. **下载安装程序**，核对哈希，完成 Setup 后从开始菜单打开。
2. **配置**已有网关代理服务的监听端口，并添加需要直连的 Wi-Fi 名称。
3. 确认软件将管理的设置后，**开启自动切换**。

**网关上必须实际运行代理服务。WiFi Proxy Pilot 不提供代理服务器或 VPN 节点。** 使用 Android 热点时，程序会自动读取当前 IPv4 网关；你需要设置手机代理应用的监听端口，并确保其允许通过热点连接的 Windows 设备访问。热点本身不等于代理服务。

## 工作原理

```text
连接 Wi-Fi → 读取稳定的 SSID／接口快照 → 匹配用户规则
  ├─ 命中直连规则 → 关闭 Windows 手动代理
  └─ 未命中规则   → 读取当前 Wi-Fi 的 IPv4 网关
                    → 应用网关地址 + 配置的端口
```

后台在应用变更前重新核对当前网络，避免切换 Wi-Fi 后继续使用旧网关。SSID 无法确认、路由缺失或接口存在歧义时，保留现有设置，说明原因并重试。确认断开连接后关闭手动代理。PAC 和自动检测保留原值，仍可能影响应用的实际路由。

## Wi-Fi 规则管理

进入**“Wi-Fi 规则”**，可添加、重命名、删除网络，或添加当前可靠识别的网络。支持空规则列表。匹配采用完整名称的 `OrdinalIgnoreCase` 比较，不匹配前缀或子串。合法空格原样保留；名称须为 1–32 个 UTF-8 字节，不含控制字符。

**“保存并应用”**检查并发修改后原子写入。“已保存”确认文件写入；“已应用”需要新鲜、兼容的 Watcher 心跳确认同一配置版本，并完成当前网络的稳定确认。尚未满足时显示等待后台应用。取消可放弃未保存的修改。已删除的规则不会被后台悄悄补回。

## 系统托盘与代理模式

| 操作 | 作用 |
| --- | --- |
| 开启自动切换 | 重新采集网络，按用户规则管理手动代理 |
| 暂停 | 停止自动代理写入；保留当前代理设置 |
| 恢复直连 | 暂停管理，仅关闭 Windows 手动代理 |
| 立即检测 | 请求新的网络观测，并经过稳定确认 |
| 关闭窗口 | 默认隐藏到托盘；后台继续运行 |
| 退出界面 | 关闭 GUI／托盘；独立后台继续运行 |
| 恢复安装前配置 | 停止管理，通过冲突检查安全恢复最初备份 |

暂停和直连意图在 GUI 重启及重新登录后继续保留。后台登录启动和托盘自启是两个独立设置。

**Strict** 按选定规则应用代理，探测失败时报告原因，不悄悄关闭代理。**Safe** 可在诊断连续失败达到设定阈值后回退直连，因此部分流量可能绕过代理。未知诊断不代表服务恢复。TCP 诊断只证明端口能够连接；HTTP 诊断会通过代理实际请求你配置的 HTTP 测试 URL。两者都不能保证所有网站和应用正常工作。

## 恢复与卸载

最初的手动代理备份保存在后台数据目录中的 `state/proxy-before-install.json`。程序文件和后台数据采用独立的归属记录。Setup 保留旧版数据根目录、SSID 规则、管理意图、任务归属及最初备份，并移除已经核实归属的旧桌面／卸载记录，避免与 Inno Setup 并行竞争。请勿公开这些本地文件。

升级时直接运行新 **Setup EXE**。不要先卸载，也不要用仓库默认配置覆盖个人配置。全新账户安装程序不会自动安装或启动 Watcher；已有启用状态的升级则保留原管理意图。详见[安装与迁移说明](docs/INSTALLATION_V3_3.md)及[配置迁移](docs/CONFIG_MIGRATION.md)。

从 **Windows 设置 → 应用 → 已安装的应用 → WiFi Proxy Pilot**，或软件的**设置 → 高级操作 → 卸载**进入卸载向导。向导提供恢复最初手动代理和保留当前代理两种选择。检测到后续外部修改时，明确显示**恢复原配置／保留当前配置／取消**。取消保留运行中的界面、后台和安装状态。

向导另行询问是否保留已知用户数据。保留的规则、配置、最初备份及日志复制到 `%LOCALAPPDATA%\WiFiProxyPilot-Retained`。未知文件、被用户修改的程序文件和升级备份继续受到保护。清理只针对核实归属的任务、启动记录及已知文件，不递归清空整个应用数据目录。生命周期校验失败时，按[故障排查](docs/TROUBLESHOOTING_V3_3.md)处理后重试。

## 程序界面语言

软件界面支持 **English（en-US）**和**简体中文（zh-CN）**。**设置 → 语言 → 跟随系统**为默认选项，通过 `CurrentUICulture` 读取 Windows 显示语言，不用地区或日期格式猜测。其他未支持语言回退英文；本版本对繁体中文 Windows 明确回退简体中文。

主动选择 English 或简体中文后，已创建的页面、托盘菜单和后续对话框立即刷新，选择保存后重启仍有效。语言偏好及未确认的首次配置草稿可以在启用后台之前持久化。十一种 README 翻译属于文档能力，不代表软件支持十一种界面语言。

在 `/preview` 或隔离数据模式中，主界面始终显示**演示模式**提示，明确网络为模拟。代理、自动切换、后台及安装操作禁用；演示模式不会宣称真实代理已经切换。

## 安全与隐私

- SSID、代理配置、状态和日志在本机处理；无需云端账户或分析服务。
- 程序不收集 Wi-Fi 密码。可选诊断会连接所选代理；HTTP 模式还会访问你配置的 URL。
- 保留原始代理备份；安装及任务操作遵守当前用户的身份和权限检查。
- 程序管理当前用户的 Windows **手动代理**，不修改 DNS、路由或防火墙规则。
- 日志和诊断可能包含网络标识，分享前请检查并脱敏。

安全问题的报告方式见 [SECURITY.md](SECURITY.md)。

## 常见问题

**如何在 Windows 11 上按 Wi-Fi 自动切换代理？** 配置网关代理端口，添加需要直连的 SSID，然后开启自动切换。后台会稳定确认 Wi-Fi 变化，并管理当前用户的 Windows 手动代理设置。

**如何将 Android 热点网关用作 Windows 代理？** 在手机上运行独立代理服务，允许热点连接的设备访问，并在 Pilot 中填写监听端口。网关从当前 Wi-Fi 接口自动发现。无法访问时检查手机上的代理服务和防火墙。

**WiFi Proxy Pilot 是否包含 VPN？** 不包含。它管理 Windows 手动代理配置，你需要自行提供服务。使用自有代理或忽略 Windows 设置的应用可能表现不同。

**代理已开启，为什么互联网仍不可用？** 网关可能没有代理服务，端口可能有误，服务可能已停止，或目标网站访问失败。请单独查看 TCP／HTTP 诊断。暂停保留当前设置，直连关闭手动代理；PAC 仍可能影响流量。

**如何让特定 Wi-Fi 绕过代理？** 将完整 SSID 添加到“Wi-Fi 规则”，保存并应用。每条规则都能编辑或删除；空列表合法。

**如何恢复 Windows 代理设置？** 选择“恢复安装前配置”，并审查后续外部修改产生的冲突。直连只关闭手动代理，不恢复原来的服务器地址和绕过列表。

**关闭窗口后，程序还会运行吗？** 会。X 默认隐藏到托盘。退出 GUI 后独立后台仍会运行；需要改变后台管理时，使用暂停或恢复操作。

**为什么无法读取当前网络？** WLAN／位置权限、组织策略、路由缺失、后台停止或心跳过期都可能影响可靠状态。界面显示原因和上次有效观测，不把旧数据当作当前数据。

**哪些行为已经测试？** 见 [v3.3 验收记录](docs/TEST_RESULTS_V3_3.md)、[v3.2 性能基线](docs/PERFORMANCE_V3_2.md)及[发布检查](docs/RELEASE_CHECKLIST.md)。实际 UI 操作、一次性 Windows 安装／WinINet 测试、设备限制及实测性能分别记录；未执行项目不写为通过。

## Star History

如果 WiFi Proxy Pilot 让你的日常工作更轻松，欢迎为项目点一个 Star。

<a href="https://star-history.com/#jeffxuu/WiFiProxyPilot&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
    <img alt="WiFi Proxy Pilot Star History" src="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
  </picture>
</a>

官方实时 SVG 使用本仓库真实的 GitHub 数据。没有星标活动时，空白历史属于正常结果。不会伪造星标或增长，也不会用虚构数据替代空白历史。参考[官方嵌入说明](https://www.star-history.com/blog/how-to-use-github-star-history/)。

## 贡献与路线图

欢迎具有仓库访问权限的用户提交 Issues 和 Pull Requests。请说明构建版本、预期／实际行为，并附脱敏证据。Windows 构建和审查流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。不要提交个人配置、代理备份、凭据或未脱敏日志。

本候选版本加入统一安装归属、双语资源及真实控件自动化。硬件相关 Wi-Fi、DPI／Snap 等剩余验收限制列于测试记录。自动更新尚未实现。

使用 `global.json` 中指定的 SDK 和 Windows PowerShell 构建：

```powershell
powershell.exe -NoProfile -File tests\Run-Tests.ps1 -ResultPath artifacts\engine-results.json
powershell.exe -NoProfile -File release\Build.ps1
```

构建生成 `WiFiProxyPilot-Setup-x64.exe`、`WiFiProxyPilot-Portable-x64.zip`和 `SHA256.txt`，不会自动安装或修改构建机代理。安装版使用非单文件的自包含运行时，避免启动时重复解包；Inno Setup 7.1.0 通过哈希和上游签名锁定。内部 `WiFiProxySwitcher` 数据、注册表、互斥锁及任务标识保留兼容。详见[构建教程](docs/INSTALLATION_V3_3.md#build-and-verify)。

## 许可证

项目源码采用 [MIT](LICENSE) 许可。第三方材料遵循各自条款，见[第三方声明](docs/THIRD_PARTY_NOTICES.md)。使用 Windows 已安装的系统字体，不重新分发字体文件。
