# v3.1 验证结果与未验证项

测试运行于 Windows 11 Enterprise 10.0.26200、Windows PowerShell 5.1.26100.8115、.NET SDK 8.0.425。用户明确选择本轮只做模拟验证、构建和 PR，不授权真实安装/代理/计划任务修改。没有运行真实切网验收。

基线：原 PowerShell 103/103，原 C# 22/22 全部通过。新增 C# 后 37/37 通过，本机 Windows 桌面冒烟 17/17。GitHub Windows CI 的 08c5e74 提交完成全部 PowerShell 113/113、C# 37/37、隔离桌面及 EXE/ZIP 打包和上传，证据见 docs/evidence/ci-v31.json 和对应 Actions 附件。该次运行仅草稿 Release 步骤因内联中文脚本被 PS 5.1 误读而失败，已改用 pwsh；不将整次 workflow 标为成功。

| 分类 | 验证范围 | 真实性边界 |
| --- | --- | --- |
| C# 单元/文件模拟 | 缓存提取/命中/损坏/额外文件/版本隔离、SSID、原子保存、有效备份、JSON 转义、revision 冲突、快速保存 | 真文件系统，临时目录；不安装真实引擎 |
| PowerShell 生产函数模拟 | 精确名单、当前网关、断开确认、Strict/Safe、夹读、冲突恢复、任务 SID 归属、热加载、暂停及升级/自启项保护 | 原生产代码 + 注入网络/注册表/任务服务；TCP/HTTP 用 loopback 测试服务 |
| Windows 桌面冒烟 | 真 WinForms/NotifyIcon、X 隐藏、重新打开、单实例事件、真实 UI 添加/删除/保存/取消、可读及大量日志、合成 100/125/150/200% 页面截图 | 独立 fixture，代理和任务命令显式禁止；TaskbarCreated 仅向测试监听窗口发送 |
| 启动性能 | 新提取目录、缓存命中、首次绘制和状态、再次 EXE 打开、CPU/内存 | 同一真实设备的隔离状态；OS 冷缓存和外部扫描未受控 |
| 真实网络/任务验收 | 未执行 | 尚未授权，不列为通过 |

修复过程中暴露的失败没有跳过：PS 5.1 无 BOM 新文件乱码已修正；配置备份路径数组表达式已修正；异步 UI 保存后的启用状态/线程调度问题通过显式 WinForms SynchronizationContext 和 busy 状态顺序修复；旧 R2 大量文件 fixture 清理偶发 `directory is not empty`，增加仅限唯一临时测试目录的有界清理重试，未重试或放宽产品断言。Productization 的版本路径断言按实际新版本更新，其余条件保留。

待人工验收：

- 登录后 Watcher 与托盘各自启用/关闭偏好及只有一个监控实例；旧版升级时真实 config/原始备份保留。
- 实际 XiaoMi 名单增删、热更新及新普通 Wi-Fi 的真实 IPv4 网关代理；中文和空格 SSID 的系统真实读取权限。
- X 与退出托盘前后 Watcher PID/任务/ProxyEnable/ProxyServer/网关/TCP7890/代理响应完整取证；目前没有证据把用户报告的掉线归因于旧 GUI。
- Explorer 真实重启、锁屏/解锁、休眠唤醒、Watcher 异常退出及任务重启。
- 多显示器真实 125/150/200% DPI、Tab 键路径和 Windows 通知区域可见位置。
- 真实停止/恢复冲突、卸载删除本软件任务/Run 项/入口且不触碰后续手动设置。
- 真实机器断电期间磁盘持久化与不同 Windows 安全策略/执行策略/防病毒环境。

发行状态为**待真实 Windows 网络验收候选**。GitHub Actions 继续执行全部原始/新增模拟与桌面检查，并仅准备 draft prerelease。v3.0.0 Release 不更新。

本机高频原子替换压力还发现 Windows 短暂共享/删除冲突；Write-JsonAtomic 增加保留源临时文件时的有界重试，不删除/截断有效目标，持续失败仍抛错。针对压力用例再次验证通过；最终完整重跑记录与 CI 按提交分别保留。临时文件检查改用真实长文件名匹配，避免 Windows 8.3 短名导致误判；没有忽略实际残留临时文件。
