import Foundation

/// Joins the same identified deliverable across Canvas and syllabus sources.
/// The API owns its effective deadline; observations and user edits stay stored.
enum DeadlineReconciliation {
    static func project(events: [AcademicEvent], sources: [SourceDocument]) -> [AcademicEvent] {
        let sourceByID = sources.reduce(into: [String: SourceDocument]()) { $0[$1.id] = $1 }
        var groups: [String: [AcademicEvent]] = [:]
        for event in events {
            guard event.category == .deadline, event.state == .approved, !event.userEdited, event.date != nil,
                  event.importUndone != true, event.curationExcluded != true, event.academicCalendarID == nil,
                  let sourceID = event.sourceID, let source = sourceByID[sourceID],
                  source.courseID == event.courseID,
                  event.id.hasPrefix("canvas:") || isCuratedObservation(event) else { continue }
            guard event.curationVersion != nil || (event.id.hasPrefix("canvas:") && source.kind == .assignment && source.effectiveDueAt == event.date) else { continue }
            let heading = SourceDocument(courseID: event.courseID, title: event.title, text: "", kind: .assignment)
            let identity = CurationContext.assignmentIdentity(heading) ?? (source.kind == .assignment ? CurationContext.assignmentIdentity(source) : nil)
            guard let identity else { continue }
            groups[event.courseID + "|" + event.kind.rawValue + "|" + identity, default: []].append(event)
        }
        var replacements: [String: AcademicEvent] = [:], retired = Set<String>()
        for group in groups.values where group.count > 1 {
            let native = group.filter { $0.id.hasPrefix("canvas:") && sourceByID[$0.sourceID!]?.kind == .assignment && sourceByID[$0.sourceID!]?.effectiveDueAt == $0.date }
            if native.count > 1 { continue }
            let canonical = native.first ?? group.sorted { $0.id < $1.id }.first!
            if native.isEmpty, Set(group.compactMap(\.sourceID)).count == group.count,
               Set(group.map(\.timeZone)).count == 1, Set(group.map(\.dateOnly)).count == 1,
               Set(group.compactMap(\.date)).count == 2,
               group.allSatisfy({ sourceByID[$0.sourceID!]?.kind == .syllabus }),
               let alternative = group.first(where: { $0.date != canonical.date }) {
                var conflict = combine(canonical, with: group)
                conflict.state = .conflict; conflict.wasApproved = false
                conflict.proposedDate = alternative.date; conflict.proposedDateOnly = alternative.dateOnly
                conflict.proposedTimeZone = alternative.timeZone
                replacements[canonical.id] = conflict
                retired.formUnion(group.filter { $0.id != canonical.id }.map(\.id))
                continue
            }
            let copies = group.filter { candidate in
                guard candidate.id != canonical.id, candidate.sourceID != canonical.sourceID,
                      isCuratedObservation(candidate), let source = sourceByID[candidate.sourceID!],
                      let date = candidate.date, let target = canonical.date else { return false }
                if native.count == 1, source.kind == .syllabus { return true }
                guard candidate.timeZone == canonical.timeZone else { return false }
                if candidate.dateOnly == canonical.dateOnly { return date == target }
                guard native.count == 1, candidate.dateOnly, let zone = TimeZone(identifier: canonical.timeZone) else { return false }
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
                return calendar.isDate(date, inSameDayAs: target)
            }
            guard !copies.isEmpty else { continue }
            let joined = [canonical] + copies
            // Two separate interpretations within one source are ambiguous.
            guard Set(joined.compactMap(\.sourceID)).count == joined.count else { continue }
            var combined = combine(canonical, with: joined)
            if combined.releasedAt == nil {
                let releases = Set(joined.compactMap(\.releasedAt))
                if releases.count == 1, let release = releases.first, release <= combined.date! {
                    combined.releasedAt = release
                    combined.releaseDateOnly = joined.first(where: { $0.releasedAt == release })?.releaseDateOnly
                }
            }
            replacements[canonical.id] = combined
            retired.formUnion(copies.map(\.id))
        }
        return events.filter { !retired.contains($0.id) }.map { replacements[$0.id] ?? $0 }
    }
    private static func isCuratedObservation(_ event: AcademicEvent) -> Bool {
        // Recuration preserves the legacy document ID when matching an old
        // observation; its validated curation version identifies that result.
        event.curationVersion != nil && (event.id.hasPrefix("model:") || event.id.hasPrefix("document-"))
    }
    private static func combine(_ canonical: AcademicEvent, with observations: [AcademicEvent]) -> AcademicEvent {
        var combined = canonical
        combined.relatedEventIDs = Array(Set(observations.flatMap { ($0.relatedEventIDs ?? []) + [$0.id] }).subtracting([canonical.id])).sorted()
        combined.relatedSourceIDs = Array(Set(observations.flatMap { ($0.relatedSourceIDs ?? []) + [$0.sourceID].compactMap { $0 } }).subtracting([canonical.sourceID!])).sorted()
        return combined
    }
}
