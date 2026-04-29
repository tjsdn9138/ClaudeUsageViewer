using System.Windows.Forms;
using Microsoft.Win32;
using Windows.Data.Xml.Dom;
using Windows.UI.Notifications;

class TrayApp : ApplicationContext
{
    const string Aumid = "ClaudeUsageViewer.App";
    const double AlertThreshold80 = 80.0;
    const double AlertThreshold50 = 50.0;
    const string RunKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    const string AppName = "ClaudeUsageViewer";

    readonly NotifyIcon _tray;
    readonly System.Windows.Forms.Timer _timer;
    bool _alertedSession80, _alertedWeekly80;
    bool _alertedSession50, _alertedWeekly50;
    bool _refreshing;
    string? _lastError;

    public TrayApp()
    {
        RegisterAumid();

        _tray = new NotifyIcon
        {
            Icon = MakeIcon(Color.Gray),
            Text = "Claude Usage - 로딩 중...",
            Visible = true,
            ContextMenuStrip = BuildMenu()
        };

        _timer = new System.Windows.Forms.Timer { Interval = 60_000 };
        _timer.Tick += async (_, _) => await RefreshAsync();
        _timer.Start();

        _ = RefreshAsync();
    }

    ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("↻  새로고침", null, async (_, _) => await RefreshAsync());
        menu.Items.Add("오류 보기", null, (_, _) =>
        {
            var msg = _lastError ?? "오류 없음";
            MessageBox.Show(msg, "Claude Usage - 오류 상세", MessageBoxButtons.OK, MessageBoxIcon.Information);
        });
        menu.Items.Add(new ToolStripSeparator());

        var autoStartItem = new ToolStripMenuItem("시작 시 자동 실행")
        {
            Checked = IsAutoStartEnabled()
        };
        autoStartItem.Click += (_, _) =>
        {
            SetAutoStart(!autoStartItem.Checked);
            autoStartItem.Checked = IsAutoStartEnabled();
        };
        menu.Items.Add(autoStartItem);

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("종료", null, (_, _) => { _tray.Visible = false; Application.Exit(); });
        return menu;
    }

    static bool IsAutoStartEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        return key?.GetValue(AppName) != null;
    }

    static void SetAutoStart(bool enable)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)!;
        if (enable)
            key.SetValue(AppName, $"\"{Environment.ProcessPath}\"");
        else
            key.DeleteValue(AppName, throwOnMissingValue: false);
    }

    async Task RefreshAsync()
    {
        if (_refreshing) return;
        _refreshing = true;
        try
        {
            var data = await UsageService.FetchAsync();
            UpdateTray(data);
            CheckAlerts(data);
        }
        catch (Exception ex)
        {
            _lastError = ex.ToString();
            _tray.Icon = MakeIcon(Color.Gray);
            _tray.Text = Truncate($"Claude Usage\n오류: {ex.Message}");
        }
        finally
        {
            _refreshing = false;
        }
    }

    void UpdateTray(UsageData d)
    {
        var dominant = Math.Max(d.SessionPct, d.WeeklyPct);
        var color = dominant >= 80 ? Color.Red : dominant >= 50 ? Color.Orange : Color.LimeGreen;

        _tray.Icon = MakeIcon(color);
        _tray.Text = Truncate($"Claude Usage\n세션: {d.SessionPct:F1}%  |  주간: {d.WeeklyPct:F1}%");
    }

    void CheckAlerts(UsageData d)
    {
        if (d.SessionPct >= AlertThreshold80 && !_alertedSession80)
        {
            _alertedSession80 = true;
            ShowToast("세션 사용량 경고 🔴", $"5시간 세션이 {d.SessionPct:F1}%에 도달했습니다.");
        }
        else if (d.SessionPct < AlertThreshold80)
            _alertedSession80 = false;

        if (d.SessionPct >= AlertThreshold50 && !_alertedSession50)
        {
            _alertedSession50 = true;
            ShowToast("세션 사용량 알림 🟠", $"5시간 세션이 {d.SessionPct:F1}%에 도달했습니다.");
        }
        else if (d.SessionPct < AlertThreshold50)
            _alertedSession50 = false;

        if (d.WeeklyPct >= AlertThreshold80 && !_alertedWeekly80)
        {
            _alertedWeekly80 = true;
            ShowToast("주간 사용량 경고 🔴", $"7일 주간이 {d.WeeklyPct:F1}%에 도달했습니다.");
        }
        else if (d.WeeklyPct < AlertThreshold80)
            _alertedWeekly80 = false;

        if (d.WeeklyPct >= AlertThreshold50 && !_alertedWeekly50)
        {
            _alertedWeekly50 = true;
            ShowToast("주간 사용량 알림 🟠", $"7일 주간이 {d.WeeklyPct:F1}%에 도달했습니다.");
        }
        else if (d.WeeklyPct < AlertThreshold50)
            _alertedWeekly50 = false;
    }

    static void ShowToast(string title, string message)
    {
        var xml = new XmlDocument();
        xml.LoadXml($"""
            <toast>
              <visual>
                <binding template="ToastGeneric">
                  <text>{Escape(title)}</text>
                  <text>{Escape(message)}</text>
                </binding>
              </visual>
            </toast>
            """);

        ToastNotificationManager.CreateToastNotifier(Aumid).Show(new ToastNotification(xml));
    }

    static Icon MakeIcon(Color color)
    {
        var bmp = new Bitmap(16, 16);
        using var g = Graphics.FromImage(bmp);
        g.Clear(Color.Transparent);
        using var brush = new SolidBrush(color);
        g.FillEllipse(brush, 1, 1, 13, 13);
        return Icon.FromHandle(bmp.GetHicon());
    }

    // NotifyIcon.Text 최대 63자 제한
    static string Truncate(string s) => s.Length > 63 ? s[..63] : s;

    static string Escape(string s) =>
        s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");

    static void RegisterAumid()
    {
        using var key = Registry.CurrentUser.CreateSubKey($@"SOFTWARE\Classes\AppUserModelId\{Aumid}");
        key.SetValue("DisplayName", "Claude Usage Viewer");
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { _tray.Dispose(); _timer.Dispose(); }
        base.Dispose(disposing);
    }
}
