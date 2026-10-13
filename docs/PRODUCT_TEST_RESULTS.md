# v3.0.0 测试证据

2026-10-12（Asia/Shanghai）。实际云端环境：Debian 13 x64、PowerShell 7.4.6、.NET SDK 8.0.425。

| 层次 | 实际结果 | 边界 |
|---|---|---|
| 仓库审计基线 | 原有 95 项全部通过 | Linux 模拟/静态/loopback |
| 产品化 PowerShell 回归 | **103 执行、103 通过、0 失败** | 保留全部原 95 项；新增立即检测、BAT 迁移、旧清单升级、结构化冲突、桌面清单与安装契约 |
| C# 启动器回归 | **22 执行、22 通过、0 失败** | 真实解析、提取、哈希、路径文件 I/O；身份和安装命令为边界模拟 |
| win-x64 self-contained 构建 | 成功，PE32+ x86-64 GUI 可执行文件 | Linux 交叉编译，尚未在此环境运行 EXE |
| ZIP / SHA256 | 已生成并校验 | 校验具体构建产物，Release 工作流另行生成其最终校验值 |
| Windows 托管环境 PowerShell 5.1 | **103/103 通过**，引擎编译和回归已实际执行 | 任务/代理/账户转换等系统边界仍使用测试替身 |
| Windows C# 与 EXE/WinForms 冒烟 | **22/22 通过；EXE 启动、嵌入包和窗口渲染通过** | Windows 托管 runner，不是用户的 Windows 11 实机，不安装或改真实代理 |
| 真实 Windows 网络/安装/卸载 | **未验证** | 见 PRODUCT_WINDOWS_ACCEPTANCE.md，不将模拟或渲染当系统验收 |

机器可读逐项记录：[PowerShell 103 项](product-engine-tests.json)、[C# 22 项](product-launcher-tests.json)。未更改云端真实代理。

新增 EXE 验收覆盖：默认启动路由、安装/重复安装调用与提取隔离、卸载冲突、中文/空格路径、普通用户与同 SID 管理员、拒绝 SYSTEM/借用管理员、参数注入边界、异常退出/结果不一致与重试。真实 Windows 交互安装、提权、任务回读、窗口和文件锁需按本机矩阵执行。

首轮 C# 测试编译发现测试用 Windows 路径的反斜杠未用逐字字符串；已修复并重新编译运行完整 C# 套件。没有删除原断言或降低测试数量。

构建命令：`bash tools/cloud-setup.sh`；`pwsh -NoProfile -File release/Build.ps1 -Dotnet /workspace/tooling/dotnet/dotnet`（Windows 开发机省略 Dotnet 参数）。发布前必须检查 Windows CI 的 SourceCommit 和各步 outcome；workflow 失败不会创建 Release。

Windows 实际证据：提交 `9a64506366207110b7b1885403e633df789f6429` 的 [成功工作流](https://github.com/jeffxuu/WiFiProxyPilot/actions/runs/38185726770)，回传于开发分支 `release/ci-latest.json`，界面截图 `release/ci-ui.png` 已人工查看无裁切。发布 tag 会重新运行同一门禁，并记录最终产物元数据。

首次 Windows CI 实测 99/101：发现 PowerShell 5.1 的 Add-Type 不支持 CompilerOptions，后续依赖类型也因此加载失败。已为 5.1 使用 CompilerParameters，并保留 /langversion:5 和全部断言；修复后 Windows 103 项全部通过。新增两项使用真实临时文件验证桌面 EXE 重复安装、版本更新不覆盖旧文件及修改文件保护。
