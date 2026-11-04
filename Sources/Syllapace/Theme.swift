import SwiftUI

enum Palette {
    static let accent = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.46, green: 0.79, blue: 0.73, alpha: 1) : NSColor(red: 0.15, green: 0.47, blue: 0.43, alpha: 1) })
    static let warning = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemOrange : NSColor(red: 0.59, green: 0.30, blue: 0.03, alpha: 1) })
    static let onAccent = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.05, green: 0.17, blue: 0.15, alpha: 1) : .white })
    // Native prominent buttons enforce white labels; use a deeper shade in both appearances.
    static let actionAccent = Color(red: 0.15, green: 0.47, blue: 0.43)
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let colors: [Color] = [accent, .blue, .orange, .purple]
    static func course(_ index: Int) -> Color { colors[abs(index) % colors.count] }
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
