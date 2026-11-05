import Foundation

public enum RuleExtractor {
    /// The supplied year is an explicit import setting, never guessed from today's date.
    public static func extract(source: SourceDocument, year: Int, timeZone: String) -> [AcademicEvent] {
        var events: [AcademicEvent] = []
        var occurrence: [String: Int] = [:]
        var page = ""
        for raw in source.text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[Page ") { page = line; continue }
            guard !line.isEmpty, line.count < 8000, containsEvent(line) else { continue }
            let parsed = parseDate(line, year: year, timeZone: timeZone)
            var title = line
            if let range = parsed.range { title.removeSubrange(range) }
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
            events.append(AcademicEvent(
                id: "document-" + DocumentReader.fingerprint(identity), courseID: source.courseID,
                title: title, kind: eventKind(line), date: parsed.date, dateOnly: parsed.dateOnly,
                timeZone: parsed.zone, sourceID: source.id,
                evidence: page.isEmpty ? line : page + "\n" + line, sourceURL: source.url
            ))
        }
        return events
    }

    private static func containsEvent(_ line: String) -> Bool {
        line.range(of: "(?i)\\b(assignment|exam|quiz|project|presentation|homework|problem\\s+set|milestone|midterm|final|deadline|due|paper|report)\\b", options: .regularExpression) != nil
    }
    private static func eventKind(_ text: String) -> EventKind {
        let value = text.lowercased()
        if value.contains("exam") || value.contains("midterm") || value.contains("final") { return .exam }
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
    private static func parseDate(_ text: String, year: Int, timeZone: String) -> ParsedDate {
        var result = ParsedDate(zone: timeZone)
        guard var zone = TimeZone(identifier: timeZone), (1900...2200).contains(year) else { return result }
        if text.range(of: "(?i)\\b(?:UTC|GMT)\\b", options: .regularExpression) != nil { zone = .gmt; result.zone = zone.identifier }
        let monthPattern = "(?i)\\b(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(20\\d{2}))?\\b"
        let datePatterns = [monthPattern, "\\b20\\d{2}-\\d{2}-\\d{2}\\b", "\\b\\d{1,2}/\\d{1,2}(?:/20\\d{2})?\\b"]
        let dateCount = datePatterns.reduce(0) { count, pattern in
            count + ((try? NSRegularExpression(pattern: pattern))?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0)
        }
        // A line can contain release and due dates, or several events. Do not guess which
        // date belongs to the deadline; the structured extractor or reviewer can resolve it.
        guard dateCount <= 1 else { return result }
        var dateYear = year
        var month: Int?
        var day: Int?
        if let match = firstMatch("\\b(20\\d{2})-(\\d{2})-(\\d{2})\\b", in: text) {
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
        if let time = firstMatch("(?i)\\b(\\d{1,2}):(\\d{2})\\s*(AM|PM)?\\b", in: text) {
            var hour = Int(time.values[0]) ?? -1
            let minute = Int(time.values[1]) ?? -1
            let period = time.values[2].uppercased()
            guard (0...59).contains(minute) else { return result }
            if !period.isEmpty {
                guard (1...12).contains(hour) else { return result }
                hour = hour % 12 + (period == "PM" ? 12 : 0)
            } else { guard (0...23).contains(hour) else { return result } }
            components.hour = hour; components.minute = minute
            result.dateOnly = false
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
