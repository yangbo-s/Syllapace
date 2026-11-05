import Foundation
import Testing
@testable import SyllapaceKit

struct WorkspaceSemanticsTests {
    @Test func labeledReleaseAndDueProduceOneTaskWithAWindow() throws {
        let source = SourceDocument(courseID: "course", title: "Schedule", text: "Homework 4 released November 1, 2026; due November 20, 2026 at 23:00 UTC.")
        let events = RuleExtractor.extract(source: source, year: 2026, timeZone: "UTC")
        let task = try #require(events.first)
        #expect(events.count == 1)
        #expect(task.title == "Homework 4")
        #expect(task.date == CanvasClient.instant("2026-11-20T23:00:00Z"))
        #expect(task.releasedAt.map { WorkspaceWireDate.dateOnly($0, timeZone: "UTC") } == "2026-11-01")
    }
    @Test func sourceReleaseNeedsAnExplicitDateAndDoesNotUseTheDeadline() throws {
        let due = try #require(CanvasClient.instant("2026-11-20T23:00:00Z"))
        let release = RuleExtractor.releaseDate(in: "Homework released November 1, 2026. Due November 20, 2026 at 23:00 UTC.", year: 2026, timeZone: "UTC", due: due)
        #expect(release?.1 == true)
        #expect(release.map { WorkspaceWireDate.dateOnly($0.0, timeZone: "UTC") } == "2026-11-01")
        #expect(RuleExtractor.releaseDate(in: "Homework due November 20, 2026.", year: 2026, timeZone: "UTC", due: due) == nil)
        #expect(RuleExtractor.releaseDate(in: "Released December 1, 2026. Due November 20, 2026.", year: 2026, timeZone: "UTC", due: due) == nil)
    }

    @Test func dateOnlyReleaseStartsAtTheBeginningOfItsCivilDay() throws {
        let due = try #require(CanvasClient.instant("2026-11-20T10:00:00Z"))
        let release = RuleExtractor.releaseDate(in: "Released November 20, 2026. Due November 20, 2026 at 10:00 UTC.", year: 2026, timeZone: "UTC", due: due)
        #expect(release?.1 == true)
        #expect(release.map { WorkspaceWireDate.dateOnly($0.0, timeZone: "UTC") } == "2026-11-20")
    }
    @Test func sourceAvailabilityRefreshPreservesUserPlanAndDeadline() throws {
        var saved = AcademicEvent(id: "canvas:test:assignment:1", courseID: "course", title: "Homework", date: try #require(CanvasClient.instant("2026-11-20T23:00:00Z")), dateOnly: false, state: .approved)
        saved.plannedStart = CanvasClient.instant("2026-11-10T15:00:00Z")
        var incoming = saved
        incoming.releasedAt = CanvasClient.instant("2026-11-01T15:00:00Z"); incoming.releaseDateOnly = false; incoming.plannedStart = nil
        let updated = try #require(Reconciler.merge(existing: [saved], incoming: [incoming]).first)
        #expect(updated.releasedAt == incoming.releasedAt)
        #expect(updated.plannedStart == saved.plannedStart)
        #expect(updated.date == saved.date)
        #expect(try JSONDecoder().decode(AcademicEvent.self, from: JSONEncoder().encode(updated)) == updated)
    }
    @Test func practiceMaterialIsNotAnActualExam() {
        #expect(CanvasClassification.kind(title: "18-749 PRACTICE Mid-Term Exam", quiz: true) == .other)
        #expect(!EventCuration.supports(.exam, evidence: "This is a practice mid-term exam. Available until December 4, 2026."))
        #expect(CanvasClassification.kind(title: "Project Midterm Report") == .project)
        #expect(CanvasClassification.kind(title: "Mid-Term Exam") == .exam)
    }

    @Test func legacyPracticeIsExcludedReversiblyAndEditsSurvive() {
        let practice = AcademicEvent(id: "canvas:test:quiz:12", courseID: "course", title: "PRACTICE Mid-Term Exam", kind: .exam,
            date: Date(timeIntervalSince1970: 1_796_432_400), state: .approved, evidence: "This is a practice mid-term exam.")
        var edited = practice; edited.id += "-edited"; edited.userEdited = true
        let result = EventCuration.sanitizeLegacyEvents(existing: [practice, edited], courseIDs: ["course"])
        #expect(result.events[0].state == .rejected)
        #expect(result.events[0].date == practice.date)
        #expect(result.events[0].curationExcluded == true)
        #expect(result.events[1] == edited)
        #expect(result.undo(current: result.events) == [practice, edited])
    }
}
