import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Unedited source completion repair")
struct ReconciliationRepairTests {
    private func legacyEndCompletion() -> AcademicEvent {
        let start = Date(timeIntervalSince1970: 1_794_065_400)
        var event = AcademicEvent(id: "canvas:school.test:calendar:42", courseID: "course", title: "Recitation",
                                  kind: .session, date: start, dateOnly: false, timeZone: "America/New_York",
                                  state: .conflict, sourceID: "canvas-calendar", evidence: "Weekly recitation",
                                  previousDate: start, proposedDate: start,
                                  proposedDateOnly: false, proposedTimeZone: "America/New_York")
        event.wasApproved = true
        event.curationVersion = 2
        event.observedSourceEndsAt = start.addingTimeInterval(3600)
        event.proposedEndsAt = event.observedSourceEndsAt
        return event
    }

    private func observation(for saved: AcademicEvent) -> AcademicEvent {
        var observation = saved
        observation.state = .approved
        observation.endsAt = saved.observedSourceEndsAt
        observation.proposedDate = nil
        observation.proposedDateOnly = nil
        observation.proposedTimeZone = nil
        observation.proposedEndsAt = nil
        return observation
    }

    @Test func unchangedSyncClearsLegacyEndCompletionConflict() throws {
        let saved = legacyEndCompletion()
        let incoming = observation(for: saved)
        let merged = try #require(Reconciler.merge(existing: [saved], incoming: [incoming]).first)
        #expect(merged.state == .approved)
        #expect(merged.date == saved.date && merged.dateOnly == saved.dateOnly && merged.timeZone == saved.timeZone)
        #expect(merged.endsAt == incoming.endsAt)
        #expect(merged.proposedDate == nil && merged.proposedDateOnly == nil && merged.proposedTimeZone == nil && merged.proposedEndsAt == nil)
        #expect(merged.wasApproved == true && !merged.userEdited && merged.id == saved.id)
        #expect(merged.revision == saved.revision + 1)
        #expect(Reconciler.merge(existing: [merged], incoming: [incoming]) == [merged])
    }

    @Test func userEditedCompletionRemainsAConflict() throws {
        var saved = legacyEndCompletion()
        saved.userEdited = true
        let merged = try #require(Reconciler.merge(existing: [saved], incoming: [observation(for: saved)]).first)
        #expect(merged.state == .conflict && merged.endsAt == nil)
        #expect(merged.proposedEndsAt == saved.proposedEndsAt && merged.date == saved.date)
    }

    @Test func existingEndTimeChangeIsNotTreatedAsMissingInformation() throws {
        var saved = legacyEndCompletion()
        saved.endsAt = saved.date!.addingTimeInterval(1800)
        let merged = try #require(Reconciler.merge(existing: [saved], incoming: [observation(for: saved)]).first)
        #expect(merged.state == .conflict && merged.endsAt == saved.endsAt)
        #expect(merged.proposedEndsAt == saved.proposedEndsAt)
    }

    @Test func neverApprovedDuplicateIsNotPromoted() throws {
        var saved = legacyEndCompletion()
        saved.wasApproved = false
        let merged = try #require(Reconciler.merge(existing: [saved], incoming: [observation(for: saved)]).first)
        #expect(merged.state == .conflict && merged.endsAt == nil)
    }

    @Test func offlineRepairIsIdempotentAndPreservesProtectedRecords() throws {
        let saved = legacyEndCompletion()
        var rejected = saved; rejected.id = "rejected"; rejected.state = .rejected
        var undone = saved; undone.id = "undone"; undone.importUndone = true
        var excluded = saved; excluded.id = "excluded"; excluded.curationExcluded = true
        var edited = saved; edited.id = "edited"; edited.userEdited = true
        var noProvenance = saved; noProvenance.id = "manual"; noProvenance.sourceID = nil
        var uncurated = saved; uncurated.id = "uncurated"; uncurated.curationVersion = nil
        var moved = saved; moved.id = "moved"; moved.proposedDate = saved.date!.addingTimeInterval(86400)
        var otherZone = saved; otherZone.id = "other-zone"; otherZone.proposedTimeZone = "UTC"
        var wrongPrecision = saved; wrongPrecision.id = "precision"; wrongPrecision.proposedDateOnly = true
        var invalidEnd = saved; invalidEnd.id = "invalid-end"; invalidEnd.proposedEndsAt = saved.date
        var unconfirmedEnd = saved; unconfirmedEnd.id = "unconfirmed"; unconfirmedEnd.observedSourceEndsAt = nil
        let protected = [rejected, undone, excluded, edited, noProvenance, uncurated, moved, otherZone, wrongPrecision, invalidEnd, unconfirmedEnd]
        let result = Reconciler.repairUneditedConflicts(existing: [saved] + protected)
        let repaired = try #require(result.first)
        #expect(repaired.state == .approved && repaired.endsAt == saved.proposedEndsAt)
        #expect(repaired.evidence == saved.evidence && repaired.sourceID == saved.sourceID && repaired.previousDate == saved.previousDate)
        #expect(Array(result.dropFirst()) == protected)
        #expect(Reconciler.repairUneditedConflicts(existing: result) == result)
    }
}
