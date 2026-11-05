import SwiftUI
import SyllapaceKit
final class DesktopPanel: NSPanel {
    init(model: AppModel) {
        super.init(contentRect: NSRect(x: 80, y: 80, width: 360, height: 420), styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable], backing: .buffered, defer: false)
        title = "Syllapace"; titleVisibility = .hidden; titlebarAppearsTransparent = true
        isMovableByWindowBackground = true; isReleasedWhenClosed = false; hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]; level = NSWindow.Level(rawValue: -1)
        let host = NSHostingView(rootView: DesktopCard(model: model, setPinned: { [weak self] pinned in self?.level = pinned ? .floating : NSWindow.Level(rawValue: -1) }))
        host.sizingOptions = []; contentView = host
        setFrameAutosaveName("SyllapaceDesktop")
        if let screen = NSScreen.main { setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 392, y: screen.visibleFrame.maxY - 460)) }
    }
    override var canBecomeKey: Bool { true }
    func toggle() { if isVisible { orderOut(nil) } else { orderFrontRegardless() } }
}
struct DesktopCard: View {
    @Bindable var model: AppModel
    var setPinned: (Bool) -> Void
    @State private var pinned = false
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    @Environment(\.openWindow) private var openWindow
    var upcoming: [AcademicEvent] { model.scopedEvents.filter { $0.state == .approved && !$0.completed && ($0.presentationDate ?? .distantPast) >= Calendar.current.startOfDay(for: .now) }.sorted { $0.presentationDate! < $1.presentationDate! } }
    var body: some View {
        // Reading the preference invalidates this independent NSHostingView too.
        let _ = languagePreference
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(L10n.string("Today")).font(.system(size: 23, weight: .medium, design: .rounded)); Spacer(); Button { pinned.toggle(); setPinned(pinned) } label: { Image(systemName: pinned ? "pin.fill" : "pin") }.buttonStyle(.plain).help(pinned ? L10n.string("Keep on desktop") : L10n.string("Keep above windows")) }.gridProbe("desktop-title", area: "desktop")
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(L10n.locale))).font(.caption).foregroundStyle(.secondary).gridProbe("desktop-date", area: "desktop")
            if upcoming.isEmpty { Spacer(); Text(L10n.string("A clear day ahead.")).foregroundStyle(.secondary); Spacer() }
            else { ForEach(upcoming.prefix(3)) { event in
                Button {
                    model.page = .timeline; model.selectedID = event.id
                    model.revealMain()
                } label: {
                    HStack(alignment: .top, spacing: 12) { Circle().fill(Palette.course(model.course(event.courseID).color)).frame(width: 8, height: 8).padding(.top, 4); VStack(alignment: .leading, spacing: 8) { Text(event.title).fontWeight(.medium).lineLimit(2); Text("\(model.course(event.courseID).localizedCode) · \(L10n.date(event.presentationDate!, dateOnly: event.dateOnly))").font(.caption).foregroundStyle(.secondary) }; Spacer() }.contentShape(Rectangle())
                }.buttonStyle(.plain).gridProbe("desktop-event-\(event.id)", area: "desktop")
            }; Spacer(minLength: 0) }
            HStack { Text(model.isDemo ? L10n.string("Demo workspace") : "Syllapace").font(.caption).foregroundStyle(.secondary); Spacer(); Button(L10n.string("Open timeline")) { model.page = .timeline; model.revealMain() }.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.accent) }.gridProbe("desktop-footer", area: "desktop", edge: "footer") // Flexible Spacer above the footer intentionally absorbs remaining height.
        }.padding(24).padding(.top, 12).frame(width: 360, height: 420).gridArea("desktop", inset: 24).background(Palette.canvas).tint(Palette.accent).environment(\.locale, L10n.locale)
    }
}
