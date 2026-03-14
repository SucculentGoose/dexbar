using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Color = System.Windows.Media.Color;
using Colors = System.Windows.Media.Colors;
using UserControl = System.Windows.Controls.UserControl;

namespace DexBarWindows.Controls;

public partial class TirBarControl : UserControl
{
    // --- Dependency Properties ---

    public static readonly DependencyProperty LowPctProperty =
        DependencyProperty.Register(nameof(LowPct), typeof(double), typeof(TirBarControl),
            new PropertyMetadata(0.0, OnSegmentChanged));

    public static readonly DependencyProperty InRangePctProperty =
        DependencyProperty.Register(nameof(InRangePct), typeof(double), typeof(TirBarControl),
            new PropertyMetadata(0.0, OnSegmentChanged));

    public static readonly DependencyProperty HighPctProperty =
        DependencyProperty.Register(nameof(HighPct), typeof(double), typeof(TirBarControl),
            new PropertyMetadata(0.0, OnSegmentChanged));

    public static readonly DependencyProperty LowColorProperty =
        DependencyProperty.Register(nameof(LowColor), typeof(Color), typeof(TirBarControl),
            new PropertyMetadata(Colors.OrangeRed, OnColorChanged));

    public static readonly DependencyProperty InRangeColorProperty =
        DependencyProperty.Register(nameof(InRangeColor), typeof(Color), typeof(TirBarControl),
            new PropertyMetadata(Colors.MediumSeaGreen, OnColorChanged));

    public static readonly DependencyProperty HighColorProperty =
        DependencyProperty.Register(nameof(HighColor), typeof(Color), typeof(TirBarControl),
            new PropertyMetadata(Colors.Gold, OnColorChanged));

    // --- CLR Properties ---

    public double LowPct
    {
        get => (double)GetValue(LowPctProperty);
        set => SetValue(LowPctProperty, value);
    }

    public double InRangePct
    {
        get => (double)GetValue(InRangePctProperty);
        set => SetValue(InRangePctProperty, value);
    }

    public double HighPct
    {
        get => (double)GetValue(HighPctProperty);
        set => SetValue(HighPctProperty, value);
    }

    public Color LowColor
    {
        get => (Color)GetValue(LowColorProperty);
        set => SetValue(LowColorProperty, value);
    }

    public Color InRangeColor
    {
        get => (Color)GetValue(InRangeColorProperty);
        set => SetValue(InRangeColorProperty, value);
    }

    public Color HighColor
    {
        get => (Color)GetValue(HighColorProperty);
        set => SetValue(HighColorProperty, value);
    }

    // --- Constructor ---

    public TirBarControl()
    {
        InitializeComponent();
        UpdateColumns();
        UpdateColors();
    }

    // --- Change Callbacks ---

    private static void OnSegmentChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        ((TirBarControl)d).UpdateColumns();
    }

    private static void OnColorChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        ((TirBarControl)d).UpdateColors();
    }

    // --- Update Helpers ---

    private void UpdateColumns()
    {
        double low     = LowPct;
        double inRange = InRangePct;
        double high    = HighPct;
        double total   = low + inRange + high;

        if (total <= 0)
        {
            // Avoid divide-by-zero: distribute equally so the bar renders
            LowColumn.Width     = new GridLength(1, GridUnitType.Star);
            InRangeColumn.Width = new GridLength(1, GridUnitType.Star);
            HighColumn.Width    = new GridLength(1, GridUnitType.Star);
        }
        else
        {
            LowColumn.Width     = new GridLength(low,     GridUnitType.Star);
            InRangeColumn.Width = new GridLength(inRange, GridUnitType.Star);
            HighColumn.Width    = new GridLength(high,    GridUnitType.Star);
        }
    }

    private void UpdateColors()
    {
        LowBorder.Background     = new SolidColorBrush(LowColor);
        InRangeBorder.Background = new SolidColorBrush(InRangeColor);
        HighBorder.Background    = new SolidColorBrush(HighColor);
    }
}
