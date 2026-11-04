import Foundation

public enum Reconciler {
    /// A failed or partial fetch supplies fewer incoming records; absence never deletes history.
    public static func merge(existing: [AcademicEvent], incoming: [AcademicEvent]) -> [AcademicEvent] {
        var result = existing
        for observation in incoming {
            let exact = result.firstIndex { $0.id == observation.id }
            let sameSource = result.indices.filter {
                result[$0].sourceID != nil && result[$0].sourceID == observation.sourceID &&
                result[$0].courseID == observation.courseID && normalized(result[$0].title) == normalized(observation.title)
            }
            let incomingOccurrences = incoming.filter {
                $0.sourceID == observation.sourceID && $0.courseID == observation.courseID && normalized($0.title) == normalized(observation.title)
            }.count
            let match = exact ?? (sameSource.count == 1 && incomingOccurrences == 1 ? sameSource.first : nil)
            if let index = match {
                var current = result[index]
                if current.state == .approved { current.wasApproved = true }
                let sourceChanged = current.observedSourceDate != observation.date || (current.observedSourceDateOnly ?? current.dateOnly) != observation.dateOnly || (current.observedSourceTimeZone ?? current.timeZone) != observation.timeZone
                current.observedSourceDate = observation.date
                current.observedSourceDateOnly = observation.dateOnly
                current.observedSourceTimeZone = observation.timeZone
                if sourceChanged {
                    if current.state == .pending && !current.userEdited {
                        current.date = observation.date
                        current.dateOnly = observation.dateOnly
                        current.timeZone = observation.timeZone
                    } else if current.state != .rejected {
                        current.previousDate = current.date
                        current.proposedDate = observation.date
                        current.proposedDateOnly = observation.dateOnly
                        current.proposedTimeZone = observation.timeZone
                        current.state = .conflict
                    }
                    current.revision += 1
                }
                if !current.userEdited { current.title = observation.title; current.kind = observation.kind }
                current.evidence = observation.evidence
                current.sourceURL = observation.sourceURL
                result[index] = current
            } else {
                var candidate = observation
                let duplicate = result.first {
                    $0.courseID == observation.courseID && $0.sourceID != observation.sourceID &&
                    normalized($0.title) == normalized(observation.title) && $0.kind == observation.kind &&
                    $0.state != .rejected
                }
                if let duplicate {
                    candidate.state = .conflict
                    candidate.previousDate = duplicate.date
                    candidate.proposedDate = observation.date
                    candidate.evidence = "Possible duplicate: \(duplicate.title). Compare sources before approving.\n\n" + observation.evidence
                }
                result.append(candidate)
            }
        }
        return result
    }
    private static func normalized(_ title: String) -> String {
        title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
