# 托盘与监控生命周期

四种职责分离：MainForm 是可隐藏的主窗口；TrayContext 是 ApplicationContext 和 NotifyIcon 的所有者；PowerShell ProxyWatcher 是独立后台引擎；监控登录任务是当前用户 Interactive/Limited 任务。托盘登录入口为当前用户 HKCU Run 的 `WiFiProxySwitcher.Tray`，指向归属清单中的版本化 EXE 加 `/tray`。两者分别可配置，均不以 SYSTEM 写 HKCU。

| 操作 | GUI/托盘 | Watcher | 手动代理 |
| --- | --- | --- | --- |
| X（默认） | 隐藏，托盘保留 | 继续 | 不写入 |
| 最小化到托盘（可选） | 隐藏 | 继续 | 不写入 |
| 双击托盘/再次运行 EXE | 恢复原窗口 | 不创建第二份 | 不写入 |
| 暂停自动切换 | 显示暂停 | pause.request 控制，保持存活 | 保留当前配置 |
| 重新启用 | 显示确认过程 | 清除暂停，必要时启动原任务，重新确认网络 | 原网络规则 |
| 退出界面 | 退出窗口及托盘 | 继续 | 不写入，不恢复 |
| 停止并恢复 | 确认后执行控制脚本 | 安全停止 | 原备份及冲突保护 |
| 卸载 | 独立 helper 等待调用进程并请求已有托盘退出 | 原安全停止及清理流程 | 原恢复及冲突保护 |

用户 SID + SessionId 范围的命名 Mutex 保证一个托盘实例；命名事件请求打开原窗口。二次启动在 AppController 或 Payload 创建前返回，不解包、不安装、不创建 PowerShell。退出界面不调用任何引擎命令。卸载 helper 请求原托盘退出并等候锁释放；忙碌或仍在运行时超时，在接触监控/代理前拒绝。

NotifyIcon 原生处理 Explorer 通知；额外隐藏顶层 ShellWindow 接收 TaskbarCreated 并重新注册图标。PowerModeChanged.Resume 和 SessionSwitch.SessionUnlock 触发后台状态读取。Watcher 自身沿用长间隔后的防抖和诊断废弃逻辑。任务沿用异常重启策略；不新建恢复网络引擎，也不因 UI 崩溃执行恢复。

托盘自启更新/删除仅接受 desktop.json 清单中的完整带引号命令。同名项被其他程序改动时拒绝覆盖。原桌面清单标识维持 v3，接受旧 3.0.0 路径；新文件使用 3.1.0-哈希路径，避免覆盖运行中的旧 EXE。

## “关窗口掉线”的取证

本轮未获真实安装与网络验收授权。只能确认源码中旧 GUI 的关闭路径没有显式 stop/restore，以及隔离新 GUI 的 X/Exit 未改变模拟后台状态。**不能据此宣称已经修复真实断网原因。**

人工复现时先使用现有只读 Diagnose/Status 报告记录：GUI PID、Watcher PID/RunId、Watcher 命名锁、任务 State/LastTaskResult、心跳时间、ProxyEnable/ProxyServer、网关、TCP 7890 与实际代理响应。关闭 X 后在 0、2、10、30 秒再次采集并比较，再做退出托盘 UI 的对照。保持相同 Wi-Fi 和独立代理服务，禁止同时切网混淆变量。记录代理配置变化的时间与 watcher.jsonl 的 Changed/Reason，观察是否有恢复命令或异常重启。

若 Watcher 仍存活、任务及代理未变化而 TCP/HTTP 失败，应继续定位代理服务或网关；若只有 GUI PID 消失，不等同于监控退出。若网关变化，核对原有物理 WLAN 路由选择。允许 TCP 连接仍不能证明 HTTP 代理可用。真实 Explorer 重启、锁屏、休眠、登录和 Watcher 崩溃恢复仍列为人工待验收，不能将消息处理代码视为实机通过。
