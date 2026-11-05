import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Cross-source assignment projection")
struct DeadlineReconciliationTests {
    @Test func canvasIdentityMergesSyllabusCopiesAndRetainsTheEffectiveDate() {
        var native = event("canvas:assignment:1", title: "Synthetic solver", source: "assignment", date: "2026-09-30T03:59:59Z")
        native.curationVersion = nil // Structured API dates also identify legacy records.
        let html = event("model:html", title: "Homework 1", source: "html", date: "2026-09-23T03:59:59Z")
        var pdf = event("model:pdf", title: "Homework 1", source: "pdf", date: "2026-09-29T16:00:00Z"); pdf.dateOnly = true
        let result = project([html, native, pdf])
        #expect(result.count == 1)
        #expect(result.first?.id == native.id && result.first?.date == native.date)
        #expect(Set(result.first?.relatedEventIDs ?? []) == [html.id, pdf.id])
        #expect(Set(result.first?.relatedSourceIDs ?? []) == ["html", "pdf"])
        #expect(project([pdf, native, html]).first == result.first)
    }

    @Test func editsPartsAndAmbiguousCanvasIdentitiesRemainSeparate() {
        let native = event("canvas:assignment:1", title: "Synthetic solver", source: "assignment", date: "2026-09-30T03:59:59Z")
        var changed = event("model:html", title: "Homework 1", source: "html", date: "2026-09-23T03:59:59Z"); changed.userEdited = true
        let part = event("model:part", title: "Homework 1 Part A", source: "pdf", date: "2026-09-30T03:59:59Z")
        #expect(project([native, changed, part]).count == 3)
        var second = native; second.id = "canvas:assignment:second"
        var copy = changed; copy.userEdited = false
        #expect(project([native, second, copy]).count == 3)
    }

    @Test func validatedLegacyDocumentIdentityStillMergesAfterRecuration() {
        let native = event("canvas:assignment:1", title: "Synthetic solver", source: "assignment", date: "2026-09-30T03:59:59Z")
        let legacy = event("document-original", title: "Homework 1", source: "html", date: "2026-09-30T03:59:59Z")
        let result = project([native, legacy])
        #expect(result.count == 1 && result[0].id == native.id)
        #expect(result[0].relatedEventIDs == [legacy.id])
        var unvalidated = legacy; unvalidated.curationVersion = nil
        #expect(project([native, unvalidated]).count == 2)
    }

    @Test func sameTaskWithoutCanvasNeedsMatchingDatesAndKeepsTransitiveAliases() {
        var html = event("model:html", title: "Homework 5", source: "html", date: "2026-12-02T04:59:59Z")
        html.relatedEventIDs = ["older-copy"]
        let pdf = event("model:pdf", title: "Homework 5", source: "pdf", date: "2026-12-02T04:59:59Z")
        var merged = project([html, pdf])
        #expect(merged.count == 1 && merged[0].relatedEventIDs?.contains("older-copy") == true)
        merged[0].userEdited = true; merged[0].state = .rejected
        #expect(project(merged + [pdf]).filter { $0.state != .rejected }.isEmpty)
        var different = pdf; different.date = CanvasClient.instant("2026-12-03T04:59:59Z")
        let conflict = project([html, different])
        #expect(conflict.count == 1 && conflict[0].state == .conflict && conflict[0].wasApproved == false)
        #expect(conflict[0].date == html.date && conflict[0].proposedDate == different.date)
        #expect(Set(conflict[0].relatedSourceIDs ?? []) == ["pdf"])
    }

    private func project(_ events: [AcademicEvent]) -> [AcademicEvent] {
        var assignment = SourceDocument(id: "assignment", courseID: "course", title: "Synthetic solver", text: "Homework 1\nSolve the task.", kind: .assignment)
        assignment.effectiveDueAt = CanvasClient.instant("2026-09-30T03:59:59Z")
        let sources = [assignment] + ["html", "pdf"].map { SourceDocument(id: $0, courseID: "course", title: "Syllabus", text: "", kind: .syllabus) }
        return CourseScheduleProjection.project(events: events, sources: sources, courses: [])
    }
    private func event(_ id: String, title: String, source: String, date: String) -> AcademicEvent {
        var value = AcademicEvent(id: id, courseID: "course", title: title, kind: .assignment, date: CanvasClient.instant(date), dateOnly: false,
                                  timeZone: "America/New_York", state: .approved, sourceID: source)
        value.curationVersion = EventCuration.version
        return value
    }
}
