import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Offline announcement meeting recovery")
struct LocalCurationRecoveryTests {
    private let course = Course(id: "course", name: "Synthetic course", code: "18-794",
                                term: AcademicTerm(id: "fall", name: "Fall 2026"), timeZone: "America/New_York")

    @Test func explicitRelativeMeetingUsesRealEvidenceAndStableIdentity() throws {
        var source = notice("Recitation", "Recitation today at 13:00 covers attention.")
        let event = try #require(recover(source).first)
        #expect(event.date == instant("2026-11-05T18:00:00Z") && !event.dateOnly)
        #expect(event.kind == .session && event.subtype == .recitation && event.state == .approved)
        #expect(event.sourceID == source.id && event.sourceURL == source.url && event.sourceTitle == source.title)
        #expect(event.curationVersion == EventCuration.version)
        let prepared = CurationContext.prepare(source: source, course: course, relatedSources: [])
        #expect(prepared.text.contains(event.evidence))
        #expect(RuleExtractor.evidenceSupports(date: event.date!, dateOnly: false, timeZone: event.timeZone,
                                              year: 2026, evidence: event.evidence, kind: .session))
        let item: [String: Any] = ["title": event.title, "kind": "session", "date": event.date!.ISO8601Format(),
                                  "dateOnly": false, "timeZone": event.timeZone, "evidence": event.evidence]
        let content = String(decoding: try JSONSerialization.data(withJSONObject: ["events": [item], "issues": []]), as: UTF8.self)
        let validated = try LLMClient.parseCuration(content: content, source: prepared, year: 2026, timeZone: event.timeZone)
        #expect(validated.events.first?.date == event.date && validated.issues.isEmpty)
        source.text += "\nThe slides are online."; source.fetchedAt = instant("2027-01-01T00:00:00Z")
        #expect(recover(source).first?.id == event.id)
    }

    @Test func titleCanDateItsOwnExplicitClockWithoutInventingDuration() throws {
        let source = notice("Recitation today", "We meet at 1 p.m. in the usual room.")
        let event = try #require(recover(source).first)
        #expect(event.date == instant("2026-11-05T18:00:00Z") && event.endsAt == nil)
        #expect(event.evidence.contains("2026-11-05") && event.evidence.contains("1 p.m."))
        #expect(recover(notice("Recitation today", "Homework is due at 23:59.")).isEmpty)
    }

    @Test func explicitRangesPreserveWrittenEndAndRejectTwoUnrelatedClocks() throws {
        let event = try #require(recover(notice("Recitation", "Recitation today from 1–2 p.m.")).first)
        #expect(event.date == instant("2026-11-05T18:00:00Z"))
        #expect(event.endsAt == instant("2026-11-05T19:00:00Z"))
        #expect(recover(notice("Recitation", "Recitation today at 13:00 or 14:00.")).isEmpty)
    }

    @Test func uniqueSameDaySameTypeRelatedClockIsAttributed() throws {
        let source = notice("Recitation", "Recitation today covers attention.")
        var timed = notice("Recitation", "Recitation today at 13:00."); timed.id = "timed"
        let event = try #require(recover(source, related: [timed]).first)
        #expect(event.date == instant("2026-11-05T18:00:00Z") && !event.dateOnly)
        #expect(event.sourceID == source.id && event.relatedSourceIDs == [timed.id])
        #expect(event.evidence.contains("source: timed") && event.evidence.contains(timed.url!))
        #expect(event.evidence.contains("covers attention") && event.evidence.contains("13:00"))
        var conflict = timed; conflict.id = "conflict"; conflict.text = "Recitation today at 14:00."
        #expect(recover(source, related: [timed, conflict]).isEmpty)
        var otherDay = timed; otherDay.id = "other-day"; otherDay.publishedAt = instant("2026-11-12T15:00:00Z")
        var otherCourse = timed; otherCourse.courseID = "other"
        var lecture = timed; lecture.id = "lecture"; lecture.title = "Lecture"; lecture.text = "Lecture today at 13:00."
        #expect(recover(source, related: [otherDay, otherCourse, lecture]).isEmpty)
    }

    @Test func officialClockRequiresConfirmedMatchingTypeAndActualDay() throws {
        let source = notice("Recitation", "Recitation today covers attention.")
        var official = SourceDocument(id: "official", courseID: course.id, title: "Verified schedule", text: "Thursday 13:00–14:20",
                                      url: "https://example.edu/schedule", kind: .external)
        var meeting = AcademicEvent(id: "official-meeting", courseID: course.id, title: "Recitation", kind: .session,
                                    date: instant("2026-11-05T18:00:00Z"), dateOnly: false, timeZone: "America/New_York",
                                    state: .approved, evidence: "Thursday 13:00–14:20", endsAt: instant("2026-11-05T19:20:00Z"))
        meeting.subtype = .recitation; official.meetingSchedule = [meeting]
        let event = try #require(recover(source, related: [official]).first)
        #expect(event.date == meeting.date && event.endsAt == meeting.endsAt && event.relatedSourceIDs == [official.id])
        #expect(event.evidence.contains("Verified timetable observation"))
        meeting.subtype = .lecture; official.meetingSchedule = [meeting]
        #expect(recover(source, related: [official]).isEmpty)
        meeting.subtype = .recitation; meeting.date = instant("2026-11-12T18:00:00Z"); official.meetingSchedule = [meeting]
        #expect(recover(source, related: [official]).isEmpty)
    }

    @Test func announcementTypesOnlyTheUniqueOfficialGenericSlot() throws {
        let source = notice("Recitation today", "We'll be having recitation today.")
        var official = SourceDocument(id: "official", courseID: course.id, title: "Verified schedule", text: "A Thursday 13:00–14:20",
                                      url: "https://example.edu/schedule", kind: .external)
        var slot = AcademicEvent(id: "section-a", courseID: course.id, title: "Section A", kind: .session,
                                 date: instant("2026-11-05T18:00:00Z"), dateOnly: false, timeZone: "America/New_York",
                                 state: .approved, evidence: "A Thursday 13:00–14:20", endsAt: instant("2026-11-05T19:20:00Z"))
        slot.subtype = .classMeeting; official.meetingSchedule = [slot]
        // Refined requirement: generic type is not a prohibition when the
        // source proves a type and the entire day's official schedule is unique.
        let recovered = try #require(recover(source, related: [official]).first)
        #expect(recovered.subtype == .recitation && recovered.date == slot.date && recovered.endsAt == slot.endsAt)
        #expect(recovered.sourceID == source.id && recovered.relatedSourceIDs == [official.id])
        #expect(recovered.evidence.contains("only official course meeting on this local date"))
        #expect(official.meetingSchedule?.first?.subtype == .classMeeting)
        let issue = "Recitation today: date or time needs clarification."
        #expect(LocalCurationRecovery.unresolvedIssues([issue], source: source, course: course, recoveredEvents: [recovered]).isEmpty)

        var second = slot; second.id = "section-b"; second.date = instant("2026-11-05T20:00:00Z")
        official.meetingSchedule = [slot, second]
        #expect(recover(source, related: [official]).isEmpty)
        second.date = slot.date
        official.meetingSchedule = [slot, second]
        #expect(recover(source, related: [official]).isEmpty)
        second.subtype = .lecture; second.title = "Lecture"
        official.meetingSchedule = [slot, second]
        #expect(recover(source, related: [official]).isEmpty)
        official.meetingSchedule = [second]
        #expect(recover(source, related: [official]).isEmpty)
        slot.dateOnly = true; official.meetingSchedule = [slot]
        #expect(recover(source, related: [official]).isEmpty)
    }

    @Test(arguments: ["We'll be having recitation today.",
                      "We'll be having recitation today.\n\nToday's recitation talks about linear algebra.",
                      "We'll be having recitation today. Today's recitation talks about linear algebra."])
    func repeatedRelativeDayAndPossessiveTodayRecoverOneOccurrence(_ text: String) throws {
        var source = notice("Recitation", text)
        source.publishedAt = instant("2026-10-27T05:13:00Z")
        var official = SourceDocument(id: "official", courseID: course.id, title: "Verified schedule", text: "A Tuesday 16:00–16:50",
                                      url: "https://example.edu/schedule", kind: .external)
        var slot = AcademicEvent(id: "section-a-october-27", courseID: course.id, title: "Section A", kind: .session,
                                 date: instant("2026-10-27T20:00:00Z"), dateOnly: false, timeZone: "America/New_York",
                                 state: .approved, evidence: "A Tuesday 16:00–16:50", endsAt: instant("2026-10-27T20:50:00Z"))
        slot.subtype = .classMeeting; official.meetingSchedule = [slot]
        let normalized = CurationContext.resolvedMeetingEvidence(source: source, course: course)
        #expect(!normalized.isEmpty && normalized.allSatisfy { $0.contains("2026-10-27") })
        let recovered = recover(source, related: [official])
        #expect(recovered.count == 1)
        let event = try #require(recovered.first)
        #expect(event.subtype == .recitation && !event.dateOnly)
        #expect(event.date == slot.date && event.endsAt == slot.endsAt)
        #expect(event.sourceID == source.id && event.relatedSourceIDs == [official.id])
    }

    @Test func datesAreLocalAndDSTAmbiguityNeverCreatesClock() throws {
        var source = notice("Recitation", "Recitation today at 13:00.")
        source.publishedAt = instant("2026-11-06T01:00:00Z")
        #expect(recover(source).first?.date == instant("2026-11-05T18:00:00Z"))
        source.publishedAt = instant("2026-11-01T04:30:00Z"); source.text = "Recitation today at 1:30 a.m."
        #expect(recover(source).isEmpty)
        source.text = "Recitation tomorrow at 13:00."
        #expect(recover(source).first?.date == instant("2026-11-02T18:00:00Z"))
    }

    @Test(arguments: ["Recitation today.", "Recitation next Friday at 13:00.", "Recitation today at noon.",
                      "No recitation today at 13:00.", "Recitation is cancelled today at 13:00.",
                      "If recitation meets today at 13:00, attend.", "Homework is due today at 23:59.", "Exam today at 13:00."])
    func unclearCancelledAndNonMeetingContentIsNotRecovered(_ text: String) {
        #expect(recover(notice("Course update", text)).isEmpty)
    }

    @Test func metadataAndFetchTimeAreNeverMeetingDates() {
        var source = notice("Recitation", "Recitation at 13:00.")
        source.effectiveDueAt = instant("2026-11-05T18:00:00Z"); source.availableAt = source.effectiveDueAt
        #expect(recover(source).isEmpty)
        source.text = "Recitation today at 13:00."; source.publishedAt = nil
        source.fetchedAt = instant("2026-11-05T15:00:00Z"); source.updatedAt = source.fetchedAt
        #expect(recover(source).isEmpty)
        source.publishedAt = source.fetchedAt; source.kind = .assignment
        #expect(recover(source).isEmpty)
        source.kind = .announcement; source.courseID = "other"
        #expect(recover(source).isEmpty)
    }

    @Test func issuesOnlyDisappearForProvedSourceTypeAndDay() throws {
        let source = notice("Recitation", "Recitation today at 13:00.")
        let event = try #require(recover(source).first)
        let fixed = "Recitation today: date or time needs clarification."
        let retained = ["Lecture today: date missing.", "Recitation tomorrow: date missing.",
                        "Homework Part 2 today: missing date.", "Recitation today: no date or room stated.",
                        "Recitation today has an explicit date; the room is unknown.", "Recitation: date missing."]
        #expect(LocalCurationRecovery.unresolvedIssues([fixed] + retained, source: source, course: course, recoveredEvents: [event]) == retained)
        var otherSource = event; otherSource.sourceID = "other"
        #expect(LocalCurationRecovery.unresolvedIssues([fixed], source: source, course: course, recoveredEvents: [otherSource]) == [fixed])
        var placeholder = event; placeholder.dateOnly = true
        #expect(LocalCurationRecovery.unresolvedIssues([fixed], source: source, course: course, recoveredEvents: [placeholder]) == [fixed])
    }

    @Test func provedCancellationResolvesOnlyMatchingRelativeDateQuestion() {
        let source = notice("Course update", "No recitation this Friday.")
        let fixed = "Recitation cancellation refers to this Friday without an explicit date."
        let retained = ["Recitation cancellation refers to next Friday without an explicit date.",
                        "Lecture cancellation refers to this Friday without an explicit date.",
                        "Recitation cancellation refers to this week without an explicit date.",
                        "Homework today: missing date."]
        #expect(LocalCurationRecovery.unresolvedIssues([fixed] + retained, source: source, course: course, recoveredEvents: []) == retained)
        var missingPublication = source; missingPublication.publishedAt = nil
        #expect(LocalCurationRecovery.unresolvedIssues([fixed], source: missingPublication, course: course, recoveredEvents: []) == [fixed])
    }

    @Test func repeatRestoreIsIdempotentAndRetainsOtherObservations() throws {
        let source = notice("Recitation", "Recitation today from 1–2 p.m.")
        var assignment = AcademicEvent(id: "model:assignment", courseID: course.id, title: "Homework", kind: .assignment,
                                       date: instant("2026-11-05T23:00:00Z"), dateOnly: false, state: .approved, sourceID: source.id)
        assignment.curationVersion = EventCuration.version
        let once = LocalCurationRecovery.restore(existing: [assignment], sources: [source], courses: [course])
        #expect(once.count == 2 && once.first == assignment)
        let twice = LocalCurationRecovery.restore(existing: once, sources: [source], courses: [course])
        #expect(twice == once)
        #expect(twice.filter { $0.id.hasPrefix("local-meeting:") && $0.state == .approved }.count == 1)
    }

    @Test func approvedModelObservationReplacesLocalWithoutBeingChanged() throws {
        let source = notice("Recitation", "Recitation today at 13:00.")
        let local = try #require(recover(source).first)
        var model = local; model.id = "model:later"; model.title = "Recitation · attention"; model.evidence = "Model-validated source excerpt"
        let restored = LocalCurationRecovery.restore(existing: [local, model], sources: [source], courses: [course])
        #expect(restored.count == 2)
        #expect(restored.first { $0.id == model.id } == model)
        #expect(restored.first { $0.id == local.id }?.state == .rejected)
        #expect(restored.first { $0.id == local.id }?.curationExcluded == true)
        #expect(LocalCurationRecovery.restore(existing: [model], sources: [source], courses: [course]) == [model])
    }

    @Test func rescheduledNoticeRetiresOnlyOldLocalIdentity() throws {
        var source = notice("Recitation", "Recitation today at 13:00.")
        let previous = try #require(recover(source).first)
        var unrelated = previous; unrelated.id = "model:other"; unrelated.title = "Lecture"; unrelated.subtype = .lecture
        source.text = "Recitation tomorrow at 13:00."
        let restored = LocalCurationRecovery.restore(existing: [previous, unrelated], sources: [source], courses: [course])
        #expect(restored.count == 3 && restored.first { $0.id == unrelated.id } == unrelated)
        #expect(restored.first { $0.id == previous.id }?.state == .rejected)
        #expect(restored.first { $0.id == previous.id }?.curationExcluded == true)
        let current = try #require(restored.first { $0.id.hasPrefix("local-meeting:") && $0.state == .approved })
        #expect(current.id != previous.id && current.date == instant("2026-11-06T18:00:00Z"))
        #expect(LocalCurationRecovery.restore(existing: restored, sources: [source], courses: [course]) == restored)
    }

    @Test func restorePreservesManualEditsRejectionsAndUndoneImports() throws {
        var source = notice("Recitation", "Recitation today at 13:00.")
        let local = try #require(recover(source).first)
        source.text = "Recitation tomorrow at 13:00."
        var edited = local; edited.userEdited = true; edited.title = "My recitation"; edited.date = instant("2026-11-06T19:00:00Z")
        #expect(LocalCurationRecovery.restore(existing: [edited], sources: [source], courses: [course]) == [edited])
        var rejected = local; rejected.state = .rejected; rejected.curationExcluded = nil
        #expect(LocalCurationRecovery.restore(existing: [rejected], sources: [source], courses: [course]) == [rejected])
        var undone = local; undone.importUndone = true
        #expect(LocalCurationRecovery.restore(existing: [undone], sources: [source], courses: [course]) == [undone])
    }

    private func notice(_ title: String, _ text: String) -> SourceDocument {
        var source = SourceDocument(id: "notice", courseID: course.id, title: title, text: text,
                                    url: "https://canvas.example.edu/courses/1/discussion_topics/2", kind: .announcement)
        source.publishedAt = instant("2026-11-05T15:00:00Z")
        return source
    }
    private func recover(_ source: SourceDocument, related: [SourceDocument] = []) -> [AcademicEvent] {
        LocalCurationRecovery.recover(source: source, course: course, relatedSources: related)
    }
    private func instant(_ value: String) -> Date { CanvasClient.instant(value)! }
}
