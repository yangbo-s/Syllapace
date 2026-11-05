import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Meeting occurrence projection")
struct MeetingReconciliationTests {
    private func meeting(_ id: String, source: String, title: String = "Recitation") -> AcademicEvent {
        var event = AcademicEvent(id: id, courseID: "course-A", title: title, kind: .session,
                                  date: Date(timeIntervalSince1970: 1_794_065_400), dateOnly: false,
                                  timeZone: "America/New_York", state: .approved, sourceID: source,
                                  sourceSeriesID: "model-series:" + source)
        event.curationVersion = 2
        event.subtype = .recitation
        return event
    }

    @Test func canonicalOccurrenceCollectsCrossSourceEvidenceWithoutChangingOriginals() throws {
        var announcement = meeting("announcement-event", source: "announcement", title: "Recitation · Transformers")
        announcement.relatedSourceIDs = ["another-notice"]
        announcement.endsAt = announcement.date!.addingTimeInterval(3600)
        let syllabus = meeting("syllabus-event", source: "syllabus", title: "18-749 Recitation")
        var official = meeting("official-event", source: "official")
        official.sourceSeriesID = "registrar-series:A"
        official.sourceURL = "https://school.test/schedule/fall-2026"
        let originals = [announcement, syllabus, official]
        let result = MeetingReconciliation.project(events: originals, canonicalSourceIDs: ["official"])
        let event = try #require(result.first)
        #expect(result.count == 1 && event.id == official.id)
        #expect(event.title == announcement.title && event.sourceURL == official.sourceURL)
        #expect(event.endsAt == announcement.endsAt)
        #expect(Set(event.relatedSourceIDs ?? []) == ["announcement", "syllabus", "another-notice"])
        #expect(MeetingReconciliation.project(events: result, canonicalSourceIDs: ["official"]) == result)
    }

    @Test func aDifferentMeetingKindOrDateIsNeverDeduplicated() {
        let recitation = meeting("recitation", source: "syllabus")
        var lecture = meeting("lecture", source: "announcement", title: "Lecture")
        lecture.subtype = .lecture
        var next = recitation; next.id = "next"; next.sourceID = "second"; next.date = next.date!.addingTimeInterval(7 * 86400)
        #expect(MeetingReconciliation.project(events: [recitation, lecture, next]).count == 3)
    }

    @Test func editsOtherCoursesAndIndependentCalendarSeriesArePreserved() {
        let base = meeting("base", source: "syllabus")
        var edited = meeting("edited", source: "announcement"); edited.userEdited = true
        var otherCourse = meeting("other-course", source: "other"); otherCourse.courseID = "course-B"
        var firstICS = meeting("ics-one", source: "feed-1"); firstICS.sourceSeriesID = "uid-1"
        var secondICS = meeting("ics-two", source: "feed-2"); secondICS.sourceSeriesID = "uid-2"
        var rejected = meeting("rejected", source: "rejected-source"); rejected.state = .rejected
        let events = [base, edited, otherCourse, firstICS, secondICS, rejected]
        #expect(MeetingReconciliation.project(events: events) == events)
    }

    @Test func sectionsMustMatchAndUnknownSectionCannotJoinAKnownSection() {
        let first = meeting("section-a", source: "source-1")
        let second = meeting("section-b", source: "source-2")
        let unknown = meeting("unknown", source: "source-3")
        let events = [first, second, unknown]
        #expect(MeetingReconciliation.project(events: events, sectionsByEventID: [first.id: "A", second.id: "B"]) == events)
        let same = MeetingReconciliation.project(events: [first, second], sectionsByEventID: [first.id: "A", second.id: "a"])
        #expect(same.count == 1)
    }

    @Test func sectionLabelsInTitlesRemainDistinct() {
        let first = meeting("section-a", source: "source-1", title: "Recitation Section A")
        let second = meeting("section-b", source: "source-2", title: "Recitation Section B")
        #expect(MeetingReconciliation.project(events: [first, second]) == [first, second])
    }

    @Test func conflictingDurationsAndRoomsAreNotBridgedByIncompleteEvidence() {
        var short = meeting("short", source: "source-1"); short.endsAt = short.date!.addingTimeInterval(3600)
        var long = meeting("long", source: "source-2"); long.endsAt = long.date!.addingTimeInterval(5400)
        let unknown = meeting("unknown", source: "source-3")
        #expect(MeetingReconciliation.project(events: [unknown, short, long]).count == 3)
        var roomA = short; roomA.location = "Room A"
        var roomB = long; roomB.endsAt = roomA.endsAt; roomB.location = "Room B"
        #expect(MeetingReconciliation.project(events: [roomA, unknown, roomB]).count == 3)
    }

    @Test func observationsFromOneSourceDoNotCollapseSeparateRecords() {
        let first = meeting("first", source: "same-source")
        let second = meeting("second", source: "same-source")
        #expect(MeetingReconciliation.project(events: [first, second]) == [first, second])
    }

    @Test func oneSpecificSubtypeCanCompleteAnOfficialGenericMeeting() throws {
        var official = meeting("official", source: "registrar", title: "Class")
        official.subtype = .classMeeting
        let recitation = meeting("notice", source: "announcement")
        let result = MeetingReconciliation.project(events: [official, recitation], canonicalSourceIDs: ["registrar"])
        let event = try #require(result.first)
        #expect(result.count == 1 && event.id == official.id)
        #expect(event.subtype == .recitation && event.title == recitation.title)
    }

    @Test func genericMeetingDoesNotBridgeDifferentExplicitSubtypes() {
        var generic = meeting("generic", source: "registrar", title: "Class")
        generic.subtype = .classMeeting
        let recitation = meeting("recitation", source: "recitation-notice")
        var lecture = meeting("lecture", source: "lecture-notice", title: "Lecture")
        lecture.subtype = .lecture
        let events = [generic, recitation, lecture]
        #expect(MeetingReconciliation.project(events: events, canonicalSourceIDs: ["registrar"]) == events)
    }

    @Test func explicitDurationCanIdentifyTheOnlyCompatibleSubtype() throws {
        var official = meeting("official", source: "registrar", title: "Class")
        official.subtype = .classMeeting
        official.endsAt = official.date!.addingTimeInterval(3600)
        var recitation = meeting("recitation", source: "recitation-notice")
        recitation.endsAt = official.endsAt
        var lecture = meeting("lecture", source: "lecture-notice", title: "Lecture")
        lecture.subtype = .lecture
        lecture.endsAt = official.date!.addingTimeInterval(5400)
        let result = MeetingReconciliation.project(events: [official, recitation, lecture], canonicalSourceIDs: ["registrar"])
        #expect(result.count == 2)
        #expect(try #require(result.first).subtype == .recitation)
    }
}
