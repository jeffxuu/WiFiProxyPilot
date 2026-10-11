using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;
internal sealed class MainForm : Form
{
    private readonly AppController? controller;
    private readonly Label[] values = new Label[6];
    private readonly Label message = new() { AutoSize = true, ForeColor = Color.FromArgb(70, 90, 110), Dock = DockStyle.Fill };
    private readonly TextBox logs = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both, WordWrap = false, Dock = DockStyle.Fill };
    private readonly FlowLayoutPanel buttons = new() { Dock = DockStyle.Fill, AutoSize = true, WrapContents = true };
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 3000 };
    private bool busy;
    internal MainForm(AppController? controller)
    {
        this.controller = controller;
        Text = "Wi-Fi 智能代理切换 · 3.0.0"; MinimumSize = new Size(780, 620); Size = new Size(1000, 760);
        StartPosition = FormStartPosition.CenterScreen; Font = new Font("Microsoft YaHei UI", 10F); BackColor = Color.FromArgb(247, 249, 252);
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), ColumnCount = 2, RowCount = 11 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150)); layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        var title = new Label { Text = "Wi-Fi 智能代理切换", AutoSize = true, Font = new Font(Font.FontFamily, 20, FontStyle.Bold), Margin = new Padding(0, 0, 0, 18) };
        layout.Controls.Add(title, 0, 0); layout.SetColumnSpan(title, 2);
        string[] labels = { "当前 SSID", "Wi-Fi 接口", "IPv4 网关", "系统手动代理", "Watcher 状态", "最近检测时间" };
        for (int i = 0; i < labels.Length; i++)
        {
            layout.Controls.Add(new Label { Text = labels[i], AutoSize = true, Margin = new Padding(0, 7, 0, 7) }, 0, i + 1);
            values[i] = new Label { Text = "读取中…", UseMnemonic = false, AutoSize = true, Dock = DockStyle.Fill, Margin = new Padding(0, 7, 0, 7) }; layout.Controls.Add(values[i], 1, i + 1);
        }
        AddButton("安装 / 修复", "install"); AddButton("启动监控", "start"); AddButton("停止监控", "stop"); AddButton("立即检测", "check"); AddButton("恢复代理", "restore"); AddButton("卸载", "uninstall");
        layout.Controls.Add(buttons, 0, 7); layout.SetColumnSpan(buttons, 2);
        layout.Controls.Add(message, 0, 8); layout.SetColumnSpan(message, 2);
        layout.Controls.Add(new Label { Text = "最近日志（关闭窗口不会停止后台监控）", AutoSize = true, Margin = new Padding(0, 14, 0, 8) }, 0, 9); layout.SetColumnSpan(layout.GetControlFromPosition(0, 9)!, 2);
        layout.Controls.Add(logs, 0, 10); layout.SetColumnSpan(logs, 2); layout.RowStyles.Clear();
        for (int i = 0; i < 10; i++) layout.RowStyles.Add(new RowStyle(SizeType.AutoSize)); layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        Controls.Add(layout);
        timer.Tick += (_, _) => RefreshStatus();
        Shown += async (_, _) => { if (controller == null) return; RefreshStatus(); timer.Start(); var root = AppController.InstalledRoot(); if (root == null || !File.Exists(Path.Combine(root, "app", "desktop.json"))) await Operate("install"); };
        FormClosing += (_, e) => { if (busy) { e.Cancel = true; message.Text = "正在完成操作，请稍候再关闭窗口。"; } };
        FormClosed += (_, _) => timer.Dispose();
    }
    private void AddButton(string text, string command)
    {
        var b = new Button { Text = text, AutoSize = true, Padding = new Padding(8, 5, 8, 5), Margin = new Padding(0, 8, 8, 8), FlatStyle = FlatStyle.Flat };
        b.Click += async (_, _) => await Operate(command); buttons.Controls.Add(b);
    }
    private void RefreshStatus()
    {
        if (busy || controller == null) return;
        try { var s = StatusReader.Read(); string[] data = { s.Ssid, s.Interface, s.Gateway, s.Proxy, s.Watcher, s.Updated }; for (int i = 0; i < data.Length; i++) values[i].Text = string.IsNullOrEmpty(data[i]) ? "—" : data[i]; logs.Text = s.Logs; }
        catch (Exception ex) { message.Text = "状态读取失败：" + ex.Message; }
    }
    private async Task Operate(string command)
    {
        if (busy || controller == null) return;
        if (command == "uninstall")
        {
            if (MessageBox.Show(this, "将停止监控并尝试恢复安装前的手动代理。发现后续修改时会再次询问。", "卸载", MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK) return;
            try { controller.BeginUninstall(new("uninstall")); Close(); } catch (Exception ex) { MessageBox.Show(this, ex.Message, "无法卸载", MessageBoxButtons.OK, MessageBoxIcon.Error); }
            return;
        }
        busy = true; buttons.Enabled = false; message.Text = "正在执行，请稍候…";
        try
        {
            var options = new Options(command); var result = await controller.Execute(options);
            if (result.Code == "RestoreConflict")
            {
                var choice = MessageBox.Show(this, "代理已被后来修改。\n\n选择“是”：恢复安装前配置。\n选择“否”：保留当前配置。\n选择“取消”：停止本次恢复。", "代理配置冲突", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning);
                if (choice == DialogResult.Yes) result = await controller.Execute(options with { Force = true });
                else { message.Text = "监控已停止；当前代理与原始备份均保留。"; return; }
            }
            message.Text = result.Succeeded ? "操作完成。Strict / Safe 与白名单规则保持原配置。" : result.Message;
            if (!result.Succeeded) MessageBox.Show(this, result.Message, "操作未完成", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        catch (Exception ex) { message.Text = ex.Message; MessageBox.Show(this, ex.Message, "操作未完成", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        finally { busy = false; buttons.Enabled = true; RefreshStatus(); }
    }
}
