import Foundation

/// A bounded RFC 5545 reader for school calendar subscriptions. Recurrences are
/// expanded in their source time zone, then intersected with the requested window.
/// Unsupported rule parts are surfaced for review instead of approximated.
public enum ICalendarReader {
    private static let maxRecords = 5_000
    private static let maxOccurrences = 20_000
    private static let maxScannedDays = 200_000

    public static func parse(text: String, sourceID: String, calendarID: String, timeZone: String,
                             window: DateInterval, sourceURL: String? = nil) throws -> ICalendarResult {
        guard TimeZone(identifier: timeZone) != nil else { throw AcademicCalendarError.invalidTimeZone }
        guard window.duration > 0, window.duration <= 5 * 366 * 86_400 else { throw AcademicCalendarError.invalidWindow }
        guard text.utf8.count <= DocumentReader.maxTextBytes else { throw ConnectorError.responseTooLarge }
        let records = try components(text)
        var events: [AcademicEvent] = [], warnings: [String] = [], dates: [Date] = []
        var reviewSeriesIDs = Set<String>(), reviewEventIDs = Set<String>()
        var payloadBytes = 0
        func appendEvent(_ item: AcademicEvent) throws {
            payloadBytes += item.evidence.utf8.count + item.title.utf8.count + (item.location?.utf8.count ?? 0)
            guard payloadBytes <= DocumentReader.maxBytes, events.count < maxOccurrences else { throw ConnectorError.responseTooLarge }
            events.append(item)
        }
        var groups: [String: [Record]] = [:]
        for record in records {
            guard let uid = record.first("UID")?.value.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty else {
                warnings.append(warning(record.title, "The calendar item has no stable UID and was not imported.")); continue
            }
            groups[uid, default: []].append(record)
            if let property = record.first("DTSTART"), let date = try? readDate(property, fallbackZone: timeZone) { dates.append(date.date) }
        }
        var scannedDays = 0
        for uid in groups.keys.sorted() {
            try Task.checkCancellation()
            let items = groups[uid]!
            let master = items.filter { $0.first("RECURRENCE-ID") == nil }.max(by: { $0.revision < $1.revision })
            let zone = master?.first("DTSTART")?.parameters["TZID"] ?? timeZone
            var overrides: [String: Record] = [:]
            var invalidOverride = false
            for record in items where record.first("RECURRENCE-ID") != nil {
                do {
                    let property = record.first("RECURRENCE-ID")!
                    if property.parameters["RANGE"] != nil { throw ParseIssue.unsupportedRange }
                    let recurrence = try readDate(property, fallbackZone: zone)
                    if let existing = overrides[recurrence.key], existing.revision > record.revision { continue }
                    overrides[recurrence.key] = record
                } catch {
                    warnings.append(warning(record.title, reason(error)))
                    invalidOverride = true
                }
            }
            if invalidOverride {
                reviewSeriesIDs.insert(seriesID(calendarID: calendarID, uid: uid))
                if let master { try appendEvent(event(master, uid: uid, occurrence: nil, start: nil, end: nil, sourceID: sourceID, calendarID: calendarID, sourceURL: sourceURL)) }
                continue
            }
            if let master {
                if master.cancelled {
                    reviewSeriesIDs.insert(seriesID(calendarID: calendarID, uid: uid))
                    warnings.append(warning(master.title, "The source cancelled this item. Previously saved events have been kept for review."))
                    continue
                }
                do {
                    let start = try readStart(master, fallbackZone: timeZone)
                    let duration = try readDuration(master, start: start)
                    var occurrences: [String: CalendarDate] = [start.key: start]
                    if master.first("EXRULE") != nil { throw ParseIssue.unsupportedRule }
                    if master.values("RRULE").count > 1 { throw ParseIssue.unsupportedRule }
                    if let ruleProperty = master.first("RRULE") {
                        let rule = try RecurrenceRule(ruleProperty.value, start: start)
                        let expanded = try expand(rule: rule, start: start, duration: duration, window: window, scannedDays: &scannedDays)
                        for date in expanded { occurrences[date.key] = date }
                    }
                    var dateValueCount = 0
                    for property in master.values("RDATE") {
                        if property.parameters["VALUE"]?.uppercased() == "PERIOD" { throw ParseIssue.unsupportedRule }
                        let values = property.value.split(separator: ",")
                        dateValueCount += values.count
                        guard dateValueCount <= maxOccurrences else { throw ParseIssue.expansionLimit }
                        for (offset, value) in values.enumerated() {
                            if offset % 128 == 0 { try Task.checkCancellation() }
                            let date = try readDate(Property(name: property.name, parameters: property.parameters, value: String(value)), fallbackZone: start.zone)
                            guard date.dateOnly == start.dateOnly else { throw ParseIssue.invalidDate }
                            occurrences[date.key] = date
                        }
                    }
                    var excluded = Set<String>()
                    for property in master.values("EXDATE") {
                        let values = property.value.split(separator: ",")
                        dateValueCount += values.count
                        guard dateValueCount <= maxOccurrences else { throw ParseIssue.expansionLimit }
                        for (offset, value) in values.enumerated() {
                            if offset % 128 == 0 { try Task.checkCancellation() }
                            let date = try readDate(Property(name: property.name, parameters: property.parameters, value: String(value)), fallbackZone: start.zone)
                            guard date.dateOnly == start.dateOnly else { throw ParseIssue.invalidDate }
                            excluded.insert(date.key)
                        }
                    }
                    let recurring = master.first("RRULE") != nil || master.first("RDATE") != nil || !overrides.isEmpty
                    for key in excluded where recurring || key == start.key {
                        reviewEventIDs.insert(eventID(calendarID: calendarID, uid: uid, occurrence: recurring ? key : nil))
                    }
                    for date in occurrences.values.sorted(by: { $0.date < $1.date }) {
                        // An explicit override is processed separately, including a
                        // moved instance whose new date falls outside the old window.
                        guard overrides[date.key] == nil, !excluded.contains(date.key) else { continue }
                        let end = duration.end(from: date)
                        guard overlaps(start: date.date, end: end, window: window) else { continue }
                        try appendEvent(event(master, uid: uid, occurrence: recurring ? date.key : nil, start: date, end: end,
                                            sourceID: sourceID, calendarID: calendarID, sourceURL: sourceURL))
                    }
                } catch is CancellationError { throw CancellationError()
                } catch ConnectorError.responseTooLarge { throw ConnectorError.responseTooLarge
                } catch {
                    reviewSeriesIDs.insert(seriesID(calendarID: calendarID, uid: uid))
                    warnings.append(warning(master.title, reason(error)))
                    var pending = event(master, uid: uid, occurrence: nil, start: nil, end: nil,
                                        sourceID: sourceID, calendarID: calendarID, sourceURL: sourceURL)
                    pending.state = .pending
                    try appendEvent(pending)
                }
            }
            for key in overrides.keys.sorted() {
                var override = overrides[key]!
                if let master {
                    for name in ["SUMMARY", "DESCRIPTION", "LOCATION", "URL"] where override.first(name) == nil {
                        if let inherited = master.first(name) { override.properties.append(inherited) }
                    }
                }
                if override.cancelled {
                    reviewEventIDs.insert(eventID(calendarID: calendarID, uid: uid, occurrence: key))
                    warnings.append(warning(override.title, "The source cancelled this item. Previously saved events have been kept for review."))
                    continue
                }
                do {
                    let start = try readStart(override, fallbackZone: zone)
                    let duration: EventDuration
                    if override.first("DTEND") == nil && override.first("DURATION") == nil, let master {
                        duration = try readDuration(master, start: readStart(master, fallbackZone: timeZone))
                    } else { duration = try readDuration(override, start: start) }
                    let end = duration.end(from: start)
                    guard overlaps(start: start.date, end: end, window: window) else { continue }
                    try appendEvent(event(override, uid: uid, occurrence: key, start: start, end: end,
                                        sourceID: sourceID, calendarID: calendarID, sourceURL: sourceURL))
                } catch is CancellationError { throw CancellationError()
                } catch ConnectorError.responseTooLarge { throw ConnectorError.responseTooLarge
                } catch {
                    reviewEventIDs.insert(eventID(calendarID: calendarID, uid: uid, occurrence: key))
                    warnings.append(warning(override.title, reason(error)))
                    try appendEvent(event(override, uid: uid, occurrence: key, start: nil, end: nil,
                                        sourceID: sourceID, calendarID: calendarID, sourceURL: sourceURL))
                }
            }
            guard events.count <= maxOccurrences else { throw ConnectorError.responseTooLarge }
        }
        return ICalendarResult(events: events.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) },
                               warnings: Array(Set(warnings)).sorted(), sourceCount: records.count,
                               firstDate: dates.min(), lastDate: dates.max(),
                               reviewSeriesIDs: reviewSeriesIDs, reviewEventIDs: reviewEventIDs)
    }

    private static func overlaps(start: Date, end: Date?, window: DateInterval) -> Bool {
        start < window.end && (start >= window.start || (end ?? start) > window.start)
    }
    private static func event(_ record: Record, uid: String, occurrence: String?, start: CalendarDate?, end: Date?,
                              sourceID: String, calendarID: String, sourceURL: String?) -> AcademicEvent {
        let title = record.title
        let lower = title.lowercased()
        // These labels are reminders only. They never cancel class meetings.
        let holiday = lower.contains("no classes") || lower.contains("university closed") || lower.contains("holiday") || lower.contains("break")
        var evidence = title
        if let description = record.first("DESCRIPTION") { evidence += "\n" + unescape(description.value) }
        if let start = record.first("DTSTART") { evidence += "\nDTSTART: " + start.value }
        if let end = record.first("DTEND") { evidence += "\nDTEND: " + end.value }
        if let rule = record.first("RRULE") { evidence += "\nRRULE: " + rule.value }
        let itemURL = record.first("URL").map { unescape($0.value) }
        let safeURL = itemURL.flatMap(URL.init(string:)).flatMap { ConnectorURL.safeDownload($0) ? $0.absoluteString : nil }
        var result = AcademicEvent(id: eventID(calendarID: calendarID, uid: uid, occurrence: occurrence), courseID: "", title: title,
                                   kind: holiday ? .holiday : .academic, date: start?.date, dateOnly: start?.dateOnly ?? true,
                                   timeZone: start?.zone ?? "UTC", state: start == nil ? .pending : .approved,
                                   sourceID: sourceID, evidence: evidence, sourceURL: safeURL ?? sourceURL,
                                   endsAt: end, location: record.first("LOCATION").map { unescape($0.value) })
        result.academicCalendarID = calendarID
        result.sourceSeriesID = seriesID(calendarID: calendarID, uid: uid)
        return result
    }
    private static func eventID(calendarID: String, uid: String, occurrence: String?) -> String {
        "ical:" + CanvasClient.hash(calendarID + "|" + uid + (occurrence.map { "|" + $0 } ?? ""))
    }
    private static func seriesID(calendarID: String, uid: String) -> String {
        "ical-series:" + CanvasClient.hash(calendarID + "|" + uid)
    }
    private static func warning(_ title: String, _ message: String) -> String {
        L10n.format("Calendar item “%@”: %@", String(title.prefix(160)), L10n.string(message))
    }
    private static func reason(_ error: Error) -> String {
        (error as? ParseIssue)?.message ?? "The calendar item could not be read and needs review."
    }
}

private extension ICalendarReader {
    struct Property {
        var name: String
        var parameters: [String: String]
        var value: String
    }
    struct Record {
        var properties: [Property] = []
        func first(_ name: String) -> Property? { properties.first { $0.name == name } }
        func values(_ name: String) -> [Property] { properties.filter { $0.name == name } }
        var title: String { first("SUMMARY").map { unescape($0.value) } ?? L10n.string("Untitled calendar item") }
        var cancelled: Bool { first("STATUS")?.value.uppercased() == "CANCELLED" }
        var revision: String {
            String(format: "%012lld", min(2_147_483_647, max(0, Int64(first("SEQUENCE")?.value ?? "0") ?? 0))) + ":" + (first("LAST-MODIFIED")?.value ?? first("DTSTAMP")?.value ?? "")
        }
    }
    enum ParseIssue: Error {
        case invalidDate, invalidZone, invalidEnd, unsupportedRule, unsupportedRange, expansionLimit
        var message: String {
            switch self {
            case .invalidDate: "A date is missing, invalid or ambiguous; review the original calendar."
            case .invalidZone: "This calendar uses an unsupported time zone; review the original calendar."
            case .invalidEnd: "The calendar end or duration is invalid; review the original calendar."
            case .unsupportedRule: "This recurrence rule is not supported; its dates were not guessed."
            case .unsupportedRange: "This recurring change affects later instances and needs manual review."
            case .expansionLimit: "The recurrence exceeds the import limit; narrow the range or review the source."
            }
        }
    }
    static func components(_ input: String) throws -> [Record] {
        let raw = input.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.first == " " || line.first == "\t", !lines.isEmpty { lines[lines.count - 1] += line.dropFirst() }
            else if !line.isEmpty { lines.append(String(line)) }
        }
        guard lines.first?.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}")).uppercased() == "BEGIN:VCALENDAR",
              lines.last?.uppercased() == "END:VCALENDAR" else { throw AcademicCalendarError.notCalendar }
        var stack: [String] = [], records: [Record] = [], current: Record?
        for line in lines {
            guard let colon = separator(in: line, character: ":") else { throw AcademicCalendarError.notCalendar }
            let prefix = String(line[..<colon]), value = String(line[line.index(after: colon)...])
            let fields = splitQuoted(prefix, separator: ";")
            let name = fields[0].uppercased()
            if name == "BEGIN" {
                let component = value.uppercased()
                if component == "VEVENT", stack == ["VCALENDAR"] { current = Record() }
                stack.append(component)
            } else if name == "END" {
                guard stack.last == value.uppercased() else { throw AcademicCalendarError.notCalendar }
                if stack == ["VCALENDAR", "VEVENT"], let item = current {
                    records.append(item); current = nil
                    guard records.count <= maxRecords else { throw ConnectorError.responseTooLarge }
                }
                stack.removeLast()
            } else if stack == ["VCALENDAR", "VEVENT"] {
                var parameters: [String: String] = [:]
                for field in fields.dropFirst() {
                    guard let equals = field.firstIndex(of: "=") else { continue }
                    parameters[String(field[..<equals]).uppercased()] = String(field[field.index(after: equals)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                current?.properties.append(Property(name: name, parameters: parameters, value: value))
            }
        }
        guard stack.isEmpty else { throw AcademicCalendarError.notCalendar }
        return records
    }
    static func separator(in text: String, character: Character) -> String.Index? {
        var quoted = false
        for index in text.indices {
            if text[index] == "\"" { quoted.toggle() }
            if text[index] == character, !quoted { return index }
        }
        return nil
    }
    static func splitQuoted(_ text: String, separator character: Character) -> [String] {
        var parts: [String] = [], start = text.startIndex, quoted = false
        for index in text.indices {
            if text[index] == "\"" { quoted.toggle() }
            if text[index] == character, !quoted { parts.append(String(text[start..<index])); start = text.index(after: index) }
        }
        parts.append(String(text[start...])); return parts
    }
    static func unescape(_ text: String) -> String {
        var result = "", escaped = false
        for character in text {
            if escaped { result.append(character == "n" || character == "N" ? "\n" : character); escaped = false }
            else if character == "\\" { escaped = true }
            else { result.append(character) }
        }
        if escaped { result.append("\\") }
        return result
    }
    struct CalendarDate {
        var date: Date
        var dateOnly: Bool
        var zone: String
        var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: zone)!; return value }
        var key: String {
            if dateOnly {
                let c = calendar.dateComponents([.year, .month, .day], from: date)
                return String(format: "D:%04d%02d%02d", c.year!, c.month!, c.day!)
            }
            return "T:\(Int(date.timeIntervalSince1970))"
        }
    }
    static func readStart(_ record: Record, fallbackZone: String) throws -> CalendarDate {
        guard let start = record.first("DTSTART") else { throw ParseIssue.invalidDate }
        return try readDate(start, fallbackZone: fallbackZone)
    }
    static func readDate(_ property: Property, fallbackZone: String) throws -> CalendarDate {
        let raw = property.value
        if let kind = property.parameters["VALUE"], !["DATE", "DATE-TIME"].contains(kind.uppercased()) { throw ParseIssue.invalidDate }
        let dateOnly = property.parameters["VALUE"]?.uppercased() == "DATE" || raw.count == 8
        guard raw.range(of: dateOnly ? "^[0-9]{8}$" : "^[0-9]{8}T[0-9]{6}Z?$", options: .regularExpression) != nil else { throw ParseIssue.invalidDate }
        if dateOnly, property.parameters["TZID"] != nil { throw ParseIssue.invalidDate }
        let zone = raw.hasSuffix("Z") ? "UTC" : property.parameters["TZID"] ?? fallbackZone
        guard let timeZone = TimeZone(identifier: zone) else { throw ParseIssue.invalidZone }
        let digits = raw.filter(\.isNumber)
        let values = Array(digits)
        func integer(_ a: Int, _ b: Int) -> Int { Int(String(values[a..<b]))! }
        let year = integer(0, 4), month = integer(4, 6), day = integer(6, 8)
        let hour = dateOnly ? 0 : integer(8, 10), minute = dateOnly ? 0 : integer(10, 12), second = dateOnly ? 0 : integer(12, 14)
        guard (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 60 else { throw ParseIssue.invalidDate }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let c = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: c), calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == c else { throw ParseIssue.invalidDate }
        // Foundation resolves a repeated wall-clock time arbitrarily. Preserve
        // uncertainty unless the source supplied UTC (or an unambiguous instant).
        if !dateOnly, !raw.hasSuffix("Z"), let later = calendar.nextDate(after: date.addingTimeInterval(-1), matching: DateComponents(hour: hour, minute: minute, second: second), matchingPolicy: .strict, repeatedTimePolicy: .last, direction: .forward),
           later != date, calendar.isDate(later, inSameDayAs: date) { throw ParseIssue.invalidDate }
        return CalendarDate(date: date, dateOnly: dateOnly, zone: zone)
    }
    struct EventDuration {
        var days = 0
        var seconds: TimeInterval = 0
        var explicit = false
        func end(from start: CalendarDate) -> Date? {
            guard explicit else { return nil }
            return start.calendar.date(byAdding: .day, value: days, to: start.date)?.addingTimeInterval(seconds)
        }
    }
    static func readDuration(_ record: Record, start: CalendarDate) throws -> EventDuration {
        if let property = record.first("DTEND") {
            guard record.first("DURATION") == nil else { throw ParseIssue.invalidEnd }
            let end = try readDate(property, fallbackZone: start.zone)
            guard end.dateOnly == start.dateOnly, end.date > start.date, end.date.timeIntervalSince(start.date) <= 366 * 86_400 else { throw ParseIssue.invalidEnd }
            if start.dateOnly { return EventDuration(days: start.calendar.dateComponents([.day], from: start.date, to: end.date).day!, explicit: true) }
            return EventDuration(seconds: end.date.timeIntervalSince(start.date), explicit: true)
        }
        if let raw = record.first("DURATION")?.value {
            guard let regex = try? NSRegularExpression(pattern: "^P(?:(\\d+)W|(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?)?)$"),
                  let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { throw ParseIssue.invalidEnd }
            func number(_ index: Int) throws -> Int {
                guard let range = Range(match.range(at: index), in: raw) else { return 0 }
                guard let value = Int(raw[range]) else { throw ParseIssue.invalidEnd }
                return value
            }
            let weeks = try number(1), days = try number(2), hours = try number(3), minutes = try number(4), seconds = try number(5)
            guard weeks <= 52, days <= 366, hours <= 8784, minutes <= 527040, seconds <= 31622400 else { throw ParseIssue.invalidEnd }
            let duration = EventDuration(days: weeks * 7 + days, seconds: Double(hours * 3600 + minutes * 60 + seconds), explicit: true)
            guard duration.days > 0 || duration.seconds > 0, !start.dateOnly || duration.seconds == 0,
                  let end = duration.end(from: start), end.timeIntervalSince(start.date) <= 366 * 86_400 else { throw ParseIssue.invalidEnd }
            return duration
        }
        return EventDuration(days: start.dateOnly ? 1 : 0, explicit: start.dateOnly)
    }
}

private extension ICalendarReader {
    struct WeekdayRule {
        var ordinal: Int?
        var weekday: Int
    }
    struct RecurrenceRule {
        var frequency: String
        var interval: Int
        var count: Int?
        var until: Date?
        var months: [Int]
        var monthDays: [Int]
        var weekdays: [WeekdayRule]
        var weekStart: Int

        init(_ value: String, start: CalendarDate) throws {
            var fields: [String: String] = [:]
            for part in value.uppercased().split(separator: ";", omittingEmptySubsequences: false) {
                let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pair.count == 2, !pair[1].isEmpty, fields[String(pair[0])] == nil else { throw ParseIssue.unsupportedRule }
                fields[String(pair[0])] = String(pair[1])
            }
            let supported: Set<String> = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "BYMONTH", "BYMONTHDAY", "WKST"]
            guard Set(fields.keys).isSubset(of: supported), let frequency = fields["FREQ"],
                  ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].contains(frequency), fields["COUNT"] == nil || fields["UNTIL"] == nil else { throw ParseIssue.unsupportedRule }
            self.frequency = frequency
            func positive(_ key: String, maximum: Int) throws -> Int? {
                guard let raw = fields[key] else { return nil }
                guard let value = Int(raw), (1...maximum).contains(value) else { throw ParseIssue.unsupportedRule }
                return value
            }
            interval = try positive("INTERVAL", maximum: 3660) ?? 1
            count = try positive("COUNT", maximum: 100_000)
            func numbers(_ key: String, allowed: ClosedRange<Int>, excludeZero: Bool = false) throws -> [Int] {
                guard let raw = fields[key] else { return [] }
                let values = raw.split(separator: ",", omittingEmptySubsequences: false)
                let result = values.compactMap { Int($0) }
                guard values.count == result.count, result.allSatisfy({ allowed.contains($0) && (!excludeZero || $0 != 0) }) else { throw ParseIssue.unsupportedRule }
                return Array(Set(result))
            }
            months = try numbers("BYMONTH", allowed: 1...12)
            monthDays = try numbers("BYMONTHDAY", allowed: -31...31, excludeZero: true)
            if frequency == "WEEKLY", !monthDays.isEmpty { throw ParseIssue.unsupportedRule }
            let weekdayNames = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
            guard let weekStart = weekdayNames[fields["WKST"] ?? "MO"] else { throw ParseIssue.unsupportedRule }
            self.weekStart = weekStart
            weekdays = []
            if let raw = fields["BYDAY"] {
                for day in raw.split(separator: ",", omittingEmptySubsequences: false) {
                    guard day.count >= 2, let weekday = weekdayNames[String(day.suffix(2))] else { throw ParseIssue.unsupportedRule }
                    let prefix = day.dropLast(2)
                    var ordinal: Int?
                    if !prefix.isEmpty {
                        guard ["MONTHLY", "YEARLY"].contains(frequency), let parsed = Int(prefix), parsed != 0, (-53...53).contains(parsed) else { throw ParseIssue.unsupportedRule }
                        ordinal = parsed
                    }
                    weekdays.append(WeekdayRule(ordinal: ordinal, weekday: weekday))
                }
            }
            if let raw = fields["UNTIL"] {
                let property = Property(name: "UNTIL", parameters: start.dateOnly ? ["VALUE": "DATE"] : [:], value: raw)
                let value = try readDate(property, fallbackZone: start.zone)
                guard value.dateOnly == start.dateOnly, value.date >= start.date else { throw ParseIssue.unsupportedRule }
                until = value.date
            } else { until = nil }
            // RFC 5545 leaves a DTSTART inconsistent with RRULE undefined. Do
            // not silently choose one interpretation for a school schedule.
            guard matches(start.date, start: start) else { throw ParseIssue.unsupportedRule }
        }

        func matches(_ candidate: Date, start: CalendarDate) -> Bool {
            let calendar = start.calendar
            let current = calendar.dateComponents([.year, .month, .day, .weekday], from: candidate)
            let first = calendar.dateComponents([.year, .month, .day, .weekday], from: start.date)
            guard let year = current.year, let month = current.month, let day = current.day, let weekday = current.weekday,
                  let firstYear = first.year, let firstMonth = first.month, let firstDay = first.day, let firstWeekday = first.weekday else { return false }
            let elapsedDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: start.date), to: calendar.startOfDay(for: candidate)).day ?? -1
            guard elapsedDays >= 0 else { return false }
            if !months.isEmpty && !months.contains(month) { return false }
            switch frequency {
            case "DAILY": if elapsedDays % interval != 0 { return false }
            case "WEEKLY":
                let offset = (firstWeekday - weekStart + 7) % 7
                if ((elapsedDays + offset) / 7) % interval != 0 { return false }
                if weekdays.isEmpty && weekday != firstWeekday { return false }
            case "MONTHLY":
                if ((year - firstYear) * 12 + month - firstMonth) % interval != 0 { return false }
                if monthDays.isEmpty && weekdays.isEmpty && day != firstDay { return false }
            case "YEARLY":
                if (year - firstYear) % interval != 0 { return false }
                if monthDays.isEmpty && weekdays.isEmpty {
                    if months.isEmpty && month != firstMonth { return false }
                    if day != firstDay { return false }
                }
            default: return false
            }
            if !monthDays.isEmpty {
                guard let range = calendar.range(of: .day, in: .month, for: candidate) else { return false }
                if !monthDays.contains(where: { $0 > 0 ? day == $0 : day == range.count + $0 + 1 }) { return false }
            }
            if !weekdays.isEmpty {
                let accepted = weekdays.contains { rule in
                    guard rule.weekday == weekday else { return false }
                    guard let ordinal = rule.ordinal else { return true }
                    let scope: Calendar.Component = frequency == "YEARLY" && months.isEmpty ? .year : .month
                    guard let position = calendar.ordinality(of: .day, in: scope, for: candidate),
                          let range = calendar.range(of: .day, in: scope, for: candidate) else { return false }
                    let forward = (position - 1) / 7 + 1
                    let backward = -((range.count - position) / 7 + 1)
                    return ordinal > 0 ? ordinal == forward : ordinal == backward
                }
                if !accepted { return false }
            }
            return true
        }
    }

    static func expand(rule: RecurrenceRule, start: CalendarDate, duration: EventDuration, window: DateInterval,
                       scannedDays: inout Int) throws -> [CalendarDate] {
        let calendar = start.calendar
        let clock = calendar.dateComponents([.hour, .minute, .second], from: start.date)
        var day = calendar.startOfDay(for: start.date)
        if rule.count == nil {
            // No COUNT means history cannot affect the current occurrence count.
            // Include a lookback for multi-day events spanning the window start.
            let lookback = Double(duration.days) * 90_000 + duration.seconds
            day = max(day, calendar.startOfDay(for: window.start.addingTimeInterval(-lookback)))
        }
        var result: [CalendarDate] = [], occurrenceCount = 0
        while day < window.end {
            if scannedDays % 128 == 0 { try Task.checkCancellation() }
            if let until = rule.until, day > until { break }
            scannedDays += 1
            guard scannedDays <= maxScannedDays else { throw ParseIssue.expansionLimit }
            if rule.matches(day, start: start) {
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = clock.hour; components.minute = clock.minute; components.second = clock.second
                // Invalid recurrence dates and nonexistent local times are
                // excluded from the count (RFC 5545 section 3.3.10).
                if let candidate = calendar.date(from: components), calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: candidate) == components {
                    if let until = rule.until, candidate > until { break }
                    occurrenceCount += 1
                    if let count = rule.count, occurrenceCount > count { break }
                    let value = CalendarDate(date: candidate, dateOnly: start.dateOnly, zone: start.zone)
                    if overlaps(start: candidate, end: duration.end(from: value), window: window) { result.append(value) }
                    guard result.count <= maxOccurrences else { throw ParseIssue.expansionLimit }
                    if occurrenceCount == rule.count { break }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { throw ParseIssue.expansionLimit }
            day = next
        }
        return result
    }
}
