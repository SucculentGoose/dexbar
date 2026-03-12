#if canImport(CGtk3)
import CGtk3
import Foundation

// MARK: - Type casting helpers for GTK3's C GObject hierarchy

typealias GWidget    = UnsafeMutablePointer<GtkWidget>
typealias GWindow    = UnsafeMutablePointer<GtkWindow>
typealias GContainer = UnsafeMutablePointer<GtkContainer>
typealias GBox       = UnsafeMutablePointer<GtkBox>
typealias GGrid      = UnsafeMutablePointer<GtkGrid>
typealias GLabel     = UnsafeMutablePointer<GtkLabel>
typealias GEntry     = UnsafeMutablePointer<GtkEntry>
typealias GButton    = UnsafeMutablePointer<GtkButton>
typealias GComboText = UnsafeMutablePointer<GtkComboBoxText>
typealias GCombo     = UnsafeMutablePointer<GtkComboBox>
typealias GNotebook  = UnsafeMutablePointer<GtkNotebook>
typealias GTBut      = UnsafeMutablePointer<GtkToggleButton>
typealias GSpinBut   = UnsafeMutablePointer<GtkSpinButton>
typealias GMShell    = UnsafeMutablePointer<GtkMenuShell>
typealias GMenuItem  = UnsafeMutablePointer<GtkMenuItem>

// Cast a GWidget to a more specific type via OpaquePointer bridge
func asWindow(_ w: GWidget?) -> GWindow?    { w.flatMap { GWindow(OpaquePointer($0)) } }
func asContainer(_ w: GWidget?) -> GContainer? { w.flatMap { GContainer(OpaquePointer($0)) } }
func asBox(_ w: GWidget?) -> GBox?          { w.flatMap { GBox(OpaquePointer($0)) } }
func asGrid(_ w: GWidget?) -> GGrid?        { w.flatMap { GGrid(OpaquePointer($0)) } }
func asLabel(_ w: GWidget?) -> GLabel?      { w.flatMap { GLabel(OpaquePointer($0)) } }
func asEntry(_ w: GWidget?) -> GEntry?      { w.flatMap { GEntry(OpaquePointer($0)) } }
func asComboText(_ w: GWidget?) -> GComboText? { w.flatMap { GComboText(OpaquePointer($0)) } }
func asCombo(_ w: GWidget?) -> GCombo?      { w.flatMap { GCombo(OpaquePointer($0)) } }
func asNotebook(_ w: GWidget?) -> GNotebook? { w.flatMap { GNotebook(OpaquePointer($0)) } }
func asToggle(_ w: GWidget?) -> GTBut?      { w.flatMap { GTBut(OpaquePointer($0)) } }
func asSpin(_ w: GWidget?) -> GSpinBut?     { w.flatMap { GSpinBut(OpaquePointer($0)) } }
func asMenuShell(_ w: GWidget?) -> GMShell? { w.flatMap { GMShell(OpaquePointer($0)) } }
func asMenuItem(_ w: GWidget?) -> GMenuItem? { w.flatMap { GMenuItem(OpaquePointer($0)) } }
func asMenu(_ w: GWidget?) -> UnsafeMutablePointer<GtkMenu>? { w.flatMap { UnsafeMutablePointer(OpaquePointer($0)) } }

// MARK: - Convenience wrappers

func gtkBox(orientation: GtkOrientation, spacing: Int32 = 0) -> GWidget {
    gtk_box_new(orientation, spacing)!
}
func gtkLabel(_ text: String) -> GWidget { gtk_label_new(text)! }
func gtkSeparator(_ orientation: GtkOrientation = GTK_ORIENTATION_HORIZONTAL) -> GWidget {
    gtk_separator_new(orientation)!
}

func packStart(_ box: GWidget?, _ child: GWidget?, expand: Bool = false, fill: Bool = false, padding: UInt32 = 0) {
    gtk_box_pack_start(asBox(box), child, expand ? 1 : 0, fill ? 1 : 0, padding)
}

func containerAdd(_ parent: GWidget?, _ child: GWidget?) {
    gtk_container_add(asContainer(parent), child)
}

// MARK: - Window icon

/// Sets the DexBar app icon on a GTK window from ~/.local/share/dexbar/icon.png.
func gtkSetAppIcon(_ window: GWidget?) {
    let iconPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/dexbar/icon.png").path
    gtk_window_set_icon_from_file(asWindow(window), iconPath, nil)
}

// MARK: - Signal connection

final class GtkCallback {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    func retained() -> gpointer { gpointer(Unmanaged.passRetained(self).toOpaque()) }
}

func gtkConnect(_ widget: GWidget?, signal: String, _ action: @escaping () -> Void) {
    let cb = GtkCallback(action)
    let rawWidget: gpointer? = widget.map { UnsafeMutableRawPointer($0) }
    g_signal_connect_data(
        rawWidget, signal,
        unsafeBitCast(gtkCallbackTrampoline, to: GCallback.self),
        cb.retained(), nil, GConnectFlags(rawValue: 0)
    )
}

func gtkConnect(_ widget: OpaquePointer?, signal: String, _ action: @escaping () -> Void) {
    let cb = GtkCallback(action)
    let rawWidget: gpointer? = widget.map { UnsafeMutableRawPointer($0) }
    g_signal_connect_data(
        rawWidget, signal,
        unsafeBitCast(gtkCallbackTrampoline, to: GCallback.self),
        cb.retained(), nil, GConnectFlags(rawValue: 0)
    )
}

// @convention(c) trampolines — single pointers, same size as GCallback
private let gtkCallbackTrampoline: @convention(c) (OpaquePointer?, gpointer?) -> Void = { _, userData in
    guard let ptr = userData else { return }
    Unmanaged<GtkCallback>.fromOpaque(ptr).takeUnretainedValue().action()
}

// MARK: - Draw signal (for GtkDrawingArea + Cairo)

final class GtkDrawCallback {
    let action: (OpaquePointer) -> Void
    init(_ action: @escaping (OpaquePointer) -> Void) { self.action = action }
    func retained() -> gpointer { gpointer(Unmanaged.passRetained(self).toOpaque()) }
}

/// Connects a "draw" signal on a GtkDrawingArea. The closure receives the `cairo_t*`.
func gtkConnectDraw(_ widget: GWidget?, _ action: @escaping (OpaquePointer) -> Void) {
    let cb = GtkDrawCallback(action)
    let rawWidget: gpointer? = widget.map { UnsafeMutableRawPointer($0) }
    g_signal_connect_data(
        rawWidget, "draw",
        unsafeBitCast(gtkDrawTrampoline, to: GCallback.self),
        cb.retained(), nil, GConnectFlags(rawValue: 0)
    )
}

private let gtkDrawTrampoline: @convention(c) (OpaquePointer?, OpaquePointer?, gpointer?) -> gboolean = { _, cr, userData in
    guard let ptr = userData, let cr = cr else { return 0 }
    Unmanaged<GtkDrawCallback>.fromOpaque(ptr).takeUnretainedValue().action(cr)
    return 1
}

// MARK: - Motion event (for hover tracking on GtkDrawingArea)

final class GtkMotionCallback {
    let action: (Double, Double) -> Void
    init(_ action: @escaping (Double, Double) -> Void) { self.action = action }
    func retained() -> gpointer { gpointer(Unmanaged.passRetained(self).toOpaque()) }
}

/// Connects a "motion-notify-event" signal. The closure receives (x, y) in widget coords.
func gtkConnectMotion(_ widget: GWidget?, _ action: @escaping (Double, Double) -> Void) {
    gtk_widget_add_events(widget, gint(GDK_POINTER_MOTION_MASK.rawValue))
    let cb = GtkMotionCallback(action)
    let rawWidget: gpointer? = widget.map { UnsafeMutableRawPointer($0) }
    g_signal_connect_data(
        rawWidget, "motion-notify-event",
        unsafeBitCast(gtkMotionTrampoline, to: GCallback.self),
        cb.retained(), nil, GConnectFlags(rawValue: 0)
    )
}

private let gtkMotionTrampoline: @convention(c) (OpaquePointer?, UnsafeMutablePointer<GdkEventMotion>?, gpointer?) -> gboolean = { _, event, userData in
    guard let ptr = userData, let event = event else { return 0 }
    Unmanaged<GtkMotionCallback>.fromOpaque(ptr).takeUnretainedValue().action(event.pointee.x, event.pointee.y)
    return 0
}

/// Connects a "leave-notify-event" signal (mouse leaves widget).
func gtkConnectLeave(_ widget: GWidget?, _ action: @escaping () -> Void) {
    gtk_widget_add_events(widget, gint(GDK_LEAVE_NOTIFY_MASK.rawValue))
    let cb = GtkCallback(action)
    let rawWidget: gpointer? = widget.map { UnsafeMutableRawPointer($0) }
    g_signal_connect_data(
        rawWidget, "leave-notify-event",
        unsafeBitCast(gtkLeaveTrampoline, to: GCallback.self),
        cb.retained(), nil, GConnectFlags(rawValue: 0)
    )
}

private let gtkLeaveTrampoline: @convention(c) (OpaquePointer?, OpaquePointer?, gpointer?) -> gboolean = { _, _, userData in
    guard let ptr = userData else { return 0 }
    Unmanaged<GtkCallback>.fromOpaque(ptr).takeUnretainedValue().action()
    return 0
}

// MARK: - CSS helpers

/// Applies a CSS stylesheet to the default screen (affects all widgets).
func gtkApplyCSS(_ css: String) {
    let provider = gtk_css_provider_new()
    gtk_css_provider_load_from_data(provider, css, gssize(css.utf8.count), nil)
    let screen = gdk_screen_get_default()
    gtk_style_context_add_provider_for_screen(
        screen, OpaquePointer(provider),
        UInt32(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
    )
}

/// Applies a CSS class name to a widget.
func gtkAddClass(_ widget: GWidget?, _ className: String) {
    let ctx = gtk_widget_get_style_context(widget)
    gtk_style_context_add_class(ctx, className)
}

/// Removes a CSS class name from a widget.
func gtkRemoveClass(_ widget: GWidget?, _ className: String) {
    let ctx = gtk_widget_get_style_context(widget)
    gtk_style_context_remove_class(ctx, className)
}

// MARK: - Hex color parsing

/// Parses "#RRGGBB" into (r, g, b) each in [0, 1].
func hexToRGB(_ hex: String) -> (r: Double, g: Double, b: Double) {
    var str = hex
    if str.hasPrefix("#") { str.removeFirst() }
    guard str.count == 6, let val = UInt64(str, radix: 16) else {
        return (0.5, 0.5, 0.5)
    }
    return (
        r: Double((val >> 16) & 0xFF) / 255.0,
        g: Double((val >> 8)  & 0xFF) / 255.0,
        b: Double( val        & 0xFF) / 255.0
    )
}

// Returns 1 (TRUE) to prevent window destruction on delete-event
func gtkConnectDeleteHide(_ widget: GWidget?, _ action: @escaping () -> Void) {
    let cb = GtkCallback(action)
    let rawWidget: gpointer? = widget.map { UnsafeMutableRawPointer($0) }
    g_signal_connect_data(
        rawWidget, "delete-event",
        unsafeBitCast(gtkDeleteEventTrampoline, to: GCallback.self),
        cb.retained(), nil, GConnectFlags(rawValue: 0)
    )
}

private let gtkDeleteEventTrampoline: @convention(c) (OpaquePointer?, OpaquePointer?, gpointer?) -> gboolean = { _, _, userData in
    guard let ptr = userData else { return 0 }
    Unmanaged<GtkCallback>.fromOpaque(ptr).takeUnretainedValue().action()
    return 1
}
#endif
