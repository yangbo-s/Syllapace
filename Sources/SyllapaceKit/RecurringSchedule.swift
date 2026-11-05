import Foundation

enum RecurringScheduleEvidence {
    static func sameDayOrExplicitEnd(start: Date, end: Date, evidence: String, year: Int, timeZone: String) -> Bool {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        return calendar.isDate(start, inSameDayAs: end) || RuleExtractor.evidenceSupports(date: end, dateOnly: true, timeZone: timeZone, year: year, evidence: evidence, kind: .session)
    }
}

struct ExtractedRecurrence: Decodable, Sendable {
    var weekdays: [Int]
    var startTime: String
    var endTime: String?
    var startsOn: String?
    var endsOn: String?
    var excludedDates: [String]?

    func occurrences(evidence: String, year: Int, timeZone: String, termStart: Date?, termEnd: Date?) throws -> [(Date, Date?)] {
        let days = Set(weekdays)
        guard !days.isEmpty, days.count == weekdays.count, days.allSatisfy({ (1...7).contains($0) }),
              let startClock = Self.clock(startTime), Self.hasTime(startTime, evidence: evidence) else {
            throw ConnectorError.invalidModelOutput("A recurring class has no matching weekday or time evidence.")
        }
        let names = [1: #"\bSun(?:day)?s?\b|周日|星期日|星期天"#, 2: #"\bMon(?:day)?s?\b|周一|星期一"#,
                     3: #"\bTue(?:sday)?s?\b|周二|星期二"#, 4: #"\bWed(?:nesday)?s?\b|周三|星期三"#,
                     5: #"\bThu(?:rsday)?s?\b|周四|星期四"#, 6: #"\bFri(?:day)?s?\b|周五|星期五"#,
                     7: #"\bSat(?:urday)?s?\b|周六|星期六"#]
        for day in days {
            let compact = (days == Set([2, 4, 6]) && EventCuration.matches(#"\bM[ /-]?W[ /-]?F\b"#, evidence)) ||
                (days == Set([3, 5]) && EventCuration.matches(#"\b(?:TuTh|TTh)\b"#, evidence)) ||
                (days == Set([2, 4]) && EventCuration.matches(#"\bM[ /-]?W\b"#, evidence))
            guard compact || EventCuration.matches(names[day]!, evidence) else {
                throw ConnectorError.invalidModelOutput("A recurring class has no matching weekday or time evidence.")
            }
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timeZone)!
        let explicitStart = startsOn.flatMap { LLMClient.localDate($0, timeZone: timeZone) }
        let explicitLast = endsOn.flatMap { LLMClient.localDate($0, timeZone: timeZone) }
        if let startsOn {
            guard let explicitStart, RuleExtractor.evidenceSupports(date: explicitStart, dateOnly: true, timeZone: timeZone, year: year, evidence: evidence, kind: .session), !startsOn.isEmpty else {
                throw ConnectorError.invalidModelOutput("The recurrence start date is not supported by its evidence.")
            }
        }
        if let endsOn {
            guard let explicitLast, RuleExtractor.evidenceSupports(date: explicitLast, dateOnly: true, timeZone: timeZone, year: year, evidence: evidence, kind: .session), !endsOn.isEmpty else {
                throw ConnectorError.invalidModelOutput("The recurrence end date is not supported by its evidence.")
            }
        }
        let explicitEnd = explicitLast.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
        guard let lower = explicitStart ?? termStart, let upper = explicitEnd ?? termEnd else {
            throw ConnectorError.invalidModelOutput("A recurring class needs explicit course start and end dates.")
        }
        let start = max(lower, termStart ?? lower), end = min(upper, termEnd ?? upper)
        guard start < end, end.timeIntervalSince(start) <= 370 * 86_400 else {
            throw ConnectorError.invalidModelOutput("A recurring class has an invalid course date range.")
        }
        let mentionsExceptions = EventCuration.matches(#"\bexcept\b|\bno (?:class|lecture|lab|recitation)\b|\b(?:class|lecture|lab) (?:is |will be )?cancel(?:led|ed)\b|停课|不上课"#, evidence)
        let omitted = excludedDates ?? []
        guard omitted.count <= 100, !mentionsExceptions || !omitted.isEmpty else {
            throw ConnectorError.invalidModelOutput("A recurring class has an unresolved cancellation or exception.")
        }
        var exclusions = Set<Date>()
        for raw in omitted {
            guard mentionsExceptions, let excluded = LLMClient.localDate(raw, timeZone: timeZone),
                  RuleExtractor.evidenceSupports(date: excluded, dateOnly: true, timeZone: timeZone, year: year, evidence: evidence, kind: .session) else {
                throw ConnectorError.invalidModelOutput("A class cancellation is not supported by its source.")
            }
            exclusions.insert(calendar.startOfDay(for: excluded))
        }
        let endClock = endTime.flatMap(Self.clock)
        if let endTime {
            guard let endClock, Self.hasTime(endTime, evidence: evidence), endClock.0 * 60 + endClock.1 > startClock.0 * 60 + startClock.1 else {
                throw ConnectorError.invalidModelOutput("A recurring class has no matching end-time evidence.")
            }
        }
        var result: [(Date, Date?)] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            try Task.checkCancellation()
            if days.contains(calendar.component(.weekday, from: day)), !exclusions.contains(day) {
                let stamp = Self.wallTime(startClock, day: day, calendar: calendar)
                let finish = endClock.flatMap { Self.wallTime($0, day: day, calendar: calendar) }
                // Nonexistent or repeated DST times are not guessed.
                guard let stamp, endClock == nil || finish != nil else {
                    throw ConnectorError.invalidModelOutput("A recurring class crosses an ambiguous daylight-saving time.")
                }
                if stamp >= start && stamp < end { result.append((stamp, finish)) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        guard result.count <= 300 else { throw ConnectorError.responseTooLarge }
        return result
    }

    static func clock(_ text: String) -> (Int, Int)? {
        guard text.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let values = text.split(separator: ":").compactMap { Int($0) }
        guard values.count == 2, (0...23).contains(values[0]), (0...59).contains(values[1]) else { return nil }
        return (values[0], values[1])
    }

    static func hasTime(_ text: String, evidence: String) -> Bool {
        guard let wanted = clock(text) else { return false }
        return EvidenceClock.values(in: evidence).contains { $0.0 == wanted.0 && $0.1 == wanted.1 }
    }

    private static func wallTime(_ clock: (Int, Int), day: Date, calendar: Calendar) -> Date? {
        let components = DateComponents(hour: clock.0, minute: clock.1, second: 0)
        let first = calendar.nextDate(after: day.addingTimeInterval(-1), matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first)
        let last = calendar.nextDate(after: day.addingTimeInterval(-1), matching: components, matchingPolicy: .strict, repeatedTimePolicy: .last)
        guard let first, first == last, calendar.isDate(first, inSameDayAs: day) else { return nil }
        return first
    }
}
