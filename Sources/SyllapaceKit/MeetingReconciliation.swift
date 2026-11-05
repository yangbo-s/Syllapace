import Foundation

/// A display/export projection. Original observations remain in the archive.
public enum MeetingReconciliation {
    public static func project(events: [AcademicEvent], canonicalSourceIDs: Set<String> = [],
                               sectionsByEventID: [String: String] = [:]) -> [AcademicEvent] {
        var slots: [OccurrenceSlot: [(Int, AcademicEvent, OccurrenceKey)]] = [:]
        var projected: [(Int, AcademicEvent)] = []
        for (index, event) in events.enumerated() {
            guard let key = occurrenceKey(event, canonicalSourceIDs: canonicalSourceIDs,
                                          explicitSection: sectionsByEventID[event.id]) else {
                projected.append((index, event)); continue
            }
            slots[key.slot, default: []].append((index, event, key))
        }
        var buckets: [OccurrenceKey: [(Int, AcademicEvent)]] = [:]
        for entries in slots.values {
            for entry in entries {
                var key = entry.2
                if key.subtype == EventSubtype.classMeeting.rawValue {
                    let compatibleTypes = Set(entries.compactMap { other -> String? in
                        guard other.2.subtype != EventSubtype.classMeeting.rawValue,
                              other.1.sourceID != entry.1.sourceID, compatible(entry.1, other.1) else { return nil }
                        return other.2.subtype
                    })
                    // Registrar rows can omit lecture/recitation labels. They
                    // may adopt one proven subtype, never bridge two of them.
                    if compatibleTypes.count == 1, let subtype = compatibleTypes.first { key.subtype = subtype }
                }
                buckets[key, default: []].append((entry.0, entry.1))
            }
        }
        for (key, entries) in buckets {
            let sourceCounts = entries.reduce(into: [String: Int]()) { counts, entry in
                counts[entry.1.sourceID!, default: 0] += 1
            }
            // If one source itself names two meetings at this instant, another
            // source cannot prove which one it describes. Keep that ambiguity.
            guard sourceCounts.values.allSatisfy({ $0 == 1 }) else {
                projected += entries; continue
            }
            let ends = Set(entries.compactMap { $0.1.endsAt })
            let locations = Set(entries.compactMap { normalizedLocation($0.1.location) })
            var groups: [[(Int, AcademicEvent)]] = []
            for entry in entries.sorted(by: { preferred($0.1, over: $1.1, canonicalSourceIDs: canonicalSourceIDs) }) {
                let event = entry.1
                // A missing value must not bridge two conflicting concrete
                // durations or rooms and silently turn them into one meeting.
                guard !(event.endsAt == nil && ends.count > 1),
                      !(normalizedLocation(event.location) == nil && locations.count > 1) else {
                    projected.append(entry); continue
                }
                let matches = groups.indices.filter { index in
                    groups[index].allSatisfy { compatible(event, $0.1) }
                }
                if matches.count == 1 { groups[matches[0]].append(entry) }
                else { groups.append([entry]) }
            }
            for group in groups {
                guard var combined = group.first?.1, let position = group.map(\.0).min() else { continue }
                guard group.count > 1 else { projected.append((position, combined)); continue }
                if combined.endsAt == nil { combined.endsAt = group.compactMap { $0.1.endsAt }.first }
                if normalizedLocation(combined.location) == nil { combined.location = group.compactMap { $0.1.location }.first }
                if meetingSubtype(combined) == .classMeeting, key.subtype != EventSubtype.classMeeting.rawValue,
                   let specific = group.first(where: { meetingSubtype($0.1)?.rawValue == key.subtype }) {
                    combined.subtype = EventSubtype(rawValue: key.subtype)
                    combined.title = specific.1.title
                }
                // Keep the authoritative identity and URL, while a linked
                // announcement can supply the specific topic for this week.
                if let detailed = group.map(\.1).max(by: { titleDetail($0.title) < titleDetail($1.title) }),
                   titleDetail(detailed.title) > titleDetail(combined.title) {
                    combined.title = detailed.title
                }
                var sources = Set(group.flatMap { ($0.1.relatedSourceIDs ?? []) + [$0.1.sourceID].compactMap { $0 } })
                if let primary = combined.sourceID { sources.remove(primary) }
                combined.relatedSourceIDs = sources.sorted()
                var aliases = Set(group.flatMap { ($0.1.relatedEventIDs ?? []) + [$0.1.id] })
                aliases.remove(combined.id)
                combined.relatedEventIDs = aliases.sorted()
                projected.append((position, combined))
            }
        }
        return projected.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private struct OccurrenceKey: Hashable {
        var course: String
        var subtype: String
        var start: Date
        var timeZone: String
        var section: String?
        var slot: OccurrenceSlot { OccurrenceSlot(course: course, start: start, timeZone: timeZone, section: section) }
    }
    private struct OccurrenceSlot: Hashable {
        var course: String
        var start: Date
        var timeZone: String
        var section: String?
    }

    private static func occurrenceKey(_ event: AcademicEvent, canonicalSourceIDs: Set<String>, explicitSection: String?) -> OccurrenceKey? {
        guard event.kind == .session, event.state == .approved, !event.userEdited,
              event.importUndone != true, event.curationExcluded != true, event.academicCalendarID == nil,
              event.curationVersion != nil, let source = event.sourceID,
              let start = event.date, !event.dateOnly, event.endsAt.map({ $0 > start }) ?? true else { return nil }
        if let series = event.sourceSeriesID,
           !series.hasPrefix("model-series:"), !series.hasPrefix("schedule:"), !series.hasPrefix("canvas-series:"), !canonicalSourceIDs.contains(source) {
            return nil
        }
        guard let subtype = meetingSubtype(event), [.lecture, .recitation, .lab, .demo, .seminar, .classMeeting].contains(subtype) else { return nil }
        let titleSection = section(in: event.title)
        let suppliedSection = explicitSection.map(normalized).flatMap { $0.isEmpty ? nil : $0 }
        if let titleSection, let suppliedSection, titleSection != suppliedSection { return nil }
        return OccurrenceKey(course: event.courseID, subtype: subtype.rawValue, start: start, timeZone: event.timeZone,
                             section: suppliedSection ?? titleSection)
    }

    private static func meetingSubtype(_ event: AcademicEvent) -> EventSubtype? {
        let inferred = EventCuration.subtype(for: event.sourceTitle ?? event.title, kind: .session)
        return inferred == .classMeeting ? event.subtype ?? inferred : inferred
    }

    private static func compatible(_ first: AcademicEvent, _ second: AcademicEvent) -> Bool {
        if let a = first.endsAt, let b = second.endsAt, a != b { return false }
        if let a = normalizedLocation(first.location), let b = normalizedLocation(second.location), a != b { return false }
        return true
    }

    private static func preferred(_ first: AcademicEvent, over second: AcademicEvent, canonicalSourceIDs: Set<String>) -> Bool {
        let a = first.sourceID.map(canonicalSourceIDs.contains) ?? false
        let b = second.sourceID.map(canonicalSourceIDs.contains) ?? false
        if a != b { return a }
        if (first.endsAt != nil) != (second.endsAt != nil) { return first.endsAt != nil }
        if (normalizedLocation(first.location) != nil) != (normalizedLocation(second.location) != nil) {
            return normalizedLocation(first.location) != nil
        }
        return first.id < second.id
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
    private static func normalizedLocation(_ text: String?) -> String? {
        text.map(normalized).flatMap { $0.isEmpty ? nil : $0 }
    }
    private static func section(in title: String) -> String? {
        let patterns = [#"\b(?:section|sec\.?)\s*[:#-]?\s*([A-Za-z0-9]+)\b"#,
                        #"\b(?:recitation|lecture|lab|class|seminar)\s+([A-Za-z])(?:\s*$|\s*[·:–—-])"#]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = expression.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let range = Range(match.range(at: 1), in: title) else { continue }
            return normalized(String(title[range]))
        }
        return nil
    }
    private static func titleDetail(_ title: String) -> Int {
        let value = normalized(title).replacingOccurrences(of: #"^\d{2}[- ]?\d{3}(?:-[a-z])?\s*[:·–—-]?\s*"#, with: "", options: .regularExpression)
        let generic = #"^(?:normal )?(?:lecture|recitation|class|lab|seminar|demo)(?:\s+(?:section\s+)?[a-z0-9]+)?$"#
        return value.range(of: generic, options: .regularExpression) == nil ? value.count : 0
    }
}
