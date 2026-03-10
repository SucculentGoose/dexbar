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
