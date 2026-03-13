using System.Drawing;
using System.Drawing.Text;
using System.Windows.Forms;
using DexBarWindows.Controls;
using DexBarWindows.Managers;
using DexBarWindows.Models;

namespace DexBarWindows.Forms;

/// <summary>
/// Borderless popup shown when the user left-clicks the tray icon.
/// Displays the current glucose reading, chart, TiR stats, and quick actions.
/// </summary>
public class PopupForm : Form
{
    public event Action? OpenSettingsRequested;

    private readonly GlucoseMonitor _monitor;
    private Point _dragStart;
    private bool  _dragging;

    // ── Header ──────────────────────────────────────────────────────────────
    private readonly Panel        _pnlStale;
    private readonly Label        _lblValue;
    private readonly Label        _lblTrend;
    private readonly Label        _lblStatus;
    private readonly Label        _lblUpdated;

    // ── Chart ────────────────────────────────────────────────────────────────
    private readonly GlucoseChartControl _chart;
    private readonly Panel               _pnlRangeButtons;

    private readonly Label        _lblStaleText;

    // ── TiR ──────────────────────────────────────────────────────────────────
    private readonly Label        _lblTirHeader;
    private readonly Panel        _pnlStatsRange;
    private readonly TirBarControl _tirBar;
    private readonly Label        _lblLowPct;
    private readonly Label        _lblInRangePct;
    private readonly Label        _lblHighPct;
    private readonly Label        _lblGmi;

    // Colors
    private static readonly Color BgColor      = Color.FromArgb(28, 28, 30);
    private static readonly Color DividerColor = Color.FromArgb(58, 58, 62);
    private static readonly Color TextPrimary  = Color.FromArgb(240, 240, 242);
    private static readonly Color TextSecondary = Color.FromArgb(160, 160, 168);
    private static readonly Color TextTertiary  = Color.FromArgb(100, 100, 108);
    private const int FormWidth = 340;

    public PopupForm(GlucoseMonitor monitor)
    {
        _monitor = monitor;

        // Form setup — fixed size, no task-bar entry, borderless dark popup
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar   = false;
        TopMost         = true;
        BackColor       = BgColor;
        Width           = FormWidth;
        Height          = 420;   // stale(28)+header(80)+div+rangeBtns(34)+chart(130)+div+tir(103)+div+actions(40)

        // ── Stale warning banner (always in layout; colour-toggles when stale) ─
        _pnlStale = new Panel
        {
            BackColor = BgColor,   // transparent until stale
            Height    = 28,
            Dock      = DockStyle.Top
        };
        _lblStaleText = new Label
        {
            Text      = "⚠  No new readings for 20+ min",
            ForeColor = Color.White,
            AutoSize  = false,
            Dock      = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleCenter,
            Font      = new Font("Segoe UI", 9f),
            Visible   = false
        };
        _pnlStale.Controls.Add(_lblStaleText);

        // ── Header panel ────────────────────────────────────────────────────
        var pnlHeader = new Panel
        {
            BackColor = BgColor,
            Dock      = DockStyle.Top,
            Height    = 80,
            Padding   = new Padding(16, 10, 16, 10)
        };

        _lblValue = new Label
        {
            Text      = "--",
            ForeColor = TextPrimary,
            Font      = new Font("Segoe UI", 30f, FontStyle.Bold),
            AutoSize  = true,
            Location  = new Point(16, 10)
        };

        _lblTrend = new Label
        {
            Text      = "Loading...",
            ForeColor = TextSecondary,
            Font      = new Font("Segoe UI", 10f),
            AutoSize  = true,
            Location  = new Point(16, 52)
        };

        _lblStatus = new Label
        {
            Text      = "Disconnected",
            ForeColor = TextSecondary,
            Font      = new Font("Segoe UI", 8.5f),
            AutoSize  = true
        };

        _lblUpdated = new Label
        {
            Text      = "",
            ForeColor = TextTertiary,
            Font      = new Font("Segoe UI", 8f),
            AutoSize  = true
        };

        pnlHeader.Controls.Add(_lblValue);
        pnlHeader.Controls.Add(_lblTrend);
        pnlHeader.Controls.Add(_lblStatus);
        pnlHeader.Controls.Add(_lblUpdated);

        // ── Chart (must come before BuildRangeButtons which reads _chart.SelectedRange) ──
        _chart = new GlucoseChartControl(_monitor)
        {
            Dock   = DockStyle.Top,
            Height = 130
        };

        // ── Chart range buttons ──────────────────────────────────────────────
        _pnlRangeButtons = new Panel
        {
            BackColor = BgColor,
            Dock      = DockStyle.Top,
            Height    = 34,
            Padding   = new Padding(16, 6, 16, 0)
        };
        BuildRangeButtons();

        // ── TiR header ───────────────────────────────────────────────────────
        _lblTirHeader = new Label
        {
            Text      = "Time in Range",
            ForeColor = TextSecondary,
            Font      = new Font("Segoe UI", 8.5f, FontStyle.Bold),
            AutoSize  = false,
            Dock      = DockStyle.Top,
            Height    = 20,
            Padding   = new Padding(16, 4, 0, 0)
        };

        // ── Stats range buttons ──────────────────────────────────────────────
        _pnlStatsRange = new Panel
        {
            BackColor = BgColor,
            Dock      = DockStyle.Top,
            Height    = 30,
            Padding   = new Padding(16, 4, 16, 0)
        };
        BuildStatsRangeButtons();

        // ── TiR bar ──────────────────────────────────────────────────────────
        _tirBar = new TirBarControl
        {
            Dock   = DockStyle.Top,
            Height = 8,
            Margin = new Padding(16, 0, 16, 0)
        };
        var pnlTirBarWrapper = new Panel
        {
            BackColor = BgColor,
            Dock      = DockStyle.Top,
            Height    = 12,
            Padding   = new Padding(16, 2, 16, 0)
        };
        _tirBar.Dock    = DockStyle.Fill;
        pnlTirBarWrapper.Controls.Add(_tirBar);

        // ── TiR percentages ──────────────────────────────────────────────────
        var pnlTirPcts = new Panel
        {
            BackColor = BgColor,
            Dock      = DockStyle.Top,
            Height    = 22,
            Padding   = new Padding(16, 2, 16, 0)
        };

        _lblLowPct = MakeTirPctLabel("↓ 0%", ContentAlignment.MiddleLeft);
        _lblInRangePct = MakeTirPctLabel("✓ 0%", ContentAlignment.MiddleCenter);
        _lblHighPct = MakeTirPctLabel("↑ 0%", ContentAlignment.MiddleRight);

        _lblLowPct.Dock    = DockStyle.Left;
        _lblLowPct.Width   = (FormWidth - 32) / 3;
        _lblInRangePct.Dock = DockStyle.Left;
        _lblInRangePct.Width = (FormWidth - 32) / 3;
        _lblHighPct.Dock   = DockStyle.Fill;

        pnlTirPcts.Controls.Add(_lblHighPct);
        pnlTirPcts.Controls.Add(_lblInRangePct);
        pnlTirPcts.Controls.Add(_lblLowPct);

        // ── GMI label ────────────────────────────────────────────────────────
        _lblGmi = new Label
        {
            Text      = "",
            ForeColor = TextTertiary,
            Font      = new Font("Segoe UI", 8f),
            AutoSize  = false,
            Dock      = DockStyle.Top,
            Height    = 20,
            Padding   = new Padding(16, 2, 16, 0),
            TextAlign = ContentAlignment.TopLeft
        };

        // ── Actions ──────────────────────────────────────────────────────────
        var pnlActions = new Panel
        {
            BackColor = BgColor,
            Dock      = DockStyle.Top,
            Height    = 40,
            Padding   = new Padding(0, 4, 0, 4)
        };

        var btnRefresh = MakeActionButton("↺  Refresh Now");
        btnRefresh.Click += async (_, _) => await _monitor.RefreshNowAsync();

        var btnSettings = MakeActionButton("⚙  Settings…");
        btnSettings.Click += (_, _) =>
        {
            Hide();
            OpenSettingsRequested?.Invoke();
        };

        var btnQuit = MakeActionButton("✕  Quit");
        btnQuit.Click += (_, _) => Application.Exit();

        var flowActions = new FlowLayoutPanel
        {
            Dock          = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents  = false,
            BackColor     = BgColor,
            Padding       = new Padding(8, 0, 8, 0)
        };
        flowActions.Controls.Add(btnRefresh);
        flowActions.Controls.Add(MakeActionDivider());
        flowActions.Controls.Add(btnSettings);
        flowActions.Controls.Add(MakeActionDivider());
        flowActions.Controls.Add(btnQuit);
        pnlActions.Controls.Add(flowActions);

        // ── Assemble (reverse order for Dock.Top stacking) ───────────────────
        var layout = new Panel
        {
            Dock      = DockStyle.Fill,
            BackColor = BgColor
        };

        void AddSection(Control c) => layout.Controls.Add(c);
        void AddDivider() => AddSection(MakeDivider());

        // Add in reverse visual order (last added = top)
        AddSection(pnlActions);
        AddDivider();
        AddSection(_lblGmi);
        AddSection(pnlTirPcts);
        AddSection(pnlTirBarWrapper);
        AddSection(_pnlStatsRange);
        AddSection(_lblTirHeader);
        AddDivider();
        AddSection(_chart);
        AddSection(_pnlRangeButtons);
        AddDivider();
        AddSection(pnlHeader);
        AddSection(_pnlStale);

        Controls.Add(layout);

        // Border
        Paint += (_, e) =>
        {
            using var pen = new Pen(DividerColor, 1f);
            e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
        };

        // Allow the form to be dragged by clicking anywhere on it.
        // Must be applied recursively because DockStyle.Fill child panels
        // cover the entire form surface and absorb all mouse events.
        MakeDraggable(this);

        UpdateDisplay();
        _monitor.OnUpdate += UpdateDisplay;
    }

    // -------------------------------------------------------------------------
    // Drag-to-move (borderless form has no title bar)
    // -------------------------------------------------------------------------

    private void MakeDraggable(Control root)
    {
        foreach (Control c in root.Controls)
        {
            // Skip interactive controls — they need their own mouse events
            if (c is Button or TextBox or ComboBox or NumericUpDown
                   or CheckBox or RadioButton or LinkLabel
                   or GlucoseChartControl or TirBarControl)
                continue;

            c.MouseDown += OnDragStart;
            c.MouseMove += OnDragMove;
            c.MouseUp   += OnDragEnd;
            MakeDraggable(c);
        }
    }

    private void OnDragStart(object? sender, MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
        {
            _dragging  = true;
            _dragStart = Cursor.Position;
        }
    }

    private void OnDragMove(object? sender, MouseEventArgs e)
    {
        if (!_dragging) return;
        var current = Cursor.Position;
        Location = new Point(
            Left + current.X - _dragStart.X,
            Top  + current.Y - _dragStart.Y);
        _dragStart = current;
    }

    private void OnDragEnd(object? sender, MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
            _dragging = false;
    }

    // -------------------------------------------------------------------------
    // Update
    // -------------------------------------------------------------------------

    private void UpdateDisplay()
    {
        if (InvokeRequired) { Invoke(UpdateDisplay); return; }

        var settings = _monitor.Settings;
        var reading  = _monitor.CurrentReading;
        var state    = _monitor.State;

        // Stale banner (background colour-toggles; layout height stays constant)
        bool isStale = _monitor.IsStale && state is MonitorState.Connected;
        _pnlStale.BackColor    = isStale ? Color.FromArgb(255, 140, 0) : BgColor;
        _lblStaleText.Visible  = isStale;

        if (reading is not null)
        {
            var color = ParseHex(settings.GlucoseColor(reading.Value));
            _lblValue.ForeColor = color;
            _lblValue.Text = $"{reading.DisplayValue(settings.Unit)} {reading.Trend.Arrow()}";

            var parts = new List<string> { reading.Trend.Description(), settings.Unit == GlucoseUnit.MmolL ? "mmol/L" : "mg/dL" };
            if (settings.ShowDelta && _monitor.GlucoseDelta is int delta)
            {
                var sign = delta >= 0 ? "+" : "";
                var deltaStr = settings.Unit == GlucoseUnit.MmolL
                    ? $"{sign}{delta / 18.0:F1}"
                    : $"{sign}{delta}";
                parts.Insert(1, deltaStr);
            }
            _lblTrend.Text = string.Join(" · ", parts);
        }
        else
        {
            _lblValue.ForeColor = TextSecondary;
            _lblValue.Text = state is MonitorState.Loading ? "…" : "--";
            _lblTrend.Text = state.StatusText;
        }

        // Right-side status + updated time
        (_lblStatus.Text, _lblStatus.ForeColor) = state switch
        {
            MonitorState.Connected => ("● Live",        Color.FromArgb(52, 199, 89)),
            MonitorState.Loading   => ("↻ Updating",    Color.FromArgb(10, 132, 255)),
            MonitorState.Error     => ("⚠ Error",       Color.FromArgb(255, 69, 58)),
            _                      => ("○ Disconnected", TextSecondary)
        };

        if (_monitor.LastUpdated is DateTime updated)
        {
            var ago = DateTime.UtcNow - updated;
            _lblUpdated.Text = ago.TotalSeconds < 60
                ? "Just now"
                : $"{(int)ago.TotalMinutes}m ago";
        }
        else
        {
            _lblUpdated.Text = "";
        }

        // Reposition right-side labels
        PositionHeaderRightLabels();

        // TiR
        UpdateTiR(settings);

        // Chart
        _chart.Invalidate();
    }

    private void PositionHeaderRightLabels()
    {
        _lblStatus.Location = new Point(FormWidth - 16 - _lblStatus.PreferredWidth, 14);
        _lblUpdated.Location = new Point(FormWidth - 16 - _lblUpdated.PreferredWidth, 32);
    }

    private void UpdateTiR(AppSettings settings)
    {
        var stats    = _monitor.TirStats;
        var lowColor = ParseHex(settings.ColorLow);
        var inColor  = ParseHex(settings.ColorInRange);
        var hiColor  = ParseHex(settings.ColorHigh);

        _lblTirHeader.Text = stats.Total > 0
            ? $"Time in Range  {stats.InRangePct:F0}%"
            : "Time in Range";

        _tirBar.LowPct     = stats.LowPct;
        _tirBar.InRangePct = stats.InRangePct;
        _tirBar.HighPct    = stats.HighPct;
        _tirBar.LowColor   = lowColor;
        _tirBar.InRangeColor = inColor;
        _tirBar.HighColor  = hiColor;
        _tirBar.Invalidate();

        _lblLowPct.ForeColor    = lowColor;
        _lblInRangePct.ForeColor = inColor;
        _lblHighPct.ForeColor   = hiColor;

        if (stats.Total > 0)
        {
            _lblLowPct.Text     = $"↓ {stats.LowPct:F0}%";
            _lblInRangePct.Text = $"✓ {stats.InRangePct:F0}%";
            _lblHighPct.Text    = $"↑ {stats.HighPct:F0}%";
        }
        else
        {
            _lblLowPct.Text = _lblInRangePct.Text = _lblHighPct.Text = "--";
        }

        if (_monitor.Gmi is double gmi && stats.Total > 0)
        {
            var span = _monitor.StatsDataSpanDays;
            _lblGmi.ForeColor = span < 14 ? TextTertiary : TextSecondary;
            _lblGmi.Text = span < 14
                ? $"GMI {gmi:F1}%  (based on {span:F1}d — 14d+ recommended)"
                : $"GMI {gmi:F1}%  ·  {stats.Total} readings";
        }
        else
        {
            _lblGmi.Text = "";
        }
    }

    // -------------------------------------------------------------------------
    // Auto-close on deactivation
    // -------------------------------------------------------------------------

    protected override void OnDeactivate(EventArgs e)
    {
        base.OnDeactivate(e);
        Hide();
    }

    // -------------------------------------------------------------------------
    // Builder helpers
    // -------------------------------------------------------------------------

    private void BuildRangeButtons()
    {
        var flow = new FlowLayoutPanel
        {
            Dock          = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents  = false,
            BackColor     = BgColor
        };

        var ranges = new[] {
            (TimeRange.ThreeHours,  "3h"),
            (TimeRange.SixHours,    "6h"),
            (TimeRange.TwelveHours, "12h"),
            (TimeRange.Day,         "24h")
        };

        foreach (var (range, label) in ranges)
        {
            var btn = MakeSegmentButton(label, range == _chart.SelectedRange);
            btn.Click += (_, _) =>
            {
                _chart.SelectedRange = range;
                RefreshRangeButtons(flow, range);
            };
            btn.Tag = range;
            flow.Controls.Add(btn);
        }

        _pnlRangeButtons.Controls.Add(flow);
    }

    private static void RefreshRangeButtons(FlowLayoutPanel flow, TimeRange selected)
    {
        foreach (Control c in flow.Controls)
        {
            if (c is Button btn && btn.Tag is TimeRange r)
                btn.BackColor = r == selected ? Color.FromArgb(70, 70, 80) : Color.FromArgb(44, 44, 46);
        }
    }

    private void BuildStatsRangeButtons()
    {
        var flow = new FlowLayoutPanel
        {
            Dock          = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents  = false,
            BackColor     = BgColor
        };

        var ranges = new[] {
            (StatsTimeRange.TwoDays,      "2d"),
            (StatsTimeRange.SevenDays,    "7d"),
            (StatsTimeRange.FourteenDays, "14d"),
            (StatsTimeRange.ThirtyDays,   "30d"),
            (StatsTimeRange.NinetyDays,   "90d")
        };

        foreach (var (range, label) in ranges)
        {
            var btn = MakeSegmentButton(label, range == _monitor.Settings.StatsTimeRange);
            btn.Click += (_, _) =>
            {
                _monitor.Settings.StatsTimeRange = range;
                _monitor.Settings.Save();
                RefreshStatsRangeButtons(flow, range);
                UpdateTiR(_monitor.Settings);
            };
            btn.Tag = range;
            flow.Controls.Add(btn);
        }

        _pnlStatsRange.Controls.Add(flow);
    }

    private static void RefreshStatsRangeButtons(FlowLayoutPanel flow, StatsTimeRange selected)
    {
        foreach (Control c in flow.Controls)
        {
            if (c is Button btn && btn.Tag is StatsTimeRange r)
                btn.BackColor = r == selected ? Color.FromArgb(70, 70, 80) : Color.FromArgb(44, 44, 46);
        }
    }

    private static Button MakeSegmentButton(string text, bool active)
    {
        return new Button
        {
            Text      = text,
            Width     = 46,
            Height    = 22,
            FlatStyle = FlatStyle.Flat,
            BackColor = active ? Color.FromArgb(70, 70, 80) : Color.FromArgb(44, 44, 46),
            ForeColor = Color.FromArgb(210, 210, 215),
            Font      = new Font("Segoe UI", 8f),
            Margin    = new Padding(0, 0, 4, 0),
            FlatAppearance = { BorderSize = 0 },
            Cursor    = Cursors.Hand
        };
    }

    private static Button MakeActionButton(string text)
    {
        return new Button
        {
            Text      = text,
            AutoSize  = true,
            Height    = 30,
            Padding   = new Padding(8, 0, 8, 0),
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.Transparent,
            ForeColor = TextPrimary,
            Font      = new Font("Segoe UI", 9f),
            FlatAppearance = { BorderSize = 0, MouseOverBackColor = Color.FromArgb(60, 60, 64) },
            Cursor    = Cursors.Hand
        };
    }

    private static Panel MakeActionDivider()
    {
        return new Panel
        {
            Width     = 1,
            Height    = 20,
            BackColor = DividerColor,
            Margin    = new Padding(2, 5, 2, 5)
        };
    }

    private static Panel MakeDivider()
    {
        return new Panel
        {
            Height    = 1,
            Dock      = DockStyle.Top,
            BackColor = DividerColor
        };
    }

    private static Label MakeTirPctLabel(string text, ContentAlignment align)
    {
        return new Label
        {
            Text      = text,
            ForeColor = TextSecondary,
            Font      = new Font("Segoe UI", 8.5f),
            AutoSize  = false,
            TextAlign = align
        };
    }

    private static Color ParseHex(string hex)
    {
        try { return ColorTranslator.FromHtml(hex); }
        catch { return Color.Gray; }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            _monitor.OnUpdate -= UpdateDisplay;
        base.Dispose(disposing);
    }
}
