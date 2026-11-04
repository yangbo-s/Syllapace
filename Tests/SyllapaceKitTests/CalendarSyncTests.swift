import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Calendar ownership and synchronization")
struct CalendarSyncTests {
    private var event: AcademicEvent {
        AcademicEvent(id: "exam-1", courseID: "course-1", title: "Midterm", kind: .exam,
                      date: Date(timeIntervalSince1970: 1_794_499_200), dateOnly: true,
                      timeZone: "America/New_York", state: .approved, evidence: "Midterm: November 12")
    }
    private func snapshot(_ event: AcademicEvent, id: String = "ek-1") -> CalendarEventSnapshot {
        CalendarEventSnapshot(identifier: id, payload: CalendarEventPayload(event: event)!)
    }
    @Test func publishesOnlyConfirmedDates() {
        var pending = event
        pending.state = .pending
        #expect(CalendarSyncPlanner.action(event: pending, binding: nil, current: nil) == .unchanged)
        pending.state = .approved
        pending.date = nil
        guard case .blocked = CalendarSyncPlanner.action(event: pending, binding: nil, current: nil) else { Issue.record("Unknown date must not publish"); return }
    }
    @Test func stableRepeatedSyncDoesNotCreateDuplicate() {
        let current = snapshot(event)
        let binding = CalendarEventBinding(calendarEventID: current.identifier, lastWritten: current)
        #expect(CalendarSyncPlanner.action(event: event, binding: binding, current: current) == .unchanged)
    }
    @Test func movesOriginalEventWhenDateChanges() {
        let current = snapshot(event)
        var changed = event
        changed.date = changed.date!.addingTimeInterval(86_400)
        let binding = CalendarEventBinding(calendarEventID: current.identifier, lastWritten: current)
        #expect(CalendarSyncPlanner.action(event: changed, binding: binding, current: current) == .update("ek-1", CalendarEventPayload(event: changed)!))
    }
    @Test func preservesExternalEditAndDeletion() {
        let written = snapshot(event)
        let binding = CalendarEventBinding(calendarEventID: written.identifier, lastWritten: written)
        var external = written
        external.payload.title = "Personal exam reminder"
        guard case .blocked = CalendarSyncPlanner.action(event: event, binding: binding, current: external) else { Issue.record("External edit overwritten"); return }
        guard case .blocked = CalendarSyncPlanner.action(event: event, binding: binding, current: nil) else { Issue.record("External deletion recreated"); return }
    }
    @Test func rejectsOnlyOwnedUnmodifiedEvent() {
        let written = snapshot(event)
        let binding = CalendarEventBinding(calendarEventID: written.identifier, lastWritten: written)
        var rejected = event
        rejected.state = .rejected
        #expect(CalendarSyncPlanner.action(event: rejected, binding: binding, current: written) == .delete("ek-1"))
        var external = written
        external.extraState = "user added an alarm"
        guard case .blocked = CalendarSyncPlanner.action(event: rejected, binding: binding, current: external) else { Issue.record("External edit removed"); return }
        #expect(CalendarSyncPlanner.action(event: rejected, binding: nil, current: nil) == .unchanged)
    }
    @Test func recoversCommittedWriteAfterMappingFailure() {
        let written = snapshot(event)
        let pending = CalendarEventBinding(pendingPayload: written.payload)
        #expect(CalendarSyncPlanner.action(event: event, binding: pending, current: written) == .adopt(written))
        guard case .blocked = CalendarSyncPlanner.action(event: event, binding: pending, current: nil) else { Issue.record("Ambiguous write duplicated"); return }
    }
    @Test func recoversInterruptedDelete() {
        let written = snapshot(event)
        let pending = CalendarEventBinding(calendarEventID: written.identifier, lastWritten: written, pendingDeletion: true)
        var rejected = event
        rejected.state = .rejected
        #expect(CalendarSyncPlanner.action(event: rejected, binding: pending, current: nil) == .forget)
        #expect(CalendarSyncPlanner.action(event: rejected, binding: pending, current: written) == .delete("ek-1"))
    }
    @Test func daylightSavingAllDayHasCalendarDayDuration() {
        var daylight = event
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        daylight.date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let payload = CalendarEventPayload(event: daylight, calendarTimeZone: calendar.timeZone)!
        #expect(payload.end.timeIntervalSince(payload.start) == 23 * 3_600)
        daylight.dateOnly = false
        let timed = CalendarEventPayload(event: daylight)!
        #expect(timed.start == timed.end)
        #expect(timed.start == daylight.date)
    }
    @Test func relinksIdentifierWithoutChangingIdentity() {
        let written = snapshot(event)
        let binding = CalendarEventBinding(calendarEventID: written.identifier, lastWritten: written)
        let relinked = snapshot(event, id: "replacement-id")
        #expect(written.fingerprint == relinked.fingerprint)
        #expect(CalendarSyncPlanner.action(event: event, binding: binding, current: relinked) == .adopt(relinked))
    }
    @Test func malformedTimezoneCannotPublish() {
        var invalid = event
        invalid.timeZone = "Not/A_Timezone"
        #expect(CalendarEventPayload(event: invalid) == nil)
    }
    @Test func floatingDateSurvivesDeviceTimeZoneDifference() {
        var original = event
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        original.timeZone = tokyo.timeZone.identifier
        original.date = tokyo.date(from: DateComponents(year: 2026, month: 11, day: 12))!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let local = CalendarEventPayload(event: original, calendarTimeZone: losAngeles)!
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = losAngeles
        #expect(localCalendar.component(.day, from: local.start) == 12)
        let tokyoPayload = CalendarEventPayload(event: original, calendarTimeZone: tokyo.timeZone)!
        #expect(local == tokyoPayload)
        #expect(CalendarEventSnapshot(identifier: "a", payload: local).fingerprint == CalendarEventSnapshot(identifier: "b", payload: tokyoPayload).fingerprint)
    }
    @Test func normalizesModernEventKitAllDayEnd() {
        let payload = CalendarEventPayload(event: event)!
        let zone = TimeZone(identifier: payload.timeZone)!
        #expect(CalendarEventPayload.normalizedAllDayEnd(payload.end.addingTimeInterval(-1), timeZone: zone) == payload.end)
        #expect(CalendarEventPayload.normalizedAllDayEnd(payload.end, timeZone: zone) == payload.end)
    }

}
