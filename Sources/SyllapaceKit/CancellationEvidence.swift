import Foundation

public struct CourseCancellation: Sendable, Equatable {
    public let courseID: String
    /// Nil means an explicit generic class/classes cancellation in this course.
    public let subtype: EventSubtype?
    public let start: Date
    public let end: Date
    public let timeZone: String
    public let sourceID: String
    public let sourceURL: String?
    public let evidence: String

    public func matches(event: AcademicEvent) -> Bool {
        guard event.courseID == courseID, event.kind == .session, let date = event.date,
              date >= start, date < end else { return false }
        guard let subtype else { return true }
        return (event.subtype ?? EventCuration.subtype(for: event.title, kind: .session)) == subtype
    }
}

/// Only explicit cancellation statements suppress scheduled meetings. This does
/// not edit stored events, infer holidays, or choose among ambiguous relative dates.
public enum CancellationEvidence {
    public static func extract(source: SourceDocument, course: Course) -> [CourseCancellation] {
        guard source.courseID == course.id, source.kind == .announcement || source.kind == .page || source.kind == .syllabus,
              let zoneName = course.timeZone ?? source.curationTimeZone, let zone = TimeZone(identifier: zoneName) else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let body = clauses(source.text)
        var statements = body
        let titleQualified = !isNegatedOrConditional(source.text)
        if titleQualified, !source.title.isEmpty { statements.insert(source.title, at: 0) }
        // A short notice may put the cancellation in its title and the day in
        // its first sentence. Never combine the title with a whole document.
        if titleQualified, let first = body.first, first.count <= 300, hasCancellation(source.title) && dateRanges(source.title, source: source, course: course, calendar: calendar).isEmpty {
            statements.append(source.title + ": " + first)
        }
        var result: [CourseCancellation] = []
        var seen = Set<String>()
        for statement in statements {
            guard !isNegatedOrConditional(statement) else { continue }
            let kinds = cancellationKinds(statement)
            guard !kinds.isEmpty else { continue }
            for range in dateRanges(statement, source: source, course: course, calendar: calendar) {
                for kind in kinds {
                    let subtype: EventSubtype? = kind == "recitation" ? .recitation : kind == "lecture" ? .lecture : kind == "lab" ? .lab : nil
                    let key = kind + ":" + range.0.ISO8601Format() + ":" + range.1.ISO8601Format()
                    guard seen.insert(key).inserted else { continue }
                    result.append(CourseCancellation(courseID: course.id, subtype: subtype, start: range.0, end: range.1,
                                                     timeZone: zoneName, sourceID: source.id, sourceURL: source.url, evidence: statement))
                }
            }
        }
        return result.sorted { $0.start == $1.start ? ($0.subtype?.rawValue ?? "") < ($1.subtype?.rawValue ?? "") : $0.start < $1.start }
    }

    private static func clauses(_ text: String) -> [String] {
        text.replacingOccurrences(of: #"(?<=[.!?;])\s+(?=[A-Za-z])"#, with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 1_000 }
    }

    private static func hasCancellation(_ text: String) -> Bool { !cancellationKinds(text).isEmpty }

    private static func isNegatedOrConditional(_ text: String) -> Bool {
        EventCuration.matches(#"\b(?:not|never|no longer)\s+(?:be\s+)?cancel(?:led|ed)\b|\b(?:if|unless|whether|maybe)\b|\b(?:might|may|could)\s+be\s+cancel(?:led|ed)\b|\bno\s+(?:lectures?|recitations?|labs?|class(?:es)?)\s+(?:(?:is|are|was|were|will be)\s+)?cancel(?:led|ed)\b|\bno\s+(?:lecture|recitation|lab|class)\s+cancellations?\b"#, text)
    }

    private static func cancellationKinds(_ text: String) -> Set<String> {
        let noun = #"(lecture|recitation|lab|class)(?:es|s)?\b"#
        let patterns = [#"\bno\s+(?:scheduled\s+)?"# + noun,
                        #"\bcancel(?:led|ed)\s+(?:(?:today|tomorrow)['’]s\s+)?"# + noun,
                        #"\b"# + noun + #"\s+(?:(?:is|are|was|were|will be|has been|have been)\s+)?cancel(?:led|ed)\b"#]
        return Set(patterns.flatMap { captures($0, text: text).compactMap { $0.first?.lowercased() } })
    }

    private static func dateRanges(_ text: String, source: SourceDocument, course: Course, calendar: Calendar) -> [(Date, Date)] {
        var days = Set<Date>()
        let reference = source.publishedAt.map { calendar.startOfDay(for: $0) }
        let year = course.term?.academicYear ?? source.curationYear ?? reference.map { calendar.component(.year, from: $0) }
        for match in captures(#"\b(20\d{2})-(\d{2})-(\d{2})\b"#, text: text) {
            if let date = civilDate(year: Int(match[0]), month: Int(match[1]), day: Int(match[2]), calendar: calendar) { days.insert(date) }
        }
        let monthNames = #"(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)"#
        for match in captures(#"\b"# + monthNames + #"\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(20\d{2}))?\b"#, text: text) {
            if let date = civilDate(year: Int(match[2]) ?? year, month: month(match[0]), day: Int(match[1]), calendar: calendar) { days.insert(date) }
        }
        for match in captures(#"\b(\d{1,2})(?:st|nd|rd|th)?\s+"# + monthNames + #"\.?(?:,?\s+(20\d{2}))?\b"#, text: text) {
            if let date = civilDate(year: Int(match[2]) ?? year, month: month(match[1]), day: Int(match[0]), calendar: calendar) { days.insert(date) }
        }
        var ranges: [(Date, Date)] = []
        if let reference {
            if EventCuration.matches(#"\bthis\s+week\b"#, text) {
                let offset = (calendar.component(.weekday, from: reference) + 5) % 7
                if let start = calendar.date(byAdding: .day, value: -offset, to: reference), let end = calendar.date(byAdding: .day, value: 7, to: start) {
                    ranges.append((start, end))
                }
            }
            for match in captures(#"\b(today|tomorrow|yesterday|this\s+(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday))\b"#, text: text) {
                let phrase = match[0].lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
                let offset: Int?
                switch phrase {
                case "today": offset = 0
                case "tomorrow": offset = 1
                case "yesterday": offset = -1
                default:
                    let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
                    let current = (calendar.component(.weekday, from: reference) + 5) % 7
                    offset = weekdays.firstIndex(of: String(phrase.dropFirst(5))).flatMap { $0 >= current ? $0 - current : nil }
                }
                if let offset, let day = calendar.date(byAdding: .day, value: offset, to: reference) { days.insert(day) }
            }
        }
        ranges += days.sorted().compactMap { day in calendar.date(byAdding: .day, value: 1, to: day).map { (day, $0) } }
        return ranges
    }

    private static func month(_ name: String) -> Int? {
        ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"].firstIndex(of: String(name.lowercased().prefix(3))).map { $0 + 1 }
    }

    private static func civilDate(year: Int?, month: Int?, day: Int?, calendar: Calendar) -> Date? {
        guard let year, let month, let day, (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let parts = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: parts), calendar.dateComponents([.year, .month, .day], from: date) == parts else { return nil }
        return date
    }

    private static func captures(_ pattern: String, text: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }
}
