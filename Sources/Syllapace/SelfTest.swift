import AppKit
import SyllapaceKit
import WebKit

enum SelfTest {
    static var ran = false
    static func runIfRequested(model: AppModel) {
        guard !ran, ProcessInfo.processInfo.environment["APP_SELFTEST"] == "1" else { return }
        ran = true
        Task { await run(model: model) }
    }
    private static func run(model: AppModel) async {
        guard let path = ProcessInfo.processInfo.environment["APP_STORE"], path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/") else { fail("Self-test requires isolated APP_STORE"); return }
        func check(_ condition: Bool, _ text: String) { if condition { Snapshot.log("PASS \(text)") } else { fail(text) } }
        let courseID = model.addCourse(name: "Integration fixture")
        let source = SourceDocument(id: "selftest-source", courseID: courseID, title: "Synthetic syllabus", text: "Final project due November 20, 2026", hash: "v1")
        model.importYear = 2026
        model.ingest(source)
        check(model.page == .timeline && model.archive.events.isEmpty && model.archive.sources.count == 1, "Import saves material without creating keyword clutter")
        func curate(_ value: SourceDocument, day: String) throws -> CurationResult {
            let payload: [String: Any] = ["events": [["title": "Final project", "kind": "project", "date": day, "dateOnly": true, "timeZone": "America/New_York", "evidence": value.text]], "issues": []]
            return try LLMClient.parseCuration(content: String(decoding: JSONSerialization.data(withJSONObject: payload), as: UTF8.self), source: value, year: 2026, timeZone: "America/New_York")
        }
        do {
            let extracted = try curate(source, day: "2026-11-20")
            check(model.commitCuration(extracted, source: source, fingerprint: model.curationFingerprint(source)), "AI curation commits automatically")
        } catch { fail(error.localizedDescription); return }
        guard var event = model.archive.events.first else { fail("No curated fixture event"); return }
        check(event.state == .approved && model.workspaceEvents.count == 1, "Validated result appears without manual approval")
        let stable = model.archive.events
        check(model.commitCuration(CurationResult(issues: ["Date evidence is incomplete"]), source: source, fingerprint: model.curationFingerprint(source)) && model.archive.events == stable && model.curationIssues.count == 1, "Incomplete curation preserves existing dates and exposes the issue")
        let beforeFirst = model.archive
        var revision = event; revision.title = "Normalized project"; revision.revision += 1
        _ = model.commitCuration(CurationResult(events: [revision]), source: source, fingerprint: model.curationFingerprint(source))
        model.lastCurationUndo = [model.curationUndo(before: beforeFirst, after: model.archive)]
        let personal = AcademicEvent(id: "user-mid-curation", courseID: courseID, title: "User created during AI work", date: event.date, state: .approved, userEdited: true)
        model.update(personal)
        let beforeSecond = model.archive
        var latest = revision; latest.location = "Room 101"; latest.revision += 1
        _ = model.commitCuration(CurationResult(events: [latest]), source: source, fingerprint: model.curationFingerprint(source))
        model.lastCurationUndo?.append(model.curationUndo(before: beforeSecond, after: model.archive))
        model.undoCuration()
        check(model.archive.events.contains { $0.id == personal.id && $0 == personal } && model.archive.events.first(where: { $0.id == event.id })?.title == event.title, "Undo reorganization preserves user work made between AI responses")
        let count = model.archive.events.count
        model.ingest(source)
        check(model.archive.events.count == count, "Repeated import keeps stable identity")
        event.userEdited = true; event.title = "My final project"; model.update(event)
        var changed = source; changed.text = "Final project due November 22, 2026"; changed.hash = "v2"
        model.ingest(changed)
        do {
            let extracted = try curate(changed, day: "2026-11-22")
            _ = model.commitCuration(extracted, source: changed, fingerprint: model.curationFingerprint(changed))
        } catch { fail(error.localizedDescription); return }
        let result = model.archive.events.first(where: { $0.id == event.id })!
        check(result.date == event.date && result.title == "My final project", "Reorganization preserves user decisions")
        check(model.workspaceEvents.filter { $0.sourceID == source.id }.count == 1
              && result.state == .conflict && result.proposedDate != nil,
              "A renamed source task stays unique and retains its proposed date conflict")
        model.page = .timeline
        model.ingest(changed, navigate: false)
        check(model.page == .timeline, "Unchanged background source does not navigate")
        do { let restored = try model.store.load(); check(restored.events == model.archive.events, "Archive survives reload") } catch { fail(error.localizedDescription) }
        check(model.error == nil, "No persistence error")
        check(L10n.string("Today", language: .english) == "Today"
              && L10n.string("Today", language: .simplifiedChinese) != "Today"
              && L10n.string("Canvas", language: .simplifiedChinese) == "Canvas",
              "Packaged language resources load and preserve product names")
        let updater = UpdateController()
        updater.startIfNeeded()
        check(!updater.isAvailable && !updater.canCheckForUpdates,
              "Isolated self-test cannot start update checks")
        let fall = AcademicTerm(id: "fixture:fall", name: "Fall 2026")
        let spring = AcademicTerm(id: "fixture:spring", name: "Spring 2026")
        let fallCourse = Course(id: "canvas:fixture:course:fall", name: "Fall fixture", code: "FALL", term: fall)
        let springCourse = Course(id: "canvas:fixture:course:spring", name: "Spring fixture", code: "SPRING", term: spring)
        model.archive.courses += [fallCourse, springCourse]
        model.discoveredCanvasCourses = [fallCourse, springCourse]
        model.archive.events += [AcademicEvent(id: "scope-fall", courseID: fallCourse.id, title: "Fall deadline", date: .now, state: .pending), AcademicEvent(id: "scope-spring", courseID: springCourse.id, title: "Spring deadline", date: .now, state: .pending)]
        model.archive.sources += [SourceDocument(id: "source-fall", courseID: fallCourse.id, title: "Fall syllabus", text: ""), SourceDocument(id: "source-spring", courseID: springCourse.id, title: "Spring syllabus", text: "")]
        model.archive.canvasSelection = nil
        check(!model.scopedEvents.contains { $0.id.hasPrefix("scope-") }, "Legacy Canvas data waits for course selection")
        model.prepareCourseSelection(termID: fall.id)
        model.applyCanvasSelection(sync: false)
        check(model.scopedEvents.contains { $0.id == "scope-fall" } && !model.scopedEvents.contains { $0.id == "scope-spring" }, "Semester selection scopes events")
        check(model.scopedSources.contains { $0.id == "source-fall" } && !model.scopedSources.contains { $0.id == "source-spring" }, "Semester selection scopes sources")
        model.page = .review
        check(!model.events.contains { $0.id == "scope-fall" || $0.id == "scope-spring" }, "Legacy pending records do not become a manual review backlog")
        model.prepareCourseSelection(termID: spring.id)
        model.applyCanvasSelection(sync: false)
        check(model.scopedEvents.contains { $0.id == "scope-spring" } && !model.scopedEvents.contains { $0.id == "scope-fall" }
              && model.archive.events.contains { $0.id == "scope-fall" }, "Switching semesters preserves history")
        guard !model.busy, !model.isDemo, let outOfScope = model.archive.events.first(where: { $0.id == "scope-fall" }) else {
            fail("Out-of-scope Calendar check requires an idle, non-demo fixture"); return
        }
        let priorNotice = model.notice, priorError = model.error
        model.resolveCalendar(outOfScope)
        // The synchronous scope guard must return before scheduling any task
        // that could enter EventKit. This check never needs calendar permission.
        check(!model.busy && model.notice == priorNotice && model.error == priorError,
              "Calendar conflict resolution ignores events outside the selected scope")
        do { let restored = try model.store.load(); check(restored.canvasSelection == model.archive.canvasSelection, "Course selection survives reload") } catch { fail(error.localizedDescription) }
        model.archive.courseDisplayMode = .codeAndName
        model.saveAppearance(CourseAppearance(mode: .custom, alias: "My systems"), for: fallCourse.id)
        check(model.courseTitle(fallCourse) == "My systems", "Course alias overrides the global display mode")
        let school = AcademicCalendarSubscription(id: "school-fall", name: "School calendar", url: "", termID: fall.id)
        model.saveAcademicCalendar(school)
        let schoolEvent = AcademicEvent(id: "school-event", courseID: "", title: "Reading day", kind: .academic, date: .now, state: .approved, academicCalendarID: school.id)
        model.archive.events.append(schoolEvent)
        check(!model.scopedEvents.contains { $0.id == schoolEvent.id }, "School dates respect semester selection")
        model.prepareCourseSelection(termID: fall.id); model.applyCanvasSelection(sync: false)
        check(model.scopedEvents.contains { $0.id == schoolEvent.id } && model.eventOwnerName(schoolEvent) == school.name, "School calendar is a separate visible owner")
        let importedSource = SourceDocument(id: "preview-source", courseID: courseID, title: "Pasted schedule", text: "Exam November 19, 2026")
        let importedEvent = AcademicEvent(id: "preview-event", courseID: courseID, title: "Exam", kind: .exam, date: .now, sourceID: importedSource.id)
        let draft = MaterialImportDraft(); draft.sources = [importedSource]; draft.candidates = [importedEvent]; draft.selected = [importedEvent.id]
        draft.baseline = model.archive.events; draft.sourceBaseline = model.archive.sources
        check(draft.commit(model: model) && model.archive.events.contains { $0.id == importedEvent.id && $0.state == .approved }, "Preview commits selected dated events in one operation")
        model.undoImport()
        check(model.archive.events.contains { $0.id == importedEvent.id && $0.state == .rejected }, "Undo retains a rejection for safe Calendar cleanup")
        if var undone = model.archive.events.first(where: { $0.id == importedEvent.id }) {
            undone.state = .approved; model.update(undone)
            check(model.archive.events.first(where: { $0.id == importedEvent.id })?.importUndone == nil, "A manual decision clears the temporary undo marker")
        }
        draft.baseline = []; check(!draft.commit(model: model), "Stale previews cannot overwrite a changed timeline")
        let desktopPreferences = DesktopCardPreferences(persists: false)
        desktopPreferences.mode = .expanded; desktopPreferences.pinned = true; desktopPreferences.locked = true
        check(desktopPreferences.mode == .expanded && desktopPreferences.pinned && desktopPreferences.locked && desktopPreferences.savedFrame == nil, "Desktop mode and controls support isolated preferences")
        do { let restored = try model.store.load(); check(restored.courseAppearances?[fallCourse.id]?.alias == "My systems" && restored.academicCalendars?.first?.id == school.id, "Customization and school calendars survive reload") } catch { fail(error.localizedDescription) }
        let localDraft = MaterialImportDraft()
        localDraft.useAI = false; localDraft.mode = 1; localDraft.owner = courseID; localDraft.year = 2026
        localDraft.text = "Local project due November 24, 2026"
        localDraft.parse(model: model)
        await localDraft.task?.value
        check(localDraft.errors.isEmpty && localDraft.sources.first?.localOnly == true && localDraft.commit(model: model),
              "Import without Use AI persists a local-only source")
        guard let localSource = localDraft.sources.first else { fail("Missing local import source"); return }
        check(model.sourcesNeedingCuration(sourceIDs: [localSource.id]).isEmpty,
              "Automatic organization excludes material imported without Use AI")
        var refreshedLocal = localSource
        refreshedLocal.text = "Local project due November 25, 2026"; refreshedLocal.hash += ":v2"; refreshedLocal.localOnly = nil
        model.ingest(refreshedLocal)
        check(model.archive.sources.first(where: { $0.id == localSource.id })?.localOnly == true
              && model.archive.sources.first(where: { $0.id == localSource.id })?.hash == refreshedLocal.hash
              && model.sourcesNeedingCuration(sourceIDs: [localSource.id]).isEmpty,
              "Refreshing a local-only source preserves its automatic-upload exclusion")
        check(model.sourcesNeedingCuration(sourceIDs: [localSource.id], force: true).contains { $0.id == localSource.id }
              && model.archive.sources.first(where: { $0.id == localSource.id })?.localOnly == true,
              "Explicit organization selects local material without enabling future automatic uploads")
        do { let restored = try model.store.load(); check(restored.sources.first(where: { $0.id == localSource.id })?.localOnly == true, "Local-only choice survives archive reload") } catch { fail(error.localizedDescription) }
        let calendarExpected = AcademicCalendarSubscription(id: "calendar-race-fixture", name: "Calendar race fixture", url: "https://calendar.example.edu/selftest.ics")
        model.saveAcademicCalendar(calendarExpected)
        do {
            let window = DateInterval(start: WorkspaceWireDate.parseInstant("2026-11-01T00:00:00Z")!, end: WorkspaceWireDate.parseInstant("2026-12-01T00:00:00Z")!)
            let calendarResult = try await AcademicCalendarClient(transport: CalendarFixtureTransport()).sync(subscription: calendarExpected, window: window)
            check(calendarResult.events.count == 1, "Synthetic academic calendar parses through the real client without networking")
            var disabled = calendarExpected; disabled.enabled = false
            model.saveAcademicCalendar(disabled)
            let beforeCalendarCommit = model.archive
            check(!model.commitAcademicCalendarSync(calendarResult, expected: calendarExpected)
                  && model.archive.events == beforeCalendarCommit.events && model.archive.sources == beforeCalendarCommit.sources
                  && model.archive.academicCalendars == beforeCalendarCommit.academicCalendars,
                  "A late calendar response cannot reactivate a disabled subscription or change its data")
            do { let restored = try model.store.load(); check(restored.events == beforeCalendarCommit.events && restored.sources == beforeCalendarCommit.sources && restored.academicCalendars == beforeCalendarCommit.academicCalendars, "Rejected calendar response leaves persisted data unchanged") } catch { fail(error.localizedDescription) }
            model.saveAcademicCalendar(calendarExpected)
            check(model.commitAcademicCalendarSync(calendarResult, expected: calendarExpected)
                  && model.archive.events.contains { $0.id == calendarResult.events[0].id },
                  "An unchanged enabled calendar accepts its response")
        } catch { fail(error.localizedDescription) }
        let editorOriginal = AcademicEvent(id: "editor-cas-fixture", courseID: courseID, title: "Original project", kind: .project,
                                           date: event.date, state: .approved, userEdited: true)
        model.update(editorOriginal)
        var backgroundUpdate = editorOriginal
        backgroundUpdate.date = editorOriginal.date?.addingTimeInterval(86_400)
        backgroundUpdate.progress = .done; backgroundUpdate.observedSourceDate = backgroundUpdate.date
        backgroundUpdate.sourceTitle = "Updated source project"; backgroundUpdate.revision += 1
        model.update(backgroundUpdate)
        var oldDraft = editorOriginal; oldDraft.title = "Stale editor title"
        check(!model.saveEditedEvent(oldDraft, replacing: editorOriginal)
              && model.archive.events.first(where: { $0.id == editorOriginal.id }) == backgroundUpdate,
              "Stale editor cannot overwrite a background date, progress, or source update")
        do { let restored = try model.store.load(); check(restored.events.first(where: { $0.id == editorOriginal.id }) == backgroundUpdate, "Rejected editor save leaves persisted data unchanged") } catch { fail(error.localizedDescription) }
        model.error = nil
        var freshDraft = backgroundUpdate; freshDraft.title = "Fresh editor title"
        check(model.saveEditedEvent(freshDraft, replacing: backgroundUpdate), "A refreshed editor can save its changes")
        freshDraft.revision += 1
        do { let restored = try model.store.load(); check(restored.events.first(where: { $0.id == editorOriginal.id }) == freshDraft, "Fresh editor save preserves background fields and persists a new revision") } catch { fail(error.localizedDescription) }
        model.page = .timeline
        model.courseFilter = nil; model.academicCalendarFilter = nil
        guard let task = model.workspaceEvents.first(where: { $0.category == .deadline }) else { fail("Missing workspace task"); return }
        let update = await model.handleWorkspace(.setProgress(eventID: task.id, expectedRevision: task.revision, progress: .doing), dark: false)
        check(update.ok && model.archive.events.first(where: { $0.id == task.id })?.progress == .doing, "Workspace progress command updates native data")
        let stale = await model.handleWorkspace(.setProgress(eventID: task.id, expectedRevision: task.revision, progress: .done), dark: false)
        check(!stale.ok && model.archive.events.first(where: { $0.id == task.id })?.progress == .doing, "Stale workspace edits are rejected")
        let outside = await model.handleWorkspace(.setProgress(eventID: "scope-spring", expectedRevision: 0, progress: .done), dark: false)
        check(!outside.ok, "Workspace cannot mutate an out-of-scope event")
        for view in WorkspaceViewMode.allCases {
            let response = await model.handleWorkspace(.setView(view), dark: false)
            check(response.ok && response.snapshot?.events.first(where: { $0.id == task.id })?.progress == .doing, "Shared task state in \(view.rawValue)")
        }
        do { let restored = try model.store.load(); check(restored.events.first(where: { $0.id == task.id })?.progress == .doing, "Workspace progress survives reload") } catch { fail(error.localizedDescription) }
        model.workspaceView = .list
        NSApp.appearance = NSAppearance(named: .aqua)
        // WebKit pauses animation frames in occluded windows. Show only this
        // isolated test window, without taking focus from a system dialog.
        NSApp.unhideWithoutActivation()
        NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) })?.orderFrontRegardless()
        for _ in 0..<250 {
            if WorkspaceWebViewState.shared.matches(model.workspaceSnapshot(dark: false)) { break }
            if let failure = WorkspaceWebViewState.shared.failure { fail(failure); return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        check(WorkspaceWebViewState.shared.matches(model.workspaceSnapshot(dark: false)), "Bundled React workspace loads in WKWebView")
        await exerciseWorkspace(model: model)
        Snapshot.log("SELFTEST complete")
        NSApp.terminate(nil)
    }

    /// Exercises the bundled React controls in the real WKWebView. These clicks
    /// cross its actual message handler and persist only to APP_STORE in /tmp.
    private static func exerciseWorkspace(model: AppModel) async {
        guard ProcessInfo.processInfo.environment["APP_SELFTEST"] == "1",
              let webView = NSApp.windows.compactMap({ $0.contentView }).compactMap(findWorkspace).first else {
            fail("No isolated WKWebView is available for interaction tests"); return
        }
        func check(_ condition: Bool, _ text: String) { if condition { Snapshot.log("PASS \(text)") } else { fail(text) } }
        let chinese = model.workspaceSnapshot(dark: false).language == "zh-Hans"
        let tabs: [(WorkspaceViewMode, String)] = [(.kanban, chinese ? "看板" : "Board"), (.gantt, chinese ? "甘特图" : "Gantt"),
                                                 (.calendar, chinese ? "日历" : "Calendar"), (.list, chinese ? "列表" : "List")]
        do {
            for (view, label) in tabs {
                try await clickWorkspace(webView, selector: "[role=tab]", text: label)
                check(await waitForWorkspace(model, until: { model.workspaceView == view }), "WKWebView \(view.rawValue) tab writes back to native selection")
                let selected = try await webView.callAsyncJavaScript("return Array.from(document.querySelectorAll('[role=tab][aria-selected=true]')).some(element => element.textContent.trim() === label)", arguments: ["label": label], in: nil, contentWorld: .page)
                check(selected as? Bool == true, "WKWebView \(view.rawValue) tab renders the acknowledged selection")
            }
            // A rolling future deadline keeps the test valid after this release.
            let fixture = AcademicEvent(id: "wk-interaction-task", courseID: model.archive.courses[0].id,
                                        title: "WK interaction fixture", kind: .project, date: Date.now.addingTimeInterval(7 * 86_400),
                                        dateOnly: false, state: .approved, userEdited: true)
            model.update(fixture)
            check(await waitForWorkspace(model, until: { WorkspaceWebViewState.shared.renderedSnapshot?.events.contains { $0.id == fixture.id } == true }),
                  "Native task appears in the bundled workspace")
            try await clickWorkspace(webView, selector: "button[aria-label]", attribute: "aria-label", text: fixture.title + (chinese ? ": 进度" : ": Progress"))
            try await clickWorkspace(webView, selector: "[role=menuitem]", text: chinese ? "已完成" : "Done")
            check(await waitForWorkspace(model, until: {
                model.archive.events.first { $0.id == fixture.id }?.progress == .done
                    && WorkspaceWebViewState.shared.renderedSnapshot?.events.first { $0.id == fixture.id }?.progress == .done
            }), "WKWebView progress control updates native data and the rendered snapshot")
            try await clickWorkspace(webView, selector: "button[aria-label]", attribute: "aria-label", text: (chinese ? "打开事项: " : "Open event: ") + fixture.title)
            try await clickWorkspace(webView, selector: "[role=menuitem]", text: chinese ? "开始安排 · 今天" : "Start work · Today")
            check(await waitForWorkspace(model, until: {
                model.archive.events.first { $0.id == fixture.id }?.plannedStart != nil
                    && WorkspaceWebViewState.shared.renderedSnapshot?.events.first { $0.id == fixture.id }?.plannedStart != nil
            }), "WKWebView work-plan control updates native data and the rendered snapshot")
            let saved = try model.store.load().events.first { $0.id == fixture.id }
            check(saved?.progress == .done && saved?.plannedStart != nil && saved?.date == fixture.date,
                  "WKWebView edits survive reload without moving the deadline")
        } catch { fail("WKWebView interaction: \(error.localizedDescription)") }
    }

    private static func findWorkspace(_ view: NSView) -> WKWebView? {
        if let workspace = view as? WKWebView { return workspace }
        return view.subviews.lazy.compactMap(findWorkspace).first
    }

    private static func waitForWorkspace(_ model: AppModel, until condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if let failure = WorkspaceWebViewState.shared.failure { fail(failure); return false }
            if condition(), WorkspaceWebViewState.shared.matches(model.workspaceSnapshot(dark: false)) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private static func clickWorkspace(_ webView: WKWebView, selector: String, attribute: String = "", text: String) async throws {
        // Poll for the actual control after React commits a menu or view change.
        // No bridge mocks or direct command invocation are used by this driver.
        for _ in 0..<100 {
            let result = try await webView.callAsyncJavaScript("""
                const element = Array.from(document.querySelectorAll(selector)).find(element =>
                    (attribute ? element.getAttribute(attribute) : element.textContent.trim()) === label &&
                    element.getClientRects().length > 0 && !element.disabled && element.getAttribute('aria-disabled') !== 'true');
                if (!element) return false;
                element.scrollIntoView({block: 'nearest', inline: 'nearest'});
                element.click();
                return true;
                """, arguments: ["selector": selector, "attribute": attribute, "label": text], in: nil, contentWorld: .page)
            if result as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "WorkspaceSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Control unavailable: \(text)"])
    }

    private struct CalendarFixtureTransport: HTTPTransport {
        nonisolated func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
            guard request.url?.absoluteString == "https://calendar.example.edu/selftest.ics",
                  request.value(forHTTPHeaderField: "Authorization") == nil else { throw ConnectorError.invalidURL }
            let data = Data("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:calendar-race\r\nDTSTART;VALUE=DATE:20261109\r\nDTEND;VALUE=DATE:20261110\r\nSUMMARY:Registration opens\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n".utf8)
            guard data.count <= maxBytes else { throw ConnectorError.responseTooLarge }
            return HTTPReply(data: data, headers: ["Content-Type": "text/calendar"])
        }
    }
    static func fail(_ message: String) { Snapshot.log("FAIL \(message)"); exit(1) }
}
