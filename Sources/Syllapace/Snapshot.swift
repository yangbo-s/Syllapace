import AppKit
import SwiftUI
import IOKit.pwr_mgt
import SyllapaceKit

enum Snapshot {
    static var started = false
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        guard !started, let dir = ProcessInfo.processInfo.environment["APP_SNAPSHOT"], ProcessInfo.processInfo.environment["APP_STORE"] != nil else { return }
        let modes = ["APP_SNAPSHOT_CONTROLS", "APP_SNAPSHOT_EMPTY", "APP_SNAPSHOT_WORKSPACE", "APP_SNAPSHOT_GANTT", "APP_SNAPSHOT_COPY", "APP_SNAPSHOT_CREDENTIALS", "APP_SNAPSHOT_APPEARANCE", "APP_SNAPSHOT_ACTIVITY"]
        guard modes.filter({ ProcessInfo.processInfo.environment[$0] == "1" }).count <= 1 else {
            log("Capture failed: choose only one snapshot mode"); exit(1)
        }
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
            if let input = ProcessInfo.processInfo.environment["APP_SNAPSHOT_INPUT"], input.hasPrefix("/tmp/") || input.hasPrefix("/private/tmp/") {
                do { model.archive = try ArchiveStore(url: URL(fileURLWithPath: input)).load() }
                catch { log("Capture failed: isolated course archive unavailable"); NSApp.terminate(nil); return }
                model.cancelCuration(); model.workspaceRevision += 1
                for dark in [false, true] {
                    let mode = dark ? "dark" : "light"
                    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    main.setContentSize(NSSize(width: 1320, height: 820))
                    model.courseFilter = nil
                    for view in WorkspaceViewMode.allCases {
                        model.page = AppPage(view: view)
                        await captureWorkspace(model: model, window: main, dark: dark, path: "\(dir)/courses-\(view.rawValue)-\(mode).png")
                    }
                    for course in model.scopedCourses {
                        model.courseFilter = course.id; model.page = AppPage(view: .gantt)
                        await captureWorkspace(model: model, window: main, dark: dark, path: "\(dir)/course-\(course.code)-\(mode).png")
                    }
                    model.courseFilter = nil; model.page = .review
                    try? await Task.sleep(for: .milliseconds(600))
                    await captureActive(main, path: "\(dir)/courses-review-\(mode).png")
                    model.editor = model.archive.events.first { $0.sourceID?.hasPrefix("official:") == true }
                    try? await Task.sleep(for: .milliseconds(600))
                    if let sheet = main.attachedSheet { await captureActive(sheet, path: "\(dir)/courses-editor-\(mode).png") }
                    model.editor = nil
                }
                log("SNAPSHOT done \(dir)"); NSApp.terminate(nil); return
            }
            if ProcessInfo.processInfo.environment["APP_SNAPSHOT_ACTIVITY"] == "1" {
                await captureActivity(model: model, window: main, directory: dir)
                log("SNAPSHOT done \(dir)"); NSApp.terminate(nil); return
            }
            if ProcessInfo.processInfo.environment["APP_SNAPSHOT_APPEARANCE"] == "1" {
                for dark in [false, true] {
                    AppAppearance.shared.mode = dark ? "dark" : "light"
                    AppAppearance.shared.accentHex = "346ABE"
                    for scale in [0.9, 1.0, 1.15] {
                        AppAppearance.shared.scale = scale
                        model.workspaceView = .calendar
                        main.setContentSize(NSSize(width: 1120 * scale, height: 760 * scale))
                        await captureWorkspace(model: model, window: main, dark: dark, path: "\(dir)/appearance-\(Int((scale * 100).rounded()))-\(dark ? "dark" : "light").png")
                    }
                    model.settingsTab = 5
                    openSettings()
                    try? await Task.sleep(for: .milliseconds(700))
                    if let settings = NSApp.windows.first(where: { $0 != main && $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }) {
                        await captureActive(settings, path: "\(dir)/appearance-settings-\(dark ? "dark" : "light").png")
                        settings.orderOut(nil)
                    }
                }
                log("SNAPSHOT done \(dir)"); NSApp.terminate(nil); return
            }
            if ProcessInfo.processInfo.environment["APP_SNAPSHOT_CREDENTIALS"] == "1" {
                await captureCredentialSettings(model: model, window: main, directory: dir, openSettings: openSettings)
                log("SNAPSHOT done \(dir)"); NSApp.terminate(nil); return
            }
            if ProcessInfo.processInfo.environment["APP_SNAPSHOT_COPY"] == "1" {
                await captureCopyStates(model: model, window: main, directory: dir, openSettings: openSettings)
                log("SNAPSHOT done \(dir)"); NSApp.terminate(nil); return
            }
            if ProcessInfo.processInfo.environment["APP_SNAPSHOT_WORKSPACE"] == "1" || ProcessInfo.processInfo.environment["APP_SNAPSHOT_GANTT"] == "1" {
                await captureWorkspaceStates(model: model, window: main, directory: dir)
                log("SNAPSHOT done \(dir)"); NSApp.terminate(nil); return
            }
            if ProcessInfo.processInfo.environment["APP_SNAPSHOT_CONTROLS"] == "1" {
                for dark in [false, true] {
                    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    for width in [940, 1120] {
                        main.setContentSize(NSSize(width: width, height: 760))
                        model.prepareCourseSelection(termID: model.archive.canvasSelection?.termID)
                        try? await Task.sleep(for: .milliseconds(700))
                        if let sheet = main.attachedSheet { await captureActive(sheet, path: "\(dir)/course-scope-\(width)-\(dark ? "dark" : "light").png") }
                        model.showCourseSelection = false
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
                log("SNAPSHOT done \(dir)"); NSApp.terminate(nil); return
            }
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
                    if page == .list {
                        model.selectedID = nil
                        for view in WorkspaceViewMode.allCases {
                            model.workspaceView = view
                            await captureWorkspace(model: model, window: main, dark: dark, path: "\(dir)/workspace-\(view.rawValue)-\(mode).png")
                        }
                        continue
                    }
                    if page.workspaceView != nil { continue }
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
                for fixture in 1...3 {
                    model.importFixtureMode = fixture; model.showImport = true
                    try? await Task.sleep(for: .milliseconds(600))
                    if let sheet = main.attachedSheet { await captureActive(sheet, path: "\(dir)/import-\(fixture)-\(mode).png") }
                    model.showImport = false
                    try? await Task.sleep(for: .milliseconds(400))
                }
                model.importFixtureMode = nil
                model.editingCourse = model.scopedCourses.first
                try? await Task.sleep(for: .milliseconds(600))
                if let sheet = main.attachedSheet { await captureActive(sheet, path: "\(dir)/course-display-\(mode).png") }
                model.editingCourse = nil
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
                if let panel = model.panel { panel.setMode(.compact); panel.level = .floating; panel.makeKeyAndOrderFront(nil); await captureActive(panel, path: "\(dir)/desktop-\(mode).png"); panel.setMode(.expanded); panel.level = .floating; await captureActive(panel, path: "\(dir)/desktop-expanded-\(mode).png"); panel.orderOut(nil) }
                main.makeKeyAndOrderFront(nil)
                if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil) }
                else { openSettings() }
                try? await Task.sleep(for: .milliseconds(1600))
                if let settings = settingsWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0 !== main && !($0 is NSPanel) }) {
                    settingsWindow = settings
                    for tab in [5, 3, 0, 1, 4, 2] {
                        model.settingsTab = tab
                        settings.makeKeyAndOrderFront(nil)
                        try? await Task.sleep(for: .milliseconds(500))
                        await captureActive(settings, path: "\(dir)/settings-\(tab)-\(mode).png")
                        if tab == 0 {
                            model.showSchoolSearch = true
                            try? await Task.sleep(for: .milliseconds(600))
                            if let sheet = settings.attachedSheet { await captureActive(sheet, path: "\(dir)/school-search-\(mode).png") }
                            model.showSchoolSearch = false
                            try? await Task.sleep(for: .milliseconds(400))
                        }
                    }
                    settings.orderOut(nil)
                }

            }
            model.page = .list; model.workspaceView = .list
            model.courseFilter = "personal"
            main.makeKeyAndOrderFront(nil)
            await captureWorkspace(model: model, window: main, dark: true, path: "\(dir)/course-empty-dark.png")
            model.courseFilter = nil
            main.setContentSize(NSSize(width: 940, height: 620))
            model.page = .review
            try? await Task.sleep(for: .milliseconds(200))
            model.selectedID = model.events.first?.id
            try? await Task.sleep(for: .milliseconds(300))
            await captureActive(main, path: "\(dir)/review-narrow-dark.png")
            model.selectedID = nil
            let originalArchive = model.archive
            model.archive.events = []; model.archive.sources = []; model.page = .list; model.workspaceView = .list
            main.makeKeyAndOrderFront(nil)
            await captureWorkspace(model: model, window: main, dark: true, path: "\(dir)/empty-dark.png")
            model.archive = originalArchive
            FileHandle.standardError.write(Data("SNAPSHOT done \(dir)\n".utf8))
            main.setFrame(originalFrame, display: true)
            NSApp.terminate(nil)
        }
    }

    /// Foreground feedback fixtures; no import or background operation is started.
    private static func captureActivity(model: AppModel, window: NSWindow, directory: String) async {
        model.workspaceView = .calendar
        window.setContentSize(NSSize(width: 940, height: 620))
        var before = model.archive
        before.events.removeFirst()
        model.lastImportUndo = ImportUndo(before: before, after: model.archive)
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            AppAppearance.shared.mode = mode
            model.notice = nil
            try? await Task.sleep(for: .milliseconds(200))
            model.notice = L10n.format("Imported %ld events. You can undo this import.", 12)
            await captureWorkspace(model: model, window: window, dark: dark, path: "\(directory)/activity-summary-\(mode).png")
            try? await Task.sleep(for: .seconds(6))
            await captureActive(window, path: "\(directory)/activity-compact-\(mode).png")
            await captureActivityDetails(model: model, window: window, path: "\(directory)/activity-details-\(mode).png")
            model.curationStatus = L10n.format("Organizing material %ld of %ld…", 3, 12)
            await captureActive(window, path: "\(directory)/activity-running-\(mode).png")
            await captureActivityDetails(model: model, window: window, path: "\(directory)/activity-running-details-\(mode).png")
            model.curationStatus = nil
        }
    }

    private static func captureActivityDetails(model: AppModel, window: NSWindow, path: String) async {
        let existing = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        model.showActivity = true
        try? await Task.sleep(for: .milliseconds(800))
        guard let popover = NSApp.windows.first(where: { $0.isVisible && !existing.contains($0.windowNumber) && $0.frame.width >= 392 }),
              NSApp.isActive else { log("Capture failed: activity popover unavailable"); exit(1) }
        // A native popover may leave its parent key. Capture that visible app-owned
        // window without forcing key status or dismissing its transient presentation.
        await captureExternal(popover, path: path)
        model.showActivity = false
        try? await Task.sleep(for: .milliseconds(300))
        window.makeKeyAndOrderFront(nil)
    }

    /// Settings fixtures only: never reads real credentials or calls Keychain.
    private static func captureCredentialSettings(model: AppModel, window: NSWindow, directory: String, openSettings: OpenSettingsAction) async {
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               document.bounds.height > scroll.contentView.bounds.height { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        func scroll(_ settings: NSWindow, bottom: Bool) {
            guard let content = settings.contentView, let view = scrollView(in: content), let document = view.documentView else { return }
            let end = max(0, document.bounds.height - view.contentView.bounds.height)
            view.contentView.scroll(to: NSPoint(x: 0, y: bottom == document.isFlipped ? end : 0))
            view.reflectScrolledClipView(view.contentView)
        }
        model.settingsTab = 3; openSettings()
        try? await Task.sleep(for: .milliseconds(1600))
        guard let settings = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0 !== window && !($0 is NSPanel) }) else {
            log("Capture failed: credential settings unavailable"); exit(1)
        }
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for state in ["local", "keychain", "error", "updates", "canvas", "models"] {
                model.settingsTab = state == "canvas" ? 0 : (state == "models" ? 1 : 3)
                model.credentialStorage = state == "keychain" ? .keychain : .local
                model.credentialStorageError = state == "error" ? L10n.string("Keychain access was cancelled. Your storage selection was not changed.") : nil
                model.credentialStorageStatus = nil
                settings.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(500))
                scroll(settings, bottom: ["updates", "canvas", "models"].contains(state))
                try? await Task.sleep(for: .milliseconds(250))
                await captureActive(settings, path: "\(directory)/credentials-\(state)-\(mode).png")
            }
        }
        settings.orderOut(nil)
    }

    /// Six captures per language for model privacy copy and both desktop sizes.
    private static func captureCopyStates(model: AppModel, window: NSWindow, directory: String, openSettings: OpenSettingsAction) async {
        let originalTab = model.settingsTab
        defer { model.settingsTab = originalTab }
        func overflowingScrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               document.bounds.height > scroll.contentView.bounds.height { return scroll }
            return view.subviews.lazy.compactMap { overflowingScrollView(in: $0) }.first
        }
        var settingsWindow: NSWindow?
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            model.settingsTab = 1
            if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil) } else { openSettings() }
            try? await Task.sleep(for: .milliseconds(1600))
            guard let settings = settingsWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0 !== window && !($0 is NSPanel) }) else {
                log("Capture failed: Models settings window was not available"); exit(1)
            }
            settingsWindow = settings
            // The copy being checked is the footer. Use public AppKit scrolling
            // so it is visible even when the settings form exceeds the viewport.
            if let content = settings.contentView, let scroll = overflowingScrollView(in: content), let document = scroll.documentView {
                let bottom = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
                scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
                scroll.reflectScrolledClipView(scroll.contentView)
                try? await Task.sleep(for: .milliseconds(250))
            }
            await captureActive(settings, path: "\(directory)/settings-1-\(mode).png")
            settings.orderOut(nil)
            window.makeKeyAndOrderFront(nil)
            model.showDesktop()
            try? await Task.sleep(for: .milliseconds(300))
            guard let panel = model.panel else { log("Capture failed: desktop panel was not available"); exit(1) }
            panel.setMode(.compact); panel.level = .floating; panel.makeKeyAndOrderFront(nil)
            await captureActive(panel, path: "\(directory)/desktop-\(mode).png")
            panel.setMode(.expanded); panel.level = .floating
            await captureActive(panel, path: "\(directory)/desktop-expanded-\(mode).png")
            panel.orderOut(nil)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// 24 captures: three views × three sizes × two appearances, then three states × two appearances.
    private static func captureWorkspaceStates(model: AppModel, window: NSWindow, directory: String) async {
        let originalArchive = model.archive
        let originalPage = model.page
        let originalView = model.workspaceView
        let originalCourse = model.courseFilter
        let originalCalendar = model.academicCalendarFilter
        let originalSelection = model.selectedID
        let originalFrame = window.frame
        defer {
            model.archive = originalArchive; model.page = originalPage; model.workspaceView = originalView
            model.courseFilter = originalCourse; model.academicCalendarFilter = originalCalendar
            model.selectedID = originalSelection; window.setFrame(originalFrame, display: true)
        }
        model.page = .list; model.selectedID = nil
        model.courseFilter = nil; model.academicCalendarFilter = nil
        // Synthetic density fixture: pagination must be visible with more than one page.
        if let owner = model.scopedCourses.first {
            for index in 1...24 {
                model.archive.events.append(AcademicEvent(id: "pagination-fixture-\(index)", courseID: owner.id,
                    title: "Problem set \(index) · Practice exercises", kind: .assignment,
                    date: Calendar.current.date(byAdding: .day, value: index, to: .now), dateOnly: true,
                    state: .approved, evidence: "Synthetic layout fixture"))
            }
        }
        let densityArchive = model.archive
        for dark in [false, true] {
            model.archive = densityArchive
            let mode = dark ? "dark" : "light"
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for size in [NSSize(width: 1320, height: 760), NSSize(width: 1120, height: 760), NSSize(width: 940, height: 620)] {
                window.setContentSize(size)
                for view in WorkspaceViewMode.allCases {
                    if ProcessInfo.processInfo.environment["APP_SNAPSHOT_GANTT"] == "1" && view != .gantt { continue }
                    model.workspaceView = view
                    await captureWorkspace(model: model, window: window, dark: dark,
                                           path: "\(directory)/workspace-\(view.rawValue)-\(Int(size.width))-\(mode).png")
                }
            }
            if ProcessInfo.processInfo.environment["APP_SNAPSHOT_GANTT"] == "1" { continue }
            window.setContentSize(NSSize(width: 1120, height: 760))
            model.workspaceView = .list
            model.archive.events = []
            await captureWorkspace(model: model, window: window, dark: dark, path: "\(directory)/workspace-list-empty-\(mode).png")
            model.archive = originalArchive
            guard let course = model.scopedCourses.first(where: { candidate in model.workspaceEvents.contains { $0.courseID == candidate.id } }) else {
                log("Capture failed: the workspace fixture has no course events"); exit(1)
            }
            model.courseFilter = course.id
            await captureWorkspace(model: model, window: window, dark: dark, path: "\(directory)/workspace-list-course-\(mode).png")
            model.courseFilter = nil
            guard let calendar = model.scopedAcademicCalendars.first else {
                log("Capture failed: the workspace fixture has no academic calendar"); exit(1)
            }
            model.academicCalendarFilter = calendar.id
            await captureWorkspace(model: model, window: window, dark: dark, path: "\(directory)/workspace-list-academic-\(mode).png")
            model.academicCalendarFilter = nil
        }
    }

    private static func captureEmptyStates(model: AppModel, window: NSWindow, directory: String, openSettings: OpenSettingsAction) async {
        let originalArchive = model.archive
        let originalPage = model.page
        let originalView = model.workspaceView
        let originalCourse = model.courseFilter
        let originalCalendar = model.academicCalendarFilter
        let originalSelection = model.selectedID
        let originalSearch = model.search
        defer {
            model.archive = originalArchive; model.page = originalPage; model.workspaceView = originalView
            model.courseFilter = originalCourse; model.academicCalendarFilter = originalCalendar
            model.selectedID = originalSelection; model.search = originalSearch
        }
        model.selectedID = nil
        model.courseFilter = nil
        model.academicCalendarFilter = nil
        model.workspaceView = .list
        for size in [NSSize(width: 940, height: 620), NSSize(width: 1280, height: 800)] {
            let width = Int(size.width)
            window.setContentSize(size)
            for dark in [false, true] {
                let mode = dark ? "dark" : "light"
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                model.archive.events = []; model.archive.sources = []
                model.search = ""
                for page in AppPage.allCases {
                    model.page = page
                    if page == .list {
                        await captureWorkspace(model: model, window: window, dark: dark, path: "\(directory)/empty-workspace-list-\(width)-\(mode).png")
                    } else {
                        await captureActive(window, path: "\(directory)/empty-\(page.rawValue.lowercased())-\(width)-\(mode).png")
                    }
                }
                model.archive = originalArchive
                model.page = .list
                model.courseFilter = "personal"
                await captureWorkspace(model: model, window: window, dark: dark, path: "\(directory)/empty-course-\(width)-\(mode).png")
                model.courseFilter = nil
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
    private static func captureWorkspace(model: AppModel, window: NSWindow, dark: Bool, path: String) async {
        NSApp.unhideWithoutActivation(); NSApp.activate(); window.makeKeyAndOrderFront(nil)
        for _ in 0..<150 {
            let state = WorkspaceWebViewState.shared
            if state.matches(model.workspaceSnapshot(dark: dark)) {
                await captureActive(window, path: path)
                return
            }
            if let failure = state.failure {
                log("Capture failed: workspace error for \(path): \(failure)"); exit(1)
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        let state = WorkspaceWebViewState.shared
        log("Capture failed: workspace render timed out for \(path); ready=\(state.isReady), expected=\(model.workspaceView.rawValue)/\(model.workspaceRevision), rendered=\(state.renderedView?.rawValue ?? "none")/\(state.renderedRevision.map(String.init) ?? "none")")
        exit(1)
    }
    private static func captureActive(_ window: NSWindow, path: String) async {
        // An inactive window dims native controls and is not valid visual evidence.
        for _ in 0..<(ProcessInfo.processInfo.environment["APP_SNAPSHOT_WAIT"] == "1" ? 500 : 5) {
            NSApp.unhideWithoutActivation(); NSApp.activate(); window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(600))
            if NSApp.isActive && window.isKeyWindow {
                if ProcessInfo.processInfo.environment["APP_SNAPSHOT_EXTERNAL"] == "1" {
                    await captureExternal(window, path: path)
                    return
                }
                capture(window, path: path)
                return
            }
        }
        log("Capture failed: window did not become active for \(path); active=\(NSApp.isActive), key=\(window.isKeyWindow), visible=\(window.isVisible), canKey=\(window.canBecomeKey)")
        exit(1)
    }
    private static func captureExternal(_ window: NSWindow, path: String) async {
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: window)
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: path) { log("SNAPSHOT \(path) (external window capture)"); return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        log("Capture failed: external window capture timed out for \(path)"); exit(1)
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
