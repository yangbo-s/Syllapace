import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Explicit course cancellation evidence")
struct CancellationEvidenceTests {
    private let course = Course(id: "course", name: "Synthetic course", code: "10-100",
                                term: AcademicTerm(id: "fall", name: "Fall 2026"), timeZone: "America/New_York")

    @Test func thisFridayCancelsOnlySameCourseConfirmedRecitation() throws {
        let source = notice("No recitation this Friday.", published: "2026-11-05T20:00:00Z")
        let cancellation = try #require(CancellationEvidence.extract(source: source, course: course).first)
        #expect(cancellation.subtype == .recitation)
        #expect(cancellation.start == instant("2026-11-06T05:00:00Z"))
        #expect(cancellation.end == instant("2026-11-07T05:00:00Z"))
        #expect(cancellation.sourceID == source.id && cancellation.sourceURL == source.url && cancellation.evidence == source.text)
        let recitation = meeting("Recitation", subtype: .recitation, date: "2026-11-06T18:00:00Z")
        #expect(cancellation.matches(event: recitation))
        #expect(!cancellation.matches(event: meeting("Lecture", subtype: .lecture, date: "2026-11-06T18:00:00Z")))
        #expect(!cancellation.matches(event: meeting("Section A", subtype: .classMeeting, date: "2026-11-06T18:00:00Z")))
        var anotherCourse = recitation; anotherCourse.courseID = "other"
        #expect(!cancellation.matches(event: anotherCourse))
        #expect(!cancellation.matches(event: meeting("Recitation", subtype: .recitation, date: "2026-11-13T18:00:00Z")))
    }

    @Test func thisWeekUsesCivilWeekBoundariesAcrossDST() throws {
        let source = notice("There is no class this week.", published: "2026-11-01T16:00:00Z")
        let cancellation = try #require(CancellationEvidence.extract(source: source, course: course).first)
        #expect(cancellation.subtype == nil)
        #expect(cancellation.start == instant("2026-10-26T04:00:00Z"))
        #expect(cancellation.end == instant("2026-11-02T05:00:00Z"))
        #expect(cancellation.end.timeIntervalSince(cancellation.start) == 169 * 3_600)
    }

    @Test func publicationDayIsLocalAndTomorrowIsCalendarBased() throws {
        let today = try #require(CancellationEvidence.extract(source: notice("Lecture is cancelled today.", published: "2026-11-06T01:00:00Z"), course: course).first)
        #expect(today.start == instant("2026-11-05T05:00:00Z"))
        let tomorrow = try #require(CancellationEvidence.extract(source: notice("Cancelled tomorrow's lecture.", published: "2026-11-01T04:30:00Z"), course: course).first)
        #expect(tomorrow.start == instant("2026-11-02T05:00:00Z"))
    }

    @Test(arguments: [
        "Lecture is not cancelled today.", "No homework today; recitation meets as usual.",
        "No class cancellations this week.", "No classes are cancelled today.",
        "If lecture is cancelled tomorrow, watch for a notice.", "Lecture may be cancelled tomorrow.",
        "No recitation next Friday.", "No lecture. Homework is due November 6."
    ])
    func uncertainNegatedAndUnrelatedStatementsDoNotCancel(_ text: String) {
        #expect(CancellationEvidence.extract(source: notice(text, published: "2026-11-05T20:00:00Z"), course: course).isEmpty)
    }

    @Test func missingPublicationNeverUsesFetchDateAndReinstatementDefeatsOldTitle() {
        var source = notice("No recitation today.", published: nil)
        source.fetchedAt = instant("2026-11-05T20:00:00Z")
        source.updatedAt = source.fetchedAt
        #expect(CancellationEvidence.extract(source: source, course: course).isEmpty)
        source = notice("Recitation is not cancelled today.", published: "2026-11-05T20:00:00Z")
        source.title = "No Recitation Today"
        #expect(CancellationEvidence.extract(source: source, course: course).isEmpty)
    }

    @Test(arguments: ["No lecture on 2026-11-06.", "Lecture is canceled on November 6, 2026.", "No class on 6th November."])
    func explicitDatesWorkWithoutPublication(_ text: String) throws {
        let cancellation = try #require(CancellationEvidence.extract(source: notice(text, published: nil), course: course).first)
        #expect(cancellation.start == instant("2026-11-06T05:00:00Z"))
    }

    @Test func wrongCourseInvalidDateAndUnknownZoneRemainUnresolved() {
        var source = notice("No class on February 31, 2026.", published: nil)
        #expect(CancellationEvidence.extract(source: source, course: course).isEmpty)
        source.text = "No class on November 6, 2026."; source.courseID = "other"
        #expect(CancellationEvidence.extract(source: source, course: course).isEmpty)
        source.courseID = course.id
        var unknown = course; unknown.timeZone = nil
        #expect(CancellationEvidence.extract(source: source, course: unknown).isEmpty)
    }

    private func notice(_ text: String, published: String?) -> SourceDocument {
        var source = SourceDocument(id: "notice", courseID: course.id, title: "Course update", text: text,
                                    url: "https://canvas.example.edu/courses/1/discussion_topics/2", kind: .announcement)
        source.publishedAt = published.map(instant)
        return source
    }

    private func meeting(_ title: String, subtype: EventSubtype, date: String) -> AcademicEvent {
        var event = AcademicEvent(courseID: course.id, title: title, kind: .session, date: instant(date),
                                  dateOnly: false, timeZone: "America/New_York", state: .approved)
        event.subtype = subtype
        return event
    }

    private func instant(_ value: String) -> Date { CanvasClient.instant(value)! }
}
