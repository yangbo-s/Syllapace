import AppKit
import Observation
import SwiftUI

@Observable final class AppAppearance {
    static let shared = AppAppearance()
    var mode: String { didSet { persist(); apply() } }
    var accentHex: String { didSet { persist() } }
    var scale: Double { didSet { persist() } }
    private let isolated: Bool

    private init() {
        let environment = ProcessInfo.processInfo.environment
        isolated = environment["APP_DEMO"] == "1" || environment["APP_SNAPSHOT"] != nil || environment["APP_SELFTEST"] == "1"
        let defaults = UserDefaults.standard
        mode = isolated ? "system" : defaults.string(forKey: "appearanceMode") ?? "system"
        accentHex = isolated ? "" : defaults.string(forKey: "appearanceAccent") ?? ""
        let saved = isolated ? 1 : defaults.double(forKey: "interfaceScale")
        scale = [0.9, 1, 1.15].contains(saved) ? saved : 1
    }

    func apply() {
        NSApp.appearance = mode == "light" ? NSAppearance(named: .aqua) : mode == "dark" ? NSAppearance(named: .darkAqua) : nil
    }
    private func persist() {
        guard !isolated else { return }
        UserDefaults.standard.set(mode, forKey: "appearanceMode")
        UserDefaults.standard.set(accentHex, forKey: "appearanceAccent")
        UserDefaults.standard.set(scale, forKey: "interfaceScale")
    }
    private func selectedAccent(dark: Bool) -> NSColor {
        if accentHex.count == 6, let rgb = UInt32(accentHex, radix: 16) {
            return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1)
        }
        return dark ? NSColor(srgbRed: 0.46, green: 0.79, blue: 0.73, alpha: 1) : NSColor(srgbRed: 0.15, green: 0.47, blue: 0.43, alpha: 1)
    }
    /// Keep a custom hue usable for small native text on raised settings surfaces.
    /// The picker preserves the selected swatch; both renderers use these variants.
    func accent(dark: Bool) -> NSColor {
        var color = selectedAccent(dark: dark)
        guard !accentHex.isEmpty else { return color }
        let background = dark ? NSColor(srgbRed: 0.25, green: 0.25, blue: 0.25, alpha: 1) : .white
        for _ in 0..<32 {
            let a = Self.luminance(color), b = Self.luminance(background)
            // Aqua blends native control tints with their light surfaces. Leave
            // enough headroom for that composition as well as plain web text.
            if (max(a, b) + 0.05) / (min(a, b) + 0.05) >= (dark ? 4.6 : 7.5) { break }
            color = color.blended(withFraction: 0.1, of: dark ? .white : .black) ?? color
        }
        return color
    }
    func course(_ index: Int, dark: Bool) -> NSColor {
        let values = dark ? ["", "81A8E1", "DBAC70", "BA92D6", "DA91AA", "A1C391"] : ["", "4774B8", "A96824", "825BA6", "AA5A74", "557E48"]
        let value = values[((index % 6) + 6) % 6]
        guard let rgb = UInt32(value, radix: 16) else { return accent(dark: dark) }
        return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1)
    }
    var pickerColor: Color {
        get { Color(nsColor: selectedAccent(dark: false)) }
        set {
            guard let color = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            accentHex = String(format: "%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
        }
    }
    func webTokens(dark: Bool) -> [String: String] {
        var tokens: [String: String] = [:]
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            let canvas = NSColor.windowBackgroundColor
            let foreground = NSColor.labelColor
            let raised = canvas.blended(withFraction: 0.055, of: foreground) ?? canvas
            for (key, color) in ["background": canvas, "foreground": foreground,
                                 "muted": raised, "muted-foreground": foreground.withAlphaComponent(dark ? 0.72 : 0.64),
                                 "card": canvas, "card-foreground": foreground,
                                 "popover": raised, "popover-foreground": foreground,
                                 "secondary": raised, "secondary-foreground": foreground,
                                 "accent": raised, "accent-foreground": foreground,
                                 "border": NSColor.separatorColor, "input": NSColor.separatorColor,
                                 "primary": accent(dark: dark), "ring": accent(dark: dark),
                                 "primary-foreground": Self.ink(on: accent(dark: dark))] {
                tokens[key] = Self.css(color)
            }
            for index in 0..<6 { tokens["course-\(index)"] = Self.css(course(index, dark: dark)) }
        }
        return tokens
    }
    private static func luminance(_ color: NSColor) -> Double {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }
    static func ink(on color: NSColor) -> NSColor {
        luminance(color) > 0.179 ? NSColor(srgbRed: 0.04, green: 0.04, blue: 0.04, alpha: 1) : .white
    }
    private static func css(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "transparent" }
        return String(format: "rgba(%.0f, %.0f, %.0f, %.3f)", rgb.redComponent * 255, rgb.greenComponent * 255, rgb.blueComponent * 255, rgb.alphaComponent)
    }
}

/// One layout scale applies to native content and the embedded workspace together.
struct InterfaceScale: ViewModifier {
    let scale: Double
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content.frame(width: geometry.size.width / scale, height: geometry.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
        }
    }
}
