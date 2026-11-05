import Foundation

/// A small deterministic path for written syllabus meeting times. No model call,
/// inferred semester, or conversion from a numbered teaching week is involved.
public enum WeeklySchedule {
    public static func extract(source: SourceDocument, year: Int, timeZone: String, termStart: Date?, termEnd: Date?) -> [AcademicEvent] {
        guard source.kind == .syllabus || source.title.localizedCaseInsensitiveContains("syllabus"),
              TimeZone(identifier: timeZone) != nil, termStart != nil, termEnd != nil else { return [] }
        let lines = source.text.components(separatedBy: .newlines)
        let dayPatterns = [#"\bSun(?:day)?s?\b"#, #"\bMon(?:day)?s?\b"#, #"\bTue(?:sday)?s?\b"#,
                           #"\bWed(?:nesday)?s?\b"#, #"\bThu(?:rsday)?s?\b"#, #"\bFri(?:day)?s?\b"#, #"\bSat(?:urday)?s?\b"#]
        var result: [AcademicEvent] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard EventCuration.matches(#"^(?:Lectures?|Recitations?|Labs?|Class(?:es)?(?: time)?|Time)\s*[:：]"#, line),
                  !EventCuration.matches(#"office hours|except|cancel|no class|考试|exam"#, line) else { continue }
            let days = dayPatterns.enumerated().compactMap { EventCuration.matches($0.element, line) ? $0.offset + 1 : nil }
            let clocks = EvidenceClock.values(in: line)
            guard !days.isEmpty, clocks.count == 2 else { continue }
            let startTime = String(format: "%02d:%02d", clocks[0].0, clocks[0].1)
            let endTime = String(format: "%02d:%02d", clocks[1].0, clocks[1].1)
            let recurrence = ExtractedRecurrence(weekdays: days, startTime: startTime, endTime: endTime)
            guard let occurrences = try? recurrence.occurrences(evidence: line, year: year, timeZone: timeZone, termStart: termStart, termEnd: termEnd) else { continue }
            let title = EventCuration.matches(#"^Recitation"#, line) ? "Recitation" : EventCuration.matches(#"^Lab"#, line) ? "Lab" : "Lecture"
            let series = "schedule:" + CanvasClient.hash(source.id + title + days.map(String.init).joined(separator: ",") + startTime)
            for (start, end) in occurrences {
                var event = AcademicEvent(id: series + ":" + start.ISO8601Format(), courseID: source.courseID, title: title,
                    kind: .session, date: start, dateOnly: false, timeZone: timeZone, state: .approved,
                    sourceID: source.id, evidence: line, sourceURL: source.url, sourceSeriesID: series)
                event.endsAt = end; event.observedSourceEndsAt = end
                event.subtype = EventCuration.subtype(for: title, kind: .session)
                event.curationVersion = EventCuration.version
                result.append(event)
            }
        }
        return result
    }
}
