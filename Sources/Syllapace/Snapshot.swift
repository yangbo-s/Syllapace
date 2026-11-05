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
            try? await Task.sleep(for: .seconds(ProcessInfo.processInfo.environment["APP_SNAPSHOT_WAIT"] == "1" ? 20 : 1))
            guard let main = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) else { return }
            let originalFrame = main.frame
            defer { main.setFrame(originalFrame, display: false) }
            if ProcessInfo.processInfo.environment["APP_SNAPSHOT_EMPTY"] == "1" {
                await captureEmptyStates(model: model, window: main, directory: dir, openSettings: openSettings)
                log("SNAPSHOT done \(dir)")
                main.setFrame(originalFrame, display: true)
                NSApp.terminate(nil)
                return
            }
            var settingsWindow: NSWindow?
            for dark in [false, true] {
                let mode = dark ? "dark" : "light"
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                for page in AppPage.allCases {
                    model.page = page
                    try? await Task.sleep(for: .milliseconds(200))
                    if page == .review { model.selectedID = model.events.first?.id }
                    NSApp.activate(); main.makeKeyAndOrderFront(nil)
                    try? await Task.sleep(for: .milliseconds(600))
                    await captureActive(main, path: "\(dir)/\(page.rawValue.lowercased())-\(mode).png")
                }
                model.editor = model.archive.events.first
                try? await Task.sleep(for: .milliseconds(700))
                if let sheet = main.attachedSheet { await captureActive(sheet, path: "\(dir)/editor-\(mode).png") }
                model.editor = nil
                try? await Task.sleep(for: .milliseconds(400))
                model.editor = model.archive.events.first { $0.kind == .session }
                try? await Task.sleep(for: .milliseconds(600))
                if let sheet = main.attachedSheet { await captureActive(sheet, path: "\(dir)/session-editor-\(mode).png") }
                model.editor = nil
                try? await Task.sleep(for: .milliseconds(500))
                model.showImport = true
                try? await Task.sleep(for: .milliseconds(700))
                if let sheet = main.attachedSheet { await captureActive(sheet, path: "\(dir)/import-\(mode).png") }
                model.showImport = false
                try? await Task.sleep(for: .milliseconds(400))
                model.readingSource = model.archive.sources.first { $0.kind == .announcement }
                try? await Task.sleep(for: .milliseconds(600))
                if let sheet = main.attachedSheet { await captureActive(sheet, path: "\(dir)/source-reader-\(mode).png") }
                model.readingSource = nil
                try? await Task.sleep(for: .milliseconds(500))
                model.prepareCourseSelection(termID: model.archive.canvasSelection?.termID)
                try? await Task.sleep(for: .milliseconds(700))
                if let sheet = main.attachedSheet { await captureActive(sheet, path: "\(dir)/course-scope-\(mode).png") }
                model.showCourseSelection = false
                try? await Task.sleep(for: .milliseconds(400))
                main.setContentSize(NSSize(width: 940, height: 620))
                model.prepareCourseSelection(termID: model.archive.canvasSelection?.termID)
                try? await Task.sleep(for: .milliseconds(600))
                if let sheet = main.attachedSheet { await captureActive(sheet, path: "\(dir)/course-scope-narrow-\(mode).png") }
                model.showCourseSelection = false
                main.setFrame(originalFrame, display: true)
                try? await Task.sleep(for: .milliseconds(500))
                model.showDesktop()
                try? await Task.sleep(for: .milliseconds(300))
                if let panel = model.panel { panel.level = .floating; panel.makeKeyAndOrderFront(nil); await captureActive(panel, path: "\(dir)/desktop-\(mode).png"); panel.orderOut(nil) }
                main.makeKeyAndOrderFront(nil)
                if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil) }
                else { openSettings() }
                try? await Task.sleep(for: .milliseconds(1600))
                if let settings = settingsWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0 !== main && !($0 is NSPanel) }) {
                    settingsWindow = settings
                    for tab in [3, 0, 1, 2] {
                        model.settingsTab = tab
                        settings.makeKeyAndOrderFront(nil)
                        try? await Task.sleep(for: .milliseconds(500))
                        await captureActive(settings, path: "\(dir)/settings-\(tab)-\(mode).png")
                    }
                    settings.orderOut(nil)
                }

            }
            model.page = .timeline; model.search = "no-match-fixture"
            main.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(300))
            await captureActive(main, path: "\(dir)/search-empty-dark.png")
            model.search = ""
            main.setContentSize(NSSize(width: 940, height: 620))
            model.page = .review
            try? await Task.sleep(for: .milliseconds(200))
            model.selectedID = model.events.first?.id
            try? await Task.sleep(for: .milliseconds(300))
            await captureActive(main, path: "\(dir)/review-narrow-dark.png")
            model.selectedID = nil
            model.archive.events = []; model.archive.sources = []; model.page = .today
            main.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(300))
            await captureActive(main, path: "\(dir)/empty-dark.png")
            FileHandle.standardError.write(Data("SNAPSHOT done \(dir)\n".utf8))
            main.setFrame(originalFrame, display: true)
            NSApp.terminate(nil)
        }
    }
    private static func captureEmptyStates(model: AppModel, window: NSWindow, directory: String, openSettings: OpenSettingsAction) async {
        let events = model.archive.events
        model.selectedID = nil
        model.courseFilter = nil
        for size in [NSSize(width: 940, height: 620), NSSize(width: 1280, height: 800)] {
            let width = Int(size.width)
            window.setContentSize(size)
            for dark in [false, true] {
                let mode = dark ? "dark" : "light"
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                model.archive.events = []
                model.search = ""
                for page in [AppPage.today, .timeline, .review] {
                    model.page = page
                    await captureActive(window, path: "\(directory)/empty-\(page.rawValue.lowercased())-\(width)-\(mode).png")
                }
                model.archive.events = events
                model.page = .timeline
                model.search = "no-match-fixture"
                await captureActive(window, path: "\(directory)/empty-search-\(width)-\(mode).png")
                model.search = ""
            }
        }
        model.settingsTab = 0
        openSettings()
        try? await Task.sleep(for: .milliseconds(800))
        if let settings = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0 !== window && !($0 is NSPanel) }) {
            for dark in [false, true] {
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                await captureActive(settings, path: "\(directory)/settings-canvas-\(dark ? "dark" : "light").png")
            }
            settings.orderOut(nil)
        }
    }
    private static func captureActive(_ window: NSWindow, path: String) async {
        // An inactive window dims native controls and is not valid visual evidence.
        for _ in 0..<(ProcessInfo.processInfo.environment["APP_SNAPSHOT_WAIT"] == "1" ? 500 : 5) {
            NSApp.unhideWithoutActivation(); NSApp.activate(); window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(600))
            if NSApp.isActive && window.isKeyWindow {
                if ProcessInfo.processInfo.environment["APP_SNAPSHOT_EXTERNAL"] == "1" {
                    GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: window)
                    // A permitted external runner captures this window only. Keep
                    // its state stable until the PNG is written or capture fails.
                    for _ in 0..<100 {
                        if FileManager.default.fileExists(atPath: path) { log("SNAPSHOT \(path) (external window capture)"); return }
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    log("Capture failed: external window capture timed out for \(path)")
                    exit(1)
                }
                capture(window, path: path)
                return
            }
        }
        log("Capture failed: window did not become active for \(path); active=\(NSApp.isActive), key=\(window.isKeyWindow), visible=\(window.isVisible), canKey=\(window.canBecomeKey)")
        exit(1)
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
