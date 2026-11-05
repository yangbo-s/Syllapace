import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Course schedule projection")
struct CourseScheduleProjectionTests {
    private let course = Course(id: "course", name: "Course", code: "12345-A", timeZone: "America/New_York")
    private func event(_ id: String, source: String? = nil, series: String? = nil) -> AcademicEvent {
        var value = AcademicEvent(id: id, courseID: "course", title: "Recitation", kind: .session,
            date: ISO8601DateFormatter().date(from: "2026-11-06T15:00:00Z"), dateOnly: false,
            timeZone: "America/New_York", state: .approved, sourceID: source, sourceSeriesID: series)
        value.curationVersion = 2; value.subtype = .recitation
        return value
    }
    private func source(_ schedule: [AcademicEvent]) -> SourceDocument {
        var source = SourceDocument(id: "official", courseID: "course", title: "Official", text: "", hash: "stable")
        source.meetingSchedule = schedule; source.meetingScheduleComplete = true; source.localOnly = true
        return source
    }
    @Test func officialScheduleReplacesOnlyMachineExpandedSeries() {
        let official = event("official-event", source: "official", series: "official-series")
        let old = event("old", source: "syllabus", series: "schedule:old")
        var edited = old; edited.id = "edited"; edited.userEdited = true
        let independent = event("ics", source: "calendar", series: "calendar-uid")
        let originals = [official, old, edited, independent]
        let result = CourseScheduleProjection.project(events: originals, sources: [source([official])], courses: [course])
        #expect(Set(result.map(\.id)) == ["official-event", "edited", "ics"])
        let output = CourseScheduleProjection.publication(events: originals, sources: [source([official])], courses: [course])
        #expect(output.first { $0.id == "old" }?.state == .rejected)
        #expect(old.state == .approved)
    }
    @Test func olderCanvasCalendarIdentityJoinsItsTextObservation() throws {
        let canvas = event("canvas:school:443:course:1:calendar:4")
        let text = event("model:4", source: canvas.id)
        let result = CourseScheduleProjection.project(events: [canvas, text], sources: [], courses: [course])
        #expect(result.count == 1)
        var notice = text; notice.sourceID = "announcement"; notice.id = "model:notice"
        let joined = CourseScheduleProjection.project(events: [canvas, notice], sources: [], courses: [course])
        #expect(joined.count == 1)
        #expect(try #require(joined.first).relatedSourceIDs?.count == 1)
    }
    @Test func officialCampusIsNotMistakenForAConflictingClassroom() throws {
        var official = event("official-event", source: "official", series: "official-series")
        official.location = "Pittsburgh, Pennsylvania"
        var notice = event("notice", source: "announcement"); notice.location = "Hall 101"
        let result = CourseScheduleProjection.project(events: [official, notice], sources: [source([official])], courses: [course])
        #expect(result.count == 1)
        #expect(try #require(result.first).location == "Hall 101")
    }
    @Test func cancellationDoesNotOverwriteAnEditedOccurrence() {
        let official = event("official-event", source: "official", series: "official-series")
        var edited = official; edited.id = "edited"; edited.userEdited = true
        let notice = SourceDocument(id: "cancellation", courseID: "course", title: "Notice", text: "No recitation on November 6, 2026.", kind: .announcement)
        let result = CourseScheduleProjection.project(events: [official, edited], sources: [source([official]), notice], courses: [course])
        #expect(result.map(\.id) == ["edited"])
    }
    @Test func syllabusRoleAndCancellationSurviveRemovalOfRedundantModelRecurrences() {
        var official = event("official-event", source: "official", series: "official-series")
        official.title = "Class"; official.subtype = .classMeeting
        official.endsAt = official.date!.addingTimeInterval(50 * 60)
        var verified = source([official])
        verified.teachingStartsAt = ISO8601DateFormatter().date(from: "2026-08-24T04:00:00Z")
        verified.teachingEndsAt = ISO8601DateFormatter().date(from: "2026-12-05T05:00:00Z")
        var owner = course; owner.term = AcademicTerm(id: "term", name: "Fall 2026")
        let syllabus = SourceDocument(id: "syllabus", courseID: course.id, title: "Syllabus", text: "Recitation: Fridays 10:00–10:50 AM", kind: .syllabus)
        let sources = [verified, syllabus]
        let labeled = CourseScheduleProjection.project(events: [official], sources: sources, courses: [owner])
        #expect(labeled.first?.subtype == .recitation && labeled.first?.relatedSourceIDs == [syllabus.id])
        let notice = SourceDocument(id: "notice", courseID: course.id, title: "Notice", text: "No recitation on November 6, 2026.", kind: .announcement)
        #expect(CourseScheduleProjection.project(events: [official], sources: sources + [notice], courses: [owner]).isEmpty)
        var ambiguous = syllabus; ambiguous.id = "ambiguous"; ambiguous.text = "Lecture: Fridays 10:00–10:50 AM"
        #expect(CourseScheduleProjection.project(events: [official], sources: sources + [ambiguous], courses: [owner]).first?.subtype == .classMeeting)
    }
    @Test func editedAndCancelledCanonicalKeepTheirExactAliasesSuppressed() throws {
        let canonical = event("official-event", source: "official", series: "official-series")
        let notice = event("notice", source: "announcement")
        let sources = [source([canonical])]
        var joined = try #require(CourseScheduleProjection.project(events: [canonical, notice], sources: sources, courses: [course]).first)
        #expect(joined.relatedEventIDs == ["notice"])
        joined.userEdited = true; joined.title = "My recitation"
        #expect(CourseScheduleProjection.project(events: [joined, notice], sources: sources, courses: [course]).map(\.id) == [canonical.id])
        joined.state = .rejected
        let published = CourseScheduleProjection.publication(events: [joined, notice], sources: sources, courses: [course])
        #expect(published.allSatisfy { $0.state == .rejected })
        var independentlyEdited = notice; independentlyEdited.userEdited = true
        #expect(CourseScheduleProjection.project(events: [joined, independentlyEdited], sources: sources, courses: [course]).count == 2)
    }
    @Test func incompleteOfficialScheduleKeepsUnmatchedWeeklyRecitations() {
        var lecture = event("official-event", source: "official", series: "official-series")
        lecture.title = "Lecture"; lecture.subtype = .lecture
        var recitation = event("weekly", source: "syllabus", series: "schedule:weekly")
        recitation.date = recitation.date!.addingTimeInterval(86400)
        var partial = source([lecture]); partial.meetingScheduleComplete = false
        #expect(CourseScheduleProjection.project(events: [lecture, recitation], sources: [partial], courses: [course]).count == 2)
    }
    @Test func oldGlobalCanvasIdentityMatchesScopedSourceIdentity() {
        var native = event("canvas:school:443:calendar:4"); native.location = "Zoom Online Meeting"
        let sourceID = "canvas:school:443:course:1:calendar:4"
        var derived = event("model:4", source: sourceID); derived.location = "Zoom Meeting: synthetic-room"
        let document = SourceDocument(id: sourceID, courseID: "course", title: "Recitation", text: "")
        let result = CourseScheduleProjection.project(events: [native, derived], sources: [document], courses: [course])
        #expect(result.count == 1 && result.first?.id == native.id)
    }

    @Test func obsoleteModelInterpretationDoesNotDuplicateItsValidatedReplacement() {
        var old = event("model:old", source: "assignment"); old.curationVersion = 1
        var current = event("model:current", source: "assignment"); current.title = "Recitation · Topic"
        #expect(CourseScheduleProjection.project(events: [old, current], sources: [], courses: [course]).map(\.id) == [current.id])
        old.userEdited = true
        #expect(CourseScheduleProjection.project(events: [old, current], sources: [], courses: [course]).count == 2)
    }

    @Test func canvasCanonicalKeepsTransitiveModelAliasesWhenCancelled() throws {
        let native = event("canvas:school:443:calendar:4", source: "same-source")
        let current = event("model:current", source: "same-source")
        var legacy = event("model:legacy", source: "same-source"); legacy.curationVersion = 1
        var joined = try #require(CourseScheduleProjection.project(events: [native, current, legacy], sources: [], courses: [course]).first)
        #expect(joined.id == native.id)
        #expect(Set(joined.relatedEventIDs ?? []) == [current.id, legacy.id])
        joined.state = .rejected
        #expect(CourseScheduleProjection.publication(events: [joined, current, legacy], sources: [], courses: [course]).allSatisfy { $0.state == .rejected })
    }

}
