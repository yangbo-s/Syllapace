import Foundation

public enum Reconciler {
    /// A failed or partial fetch supplies fewer incoming records; absence never deletes history.
    public static func merge(existing: [AcademicEvent], incoming: [AcademicEvent]) -> [AcademicEvent] {
        var result = existing
        let lookup = MergeIndex(events: existing)
        let incomingKeys = incoming.map { SourceKey($0) }
        let incomingCounts = incomingKeys.reduce(into: [SourceKey: Int]()) { $0[$1, default: 0] += 1 }
        for (offset, observation) in incoming.enumerated() {
            let sourceKey = incomingKeys[offset]
            let exact = lookup.exact(observation.id)
            // ICS UIDs are authoritative. Equal titles must never merge distinct
            // series or occurrences merely because they came from one feed.
            let fallback = observation.sourceSeriesID == nil && incomingCounts[sourceKey] == 1
                ? lookup.uniqueSource(sourceKey) : nil
            let match = exact ?? fallback
            if let index = match {
                var current = result[index]
                if current.importUndone == true {
                    var retry = observation; retry.importUndone = nil
                    self.replace(&result, at: index, with: retry, index: lookup)
                    continue
                }
                current.sourceSeriesID = observation.sourceSeriesID ?? current.sourceSeriesID
                if current.state == .approved { current.wasApproved = true }
                let sourceChanged = current.observedSourceDate != observation.date || (current.observedSourceDateOnly ?? current.dateOnly) != observation.dateOnly || (current.observedSourceTimeZone ?? current.timeZone) != observation.timeZone || current.observedSourceEndsAt != observation.endsAt
                current.observedSourceDate = observation.date
                current.observedSourceDateOnly = observation.dateOnly
                current.observedSourceTimeZone = observation.timeZone
                current.observedSourceEndsAt = observation.endsAt
                if sourceChanged {
                    if current.state == .pending && !current.userEdited {
                        current.date = observation.date
                        current.dateOnly = observation.dateOnly
                        current.timeZone = observation.timeZone
                        current.endsAt = observation.endsAt
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
                if !current.userEdited { current.title = observation.title; current.kind = observation.kind; current.location = observation.location }
                if observation.submission != current.submission, observation.submission != nil {
                    current.submission = observation.submission
                    current.completed = observation.completed
                }
                current.evidence = observation.evidence
                current.sourceURL = observation.sourceURL
                self.replace(&result, at: index, with: current, index: lookup)
            } else {
                var candidate = observation
                let duplicate = lookup.duplicate(observation, normalizedTitle: sourceKey.title).map { result[$0] }
                if let duplicate {
                    candidate.state = .conflict
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
        title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
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
            owner = OwnerKey(event); sourceID = event.sourceID; title = normalized(event.title)
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
    struct SourceIdentity: Hashable { var id: String? }

    /// Indexes track the evolving result, including title changes and import undo
    /// replacement. A later observation sees exactly what earlier ones changed.
    final class MergeIndex {
        var ids: [String: MinimumHeap<Int>] = [:]
        var sources: [SourceKey: Set<Int>] = [:]
        var duplicates: [DuplicateKey: DuplicateBucket] = [:]

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
            }
        }
        func replace(_ old: AcademicEvent, with new: AcademicEvent, at position: Int) {
            guard old.id != new.id || old.sourceID != new.sourceID || old.courseID != new.courseID ||
                    old.academicCalendarID != new.academicCalendarID || old.title != new.title || old.kind != new.kind ||
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
