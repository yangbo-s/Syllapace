import Foundation

public enum OfficialCourseScheduleError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedSemester, semesterMismatch, invalidSchedule, invalidCalendar
    case unsupportedCourse, courseNotFound, ambiguousSection, unsupportedCampus, miniSemester
    public var errorDescription: String? {
        switch self {
        case .unsupportedSemester: return "The official schedule requires an explicit semester and year."
        case .semesterMismatch: return "The official schedule is for a different semester."
        case .invalidSchedule: return "The university schedule could not be verified."
        case .invalidCalendar: return "The university teaching dates could not be verified."
        case .unsupportedCourse: return "The course number or section could not be verified."
        case .courseNotFound: return "No matching course and section was found in the official schedule."
        case .ambiguousSection: return "The official schedule has multiple sections; a section is needed."
        case .unsupportedCampus: return "This official teaching calendar only covers Pittsburgh."
        case .miniSemester: return "Mini-semester teaching dates need a separate calendar."
        }
    }
}

/// A row in the registrar's schedule. A section is not necessarily a recitation.
public struct OfficialCourseMeeting: Codable, Sendable, Hashable {
    public let courseNumber: String
    public let courseTitle: String
    public let section: String
    /// Calendar weekday numbers: Sunday = 1, Monday = 2, etc.
    public let weekdays: [Int]
    public let startMinute: Int?
    public let endMinute: Int?
    public let location: String
    public var isLecture: Bool { section.caseInsensitiveCompare("Lec") == .orderedSame }
    public var isScheduled: Bool { !weekdays.isEmpty && startMinute != nil && endMinute != nil }
    public var summary: String {
        let names = weekdays.map { Self.dayNames[$0 - 1] }.joined(separator: ", ")
        guard let startMinute, let endMinute else { return "Section \(section): time not published" }
        return "Section \(section): \(names) \(Self.clock(startMinute))–\(Self.clock(endMinute)), America/New_York; \(location)"
    }
    static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let dayCodes: [Character: Int] = ["U": 1, "M": 2, "T": 3, "W": 4, "R": 5, "F": 6, "S": 7]
    static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}

public struct OfficialTeachingDay: Codable, Sendable, Equatable {
    public let date: String
    public let weekday: Int
    public let classesMeet: Bool
    /// Some official holidays allow evening classes, even when the workbook says No.
    public var classesFromMinute: Int?
}

public struct OfficialCourseScheduleSnapshot: Codable, Sendable, Equatable {
    public let semester: String
    public let sourceURL: String
    public let calendarURL: String
    public let exceptionURL: String?
    public let fetchedAt: Date
    public let rows: [OfficialCourseMeeting]
    public let teachingDays: [OfficialTeachingDay]
    public var firstTeachingDate: String? { teachingDays.first?.date }
    public var lastTeachingDate: String? { teachingDays.last?.date }

    /// Match the exact section, plus an explicitly common Lec. Never choose among sections.
    public func meetings(for course: Course) throws -> [OfficialCourseMeeting] {
        if let name = course.term?.name, try ScheduleSemester(name).name != semester {
            throw OfficialCourseScheduleError.semesterMismatch
        }
        if let zone = course.timeZone, zone != "America/New_York" { throw OfficialCourseScheduleError.unsupportedCampus }
        guard let parts = ScheduleParsing.captures(#"^\s*([0-9]{2})-?([0-9]{3})(?:[\s-]+([A-Za-z]+[0-9]*))?\s*$"#, in: course.code).first else {
            throw OfficialCourseScheduleError.unsupportedCourse
        }
        let number = parts[0] + parts[1], requested = parts[2].uppercased()
        let candidates = rows.filter { $0.courseNumber == number }
        guard !candidates.isEmpty else { throw OfficialCourseScheduleError.courseNotFound }
        let sections = Set(candidates.filter { !$0.isLecture }.map { $0.section.uppercased() })
        let selected: String?
        if !requested.isEmpty {
            guard sections.contains(requested) || (requested == "LEC" && candidates.contains(where: \.isLecture)) else {
                throw OfficialCourseScheduleError.courseNotFound
            }
            selected = requested
        } else {
            guard sections.count <= 1 else { throw OfficialCourseScheduleError.ambiguousSection }
            selected = sections.first
        }
        if let selected, selected.range(of: #"[0-9]"#, options: .regularExpression) != nil {
            throw OfficialCourseScheduleError.miniSemester
        }
        let matched = candidates.filter { $0.isLecture || $0.section.uppercased() == selected }
        guard !matched.isEmpty else { throw OfficialCourseScheduleError.courseNotFound }
        guard matched.allSatisfy({ $0.location == "Pittsburgh, Pennsylvania" }) else { throw OfficialCourseScheduleError.unsupportedCampus }
        return matched
    }

    public func sourceDocument(course: Course) throws -> SourceDocument {
        let meetings = try meetings(for: course)
        let exclusions = teachingDays.filter { !$0.classesMeet }.map { day in
            day.date + (day.classesFromMinute.map { " (classes from \(OfficialCourseMeeting.clock($0)))" } ?? "")
        }.joined(separator: ", ")
        let text = (["Carnegie Mellon University — official Schedule of Classes", "Semester: \(semester)",
                     "Course: \(meetings[0].courseNumber) — \(meetings[0].courseTitle)", "Time zone: America/New_York",
                     "Teaching dates: \(firstTeachingDate ?? "") through \(lastTeachingDate ?? "")"] + meetings.map(\.summary) +
                    ["No daytime classes: \(exclusions)", "Schedule: \(sourceURL)", "Teaching calendar: \(calendarURL)"] +
                    (exceptionURL.map { ["Evening-class exception: \($0)"] } ?? [])).joined(separator: "\n")
        var links = [SourceLink(url: calendarURL, title: "Official teaching dates", kind: "file")]
        if let exceptionURL { links.append(SourceLink(url: exceptionURL, title: "Official evening-class exception", kind: "external")) }
        var source = SourceDocument(id: "official:cmu:soc:\(semester):\(course.id)", courseID: course.id,
            title: "\(course.code) · Official class schedule", text: text, url: sourceURL,
            hash: CanvasClient.hash(text), fetchedAt: fetchedAt, kind: .external, links: links)
        source.localOnly = true
        source.meetingScheduleComplete = meetings.allSatisfy(\.isScheduled)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        source.teachingStartsAt = firstTeachingDate.flatMap { ScheduleParsing.wallTime($0, minute: 0, calendar: calendar) }
        source.teachingEndsAt = lastTeachingDate.flatMap { ScheduleParsing.wallTime($0, minute: 0, calendar: calendar) }
            .flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
        return source
    }

    /// Expand actual teaching dates, not enrollment dates or the exam period.
    public func events(for course: Course) throws -> [AcademicEvent] {
        let meetings = try meetings(for: course), source = try sourceDocument(course: course)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var result: [AcademicEvent] = [], ids = Set<String>()
        for meeting in meetings where meeting.isScheduled {
            guard let start = meeting.startMinute, let end = meeting.endMinute else { continue }
            let seriesKey = "\(meeting.courseNumber)|\(meeting.section)|\(meeting.weekdays)|\(start)|\(end)"
            let seriesID = source.id + ":series:" + String(CanvasClient.hash(seriesKey).prefix(16))
            for day in teachingDays where meeting.weekdays.contains(day.weekday) {
                guard day.classesMeet || day.classesFromMinute.map({ start >= $0 }) == true,
                      let date = ScheduleParsing.wallTime(day.date, minute: start, calendar: calendar),
                      let endsAt = ScheduleParsing.wallTime(day.date, minute: end, calendar: calendar), date < endsAt else { continue }
                let id = seriesID + ":" + day.date
                guard ids.insert(id).inserted else { continue }
                var event = AcademicEvent(id: id, courseID: course.id, title: "\(course.code) \(meeting.isLecture ? "Lecture" : "Class")",
                    kind: .session, date: date, dateOnly: false, timeZone: calendar.timeZone.identifier, state: .approved,
                    sourceID: source.id, evidence: "\(semester); \(meeting.summary); teaching date \(day.date) verified against \(calendarURL)" +
                        (day.classesFromMinute != nil ? "; evening exception \(exceptionURL ?? "")" : ""),
                    sourceURL: sourceURL, endsAt: endsAt, location: meeting.location, sourceSeriesID: seriesID)
                event.subtype = meeting.isLecture ? .lecture : .classMeeting
                event.curationVersion = EventCuration.version
                result.append(event)
            }
        }
        return result.sorted { ($0.date ?? .distantPast, $0.id) < ($1.date ?? .distantPast, $1.id) }
    }
}

/// Public CMU registrar data only. This client never receives a Canvas credential.
public struct OfficialCourseScheduleClient: Sendable {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = BoundedHTTPTransport()) { self.transport = transport }
    public static func supports(canvasHost: String) -> Bool {
        guard let host = try? ConnectorURL.canvasOrigin(canvasHost).host?.lowercased() else { return false }
        return host == "cmu.edu" || host.hasSuffix(".cmu.edu")
    }

    public func fetch(semester: String) async throws -> OfficialCourseScheduleSnapshot {
        let term = try ScheduleSemester(semester)
        let sourceURL = "https://enr-apps.as.cmu.edu/assets/SOC/sched_layout_\(term.season.lowercased()).htm"
        let academicYear = term.season == "Fall" ? term.year : term.year - 1
        let calendarURL = String(format: "https://www.cmu.edu/hub/calendar/docs/%02d%02d-pgh-class-meeting-days.xlsx", academicYear % 100, (academicYear + 1) % 100)
        async let scheduleData = download(sourceURL, maxBytes: 4 * 1024 * 1024)
        async let calendarData = download(calendarURL, maxBytes: 2 * 1024 * 1024)
        let (htmlData, workbookData) = try await (scheduleData, calendarData)
        guard let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .isoLatin1) else { throw OfficialCourseScheduleError.invalidSchedule }
        let rows = try Self.parseSchedule(html, semester: term.name)
        let workbook = try await Self.readWorkbook(workbookData)
        var days = try Self.parseTeachingDays(workbook, semester: term.name)
        var exceptionURL: String?
        if term.season == "Fall" {
            let url = "https://www.cmu.edu/leadership/the-provost/provost-initiatives-democracy-day"
            // The workbook remains usable when this optional, more specific exception is unavailable.
            if let data = try? await download(url, maxBytes: 512 * 1024), let page = String(data: data, encoding: .utf8),
               let exception = Self.democracyDayException(page, semester: term.name),
               let index = days.firstIndex(where: { $0.date == exception.date && !$0.classesMeet }) {
                days[index].classesFromMinute = exception.minute; exceptionURL = url
            }
        }
        try Task.checkCancellation()
        return OfficialCourseScheduleSnapshot(semester: term.name, sourceURL: sourceURL, calendarURL: calendarURL,
            exceptionURL: exceptionURL, fetchedAt: .now, rows: rows, teachingDays: days)
    }

    private func download(_ address: String, maxBytes: Int) async throws -> Data {
        guard let url = URL(string: address) else { throw ConnectorError.invalidURL }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue("Syllapace/OfficialSchedule", forHTTPHeaderField: "User-Agent")
        let reply = try await transport.send(request, maxBytes: maxBytes)
        guard !(300..<400).contains(reply.status) else { throw ConnectorError.unsafeRedirect }
        guard (200..<300).contains(reply.status) else { throw ConnectorError.http(reply.status) }
        guard reply.data.count <= maxBytes else { throw ConnectorError.responseTooLarge }
        return reply.data
    }

    @concurrent private static func readWorkbook(_ data: Data) async throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("syllapace-official-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url, options: [.atomic])
        return try SpreadsheetReader.read(url: url)
    }

    static func parseSchedule(_ html: String, semester: String) throws -> [OfficialCourseMeeting] {
        guard html.utf8.count <= 4 * 1024 * 1024 else { throw ConnectorError.responseTooLarge }
        let expected = try ScheduleSemester(semester).name
        let heading = CanvasClient.plainText(String(html.prefix(4096)))
        guard let published = ScheduleParsing.captures(#"Semester:\s*((?:Fall|Spring|Summer)\s+[0-9]{4})\b"#, in: heading).first?.first else {
            throw OfficialCourseScheduleError.invalidSchedule
        }
        guard try ScheduleSemester(published).name == expected else { throw OfficialCourseScheduleError.semesterMismatch }
        var number = "", title = "", section = "", rows: [OfficialCourseMeeting] = [], seen = Set<OfficialCourseMeeting>()
        // The registrar HTML omits opening TR tags in some department-first rows.
        for row in ScheduleParsing.captures(#"(?is)(.*?)</tr\s*>"#, in: html) {
            let cells = ScheduleParsing.captures(#"(?is)<td\b[^>]*>(.*?)</td\s*>"#, in: row[0]).map { CanvasClient.plainText($0[0]).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard cells.count == 8 else { number = ""; title = ""; section = ""; continue }
            if !cells[0].isEmpty {
                guard cells[0].range(of: #"^[0-9]{5}$"#, options: .regularExpression) != nil else { number = ""; section = ""; continue }
                number = cells[0]; title = cells[1]; section = ""
            } else if !cells[1].isEmpty { title = cells[1] }
            guard !number.isEmpty, !title.isEmpty else { continue }
            if !cells[3].isEmpty { section = cells[3] }
            guard section.range(of: #"^[A-Za-z]+[0-9]*$"#, options: .regularExpression) != nil else { continue }
            let days = cells[4].uppercased(), weekdays = days.compactMap { OfficialCourseMeeting.dayCodes[$0] }
            let validDays = !days.isEmpty && weekdays.count == days.count && Set(weekdays).count == weekdays.count
            let start = ScheduleParsing.minutes(cells[5]), end = ScheduleParsing.minutes(cells[6])
            let validTime = start != nil && end != nil && start! < end!
            let meeting = OfficialCourseMeeting(courseNumber: number, courseTitle: title, section: section,
                weekdays: validDays && validTime ? weekdays.sorted() : [], startMinute: validDays && validTime ? start : nil,
                endMinute: validDays && validTime ? end : nil, location: cells[7])
            if seen.insert(meeting).inserted { rows.append(meeting) }
        }
        guard !rows.isEmpty else { throw OfficialCourseScheduleError.invalidSchedule }
        return rows
    }

    static func parseTeachingDays(_ workbookText: String, semester: String) throws -> [OfficialTeachingDay] {
        let term = try ScheduleSemester(semester)
        guard workbookText.hasPrefix("[Sheet: Class Meeting Days - Pittsburgh]") else { throw OfficialCourseScheduleError.invalidCalendar }
        var cells: [String: String] = [:]
        for line in workbookText.components(separatedBy: "\n") where line.hasPrefix("[Row ") {
            for entry in line.components(separatedBy: "\t").dropFirst() {
                guard let colon = entry.firstIndex(of: ":") else { continue }
                cells[String(entry[..<colon])] = entry[entry.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let matches = cells.filter { $0.key.hasSuffix("1") && $0.value == term.name }
        guard matches.count == 1, let address = matches.first?.key,
              address.count == 2, let scalar = address.unicodeScalars.first, scalar.value >= 65, scalar.value <= 87,
              let dateScalar = UnicodeScalar(scalar.value + 1), let meetScalar = UnicodeScalar(scalar.value + 2) else { throw OfficialCourseScheduleError.invalidCalendar }
        let weekdayColumn = String(scalar), dateColumn = String(dateScalar), meetColumn = String(meetScalar)
        guard cells[weekdayColumn + "2"] == "Teaching Day", cells[dateColumn + "2"] == "Date", cells[meetColumn + "2"] == "Classes Meet?" else {
            throw OfficialCourseScheduleError.invalidCalendar
        }
        var days: [OfficialTeachingDay] = [], calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var previous: Date?
        for row in 3...250 {
            guard let value = cells[dateColumn + String(row)], !value.isEmpty else { break }
            guard value.hasPrefix(String(term.year)), let date = ScheduleParsing.wallTime(value, minute: 0, calendar: calendar),
                  let dayText = cells[weekdayColumn + String(row)], dayText.count == 1, let code = dayText.first,
                  let weekday = OfficialCourseMeeting.dayCodes[code], let meets = cells[meetColumn + String(row)], ["Y", "No"].contains(meets),
                  previous == nil || calendar.date(byAdding: .day, value: 1, to: previous!) == date else { throw OfficialCourseScheduleError.invalidCalendar }
            days.append(OfficialTeachingDay(date: value, weekday: weekday, classesMeet: meets == "Y"))
            previous = date
        }
        guard (20...200).contains(days.count), days.first?.classesMeet == true, days.last?.classesMeet == true else { throw OfficialCourseScheduleError.invalidCalendar }
        return days
    }

    static func democracyDayException(_ html: String, semester: String) -> (date: String, minute: Int)? {
        guard let term = try? ScheduleSemester(semester), term.season == "Fall" else { return nil }
        let text = CanvasClient.plainText(html).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard let match = ScheduleParsing.captures(#"Democracy Day at Carnegie Mellon University on [A-Za-z]+, November ([0-9]{1,2}), ([0-9]{4})"#, in: text).first,
              Int(match[1]) == term.year, let day = Int(match[0]), (1...30).contains(day),
              text.contains("does not hold classes prior to 5 p.m. on the General Election Day") else { return nil }
        return (String(format: "%04d-11-%02d", term.year, day), 17 * 60)
    }
}

private struct ScheduleSemester {
    let season: String
    let year: Int
    var name: String { "\(season) \(year)" }
    init(_ value: String) throws {
        guard let parts = ScheduleParsing.captures(#"(?i)^\s*(Fall|Spring|Summer)\s+(20[0-9]{2})\s*$"#, in: value).first,
              let year = Int(parts[1]) else { throw OfficialCourseScheduleError.unsupportedSemester }
        self.season = parts[0].capitalized; self.year = year
    }
}

private enum ScheduleParsing {
    static func captures(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }
    static func minutes(_ text: String) -> Int? {
        guard let parts = captures(#"^([0-9]{1,2}):([0-9]{2})(AM|PM)$"#, in: text.uppercased()).first,
              let hour = Int(parts[0]), let minute = Int(parts[1]), (1...12).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour % 12 + (parts[2] == "PM" ? 12 : 0)) * 60 + minute
    }
    static func wallTime(_ date: String, minute: Int, calendar: Calendar) -> Date? {
        guard let parts = captures(#"^([0-9]{4})-([0-9]{2})-([0-9]{2})$"#, in: date).first,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), (0..<1440).contains(minute) else { return nil }
        let components = DateComponents(year: year, month: month, day: day, hour: minute / 60, minute: minute % 60)
        guard let result = calendar.date(from: components), calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result) == components else { return nil }
        return result
    }
}
