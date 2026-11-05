import Foundation

/// Builds a transient model input. The stored source text and its identity stay
/// unchanged; every added date is attributed to Canvas metadata or a named source.
public enum CurationContext {
    /// The same attributed relative-date excerpts used in the prepared input.
    /// Local recovery can inspect these without parsing metadata as event text.
    public static func resolvedMeetingEvidence(source: SourceDocument, course: Course) -> [String] {
        guard source.courseID == course.id, source.kind == .announcement,
              let zone = (course.timeZone ?? source.curationTimeZone).flatMap(TimeZone.init(identifier:)) else { return [] }
        return normalizedLines(source: source, zone: zone).map(\.text)
    }

    public static func prepare(source: SourceDocument, course: Course, relatedSources: [SourceDocument]) -> SourceDocument {
        guard source.courseID == course.id else { return source }
        let zone = (course.timeZone ?? source.curationTimeZone).flatMap(TimeZone.init(identifier:))
        var additions: [String] = []
        if let table = SyllabusTableContext.evidence(source: source, course: course, relatedSources: relatedSources) { additions.append(table) }
        if let due = source.effectiveDueAt {
            additions.append(metadataEvidence(source: source, due: due))
        } else if let available = source.availableAt {
            additions.append("[Canvas availability metadata; not a deadline]\n\(reference(source))\nAvailable from: \(available.ISO8601Format())")
        }
        if let published = source.publishedAt {
            additions.append("[Canvas publication metadata; not an event date]\n\(reference(source))\nposted_at: \(published.ISO8601Format())")
        }
        if let zone {
            let lines = normalizedLines(source: source, zone: zone)
            if !lines.isEmpty {
                additions.append("[Relative dates resolved from Canvas posted_at in \(zone.identifier)]\n\(reference(source))\n" + lines.map(\.text).joined(separator: "\n"))
            }
            if let meeting = relatedMeeting(source: source, lines: lines, relatedSources: relatedSources, zone: zone) {
                additions.append(meeting)
            }
        }
        if let timetable = weeklyReference(source: source, relatedSources: relatedSources) { additions.append(timetable) }
        let gradesOnly = source.kind == .announcement && EventCuration.matches(#"\b(grades?|scores?)\b"#, source.title) &&
            !EventCuration.matches(#"\b(due|deadline|submit|extension|extended)\b"#, source.text)
        if !gradesOnly, source.effectiveDueAt == nil, let identity = assignmentIdentity(source) {
            let matches = relatedSources.filter {
                $0.id != source.id && $0.courseID == source.courseID && $0.kind == .assignment &&
                    $0.effectiveDueAt != nil && assignmentIdentity($0) == identity
            }.sorted { $0.id < $1.id }
            // A shared name is not permission to choose between conflicting due dates.
            if Set(matches.compactMap(\.effectiveDueAt)).count == 1, var matched = matches.first, let due = matched.effectiveDueAt {
                if Set(matches.compactMap(\.availableAt)).count > 1 { matched.availableAt = nil }
                additions.append(metadataEvidence(source: matched, due: due, related: true))
            }
        }
        var prepared = source
        // Never truncate the original. Add complete evidence blocks only, within
        // the model adapter's existing document limit.
        for addition in additions {
            let block = "\n\n" + addition
            if prepared.text.count + block.count <= 64_000 { prepared.text += block }
        }
        return prepared
    }

    private static func weeklyReference(source: SourceDocument, relatedSources: [SourceDocument]) -> String? {
        let syllabus = source.kind == .syllabus || source.title.localizedCaseInsensitiveContains("syllabus")
        let requestedKind = meetingKind(source)
        let currentNotice = source.kind == .announcement && requestedKind != nil &&
            EventCuration.matches(#"\b(today|tomorrow|this\s+(?:week|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)|cancelled|canceled|no\s+(?:class|lecture|recitation|lab))\b"#, source.title + "\n" + source.text)
        guard syllabus || currentNotice else { return nil }
        var blocks: [String] = []
        for related in relatedSources.sorted(by: { $0.id < $1.id }) where related.courseID == source.courseID && related.id != source.id {
            var groups: [String: (kind: String, clock: String, zone: String, days: Set<Int>)] = [:]
            for event in related.meetingSchedule ?? [] where event.courseID == source.courseID && event.kind == .session && !event.dateOnly {
                guard let date = event.date, let zone = TimeZone(identifier: event.timeZone) else { continue }
                let subtype = event.subtype ?? EventCuration.subtype(for: event.title, kind: .session)
                let kind: String
                switch subtype {
                case .lecture: kind = "lecture"
                case .recitation: kind = "recitation"
                case .lab: kind = "lab"
                case .seminar: kind = "seminar"
                case .demo: kind = "demo"
                default: kind = "class"
                }
                guard syllabus || requestedKind == kind || kind == "class" else { continue }
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                func clock(_ value: Date) -> String {
                    let parts = calendar.dateComponents([.hour, .minute], from: value)
                    return String(format: "%02d:%02d", parts.hour!, parts.minute!)
                }
                let time = clock(date) + (event.endsAt.map { "–" + clock($0) } ?? "")
                let key = kind + "|" + time + "|" + zone.identifier
                var group = groups[key] ?? (kind, time, zone.identifier, [])
                group.days.insert(calendar.component(.weekday, from: date)); groups[key] = group
            }
            guard !groups.isEmpty else { continue }
            let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            let summaries = groups.keys.sorted().prefix(6).compactMap { key -> String? in
                guard let group = groups[key] else { return nil }
                let label = group.kind == "class" ? "Class (meeting type not specified)" : group.kind.capitalized
                return label + ": " + group.days.sorted().map { names[$0 - 1] }.joined(separator: ", ") + " " + group.clock + " (" + group.zone + ")"
            }
            blocks.append(reference(related) + "\n" + summaries.joined(separator: "\n"))
            if blocks.count == 2 { break }
        }
        guard !blocks.isEmpty else { return nil }
        return "[Official weekly timetable — reference only. These recurring meetings are already scheduled. Use this context to interpret this source; do not extract or expand the whole semester again. An unspecified class type is not evidence of a lecture or recitation.]\n" + blocks.joined(separator: "\n")
    }

    private static func metadataEvidence(source: SourceDocument, due: Date, related: Bool = false) -> String {
        let release = source.availableAt.flatMap { $0 <= due ? $0 : nil }
            .map { "available from \($0.ISO8601Format()); " } ?? ""
        let label = related ? "Related Canvas assignment with the same course and task identity" : "Canvas effective assignment dates"
        return "[\(label)]\n\(reference(source))\n\(source.title) — \(release)due \(due.ISO8601Format())"
    }

    private struct NormalizedLine {
        let text: String
        let dates: Set<String>
    }

    private static func normalizedLines(source: SourceDocument, zone: TimeZone) -> [NormalizedLine] {
        guard let published = source.publishedAt,
              let regex = try? NSRegularExpression(pattern: #"\b(today|tomorrow|yesterday|this\s+(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday))\b"#,
                                                    options: .caseInsensitive) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = calendar.startOfDay(for: published)
        return ([source.title] + source.text.components(separatedBy: .newlines)).compactMap { line in
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            var normalized = line
            var dates = Set<String>()
            for match in matches.reversed() {
                guard let range = Range(match.range, in: line) else { continue }
                let phrase = String(line[range]).lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
                let offset: Int?
                switch phrase {
                case "today": offset = 0
                case "tomorrow": offset = 1
                case "yesterday": offset = -1
                default:
                    let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
                    let current = (calendar.component(.weekday, from: day) + 5) % 7
                    let target = weekdays.firstIndex(of: String(phrase.dropFirst(5)))
                    // "This Friday" before/on Friday is unambiguous. A past
                    // weekday may refer to this week or the next; leave it intact.
                    offset = target.flatMap { $0 >= current ? $0 - current : nil }
                }
                guard let offset, let date = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
                let key = dayKey(date, calendar: calendar)
                dates.insert(key)
                normalized.replaceSubrange(range, with: key)
            }
            guard !dates.isEmpty else { return nil }
            return NormalizedLine(text: source.title + " — " + normalized, dates: dates)
        }
    }

    private static func relatedMeeting(source: SourceDocument, lines: [NormalizedLine], relatedSources: [SourceDocument], zone: TimeZone) -> String? {
        guard let meeting = meetingKind(source), EvidenceClock.values(in: source.text).isEmpty else { return nil }
        let dates = Set(lines.flatMap(\.dates))
        guard dates.count == 1 else { return nil }
        var candidates: [(SourceDocument, NormalizedLine, String)] = []
        for related in relatedSources where related.id != source.id && related.courseID == source.courseID && meetingKind(related) == meeting {
            for line in normalizedLines(source: related, zone: zone) where line.dates == dates {
                let times = EvidenceClock.values(in: line.text)
                guard !times.isEmpty, times.count <= 2 else { continue }
                let signature = times.map { "\($0.0):\($0.1)" }.joined(separator: "-")
                candidates.append((related, line, signature))
            }
        }
        guard Set(candidates.map(\.2)).count == 1, let match = candidates.sorted(by: { $0.0.id < $1.0.id }).first else { return nil }
        return "[Related \(meeting) notice for the same course and resolved date; use its stated time]\n\(reference(match.0))\n\(match.1.text)"
    }

    static func assignmentIdentity(_ source: SourceDocument) -> String? {
        let heading = source.title
        let text = source.kind == .assignment ? heading + "\n" + source.text.prefix(1_000) : heading
        let numbered = #"\b(homework|hw|problem\s*set|pset|project)\s*[-#:]?\s*0*(\d+)\b"#
        if let regex = try? NSRegularExpression(pattern: numbered, options: .caseInsensitive) {
            let identities = Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> String? in
                guard let kindRange = Range(match.range(at: 1), in: text), let numberRange = Range(match.range(at: 2), in: text),
                      let number = Int(text[numberRange]) else { return nil }
                return (text[kindRange].lowercased() == "project" ? "project:" : "homework:") + String(number)
            })
            if identities.count == 1, let identity = identities.first {
                let part = capture(#"\bpart\s*[-#:]?\s*(\d+|[a-z])\b"#, in: heading).map { ":part:" + (Int($0).map(String.init) ?? $0.lowercased()) } ?? ""
                return identity + part
            }
            if !identities.isEmpty { return nil }
        }
        let normalized = EventCuration.canonicalTitle(heading)
            .replacingOccurrences(of: #"(?:\s+(?:released|updated|available|posted|reminder))+$"#, with: "", options: .regularExpression)
        if ["project proposal", "final project proposal", "final report", "final project report"].contains(normalized) { return "named:" + normalized }
        if normalized.split(separator: " ").count >= 3, EventCuration.matches(#"\b(project|report|assignment|submission)\b"#, normalized) { return "named:" + normalized }
        return nil
    }

    private static func meetingKind(_ source: SourceDocument) -> String? {
        let text = source.title + "\n" + source.text.prefix(300)
        let kinds = ["recitation", "lecture", "lab"].filter { EventCuration.matches("\\b" + $0 + "\\b", text) }
        return kinds.count == 1 ? kinds.first : nil
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private static func reference(_ source: SourceDocument) -> String {
        var reference = "Source: " + source.id + " (" + source.title + ")"
        if let raw = source.url, var url = URLComponents(string: raw), url.scheme == "https", url.host != nil {
            url.user = nil; url.password = nil; url.query = nil; url.fragment = nil
            if let safe = url.string { reference += "\nURL: " + safe }
        }
        return reference
    }
}
