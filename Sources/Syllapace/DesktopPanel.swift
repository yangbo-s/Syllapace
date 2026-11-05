import SwiftUI
import SyllapaceKit

enum DesktopCardMode: String, CaseIterable {
    case compact, expanded
    var height: CGFloat { self == .compact ? 304 : 552 }
}

@Observable
final class DesktopCardPreferences {
    var mode: DesktopCardMode { didSet { changed("mode", mode.rawValue) } }
    var pinned: Bool { didSet { changed("pinned", pinned) } }
    var locked: Bool { didSet { changed("locked", locked) } }
    var snapsToEdges: Bool { didSet { changed("snapsToEdges", snapsToEdges) } }
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults?
    private static let prefix = "SyllapaceDesktop."

    init(persists: Bool) {
        let storage = persists ? UserDefaults.standard : nil
        defaults = storage
        mode = DesktopCardMode(rawValue: storage?.string(forKey: Self.prefix + "mode") ?? "") ?? .compact
        pinned = storage?.bool(forKey: Self.prefix + "pinned") ?? false
        locked = storage?.bool(forKey: Self.prefix + "locked") ?? false
        snapsToEdges = storage?.object(forKey: Self.prefix + "snapsToEdges") as? Bool ?? true
    }

    var savedFrame: NSRect? {
        guard let value = defaults?.string(forKey: Self.prefix + "frame") else { return nil }
        let rect = NSRectFromString(value)
        guard rect.width > 0, rect.height > 0, rect.origin.x.isFinite, rect.origin.y.isFinite else { return nil }
        return rect
    }

    func save(frame: NSRect) { defaults?.set(NSStringFromRect(frame), forKey: Self.prefix + "frame") }
    private func changed(_ key: String, _ value: Any) {
        defaults?.set(value, forKey: Self.prefix + key)
        onChange?()
    }
}

final class DesktopPanel: NSPanel, NSWindowDelegate {
    private let preferences: DesktopCardPreferences
    private var settlingTask: Task<Void, Never>?
    private var applyingFrame = false

    init(model: AppModel) {
        let preferences = DesktopCardPreferences(persists: !model.isDemo)
        self.preferences = preferences
        super.init(contentRect: NSRect(x: 80, y: 80, width: 360, height: preferences.mode.height),
                   styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable],
                   backing: .buffered, defer: false)
        title = "Syllapace"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        let host = NSHostingView(rootView: DesktopCard(model: model, setPinned: { [weak self] pinned in
            self?.level = pinned ? .floating : NSWindow.Level(rawValue: -1)
        }, preferences: preferences))
        host.sizingOptions = []
        contentView = host
        delegate = self
        preferences.onChange = { [weak self] in self?.applyPreferences() }
        if let restored = preferences.savedFrame {
            setFrameOrigin(NSPoint(x: restored.minX, y: restored.maxY - frame.height))
        } else if let screen = NSScreen.main {
            setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 380, y: screen.visibleFrame.maxY - frame.height - 20))
        }
        applyPreferences()
    }

    override var canBecomeKey: Bool { true }
    func toggle() { if isVisible { orderOut(nil) } else { orderFrontRegardless() } }
    func setMode(_ mode: DesktopCardMode) { preferences.mode = mode }

    private func applyPreferences() {
        level = preferences.pinned ? .floating : NSWindow.Level(rawValue: -1)
        isMovable = !preferences.locked
        isMovableByWindowBackground = !preferences.locked
        let target = NSRect(x: frame.minX, y: frame.maxY - preferences.mode.height,
                            width: 360, height: preferences.mode.height)
        applyingFrame = true
        setFrame(target, display: true)
        applyingFrame = false
        settlePosition()
    }

    func windowDidMove(_ notification: Notification) {
        guard !applyingFrame else { return }
        settlingTask?.cancel()
        settlingTask = Task { [weak self] in
            // Do not fight AppKit's live window drag; snap only after the pointer is released.
            do {
                try await Task.sleep(for: .milliseconds(160))
                while NSEvent.pressedMouseButtons != 0 { try await Task.sleep(for: .milliseconds(100)) }
            } catch { return }
            guard !Task.isCancelled else { return }
            self?.settlePosition()
        }
    }

    private func settlePosition() {
        guard let screen = screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        var target = frame
        target.origin.x = min(max(target.minX, visible.minX), max(visible.minX, visible.maxX - target.width))
        target.origin.y = min(max(target.minY, visible.minY), max(visible.minY, visible.maxY - target.height))
        if preferences.snapsToEdges {
            if abs(target.minX - visible.minX) <= 16 { target.origin.x = visible.minX }
            else if abs(target.maxX - visible.maxX) <= 16 { target.origin.x = visible.maxX - target.width }
            if abs(target.minY - visible.minY) <= 16 { target.origin.y = visible.minY }
            else if abs(target.maxY - visible.maxY) <= 16 { target.origin.y = visible.maxY - target.height }
        }
        if target != frame {
            applyingFrame = true
            setFrame(target, display: true)
            applyingFrame = false
        }
        preferences.save(frame: target)
    }
}
