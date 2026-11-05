import Foundation

public enum Reconciler {
    /// A failed or partial fetch supplies fewer incoming records; absence never deletes history.
    public static func merge(existing: [AcademicEvent], incoming: [AcademicEvent]) -> [AcademicEvent] {
        var result = existing
        let lookup = MergeIndex(events: existing)
        let incomingKeys = incoming.map { SourceKey($0) }
        let incomingCounts = incomingKeys.reduce(into: [SourceKey: Int]()) { $0[$1, default: 0] += 1 }
        let legacyEditedSources = Set(existing.filter { $0.userEdited && $0.sourceTitle == nil }.compactMap(\.sourceID))
        for (offset, observation) in incoming.enumerated() {
            let sourceKey = incomingKeys[offset]
            let exact = lookup.exact(observation.id)
            // ICS UIDs are authoritative. Equal titles must never merge distinct
            // series or occurrences merely because they came from one feed.
            let fallback = observation.sourceSeriesID == nil && incomingCounts[sourceKey] == 1
                ? lookup.uniqueSource(sourceKey) : nil
            let canRecoverLegacy = observation.sourceID.map { legacyEditedSources.contains($0) } ?? false
            let legacyMatches = exact == nil && fallback == nil && canRecoverLegacy ? legacyEditedMatches(observation, in: result) : []
            let match = exact ?? fallback ?? (legacyMatches.count == 1 ? legacyMatches.first : nil)
            if let index = match {
                var current = result[index]
                if current.id.hasPrefix("canvas:"), !observation.id.hasPrefix("canvas:"), observation.curationVersion != nil,
                   current.category != nil, current.date != nil {
                    let sources = Array(Set((current.relatedSourceIDs ?? []) + [observation.sourceID].compactMap { $0 })).sorted()
                    if sources != current.relatedSourceIDs { current.relatedSourceIDs = sources; current.revision += 1 }
                    self.replace(&result, at: index, with: current, index: lookup)
                    continue
                }
                if current.importUndone == true {
                    // Background curation cannot undo the user's Undo Import.
                    if observation.curationVersion != nil { continue }
                    var retry = observation; retry.importUndone = nil
                    self.replace(&result, at: index, with: retry, index: lookup)
                    continue
                }
                current.sourceSeriesID = observation.sourceSeriesID ?? current.sourceSeriesID
                current.sourceTitle = observation.sourceTitle ?? current.sourceTitle
                if observation.id.hasPrefix("canvas:"), !current.id.hasPrefix("canvas:"), !current.userEdited,
                   observation.curationVersion != nil { current.id = observation.id }
                if current.state == .approved { current.wasApproved = true }
                let sourceChanged = current.observedSourceDate != observation.date || (current.observedSourceDateOnly ?? current.dateOnly) != observation.dateOnly || (current.observedSourceTimeZone ?? current.timeZone) != observation.timeZone || current.observedSourceEndsAt != observation.endsAt
                current.observedSourceDate = observation.date
                current.observedSourceDateOnly = observation.dateOnly
                current.observedSourceTimeZone = observation.timeZone
                current.observedSourceEndsAt = observation.endsAt
                if sourceChanged {
                    let automatic = observation.curationVersion != nil && observation.state == .approved && observation.date != nil && !current.userEdited && (current.state != .rejected || current.curationExcluded == true)
                    if (current.state == .pending && !current.userEdited) || automatic {
                        if automatic { current.previousDate = current.date }
                        current.date = observation.date
                        current.dateOnly = observation.dateOnly
                        current.timeZone = observation.timeZone
                        current.endsAt = observation.endsAt
                        if automatic {
                            current.state = .approved; current.wasApproved = true
                            current.proposedDate = nil; current.proposedDateOnly = nil; current.proposedTimeZone = nil; current.proposedEndsAt = nil
                        }
                    } else if current.state != .rejected {
                        current.previousDate = current.date
                        current.proposedDate = observation.date
                        current.proposedDateOnly = observation.dateOnly
                        current.proposedTimeZone = observation.timeZone
                        current.proposedEndsAt = observation.endsAt
                        current.state = .conflict
                    }
                    current.revision += 1
                }
                if !current.userEdited {
                    current.title = observation.title; current.kind = observation.kind; current.location = observation.location
                    current.subtype = observation.subtype ?? current.subtype
                    if observation.curationVersion != nil, observation.state == .approved,
                       current.state == .pending || current.curationExcluded == true {
                        current.state = .approved; current.wasApproved = true
                    }
                }
                current.curationVersion = observation.curationVersion ?? current.curationVersion
                if current.state == .approved { current.curationExcluded = nil }
                if observation.submission != current.submission, observation.submission != nil {
                    current.submission = observation.submission
                    current.completed = observation.completed || current.taskProgress == .done
                }
                current.evidence = observation.evidence
                current.sourceURL = observation.sourceURL
                if let planned = current.plannedStart, let due = current.date, planned > due {
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(identifier: current.timeZone) ?? .gmt
                    if !current.dateOnly || !calendar.isDate(planned, inSameDayAs: due) { current.plannedStart = nil }
                }
                if current != result[index], current.revision == result[index].revision { current.revision += 1 }
                self.replace(&result, at: index, with: current, index: lookup)
            } else {
                var candidate = observation
                if legacyMatches.count > 1 {
                    candidate.state = .conflict; candidate.wasApproved = false
                    candidate.proposedDate = observation.date
                    candidate.evidence = "Several edited occurrences match this source identity.\n\n" + observation.evidence
                    lookup.insert(candidate, at: result.count); result.append(candidate)
                    continue
                }
                let datedDuplicate = observation.curationVersion != nil ? lookup.datedDuplicate(observation, normalizedTitle: sourceKey.title) : nil
                let duplicateIndex = datedDuplicate ?? lookup.duplicate(observation, normalizedTitle: sourceKey.title)
                let duplicate = duplicateIndex.map { result[$0] }
                if let duplicate, let duplicateIndex, observation.curationVersion != nil,
                   !duplicate.userEdited, duplicate.sourceID != nil || duplicate.id.hasPrefix("canvas:"),
                   (datedDuplicate != nil || (duplicate.date == observation.date && duplicate.dateOnly == observation.dateOnly)) ||
                   (duplicate.id.hasPrefix("canvas:") && observation.category == .deadline) {
                    var combined = duplicate
                    combined.relatedSourceIDs = Array(Set((combined.relatedSourceIDs ?? []) + [observation.sourceID].compactMap { $0 })).sorted()
                    if combined.state == .pending { combined.state = .approved; combined.wasApproved = true }
                    combined.curationVersion = observation.curationVersion
                    if combined != duplicate { combined.revision += 1 }
                    self.replace(&result, at: duplicateIndex, with: combined, index: lookup)
                    continue
                }
                if let duplicate, observation.curationVersion == nil || (observation.category != .meeting && observation.sourceSeriesID == nil) {
                    candidate.state = .conflict
                    candidate.wasApproved = false
                    candidate.previousDate = duplicate.date
                    candidate.proposedDate = observation.date
                    candidate.evidence = "Possible duplicate: \(duplicate.title). Compare sources before approving.\n\n" + observation.evidence
                }
                lookup.insert(candidate, at: result.count)
                result.append(candidate)
            }
        }
        return result
    }

    private static func replace(_ result: inout [AcademicEvent], at position: Int, with event: AcademicEvent, index: MergeIndex) {
        index.replace(result[position], with: event, at: position)
        result[position] = event
    }
    private static func normalized(_ title: String) -> String {
        EventCuration.canonicalTitle(title)
    }

    /// Old archives did not retain a source title. Recover only when the stored
    /// ID proves the identity; never infer it from a user's custom display name.
    private static func legacyEditedMatches(_ observation: AcademicEvent, in events: [AcademicEvent]) -> [Int] {
        guard observation.curationVersion != nil, let source = observation.sourceID else { return [] }
        let possible = events.indices.filter { index in
            let event = events[index]
            return event.userEdited && event.sourceTitle == nil && event.sourceID == source &&
                event.courseID == observation.courseID && event.academicCalendarID == observation.academicCalendarID &&
                (event.id.hasPrefix("model:") || event.id.hasPrefix("document-"))
        }
        guard !possible.isEmpty else { return [] }
        let sourceTitle = observation.sourceTitle ?? observation.title
        let oldTitle = sourceTitle.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        let oldIdentity = oldTitle + ":" + observation.kind.rawValue
        var provenIDs = Set<String>()
        for ordinal in 0..<300 {
            provenIDs.insert("model:" + CanvasClient.hash(source + ":" + oldIdentity + ":\(ordinal)"))
            provenIDs.insert("document-" + DocumentReader.fingerprint(source + "|" + oldTitle + "|\(ordinal)"))
        }
        for index in possible {
            if let oldDate = events[index].observedSourceDate {
                provenIDs.insert("model:" + CanvasClient.hash(source + ":" + normalized(sourceTitle) + ":" + observation.kind.rawValue + ":" + oldDate.ISO8601Format()))
            }
        }
        return possible.filter { provenIDs.contains(events[$0].id) }
    }
}

private extension Reconciler {
    struct OwnerKey: Hashable {
        var courseID: String
        var calendarID: String?
        init(_ event: AcademicEvent) { courseID = event.courseID; calendarID = event.academicCalendarID }
    }
    struct SourceKey: Hashable {
        var owner: OwnerKey
        var sourceID: String?
        var title: String
        init(_ event: AcademicEvent) {
            owner = OwnerKey(event); sourceID = event.sourceID; title = normalized(event.sourceTitle ?? event.title)
        }
    }
    struct DuplicateKey: Hashable {
        var owner: OwnerKey
        var title: String
        var kind: String
        init(_ event: AcademicEvent, title: String) {
            owner = OwnerKey(event); self.title = title; kind = event.kind.rawValue
        }
    }
    struct DatedDuplicateKey: Hashable {
        var identity: DuplicateKey
        var instant: Date?
        var localDay: String?
        init(_ event: AcademicEvent, title: String) {
            identity = DuplicateKey(event, title: title)
            if event.dateOnly, let date = event.date {
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: event.timeZone) ?? .gmt
                let day = calendar.dateComponents([.year, .month, .day], from: date)
                localDay = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
                instant = nil
            } else { instant = event.date; localDay = nil }
        }
    }
    struct SourceIdentity: Hashable { var id: String? }

    /// Indexes track the evolving result, including title changes and import undo
    /// replacement. A later observation sees exactly what earlier ones changed.
    final class MergeIndex {
        var ids: [String: MinimumHeap<Int>] = [:]
        var sources: [SourceKey: Set<Int>] = [:]
        var duplicates: [DuplicateKey: DuplicateBucket] = [:]
        var datedDuplicates: [DatedDuplicateKey: DuplicateBucket] = [:]

        init(events: [AcademicEvent]) {
            for (position, event) in events.enumerated() { insert(event, at: position) }
        }
        func exact(_ id: String) -> Int? { ids[id]?.minimum }
        func uniqueSource(_ key: SourceKey) -> Int? {
            guard key.sourceID != nil, let matches = sources[key], matches.count == 1 else { return nil }
            return matches.first
        }
        func duplicate(_ event: AcademicEvent, normalizedTitle: String) -> Int? {
            duplicates[DuplicateKey(event, title: normalizedTitle)]?
                .first(excluding: SourceIdentity(id: event.sourceID), canvasOnly: event.id.hasPrefix("canvas:"))
        }
        func datedDuplicate(_ event: AcademicEvent, normalizedTitle: String) -> Int? {
            guard event.date != nil else { return nil }
            return datedDuplicates[DatedDuplicateKey(event, title: normalizedTitle)]?
                .first(excluding: SourceIdentity(id: event.sourceID), canvasOnly: event.id.hasPrefix("canvas:"))
        }
        func insert(_ event: AcademicEvent, at position: Int) {
            let idsForEvent = ids[event.id] ?? MinimumHeap<Int>()
            idsForEvent.set(position, priority: position); ids[event.id] = idsForEvent
            let key = SourceKey(event)
            if key.sourceID != nil { sources[key, default: []].insert(position) }
            if event.state != .rejected {
                let duplicateKey = DuplicateKey(event, title: key.title)
                let bucket = duplicates[duplicateKey] ?? DuplicateBucket()
                bucket.insert(position, source: SourceIdentity(id: event.sourceID), canvas: event.id.hasPrefix("canvas:"))
                duplicates[duplicateKey] = bucket
                if event.date != nil {
                    let datedKey = DatedDuplicateKey(event, title: key.title)
                    let datedBucket = datedDuplicates[datedKey] ?? DuplicateBucket()
                    datedBucket.insert(position, source: SourceIdentity(id: event.sourceID), canvas: event.id.hasPrefix("canvas:"))
                    datedDuplicates[datedKey] = datedBucket
                }
            }
        }
        func replace(_ old: AcademicEvent, with new: AcademicEvent, at position: Int) {
            guard old.id != new.id || old.sourceID != new.sourceID || old.courseID != new.courseID ||
                    old.academicCalendarID != new.academicCalendarID || old.title != new.title || old.sourceTitle != new.sourceTitle || old.userEdited != new.userEdited || old.kind != new.kind || old.date != new.date || old.dateOnly != new.dateOnly || old.timeZone != new.timeZone ||
                    (old.state == .rejected) != (new.state == .rejected) else { return }
            ids[old.id]?.remove(position)
            if ids[old.id]?.minimum == nil { ids.removeValue(forKey: old.id) }
            let oldKey = SourceKey(old)
            if oldKey.sourceID != nil {
                sources[oldKey]?.remove(position)
                if sources[oldKey]?.isEmpty == true { sources.removeValue(forKey: oldKey) }
            }
            let duplicateKey = DuplicateKey(old, title: oldKey.title)
            if old.state != .rejected {
                duplicates[duplicateKey]?.remove(position, source: SourceIdentity(id: old.sourceID), canvas: old.id.hasPrefix("canvas:"))
                if duplicates[duplicateKey]?.isEmpty == true { duplicates.removeValue(forKey: duplicateKey) }
                let datedKey = DatedDuplicateKey(old, title: oldKey.title)
                datedDuplicates[datedKey]?.remove(position, source: SourceIdentity(id: old.sourceID), canvas: old.id.hasPrefix("canvas:"))
                if datedDuplicates[datedKey]?.isEmpty == true { datedDuplicates.removeValue(forKey: datedKey) }
            }
            insert(new, at: position)
        }
    }

    final class DuplicateBucket {
        let all = SourceMinima()
        let nonCanvas = SourceMinima()
        var isEmpty: Bool { all.isEmpty }
        func insert(_ position: Int, source: SourceIdentity, canvas: Bool) {
            all.insert(position, source: source)
            if !canvas { nonCanvas.insert(position, source: source) }
        }
        func remove(_ position: Int, source: SourceIdentity, canvas: Bool) {
            all.remove(position, source: source)
            if !canvas { nonCanvas.remove(position, source: source) }
        }
        func first(excluding source: SourceIdentity, canvasOnly: Bool) -> Int? {
            (canvasOnly ? nonCanvas : all).first(excluding: source)
        }
    }

    /// The earliest event per source is enough: duplicate matching excludes only
    /// one source. Looking at the first two distinct sources avoids rescanning a
    /// large repeated course schedule for every occurrence.
    final class SourceMinima {
        var members: [SourceIdentity: MinimumHeap<Int>] = [:]
        let minima = MinimumHeap<SourceIdentity>()
        var isEmpty: Bool { minima.minimum == nil }
        func insert(_ position: Int, source: SourceIdentity) {
            let heap = members[source] ?? MinimumHeap<Int>()
            heap.set(position, priority: position); members[source] = heap
            if let first = heap.minimum { minima.set(source, priority: first) }
        }
        func remove(_ position: Int, source: SourceIdentity) {
            guard let heap = members[source] else { return }
            heap.remove(position)
            if let first = heap.minimum { minima.set(source, priority: first) }
            else { members.removeValue(forKey: source); minima.remove(source) }
        }
        func first(excluding source: SourceIdentity) -> Int? { minima.minimum(excluding: source) }
    }

    /// Small indexed heap: insert, replacement and removal are O(log n), and
    /// excluding the root key requires only its two children. No stale entries.
    final class MinimumHeap<Key: Hashable> {
        struct Node { var key: Key; var priority: Int }
        var nodes: [Node] = []
        var positions: [Key: Int] = [:]
        var minimum: Int? { nodes.first?.priority }
        func minimum(excluding key: Key) -> Int? {
            guard let first = nodes.first else { return nil }
            guard first.key == key else { return first.priority }
            return nodes.indices.dropFirst().prefix(2).map { nodes[$0].priority }.min()
        }
        func set(_ key: Key, priority: Int) {
            if let position = positions[key] {
                let old = nodes[position].priority
                nodes[position].priority = priority
                if priority < old { up(position) } else if priority > old { down(position) }
            } else {
                positions[key] = nodes.count
                nodes.append(Node(key: key, priority: priority))
                up(nodes.count - 1)
            }
        }
        func remove(_ key: Key) {
            guard let position = positions.removeValue(forKey: key) else { return }
            let last = nodes.removeLast()
            guard position < nodes.count else { return }
            nodes[position] = last; positions[last.key] = position
            if position > 0, nodes[position].priority < nodes[(position - 1) / 2].priority { up(position) }
            else { down(position) }
        }
        func up(_ start: Int) {
            var position = start
            while position > 0 {
                let parent = (position - 1) / 2
                guard nodes[position].priority < nodes[parent].priority else { break }
                swap(position, parent); position = parent
            }
        }
        func down(_ start: Int) {
            var position = start
            while position * 2 + 1 < nodes.count {
                var child = position * 2 + 1
                if child + 1 < nodes.count, nodes[child + 1].priority < nodes[child].priority { child += 1 }
                guard nodes[child].priority < nodes[position].priority else { break }
                swap(position, child); position = child
            }
        }
        func swap(_ a: Int, _ b: Int) {
            nodes.swapAt(a, b)
            positions[nodes[a].key] = a; positions[nodes[b].key] = b
        }
    }
}
