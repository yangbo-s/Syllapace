import Foundation

public struct SourceCurationRecord: Codable, Sendable, Equatable {
    public var fingerprint: String
    public var completedAt: Date
    public var eventCount: Int
    public var issues: [String]?
    public init(fingerprint: String, completedAt: Date = .now, eventCount: Int = 0, issues: [String]? = nil) {
        self.fingerprint = fingerprint; self.completedAt = completedAt; self.eventCount = eventCount; self.issues = issues
    }
}

public struct CurationResult: Sendable {
    public var events: [AcademicEvent]
    public var issues: [String]
    public init(events: [AcademicEvent] = [], issues: [String] = []) { self.events = events; self.issues = issues }
}

/// Source evidence remains available even when it contains no actionable event.
/// Only the three course categories enter the workspace. Explicit school-calendar
/// subscriptions are a separate, opt-in layer and retain their existing semantics.
public enum EventCuration {
    public static let version = 2

    public static func isPracticeAssessment(_ text: String) -> Bool {
        matches(#"\b(?:practice|mock|sample)\s+(?:(?:mid[- ]?term|final)\s+)?(?:exam|quiz|test)\b|\bpractice\s+mid[- ]?term\b|(?:模拟|练习|样例)(?:考试|测验|试卷)|\b(?:exam|quiz|test)\s+(?:practice|solutions?|review)\b"#, text)
    }

    public static func fingerprint(source: SourceDocument, modelIdentity: String, year: Int, timeZone: String,
                                   termStart: Date? = nil, termEnd: Date? = nil, intent: String = "") -> String {
        CanvasClient.hash([source.id, source.hash.isEmpty ? CanvasClient.hash(source.text) : source.hash,
                           String(version), modelIdentity, String(year), timeZone,
                           termStart?.ISO8601Format() ?? "", termEnd?.ISO8601Format() ?? "", intent].joined(separator: "\n"))
    }

    public static func subtype(for title: String, kind: EventKind) -> EventSubtype? {
        switch kind {
        case .session:
            if matches(#"\brecitation\b|习题课"#, title) { return .recitation }
            if matches(#"\blab(?:oratory)?\b|实验课"#, title) { return .lab }
            if matches(#"\bdemo\b"#, title) { return .demo }
            if matches(#"\bseminar\b|研讨课"#, title) { return .seminar }
            if matches(#"\blecture\b|讲课"#, title) { return .lecture }
            return .classMeeting
        case .assignment:
            if matches(#"\b(homework|hw|problem set|assignment)\b|作业"#, title) { return .homework }
            if matches(#"\b(report|paper)\b|报告|论文"#, title) { return .report }
            return .submission
        case .project: return .project
        case .presentation: return .presentation
        case .quiz: return .quiz
        case .exam:
            if matches(#"\bmidterm\b|期中"#, title) { return .midterm }
            if matches(#"\bfinal\b|期末"#, title) { return .final }
            return .exam
        default: return nil
        }
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func canonicalTitle(_ title: String) -> String {
        let aliases = title.lowercased().replacingOccurrences(of: #"\b(?:hw|homework|problem\s*set|pset)\s*[-#:]?\s*0*(\d+)\b"#,
                                                              with: "homework $1", options: .regularExpression)
        return aliases.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Conservative admission for text, not an attempt to infer an event from a keyword.
    static func supports(_ kind: EventKind, evidence: String) -> Bool {
        if [.quiz, .exam].contains(kind), isPracticeAssessment(evidence) { return false }
        if matches(#"will be judged|assessment forms|grading (?:criteria|policy|rubric)|quality and depth|students can expect|learning objectives|course objectives|percentage of|% of (?:your|the) grade"#, evidence) { return false }
        switch kind {
        case .session:
            return matches(#"\b(lecture|recitation|lab|laboratory|seminar|class|discussion|demo)\b|上课|实验课|讨论课|习题课"#, evidence)
                && !matches(#"\boffice hours\b|咨询时间"#, evidence)
        case .assignment, .project, .presentation:
            return matches(#"\b(assignment|homework|hw\s*\d*|problem\s+set|project|milestone|proposal|paper|report|submission|submit|due|deadline)\b|作业|项目|截止|提交|报告"#, evidence)
                && !matches(#"\b(?:grades?|scores?) (?:are |were )?(?:posted|released|available)\b"#, evidence)
        case .quiz, .exam:
            return matches(#"\b(exam|midterm|quiz|test|final)\b|考试|期中|期末|小测|测验"#, evidence)
                && !matches(#"\bfinal (?:report|project|paper|presentation|submission)\b"#, evidence)
                && !matches(#"\b(exam|midterm|quiz|test) (?:review|results?|grades?|scores?|solutions?)\b"#, evidence)
        default: return false
        }
    }

    /// Replaces machine-generated observations for explicitly selected sources.
    /// Excluded records are retained as reversible tombstones, never hard-deleted.
    public static func reorganize(existing: [AcademicEvent], incoming: [AcademicEvent], sourceIDs: Set<String>) -> CurationReorganization {
        var prepared = existing
        for index in prepared.indices {
            let event = prepared[index]
            guard let sourceID = event.sourceID, sourceIDs.contains(sourceID), !event.userEdited,
                  event.importUndone != true,
                  !(event.id.hasPrefix("canvas:") && event.category != nil && event.date != nil),
                  event.state != .rejected || event.curationExcluded == true else { continue }
            prepared[index].state = .rejected
            prepared[index].curationExcluded = true
            if prepared[index] != event { prepared[index].revision += 1 }
        }
        let protected = existing.filter { $0.importUndone == true || ($0.state == .rejected && $0.curationExcluded != true) }
        let observations = incoming.compactMap { observation -> AcademicEvent? in
            let rejected = protected.contains { saved in
                saved.id == observation.id || (saved.sourceID != nil && saved.sourceID == observation.sourceID && saved.kind == observation.kind && saved.observedSourceDate == observation.date &&
                    saved.evidence.split(whereSeparator: \.isWhitespace).joined(separator: " ") == observation.evidence.split(whereSeparator: \.isWhitespace).joined(separator: " "))
            }
            guard !rejected else { return nil }
            // Reconciliation preserves user-edited values while retaining the
            // source's new proposal. An unchanged excerpt also connects an AI
            // title normalization back to an event the user has renamed.
            if let edited = existing.first(where: { saved in
                saved.userEdited && (saved.id == observation.id || (saved.sourceID != nil && saved.sourceID == observation.sourceID && saved.kind == observation.kind && saved.observedSourceDate == observation.date &&
                    saved.evidence.split(whereSeparator: \.isWhitespace).joined(separator: " ") == observation.evidence.split(whereSeparator: \.isWhitespace).joined(separator: " ")))
            }) {
                var linked = observation; linked.id = edited.id; return linked
            }
            return observation
        }
        let merged = Reconciler.merge(existing: prepared, incoming: observations)
        let originals = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let events = merged.map { event -> AcademicEvent in
            guard let original = originals[event.id] else { return event }
            var normalized = event; normalized.revision = original.revision
            if normalized != original { normalized.revision += 1 }
            return normalized
        }
        return CurationReorganization(before: existing, events: events)
    }

    public static func sanitizeLegacyEvents(existing: [AcademicEvent], courseIDs: Set<String>) -> CurationReorganization {
        let events = existing.map { saved -> AcademicEvent in
            guard courseIDs.contains(saved.courseID), saved.academicCalendarID == nil,
                  !saved.userEdited, saved.importUndone != true, saved.state != .rejected else { return saved }
            let canvas = saved.id.hasPrefix("canvas:")
            let generatedText = saved.id.hasPrefix("document-") || saved.id.hasPrefix("model:")
            guard canvas || generatedText else { return saved }
            let invalid = saved.category == nil || saved.date == nil || isPracticeAssessment(saved.sourceTitle ?? saved.title) ||
                (canvas && saved.id.contains(":calendar:") && !supports(saved.kind, evidence: saved.title)) ||
                (generatedText && !supports(saved.kind, evidence: saved.evidence))
            guard invalid else { return saved }
            var excluded = saved; excluded.state = .rejected; excluded.curationExcluded = true
            excluded.revision += 1
            return excluded
        }
        return CurationReorganization(before: existing, events: events)
    }
}

public struct CurationReorganization: Sendable {
    public var before: [AcademicEvent]
    public var events: [AcademicEvent]
    public var after: [AcademicEvent] { events }
    public init(before: [AcademicEvent], events: [AcademicEvent]) { self.before = before; self.events = events }

    /// Concurrent edits win over undo. Only the exact result of this operation is restored.
    public func undo(current: [AcademicEvent]) -> [AcademicEvent] {
        let originals = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let applied = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return current.compactMap { event in
            guard applied[event.id] == event else { return event }
            return originals[event.id]
        }
    }
}
