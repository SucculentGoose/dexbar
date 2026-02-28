import SwiftUI
import AppKit

extension Color {
    /// Creates a Color from a 6-digit hex string (with or without leading `#`).
    init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6 else { return nil }
        var value: UInt64 = 0
        Scanner(string: str).scanHexInt64(&value)
        self.init(
            .sRGB,
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }

    /// Serialises to a `#RRGGBB` hex string suitable for UserDefaults storage.
    func toHex() -> String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((c.redComponent   * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent  * 255).rounded())
        )
    }
}
