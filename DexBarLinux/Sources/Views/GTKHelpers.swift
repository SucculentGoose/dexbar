#if canImport(CGtk4)
import CGtk4
import Foundation

// MARK: - Type casting helpers for GTK4's C GObject hierarchy

typealias GWidget    = UnsafeMutablePointer<GtkWidget>
typealias GWindow    = UnsafeMutablePointer<GtkWindow>
typealias GBox       = UnsafeMutablePointer<GtkBox>
typealias GGrid      = UnsafeMutablePointer<GtkGrid>
typealias GEntry     = UnsafeMutablePointer<GtkEntry>
typealias GButton    = UnsafeMutablePointer<GtkButton>
typealias GCombo     = UnsafeMutablePointer<GtkComboBox>
typealias GTBut      = UnsafeMutablePointer<GtkToggleButton>
typealias GCheckBut  = UnsafeMutablePointer<GtkCheckButton>

// Opaque types in GTK4 (no public struct definition)
typealias GLabel     = OpaquePointer
typealias GComboText = OpaquePointer
typealias GNotebook  = OpaquePointer
typealias GSpinBut   = OpaquePointer
typealias GEditable  = OpaquePointer

// Cast a GWidget to a more specific type via OpaquePointer bridge
func asWindow(_ w: GWidget?) -> GWindow?    { w.flatMap { GWindow(OpaquePointer($0)) } }
func asBox(_ w: GWidget?) -> GBox?          { w.flatMap { GBox(OpaquePointer($0)) } }
func asGrid(_ w: GWidget?) -> GGrid?        { w.flatMap { GGrid(OpaquePointer($0)) } }
func asLabel(_ w: GWidget?) -> GLabel?      { w.flatMap { OpaquePointer($0) } }
func asEntry(_ w: GWidget?) -> GEntry?      { w.flatMap { GEntry(OpaquePointer($0)) } }
func asComboText(_ w: GWidget?) -> GComboText? { w.flatMap { OpaquePointer($0) } }
func asCombo(_ w: GWidget?) -> GCombo?      { w.flatMap { GCombo(OpaquePointer($0)) } }
func asNotebook(_ w: GWidget?) -> GNotebook? { w.flatMap { OpaquePointer($0) } }
func asToggle(_ w: GWidget?) -> GTBut?      { w.flatMap { GTBut(OpaquePointer($0)) } }
func asCheck(_ w: GWidget?) -> GCheckBut?   { w.flatMap { GCheckBut(OpaquePointer($0)) } }
func asSpin(_ w: GWidget?) -> GSpinBut?     { w.flatMap { OpaquePointer($0) } }
func asEditable(_ w: GWidget?) -> GEditable? { w.flatMap { OpaquePointer($0) } }

// MARK: - Convenience wrappers

func gtkBox(orientation: GtkOrientation, spacing: Int32 = 0) -> GWidget {
    gtk_box_new(orientation, spacing)!
}
func gtkLabel(_ text: String) -> GWidget { gtk_label_new(text)! }
func gtkSeparator(_ orientation: GtkOrientation = GTK_ORIENTATION_HORIZONTAL) -> GWidget {
    gtk_separator_new(orientation)!
}

/// GTK4 replacement for gtk_box_pack_start. Appends child to box.
/// For expand/fill behavior, set hexpand/vexpand on the child before calling.
func gtkBoxAppend(_ box: GWidget?, _ child: GWidget?, expand: Bool = false, fill: Bool = false) {
    if expand {
        gtk_widget_set_hexpand(child, 1)
        gtk_widget_set_vexpand(child, 1)
    }
    if fill {
        gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        gtk_widget_set_valign(child, GTK_ALIGN_FILL)
    }
    gtk_box_append(asBox(box), child)
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

// MARK: - Draw function (for GtkDrawingArea + Cairo) — GTK4 uses set_draw_func instead of "draw" signal

final class GtkDrawCallback {
    let action: (OpaquePointer) -> Void
    init(_ action: @escaping (OpaquePointer) -> Void) { self.action = action }
    func retained() -> gpointer { gpointer(Unmanaged.passRetained(self).toOpaque()) }
}

/// Sets the draw function on a GtkDrawingArea. The closure receives the `cairo_t*`.
func gtkSetDrawFunc(_ widget: GWidget?, _ action: @escaping (OpaquePointer) -> Void) {
    let cb = GtkDrawCallback(action)
    let drawArea = widget.flatMap { UnsafeMutablePointer<GtkDrawingArea>(OpaquePointer($0)) }
    gtk_drawing_area_set_draw_func(drawArea, gtkDrawFuncTrampoline, cb.retained(), nil)
}

private let gtkDrawFuncTrampoline: GtkDrawingAreaDrawFunc = { _, cr, _, _, userData in
    guard let ptr = userData, let cr = cr else { return }
    Unmanaged<GtkDrawCallback>.fromOpaque(ptr).takeUnretainedValue().action(cr)
}

// MARK: - Motion event (for hover tracking on GtkDrawingArea) — GTK4 uses event controllers

final class GtkMotionCallback {
    let action: (Double, Double) -> Void
    init(_ action: @escaping (Double, Double) -> Void) { self.action = action }
    func retained() -> gpointer { gpointer(Unmanaged.passRetained(self).toOpaque()) }
}

/// Adds a GtkEventControllerMotion to the widget. The closure receives (x, y) in widget coords.
/// Returns the controller so you can also connect "leave" on it.
@discardableResult
func gtkConnectMotion(_ widget: GWidget?, _ action: @escaping (Double, Double) -> Void) -> OpaquePointer? {
    let controller = gtk_event_controller_motion_new()
    gtk_widget_add_controller(widget, controller)
    let cb = GtkMotionCallback(action)
    let raw: gpointer? = controller.map { UnsafeMutableRawPointer($0) }
    g_signal_connect_data(
        raw, "motion",
        unsafeBitCast(gtkMotionTrampoline, to: GCallback.self),
        cb.retained(), nil, GConnectFlags(rawValue: 0)
    )
    return controller
}

private let gtkMotionTrampoline: @convention(c) (OpaquePointer?, Double, Double, gpointer?) -> Void = { _, x, y, userData in
    guard let ptr = userData else { return }
    Unmanaged<GtkMotionCallback>.fromOpaque(ptr).takeUnretainedValue().action(x, y)
}

/// Connects a "leave" signal on an existing GtkEventControllerMotion.
func gtkConnectLeave(_ controller: OpaquePointer?, _ action: @escaping () -> Void) {
    let cb = GtkCallback(action)
    let raw: gpointer? = controller.map { UnsafeMutableRawPointer($0) }
    g_signal_connect_data(
        raw, "leave",
        unsafeBitCast(gtkLeaveTrampoline, to: GCallback.self),
        cb.retained(), nil, GConnectFlags(rawValue: 0)
    )
}

private let gtkLeaveTrampoline: @convention(c) (OpaquePointer?, gpointer?) -> Void = { _, userData in
    guard let ptr = userData else { return }
    Unmanaged<GtkCallback>.fromOpaque(ptr).takeUnretainedValue().action()
}

// MARK: - Window icon

/// Sets the DexBar icon on a GTK4 window by name (requires icon installed in hicolor theme).
/// Uses "dexbar-app" to avoid conflicting with the tray SNI "dexbar" Id.
func gtkSetAppIcon(_ window: GWidget?) {
    gtk_window_set_icon_name(asWindow(window), "dexbar-app")
}

// MARK: - CSS helpers

/// Applies a CSS stylesheet to the default display (affects all widgets).
func gtkApplyCSS(_ css: String) {
    let provider = gtk_css_provider_new()
    gtk_css_provider_load_from_string(provider, css)
    let display = gdk_display_get_default()
    gtk_style_context_add_provider_for_display(
        display, OpaquePointer(provider),
        UInt32(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
    )
}

/// Applies a CSS class name to a widget.
func gtkAddClass(_ widget: GWidget?, _ className: String) {
    gtk_widget_add_css_class(widget, className)
}

/// Removes a CSS class name from a widget.
func gtkRemoveClass(_ widget: GWidget?, _ className: String) {
    gtk_widget_remove_css_class(widget, className)
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

/// Connects "close-request" signal on a GTK4 window. Returns TRUE (1) to prevent destruction.
func gtkConnectDeleteHide(_ widget: GWidget?, _ action: @escaping () -> Void) {
    let cb = GtkCallback(action)
    let rawWidget: gpointer? = widget.map { UnsafeMutableRawPointer($0) }
    g_signal_connect_data(
        rawWidget, "close-request",
        unsafeBitCast(gtkCloseRequestTrampoline, to: GCallback.self),
        cb.retained(), nil, GConnectFlags(rawValue: 0)
    )
}

private let gtkCloseRequestTrampoline: @convention(c) (OpaquePointer?, gpointer?) -> gboolean = { _, userData in
    guard let ptr = userData else { return 0 }
    Unmanaged<GtkCallback>.fromOpaque(ptr).takeUnretainedValue().action()
    return 1
}
#endif
