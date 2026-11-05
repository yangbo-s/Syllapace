import Foundation

public enum RuleExtractor {
    public static func curate(source: SourceDocument, year: Int, timeZone: String) -> CurationResult {
        let issues = source.text.components(separatedBy: .newlines).compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.count <= 300, containsEvent(line), isConcreteLine(line, kind: eventKind(line)),
                  parseEventDate(line, kind: eventKind(line), year: year, timeZone: timeZone).date == nil else { return nil }
            return String(line.prefix(120)) + ": date or time needs clarification."
        }
        return CurationResult(events: extract(source: source, year: year, timeZone: timeZone), issues: Array(issues.prefix(30)))
    }
    /// The supplied year is an explicit import setting, never guessed from today's date.
    public static func extract(source: SourceDocument, year: Int, timeZone: String) -> [AcademicEvent] {
        var events: [AcademicEvent] = []
        var occurrence: [String: Int] = [:]
        var page = ""
        for raw in source.text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[Page ") { page = line; continue }
            guard !line.isEmpty, line.count <= 300, containsEvent(line) else { continue }
            let kind = eventKind(line)
            let parsed = parseEventDate(line, kind: kind, year: year, timeZone: timeZone)
            guard parsed.date != nil, isConcreteLine(line, kind: kind) else { continue }
            var title = line
            if let range = parsed.range { title.removeSubrange(range) }
            else if let marker = title.range(of: #"\b(?:release[ds]?|available from|opens? on|due|deadline)\b|发布日期|开放日期|截止"#, options: [.regularExpression, .caseInsensitive]) {
                title = String(title[..<marker.lowerBound])
            }
            title = title.replacingOccurrences(of: "(?i)\\b(?:at\\s+)?\\d{1,2}:\\d{2}\\s*(?:AM|PM)?(?:\\s*(?:EST|EDT|PST|PDT|CST|CDT|MST|MDT|UTC|GMT))?\\b", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "(?i)\\b(?:due|on|at)\\s*$", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "[\\t |]+", with: " ", options: .regularExpression)
            title = title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":–—-|,;()")))
            if title.isEmpty { title = line }
            title = String(title.prefix(240))
            let normalized = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let count = occurrence[normalized, default: 0]
            occurrence[normalized] = count + 1
            let identity = source.id + "|" + normalized + "|" + String(count)
            var event = AcademicEvent(
                id: "document-" + DocumentReader.fingerprint(identity), courseID: source.courseID,
                title: title, kind: kind, date: parsed.date, dateOnly: parsed.dateOnly,
                timeZone: parsed.zone, state: .approved, sourceID: source.id,
                evidence: page.isEmpty ? line : page + "\n" + line, sourceURL: source.url
            )
            event.subtype = EventCuration.subtype(for: title, kind: kind)
            if event.category == .deadline, let due = parsed.date, let release = releaseDate(in: line, year: year, timeZone: parsed.zone, due: due) {
                event.releasedAt = release.0; event.releaseDateOnly = release.1
            }
            event.sourceTitle = title
            event.curationVersion = EventCuration.version
            event.academicCalendarID = source.academicCalendarID
            events.append(event)
        }
        return events
    }

    private static func containsEvent(_ line: String) -> Bool {
        line.range(of: "(?i)\\b(lecture|recitation|lab|laboratory|class|demo|seminar|assignment|exam|quiz|project|presentation|homework|problem\\s+set|milestone|midterm|deadline|due|paper|report)\\b|上课|实验课|讨论课|考试|期中|期末|小测|作业|项目|截止|提交", options: .regularExpression) != nil
    }
    private static func isConcreteLine(_ line: String, kind: EventKind) -> Bool {
        guard EventCuration.supports(kind, evidence: line) else { return false }
        if [.assignment, .project, .presentation].contains(kind) {
            return EventCuration.matches(#"\b(due|deadline|submit|hand in|turn in)\b|截止|提交"#, line)
        }
        return true
    }
    private static func eventKind(_ text: String) -> EventKind {
        let value = text.lowercased()
        if EventCuration.matches(#"\b(lecture|recitation|lab|laboratory|class|demo|seminar)\b|上课|实验课|讨论课"#, value), !EventCuration.matches(#"\b(due|submit|deadline)\b|截止|提交"#, value) { return .session }
        if EventCuration.matches("项目|报告|论文", value) { return value.contains("项目") ? .project : .assignment }
        if value.contains("exam") || value.contains("midterm") || EventCuration.matches("考试|期中|期末", value) ||
            (EventCuration.matches(#"\bfinal\b"#, value) && !EventCuration.matches(#"\b(project|report|paper|presentation|submission)\b"#, value)) { return .exam }
        if value.contains("quiz") { return .quiz }
        if value.contains("presentation") { return .presentation }
        if value.contains("project") || value.contains("milestone") { return .project }
        return .assignment
    }
    private struct ParsedDate {
        var date: Date?
        var range: Range<String.Index>?
        var dateOnly = true
        var zone: String
    }

    private static func parseEventDate(_ text: String, kind: EventKind, year: Int, timeZone: String) -> ParsedDate {
        let direct = parseDate(text, year: year, timeZone: timeZone)
        guard direct.date == nil, [.assignment, .project, .presentation].contains(kind),
              let due = text.range(of: #"\b(?:due|deadline|submit(?:ted)? by)\b|截止|提交日期"#, options: [.regularExpression, .caseInsensitive]) else { return direct }
        var parsed = parseDate(String(text[due.upperBound...]), year: year, timeZone: timeZone)
        // This range belongs to a substring, not the complete title.
        parsed.range = nil
        return parsed
    }

    /// Availability must be stated alongside its own date; import/publication metadata is not evidence.
    static func releaseDate(in evidence: String, year: Int, timeZone: String, due: Date) -> (Date, Bool)? {
        guard let marker = evidence.range(of: #"\b(?:release[ds]?|available from|opens? on)\b|发布日期|开放日期"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var fragment = String(evidence[marker.upperBound...])
        if let boundary = fragment.range(of: #"\b(?:due|deadline|submit)\b|截止|提交"#, options: [.regularExpression, .caseInsensitive]) {
            fragment = String(fragment[..<boundary.lowerBound])
        }
        let parsed = parseDate(fragment, year: year, timeZone: timeZone)
        guard let date = parsed.date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: parsed.zone) ?? .gmt
        guard (parsed.dateOnly ? calendar.startOfDay(for: date) : date) <= due else { return nil }
        return (date, parsed.dateOnly)
    }

    /// Checks the actual date/time tokens, rather than trusting the model's confidence.
    static func evidenceSupports(date: Date, dateOnly: Bool, timeZone: String, year: Int, evidence: String, kind: EventKind) -> Bool {
        var text = evidence
        if [.assignment, .project, .presentation].contains(kind),
           let due = text.range(of: #"\b(?:due|deadline|submit(?:ted)? by)\b|截止|提交日期"#, options: [.regularExpression, .caseInsensitive]) {
            text = String(text[due.lowerBound...])
        }
        if let iso = try? NSRegularExpression(pattern: #"\b20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})"#) {
            let instants = iso.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range, in: text).flatMap { CanvasClient.instant(String(text[$0])) }
            }
            if !dateOnly, instants.contains(where: { abs($0.timeIntervalSince(date)) < 1 }) { return true }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
            if dateOnly, instants.contains(where: { calendar.isDate($0, inSameDayAs: date) }) { return false }
        }
        let pattern = #"(?:\b(?:20\d{2}-\d{2}-\d{2}|(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\.?\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s+20\d{2})?|\d{1,2}/\d{1,2}(?:/20\d{2})?)\b|(?:20\d{2}年)?\d{1,2}月\d{1,2}[日号])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return false }
        let ranges = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        for (index, range) in ranges.enumerated() {
            let end = index + 1 < ranges.count ? ranges[index + 1].lowerBound : text.endIndex
            let fragment = String(text[range.lowerBound..<end])
            let parsed = parseDate(fragment, year: year, timeZone: timeZone)
            guard let found = parsed.date else { continue }
            if dateOnly && parsed.dateOnly && calendar.isDate(found, inSameDayAs: date) { return true }
            if !dateOnly && !parsed.dateOnly && abs(found.timeIntervalSince(date)) < 1 { return true }
            // Sources sometimes contain the exact API timestamp.
            if !dateOnly, fragment.contains(date.ISO8601Format()) { return true }
        }
        return false
    }
    private static func parseDate(_ text: String, year: Int, timeZone: String) -> ParsedDate {
        var result = ParsedDate(zone: timeZone)
        guard var zone = TimeZone(identifier: timeZone), (1900...2200).contains(year) else { return result }
        if text.range(of: "(?i)\\b(?:UTC|GMT)\\b", options: .regularExpression) != nil { zone = .gmt; result.zone = zone.identifier }
        let monthPattern = "(?i)\\b(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(20\\d{2}))?\\b"
        let chinesePattern = #"(?:(20\d{2})年)?(\d{1,2})月(\d{1,2})[日号]"#
        let datePatterns = [monthPattern, "\\b20\\d{2}-\\d{2}-\\d{2}\\b", "\\b\\d{1,2}/\\d{1,2}(?:/20\\d{2})?\\b", chinesePattern]
        let dateCount = datePatterns.reduce(0) { count, pattern in
            count + ((try? NSRegularExpression(pattern: pattern))?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0)
        }
        // A line can contain release and due dates, or several events. Do not guess which
        // date belongs to the deadline; the structured extractor or reviewer can resolve it.
        guard dateCount <= 1 else { return result }
        var dateYear = year
        var month: Int?
        var day: Int?
        if let match = firstMatch(chinesePattern, in: text) {
            if let explicit = Int(match.values[0]) { dateYear = explicit }
            month = Int(match.values[1]); day = Int(match.values[2]); result.range = match.range
        } else if let match = firstMatch("\\b(20\\d{2})-(\\d{2})-(\\d{2})\\b", in: text) {
            dateYear = Int(match.values[0]) ?? year; month = Int(match.values[1]); day = Int(match.values[2]); result.range = match.range
        } else if let match = firstMatch(monthPattern, in: text) {
            let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            month = months.firstIndex(of: String(match.values[0].lowercased().prefix(3))).map { $0 + 1 }
            day = Int(match.values[1]); if let explicitYear = Int(match.values[2]) { dateYear = explicitYear }; result.range = match.range
        } else if let match = firstMatch("\\b(\\d{1,2})/(\\d{1,2})(?:/(20\\d{2}))?\\b", in: text) {
            let first = Int(match.values[0]) ?? 0, second = Int(match.values[1]) ?? 0
            result.range = match.range
            // Numeric dates with two valid month values are locale-ambiguous.
            guard first != second || first > 0 else { return result }
            if second > 12 && first <= 12 { month = first; day = second }
            else if first > 12 && second <= 12 { month = second; day = first }
            else if first == second { month = first; day = second }
            else { return result }
            if let explicitYear = Int(match.values[2]) { dateYear = explicitYear }
        }
        guard let month, let day, (1...12).contains(month), (1...31).contains(day) else { return result }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var components = DateComponents(timeZone: zone, year: dateYear, month: month, day: day, hour: 12)
        if let time = EvidenceClock.values(in: text).first {
            components.hour = time.0; components.minute = time.1
            result.dateOnly = false
        } else if EventCuration.matches(#"\d{1,2}[:：]\d{2}|\d{1,2}[点时]|\d{1,2}\s*(?:AM|PM)"#, text) {
            return result
        } else if text.range(of: "(?i)\\b(midnight|noon|during lecture|after class|before class)\\b", options: .regularExpression) != nil {
            // Keep the known date, but do not turn the unresolved phrase into a timestamp.
            result.dateOnly = true
        }
        guard let date = calendar.date(from: components) else { return result }
        let check = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard check.year == dateYear, check.month == month, check.day == day,
              check.hour == components.hour, check.minute == (components.minute ?? 0) else { return result }
        // A repeated DST wall-clock time has two possible instants; keep it unresolved.
        if !result.dateOnly {
            let start = calendar.startOfDay(for: date).addingTimeInterval(-1)
            let wallTime = DateComponents(hour: components.hour, minute: components.minute)
            let first = calendar.nextDate(after: start, matching: wallTime, matchingPolicy: .strict, repeatedTimePolicy: .first)
            let last = calendar.nextDate(after: start, matching: wallTime, matchingPolicy: .strict, repeatedTimePolicy: .last)
            if first != last { return result }
        }
        if let abbreviation = firstMatch("\\b(EST|EDT|PST|PDT|CST|CDT|MST|MDT)\\b", in: text),
           zone.abbreviation(for: date)?.uppercased() != abbreviation.values[0] { return result }
        result.date = date
        return result
    }
    private static func firstMatch(_ pattern: String, in text: String) -> (values: [String], range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range, in: text) else { return nil }
        let values = (1..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
        return (values, range)
    }
}
