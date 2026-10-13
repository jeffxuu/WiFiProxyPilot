# v3.2 配置与安装迁移

升级继续使用原安装身份 `WiFiProxySwitcher`。显示名称为 WiFi Proxy Pilot；不因为品牌改名另建安装目录、任务、Watcher 或代理原始备份。

## 升级步骤

1. 打开候选 EXE。GUI 只读查找当前用户安装；旧后台不兼容时显示需要升级。
2. 使用设置中的“修复安装 / 升级”，明确确认后由现有安装服务更新组件。不要先卸载，不要用仓库默认配置覆盖安装配置。
3. 安装服务先校验实际安装的 `config.json`、原始代理备份、任务和文件归属，再更新。保留合法名单、端口、模式、诊断、登录偏好及未知字段。
4. schema 1 转为 schema 2，旧 `state/pause.request` 存在且尚无新意图时迁移为 Paused；否则延续旧自动管理意图。已有 schema 2 意图不被旧标记覆盖。
5. GUI 显示配置保存和后台稳定应用的不同阶段。旧引擎没有对应新鲜 revision 确认时，不显示“规则已应用”。

修复/安装将修改本机任务、启动记录和代理管理。当前开发机未执行真实升级，隔离迁移测试不代表此步骤已经实机验收。

## SchemaVersion 2

| 字段 | 新用户默认 | 旧配置迁移 |
| --- | --- | --- |
| `SchemaVersion` | 2 | 缺失或 1 升为 2；高于支持版本拒绝写入并要求升级 |
| `ManagementIntent` | Paused | 保留已有值；缺失时读取旧暂停标记，否则 Monitoring |
| `SetupComplete` | false | 保留已有值；旧安装缺失时 true |
| `Whitelist` | `[]` | 原名单合法名称保持，不添加、不清空；OrdinalIgnoreCase 去重 |
| `Port` | 7890 | 保留 |
| `Mode` | Strict | 保留 Strict/Safe 及诊断设置 |
| 其他有效/未知字段 | 默认或未设置 | 保留 |

旧版强制免代理的名称变为普通用户规则，全部可编辑/删除。保留旧名单不表示重新添加保护。删除全部规则后，所有可靠识别的 Wi-Fi 都按当前网关策略处理；未知网络仍遵守原有保护逻辑。

SSID 为 1–32 个 UTF-8 字节、无控制字符、保留合法空格；完整名称按 OrdinalIgnoreCase 匹配。空数组合法，空字符串不合法。重复 JSON 字段、非法范围、无效 GUID 和带凭据的 HTTP 诊断 URL 均被拒绝。

## 原子保存和回滚

`ConfigurationStore.Read` 计算原始文件 SHA256 revision，并返回内存中的合法迁移文档；普通读取不写安装文件。`Save` 在配置路径命名 Mutex 下重新检查 revision，使用同目录随机暂存文件、WriteThrough/Flush 和 File.Replace，保留 `config.json.previous`。外部变更导致冲突时拒绝覆盖，用户重新载入后再编辑。

Watcher 使用同一字节快照计算 revision 和读取配置。配置变化废弃旧防抖和旧诊断，重新确认当前网络。无效更新保留运行中的最后有效配置并记录错误；启动时依次验证 `.previous` 与 `state/config-last-good.json`。全部备份无效时失败，不能清空名单代替修复。

迁移可重复执行。安装器更新用户配置时应保留上一份有效 JSON；迁移失败保留旧配置和最初备份。回退 v3.1 引擎不理解 schema 2 的暂停/直连意图，不能当作透明降级：先停止自动管理，保留配置备份，再按明确恢复方案处理。

## 必须保留的身份与文件

| 项目 | 兼容身份 |
| --- | --- |
| 默认目录 | `%LOCALAPPDATA%\WiFiProxySwitcher`，实际安装指针优先 |
| 安装指针 | `HKCU\Software\WiFiProxySwitcher` |
| 任务 | `WiFiProxySwitcher-<当前用户 SID>`，Interactive/Limited |
| 桌面卸载记录 | `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\WiFiProxySwitcher` |
| 托盘登录项 | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 的 `WiFiProxySwitcher.Tray` |
| 原始手动代理备份 | `state/proxy-before-install.json`，更新不重复生成 |
| 最后自身写入 | `state/last-applied.json`，恢复冲突判断依据 |
| 安装清单 | `state/installation.json` 和 `app/desktop.json` |
| 桌面/后台互斥锁 | 沿用原身份与用户/会话范围，避免第二实例 |

版本化 EXE 路径仍保留 `WiFiProxySwitcher.exe` 兼容名。用户修改过的文件、无关目录内容和所有权不匹配的任务不能被更新或卸载擅自删除。最初备份损坏时拒绝恢复。

恢复直连只关闭手动代理，保留最初备份。恢复安装前配置/卸载默认比较当前值与原始值或最后自身写入；若外部程序或用户后来修改过代理，停止自动管理并报告冲突。强制恢复与保留当前代理是需要用户明确选择的分支，不默认强制覆盖。
