import Foundation
import SyllapaceKit

extension AppModel {
    var scopedAcademicCalendars: [AcademicCalendarSubscription] {
        (archive.academicCalendars ?? []).filter {
            $0.enabled && ($0.termID == nil || archive.canvasSelection?.termID == nil || $0.termID == archive.canvasSelection?.termID)
        }
    }
    func isInScope(courseID: String, calendarID: String?) -> Bool {
        if let calendarID { return scopedAcademicCalendars.contains { $0.id == calendarID } }
        return scopedCourseIDs.contains(courseID)
    }
    func academicDateIsVisible(_ event: AcademicEvent) -> Bool {
        guard let id = event.academicCalendarID, let subscription = archive.academicCalendars?.first(where: { $0.id == id }), let date = event.presentationDate else { return true }
        let term = availableTerms.first { $0.id == archive.canvasSelection?.termID }
        let suggested = term?.suggestedWindow(timeZone: TimeZone(identifier: subscription.timeZone) ?? .current)
        let lower = [subscription.windowStart, suggested?.start].compactMap { $0 }.max()
        let upper = [subscription.windowEnd, suggested?.end].compactMap { $0 }.min()
        return (lower.map { bound in event.endsAt.map { $0 > bound } ?? (date >= bound) } ?? true) && (upper.map { date < $0 } ?? true)
    }
    func courseTitle(_ course: Course) -> String {
        var localized = course
        localized.name = course.localizedName; localized.code = course.localizedCode
        return (archive.courseAppearances?[course.id] ?? CourseAppearance()).title(for: localized, defaultMode: archive.courseDisplayMode ?? .code)
    }
    func eventOwnerName(_ event: AcademicEvent) -> String {
        if let id = event.academicCalendarID { return archive.academicCalendars?.first { $0.id == id }?.name ?? L10n.string("Academic calendar") }
        return courseTitle(course(event.courseID))
    }
    func sourceOwnerName(_ source: SourceDocument) -> String {
        if let id = source.academicCalendarID { return archive.academicCalendars?.first { $0.id == id }?.name ?? L10n.string("Academic calendar") }
        return courseTitle(course(source.courseID))
    }
    func eventColor(_ event: AcademicEvent) -> Int { event.academicCalendarID == nil ? course(event.courseID).color : 3 }
    func eventSearchText(_ event: AcademicEvent) -> String {
        eventOwnerName(event) + " " + course(event.courseID).name + " " + course(event.courseID).code
    }
    func saveAppearance(_ appearance: CourseAppearance, for courseID: String) {
        if archive.courseAppearances == nil { archive.courseAppearances = [:] }
        archive.courseAppearances?[courseID] = appearance; save()
    }
    func saveAcademicCalendar(_ subscription: AcademicCalendarSubscription) {
        if archive.academicCalendars == nil { archive.academicCalendars = [] }
        if let i = archive.academicCalendars?.firstIndex(where: { $0.id == subscription.id }) { archive.academicCalendars?[i] = subscription }
        else { archive.academicCalendars?.append(subscription) }
        if !subscription.enabled, academicCalendarFilter == subscription.id { academicCalendarFilter = nil }
        save()
    }
    func syncAcademicCalendar(_ subscription: AcademicCalendarSubscription) {
        guard !busy, !isDemo, subscription.enabled,
              archive.academicCalendars?.first(where: { $0.id == subscription.id }) == subscription else { return }
        let now = Date.now
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: subscription.timeZone) ?? .current
        let year = cal.component(.year, from: now)
        let start = subscription.windowStart ?? cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = subscription.windowEnd ?? cal.date(byAdding: .year, value: 1, to: start)!
        guard end > start else { calendarStatus[subscription.id] = L10n.string("End date must follow start date."); return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let result = try await AcademicCalendarClient().sync(subscription: subscription, window: DateInterval(start: start, end: end))
                commitAcademicCalendarSync(result, expected: subscription)
            } catch {
                guard archive.academicCalendars?.first(where: { $0.id == subscription.id }) == subscription else { return }
                calendarStatus[subscription.id] = error.localizedDescription
            }
        }
    }
    @discardableResult func commitAcademicCalendarSync(_ result: AcademicCalendarSyncResult, expected: AcademicCalendarSubscription) -> Bool {
        guard expected.enabled, result.subscription.id == expected.id,
              let index = archive.academicCalendars?.firstIndex(where: { $0.id == expected.id }),
              archive.academicCalendars?[index] == expected else { return false }
        let checkpoint = archive
        archive.academicCalendars?[index] = result.subscription
        if let index = archive.sources.firstIndex(where: { $0.id == result.source.id }) { archive.sources[index] = result.source }
        else { archive.sources.append(result.source) }
        archive.events = result.reconcile(existing: archive.events)
        guard save() else { archive = checkpoint; return false }
        calendarStatus[expected.id] = ([L10n.format("Calendar dates synced: %ld.", result.events.count)] + result.warnings).joined(separator: "\n")
        return true
    }
    @discardableResult func commitImport(sources: [SourceDocument], candidates: [AcademicEvent], records: [String: SourceCurationRecord] = [:]) -> Bool {
        let before = archive
        for source in sources {
            if let index = archive.sources.firstIndex(where: { $0.id == source.id }) { archive.sources[index] = source } else { archive.sources.append(source) }
        }
        if !records.isEmpty {
            if archive.curationRecords == nil { archive.curationRecords = [:] }
            archive.curationRecords?.merge(records) { _, new in new }
        }
        if !records.isEmpty {
            let completeSources = Set(records.filter { ($0.value.issues ?? []).isEmpty }.keys)
            archive.events = EventCuration.reorganize(existing: archive.events, incoming: candidates, sourceIDs: completeSources).events
        }
        for event in candidates {
            if let index = archive.events.firstIndex(where: { $0.id == event.id }) { archive.events[index] = event } else { archive.events.append(event) }
        }
        guard save() else { archive = before; return false }
        lastImportUndo = ImportUndo(before: before, after: archive)
        page = .list
        courseFilter = nil; academicCalendarFilter = nil
        notice = L10n.format("Imported %ld events. You can undo this import.", candidates.count)
        return true
    }
    func undoImport() {
        guard let undo = lastImportUndo, !busy else { return }
        let before = archive
        let previous = archive.events
        archive.events = undo.restoreEvents(in: previous)
        let kept = Set(archive.events.map(\.id))
        // Rejected tombstones let EventKit remove only app-owned, unedited copies.
        archive.events += previous.filter { !kept.contains($0.id) }.map { event in
            var removed = event; removed.state = .rejected; removed.importUndone = true; return removed
        }
        archive.sources = undo.restoreSources(in: archive.sources, referencedSourceIDs: Set(archive.events.filter { $0.state != .rejected }.compactMap(\.sourceID)))
        guard save() else { archive = before; return }
        lastImportUndo = nil; selectedID = nil; notice = L10n.string("Import undone. Later edits were kept.")
    }
}
