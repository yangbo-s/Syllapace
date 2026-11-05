import Foundation

/// A narrow, offline repair for posted announcements. This does not infer tasks,
/// assessments, recurring rules, or a clock from a date-only placeholder.
public enum LocalCurationRecovery {
    public static func restore(existing: [AcademicEvent], sources: [SourceDocument], courses: [Course]) -> [AcademicEvent] {
        var restored = existing
        let courseByID = Dictionary(courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for source in sources.sorted(by: { $0.id < $1.id }) where source.kind == .announcement {
            guard let course = courseByID[source.courseID] else { continue }
            let owned = restored.filter { $0.courseID == source.courseID && $0.sourceID == source.id }
            let local = owned.filter { $0.id.hasPrefix("local-meeting:") }
            let incoming = recover(source: source, course: course, relatedSources: sources).filter { observation in
                !owned.contains { saved in
                    guard saved.kind == .session, resolvedSubtype(saved) == observation.subtype else { return false }
                    let userIntent = saved.userEdited || saved.importUndone == true || (saved.state == .rejected && saved.curationExcluded != true)
                    let alreadyObserved = !saved.id.hasPrefix("local-meeting:") && saved.state == .approved && !saved.dateOnly &&
                        saved.date == observation.date && saved.timeZone == observation.timeZone
                    return userIntent || alreadyObserved
                }
            }
            let localIDs = Set(local.map(\.id))
            // Restrict reorganization to local identities. In particular, a
            // unique source/title fallback must not reuse a retired date's ID.
            let refreshed = EventCuration.reorganize(existing: local, incoming: incoming.filter { localIDs.contains($0.id) }, sourceIDs: [source.id]).events
            let replacements = Dictionary(refreshed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            restored = restored.map { replacements[$0.id] ?? $0 }
            restored += Reconciler.merge(existing: [], incoming: incoming.filter { !localIDs.contains($0.id) })
        }
        return restored
    }

    public static func recover(source: SourceDocument, course: Course, relatedSources: [SourceDocument]) -> [AcademicEvent] {
        guard let context = context(source, course: course) else { return [] }
        let observations = relativeObservations(source, course: course, context: context)
        let cancellations = CancellationEvidence.extract(source: source, course: course)
        var recovered: [AcademicEvent] = []
        for group in Dictionary(grouping: observations, by: { key($0, calendar: context.calendar) }).values {
            guard let anchor = group.first, let anchorDate = anchor.date, let subtype = anchor.subtype else { continue }
            let stated = group.filter { !$0.dateOnly }
            var candidates = stated
            if stated.isEmpty {
                candidates = titleClockCandidates(source, anchor: anchor, context: context)
                if candidates.isEmpty {
                    for related in relatedSources.sorted(by: { $0.id < $1.id }) where related.id != source.id && related.courseID == source.courseID {
                        let timed = relativeObservations(related, course: course, context: context).filter {
                            !$0.dateOnly && $0.subtype == subtype && $0.date.map { context.calendar.isDate($0, inSameDayAs: anchorDate) } == true
                        }
                        for event in timed { candidates.append(attributed(event, to: source, anchor: anchor, related: related)) }
                        for event in related.meetingSchedule ?? [] where event.courseID == source.courseID && event.kind == .session && !event.dateOnly && event.state == .approved {
                            guard event.subtype == subtype, let date = event.date,
                                  context.calendar.isDate(date, inSameDayAs: anchorDate), event.timeZone == context.zone,
                                  let verified = verifiedOfficial(event, source: related, context: context) else { continue }
                            candidates.append(attributed(verified, to: source, anchor: anchor, related: related))
                        }
                    }
                    if let inferred = uniqueOfficialSlot(source: source, anchor: anchor, relatedSources: relatedSources, context: context) {
                        candidates.append(inferred)
                    }
                }
            }
            // Conflicting same-day clocks are still a question, even if one
            // source happens to sort first. Identical observations are harmless.
            let signatures = Set(candidates.compactMap { $0.date?.ISO8601Format() })
            guard signatures.count == 1, var event = candidates.first,
                  let date = event.date, !event.dateOnly,
                  !cancellations.contains(where: { $0.matches(event: event) }) else { continue }
            let ends = Set(candidates.compactMap(\.endsAt))
            event.endsAt = ends.count == 1 ? ends.first : nil
            event.id = "local-meeting:" + CanvasClient.hash(source.id + ":" + subtype.rawValue + ":" + date.ISO8601Format())
            event.title = label(subtype); event.sourceTitle = source.title
            event.courseID = source.courseID; event.sourceID = source.id; event.sourceURL = source.url
            event.subtype = subtype; event.state = .approved; event.curationVersion = EventCuration.version
            event.observedSourceDate = date; event.observedSourceDateOnly = false
            event.observedSourceTimeZone = event.timeZone; event.observedSourceEndsAt = event.endsAt
            recovered.append(event)
        }
        return recovered.sorted { ($0.date ?? .distantPast, $0.id) < ($1.date ?? .distantPast, $1.id) }
    }

    /// Only a proved, same-source/type/day repair resolves a cached relative-date
    /// question. Other details, task parts, and failures remain visible.
    public static func unresolvedIssues(_ issues: [String], source: SourceDocument, course: Course,
                                        recoveredEvents: [AcademicEvent]) -> [String] {
        guard let context = context(source, course: course) else { return issues }
        let cancellations = CancellationEvidence.extract(source: source, course: course)
        return issues.filter { issue in
            guard isDateQuestion(issue), !hasOtherEvent(issue),
                  !EventCuration.matches(#"\b(?:location|room|venue|link)\b"#, issue), let subtype = meetingType(issue),
                  let phrases = relativePhrases(issue), !phrases.isEmpty else { return true }
            if EventCuration.matches(#"\bcancell?ation\b|\bcancel(?:led|ed)\b|\bno\s+(?:lecture|recitation|class|lab)\b"#, issue) {
                return !phrases.allSatisfy { phrase in
                    var query = source; query.title = ""; query.text = "No " + label(subtype) + " " + phrase
                    let queried = CancellationEvidence.extract(source: query, course: course)
                    return !queried.isEmpty && queried.allSatisfy { wanted in
                        cancellations.contains { $0.subtype == wanted.subtype && $0.start == wanted.start && $0.end == wanted.end }
                    }
                }
            }
            var query = source; query.title = label(subtype); query.text = phrases.map { label(subtype) + " " + $0 }.joined(separator: "\n")
            let days = relativeObservations(query, course: course, context: context).compactMap(\.date)
            guard days.count == phrases.count else { return true }
            return !days.allSatisfy { day in recoveredEvents.contains {
                $0.sourceID == source.id && $0.courseID == source.courseID && $0.kind == .session && !$0.dateOnly &&
                    $0.state != .rejected && $0.subtype == subtype && $0.date.map { context.calendar.isDate($0, inSameDayAs: day) } == true
            } }
        }
    }

    private struct Context { let year: Int; let zone: String; let calendar: Calendar }

    private static func context(_ source: SourceDocument, course: Course) -> Context? {
        guard source.kind == .announcement, source.courseID == course.id, let published = source.publishedAt,
              let zone = (course.timeZone ?? source.curationTimeZone).flatMap(TimeZone.init(identifier:)) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let year = course.term?.academicYear ?? source.curationYear ?? calendar.component(.year, from: published)
        return Context(year: year, zone: zone.identifier, calendar: calendar)
    }

    private static func relativeObservations(_ source: SourceDocument, course: Course, context: Context) -> [AcademicEvent] {
        guard source.kind == .announcement, source.courseID == course.id, source.publishedAt != nil else { return [] }
        let cancellations = CancellationEvidence.extract(source: source, course: course)
        let headingType = meetingType(source.title)
        var observations: [AcademicEvent] = []
        for evidence in CurationContext.resolvedMeetingEvidence(source: source, course: course) {
            let prefix = source.title + " — "
            let body = evidence.hasPrefix(prefix) ? String(evidence.dropFirst(prefix.count)) : evidence
            for statement in statements(body) {
                guard !hasOtherEvent(statement), !isUncertainOrCancelled(statement),
                      let subtype = meetingType(statement) ?? headingType,
                      EvidenceClock.values(in: statement).count <= 1 || hasClockRange(statement) else { continue }
                let excerpt = label(subtype) + " — " + statement
                var fragment = source; fragment.text = excerpt
                for var event in RuleExtractor.extract(source: fragment, year: context.year, timeZone: context.zone) {
                    guard event.kind == .session, let date = event.date,
                          abs(context.calendar.component(.year, from: date) - context.year) <= 1,
                          RuleExtractor.evidenceSupports(date: date, dateOnly: event.dateOnly, timeZone: context.zone,
                                                         year: context.year, evidence: statement, kind: .session) else { continue }
                    event.subtype = subtype
                    guard !cancellations.contains(where: { $0.matches(event: event) }) else { continue }
                    event.evidence = evidence
                    if !event.dateOnly { event.endsAt = endDate(statement, start: date, context: context) }
                    observations.append(event)
                }
            }
        }
        return observations
    }

    private static func titleClockCandidates(_ source: SourceDocument, anchor: AcademicEvent, context: Context) -> [AcademicEvent] {
        // A title such as “Recitation today” can qualify the body's explicit
        // time, but never a second date, another meeting type, or a task clock.
        guard let subtype = anchor.subtype, meetingType(source.title) == subtype,
              relativePhrases(source.title)?.isEmpty == false, let date = anchor.date else { return [] }
        var output: [AcademicEvent] = []
        for statement in statements(source.text) {
            guard !hasOtherEvent(statement), !isUncertainOrCancelled(statement),
                  !EventCuration.matches(#"\b(?:today|tomorrow|yesterday|next|this|20\d\d-\d\d-\d\d|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|January|February|March|April|May|June|July|August|September|October|November|December)\b|\b\d{1,2}/\d{1,2}\b"#, statement),
                  meetingType(statement).map({ $0 == subtype }) ?? true,
                  !EvidenceClock.values(in: statement).isEmpty,
                  EvidenceClock.values(in: statement).count == 1 || hasClockRange(statement) else { continue }
            var fragment = source; fragment.text = label(subtype) + " " + dayKey(date, context.calendar) + " — " + statement
            for var event in RuleExtractor.extract(source: fragment, year: context.year, timeZone: context.zone) where event.kind == .session && !event.dateOnly {
                guard let start = event.date, RuleExtractor.evidenceSupports(date: start, dateOnly: false, timeZone: context.zone,
                                                                            year: context.year, evidence: fragment.text, kind: .session) else { continue }
                event.subtype = subtype; event.evidence = anchor.evidence + "\n" + statement
                event.endsAt = endDate(statement, start: start, context: context); output.append(event)
            }
        }
        return output
    }

    private static func verifiedOfficial(_ event: AcademicEvent, source: SourceDocument, context: Context) -> AcademicEvent? {
        guard let date = event.date, let subtype = event.subtype else { return nil }
        let parts = context.calendar.dateComponents([.hour, .minute], from: date)
        let clock = String(format: "%02d:%02d", parts.hour!, parts.minute!)
        let line = label(subtype) + " " + dayKey(date, context.calendar) + " at " + clock
        var fragment = source; fragment.text = line
        guard var checked = RuleExtractor.extract(source: fragment, year: context.year, timeZone: context.zone).first,
              !checked.dateOnly, checked.date == date,
              RuleExtractor.evidenceSupports(date: date, dateOnly: false, timeZone: context.zone, year: context.year, evidence: line, kind: .session) else { return nil }
        checked.subtype = subtype; checked.endsAt = event.endsAt
        checked.evidence = line + "\n[Verified timetable observation]\n" + event.evidence
        return checked
    }

    private static func uniqueOfficialSlot(source: SourceDocument, anchor: AcademicEvent,
                                           relatedSources: [SourceDocument], context: Context) -> AcademicEvent? {
        guard let day = anchor.date, let subtype = anchor.subtype, subtype != .classMeeting else { return nil }
        var slots: [(SourceDocument, AcademicEvent)] = []
        for related in relatedSources where related.courseID == source.courseID && related.id != source.id {
            for event in related.meetingSchedule ?? [] where event.courseID == source.courseID && event.kind == .session &&
                event.state != .rejected && event.importUndone != true && event.curationExcluded != true {
                guard let date = event.date, context.calendar.isDate(date, inSameDayAs: day) else { continue }
                slots.append((related, event))
            }
        }
        // The announcement supplies the type; the one official occurrence
        // supplies its clock. A second row, even at the same clock, may denote
        // another section. A known lecture is never relabeled as recitation.
        guard slots.count == 1, let (related, slot) = slots.first,
              resolvedSubtype(slot) == .classMeeting, slot.state == .approved, !slot.dateOnly, !slot.userEdited,
              slot.timeZone == context.zone,
              meetingType(slot.title).map({ $0 == .classMeeting || $0 == subtype }) ?? true else { return nil }
        var typed = slot; typed.subtype = subtype
        guard var verified = verifiedOfficial(typed, source: related, context: context) else { return nil }
        verified.evidence = "[The announcement names the meeting type; this is the only official course meeting on this local date.]\n" + verified.evidence
        return attributed(verified, to: source, anchor: anchor, related: related)
    }

    private static func attributed(_ event: AcademicEvent, to source: SourceDocument, anchor: AcademicEvent, related: SourceDocument) -> AcademicEvent {
        var result = event
        result.sourceID = source.id; result.sourceURL = source.url; result.relatedSourceIDs = [related.id]
        result.evidence = anchor.evidence + "\n[Same-course, same-type, same-day time evidence; source: " + related.id + "]\n" +
            (related.url.map { $0 + "\n" } ?? "") + event.evidence
        return result
    }

    private static func endDate(_ statement: String, start: Date, context: Context) -> Date? {
        let clocks = EvidenceClock.values(in: statement)
        guard clocks.count == 2, hasClockRange(statement) else { return nil }
        let text = label(.classMeeting) + " " + dayKey(start, context.calendar) + " at " + String(format: "%02d:%02d", clocks[1].0, clocks[1].1)
        let fragment = SourceDocument(courseID: "validation", title: "Class", text: text)
        guard let end = RuleExtractor.extract(source: fragment, year: context.year, timeZone: context.zone).first?.date,
              end > start, context.calendar.isDate(start, inSameDayAs: end) else { return nil }
        return end
    }

    private static func key(_ event: AcademicEvent, calendar: Calendar) -> String {
        (event.subtype?.rawValue ?? "") + ":" + event.date.map { dayKey($0, calendar) }!
    }
    private static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    private static func statements(_ text: String) -> [String] {
        text.replacingOccurrences(of: #"(?<=[.!?])\s+(?=[A-Za-z0-9])"#, with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private static func meetingType(_ text: String) -> EventSubtype? {
        let types: [(String, EventSubtype)] = [(#"\brecitation\b"#, .recitation), (#"\blecture\b"#, .lecture),
                                             (#"\blab(?:oratory)?\b"#, .lab), (#"\bseminar\b"#, .seminar), (#"\bdemo\b"#, .demo)]
        let found = types.filter { EventCuration.matches($0.0, text) }
        if found.count == 1 { return found[0].1 }
        return found.isEmpty && EventCuration.matches(#"\bclass\b"#, text) ? .classMeeting : nil
    }
    private static func label(_ subtype: EventSubtype) -> String { subtype == .classMeeting ? "Class" : subtype.rawValue.capitalized }
    private static func resolvedSubtype(_ event: AcademicEvent) -> EventSubtype? {
        event.subtype ?? EventCuration.subtype(for: event.sourceTitle ?? event.title, kind: event.kind)
    }
    private static func hasOtherEvent(_ text: String) -> Bool {
        EventCuration.matches(#"\b(?:homework|assignment|project|due|deadline|submission|submit|quiz|exam|midterm|office\s+hours|part\s+\d+)\b"#, text)
    }
    private static func isUncertainOrCancelled(_ text: String) -> Bool {
        EventCuration.matches(#"\bcancel(?:led|ed|lation)?\b|\bno\s+(?:scheduled\s+)?(?:lecture|recitation|class|lab)\b|\b(?:might|may|could|if|unless|whether|not\s+meet|will\s+not|won't)\b"#, text)
    }
    private static func hasClockRange(_ text: String) -> Bool {
        let clocks = EvidenceClock.values(in: text)
        guard clocks.count == 2 else { return false }
        let withoutDates = text.replacingOccurrences(of: #"\b20\d{2}-\d{2}-\d{2}\b"#, with: "", options: .regularExpression)
        let normalized = withoutDates.replacingOccurrences(of: #"(?i)(?<![a-z])([ap])\s*\.\s*m\.?(?![a-z])"#,
                                                            with: "$1M", options: .regularExpression)
        let pattern = #"(?<![\d:])\d{1,2}(?::\d{2})?\s*(?:AM|PM)?\s*(?:[-–—]|to)\s*\d{1,2}(?::\d{2})?\s*(?:AM|PM)?(?![\d:])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return false }
        return regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).contains { match in
            guard let range = Range(match.range, in: normalized) else { return false }
            let endpoints = EvidenceClock.values(in: String(normalized[range]))
            return endpoints.count == 2 && endpoints[0] == clocks[0] && endpoints[1] == clocks[1]
        }
    }
    private static func isDateQuestion(_ text: String) -> Bool {
        EventCuration.matches(#"(?:missing|without|no|not|unclear|unspecified|unknown|unresolved).{0,45}\bdate\b|\bdate\b.{0,45}(?:missing|clarif|not|unknown|unclear|unspecified|unresolved)|relative\s+(?:date|time)"#, text)
    }
    private static func relativePhrases(_ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(today|tomorrow|yesterday|this\s+(?:week|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday))\b"#, options: .caseInsensitive) else { return nil }
        return Array(Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]).lowercased() }
        })).sorted()
    }
}
