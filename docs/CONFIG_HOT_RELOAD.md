# 名单持久化与配置热更新

GUI 通过原注册表安装指针查找当前用户已安装根目录，不写仓库默认 config.json。读取最多 1 MiB 的完整 JSON，拒绝重复字段和不合法数据；保留 Port、Mode、Diagnostics、全部已有字段及未知未来字段。所有内置项在保存及核心目标计算中强制保护；名单 OrdinalIgnoreCase 去重，保留完整名称与合法空格，UTF-8 1–32 字节限制和控制字符拒绝与 PowerShell 一致。

ConfigurationStore 保存步骤：验证完整草稿 → 配置路径命名 Mutex → 对比读取时的 SHA256 revision → 同目录随机临时文件 → WriteThrough + Flush(true) → File.Replace 生成 `config.json.previous`。异常清理当前临时文件；遗留未完成临时文件不被当成配置。外部修改导致冲突时不覆盖。路径联接或链接被拒绝。

Watcher 在循环顶部从同一字节快照验证并计算 SHA256；候选通过后才替换内存中的有效配置。更新后废弃旧防抖身份及健康检测结果，继续使用原 Invoke-MonitorCycle 稳定确认、写入前网络夹读、WinINet/注册表回读和备份逻辑。普通等待每最多 500ms 检查配置时间/长度、检测及暂停请求，即使 PollSeconds=300 也可及时唤醒。其后仍需原防抖时序，不能瞬间跳过安全确认。

无效配置保持有效内存配置，记录 ERROR 并抑制重复同一错误；下一个不同的有效版本仍可生效。运行中保存有效快照到 `state/config-last-good.json`。下次启动若主配置错误，依次验证 `config.json.previous`、last-good，恢复有效配置并明确记错；没有有效备份时启动失败，不能清空名单。

心跳带 ConfigRevision、Mode、PollSeconds、诊断结果和诊断年龄。GUI 保存后只显示“等待后台重新确认”；对应 revision 的稳定状态才表示当前网络评估完成。暂停期间加载配置但不读取/写入网络代理。旧 Watcher 不具备热更新，需一次显式修复/升级，GUI 不伪报已应用。

编辑名单不注册任务或停止 Watcher。设置页保存时单独应用两项登录偏好，使用原任务所有权校验；启用监控不强行改变用户已经保存的 LoginMonitor 偏好。升级复用原安装器的 PreserveConfig，不重新生成原始备份；卸载按原哈希保护保留用户修改过的 JSON。

已验证：新增/删除 XiaoMi 的实际生产循环在模拟服务下关闭/启用代理、中文/空格/大小写去重、JSON 注入安全、连续快速写入、坏配置保留和修复、有效备份回退、未完成临时文件、外部 revision 冲突。真实机器上的热更新和电源中断持久化仍待授权验收。
