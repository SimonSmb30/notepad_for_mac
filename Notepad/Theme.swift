import AppKit
import SwiftUI

/// Wie das Fenster eingefärbt wird.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case light, dark, windows, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        case .windows: "Windows"
        case .custom: String(localized: "Custom Colors")
        }
    }
}

/// Die Farben der vier Fensterbereiche.
struct Palette {
    var bar: NSColor
    var menu: NSColor
    var background: NSColor
    var text: NSColor

    /// Der klassische Windows-Editor: weiß mit hellblauer Leiste.
    static let windows = Palette(
        bar: NSColor(hex: "CCDDEC")!,
        menu: NSColor(hex: "FFFFFF")!,
        background: NSColor(hex: "FFFFFF")!,
        text: NSColor(hex: "000000")!
    )
}

extension NSColor {
    convenience init?(hex: String) {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "000000" }
        let parts = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()) }
        return String(format: "%02X%02X%02X", parts[0], parts[1], parts[2])
    }

    /// Hell oder dunkel, je nachdem welche Schriftfarbe auf dieser Farbe lesbar ist.
    var matchingScheme: ColorScheme {
        luminance < 0.5 ? .dark : .light
    }

    /// Wahrgenommene Helligkeit von 0 (schwarz) bis 1 (weiß).
    var luminance: CGFloat {
        guard let rgb = usingColorSpace(.sRGB) else { return 0.5 }
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }
}

extension View {
    /// Setzt hell oder dunkel nur für diesen Bereich; `nil` lässt ihn unverändert.
    @ViewBuilder
    func localColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}
