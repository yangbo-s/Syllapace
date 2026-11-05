import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Canvas evidence context")
struct CurationContextTests {
    private let course = Course(id: "course", name: "Synthetic course", code: "10-100", timeZone: "America/New_York")

    @Test func missingPublicationNeverUsesFetchTimeOrCurrentTime() {
        var source = document("notice", "Recitation", "Recitation is today at 5 PM.")
        source.fetchedAt = instant("2026-11-05T22:00:00Z")
        source.updatedAt = instant("2026-11-05T22:00:00Z")
        #expect(CurationContext.prepare(source: source, course: course, relatedSources: []).text == source.text)
    }

    @Test func publicationUsesCourseCivilDayAndKeepsOriginalEvidence() throws {
        var source = document("notice", "Recitation", "Recitation today at 5 p.m.")
        source.publishedAt = instant("2026-11-06T01:00:00Z") // Still November 5 in New York.
        let original = source
        let prepared = CurationContext.prepare(source: source, course: course, relatedSources: [])
        #expect(source == original)
        #expect(prepared.id == source.id && prepared.courseID == source.courseID && prepared.url == source.url)
        #expect(prepared.text.hasPrefix(source.text))
        #expect(prepared.text.contains("posted_at: 2026-11-06T01:00:00Z"))
        #expect(prepared.text.contains("America/New_York"))
        let evidence = "Recitation — Recitation 2026-11-05 at 5 p.m."
        #expect(prepared.text.contains(evidence))
        let result = try parse(source: prepared, title: "Recitation", kind: .session, date: "2026-11-05T17:00:00-05:00", evidence: evidence)
        #expect(result.issues.isEmpty && result.events.count == 1)
    }

    @Test func relativeDaysUseCalendarArithmeticAcrossDST() {
        var source = document("notice", "Project", "Project due tomorrow at 11:59 PM. Yesterday the proposal was discussed.")
        source.publishedAt = instant("2026-11-01T04:30:00Z")
        let prepared = CurationContext.prepare(source: source, course: course, relatedSources: [])
        #expect(prepared.text.contains("Project due 2026-11-02 at 11:59 PM. 2026-10-31 the proposal was discussed."))
    }

    @Test func onlyUnambiguousThisWeekdayIsResolved() {
        var source = document("notice", "Lecture", "Lecture this Friday. The next Friday lecture may change. This Monday was discussed.")
        source.publishedAt = instant("2026-11-05T18:00:00Z")
        let prepared = CurationContext.prepare(source: source, course: course, relatedSources: [])
        #expect(prepared.text.contains("Lecture 2026-11-06. The next Friday lecture may change. This Monday was discussed."))
        #expect(!prepared.text.contains("2026-11-13"))
        var unknownZone = course; unknownZone.timeZone = nil
        #expect(!CurationContext.prepare(source: source, course: unknownZone, relatedSources: []).text.contains("2026-11-06"))
    }

    @Test func effectiveDatesAreExplicitAndModelVerifiable() throws {
        var source = document("assignment", "Homework 4", "Solve the exercises.", kind: .assignment)
        source.effectiveDueAt = instant("2026-11-20T04:59:00Z")
        source.availableAt = instant("2026-11-05T17:00:00Z")
        let prepared = CurationContext.prepare(source: source, course: course, relatedSources: [])
        let evidence = "Homework 4 — available from 2026-11-05T17:00:00Z; due 2026-11-20T04:59:00Z"
        #expect(prepared.text.contains(evidence))
        #expect(prepared.text.contains("https://canvas.example.edu/courses/1/assignments/2"))
        let result = try parse(source: prepared, title: "Homework 4", kind: .assignment, date: "2026-11-19T23:59:00-05:00", evidence: evidence)
        #expect(result.issues.isEmpty && result.events.count == 1)
        #expect(result.events.first?.releasedAt == source.availableAt)
    }

    @Test func relatedDeadlineRequiresSameCourseAndTaskWithoutPartConfusion() {
        let notice = document("notice", "Homework 4 Released", "Homework is available.")
        var assignment = document("assignment", "Homework 4", "Exercises", kind: .assignment)
        assignment.effectiveDueAt = instant("2026-11-20T04:59:00Z")
        var otherCourse = assignment; otherCourse.id = "other-course"; otherCourse.courseID = "other"
        otherCourse.effectiveDueAt = instant("2026-11-25T04:59:00Z")
        var otherTask = assignment; otherTask.id = "other-task"; otherTask.title = "Homework 5"
        var part = assignment; part.id = "part"; part.title = "Homework 4 Part 1"
        let prepared = CurationContext.prepare(source: notice, course: course, relatedSources: [otherCourse, otherTask, part, assignment])
        #expect(prepared.text.contains("Source: assignment (Homework 4)"))
        #expect(!prepared.text.contains("Source: other-course") && !prepared.text.contains("Source: other-task") && !prepared.text.contains("Source: part"))
        var conflict = assignment; conflict.id = "conflict"; conflict.effectiveDueAt = instant("2026-11-21T04:59:00Z")
        #expect(CurationContext.prepare(source: notice, course: course, relatedSources: [assignment, conflict]).text == notice.text)
    }

    @Test func projectProposalCanUseItsAssignmentButNotUnrelatedProjectMilestone() {
        let notice = document("notice", "Project Proposal Released", "The files are available.")
        var assignment = document("proposal", "Project Proposal", "Submit the proposal.", kind: .assignment)
        assignment.effectiveDueAt = instant("2026-09-12T03:59:00Z")
        var report = assignment; report.id = "report"; report.title = "Project Final Report"
        let prepared = CurationContext.prepare(source: notice, course: course, relatedSources: [report, assignment])
        #expect(prepared.text.contains("Source: proposal (Project Proposal)"))
        #expect(!prepared.text.contains("Source: report"))
    }

    @Test func relatedRecitationMustHaveSameCourseAndResolvedDateAndUniqueTime() throws {
        var notice = document("notice", "Recitation", "Recitation today covers transformers.")
        notice.publishedAt = instant("2026-11-05T15:00:00Z")
        var timed = document("timed", "Recitation", "Recitation today at 5 p.m.")
        timed.publishedAt = instant("2026-11-05T16:00:00Z")
        var nextWeek = timed; nextWeek.id = "next-week"; nextWeek.publishedAt = instant("2026-11-12T16:00:00Z")
        var otherCourse = timed; otherCourse.id = "other-course"; otherCourse.courseID = "other"
        let prepared = CurationContext.prepare(source: notice, course: course, relatedSources: [nextWeek, otherCourse, timed])
        #expect(prepared.text.contains("Source: timed (Recitation)"))
        #expect(!prepared.text.contains("Source: next-week") && !prepared.text.contains("Source: other-course"))
        let evidence = "Recitation — Recitation 2026-11-05 at 5 p.m."
        let result = try parse(source: prepared, title: "Recitation", kind: .session, date: "2026-11-05T17:00:00-05:00", evidence: evidence)
        #expect(result.issues.isEmpty && result.events.count == 1)
        var conflicting = timed; conflicting.id = "conflict"; conflicting.text = "Recitation today at 6 p.m."
        let unresolved = CurationContext.prepare(source: notice, course: course, relatedSources: [timed, conflicting])
        #expect(!unresolved.text.contains("[Related recitation"))
    }

    @Test func officialWeeklyContextIsCompactAndNeverAssumesSectionSubtype() {
        var official = document("official", "Official class schedule", "Verified schedule", kind: .external)
        official.meetingSchedule = ["2026-11-05T18:00:00Z", "2026-11-12T18:00:00Z", "2026-11-19T18:00:00Z"].map { value in
            var event = AcademicEvent(id: value, courseID: course.id, title: "Section A", kind: .session,
                                      date: instant(value), dateOnly: false, timeZone: "America/New_York", state: .approved)
            event.endsAt = instant(value).addingTimeInterval(80 * 60)
            event.subtype = .classMeeting
            return event
        }
        var syllabus = document("syllabus", "Course syllabus", "Course policies", kind: .syllabus)
        let prepared = CurationContext.prepare(source: syllabus, course: course, relatedSources: [official])
        #expect(prepared.text.contains("do not extract or expand the whole semester again"))
        #expect(prepared.text.contains("Source: official (Official class schedule)"))
        #expect(prepared.text.contains("Class (meeting type not specified): Thursday 13:00–14:20"))
        #expect(!prepared.text.contains("Lecture:") && !prepared.text.contains("2026-11-19"))
        syllabus.kind = .assignment; syllabus.title = "Homework 1"
        #expect(!CurationContext.prepare(source: syllabus, course: course, relatedSources: [official]).text.contains("Official weekly timetable"))
        var notice = document("notice", "Recitation", "Recitation today covers graphs.")
        notice.publishedAt = instant("2026-11-05T15:00:00Z")
        let noticeContext = CurationContext.prepare(source: notice, course: course, relatedSources: [official])
        #expect(noticeContext.text.contains("Class (meeting type not specified)"))
        #expect(!noticeContext.text.contains("Recitation: Thursday"))
        official.courseID = "other-course"
        #expect(!CurationContext.prepare(source: notice, course: course, relatedSources: [official]).text.contains("Official weekly timetable"))
    }

    private func document(_ id: String, _ title: String, _ text: String, kind: SourceKind = .announcement) -> SourceDocument {
        SourceDocument(id: id, courseID: course.id, title: title, text: text,
                       url: "https://canvas.example.edu/courses/1/assignments/2", kind: kind)
    }

    private func instant(_ value: String) -> Date { CanvasClient.instant(value)! }

    private func parse(source: SourceDocument, title: String, kind: EventKind, date: String, evidence: String) throws -> CurationResult {
        let item: [String: Any] = ["title": title, "kind": kind.rawValue, "date": date, "dateOnly": false,
                                  "timeZone": "America/New_York", "evidence": evidence]
        let content = String(decoding: try JSONSerialization.data(withJSONObject: ["events": [item], "issues": []]), as: UTF8.self)
        return try LLMClient.parseCuration(content: content, source: source, year: 2026, timeZone: "America/New_York")
    }
}
