import Foundation

/// Restores the month/day association that plain-text HTML and PDF tables lose.
/// Only explicit task rows with a matching weekday become model evidence.
enum SyllabusTableContext {
    private struct TaskDates {
        var release = Set<Date>()
        var due = Set<Date>()
    }
    private static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    private static let weekday = #"(Sun(?:day)?|Mon(?:day)?|Tue(?:s(?:day)?)?|Wed(?:nesday)?|Thu(?:rs(?:day)?)?|Fri(?:day)?|Sat(?:urday)?)\.*"#

    static func evidence(source: SourceDocument, course: Course, relatedSources: [SourceDocument]) -> String? {
        guard source.kind == .syllabus, let year = source.curationYear ?? course.term?.academicYear,
              (1900...2200).contains(year), let zone = (source.curationTimeZone ?? course.timeZone).flatMap(TimeZone.init(identifier:)) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let lines = source.text.replacingOccurrences(of: "|", with: "\n").components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var month: Int?, current: Date?, rowLines = 0
        var tasks: [String: TaskDates] = [:]
        var index = 0
        while index < lines.count {
            let line = lines[index]; index += 1
            if let position = months.firstIndex(of: line.lowercased()) {
                month = position + 1; current = nil; rowLines = 0; continue
            }
            // Explicit years never inherit the course's different year.
            if let heading = groups(#"^(January|February|March|April|May|June|July|August|September|October|November|December)\s+(20\d{2})$"#, line) {
                month = Int(heading[1]) == year ? months.firstIndex(of: heading[0].lowercased()).map { $0 + 1 } : nil
                current = nil; rowLines = 0; continue
            }
            if line.range(of: #"^\[Page \d+\]$"#, options: .regularExpression) != nil { continue }
            var row = groups(#"^(\d{1,2})\s+"# + weekday + #"(?:\s+(.*))?$"#, line)
            if row == nil, line.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil,
               index < lines.count, let day = groups("^" + weekday + "$", lines[index]) {
                row = [line, day[0], ""]; index += 1
            }
            var content = line
            if let row {
                current = nil; rowLines = 0
                if let month, let day = Int(row[0]), let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
                   calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day,
                   ["sun", "mon", "tue", "wed", "thu", "fri", "sat"][calendar.component(.weekday, from: date) - 1] == String(row[1].lowercased().prefix(3)) {
                    current = date
                }
                content = row[2]
            }
            guard let date = current, rowLines < 6 else { continue }
            rowLines += 1
            for (title, release) in actions(content) {
                var dates = tasks[title] ?? TaskDates()
                if release { dates.release.insert(date) } else { dates.due.insert(date) }
                tasks[title] = dates
            }
        }
        let clock = homeworkClock(source.text, zone: zone)
        var evidence: [String] = []
        var authorities = Set<String>()
        for title in tasks.keys.sorted() {
            guard let task = tasks[title], task.due.count == 1, task.release.count <= 1, let due = task.due.first else { continue }
            if let release = task.release.first, release > due { continue }
            var date = dayKey(due, calendar: calendar)
            var released = task.release.first.map { dayKey($0, calendar: calendar) }
            if title.hasPrefix("Homework "), let clock {
                guard let exact = calendar.date(bySettingHour: clock.0, minute: clock.1, second: clock.2, of: due),
                      calendar.isDate(exact, inSameDayAs: due),
                      calendar.component(.hour, from: exact) == clock.0,
                      calendar.component(.minute, from: exact) == clock.1,
                      calendar.component(.second, from: exact) == clock.2 else { continue }
                let start = calendar.startOfDay(for: due).addingTimeInterval(-1)
                let wall = DateComponents(hour: clock.0, minute: clock.1, second: clock.2)
                guard calendar.nextDate(after: start, matching: wall, matchingPolicy: .strict, repeatedTimePolicy: .first) ==
                      calendar.nextDate(after: start, matching: wall, matchingPolicy: .strict, repeatedTimePolicy: .last) else { continue }
                date = exact.ISO8601Format()
            }
            let identity = CurationContext.assignmentIdentity(SourceDocument(courseID: source.courseID, title: title, text: "", kind: .assignment))
            let matches = relatedSources.filter { $0.courseID == source.courseID && $0.kind == .assignment && $0.effectiveDueAt != nil &&
                identity != nil && CurationContext.assignmentIdentity($0) == identity }
            if !matches.isEmpty {
                guard Set(matches.compactMap(\.effectiveDueAt)).count == 1, let assignment = matches.sorted(by: { $0.id < $1.id }).first,
                      let effective = assignment.effectiveDueAt else { continue }
                date = effective.ISO8601Format()
                if let available = assignment.availableAt, available <= effective { released = available.ISO8601Format() }
                else if let release = RuleExtractor.releaseDate(in: assignment.text.split(whereSeparator: \.isWhitespace).joined(separator: " "), year: year, timeZone: zone.identifier, due: effective) {
                    released = release.1 ? dayKey(release.0, calendar: calendar) : release.0.ISO8601Format()
                }
                authorities.insert("Canvas effective assignment dates for " + title + ": " + assignment.id)
            }
            let release = released.map { "released " + $0 + "; " } ?? ""
            evidence.append(title + " — " + release + "due " + date)
        }
        guard !evidence.isEmpty else { return nil }
        return "[Resolved syllabus table entries — month headings and day/weekday rows, checked against the selected academic year. Explicit homework time rules apply only to homework. Matching Canvas effective assignment dates supersede preliminary syllabus dates. Quote a complete entry below; do not splice table fragments or add ellipses.]\nSource: " + source.id + "\n" + authorities.sorted().joined(separator: "\n") + "\n" + evidence.prefix(100).joined(separator: "\n")
    }

    private static func actions(_ line: String) -> [(String, Bool)] {
        let task = #"(?:HW\s*\d+|Homework\s+\d+|Blog post|Final report|Project proposal|Project report)"#
        let pattern = #"(?:^|[,;])\s*(?:release\s+("# + task + #")|("# + task + #")\s+due)\s*(?=[,;.!]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { match in
            let release = match.range(at: 1).location != NSNotFound
            guard let range = Range(match.range(at: release ? 1 : 2), in: line) else { return nil }
            let raw = String(line[range])
            if let numbered = groups(#"^(?:HW|Homework)\s*(\d+)$"#, raw), let number = Int(numbered[0]) { return ("Homework \(number)", release) }
            return (raw.prefix(1).uppercased() + raw.dropFirst().lowercased(), release)
        }
    }

    private static func homeworkClock(_ text: String, zone: TimeZone) -> (Int, Int, Int)? {
        let compact = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let rule = groups(#"\b(?:completed\s+|all\s+)?homeworks?\s+(?:assignments?\s+)?(?:are\s+)?due\s+at\s+([^.!?]{1,160})"#, compact)?.first,
              !EventCuration.matches(#"\b(unless|except|usually|typically|approximately)\b"#, rule) else { return nil }
        if EventCuration.matches(#"\b(ET|Eastern)\b"#, rule), zone.identifier != "America/New_York" { return nil }
        // A fixed abbreviation or a different zone needs per-date interpretation;
        // do not reinterpret it as the course's daylight-saving clock.
        if EventCuration.matches(#"\b(EST|EDT|PST|PDT|CST|CDT|MST|MDT|UTC|GMT|PT|CT|MT)\b"#, rule) { return nil }
        let clocks = EvidenceClock.components(in: rule)
        return clocks.count == 1 ? clocks[0] : nil
    }
    private static func groups(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let value = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", value.year!, value.month!, value.day!)
    }
}
