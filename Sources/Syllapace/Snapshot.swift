import AppKit
import SwiftUI
import IOKit.pwr_mgt

enum Snapshot {
    static var started = false
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        guard !started, let dir = ProcessInfo.processInfo.environment["APP_SNAPSHOT"], ProcessInfo.processInfo.environment["APP_STORE"] != nil else { return }
        started = true
        Task {
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Syllapace preview" as CFString, kIOPMUserActiveLocal, &activity)
            defer { IOPMAssertionRelease(activity) }
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1))
            guard let main = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) else { return }
            let originalFrame = main.frame
            defer { main.setFrame(originalFrame, display: false) }
            for dark in [false, true] {
                let mode = dark ? "dark" : "light"
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                for page in AppPage.allCases {
                    model.page = page
                    try? await Task.sleep(for: .milliseconds(200))
                    if page == .review { model.selectedID = model.events.first?.id }
                    NSApp.activate(); main.makeKeyAndOrderFront(nil)
                    try? await Task.sleep(for: .milliseconds(600))
                    capture(main, path: "\(dir)/\(page.rawValue.lowercased())-\(mode).png")
                }
                model.editor = model.archive.events.first
                try? await Task.sleep(for: .milliseconds(700))
                if let sheet = main.attachedSheet { capture(sheet, path: "\(dir)/editor-\(mode).png") }
                model.editor = nil
                try? await Task.sleep(for: .milliseconds(500))
                model.showImport = true
                try? await Task.sleep(for: .milliseconds(700))
                if let sheet = main.attachedSheet { capture(sheet, path: "\(dir)/import-\(mode).png") }
                model.showImport = false
                try? await Task.sleep(for: .milliseconds(500))
                model.showDesktop()
                try? await Task.sleep(for: .milliseconds(300))
                if let panel = model.panel { panel.level = .floating; panel.makeKeyAndOrderFront(nil); capture(panel, path: "\(dir)/desktop-\(mode).png"); panel.orderOut(nil) }
                main.makeKeyAndOrderFront(nil)
                openSettings()
                try? await Task.sleep(for: .milliseconds(1600))
                if let settings = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0 !== main && !($0 is NSPanel) }) {
                    for tab in [3, 0, 1, 2] {
                        model.settingsTab = tab
                        settings.makeKeyAndOrderFront(nil)
                        try? await Task.sleep(for: .milliseconds(500))
                        capture(settings, path: "\(dir)/settings-\(tab)-\(mode).png")
                    }
                    settings.orderOut(nil)
                }

            }
            model.page = .timeline; model.search = "no-match-fixture"
            main.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(300))
            capture(main, path: "\(dir)/search-empty-dark.png")
            model.search = ""
            main.setContentSize(NSSize(width: 940, height: 620))
            model.page = .review
            try? await Task.sleep(for: .milliseconds(200))
            model.selectedID = model.events.first?.id
            try? await Task.sleep(for: .milliseconds(300))
            capture(main, path: "\(dir)/review-narrow-dark.png")
            model.selectedID = nil
            model.archive.events = []; model.archive.sources = []; model.page = .today
            main.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(300))
            capture(main, path: "\(dir)/empty-dark.png")
            FileHandle.standardError.write(Data("SNAPSHOT done \(dir)\n".utf8))
            main.setFrame(originalFrame, display: true)
            NSApp.terminate(nil)
        }
    }
    static func capture(_ window: NSWindow, path: String) {
        NSApp.unhideWithoutActivation(); window.makeKeyAndOrderFront(nil)
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: window)
        if ProcessInfo.processInfo.environment["APP_LAYOUT_ONLY"] == "1" { return }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); process.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        do { try process.run(); process.waitUntilExit() } catch { log("Capture failed: \(error)") }
        if FileManager.default.fileExists(atPath: path) { log("SNAPSHOT \(path)"); return }
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)); log("SNAPSHOT \(path) (view-render fallback)") }
    }
    static func log(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
}
