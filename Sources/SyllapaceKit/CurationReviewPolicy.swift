import Foundation

/// A processing failure is not missing information. Suppress a date question
/// only when a matching structured observation already supplies the answer.
public enum CurationReviewPolicy {
    public static func questions(source: SourceDocument, record: SourceCurationRecord?, events: [AcademicEvent], hasWeeklySchedule: Bool) -> [String] {
        guard let record, record.failure == nil else { return [] }
        let datedAssignment = source.kind == .assignment && (source.effectiveDueAt != nil || events.contains {
            $0.courseID == source.courseID && $0.id.hasPrefix("canvas:") && $0.date != nil && $0.state != .rejected &&
            ($0.sourceID == source.id || EventCuration.canonicalTitle($0.sourceTitle ?? $0.title) == EventCuration.canonicalTitle(source.title))
        })
        return (record.issues ?? []).filter { message in
            let missingDate = EventCuration.matches(#"missing (?:due |calendar )?date|no (?:stated |submission |calendar |exact |explicit )*(?:deadline|date)|date (?:is )?(?:missing|not stated)|no submission deadline"#, message)
            let unsupportedDate = message.localizedCaseInsensitiveContains("date or time is not supported by the source")
            if datedAssignment && (missingDate || unsupportedDate) {
                // A separate part or another named event remains a question.
                let sourceParts = partNumbers(source.title), issueParts = partNumbers(message)
                if !issueParts.isEmpty && issueParts != sourceParts { return true }
                if EventCuration.matches(#"\b(?:lecture|recitation|class|exam|quiz|midterm)\b"#, message), !EventCuration.matches(#"\b(?:lecture|recitation|class|exam|quiz|midterm)\b"#, source.title) { return true }
                return false
            }
            if source.kind == .syllabus && hasWeeklySchedule && missingDate &&
                EventCuration.matches(#"^(?:Lecture|Class)\s+\d+[a-z]?\b"#, message) &&
                !EventCuration.matches(#"\b(?:submit|submission|due|deadline|exam|quiz)\b"#, message) {
                // Numbered lesson topics are covered by the course timetable.
                return false
            }
            return true
        }
    }

    private static func partNumbers(_ text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"\bpart\s+(\d+)\b"#, options: .caseInsensitive) else { return [] }
        return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        })
    }
}
