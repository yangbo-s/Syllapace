import SwiftUI

/// Diagnostic backgrounds do not participate in layout, hit testing, or accessibility.
/// Frames are sampled from the actual captured window, rather than SwiftUI's global
/// coordinate space (which is independent for every sheet and hosting window).
extension View {
    func gridArea(_ name: String, inset: CGFloat = 20) -> some View {
        modifier(GridProbeModifier(kind: "area", name: name, area: name, edge: nil, inset: inset))
    }
    func gridProbe(_ name: String, area: String, edge: String? = "lead") -> some View {
        modifier(GridProbeModifier(kind: "probe", name: name, area: area, edge: edge, inset: 0))
    }
}

private struct GridProbeModifier: ViewModifier {
    let kind: String
    let name: String
    let area: String
    let edge: String?
    let inset: CGFloat
    func body(content: Content) -> some View {
        if GridProbes.enabled {
            content.background(GridAnchor(metadata: .init(kind: kind, name: name, area: area, edge: edge, inset: inset)))
        } else { content }
    }
}

final class GridProbes {
    static let shared = GridProbes()
    static let enabled = ProcessInfo.processInfo.environment["APP_SNAPSHOT"] != nil || ProcessInfo.processInfo.environment["APP_GRID"] == "1"
    struct Metadata {
        var kind: String
        var name: String
        var area: String
        var edge: String?
        var inset: Double
    }
    struct Probe: Codable {
        var kind: String
        var name: String
        var area: String
        var edge: String?
        var inset: Double
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var partiallyClipped: Bool
    }
    private final class WeakView {
        weak var view: GridProbeView?
        init(_ view: GridProbeView) { self.view = view }
    }
    private var views: [ObjectIdentifier: WeakView] = [:]
    fileprivate func register(_ view: GridProbeView) { views[ObjectIdentifier(view)] = WeakView(view) }

    func write(to path: String, window: NSWindow) {
        guard let root = window.contentView else { return }
        root.layoutSubtreeIfNeeded()
        views = views.filter { $0.value.view != nil }
        var probes: [Probe] = []
        for entry in views.values {
            guard let view = entry.view, view.window === window, !view.isHiddenOrHasHiddenAncestor,
                  view.bounds.width > 0, view.bounds.height > 0 else { continue }
            let rect = view.convert(view.bounds, to: root)
            let visible = view.convert(view.visibleRect, to: root).intersection(root.bounds)
            guard !visible.isNull, visible.width > 0, visible.height > 0 else { continue }
            let m = view.metadata
            probes.append(.init(kind: m.kind, name: m.name, area: m.area, edge: m.edge, inset: m.inset,
                                x: rect.minX - root.bounds.minX,
                                y: root.isFlipped ? rect.minY - root.bounds.minY : root.bounds.maxY - rect.maxY,
                                width: rect.width, height: rect.height,
                                partiallyClipped: !visible.contains(rect)))
        }
        // An off-screen enclosing content area may have no own visible background;
        // retain it only when a visible child probe needs its real frame.
        let needed = Set(probes.filter { $0.kind == "probe" }.map(\.area))
        let present = Set(probes.filter { $0.kind == "area" }.map(\.area))
        for entry in views.values {
            guard let view = entry.view, view.window === window, !view.isHiddenOrHasHiddenAncestor,
                  view.metadata.kind == "area", needed.contains(view.metadata.area), !present.contains(view.metadata.area) else { continue }
            let r = view.convert(view.bounds, to: root), m = view.metadata
            probes.append(.init(kind: m.kind, name: m.name, area: m.area, edge: m.edge, inset: m.inset,
                                x: r.minX - root.bounds.minX, y: root.isFlipped ? r.minY - root.bounds.minY : root.bounds.maxY - r.maxY,
                                width: r.width, height: r.height, partiallyClipped: true))
        }
        struct Layout: Encodable {
            var window: [String: Double]
            var probes: [Probe]
        }
        let file = Layout(window: ["number": Double(window.windowNumber), "width": root.bounds.width, "height": root.bounds.height],
                          probes: probes.sorted { ($0.area, $0.y, $0.x) < ($1.area, $1.y, $1.x) })
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: URL(fileURLWithPath: path), options: .atomic)
            Snapshot.log("LAYOUT \(path): \(probes.filter { $0.kind == "probe" }.count) visible probes")
        } catch { Snapshot.log("LAYOUT failed: \(error.localizedDescription)") }
    }
}

private struct GridAnchor: NSViewRepresentable {
    let metadata: GridProbes.Metadata
    func makeNSView(context: Context) -> GridProbeView {
        let view = GridProbeView(metadata: metadata)
        GridProbes.shared.register(view)
        return view
    }
    func updateNSView(_ nsView: GridProbeView, context: Context) { nsView.metadata = metadata }
}
private final class GridProbeView: NSView {
    var metadata: GridProbes.Metadata
    init(metadata: GridProbes.Metadata) {
        self.metadata = metadata
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
