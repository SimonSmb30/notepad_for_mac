import AppKit

/// Die Arten von Textstellen, die in der Vorschau eine eigene Farbe bekommen.
/// Unter diesen Namen kennt sie `Preview/preview.css` als Variablen.
enum SyntaxToken: CaseIterable {
    case comment, keyword, string, number, type, function, attribute
}

/// Farben für Code und Daten in der Vorschau, aus Hintergrund und Schriftfarbe
/// berechnet, damit sie in jeder Darstellung lesbar sind.
struct SyntaxPalette: Equatable {
    let text: NSColor
    private(set) var colors: [SyntaxToken: NSColor] = [:]

    /// Kontrast zum Hintergrund, den jede Farbe mindestens erreicht.
    private static let threshold = 3.0
    /// Töne für Darstellungen ohne eigenen Farbton, gleichmäßig über den Farbkreis verteilt.
    private static let neutralHues: [SyntaxToken: Double] = [
        .number: 30, .attribute: 90, .string: 150, .function: 210, .type: 270, .keyword: 330,
    ]
    /// Reihenfolge auf dem Farbkreis, wenn die Darstellung einen Farbton vorgibt:
    /// Schlüsselwörter landen nahe der Gegenfarbe.
    private static let anchoredOrder: [SyntaxToken] = [.attribute, .number, .string, .keyword, .type, .function]

    init(background: NSColor, text: NSColor) {
        self.text = text
        let back = RGB(background), fore = RGB(text)
        colors[.comment] = RGB(r: (fore.r + back.r) / 2, g: (fore.g + back.g) / 2, b: (fore.b + back.b) / 2).color

        // Bei zu schwachem Kontrast bliebe für Farben kein Spielraum.
        let base = fore.contrast(to: back)
        guard base >= Self.threshold else { return }

        let backLCH = back.lch, foreLCH = fore.lch
        var hues = Self.neutralHues
        if let anchor = [backLCH, foreLCH].first(where: { $0.c > 0.02 })?.h {
            for (index, token) in Self.anchoredOrder.enumerated() {
                hues[token] = (anchor + 40 + Double(index) * 56).truncatingRemainder(dividingBy: 360)
            }
        }

        // Heller oder dunkler als der Hintergrund, so wie die Schrift selbst.
        let direction: Double = foreLCH.l >= backLCH.l ? 1 : -1
        for (token, hue) in hues {
            var lightness = direction > 0 ? min(foreLCH.l, 0.80) : max(foreLCH.l, 0.50)
            var color = RGB(lightness: lightness, hue: hue)
            while color.contrast(to: back) < Self.threshold, lightness > 0, lightness < 1 {
                lightness += direction * 0.01
                color = RGB(lightness: lightness, hue: hue)
            }
            colors[token] = color.color
        }
    }

    func color(for token: SyntaxToken) -> NSColor {
        colors[token] ?? text
    }
}

/// Eine Farbe in sRGB mit Anteilen von 0 bis 1.
private struct RGB {
    var r, g, b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .gray
        self.init(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent)
    }

    /// Die kräftigste darstellbare Farbe mit dieser Helligkeit und diesem Ton in OKLCH.
    init(lightness: Double, hue: Double) {
        var chroma = 0.15
        while chroma > 0 {
            if let rgb = RGB(lch: (lightness, chroma, hue)) {
                self = rgb
                return
            }
            chroma -= 0.005
        }
        self = RGB(lch: (min(max(lightness, 0), 1), 0, 0)) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
    }

    /// `nil`, wenn die Farbe außerhalb von sRGB liegt.
    private init?(lch: (l: Double, c: Double, h: Double)) {
        let a = lch.c * cos(lch.h * .pi / 180), b = lch.c * sin(lch.h * .pi / 180)
        let l = pow(lch.l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lch.l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lch.l - 0.0894841775 * a - 1.2914855480 * b, 3)
        let linear = [
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
        ]
        guard linear.allSatisfy({ $0 >= -0.0005 && $0 <= 1.0005 }) else { return nil }
        let encoded = linear.map { Self.encode(min(max($0, 0), 1)) }
        self.init(r: encoded[0], g: encoded[1], b: encoded[2])
    }

    var color: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// Helligkeit, Sättigung und Farbton (in Grad) in OKLCH.
    var lch: (l: Double, c: Double, h: Double) {
        let r = Self.decode(r), g = Self.decode(g), b = Self.decode(b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let b2 = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let hue = atan2(b2, a) * 180 / .pi
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, hypot(a, b2), hue < 0 ? hue + 360 : hue)
    }

    /// Kontrastverhältnis nach WCAG, von 1 (gleich) bis 21 (schwarz auf weiß).
    func contrast(to other: RGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private var luminance: Double {
        0.2126 * Self.decode(r) + 0.7152 * Self.decode(g) + 0.0722 * Self.decode(b)
    }

    private static func decode(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func encode(_ value: Double) -> Double {
        value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}
