using System.Diagnostics;
using System.Text.Json.Nodes;
using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;
internal sealed class MainForm : Form
{
    private static readonly Color Accent = Color.FromArgb(0, 103, 192), Ink = Color.FromArgb(30, 41, 59), Muted = Color.FromArgb(85, 100, 120);
    private readonly AppController? controller;
    private readonly Panel[] pages = new Panel[4];
    private readonly Button[] navigation = new Button[4];
    private readonly Label headline = new() { Text = "正在读取状态", AutoSize = true, ForeColor = Ink };
    private readonly Label explanation = new() { Text = "关闭窗口后，托盘与后台监控继续运行。", AutoSize = true, ForeColor = Muted };
    private readonly Label message = new() { AutoEllipsis = true, Dock = DockStyle.Fill, ForeColor = Accent, UseMnemonic = false };
    private readonly Label[] values = new Label[6];
    private readonly ToolTip tips = new() { AutoPopDelay = 20000 };
    private readonly Button automatic = new() { Text = "开启自动切换" }, detect = new() { Text = "立即检测" };
    private readonly ListBox networks = new() { Dock = DockStyle.Fill, IntegralHeight = false, HorizontalScrollbar = true };
    private readonly TextBox input = new() { Width = 280, PlaceholderText = "完整 Wi-Fi 名称，空格会原样保留" };
    private readonly TextBox logs = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both, WordWrap = false, Dock = DockStyle.Fill, BorderStyle = BorderStyle.FixedSingle };
    private readonly CheckBox errors = new() { Text = "仅警告和错误", AutoSize = true }, raw = new() { Text = "原始 JSON（高级）", AutoSize = true };
    private readonly CheckBox login = new() { Text = "登录后自动运行监控", AutoSize = true, Checked = true }, trayLogin = new() { Text = "登录后显示托盘图标", AutoSize = true, Checked = true }, close = new() { Text = "关闭窗口时隐藏到托盘", AutoSize = true, Checked = true }, minimize = new() { Text = "最小化时隐藏到托盘", AutoSize = true };
    private readonly ComboBox mode = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 180 }, diagnostics = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 180 };
    private readonly NumericUpDown port = new() { Minimum = 1, Maximum = 65535, Value = 7890, Width = 180 }, poll = new() { Minimum = 1, Maximum = 300, Value = 5, Width = 180 };
    private readonly TextBox httpUrl = new() { Width = 360, PlaceholderText = "HTTP 诊断使用的 http URL" };
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 3000 };
    private ConfigurationDocument? configuration;
    private readonly List<string> draftNames = new();
    private bool busy, reading, listDirty;
    private Task? initialization;
    private string? pendingRevision;
    private int selectedPage = -1;
    internal bool IsBusy => busy;
    internal bool CloseToTray => configuration?.Flag("CloseToTray", true) ?? true;
    internal bool MinimizeToTray => configuration?.Flag("MinimizeToTray", false) ?? false;
    internal StatusView? CurrentStatus { get; private set; }
    internal event Action<StatusView>? StatusChanged;
    internal event Action<bool>? BusyChanged;
    internal event Action? ExitRequested;

    internal MainForm(AppController? controller)
    {
        this.controller = controller;
        SuspendLayout();
        Text = "Wi-Fi 智能代理切换 · 3.1.0"; AutoScaleMode = AutoScaleMode.Dpi; AutoScaleDimensions = new SizeF(96, 96);
        MinimumSize = new Size(900, 680); Size = new Size(1060, 790); StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Microsoft YaHei UI", 10F); BackColor = Color.FromArgb(245, 247, 250); ForeColor = Ink; Icon = AppIcons.Create(Accent);
        var shell = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1 };
        shell.SuspendLayout();
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 196)); shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        var sidebar = new TableLayoutPanel { Dock = DockStyle.Fill, BackColor = Color.White, Padding = new Padding(16, 25, 14, 20), ColumnCount = 1, RowCount = 7 };
        sidebar.SuspendLayout();
        sidebar.Controls.Add(Label("Wi-Fi 代理", 18, FontStyle.Bold), 0, 0); sidebar.Controls.Add(Label("自动管理 · 当前用户", 9), 0, 1);
        string[] titles = ["概览", "免代理 Wi-Fi", "设置", "日志与诊断"];
        for (int i = 0; i < titles.Length; i++)
        {
            int index = i; navigation[i] = Button(titles[i], () => SelectPage(index)); navigation[i].Dock = DockStyle.Top; navigation[i].Height = 46;
            sidebar.Controls.Add(navigation[i], 0, i + 2); sidebar.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        }
        sidebar.RowStyles.Add(new RowStyle(SizeType.AutoSize)); sidebar.RowStyles.Add(new RowStyle(SizeType.AutoSize)); sidebar.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        var version = Label("v3.1.0\n后台监控独立运行", 9); version.Dock = DockStyle.Bottom; sidebar.Controls.Add(version, 0, 6);
        var body = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(26, 24, 26, 20), RowCount = 3, ColumnCount = 1 };
        body.SuspendLayout();
        body.RowStyles.Add(new RowStyle(SizeType.AutoSize)); body.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); body.RowStyles.Add(new RowStyle(SizeType.Absolute, 52));
        var heading = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, FlowDirection = FlowDirection.TopDown, WrapContents = false, Margin = new Padding(0, 0, 0, 20) };
        headline.Font = new Font(Font.FontFamily, 19, FontStyle.Bold); heading.Controls.Add(headline); heading.Controls.Add(explanation);
        body.Controls.Add(heading, 0, 0);
        var content = new Panel { Dock = DockStyle.Fill };
        for (int i = 0; i < pages.Length; i++) { pages[i] = new Panel { Dock = DockStyle.Fill, AutoScroll = true }; content.Controls.Add(pages[i]); }
        BuildOverview(); BuildNetworks(); BuildSettings(); BuildLogs(); body.Controls.Add(content, 0, 1); body.Controls.Add(message, 0, 2);
        shell.Controls.Add(sidebar, 0, 0); shell.Controls.Add(body, 1, 0); Controls.Add(shell); SelectPage(0);
        ResumeTree(this); ResumeLayout(true);
        timer.Tick += async (_, _) => await RefreshAsync();
        Shown += async (_, _) => { StartupMetrics.Mark("FirstVisible"); await InitializeAsync(); };
        bool painted = false; Paint += (_, _) => { if (!painted) { painted = true; StartupMetrics.Mark("FirstPaint"); } };
        FormClosed += (_, _) => { timer.Stop(); timer.Dispose(); tips.Dispose(); };
    }
    private Label Label(string text, float size = 10, FontStyle style = FontStyle.Regular) => new() { Text = text, AutoSize = true, UseMnemonic = false, ForeColor = style == FontStyle.Bold ? Ink : Muted, Font = new Font(Font.FontFamily, size, style), Margin = new Padding(0, 6, 0, 10) };
    private static void Style(Button button, bool primary = false)
    {
        button.AutoSize = true; button.Padding = new Padding(12, 7, 12, 7); button.Margin = new Padding(0, 6, 10, 6); button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = primary ? 0 : 1; button.FlatAppearance.BorderColor = Color.FromArgb(217, 223, 232);
        button.BackColor = primary ? Accent : Color.White; button.ForeColor = primary ? Color.White : Ink; button.Cursor = Cursors.Hand;
    }
    private Button Button(string text, Action click, bool primary = false) { var b = new Button { Text = text }; Style(b, primary); b.Click += (_, _) => click(); return b; }
    private Button AsyncButton(string text, Func<Task> click, bool primary = false) { var b = new Button { Text = text }; Style(b, primary); b.Click += async (_, _) => await click(); return b; }
    private static FlowLayoutPanel Row() { var panel = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, WrapContents = true, Margin = new Padding(0, 4, 0, 6) }; panel.SuspendLayout(); return panel; }
    private static TableLayoutPanel Stack(int rows) { var panel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = rows, AutoScroll = true }; panel.SuspendLayout(); return panel; }
    private static void ResumeTree(Control control) { foreach (Control child in control.Controls) ResumeTree(child); control.ResumeLayout(false); }
    private void BuildOverview()
    {
        var stack = Stack(4); for (int i = 0; i < 3; i++) stack.RowStyles.Add(new RowStyle(SizeType.AutoSize)); stack.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        var actions = Row(); Style(automatic, true); Style(detect); automatic.Click += async (_, _) => await ToggleAutomatic(); detect.Click += async (_, _) => await Operate("check");
        actions.Controls.Add(automatic); actions.Controls.Add(detect); actions.Controls.Add(Button("管理免代理 Wi-Fi", () => SelectPage(1))); stack.Controls.Add(actions, 0, 0);
        var cards = new TableLayoutPanel { ColumnCount = 2, RowCount = 3, Dock = DockStyle.Top, AutoSize = true };
        cards.SuspendLayout();
        cards.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50)); cards.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        string[] names = ["当前 Wi-Fi", "IPv4 网关", "Windows 手动代理", "当前规则", "最近检测时间", "代理服务检测"];
        for (int i = 0; i < names.Length; i++)
        {
            var card = new TableLayoutPanel { BackColor = Color.White, Padding = new Padding(16, 12, 14, 12), Dock = DockStyle.Fill, Height = 102, RowCount = 2, ColumnCount = 1, Margin = new Padding(0, 4, 12, 8) };
            card.SuspendLayout();
            card.RowStyles.Add(new RowStyle(SizeType.Absolute, 32)); card.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); card.Controls.Add(Label(names[i], 9), 0, 0);
            values[i] = new Label { Text = "—", AutoEllipsis = true, Dock = DockStyle.Fill, UseMnemonic = false, Font = new Font(Font.FontFamily, 11, FontStyle.Bold) };
            card.Controls.Add(values[i], 0, 1); cards.Controls.Add(card, i % 2, i / 2);
        }
        stack.Controls.Add(cards, 0, 1);
        stack.Controls.Add(Button("查看详细信息", () => MessageBox.Show(this, $"Wi-Fi 接口：{CurrentStatus?.Interface}\n\n检测说明：{CurrentStatus?.Reason}\n\n代理检测：{CurrentStatus?.Health}\n\n代理开启仅代表系统配置，不代表代理服务可用。", "详细信息", MessageBoxButtons.OK, MessageBoxIcon.Information)), 0, 2);
        stack.Controls.Add(Label("Strict：遵循网络规则。Safe：按有效诊断结果提供保护。\n本工具只管理 Windows 手动代理，保留 PAC 与自动检测。", 9), 0, 3); pages[0].Controls.Add(stack);
    }
    private void BuildNetworks()
    {
        var stack = Stack(5); stack.RowStyles.Add(new RowStyle(SizeType.AutoSize)); stack.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); for (int i = 0; i < 3; i++) stack.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        var note = Label("连接名单中的 Wi-Fi 时自动关闭 Windows 手动代理；\n连接其他 Wi-Fi 时按当前网关自动配置代理。\n完整名称匹配，忽略大小写。内置规则始终保留。", 10); stack.Controls.Add(note, 0, 0);
        stack.Controls.Add(networks, 0, 1); var add = Row(); add.Controls.Add(input); add.Controls.Add(Button("添加", AddInput));
        add.Controls.Add(AsyncButton("从当前连接添加", async () => { if (busy) return; SetBusy(true); try { input.Text = await Task.Run(StatusReader.ConfirmedSsid); AddInput(); } catch (Exception e) { ShowError(e); } finally { SetBusy(false); } }));
        input.KeyDown += (_, e) => { if (e.KeyCode == Keys.Enter) { AddInput(); e.SuppressKeyPress = true; } }; stack.Controls.Add(add, 0, 2);
        var edit = Row(); edit.Controls.Add(Button("删除所选", () => { int n = networks.SelectedIndex; if (n < 0) return; if (ConfigurationStore.BuiltIns.Contains(draftNames[n], StringComparer.OrdinalIgnoreCase)) { Feedback("内置规则始终保留，不能删除。"); return; } draftNames.RemoveAt(n); listDirty = true; RenderNames(); Feedback("尚未保存：点击“保存并应用”生效。"); }));
        edit.Controls.Add(AsyncButton("保存并应用", () => SaveConfiguration(false), true)); edit.Controls.Add(AsyncButton("取消修改 / 重新载入", async () => { if (busy) return; SetBusy(true); try { await ReloadConfiguration(true, false); Feedback("已重新载入名单，取消尚未保存的修改。"); } finally { SetBusy(false); } })); stack.Controls.Add(edit, 0, 3);
        stack.Controls.Add(Label("名称按真实 SSID 的 32 字节限制验证；支持中文和合法空格。", 9), 0, 4); pages[1].Controls.Add(stack);
    }
    private void BuildSettings()
    {
        var stack = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoScroll = true, FlowDirection = FlowDirection.TopDown, WrapContents = false };
        stack.SuspendLayout();
        stack.Controls.Add(Label("日常设置", 12, FontStyle.Bold)); foreach (var box in new[] { login, trayLogin, close, minimize }) { box.Margin = new Padding(0, 6, 0, 8); stack.Controls.Add(box); }
        stack.Controls.Add(Label("代理与诊断（高级）", 12, FontStyle.Bold)); mode.Items.AddRange(["Strict", "Safe"]); mode.SelectedIndex = 0; diagnostics.Items.AddRange(["None", "Tcp", "Http"]); diagnostics.SelectedIndex = 1;
        foreach (var pair in new (string Text, Control Input)[] { ("运行模式", mode), ("代理端口", port), ("轮询间隔（秒）", poll), ("连通性诊断", diagnostics), ("HTTP 诊断 URL", httpUrl) })
        { var row = Row(); var name = Label(pair.Text); name.AutoSize = false; name.Width = 180; row.Controls.Add(name); row.Controls.Add(pair.Input); stack.Controls.Add(row); }
        stack.Controls.Add(Label("Safe 必须启用诊断。TCP 开放不能证明代理服务可用。", 9)); var save = Row(); save.Controls.Add(AsyncButton("保存设置", () => SaveConfiguration(true), true)); save.Controls.Add(AsyncButton("取消修改 / 重新载入", async () => { if (busy) return; SetBusy(true); try { await ReloadConfiguration(false, true); Feedback("已重新载入设置，取消尚未保存的修改。"); } finally { SetBusy(false); } })); stack.Controls.Add(save);
        stack.Controls.Add(Label("高级操作", 12, FontStyle.Bold)); var advanced = Row(); advanced.Controls.Add(AsyncButton("修复安装 / 升级", () => Operate("install"))); advanced.Controls.Add(AsyncButton("恢复安装前代理", () => Operate("restore"))); advanced.Controls.Add(AsyncButton("卸载程序", () => Operate("uninstall"))); stack.Controls.Add(advanced); pages[2].Controls.Add(stack);
    }
    private void BuildLogs()
    {
        var stack = Stack(3); stack.RowStyles.Add(new RowStyle(SizeType.AutoSize)); stack.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); stack.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        var filters = Row(); filters.Controls.Add(errors); filters.Controls.Add(raw); errors.CheckedChanged += async (_, _) => await RefreshAsync(); raw.CheckedChanged += async (_, _) => await RefreshAsync(); stack.Controls.Add(filters, 0, 0); stack.Controls.Add(logs, 0, 1);
        var actions = Row(); actions.Controls.Add(AsyncButton("刷新", RefreshAsync)); actions.Controls.Add(Button("复制诊断信息", () => { try { Clipboard.SetText($"WiFiProxySwitcher 3.1.0\n{CurrentStatus?.Watcher}\nWi-Fi: {CurrentStatus?.Ssid}\n网关: {CurrentStatus?.Gateway}\n手动代理: {CurrentStatus?.Proxy}\n最近检测: {CurrentStatus?.Updated}\n说明: {CurrentStatus?.Reason}\n{logs.Text}"); Feedback("诊断信息已复制，分享前请检查 Wi-Fi 名称和代理地址。"); } catch (Exception e) { ShowError(e); } }));
        actions.Controls.Add(Button("打开日志目录", () => { try { string? root = AppController.InstalledRoot(); if (root == null) return; string dir = Path.Combine(root, "logs"); if (Directory.Exists(dir)) Process.Start(new ProcessStartInfo(dir) { UseShellExecute = true }); } catch (Exception e) { ShowError(e); } })); stack.Controls.Add(actions, 0, 2); pages[3].Controls.Add(stack);
    }
    internal void SelectPage(int page)
    {
        if (selectedPage == page) return; selectedPage = page;
        SuspendLayout();
        for (int i = 0; i < pages.Length; i++) { pages[i].Visible = i == page; navigation[i].BackColor = i == page ? Color.FromArgb(231, 240, 252) : Color.White; navigation[i].ForeColor = i == page ? Accent : Ink; }
        ResumeLayout(true);
        if (page == 1 && listDirty) Feedback("名单有尚未保存的修改。");
    }
    internal Task InitializeAsync() => initialization ??= InitializeCore();
    private async Task InitializeCore()
    {
        await RefreshAsync(); timer.Start();
        await ReloadConfiguration();
        if (controller != null) { try { await controller.WarmCache(); } catch (Exception e) { StartupMetrics.Value("PayloadError", e.ToString()); Feedback("内嵌资源准备失败：" + e.Message); } }
    }
    private async Task ReloadConfiguration(bool names = true, bool settings = true)
    {
        try { string? root = await Task.Run(AppController.InstalledRoot); if (root == null) return; configuration = await Task.Run(() => ConfigurationStore.Read(root)); if (names) LoadNames(); if (settings) LoadSettings(); }
        catch (Exception e) { Feedback("配置读取失败，保留已有内容：" + e.Message); }
    }
    internal async Task RefreshAsync()
    {
        if (reading || busy || IsDisposed) return; reading = true; bool errorFilter = errors.Checked, rawView = raw.Checked;
        try
        {
            var s = await Task.Run(() => StatusReader.Read(errorFilter, rawView)); if (IsDisposed) return; CurrentStatus = s;
            headline.Text = !s.Installed ? "欢迎使用 Wi-Fi 智能代理" : !s.Running ? "自动切换未运行" : s.Paused ? "自动切换已暂停" : s.Healthy ? "自动切换正常" : s.Watcher == "正在确认网络" ? "正在确认网络" : "检测异常";
            tips.SetToolTip(headline, s.Watcher); headline.ForeColor = s.Healthy ? Color.FromArgb(22, 120, 80) : s.Running && !s.Paused ? Color.FromArgb(170, 92, 0) : Ink;
            explanation.Text = s.Paused ? "当前手动代理保持不变；重新启用后按网络规则管理。" : "关闭窗口后，托盘与后台监控继续运行。";
            string[] data = [s.Ssid, s.Gateway, s.Proxy, s.Rule, s.Updated, s.Health];
            for (int i = 0; i < data.Length; i++) { values[i].Text = string.IsNullOrEmpty(data[i]) ? "—" : data[i]; tips.SetToolTip(values[i], values[i].Text); }
            if (logs.Text != s.Logs) { int selection = logs.SelectionStart; logs.Text = s.Logs; logs.SelectionStart = Math.Min(selection, logs.TextLength); }
            automatic.Text = !s.Installed ? "开启自动切换（安装）" : s.Running && !s.Paused ? "暂停自动切换" : "开启自动切换"; detect.Enabled = s.Running && !s.Paused;
            if (pendingRevision != null && s.Revision == pendingRevision && s.Healthy) { pendingRevision = null; Feedback("保存成功，后台已载入配置并完成当前网络的重新评估。"); }
            StatusChanged?.Invoke(s); StartupMetrics.Mark("FirstStatus");
        }
        catch (Exception e) { Feedback("状态读取失败：" + e.Message); }
        finally { reading = false; }
    }
    private void AddInput()
    {
        try { string name = ConfigurationStore.ValidateSsid(input.Text); if (draftNames.Contains(name, StringComparer.OrdinalIgnoreCase)) { Feedback("该完整 Wi-Fi 名称已在名单中（忽略大小写）。"); return; } draftNames.Add(name); listDirty = true; RenderNames(); input.Clear(); Feedback("已添加，点击“保存并应用”生效。"); } catch (Exception e) { Feedback(e.Message); }
    }
    private void RenderNames() { networks.BeginUpdate(); networks.Items.Clear(); foreach (string name in draftNames) networks.Items.Add(name + (ConfigurationStore.BuiltIns.Contains(name, StringComparer.OrdinalIgnoreCase) ? "   · 内置规则" : "   · 自定义")); networks.EndUpdate(); }
    private void LoadNames() { if (configuration == null) return; draftNames.Clear(); draftNames.AddRange(ConfigurationStore.Normalize(configuration.Whitelist)); listDirty = false; RenderNames(); }
    private void LoadSettings()
    {
        if (configuration == null) return; var c = configuration.Values; login.Checked = configuration.Flag("LoginMonitor", true); trayLogin.Checked = configuration.Flag("TrayAutoStart", true); close.Checked = configuration.Flag("CloseToTray", true); minimize.Checked = configuration.Flag("MinimizeToTray", false);
        mode.SelectedItem = c["Mode"]!.GetValue<string>(); diagnostics.SelectedItem = c["Diagnostics"]!.GetValue<string>(); port.Value = c["Port"]!.GetValue<int>(); poll.Value = c["PollSeconds"]!.GetValue<int>(); httpUrl.Text = c["HttpProbeUrl"]!.GetValue<string>();
    }
    private async Task SaveConfiguration(bool settings)
    {
        if (busy || configuration == null) { Feedback("请先完成安装并载入有效配置。"); return; }
        SetBusy(true);
        try
        {
            string root = (await Task.Run(AppController.InstalledRoot))!; var draft = (JsonObject)configuration.Values.DeepClone();
            if (settings) { draft["LoginMonitor"] = login.Checked; draft["TrayAutoStart"] = trayLogin.Checked; draft["CloseToTray"] = close.Checked; draft["MinimizeToTray"] = minimize.Checked; draft["Mode"] = mode.SelectedItem!.ToString(); draft["Diagnostics"] = diagnostics.SelectedItem!.ToString(); draft["Port"] = (int)port.Value; draft["PollSeconds"] = (int)poll.Value; draft["HttpProbeUrl"] = httpUrl.Text; }
            else draft["Whitelist"] = new JsonArray(draftNames.Select(n => (JsonNode?)JsonValue.Create(n)).ToArray());
            configuration = await Task.Run(() => ConfigurationStore.Save(root, configuration, draft)); pendingRevision = configuration.Revision;
            if (!settings) LoadNames();
            if (settings && controller != null && AppController.TestRoot == null) { var result = await controller.Execute(new("settings")); if (!result.Succeeded) throw new IOException("配置已保存，但登录设置未应用：" + result.Message); }
            Feedback("保存成功，等待后台载入并重新确认网络；暂停时不会改写代理。");
            if (AppController.TestRoot == null && !(await File.ReadAllTextAsync(Path.Combine(root, "ProxyWatcher.ps1"))).Contains("Update-MonitorConfiguration", StringComparison.Ordinal)) Feedback("配置已保存；旧后台引擎不支持热更新，请在高级操作中修复安装 / 升级。");
        }
        catch (Exception e) { ShowError(e); }
        finally { SetBusy(false); await RefreshAsync(); }
    }
    internal Task ToggleAutomatic() => Operate(CurrentStatus?.Installed != true ? "install" : CurrentStatus.Running && !CurrentStatus.Paused ? "pause" : "resume");
    internal async Task Operate(string command)
    {
        if (busy || controller == null) return;
        if (command is "restore" or "uninstall" or "install")
        {
            string text = command == "install" ? "将安装或升级当前用户的后台监控和登录任务，并按当前 Wi-Fi 规则管理手动代理。现有名单与最初代理备份会保留。" : "将先停止后台监控，再按冲突保护恢复安装前的手动代理。后续手动修改不会被自动覆盖。";
            if (MessageBox.Show(this, text, command == "uninstall" ? "确认卸载" : command == "install" ? "确认安装 / 升级" : "停止监控并恢复代理", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK) return;
        }
        SetBusy(true); Feedback("正在完成操作…");
        try
        {
            if (command == "uninstall") { await Task.Run(() => controller.BeginUninstall(new("uninstall"))); SetBusy(false); ExitRequested?.Invoke(); return; }
            var options = new Options(command); var result = await controller.Execute(options);
            if (result.Code == "RestoreConflict")
            {
                var choice = MessageBox.Show(this, "检测到后续手动代理修改。\n\n是：明确覆盖，恢复最初配置。\n否或取消：保留当前配置及备份。监控已经停止。", "代理配置冲突", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning);
                if (choice == DialogResult.Yes) result = await controller.Execute(options with { Force = true });
                else { Feedback("监控已停止，当前代理及原始备份均保留。"); return; }
            }
            if (!result.Succeeded) throw new IOException(result.Message);
            Feedback(command == "pause" ? "自动切换已暂停；当前手动代理保持不变，未恢复直连。" : command == "check" ? "已请求检测，后台将按稳定确认规则评估网络。" : "操作完成。");
            if (command == "install") await ReloadConfiguration();
        }
        catch (Exception e) { ShowError(e); }
        finally { SetBusy(false); await RefreshAsync(); }
    }
    private void SetBusy(bool value)
    {
        if (IsDisposed) { busy = value; return; }
        if (value) busy = true;
        foreach (var page in pages) page.Enabled = !value;
        busy = value; BusyChanged?.Invoke(value);
    }
    internal void Feedback(string text) { message.Text = text; tips.SetToolTip(message, text); }
    private void ShowError(Exception e) { Feedback(e.Message); if (AppController.TestRoot == null) MessageBox.Show(this, e.Message, "操作未完成", MessageBoxButtons.OK, MessageBoxIcon.Error); }
}
