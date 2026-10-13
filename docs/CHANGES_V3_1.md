# v3.1.0 实际变更与兼容性

基线为 feature/exe-productization 的 `2c9976b600639e9e1d88cbb67b484350d7dee2a2`。v3.0.0 为 `85bfbd05577c7a4d4206af1265429f34e032f544`，基线领先 3 个提交，仅增加/更新 CI 验证记录。新分支 feature/ui-tray-performance-v3.1。

当前工作区开始为空，无未提交用户修改。Git clone 因连接重置失败，通过已授权 GitHub 连接器取回所有文本文件，逐个核对原 Git SHA，并重建相同 Git 树及浅提交。旧 CI PNG 无法通过 UTF-8 连接器下载，保持原树/索引中的 blob 引用并标记 skip-worktree，不在远端修改或删除；不伪造完整历史。

- Program / AppController：窗口创建前不提取资源，GUI 单实例优先判断，后台资源预热、状态读取和引擎调用；首次安装由用户确认。CLI 及冲突恢复路由保留。
- PayloadCache：版本 + 内嵌清单 SHA256 寻址、完整哈希、安全单次目录遍历、并发门闩、坏缓存隔离重建。旧临时 Payload 仍保留以维持原边界回归。
- MainForm：四页导航、状态卡片、名单编辑、设置、格式化有界日志、非阻塞反馈与共享操作忙碌状态。配置保存使用 ConfigurationStore。
- TrayContext / SingleInstance：X 隐藏、可选最小化、双击、二次 EXE 激活、Explorer 消息、电源/会话刷新和仅退出界面；卸载 helper 在改网络前等待已有 UI 释放。
- Core.ps1 / Monitor.ps1 / ProxyWatcher：配置字节验证、默认名单保护、热加载、有效配置回退、独立暂停；其余 SSID/网关/Strict/Safe/写入与恢复算法不重写。
- Control / Desktop / Lifecycle：新增 Pause/Resume/Settings；独立登录偏好、归属受保护的托盘 Run 项、3.1.0 版本目录；旧安装标识/路径及最初备份继续兼容。
- Native WLAN / WinINet：GUI 编译复用原 Native.cs，避免动态启动 PowerShell 获取当前 SSID 或代理状态；不向原 PS 5.1 编译源加入新 C# 指令。
- 测试/工具：新增缓存、配置、生产热更新/暂停模拟、真实 WinForms 隔离冒烟和合成 DPI 截图、分阶段启动/CPU/内存测量；多尺寸图标生成器可重建。

原回归没有删除或放宽。Productization.Tests 的版本目录字面量从 app/3.0.0- 改为 app/3.1.0-，哈希和归属断言保留；Round2 的临时 fixture 清理增加有界重试，原产品断言不变。最初回归 103 + 22 全绿；当前结果详见 TEST_RESULTS_V3_1。

不更改 DNS、路由、防火墙、WinHTTP 或代理服务。不因为退出 GUI/托盘恢复代理。发行依然是 Windows x64 自包含 EXE；未启用裁剪或额外运行时依赖。压缩单文件实验不作为默认，因为本机启动反而变慢。

Release 为待真实网络验收候选，不覆盖 v3.0.0。正式推广前需完成登录/电源/Explorer/真实热更新/卸载和掉线取证。
