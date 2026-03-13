using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using DexBarWindows.Managers;
using DexBarWindows.Models;
using DexBarWindows.Services;
using Microsoft.Win32;

namespace DexBarWindows.Forms;

/// <summary>
/// Multi-tab settings dialog. Writes to AppSettings and CredentialStorage.
/// </summary>
public class SettingsForm : Form
{
    private readonly GlucoseMonitor _monitor;

    // Colors
    private static readonly Color BgColor      = Color.FromArgb(28, 28, 30);
    private static readonly Color SurfaceColor = Color.FromArgb(44, 44, 46);
    private static readonly Color TextPrimary  = Color.FromArgb(240, 240, 242);
    private static readonly Color TextSecondary = Color.FromArgb(160, 160, 168);

    public SettingsForm(GlucoseMonitor monitor)
    {
        _monitor = monitor;

        Text            = "DexBar Settings";
        Width           = 460;
        Height          = 520;
        MinimumSize     = new Size(460, 520);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        BackColor       = BgColor;
        ForeColor       = TextPrimary;
        StartPosition   = FormStartPosition.CenterScreen;

        var tabs = new TabControl
        {
            Dock      = DockStyle.Fill,
            BackColor = BgColor,
            ForeColor = TextPrimary
        };

        tabs.TabPages.Add(BuildAccountTab());
        tabs.TabPages.Add(BuildDisplayTab());
        tabs.TabPages.Add(BuildAlertsTab());
        tabs.TabPages.Add(BuildAboutTab());
        tabs.TabPages.Add(BuildDisclaimerTab());

        Controls.Add(tabs);
    }

    // =========================================================================
    // Account tab
    // =========================================================================

    private TabPage BuildAccountTab()
    {
        var page = MakeTabPage("Account");
        var s    = _monitor.Settings;

        var lblUser  = MakeLabel("Dexcom Username / Email");
        var txtUser  = MakeTextBox(s.DexcomUsername ?? "");
        var lblPass  = MakeLabel("Password");
        var txtPass  = MakeTextBox("", masked: true);
        var lblRegion = MakeLabel("Region");
        var cmbRegion = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            BackColor     = SurfaceColor,
            ForeColor     = TextPrimary,
            FlatStyle     = FlatStyle.Flat,
            Width         = 200
        };
        foreach (var r in Enum.GetValues<DexcomRegion>())
            cmbRegion.Items.Add(r);
        cmbRegion.SelectedItem = s.Region;

        var btnConnect  = new Button
        {
            Text      = "Connect",
            Width     = 100,
            Height    = 30,
            BackColor = Color.FromArgb(10, 132, 255),
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            FlatAppearance = { BorderSize = 0 },
            Cursor    = Cursors.Hand
        };
        var lblStatus = new Label
        {
            Text      = "",
            ForeColor = Color.Gray,
            AutoSize  = true,
            MaximumSize = new Size(320, 40)
        };

        // Load stored password
        try { txtPass.Text = CredentialStorage.LoadPassword() ?? ""; }
        catch { /* no credential */ }

        btnConnect.Click += async (_, _) =>
        {
            btnConnect.Enabled = false;
            btnConnect.Text    = "Connecting…";
            lblStatus.Text     = "";

            var username = txtUser.Text.Trim();
            var password = txtPass.Text;
            var region   = cmbRegion.SelectedItem is DexcomRegion r ? r : DexcomRegion.US;

            try { CredentialStorage.SavePassword(password); }
            catch (Exception ex)
            {
                lblStatus.ForeColor = Color.FromArgb(255, 69, 58);
                lblStatus.Text      = $"Credential error: {ex.Message}";
                btnConnect.Enabled  = true;
                btnConnect.Text     = "Connect";
                return;
            }

            try
            {
                await _monitor.StartAsync(username, password, region);
                _monitor.Settings.Save();
                lblStatus.ForeColor = Color.FromArgb(52, 199, 89);
                lblStatus.Text      = "✓ Authenticated — fetching readings…";
            }
            catch (Exception ex)
            {
                lblStatus.ForeColor = Color.FromArgb(255, 69, 58);
                lblStatus.Text      = ex.Message;
            }

            btnConnect.Enabled = true;
            btnConnect.Text    = "Connect";
        };

        var flow = MakeFormFlow(page);
        flow.Controls.Add(lblUser);
        flow.Controls.Add(txtUser);
        flow.Controls.Add(lblPass);
        flow.Controls.Add(txtPass);
        flow.Controls.Add(lblRegion);
        flow.Controls.Add(cmbRegion);
        flow.Controls.Add(MakeSpacer(8));
        flow.Controls.Add(btnConnect);
        flow.Controls.Add(lblStatus);

        return page;
    }

    // =========================================================================
    // Display tab
    // =========================================================================

    private TabPage BuildDisplayTab()
    {
        var page = MakeTabPage("Display");
        var s    = _monitor.Settings;

        // Unit
        var rdMgdL  = MakeRadio("mg/dL",  s.Unit == GlucoseUnit.MgdL);
        var rdMmol  = MakeRadio("mmol/L", s.Unit == GlucoseUnit.MmolL);
        rdMgdL.CheckedChanged += (_, _) =>
        {
            if (rdMgdL.Checked) { s.Unit = GlucoseUnit.MgdL; s.Save(); }
        };
        rdMmol.CheckedChanged += (_, _) =>
        {
            if (rdMmol.Checked) { s.Unit = GlucoseUnit.MmolL; s.Save(); }
        };

        // Refresh interval
        var cmbRefresh = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            BackColor     = SurfaceColor,
            ForeColor     = TextPrimary,
            FlatStyle     = FlatStyle.Flat,
            Width         = 200
        };
        var refreshOptions = new (int seconds, string label)[]
        {
            (60,  "1 minute"),
            (120, "2 minutes"),
            (300, "5 minutes"),
            (600, "10 minutes"),
            (900, "15 minutes")
        };
        foreach (var (_, lbl) in refreshOptions)
            cmbRefresh.Items.Add(lbl);

        int idx = Array.FindIndex(refreshOptions, x => x.seconds == s.RefreshIntervalSeconds);
        cmbRefresh.SelectedIndex = idx >= 0 ? idx : 2; // default 5 min
        cmbRefresh.SelectedIndexChanged += (_, _) =>
        {
            s.RefreshInterval = TimeSpan.FromSeconds(refreshOptions[cmbRefresh.SelectedIndex].seconds);
            s.Save();
            _monitor.UpdateRefreshInterval(s.RefreshInterval);
        };

        // Checkboxes
        var chkDelta  = MakeCheckBox("Show delta (e.g. +3 or −0.2)", s.ShowDelta);
        var chkColored = MakeCheckBox("Color-coded tray icon",         s.ColoredTrayIcon);
        var chkLogin  = MakeCheckBox("Launch at login",
            IsRegisteredForStartup());

        chkDelta.CheckedChanged += (_, _) => { s.ShowDelta = chkDelta.Checked; s.Save(); };
        chkColored.CheckedChanged += (_, _) => { s.ColoredTrayIcon = chkColored.Checked; s.Save(); };
        chkLogin.CheckedChanged += (_, _) => SetStartupRegistration(chkLogin.Checked);

        // Color pickers
        var colorRows = new[]
        {
            ("Urgent Low",  nameof(s.ColorUrgentLow)),
            ("Low",         nameof(s.ColorLow)),
            ("In Range",    nameof(s.ColorInRange)),
            ("High",        nameof(s.ColorHigh)),
            ("Urgent High", nameof(s.ColorUrgentHigh))
        };

        var flow = MakeFormFlow(page);
        flow.Controls.Add(MakeSectionLabel("Blood Sugar Unit"));
        var unitRow = new FlowLayoutPanel { AutoSize = true, BackColor = Color.Transparent };
        unitRow.Controls.Add(rdMgdL);
        unitRow.Controls.Add(rdMmol);
        flow.Controls.Add(unitRow);
        flow.Controls.Add(MakeSpacer(4));
        flow.Controls.Add(MakeSectionLabel("Refresh Interval"));
        flow.Controls.Add(cmbRefresh);
        flow.Controls.Add(MakeSpacer(4));
        flow.Controls.Add(MakeSectionLabel("Options"));
        flow.Controls.Add(chkDelta);
        flow.Controls.Add(chkColored);
        flow.Controls.Add(chkLogin);
        flow.Controls.Add(MakeSpacer(4));
        flow.Controls.Add(MakeSectionLabel("Range Colors"));

        foreach (var (label, propName) in colorRows)
        {
            var prop = typeof(AppSettings).GetProperty(propName)!;
            var currentHex = (string)prop.GetValue(s)!;
            var row = MakeColorRow(label, currentHex, hex =>
            {
                prop.SetValue(s, hex);
                s.Save();
            });
            flow.Controls.Add(row);
        }

        return page;
    }

    // =========================================================================
    // Alerts tab
    // =========================================================================

    private TabPage BuildAlertsTab()
    {
        var page = MakeTabPage("Alerts");
        var s    = _monitor.Settings;

        var flow = MakeFormFlow(page);

        flow.Controls.Add(new Label
        {
            Text      = "Thresholds define color zones and optional notifications.\nValues must stay ordered: Urgent Low < Low < High < Urgent High.",
            ForeColor = TextSecondary,
            Font      = new Font("Segoe UI", 8.5f),
            AutoSize  = true,
            Padding   = new Padding(0, 0, 0, 4)
        });

        void AddThreshold(string section, string enableProp, string threshProp, int min, int max)
        {
            flow.Controls.Add(MakeSectionLabel(section));

            var sProp = typeof(AppSettings).GetProperty(enableProp)!;
            var tProp = typeof(AppSettings).GetProperty(threshProp)!;

            var chk = MakeCheckBox("Alert enabled", (bool)sProp.GetValue(s)!);
            chk.CheckedChanged += (_, _) => { sProp.SetValue(s, chk.Checked); s.Save(); };

            var nud = new NumericUpDown
            {
                Minimum   = min,
                Maximum   = max,
                Value     = Math.Clamp((int)tProp.GetValue(s)!, min, max),
                Width     = 100,
                BackColor = SurfaceColor,
                ForeColor = TextPrimary
            };
            nud.ValueChanged += (_, _) => { tProp.SetValue(s, (int)nud.Value); s.Save(); };

            var row = new FlowLayoutPanel
            {
                AutoSize      = true,
                FlowDirection = FlowDirection.LeftToRight,
                BackColor     = Color.Transparent,
                Padding       = new Padding(0)
            };
            row.Controls.Add(nud);
            row.Controls.Add(new Label
            {
                Text      = "mg/dL",
                ForeColor = TextSecondary,
                AutoSize  = true,
                Padding   = new Padding(2, 6, 0, 0)
            });

            flow.Controls.Add(chk);
            flow.Controls.Add(row);
            flow.Controls.Add(MakeSpacer(4));
        }

        AddThreshold("Urgent High", nameof(s.AlertUrgentHighEnabled), nameof(s.AlertUrgentHighThresholdMgdL), 181, 400);
        AddThreshold("High",        nameof(s.AlertHighEnabled),       nameof(s.AlertHighThresholdMgdL),       120, 399);
        AddThreshold("Low",         nameof(s.AlertLowEnabled),        nameof(s.AlertLowThresholdMgdL),         56, 180);
        AddThreshold("Urgent Low",  nameof(s.AlertUrgentLowEnabled),  nameof(s.AlertUrgentLowThresholdMgdL),   40, 109);

        flow.Controls.Add(MakeSectionLabel("Trend Alerts"));
        var chkRising   = MakeCheckBox("Alert on rising fast (↑ ⇈)",    s.AlertRisingFastEnabled);
        var chkDropping = MakeCheckBox("Alert on dropping fast (↓ ⇊)", s.AlertDroppingFastEnabled);
        chkRising.CheckedChanged   += (_, _) => { s.AlertRisingFastEnabled   = chkRising.Checked;   s.Save(); };
        chkDropping.CheckedChanged += (_, _) => { s.AlertDroppingFastEnabled = chkDropping.Checked; s.Save(); };
        flow.Controls.Add(chkRising);
        flow.Controls.Add(chkDropping);
        flow.Controls.Add(MakeSpacer(4));

        flow.Controls.Add(MakeSectionLabel("No Data"));
        var chkStale = MakeCheckBox("Alert when no new readings for 20 min", s.AlertStaleDataEnabled);
        chkStale.CheckedChanged += (_, _) => { s.AlertStaleDataEnabled = chkStale.Checked; s.Save(); };
        flow.Controls.Add(chkStale);

        return page;
    }

    // =========================================================================
    // About tab
    // =========================================================================

    private TabPage BuildAboutTab()
    {
        var page = MakeTabPage("About");

        var version = typeof(SettingsForm).Assembly
            .GetName().Version?.ToString(3) ?? "—";

        var panel = new Panel { Dock = DockStyle.Fill, BackColor = BgColor };

        var lblName = new Label
        {
            Text      = "DexBar",
            Font      = new Font("Segoe UI", 18f, FontStyle.Bold),
            ForeColor = TextPrimary,
            AutoSize  = true
        };
        var lblVersion = new Label
        {
            Text      = $"Version {version}",
            ForeColor = TextSecondary,
            AutoSize  = true
        };
        var lblPlatform = new Label
        {
            Text      = "Windows Edition",
            ForeColor = TextSecondary,
            AutoSize  = true
        };

        var lnkGitHub = new LinkLabel
        {
            Text      = "View on GitHub",
            ForeColor = Color.FromArgb(10, 132, 255),
            AutoSize  = true,
            LinkColor = Color.FromArgb(10, 132, 255),
            Cursor    = Cursors.Hand
        };
        lnkGitHub.LinkClicked += (_, _) =>
            Process.Start(new ProcessStartInfo("https://github.com/SucculentGoose/dexbar") { UseShellExecute = true });

        var flow = new FlowLayoutPanel
        {
            Dock          = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents  = false,
            BackColor     = BgColor,
            Padding       = new Padding(24, 40, 24, 24)
        };
        flow.Controls.Add(lblName);
        flow.Controls.Add(lblVersion);
        flow.Controls.Add(lblPlatform);
        flow.Controls.Add(MakeSpacer(16));
        flow.Controls.Add(lnkGitHub);

        panel.Controls.Add(flow);
        page.Controls.Add(panel);

        return page;
    }

    // =========================================================================
    // Disclaimer tab
    // =========================================================================

    private TabPage BuildDisclaimerTab()
    {
        var page = MakeTabPage("Disclaimer");

        var rtb = new RichTextBox
        {
            Dock      = DockStyle.Fill,
            BackColor = BgColor,
            ForeColor = TextPrimary,
            Font      = new Font("Segoe UI", 9f),
            ReadOnly  = true,
            BorderStyle = BorderStyle.None,
            ScrollBars = RichTextBoxScrollBars.Vertical,
            Padding   = new Padding(12),
            Text      =
@"NOT A MEDICAL DEVICE

DexBar is an unofficial convenience tool and is not a medical device. It is not approved, certified, or intended for use in medical diagnosis, treatment, or any clinical decision-making.

Blood glucose data displayed by DexBar is sourced from the Dexcom Share service and may be delayed, inaccurate, or unavailable due to network conditions, sensor issues, or API changes beyond our control.

Always verify your blood sugar using your official Dexcom receiver, the Dexcom app, or another clinically approved method before making any medical decisions — including adjusting insulin, food intake, or physical activity.

Do not rely solely on this app. In an emergency, contact emergency services or a qualified healthcare professional immediately.

DexBar is not affiliated with or endorsed by Dexcom, Inc."
        };

        page.Controls.Add(rtb);
        return page;
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private static TabPage MakeTabPage(string title)
    {
        return new TabPage
        {
            Text      = title,
            BackColor = Color.FromArgb(28, 28, 30),
            ForeColor = Color.FromArgb(240, 240, 242)
        };
    }

    private static FlowLayoutPanel MakeFormFlow(TabPage page)
    {
        var flow = new FlowLayoutPanel
        {
            Dock          = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents  = false,
            AutoScroll    = true,
            BackColor     = Color.FromArgb(28, 28, 30),
            Padding       = new Padding(16, 16, 16, 16)
        };
        page.Controls.Add(flow);
        return flow;
    }

    private static Label MakeLabel(string text)
    {
        return new Label
        {
            Text      = text,
            ForeColor = Color.FromArgb(160, 160, 168),
            AutoSize  = true,
            Padding   = new Padding(0, 4, 0, 2)
        };
    }

    private static Label MakeSectionLabel(string text)
    {
        return new Label
        {
            Text      = text,
            ForeColor = Color.FromArgb(120, 120, 130),
            Font      = new Font("Segoe UI", 8f, FontStyle.Bold),
            AutoSize  = true,
            Padding   = new Padding(0, 6, 0, 2)
        };
    }

    private static TextBox MakeTextBox(string value, bool masked = false)
    {
        return new TextBox
        {
            Text            = value,
            UseSystemPasswordChar = masked,
            Width           = 360,
            BackColor       = Color.FromArgb(44, 44, 46),
            ForeColor       = Color.FromArgb(240, 240, 242),
            BorderStyle     = BorderStyle.FixedSingle
        };
    }

    private static RadioButton MakeRadio(string text, bool isChecked)
    {
        return new RadioButton
        {
            Text      = text,
            Checked   = isChecked,
            ForeColor = Color.FromArgb(240, 240, 242),
            AutoSize  = true,
            Padding   = new Padding(0, 0, 8, 0)
        };
    }

    private static CheckBox MakeCheckBox(string text, bool isChecked)
    {
        return new CheckBox
        {
            Text      = text,
            Checked   = isChecked,
            ForeColor = Color.FromArgb(240, 240, 242),
            AutoSize  = true,
            Padding   = new Padding(0, 2, 0, 2)
        };
    }

    private static Panel MakeSpacer(int height)
    {
        return new Panel { Height = height, BackColor = Color.Transparent };
    }

    private static Panel MakeColorRow(string label, string currentHex, Action<string> onChanged)
    {
        var panel = new Panel
        {
            AutoSize  = true,
            BackColor = Color.Transparent,
            Padding   = new Padding(0, 2, 0, 2)
        };

        var lbl = new Label
        {
            Text      = label,
            ForeColor = Color.FromArgb(200, 200, 210),
            AutoSize  = true,
            Location  = new Point(0, 6)
        };

        Color current;
        try { current = ColorTranslator.FromHtml(currentHex); }
        catch { current = Color.Gray; }

        var swatch = new Panel
        {
            Width     = 28,
            Height    = 20,
            BackColor = current,
            BorderStyle = BorderStyle.FixedSingle,
            Cursor    = Cursors.Hand,
            Location  = new Point(360, 2)
        };

        swatch.Click += (_, _) =>
        {
            using var dlg = new ColorDialog
            {
                Color          = swatch.BackColor,
                FullOpen       = true,
                AnyColor       = true,
                SolidColorOnly = true
            };
            if (dlg.ShowDialog() == DialogResult.OK)
            {
                swatch.BackColor = dlg.Color;
                var hex = $"#{dlg.Color.R:X2}{dlg.Color.G:X2}{dlg.Color.B:X2}";
                onChanged(hex);
            }
        };

        panel.Width = 400;
        panel.Height = 28;
        panel.Controls.Add(lbl);
        panel.Controls.Add(swatch);
        return panel;
    }

    // -------------------------------------------------------------------------
    // Launch at login (Windows registry)
    // -------------------------------------------------------------------------

    private const string StartupRegKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    private const string AppName = "DexBar";

    private static bool IsRegisteredForStartup()
    {
        using var key = Registry.CurrentUser.OpenSubKey(StartupRegKey);
        return key?.GetValue(AppName) is not null;
    }

    private static void SetStartupRegistration(bool enable)
    {
        using var key = Registry.CurrentUser.OpenSubKey(StartupRegKey, writable: true);
        if (key is null) return;

        if (enable)
        {
            var exePath = Process.GetCurrentProcess().MainModule?.FileName;
            if (exePath is not null)
                key.SetValue(AppName, $"\"{exePath}\"");
        }
        else
        {
            key.DeleteValue(AppName, throwOnMissingValue: false);
        }
    }
}
