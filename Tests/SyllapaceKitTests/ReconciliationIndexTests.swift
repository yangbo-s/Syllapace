import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Indexed reconciliation")
struct ReconciliationIndexTests {
    private func event(_ id: String, title: String = "Lecture", source: String? = "source", day: Int = 0,
                       calendar: String? = nil, series: String? = nil) -> AcademicEvent {
        AcademicEvent(id: id, courseID: "course", title: title,
                      date: Date(timeIntervalSince1970: 1_793_793_600 + Double(day) * 86_400),
                      sourceID: source, academicCalendarID: calendar, sourceSeriesID: series)
    }

    @Test func largeRepeatedSeriesKeepEveryOccurrenceAndOrder() {
        let incoming = (0..<20_000).map { event("occurrence-\($0)", day: $0) }
        let result = Reconciler.merge(existing: [], incoming: incoming)
        #expect(result == incoming)
    }

    @Test func largeUpdatesRetainApprovedDatesAndProposeSourceChanges() {
        let originals = (0..<5_000).map { offset in
            var value = event("item-\(offset)", title: "Deadline \(offset)", day: offset)
            value.state = .approved
            return value
        }
        let incoming = originals.map { value in
            var changed = value; changed.date = value.date?.addingTimeInterval(3_600); return changed
        }
        let result = Reconciler.merge(existing: originals, incoming: incoming)
        #expect(result.count == originals.count)
        #expect(zip(result, originals).allSatisfy { updated, old in
            updated.id == old.id && updated.date == old.date && updated.state == .conflict &&
                updated.proposedDate == old.date?.addingTimeInterval(3_600) && updated.revision == 1
        })
    }

    @Test func repeatedTitlesNeverCollapseSeparateIncomingOccurrences() {
        let original = event("old")
        let result = Reconciler.merge(existing: [original], incoming: [event("one", day: 1), event("two", day: 2)])
        #expect(result.map(\.id) == ["old", "one", "two"])
        #expect(result.allSatisfy { $0.state == .pending })
    }

    @Test func renamedCandidatesUpdateDuplicateLookupForLaterObservations() {
        let original = event("old", title: "Old title")
        let result = Reconciler.merge(existing: [original], incoming: [
            event("old", title: "New title"),
            event("duplicate", title: "New title", source: "second", day: 1),
            event("fresh", title: "Old title", source: "third", day: 2)
        ])
        #expect(result.map(\.title) == ["New title", "New title", "Old title"])
        #expect(result[1].state == .conflict && result[1].previousDate == original.date)
        #expect(result[2].state == .pending)
    }

    @Test func userRenamingRemainsTheTitleUsedByLaterMatching() {
        var original = event("custom", title: "My title")
        original.userEdited = true
        let result = Reconciler.merge(existing: [original], incoming: [
            event("custom", title: "Source title", day: 1), event("replacement-id", title: "My title", day: 2)
        ])
        #expect(result.count == 1)
        #expect(result[0].id == "custom" && result[0].title == "My title")
        #expect(result[0].proposedDate == event("x", day: 2).date)
    }

    @Test func undoReplacementUpdatesIdentityBeforeSubsequentObservations() {
        var undone = event("old-id")
        undone.state = .rejected; undone.importUndone = true
        let result = Reconciler.merge(existing: [undone], incoming: [
            event("new-id"), event("old-id", title: "Different", source: "second"),
            event("new-id", title: "Changed", day: 2)
        ])
        #expect(result.map(\.id) == ["new-id", "old-id"])
        #expect(result[0].title == "Changed" && result[0].importUndone == nil)
        #expect(result[0].date == event("x", day: 2).date)
    }

    @Test func duplicateChoicePreservesFirstEligibleResultAndCanvasExclusion() {
        let first = event("canvas:one", source: "first", day: 1)
        let second = event("document", source: "first", day: 2)
        let result = Reconciler.merge(existing: [first, second], incoming: [
            event("canvas:two", source: "second", day: 3), event("manual", source: "third", day: 4)
        ])
        #expect(result[2].state == .conflict && result[2].previousDate == second.date)
        #expect(result[3].state == .conflict && result[3].previousDate == first.date)
    }

    @Test func movedEarliestDuplicateFallsBackToNextSourceAndRespectsOwner() {
        let originals = [event("first", source: "a", day: 1), event("second", source: "b", day: 2),
                         event("third", source: "b", day: 3), event("fourth", source: "c", day: 4)]
        let result = Reconciler.merge(existing: originals, incoming: [
            event("first", title: "Renamed", source: "a"), event("new-z", source: "z"),
            event("new-b", source: "b"), event("other-owner", source: "z", calendar: "other")
        ])
        #expect(result[4].previousDate == originals[1].date)
        #expect(result[5].previousDate == originals[3].date)
        #expect(result[6].state == .pending)
    }

    @Test func calendarUIDsOnlyMatchExactlyAndMigrateSeriesMetadata() {
        let original = event("ical:one", calendar: "school")
        let distinct = event("ical:two", calendar: "school", series: "uid-two")
        let result = Reconciler.merge(existing: [original], incoming: [distinct])
        #expect(result.map(\.id) == ["ical:one", "ical:two"])
        let migrated = Reconciler.merge(existing: [original], incoming: [event("ical:one", calendar: "school", series: "uid-one")])
        #expect(migrated.count == 1 && migrated[0].sourceSeriesID == "uid-one")
    }
}
