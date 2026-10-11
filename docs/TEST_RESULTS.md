# 测试证据

验证日期：2026-10-12（Asia/Shanghai）。运行环境为云端 Debian 13 x86_64、PowerShell 7.4.6，**不是 Windows 11**。

执行：`bash tools/cloud-setup.sh`。安装工具包来自 PowerShell 官方 v7.4.6 release；对官方 hashes.sha256 验证通过，SHA256：`6f6015203c47806c5cc444c19d8ed019695e610fbd948154264bf9ca8e157561`。Windows 安装不下载该包。

当前套件实际执行 **46 项，46 通过，0 失败**。机器可读报告见 `test-results.json`。该报告列明每个用例；新增用例后以最终生成报告为准。

| 类别 | 云端证据 | 实机边界 |
|---|---|---|
| SSID 白名单、大小写、相似名、网关 A/B/同 SSID DHCP 变化 | 执行生产纯规则函数，注入模拟快照 | WLAN 真实 SSID 读取未执行 |
| 物理接口绑定、VPN 干扰、自身 IP、IPv6、过期/歧义路由、读取失败 | 执行生产 Get-NetworkSnapshot，替换 NetTCPIP/WLAN 采集对象 | 真正 WLAN/NetTCPIP 调用未执行 |
| 快速切换、防抖、断开确认、重复状态去重 | 可控时钟与模拟目标执行 | 事件到达、睡眠/登录 UI 延迟未执行 |
| Strict/Safe 目标、恢复冲突保护 | 生产纯函数执行 | 真正注册表/WinINet 更新与恢复未执行 |
| TCP 开放/拒绝、HTTP 成功/407/非协议/5xx | 实际 loopback TCP 客户端与测试服务，运行生产诊断函数 | 未探测用户真实网关，不证明真实代理可用 |
| 单实例互斥 | 实际父/子进程命名互斥排他 | Windows Global SID 锁、多会话与任务启动未执行 |
| PowerShell 文件 | 全文件 parser 语法检查与常见 5.1 禁用语法 token 检查 | 7.4 parser 不能替代 5.1 引擎运行 |
| Native.cs | 以 C# 5 语言版本编译；x64 结构大小断言 | Windows DLL 加载/调用与 .NET Framework 编译器未执行 |
| 中文空格路径、原子 JSON、日志轮转 | Linux 实际临时文件 I/O 与边界检查 | Windows ACL、文件锁、BAT/WSH 引号未执行 |
| 登录任务、电源、重启、VBS 等待/隐藏、BAT 路径 | 只做静态配置契约检查 | 全部需 Windows 本机验收 |
| 卸载 | 恢复冲突规则有模拟测试，清单/归属逻辑代码检查 | 完整安装→停止→恢复→删除任务/文件未实测 |

曾发现两项失败：PowerShell 把 File.Replace 的 `$null` string 参数变为空串；已改用 `[NullString]::Value`，重新执行相关用例及完整套件通过。没有删断言、修改目标或跳过用例来获得通过。

未执行且不能声称通过：Windows 11 API/注册表/UI、Windows PowerShell 5.1、用户任务注册权限、登录/唤醒事件、24 小时稳定性、真实后台零窗口、完整卸载集成。请按 `WINDOWS_ACCEPTANCE.md` 记录实机结果。
