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
        // Exercise the public facade with synthetic values in APP_STORE only.
        do {
            await model.loadCredentialStorage()
            check(model.credentialStorageLoaded && model.credentialStorage == .local, "Default credential storage is Local")
            check(CredentialStore.localURL.deletingLastPathComponent().deletingLastPathComponent().path == URL(fileURLWithPath: path).deletingLastPathComponent().path, "Credential file stays in the isolated store")
            try await CredentialStore.saveAsync("selftest-synthetic-token", account: model.canvasCredentialAccount)
            try await CredentialStore.saveAsync("selftest-synthetic-key", account: model.modelCredentialAccount)
            let token = try await CredentialStore.readAsync(model.canvasCredentialAccount)
            let key = try await CredentialStore.readAsync(model.modelCredentialAccount)
            check(token == "selftest-synthetic-token" && key == "selftest-synthetic-key", "Canvas and model accounts round-trip in local storage")
            let archive = String(decoding: try JSONEncoder().encode(model.archive), as: UTF8.self)
            let snapshot = String(decoding: try JSONEncoder().encode(model.workspaceSnapshot(dark: false)), as: UTF8.self)
            check(!archive.contains("selftest-synthetic-") && !snapshot.contains("selftest-synthetic-"), "Credentials stay outside the archive and WebKit snapshot")
            try await CredentialStore.deleteAsync(model.canvasCredentialAccount)
            try await CredentialStore.deleteAsync(model.modelCredentialAccount)
            // Empty selection changes need no Security.framework access.
            model.updateCredentialStorage(.keychain)
            for _ in 0..<100 where model.credentialsChanging { try await Task.sleep(for: .milliseconds(10)) }
            check(!model.busy && model.credentialStorage == .keychain && model.credentialStorageError == nil, "Settings commits optional Keychain mode")
            model.updateCredentialStorage(.local)
            for _ in 0..<100 where model.credentialsChanging { try await Task.sleep(for: .milliseconds(10)) }
            check(!model.busy && model.credentialStorage == .local && model.credentialStorageError == nil, "Settings returns to Local without reading Keychain")
            check(try await CredentialStore.readAsync(model.canvasCredentialAccount) == nil, "Deleted local credentials stay absent")
        } catch { fail("Isolated credential self-test failed"); return }
        model.notice = nil; model.error = nil
        model.syncCanvas(promptForSelection: false)
        for _ in 0..<100 where model.busy { try? await Task.sleep(for: .milliseconds(10)) }
        check(!model.busy && model.notice != nil && model.error == nil, "Background sync reports a missing local token without an alert")
        model.syncCanvas()
        for _ in 0..<100 where model.busy { try? await Task.sleep(for: .milliseconds(10)) }
        check(!model.busy && model.error != nil, "Explicit sync explains how to configure a missing token")
        model.notice = nil; model.error = nil
        let courseID = model.addCourse(name: "Integration fixture")
        let source = SourceDocument(id: "selftest-source", courseID: courseID, title: "Synthetic syllabus", text: "Final project due November 20, 2026", hash: "v1")
        model.importYear = 2026
        model.ingest(source)
        check(model.page == .list && model.archive.events.isEmpty && model.archive.sources.count == 1, "Import saves material without creating keyword clutter")
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
        check(model.sourcesNeedingCuration().isEmpty, "Saved curation skips unchanged material")
        let failureFingerprint = model.curationFingerprint(source)
        model.archive.curationRecords?[source.id] = SourceCurationRecord(fingerprint: failureFingerprint, failure: "Synthetic offline failure")
        model.save()
        do {
            model.archive = try model.store.load()
            check(model.sourcesNeedingCuration().isEmpty && model.sourcesNeedingCuration(force: true).count == 1 && model.curationIssues.isEmpty && model.curationFailures.count == 1, "Failed curation survives reload and only explicit retry repeats the request")
        } catch { fail(error.localizedDescription) }
        let legacyOwner = model.course(source.courseID), legacyWindow = model.curationWindow(for: source)
        let legacyFingerprint = EventCuration.legacyFingerprint(source: source, version: 2, modelIdentity: model.curationModelIdentity,
            year: legacyOwner.term?.academicYear ?? model.importYear, timeZone: legacyOwner.timeZone ?? TimeZone.current.identifier,
            termStart: legacyWindow.start, termEnd: legacyWindow.end)
        model.archive.curationRecords?[source.id] = SourceCurationRecord(fingerprint: legacyFingerprint)
        model.sanitizeLegacyData()
        check(model.sourcesNeedingCuration().isEmpty, "Legacy cache migrates without another model request")
        let pipelineCheckpoint = model.archive
        var dated = source; dated.publishedAt = Date(timeIntervalSince1970: 1_793_620_800)
        model.ingest(dated, navigate: false)
        model.sanitizeLegacyData()
        check(model.sourcesNeedingCuration().count == 1, "New source context invalidates the old extraction cache once")
        model.archive = pipelineCheckpoint
        var weekly = AcademicEvent(id: "official-selftest", courseID: courseID, title: "Lecture", kind: .session,
            date: Date(timeIntervalSince1970: 1_793_620_800), dateOnly: false, timeZone: "America/New_York", state: .approved,
            sourceID: "official-source", sourceSeriesID: "official-series")
        weekly.curationVersion = 2; weekly.subtype = .lecture
        var official = SourceDocument(id: "official-source", courseID: courseID, title: "Official class schedule", text: "Verified schedule", hash: "official-hash")
        official.localOnly = true; official.meetingSchedule = [weekly]
        model.ingest(official, navigate: false)
        model.restoreLocalSchedules(); model.save()
        do {
            model.archive = try model.store.load()
            check(model.archive.sources.first { $0.id == official.id }?.meetingSchedule == [weekly], "Verified weekly timetable survives an offline reload")
            check(model.workspaceEvents.contains { $0.id == weekly.id } && model.publishableEvents.contains { $0.id == weekly.id }, "Workspace and calendar export share verified occurrences")
            check(model.sourcesNeedingCuration(sourceIDs: [official.id], force: true).isEmpty, "Official schedules never make a redundant model request")
            let before = model.archive.events
            model.restoreLocalSchedules()
            check(model.archive.events == before, "Restoring cached weekly meetings is idempotent")
            var notice = weekly; notice.id = "announcement-copy"; notice.sourceID = "announcement-source"; notice.sourceSeriesID = nil; notice.location = "Hall 101"
            model.archive.events.append(notice)
            let projected = model.workspaceEvents.first { $0.id == weekly.id }
            check(projected?.relatedEventIDs == [notice.id] && projected?.location == "Hall 101", "Canonical occurrence collects exact aliases and room evidence")
            var edited = weekly; edited.userEdited = true; edited.title = "My lecture"; edited.kind = .exam
            check(model.saveEditedEvent(edited, replacing: weekly), "Editing a merged occurrence keeps a stored concurrency baseline")
            check(!model.workspaceEvents.contains { $0.id == notice.id }, "Changing a canonical meeting type keeps its duplicate hidden")
            if let current = model.archive.events.first(where: { $0.id == weekly.id }) {
                var cancelled = current; cancelled.state = .rejected
                check(model.saveEditedEvent(cancelled, replacing: current), "Cancelling the merged meeting commits its alias intent")
                check(!model.workspaceEvents.contains { $0.id == weekly.id || $0.id == notice.id }, "Cancelled aliases cannot reappear in the workspace")
            }
        } catch { fail("Verified schedule cache could not reload") }
        model.archive = pipelineCheckpoint
        let deadlineCheckpoint = model.archive
        let html = SourceDocument(id: "deadline-html", courseID: courseID, title: "Web syllabus", text: "Blog post due December 24", kind: .syllabus)
        let pdf = SourceDocument(id: "deadline-pdf", courseID: courseID, title: "PDF syllabus", text: "Blog post due December 3", kind: .syllabus)
        var first = AcademicEvent(id: "model:deadline-html", courseID: courseID, title: "Project · Blog post", kind: .project,
                                  date: ISO8601DateFormatter().date(from: "2026-12-24T17:00:00Z"), dateOnly: true,
                                  timeZone: "America/New_York", state: .approved, sourceID: html.id)
        first.curationVersion = EventCuration.version
        var second = first; second.id = "model:deadline-pdf"; second.sourceID = pdf.id
        second.date = ISO8601DateFormatter().date(from: "2026-12-03T17:00:00Z")
        model.archive.sources += [html, pdf]; model.archive.events += [first, second]
        let conflict = model.unresolvedEvents.first { $0.id == first.id }
        check(conflict?.proposedDate == second.date && conflict?.relatedSourceIDs == [pdf.id], "Conflicting syllabus dates appear once with both sources")
        check(!model.workspaceEvents.contains { $0.id == first.id || $0.id == second.id }
              && !model.publishableEvents.contains { ($0.id == first.id || $0.id == second.id) && $0.state == .approved }, "Unresolved source dates do not enter the schedule or calendar export")
        var decided = first; decided.date = second.date; decided.userEdited = true
        check(model.saveEditedEvent(decided, replacing: first), "Source conflict resolution uses the stored editing baseline")
        check(model.workspaceEvents.filter { $0.id == first.id || $0.id == second.id }.count == 1 && !model.unresolvedEvents.contains { $0.id == first.id }, "Confirmed deadline retains its aliases and clears the source conflict")
        if let stored = model.archive.events.first(where: { $0.id == first.id }) {
            var cancelled = stored; cancelled.state = .rejected
            check(model.saveEditedEvent(cancelled, replacing: stored) && !model.workspaceEvents.contains { $0.id == first.id || $0.id == second.id }, "Cancelling a merged deadline cannot restore its duplicate")
        }
        model.archive = deadlineCheckpoint
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
        model.page = .list
        model.ingest(changed, navigate: false)
        check(model.page == .list, "Unchanged background source does not navigate")
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
        model.page = .list
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
        webView.window?.setContentSize(NSSize(width: 940, height: 620))
        let chinese = model.workspaceSnapshot(dark: false).language == "zh-Hans"
        do {
            for view in WorkspaceViewMode.allCases {
                model.page = AppPage(view: view)
                check(await waitForWorkspace(model, until: { WorkspaceWebViewState.shared.renderedView == view }), "Native sidebar opens \(view.rawValue)")
                let selected = try await webView.callAsyncJavaScript("return document.querySelector('main')?.dataset.view === view && !document.querySelector('[role=tab]')", arguments: ["view": view.rawValue], in: nil, contentWorld: .page)
                check(selected as? Bool == true, "Workspace renders \(view.rawValue) without duplicate navigation")
                if view == .gantt {
                    let alignment = try await webView.callAsyncJavaScript("""
                        const rows = [...document.querySelectorAll('[data-gantt-row]')];
                        const deltas = rows.map(row => {
                          const tree = document.querySelector(`[data-slot=gantt-row-group][data-gantt-row-id="${CSS.escape(row.dataset.ganttRowId)}"]`);
                          const label = tree?.querySelector('[data-slot=gantt-tree-cell] > div');
                          const bar = row.querySelector('[data-slot=gantt-bar]');
                          const r = row.getBoundingClientRect(), t = tree?.getBoundingClientRect();
                          const l = label?.getBoundingClientRect(), b = bar?.getBoundingClientRect();
                          return {row: t ? r.top-t.top : null, bar: l && b ? b.top+b.height/2-l.top-l.height/2 : null};
                        });
                        return rows.length && deltas.some(d => d.bar !== null) && deltas.every(d => d.row !== null && Math.abs(d.row) <= 1 && (d.bar === null || Math.abs(d.bar) <= 1)) ? true : JSON.stringify(deltas);
                        """, arguments: [:], in: nil, contentWorld: .page)
                    if let geometry = alignment as? String { Snapshot.log("Row geometry: \(geometry)") }
                    check(alignment as? Bool == true, "Timeline labels and marks share a row center")
                    for width in [940, 1120, 1320, 940] {
                        webView.window?.setContentSize(NSSize(width: width, height: 620))
                        try await Task.sleep(for: .milliseconds(150))
                        let monthFits = try await webView.callAsyncJavaScript("""
                            const axis = document.querySelector('[data-gantt-axis]'), pane = document.querySelector('[data-slot=gantt-timeline-pane] [data-slot=scroll-area-viewport]');
                            if (!axis || !pane) return false;
                            const first = new Date(); first.setDate(1); first.setHours(0,0,0,0);
                            const last = new Date(first); last.setMonth(last.getMonth()+1);
                            const start = Number(axis.dataset.ganttRangeStart), span = Number(axis.dataset.ganttRangeEnd)-start;
                            const rect = axis.getBoundingClientRect(), viewport = pane.getBoundingClientRect();
                            const left = rect.left + (first-start)/span*rect.width, right = rect.left + (last-start)/span*rect.width;
                            return left >= viewport.left-2 && right <= viewport.left+pane.clientWidth+2 ? true :
                              JSON.stringify({left, right, viewportLeft: viewport.left, viewportWidth: pane.clientWidth,
                                axisWidth: rect.width, scrollWidth: pane.scrollWidth, scrollLeft: pane.scrollLeft, start, span});
                            """, arguments: [:], in: nil, contentWorld: .page)
                        if let geometry = monthFits as? String { Snapshot.log("Month geometry: \(geometry)") }
                        check(monthFits as? Bool == true, "Full month stays visible after resizing to \(width) points")
                    }
                    let fits = try await webView.callAsyncJavaScript("""
                        const axis = document.querySelector('[data-gantt-axis]');
                        const pane = document.querySelector('[data-slot=gantt-timeline-pane] [data-slot=scroll-area-viewport]');
                        if (!axis || !pane) return false;
                        const start = new Date(Number(axis.dataset.ganttRangeStart));
                        const end = new Date(Number(axis.dataset.ganttRangeEnd));
                        const before = pane.scrollLeft;
                        pane.scrollLeft += 60;
                        await new Promise(requestAnimationFrame);
                        const moved = pane.scrollLeft > before;
                        const header = document.querySelector('[data-slot=gantt-timeline-header]');
                        const origin = pane.scrollLeft;
                        header.dispatchEvent(new PointerEvent('pointerdown', { button: 0, pointerId: 1, clientX: 200, bubbles: true }));
                        window.dispatchEvent(new PointerEvent('pointermove', { pointerId: 1, clientX: 170 }));
                        window.dispatchEvent(new PointerEvent('pointerup', { pointerId: 1, clientX: 170 }));
                        await new Promise(requestAnimationFrame);
                        window.testTimelineCenter = +start + (pane.scrollLeft + pane.clientWidth/2)/pane.scrollWidth*(end-start);
                        return start.getDate() === 1 && end.getDate() === 1 && end > start && moved && pane.scrollLeft > origin;
                        """, arguments: [:], in: nil, contentWorld: .page)
                    check(fits as? Bool == true, "Timeline keeps month boundaries and supports horizontal scrolling and header dragging")
                    webView.window?.setContentSize(NSSize(width: 1120, height: 620))
                    try await Task.sleep(for: .milliseconds(150))
                    let anchorKept = try await webView.callAsyncJavaScript("""
                        const axis = document.querySelector('[data-gantt-axis]'), pane = document.querySelector('[data-slot=gantt-timeline-pane] [data-slot=scroll-area-viewport]');
                        const start = Number(axis.dataset.ganttRangeStart), span = Number(axis.dataset.ganttRangeEnd)-start;
                        const center = start + (pane.scrollLeft+pane.clientWidth/2)/pane.scrollWidth*span;
                        return Math.abs(center-window.testTimelineCenter) < 2*3600000;
                        """, arguments: [:], in: nil, contentWorld: .page)
                    check(anchorKept as? Bool == true, "Resizing preserves the user's panned timeline date")
                    webView.window?.setContentSize(NSSize(width: 940, height: 620))
                }
                if view == .calendar {
                    let month = try await webView.callAsyncJavaScript("return !!document.querySelector('[data-slot=event-calendar-month-view]')", arguments: [:], in: nil, contentWorld: .page)
                    check(month as? Bool == true, "Calendar opens to month view")
                }

            }
            model.page = .list
            check(await waitForWorkspace(model, until: { WorkspaceWebViewState.shared.renderedView == .list }), "Native List selection is rendered")
            let savedEvents = model.archive.events
            let density = (0..<45).map { index in
                AcademicEvent(id: "scroll-fixture-\(index)", courseID: model.archive.courses[0].id,
                    title: "Scroll fixture \(index)", kind: .project, date: Date.now.addingTimeInterval(Double(index + 1) * 86400),
                    dateOnly: true, state: .approved, userEdited: true)
            }
            model.archive.events += density; model.save()
            check(await waitForWorkspace(model, until: { WorkspaceWebViewState.shared.renderedSnapshot?.events.contains { $0.id == "scroll-fixture-44" } == true }), "Dense list reaches the workspace")
            let scrolling = try await webView.callAsyncJavaScript("""
                const pane = document.querySelector('[data-slot=list-scroll-viewport]');
                const footer = document.querySelector('[data-slot=list-pagination]');
                if (!pane || !footer) return false;
                pane.scrollTop = 60;
                await new Promise(requestAnimationFrame);
                return pane.scrollTop > 0 && pane.scrollWidth <= pane.clientWidth + 1 && footer.getBoundingClientRect().bottom <= innerHeight &&
                  getComputedStyle(pane).overflowY === 'auto' && document.querySelectorAll('tbody tr').length === 20;
                """, arguments: [:], in: nil, contentWorld: .page)
            check(scrolling as? Bool == true, "List uses native scrolling with 20 rows and a visible pagination footer")
            model.page = AppPage(view: .gantt)
            check(await waitForWorkspace(model, until: { WorkspaceWebViewState.shared.renderedView == .gantt }), "Dense timeline reaches the workspace")
            let denseAlignment = try await webView.callAsyncJavaScript("""
                const pane = document.querySelector('[data-slot=gantt-timeline-pane] [data-slot=scroll-area-viewport]');
                const treePane = document.querySelector('[data-slot=gantt-tree-pane] [data-slot=scroll-area-viewport]');
                const results = [];
                for (const position of [0, 120, 1e6, 0]) {
                  pane.scrollTop = position;
                  await new Promise(resolve => setTimeout(resolve, 100));
                  const rows = [...document.querySelectorAll('[data-gantt-row]')];
                  const deltas = rows.map(row => {
                    const tree = document.querySelector(`[data-slot=gantt-row-group][data-gantt-row-id="${CSS.escape(row.dataset.ganttRowId)}"]`);
                    const label = tree?.querySelector('[data-slot=gantt-tree-cell] > div');
                    const bar = row.querySelector('[data-slot=gantt-bar]');
                    const r = row.getBoundingClientRect(), t = tree?.getBoundingClientRect();
                    const l = label?.getBoundingClientRect(), b = bar?.getBoundingClientRect();
                    return {row: t ? r.top-t.top : null, bar: l && b ? b.top+b.height/2-l.top-l.height/2 : null};
                  });
                  results.push({position, scroll: pane.scrollTop, treeScroll: treePane.scrollTop, timelineHeight: pane.scrollHeight, treeHeight: treePane.scrollHeight, deltas});
                }
                return results.every(r => r.deltas.length > 10 && r.deltas.every(d => d.row !== null && Math.abs(d.row) <= 1 && (d.bar === null || Math.abs(d.bar) <= 1))) ? true : JSON.stringify(results);
                """, arguments: [:], in: nil, contentWorld: .page)
            if let geometry = denseAlignment as? String { Snapshot.log("Dense row geometry: \(geometry)") }
            check(denseAlignment as? Bool == true, "Dense timeline keeps labels and marks aligned at the top, middle and bottom")
            model.archive.events = Array(density.prefix(12)); model.save()
            check(await waitForWorkspace(model, until: { WorkspaceWebViewState.shared.renderedSnapshot?.events.count == 12 }), "Boundary-height timeline reaches the workspace")
            let heightDelta = try await webView.callAsyncJavaScript("const tree = document.querySelector('[data-slot=gantt-tree-pane] [data-slot=scroll-area-viewport]'); return tree.scrollHeight-tree.clientHeight", arguments: [:], in: nil, contentWorld: .page)
            if let delta = heightDelta as? Double, let window = webView.window, let content = window.contentView {
                window.setContentSize(NSSize(width: content.frame.width, height: content.frame.height + delta * AppAppearance.shared.scale))
            }
            try await Task.sleep(for: .milliseconds(150))
            let boundaryAlignment = try await webView.callAsyncJavaScript("""
                const pane = document.querySelector('[data-slot=gantt-timeline-pane] [data-slot=scroll-area-viewport]');
                const tree = document.querySelector('[data-slot=gantt-tree-pane] [data-slot=scroll-area-viewport]');
                pane.scrollTop = 1e6;
                await new Promise(resolve => setTimeout(resolve, 150));
                const row = document.querySelector('[data-gantt-row]');
                const label = document.querySelector('[data-slot=gantt-row-group]');
                const delta = row.getBoundingClientRect().top-label.getBoundingClientRect().top;
                return Math.abs(delta) <= 1 && pane.scrollTop >= pane.scrollHeight-pane.clientHeight-1 ? true :
                  JSON.stringify({delta, scroll: pane.scrollTop, treeScroll: tree.scrollTop, height: pane.scrollHeight, client: pane.clientHeight, treeHeight: tree.scrollHeight, treeClient: tree.clientHeight});
                """, arguments: [:], in: nil, contentWorld: .page)
            if let geometry = boundaryAlignment as? String { Snapshot.log("Boundary row geometry: \(geometry)") }
            check(boundaryAlignment as? Bool == true, "Timeline stays aligned when only the horizontal scrollbar causes vertical overflow")
            webView.window?.setContentSize(NSSize(width: 940, height: 620))
            model.archive.events = savedEvents; model.save()
            model.page = .list
            let previousNotice = model.notice
            model.notice = nil
            try await Task.sleep(for: .milliseconds(350))
            let scheduleFrame = webView.convert(webView.bounds, to: nil)
            model.notice = L10n.format("Imported %ld events. You can undo this import.", 12)
            try await Task.sleep(for: .milliseconds(350))
            check(webView.convert(webView.bounds, to: nil) == scheduleFrame, "Import feedback preserves the schedule viewport")
            model.showActivity = true
            try await Task.sleep(for: .milliseconds(500))
            check(webView.convert(webView.bounds, to: nil) == scheduleFrame, "Activity details do not displace the schedule")
            model.showActivity = false
            model.notice = previousNotice
            // A rolling future deadline keeps the test valid after this release.
            let fixture = AcademicEvent(id: "wk-interaction-task", courseID: model.archive.courses[0].id,
                                        title: "WK interaction fixture", kind: .project, date: Date.now.addingTimeInterval(7 * 86_400),
                                        dateOnly: false, state: .approved, userEdited: true)
            model.update(fixture)
            check(await waitForWorkspace(model, until: { WorkspaceWebViewState.shared.renderedSnapshot?.events.contains { $0.id == fixture.id } == true }),
                  "Native task appears in the bundled workspace")
            let past = AcademicEvent(id: "wk-history-fixture", courseID: fixture.courseID,
                                     title: "WK history fixture", kind: .exam, date: Date.now.addingTimeInterval(-7 * 86_400),
                                     dateOnly: false, state: .approved, userEdited: true)
            model.update(past)
            check(await waitForWorkspace(model, until: { WorkspaceWebViewState.shared.renderedSnapshot?.events.contains { $0.id == past.id } == true }), "Historical source remains in the native snapshot")
            let hidden = try await webView.callAsyncJavaScript("return !document.querySelector('main').textContent.includes(title) && !document.querySelector('[aria-label$=Progress]')", arguments: ["title": past.title], in: nil, contentWorld: .page)
            check(hidden as? Bool == true, "History is hidden by default without completion controls")
            try await clickWorkspace(webView, selector: "button[aria-label]", attribute: "aria-label", text: chinese ? "显示历史" : "Show history")
            // Click the historical row after React commits, exercising real keyboard-accessible controls.
            try await clickWorkspace(webView, selector: "button", text: past.title)
            check(await waitForWorkspace(model, until: { model.editor?.id == past.id }), "History toggle reveals a past event and opens its native editor")
            model.editor = nil
            let appearance = AppAppearance.shared
            let originalAccent = appearance.accentHex
            appearance.accentHex = "346ABE"
            let nativeAccent = appearance.webTokens(dark: false)["primary"]
            check(await waitForWorkspace(model, until: { WorkspaceWebViewState.shared.renderedSnapshot?.theme?["primary"] == nativeAccent }), "Custom accent reaches the actual WKWebView")
            let css = try await webView.callAsyncJavaScript("return getComputedStyle(document.documentElement).getPropertyValue('--primary').trim()", arguments: [:], in: nil, contentWorld: .page)
            check(css as? String == nativeAccent, "Rendered CSS uses the native custom accent")
            appearance.accentHex = originalAccent
            let saved = try model.store.load().events.first { $0.id == fixture.id }
            check(saved?.date == fixture.date && saved?.progress == .todo, "Viewing schedule history does not change source dates or saved progress")
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
