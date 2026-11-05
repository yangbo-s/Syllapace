import AppKit
import SyllapaceKit

extension AppModel {
    func canPresent(_ event: AcademicEvent) -> Bool {
        guard event.category != nil else { return false }
        let generated = event.id.hasPrefix("document-") || event.id.hasPrefix("model:")
        return !generated || event.userEdited || event.curationVersion != nil
    }
    var projectedEvents: [AcademicEvent] { CourseScheduleProjection.project(events: scopedEvents, sources: archive.sources, courses: scopedCourses) }
    var presentationEvents: [AcademicEvent] { projectedEvents.filter { $0.academicCalendarID == nil && canPresent($0) } }
    var publishableEvents: [AcademicEvent] {
        CourseScheduleProjection.publication(events: scopedEvents, sources: archive.sources, courses: scopedCourses).map { event in
            guard event.academicCalendarID == nil, !event.userEdited else { return event }
            var guarded = event
            if event.category == nil { guarded.state = .rejected }
            else if !canPresent(event), event.state == .approved { guarded.state = .pending }
            return guarded
        }
    }
    var workspaceEvents: [AcademicEvent] {
        projectedEvents.filter { event in
            guard event.state == .approved || (event.state == .conflict && event.wasApproved == true),
                  courseFilter == nil || event.courseID == courseFilter else { return false }
            if let academicCalendarFilter { return event.academicCalendarID == academicCalendarFilter }
            return event.academicCalendarID == nil && canPresent(event)
        }.sorted {
            if $0.presentationDate != $1.presentationDate { return ($0.presentationDate ?? .distantFuture) < ($1.presentationDate ?? .distantFuture) }
            return $0.id < $1.id
        }
    }
    func workspaceSnapshot(dark: Bool) -> WorkspaceSnapshot {
        let courses = scopedCourses.map { WorkspaceCourse(id: $0.id, label: courseTitle($0), code: $0.code, name: $0.name, color: $0.color) }
            + scopedAcademicCalendars.map { WorkspaceCourse(id: "calendar:" + $0.id, label: $0.name, code: "", name: $0.name, color: 3) }
        let items = workspaceEvents.compactMap { event -> WorkspaceEvent? in
            let category: WorkspaceCategory
            if event.academicCalendarID != nil { category = .academic }
            else if let value = event.category, let mapped = WorkspaceCategory(rawValue: value.rawValue) { category = mapped }
            else { return nil }
            func wireDate(_ value: Date?) -> String? {
                value.map { event.dateOnly ? WorkspaceWireDate.dateOnly($0, timeZone: event.timeZone) : WorkspaceWireDate.instant($0) }
            }
            return WorkspaceEvent(id: event.id, courseID: event.academicCalendarID.map { "calendar:" + $0 } ?? event.courseID,
                courseLabel: eventOwnerName(event), title: event.title, category: category,
                subtype: event.subtype?.rawValue ?? EventCuration.subtype(for: event.title, kind: event.kind)?.rawValue ?? event.kind.rawValue,
                start: wireDate(event.date), end: wireDate(event.endsAt), dateOnly: event.dateOnly, timeZone: event.timeZone,
                progress: WorkspaceProgress(rawValue: event.progress.rawValue) ?? .todo,
                plannedStart: event.plannedStart.map(WorkspaceWireDate.instant),
                releasedAt: event.releasedAt.map { event.releaseDateOnly == true ? WorkspaceWireDate.dateOnly($0, timeZone: event.timeZone) : WorkspaceWireDate.instant($0) },
                releaseDateOnly: event.releaseDateOnly, location: event.location,
                evidence: String(event.evidence.prefix(4_000)), sourceURL: event.sourceURL.flatMap { URL(string: $0) }.flatMap(WorkspaceNavigation.externalURL)?.absoluteString, revision: event.revision,
                seriesID: event.sourceSeriesID, userEdited: event.userEdited)
        }
        let scope = academicCalendarFilter.flatMap { id in scopedAcademicCalendars.first { $0.id == id }?.name }
            ?? courseFilter.map { courseTitle(course($0)) } ?? (archive.canvasSelection == nil ? L10n.string("Workspace") : selectedSemesterName)
        return WorkspaceSnapshot(revision: workspaceRevision, language: L10n.language.rawValue,
            appearance: dark ? "dark" : "light", theme: AppAppearance.shared.webTokens(dark: dark), view: workspaceView, scope: scope,
            loading: busy || curationTask != nil, needsSemester: needsCourseSelection,
            now: WorkspaceWireDate.instant(.now), courses: courses, events: items)
    }
    func handleWorkspace(_ command: WorkspaceCommand, dark: Bool) async -> WorkspaceResponse {
        func failure(_ message: String) -> WorkspaceResponse { WorkspaceResponse(ok: false, snapshot: workspaceSnapshot(dark: dark), error: L10n.string(message)) }
        func event(_ id: String) -> AcademicEvent? { workspaceEvents.first { $0.id == id } }
        func commit(_ changed: AcademicEvent) -> Bool {
            guard let index = archive.events.firstIndex(where: { $0.id == changed.id }) else { return false }
            let old = archive.events[index]
            archive.events[index] = changed
            guard save() else { archive.events[index] = old; return false }
            return true
        }
        switch command {
        case .ready: break
        case .setView(let view):
            selectWorkspaceView(view)
        case .setProgress(let id, let expectedRevision, let progress):
            guard var item = event(id), item.category == .deadline else { return failure("This task is no longer available in the selected courses.") }
            guard item.revision == expectedRevision else { return failure("This task changed. The latest version has been loaded; try again.") }
            item.taskProgress = TaskProgress(rawValue: progress.rawValue); item.completed = progress == .done; item.revision += 1
            guard commit(item) else { return failure("Could not save changes. Try again.") }
        case .setPlan(let id, let expectedRevision, let plannedStart):
            guard var item = event(id), item.category == .deadline, let due = item.date else { return failure("Only dated tasks can have a work plan.") }
            guard item.revision == expectedRevision else { return failure("This task changed. The latest version has been loaded; try again.") }
            let start = plannedStart.flatMap(WorkspaceWireDate.parseInstant)
            var courseCalendar = Calendar(identifier: .gregorian)
            courseCalendar.timeZone = TimeZone(identifier: item.timeZone) ?? .current
            let withinDeadline = start.map { item.dateOnly ? courseCalendar.startOfDay(for: $0) <= courseCalendar.startOfDay(for: due) : $0 <= due } ?? true
            guard plannedStart == nil || start != nil, withinDeadline else { return failure("The planned start must be before the deadline.") }
            item.plannedStart = start; item.revision += 1
            guard commit(item) else { return failure("Could not save changes. Try again.") }
        case .openEditor(let id):
            guard let item = event(id) else { return failure("This event is no longer available.") }
            editor = archive.events.first { $0.id == item.id } ?? item
        case .openSource(let id):
            guard let item = event(id), let raw = item.sourceURL, let url = URL(string: raw), let safe = WorkspaceNavigation.externalURL(url) else { return failure("No web source is available for this event.") }
            NSWorkspace.shared.open(safe)
        case .addMaterial: showImport = true
        case .chooseSemester: manageCanvasCourses()
        case .createEvent: newEvent()
        }
        return WorkspaceResponse(snapshot: workspaceSnapshot(dark: dark))
    }
}
