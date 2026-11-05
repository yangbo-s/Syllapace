import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Workspace customization") struct WorkspaceCustomizationTests {
    @Test func courseAliasesRemainSeparateFromCanvasMetadata() throws {
        var archive = AppArchive()
        archive.courses = [Course(id: "canvas:school:course:1", name: "Advanced Systems", code: "18-749")]
        archive.courseDisplayMode = .codeAndName
        archive.courseAppearances = [archive.courses[0].id: CourseAppearance(mode: .custom, alias: "Systems")]
        let decoded = try JSONDecoder().decode(AppArchive.self, from: JSONEncoder().encode(archive))
        var updated = decoded.courses[0]; updated.name = "New official name"
        #expect(decoded.courseAppearances?[updated.id]?.title(for: updated, defaultMode: .code) == "Systems")
        #expect(CourseAppearance(mode: .custom, alias: "   ").title(for: updated, defaultMode: .name) == "18-749")
        #expect(CourseAppearance().title(for: updated, defaultMode: .codeAndName) == "18-749 · New official name")
    }
    @Test func schoolCalendarOwnersDoNotCollide() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = AcademicEvent(courseID: "", title: "Reading day", kind: .academic, date: date, sourceID: "first", academicCalendarID: "school-a")
        let second = AcademicEvent(courseID: "", title: "Reading day", kind: .academic, date: date, sourceID: "second", academicCalendarID: "school-b")
        #expect(Reconciler.merge(existing: [first], incoming: [second]).allSatisfy { $0.state == .pending })
    }
    @Test func undoPreservesLaterEditsAndUnrelatedRecords() {
        var before = AppArchive()
        let original = AcademicEvent(id: "a", courseID: "p", title: "Original")
        before.events = [original]
        var after = before
        var changed = original; changed.title = "Imported"
        let added = AcademicEvent(id: "b", courseID: "p", title: "New")
        after.events = [changed, added]
        let undo = ImportUndo(before: before, after: after)
        #expect(undo.restoreEvents(in: after.events) == [original])
        var later = changed; later.title = "User correction"
        let unrelated = AcademicEvent(id: "c", courseID: "p", title: "Later sync")
        #expect(undo.restoreEvents(in: [later, added, unrelated]) == [later, unrelated])
    }
    @Test func multidaySchoolBreakPreservesExclusiveEndAcrossDST() throws {
        let iso = ISO8601DateFormatter()
        let start: Date = try #require(iso.date(from: "2026-03-07T05:00:00Z"))
        let end: Date = try #require(iso.date(from: "2026-03-10T04:00:00Z"))
        let event = AcademicEvent(courseID: "", title: "Break", kind: .holiday,
                                  date: start, timeZone: "America/New_York", state: .approved,
                                  endsAt: end, academicCalendarID: "school")
        let payload = try #require(CalendarEventPayload(event: event, calendarTimeZone: TimeZone(identifier: "America/Los_Angeles")!))
        #expect(payload.end.timeIntervalSince(payload.start) == 71 * 3600)
        let ics = ICSExporter.export(events: [event], courses: [], calendars: [AcademicCalendarSubscription(id: "school", name: "University", url: "")])
        #expect(ics.contains("DTEND;VALUE=DATE:20260310"))
        #expect(ics.contains("DESCRIPTION:University"))
    }
    @Test func schemaTwoLoadsNewOptionalFieldsWithoutFabricatingSources() throws {
        let data = Data(#"{"schemaVersion":2,"courses":[],"events":[],"sources":[]}"#.utf8)
        let archive = try JSONDecoder().decode(AppArchive.self, from: data)
        #expect(archive.academicCalendars == nil && archive.courseAppearances == nil)
    }
    @Test func explicitRejectionAndUndoHaveDifferentReimportSemantics() {
        let event = AcademicEvent(id: "same", courseID: "p", title: "Exam", date: .now)
        var rejected = event; rejected.state = .rejected
        #expect(Reconciler.merge(existing: [rejected], incoming: [event]).first?.state == .rejected)
        rejected.importUndone = true
        #expect(Reconciler.merge(existing: [rejected], incoming: [event]).first?.state == .pending)
        #expect(Reconciler.merge(existing: [rejected], incoming: [event]).first?.importUndone == nil)
    }

    @Test func semesterSuggestionsNeverDefaultFallToTheWholeYear() throws {
        let fall = AcademicTerm(id: "fall", name: "Fall 2026")
        let window = try #require(fall.suggestedWindow(timeZone: .gmt))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        #expect(calendar.component(.month, from: window.start) == 8)
        #expect(calendar.component(.year, from: window.end) == 2027)
        #expect(AcademicTerm(id: "unknown", name: "2026 Program").suggestedWindow(timeZone: .gmt) == nil)
        let exact = AcademicTerm(id: "spring", name: "Spring 2026", startAt: Date(timeIntervalSince1970: 1), endAt: Date(timeIntervalSince1970: 2))
        #expect(exact.suggestedWindow(timeZone: .gmt)?.duration == 1)
    }

    @Test func migrationBackupSurvivesSubsequentSaves() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("archive.json")
        let legacy = Data(#"{"schemaVersion":2,"courses":[],"events":[],"sources":[]}"#.utf8)
        try legacy.write(to: url)
        let store = ArchiveStore(url: url)
        var archive = try store.load(); try store.save(archive)
        archive.events.append(AcademicEvent(courseID: "p", title: "New record")); try store.save(archive)
        #expect(try Data(contentsOf: url.appendingPathExtension("schema-2.backup")) == legacy)
        #expect(try store.load().events.count == 1)
    }

}
