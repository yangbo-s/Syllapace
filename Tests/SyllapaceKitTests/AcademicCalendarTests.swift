import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Academic calendar subscriptions")
struct AcademicCalendarTests {
    let range = DateInterval(start: CanvasClient.instant("2026-01-01T00:00:00Z")!, end: CanvasClient.instant("2027-01-01T00:00:00Z")!)
    func calendar(_ events: String) -> String { "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" + events + "\r\nEND:VCALENDAR\r\n" }
    func parse(_ events: String, window: DateInterval? = nil) throws -> ICalendarResult {
        try ICalendarReader.parse(text: calendar(events), sourceID: "source", calendarID: "school", timeZone: "America/New_York", window: window ?? range, sourceURL: "https://school.example/calendar.ics")
    }
    @Test func allDayCalendarPreservesExclusiveMultiDayEndAndIndependentScope() throws {
        let result = try parse("""
        BEGIN:VEVENT
        UID:break
        DTSTART;VALUE=DATE:20261123
        DTEND;VALUE=DATE:20261128
        SUMMARY:Thanksgiving break
        END:VEVENT
        """)
        let event = try #require(result.events.first)
        #expect(result.warnings.isEmpty)
        #expect(event.courseID.isEmpty && event.academicCalendarID == "school")
        #expect(event.kind == .holiday && event.state == .approved && event.dateOnly)
        #expect(event.date == CanvasClient.instant("2026-11-23T05:00:00Z"))
        #expect(event.endsAt == CanvasClient.instant("2026-11-28T05:00:00Z"))
    }
    @Test func weeklyRecurrencePreservesLocalTimeAcrossDST() throws {
        let result = try parse("""
        BEGIN:VEVENT
        UID:meeting
        DTSTART;TZID=America/New_York:20260302T100000
        DTEND;TZID=America/New_York:20260302T113000
        RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=MO
        SUMMARY:Registration advising
        END:VEVENT
        """)
        #expect(result.warnings.isEmpty)
        #expect(result.events.map(\.date) == ["2026-03-02T15:00:00Z", "2026-03-09T14:00:00Z", "2026-03-16T14:00:00Z"].map(CanvasClient.instant))
        #expect(result.events.allSatisfy { $0.endsAt?.timeIntervalSince($0.date!) == 5400 })
    }
    @Test func exclusionsAndMovedInstanceUseOriginalIdentityAndInheritedDetails() throws {
        let base = """
        BEGIN:VEVENT
        UID:weekly
        DTSTART;TZID=America/New_York:20261102T100000
        DTEND;TZID=America/New_York:20261102T110000
        RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=MO
        EXDATE;TZID=America/New_York:20261109T100000
        SUMMARY:Academic advising
        LOCATION:Room 2
        END:VEVENT
        """
        let original = try parse(base)
        let modified = try parse(base + "\n" + """
        BEGIN:VEVENT
        UID:weekly
        RECURRENCE-ID;TZID=America/New_York:20261116T100000
        DTSTART;TZID=America/New_York:20261117T120000
        SEQUENCE:1
        END:VEVENT
        """)
        #expect(modified.warnings.isEmpty && modified.events.count == 2)
        let moved = try #require(modified.events.last)
        #expect(moved.id == original.events.last?.id)
        #expect(moved.date == CanvasClient.instant("2026-11-17T17:00:00Z"))
        #expect(moved.endsAt == CanvasClient.instant("2026-11-17T18:00:00Z"))
        #expect(moved.title == "Academic advising" && moved.location == "Room 2")
    }
    @Test func latestSequenceWinsWithoutCreatingDuplicates() throws {
        let result = try parse("""
        BEGIN:VEVENT
        UID:deadline
        DTSTART;VALUE=DATE:20261109
        SUMMARY:Withdrawal deadline
        SEQUENCE:1
        END:VEVENT
        BEGIN:VEVENT
        UID:deadline
        DTSTART;VALUE=DATE:20261110
        SUMMARY:Withdrawal deadline
        SEQUENCE:2
        END:VEVENT
        """)
        #expect(result.events.count == 1)
        #expect(result.events.first?.date == CanvasClient.instant("2026-11-10T05:00:00Z"))
    }
    @Test func foldedTextEscapesAndNestedAlarmsDoNotOverrideEvent() throws {
        let result = try parse("""
        BEGIN:VEVENT
        UID:text
        DTSTART:20261101T120000Z
        SUMMARY:Important registration
         deadline
        DESCRIPTION:Line one\\nLine two\\, with comma
        LOCATION:Building A\\; Room 2
        BEGIN:VALARM
        SUMMARY:Not the event title
        END:VALARM
        END:VEVENT
        """)
        let event = try #require(result.events.first)
        #expect(event.title == "Important registrationdeadline")
        #expect(event.evidence.contains("Line one\nLine two, with comma"))
        #expect(event.location == "Building A; Room 2")
    }
    @Test func monthlyOrdinalAndInvalidMonthDaysRespectCount() throws {
        let ordinal = try parse("""
        BEGIN:VEVENT
        UID:second-monday
        DTSTART;VALUE=DATE:20260112
        RRULE:FREQ=MONTHLY;COUNT=3;BYDAY=2MO
        SUMMARY:Advising
        END:VEVENT
        """)
        #expect(ordinal.events.map(\.date) == ["2026-01-12T05:00:00Z", "2026-02-09T05:00:00Z", "2026-03-09T04:00:00Z"].map(CanvasClient.instant))
        let lastDay = try parse("""
        BEGIN:VEVENT
        UID:month-31
        DTSTART;VALUE=DATE:20260131
        RRULE:FREQ=MONTHLY;COUNT=3
        SUMMARY:Monthly registration
        END:VEVENT
        """)
        #expect(lastDay.events.map(\.date) == ["2026-01-31T05:00:00Z", "2026-03-31T04:00:00Z", "2026-05-31T04:00:00Z"].map(CanvasClient.instant))
    }
    @Test func yearlyMonthAndWeekdayRuleAndInclusiveUntil() throws {
        let years = DateInterval(start: range.start, end: CanvasClient.instant("2029-01-01T00:00:00Z")!)
        let result = try parse("""
        BEGIN:VEVENT
        UID:thanksgiving
        DTSTART;VALUE=DATE:20261126
        RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;UNTIL=20281123
        SUMMARY:University holiday
        END:VEVENT
        """, window: years)
        #expect(result.warnings.isEmpty)
        #expect(result.events.map(\.date) == ["2026-11-26T05:00:00Z", "2027-11-25T05:00:00Z", "2028-11-23T05:00:00Z"].map(CanvasClient.instant))
    }
    @Test func countDoesNotRestartAtWindowAndRDatesDeduplicate() throws {
        let window = DateInterval(start: CanvasClient.instant("2026-06-01T00:00:00Z")!, end: range.end)
        let result = try parse("""
        BEGIN:VEVENT
        UID:limited
        DTSTART;VALUE=DATE:20260101
        RRULE:FREQ=DAILY;COUNT=3
        RDATE;VALUE=DATE:20261109,20261109
        SUMMARY:Three early dates plus one later date
        END:VEVENT
        """, window: window)
        #expect(result.events.count == 1)
        #expect(result.events.first?.date == CanvasClient.instant("2026-11-09T05:00:00Z"))
    }
    @Test func unsupportedRulesAndUnknownZonesBecomeUndatedReviewItems() throws {
        for body in ["DTSTART;VALUE=DATE:20260101\nRRULE:FREQ=MONTHLY;BYDAY=MO;BYSETPOS=1", "DTSTART;TZID=Private-Custom-Zone:20261101T120000"] {
            let result = try parse("BEGIN:VEVENT\nUID:unsupported\nSUMMARY:Needs review\n" + body + "\nEND:VEVENT")
            #expect(result.warnings.count == 1)
            #expect(result.events.count == 1 && result.events[0].state == .pending && result.events[0].date == nil)
        }
    }
    @Test func cancelledInstancesAreNotImportedAndReportKeptHistory() throws {
        let result = try parse("""
        BEGIN:VEVENT
        UID:series
        DTSTART;VALUE=DATE:20261101
        RRULE:FREQ=DAILY;COUNT=2
        SUMMARY:Advising
        END:VEVENT
        BEGIN:VEVENT
        UID:series
        RECURRENCE-ID;VALUE=DATE:20261102
        STATUS:CANCELLED
        END:VEVENT
        """)
        #expect(result.events.count == 1)
        #expect(result.warnings.count == 1 && result.warnings[0].contains("cancelled"))
    }
    @Test func futureRangeOverrideCannotLeaveStaleSeriesApproved() throws {
        let result = try parse("""
        BEGIN:VEVENT
        UID:series
        DTSTART;VALUE=DATE:20261101
        RRULE:FREQ=DAILY;COUNT=4
        SUMMARY:Advising
        END:VEVENT
        BEGIN:VEVENT
        UID:series
        RECURRENCE-ID;VALUE=DATE;RANGE=THISANDFUTURE:20261102
        DTSTART;VALUE=DATE:20261103
        END:VEVENT
        """)
        #expect(result.events.allSatisfy { $0.state == .pending && $0.date == nil })
        #expect(!result.warnings.isEmpty)
    }
    func syncResult(_ parsed: ICalendarResult) -> AcademicCalendarSyncResult {
        AcademicCalendarSyncResult(subscription: AcademicCalendarSubscription(id: "school", name: "School", url: "https://school.example/calendar.ics"),
                                   source: SourceDocument(id: "source", courseID: "", title: "School", text: "", academicCalendarID: "school"),
                                   events: parsed.events, warnings: parsed.warnings, coverageStart: nil, coverageEnd: nil,
                                   reviewSeriesIDs: parsed.reviewSeriesIDs, reviewEventIDs: parsed.reviewEventIDs)
    }
    @Test func cancellationAndExclusionKeepSavedDatesButRequireReview() throws {
        let base = "BEGIN:VEVENT\nUID:series\nDTSTART;VALUE=DATE:20261101\nRRULE:FREQ=DAILY;COUNT=3\nSUMMARY:Advising\nEND:VEVENT"
        let existing = try parse(base).events
        let cancelled = try parse(base + "\nBEGIN:VEVENT\nUID:series\nRECURRENCE-ID;VALUE=DATE:20261102\nSTATUS:CANCELLED\nEND:VEVENT")
        let merged = syncResult(cancelled).reconcile(existing: existing)
        #expect(merged.count == 3)
        let changed = try #require(merged.first { $0.id == existing[1].id })
        #expect(changed.date == existing[1].date && changed.state == .conflict && changed.wasApproved == true)
        #expect(changed.proposedDate == nil)
        #expect(merged.filter { $0.state == .approved }.count == 2)
        let excluded = try parse(base.replacingOccurrences(of: "SUMMARY:", with: "EXDATE;VALUE=DATE:20261102\nSUMMARY:"))
        #expect(syncResult(excluded).reconcile(existing: existing).first { $0.id == existing[1].id }?.state == .conflict)
        let absent = syncResult(try parse("" )).reconcile(existing: existing)
        #expect(absent == existing)
    }
    @Test func wholeSeriesCancellationAndUnsupportedRangeReviewAllExistingInstances() throws {
        let base = "BEGIN:VEVENT\nUID:series\nDTSTART;VALUE=DATE:20261101\nRRULE:FREQ=DAILY;COUNT=3\nSUMMARY:Advising\nEND:VEVENT"
        var existing = try parse(base).events
        existing[2].state = .rejected
        for change in [base.replacingOccurrences(of: "SUMMARY:", with: "STATUS:CANCELLED\nSUMMARY:"),
                       base + "\nBEGIN:VEVENT\nUID:series\nRECURRENCE-ID;VALUE=DATE;RANGE=THISANDFUTURE:20261102\nDTSTART;VALUE=DATE:20261103\nEND:VEVENT"] {
            let result = syncResult(try parse(change)).reconcile(existing: existing)
            for original in existing {
                let updated = try #require(result.first { $0.id == original.id })
                #expect(updated.date == original.date)
                #expect(updated.state == (original.state == .rejected ? .rejected : .conflict))
            }
        }
    }
    @Test func unrelatedExclusionDoesNotChangeASingleSavedEvent() throws {
        let base = "BEGIN:VEVENT\nUID:single\nDTSTART;VALUE=DATE:20261101\nSUMMARY:Registration\nEND:VEVENT"
        let existing = try parse(base).events
        let observation = try parse(base.replacingOccurrences(of: "SUMMARY:", with: "EXDATE;VALUE=DATE:20261102\nSUMMARY:"))
        #expect(observation.reviewEventIDs.isEmpty)
        #expect(syncResult(observation).reconcile(existing: existing).first?.state == .approved)
    }
    @Test func oversizedDurationIsNotTruncatedIntoAValidDate() throws {
        let result = try parse("BEGIN:VEVENT\nUID:duration\nDTSTART:20261101T120000Z\nDURATION:P999999999999999999999DT1H\nSUMMARY:Review duration\nEND:VEVENT")
        #expect(result.events.first?.date == nil && result.events.first?.state == .pending)
        #expect(!result.warnings.isEmpty)
    }
    @Test func cancellationOfParsingIsPropagated() async throws {
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try parse("BEGIN:VEVENT\nUID:cancelled-task\nDTSTART;VALUE=DATE:20260101\nRRULE:FREQ=DAILY\nSUMMARY:Dates\nEND:VEVENT")
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func recurrenceCannotMultiplyDescriptionsBeyondThePayloadLimit() throws {
        let description = String(repeating: "x", count: 100_000)
        #expect(throws: ConnectorError.responseTooLarge) {
            try parse("BEGIN:VEVENT\nUID:large-series\nDTSTART;VALUE=DATE:20260101\nRRULE:FREQ=DAILY;COUNT=250\nSUMMARY:Dates\nDESCRIPTION:\(description)\nEND:VEVENT")
        }
    }
    @Test func invalidLocalDateAndAmbiguousTimeAreNotInvented() throws {
        for raw in ["20260230T100000", "20260308T023000", "20261101T013000"] {
            let result = try parse("BEGIN:VEVENT\nUID:bad-date\nDTSTART;TZID=America/New_York:" + raw + "\nSUMMARY:Review\nEND:VEVENT")
            #expect(result.events.first?.date == nil)
            #expect(!result.warnings.isEmpty)
        }
    }
    @Test func boundedWindowAndInvalidCalendarAreRejected() throws {
        #expect(throws: AcademicCalendarError.self) {
            try ICalendarReader.parse(text: "<html>Sign in</html>", sourceID: "s", calendarID: "c", timeZone: "UTC", window: range)
        }
        let tooLong = DateInterval(start: range.start, duration: 6 * 366 * 86400)
        #expect(throws: AcademicCalendarError.self) { try parse("", window: tooLong) }
    }
    @Test func publicSubscriptionNormalizesWebcalAndNeverSendsCredentials() async throws {
        let transport = AcademicCalendarTransport(replies: [HTTPReply(data: Data(), status: 302, headers: ["Location": "https://cdn.example.edu/cal.ics"]), HTTPReply(data: Data(calendar("BEGIN:VEVENT\nUID:public\nDTSTART;VALUE=DATE:20261109\nSUMMARY:Drop deadline\nEND:VEVENT").utf8))])
        let subscription = AcademicCalendarSubscription(id: "cal", name: "School calendar", url: "webcal://school.example/cal.ics")
        let result = try await AcademicCalendarClient(transport: transport).sync(subscription: subscription, window: range)
        let requests = await transport.requests
        #expect(requests.count == 2 && requests[0].url?.scheme == "https")
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
        #expect(result.source.academicCalendarID == "cal" && result.source.courseID.isEmpty)
        #expect(result.subscription.lastFetchedAt != nil && result.events.count == 1)
    }
    @Test func privateRedirectAndInsecureSubscriptionAreRejected() async throws {
        for url in ["http://school.example/cal.ics", "https://user:secret@school.example/cal.ics", "webcal://127.0.0.1/cal.ics"] {
            #expect(throws: ConnectorError.self) { try AcademicCalendarClient.normalizedURL(url) }
        }
        let transport = AcademicCalendarTransport(replies: [HTTPReply(data: Data(), status: 302, headers: ["Location": "https://localhost/cal.ics"])])
        await #expect(throws: ConnectorError.self) {
            try await AcademicCalendarClient(transport: transport).sync(subscription: AcademicCalendarPreset.cmu.subscription(), window: range)
        }
        #expect(await transport.requests.count == 1)
    }
}
private actor AcademicCalendarTransport: HTTPTransport {
    var replies: [HTTPReply]
    var requests: [URLRequest] = []
    init(replies: [HTTPReply]) { self.replies = replies }
    func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
        requests.append(request)
        guard !replies.isEmpty else { throw ConnectorError.invalidResponse }
        return replies.removeFirst()
    }
}
