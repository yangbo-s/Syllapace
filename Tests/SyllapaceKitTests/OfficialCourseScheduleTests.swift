import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Official CMU class schedules") struct OfficialCourseScheduleTests {
    private let semester = "Fall 2026"
    private func course(_ code: String) -> Course {
        Course(id: "cmu:course:\(code)", name: code, code: code, term: AcademicTerm(id: "F26", name: semester), timeZone: "America/New_York")
    }
    private func row(_ number: String, _ section: String, _ days: String, _ start: String, _ end: String,
                     title: String = "", location: String = "Pittsburgh, Pennsylvania") -> String {
        "<TR>" + [number, title.isEmpty && !number.isEmpty ? "Course \(number)" : title, "12", section, days, start, end, location]
            .map { "<TD NOWRAP>\($0.isEmpty ? "&nbsp;" : $0)</TD>" }.joined() + "</TR>"
    }
    private func html(_ rows: String, semester: String = "Fall 2026") -> String { "<B>Semester: \(semester)</B><TABLE>\(rows)</TABLE>" }
    private func snapshot(_ rows: String, teachingDays: [OfficialTeachingDay]? = nil) throws -> OfficialCourseScheduleSnapshot {
        try OfficialCourseScheduleSnapshot(semester: semester, sourceURL: "https://enr-apps.as.cmu.edu/assets/SOC/sched_layout_fall.htm",
            calendarURL: "https://www.cmu.edu/hub/calendar/docs/2627-pgh-class-meeting-days.xlsx", exceptionURL: nil,
            fetchedAt: Date(timeIntervalSince1970: 0), rows: OfficialCourseScheduleClient.parseSchedule(html(rows), semester: semester),
            teachingDays: teachingDays ?? OfficialCourseScheduleClient.parseTeachingDays(calendarText(), semester: semester))
    }
    private func calendarText() -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = CanvasClient.instant("2026-10-26T00:00:00Z")!
        let excluded = Set(["2026-11-03", "2026-11-25", "2026-11-26", "2026-11-27"])
        let codes = ["U", "M", "T", "W", "R", "F", "S"]
        var text = "[Sheet: Class Meeting Days - Pittsburgh]\n[Row 1]\tA1: Fall 2026\tE1: Spring 2027\n[Row 2]\tA2: Teaching Day\tB2: Date\tC2: Classes Meet?\n"
        for offset in 0..<40 {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let day = String(ISO8601DateFormatter().string(from: date).prefix(10)), weekday = calendar.component(.weekday, from: date)
            let meets = weekday != 1 && weekday != 7 && !excluded.contains(day)
            let r = offset + 3
            text += "[Row \(r)]\tA\(r): \(codes[weekday - 1])\tB\(r): \(day)\tC\(r): \(meets ? "Y" : "No")\n"
        }
        return text
    }

    @Test func continuationRowsRetainExactCourseAndSectionWithoutGuessingMeetingRole() throws {
        let table = row("18647", "A", "TR", "09:30AM", "10:50AM") + row("", "", "F", "10:00AM", "10:50AM") +
            row("18794", "A", "T", "04:00PM", "04:50PM") + row("", "", "F", "01:00PM", "03:50PM") +
            row("19688", "A", "R", "06:00PM", "08:50PM")
        let result = try snapshot(table)
        let engineering = try result.meetings(for: course("18-647 A"))
        #expect(engineering.count == 2)
        #expect(engineering[0].weekdays == [3, 5])
        #expect(engineering[1].startMinute == 600)
        #expect(try result.meetings(for: course("18794-A")).map(\.startMinute) == [960, 780])
        #expect(try result.events(for: course("19688-A")).allSatisfy { $0.subtype == .classMeeting && $0.endsAt != nil })
        #expect(engineering.allSatisfy { !$0.isLecture })
    }

    @Test func onlyAnExplicitCommonLectureAndUniqueSectionAreSelected() throws {
        let table = row("18749", "Lec", "MW", "05:00PM", "05:50PM") + row("", "A", "M", "06:00PM", "06:50PM")
        let result = try snapshot(table)
        #expect(try result.meetings(for: course("18749")).count == 2)
        #expect(try result.meetings(for: course("18749-A")).count == 2)
        #expect(try result.events(for: course("18749")).contains { $0.subtype == .lecture })
        let multiple = try snapshot(table + row("", "B", "TBA", "", ""))
        #expect(throws: OfficialCourseScheduleError.ambiguousSection) { try multiple.meetings(for: course("18749")) }
        #expect(try multiple.meetings(for: course("18749-A")).count == 2)
        #expect(throws: OfficialCourseScheduleError.courseNotFound) { try multiple.meetings(for: course("18749-C")) }
    }

    @Test func wrongSemesterCampusAndMiniSectionsNeverProduceGuessedClasses() throws {
        let table = row("18647", "A", "TR", "09:30AM", "10:50AM")
        #expect(throws: OfficialCourseScheduleError.semesterMismatch) {
            try OfficialCourseScheduleClient.parseSchedule(html(table, semester: "Fall 2025"), semester: semester)
        }
        #expect(throws: OfficialCourseScheduleError.unsupportedSemester) {
            try OfficialCourseScheduleClient.parseSchedule(html(table), semester: "Fall")
        }
        let mini = try snapshot(row("18647", "A1", "TR", "09:30AM", "10:50AM"))
        #expect(throws: OfficialCourseScheduleError.miniSemester) { try mini.events(for: course("18647-A1")) }
        let doha = try snapshot(row("18647", "A", "TR", "09:30AM", "10:50AM", location: "Doha, Qatar"))
        #expect(throws: OfficialCourseScheduleError.unsupportedCampus) { try doha.events(for: course("18647-A")) }
        let result = try snapshot(table)
        var wrongTerm = course("18647-A"); wrongTerm.term?.name = "Fall 2025"
        #expect(throws: OfficialCourseScheduleError.semesterMismatch) { try result.events(for: wrongTerm) }
        #expect(throws: OfficialCourseScheduleError.unsupportedCourse) { try result.events(for: course("18647-A or B")) }
        #expect(!OfficialCourseScheduleClient.supports(canvasHost: "cmu.edu.evil.example"))
        #expect(OfficialCourseScheduleClient.supports(canvasHost: "https://canvas.cmu.edu"))
    }

    @Test func departmentBoundariesAndUnknownTimesCannotInheritOldSchedules() throws {
        let first = row("18647", "A", "TR", "09:30AM", "10:50AM")
        let boundary = "<TR><TD>New Department</TD></TR>"
        let malformed = row("", "", "F", "10:00AM", "10:50AM")
        let table = first + boundary + malformed + row("19688", "A", "TBA", "", "")
        let result = try snapshot(table)
        #expect(result.rows.count == 2)
        #expect(try result.events(for: course("19688-A")).isEmpty)
        let omittedOpenTag = String(first.dropFirst(4))
        #expect(try snapshot(omittedOpenTag).rows.count == 1)
    }

    @Test func actualTeachingDatesExcludeBreaksAndExamPeriodAndKeepLocalTimeAcrossDST() throws {
        let result = try snapshot(row("18647", "A", "TR", "09:30AM", "10:50AM") + row("", "", "F", "10:00AM", "10:50AM"))
        let events = try result.events(for: course("18647-A"))
        #expect(events.contains { $0.date == CanvasClient.instant("2026-10-27T13:30:00Z") })
        #expect(events.contains { $0.date == CanvasClient.instant("2026-11-05T14:30:00Z") })
        #expect(!events.contains { $0.date == CanvasClient.instant("2026-11-03T14:30:00Z") })
        #expect(!events.contains { $0.date == CanvasClient.instant("2026-11-26T14:30:00Z") })
        #expect(events.allSatisfy { $0.date! < CanvasClient.instant("2026-12-05T00:00:00Z")! })
        #expect(events.allSatisfy { $0.state == .approved && $0.sourceURL == result.sourceURL })
        #expect(events == (try result.events(for: course("18647-A"))))
        #expect(Set(events.map(\.id)).count == events.count)
        #expect(Set(events.compactMap(\.sourceSeriesID)).count == 2)
    }

    @Test func democracyDayEveningExceptionRequiresMatchingOfficialYearAndStatement() throws {
        let page = "<h1>Democracy Day at Carnegie Mellon University on Tuesday, November 3, 2026</h1><p>The university does not hold classes prior to 5 p.m. on the General Election Day (November 3).</p>"
        let exception = try #require(OfficialCourseScheduleClient.democracyDayException(page, semester: semester))
        #expect(exception.date == "2026-11-03" && exception.minute == 1020)
        #expect(OfficialCourseScheduleClient.democracyDayException(page, semester: "Fall 2027") == nil)
        #expect(OfficialCourseScheduleClient.democracyDayException(page.replacingOccurrences(of: "5 p.m.", with: "6 p.m."), semester: semester) == nil)
        var days = try OfficialCourseScheduleClient.parseTeachingDays(calendarText(), semester: semester)
        days[try #require(days.firstIndex { $0.date == exception.date })].classesFromMinute = exception.minute
        let result = try snapshot(row("18647", "A", "T", "04:00PM", "04:50PM") + row("", "", "T", "05:00PM", "05:50PM"), teachingDays: days)
        let events = try result.events(for: course("18647-A"))
        #expect(events.contains { $0.date == CanvasClient.instant("2026-11-03T22:00:00Z") })
        #expect(!events.contains { $0.date == CanvasClient.instant("2026-11-03T21:00:00Z") })
    }

    @Test func calendarRejectsMissingDatesDifferentTermsAndUncertainCells() throws {
        let text = calendarText()
        #expect(throws: OfficialCourseScheduleError.invalidCalendar) { try OfficialCourseScheduleClient.parseTeachingDays(text, semester: "Fall 2027") }
        #expect(throws: OfficialCourseScheduleError.invalidCalendar) {
            try OfficialCourseScheduleClient.parseTeachingDays(text.replacingOccurrences(of: "B4: 2026-10-27", with: "B4: 2026-10-29"), semester: semester)
        }
        #expect(throws: OfficialCourseScheduleError.invalidCalendar) {
            try OfficialCourseScheduleClient.parseTeachingDays(text.replacingOccurrences(of: "C4: Y", with: "C4: Maybe"), semester: semester)
        }
        let days = try OfficialCourseScheduleClient.parseTeachingDays(text, semester: semester)
        #expect(days.first?.date == "2026-10-26")
        #expect(days.last?.date == "2026-12-04")
    }

    @Test func officialSourceHasStableIdentityAndLocalOnlyProvenance() throws {
        let result = try snapshot(row("18647", "A", "TR", "09:30AM", "10:50AM"))
        let source = try result.sourceDocument(course: course("18647-A"))
        #expect(source.localOnly == true && source.kind == .external)
        #expect(source.text.contains("Tuesday, Thursday 09:30–10:50"))
        #expect(source.links?.first?.url == result.calendarURL)
        #expect(source.hash == (try result.sourceDocument(course: course("18647-A"))).hash)
        #expect(try JSONDecoder().decode(OfficialCourseScheduleSnapshot.self, from: JSONEncoder().encode(result)) == result)
    }

    @Test func publicRequestsAreBoundedUnauthenticatedAndRejectSemesterRollover() async throws {
        let transport = OfficialScheduleTransport(html: html(row("18647", "A", "TR", "09:30AM", "10:50AM"), semester: "Fall 2027"))
        await #expect(throws: OfficialCourseScheduleError.semesterMismatch) {
            try await OfficialCourseScheduleClient(transport: transport).fetch(semester: semester)
        }
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.0.value(forHTTPHeaderField: "Authorization") == nil && $0.1 <= 4 * 1024 * 1024 })
        #expect(requests.allSatisfy { $0.0.url?.scheme == "https" })
    }

    /// Explicit live contract check; not part of offline unit testing or CI.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SYLLAPACE_TEST_PUBLIC_SCHEDULE"] == "1"))
    func publishedFall2026ScheduleHasAllFourRequestedCourses() async throws {
        let result = try await OfficialCourseScheduleClient().fetch(semester: semester)
        #expect(result.firstTeachingDate == "2026-08-24")
        #expect(result.lastTeachingDate == "2026-12-04")
        #expect(result.exceptionURL != nil)
        let expectedCounts = ["18647-A": 39, "18794-A": 26, "19688-A": 13, "18749": 39]
        let holidays: Set<String> = ["2026-09-07", "2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16",
                                     "2026-11-03", "2026-11-25", "2026-11-26", "2026-11-27"]
        let dayFormatter = DateFormatter(); dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(identifier: "America/New_York"); dayFormatter.dateFormat = "yyyy-MM-dd"
        var total = 0
        for (code, count) in expectedCounts {
            let events = try result.events(for: course(code))
            total += events.count
            #expect(events.count == count)
            #expect(events.allSatisfy { $0.endsAt != nil && $0.date! >= CanvasClient.instant("2026-08-24T04:00:00Z")!
                && $0.date! < CanvasClient.instant("2026-12-05T05:00:00Z")! })
            #expect(Set(events.map { dayFormatter.string(from: $0.date!) }).isDisjoint(with: holidays))
            #expect(Set(events.map(\.id)).count == count)
        }
        #expect(total == 117)
        #expect(try result.meetings(for: course("18647-A")).map(\.startMinute) == [570, 600])
        #expect(try result.meetings(for: course("18647-A")).map(\.endMinute) == [650, 650])
        #expect(try result.meetings(for: course("18647-A")).map(\.weekdays) == [[3, 5], [6]])
        #expect(try result.meetings(for: course("18794-A")).map(\.startMinute) == [960, 780])
        #expect(try result.meetings(for: course("18794-A")).map(\.endMinute) == [1010, 950])
        #expect(try result.meetings(for: course("18794-A")).map(\.weekdays) == [[3], [6]])
        #expect(try result.meetings(for: course("19688-A")).map(\.startMinute) == [1080])
        #expect(try result.meetings(for: course("19688-A")).map(\.endMinute) == [1250])
        #expect(try result.meetings(for: course("19688-A")).map(\.weekdays) == [[5]])
        #expect(try result.meetings(for: course("18749")).map(\.startMinute) == [1020, 1080])
        #expect(try result.meetings(for: course("18749")).map(\.endMinute) == [1070, 1130])
        #expect(try result.meetings(for: course("18749")).map(\.weekdays) == [[2, 4], [2]])
    }
}

private actor OfficialScheduleTransport: HTTPTransport {
    let html: String
    var requests: [(URLRequest, Int)] = []
    init(html: String) { self.html = html }
    func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
        requests.append((request, maxBytes))
        return HTTPReply(data: request.url?.pathExtension == "xlsx" ? Data() : Data(html.utf8))
    }
}
