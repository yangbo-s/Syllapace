import SwiftUI

enum Palette {
    static var accent: Color {
        let theme = AppAppearance.shared
        let light = theme.accent(dark: false), dark = theme.accent(dark: true)
        return Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static let warning = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemOrange : NSColor(red: 0.59, green: 0.30, blue: 0.03, alpha: 1) })
    static var onAccent: Color {
        let light = AppAppearance.ink(on: AppAppearance.shared.accent(dark: false))
        let dark = AppAppearance.ink(on: AppAppearance.shared.accent(dark: true))
        return Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    // Native prominent buttons enforce white labels; use a deeper shade in both appearances.
    static var actionAccent: Color {
        var color = AppAppearance.shared.accent(dark: false)
        while AppAppearance.ink(on: color) != .white {
            color = color.blended(withFraction: 0.1, of: .black) ?? .black
        }
        return Color(nsColor: color)
    }
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static func course(_ index: Int) -> Color {
        let light = AppAppearance.shared.course(index, dark: false), dark = AppAppearance.shared.course(index, dark: true)
        return Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
}
struct EmptyViewState: View {
    let title: String
    let symbol: String
    let detail: String
    var body: some View { ContentUnavailableView(title, systemImage: symbol, description: Text(detail)).frame(maxWidth: .infinity, maxHeight: .infinity) }
}

struct CalmFocus: NSViewRepresentable {
    var enabled = true
    func makeNSView(context: Context) -> NSView {
        InitialFocusView(enabled: enabled)
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

private final class InitialFocusView: NSView {
    private let enabled: Bool
    private var prepared = false
    init(enabled: Bool) { self.enabled = enabled; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard enabled, !prepared, let window else { return }
        prepared = true
        // A sheet installs its default field after the representable is created.
        window.initialFirstResponder = self
        Task { @MainActor [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }
}
