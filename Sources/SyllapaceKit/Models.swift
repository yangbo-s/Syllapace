import Foundation

public enum EventKind: String, Codable, Sendable, CaseIterable { case session, assignment, project, quiz, exam, presentation, academic, holiday, other }
public enum ReviewState: String, Codable, Sendable { case pending, approved, rejected, conflict }
public enum EventCategory: String, Codable, Sendable, CaseIterable { case meeting, deadline, assessment }
public enum EventSubtype: String, Codable, Sendable, CaseIterable {
    case lecture, recitation, lab, demo, seminar, classMeeting
    case homework, project, report, presentation, submission
    case quiz, midterm, final, exam
}
public enum TaskProgress: String, Codable, Sendable, CaseIterable { case todo, doing, done }
public struct AcademicTerm: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var startAt: Date?
    public var endAt: Date?
    public var academicYear: Int? {
        guard let regex = try? NSRegularExpression(pattern: "\\b(?:19|20|21)[0-9]{2}\\b") else { return nil }
        let years = Set(regex.matches(in: name, range: NSRange(name.startIndex..., in: name)).compactMap { match in Range(match.range, in: name).flatMap { Int(name[$0]) } })
        return years.count == 1 ? years.first : nil
    }
    public init(id: String, name: String, startAt: Date? = nil, endAt: Date? = nil) {
        self.id = id; self.name = name; self.startAt = startAt; self.endAt = endAt
    }
}
public struct CanvasSelection: Codable, Sendable, Equatable {
    public var termID: String?
    public var courseIDs: Set<String>
    public init(termID: String? = nil, courseIDs: Set<String> = []) { self.termID = termID; self.courseIDs = courseIDs }
    public func includes(_ course: Course) -> Bool { !course.isCanvas || courseIDs.contains(course.id) }
}
public struct Course: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var code: String
    public var color: Int
    public var term: AcademicTerm?
    public var startsAt: Date?
    public var endsAt: Date?
    public var concluded: Bool?
    public var timeZone: String?
    public var isCanvas: Bool { id.contains(":course:") }
    public init(id: String, name: String, code: String, color: Int = 0, term: AcademicTerm? = nil, startsAt: Date? = nil, endsAt: Date? = nil, concluded: Bool? = nil, timeZone: String? = nil) {
        self.id = id; self.name = name; self.code = code; self.color = color
        self.term = term; self.startsAt = startsAt; self.endsAt = endsAt; self.concluded = concluded; self.timeZone = timeZone
    }
}
public enum SourceKind: String, Codable, Sendable { case syllabus, assignment, announcement, page, file, external }
public struct SourceLink: Identifiable, Codable, Sendable, Equatable {
    public var id: String { url }
    public var url: String
    public var title: String
    public var kind: String?
    public init(url: String, title: String, kind: String? = nil) { self.url = url; self.title = title; self.kind = kind }
}
public struct SubmissionStatus: Codable, Sendable, Equatable {
    public var state: String?
    public var grade: String?
    public var score: Double?
    public var late: Bool?
    public var missing: Bool?
    public var excused: Bool?
    public init(state: String? = nil, grade: String? = nil, score: Double? = nil, late: Bool? = nil, missing: Bool? = nil, excused: Bool? = nil) {
        self.state = state; self.grade = grade; self.score = score; self.late = late; self.missing = missing; self.excused = excused
    }
}
public struct SourceDocument: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var courseID: String
    public var title: String
    public var text: String
    public var url: String?
    public var hash: String
    public var fetchedAt: Date
    public var kind: SourceKind?
    public var academicCalendarID: String?
    public var links: [SourceLink]?
    public var curationYear: Int?
    public var curationTimeZone: String?
    public var curationIntent: String?
    /// A per-source opt-out. Explicit one-time organization does not clear it.
    public var localOnly: Bool?
    public var remoteRevision: String?
    public var publishedAt: Date?
    public var updatedAt: Date?
    public var effectiveDueAt: Date?
    public var availableAt: Date?
    /// Verified public timetable observations; retained for offline reopening.
    public var teachingStartsAt: Date?
    public var teachingEndsAt: Date?
    public var meetingScheduleComplete: Bool?
    public var meetingSchedule: [AcademicEvent]?
    public init(id: String = UUID().uuidString, courseID: String, title: String, text: String, url: String? = nil, hash: String = "", fetchedAt: Date = .now, kind: SourceKind? = nil, links: [SourceLink]? = nil, academicCalendarID: String? = nil) {
        self.id = id; self.courseID = courseID; self.title = title; self.text = text; self.url = url; self.hash = hash; self.fetchedAt = fetchedAt
        self.kind = kind; self.links = links; self.academicCalendarID = academicCalendarID
    }
}
public struct AcademicEvent: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var courseID: String
    public var academicCalendarID: String?
    public var title: String
    public var kind: EventKind
    public var date: Date?
    public var dateOnly: Bool
    public var timeZone: String
    public var wasApproved: Bool?
    public var state: ReviewState
    public var sourceID: String?
    public var sourceSeriesID: String?
    public var evidence: String
    public var sourceURL: String?
    public var userEdited: Bool
    public var completed: Bool
    public var importUndone: Bool?
    public var observedSourceDateOnly: Bool?
    public var observedSourceTimeZone: String?
    public var proposedDateOnly: Bool?
    public var proposedTimeZone: String?
    public var observedSourceDate: Date?
    public var previousDate: Date?
    public var proposedDate: Date?
    public var revision: Int
    public var endsAt: Date?
    public var location: String?
    public var submission: SubmissionStatus?
    public var observedSourceEndsAt: Date?
    public var proposedEndsAt: Date?
    public var subtype: EventSubtype?
    public var taskProgress: TaskProgress?
    public var plannedStart: Date?
    /// Source-provided availability, distinct from the user's work plan.
    public var releasedAt: Date?
    public var releaseDateOnly: Bool?
    public var curationVersion: Int?
    public var curationExcluded: Bool?
    public var relatedSourceIDs: [String]?
    public var relatedEventIDs: [String]?
    /// Last machine-provided title, retained when the user customizes `title`.
    public var sourceTitle: String?
    public var progress: TaskProgress {
        get { completed ? .done : (taskProgress == .done ? .todo : taskProgress ?? .todo) }
        set { taskProgress = newValue; completed = newValue == .done }
    }
    public var category: EventCategory? {
        guard academicCalendarID == nil else { return nil }
        switch kind {
        case .session: return .meeting
        case .assignment, .project, .presentation: return .deadline
        case .quiz, .exam: return .assessment
        case .academic, .holiday, .other: return nil
        }
    }
    public init(id: String = UUID().uuidString, courseID: String, title: String, kind: EventKind = .assignment, date: Date? = nil, dateOnly: Bool = true, timeZone: String = TimeZone.current.identifier, state: ReviewState = .pending, sourceID: String? = nil, evidence: String = "", sourceURL: String? = nil, userEdited: Bool = false, completed: Bool = false, observedSourceDate: Date? = nil, previousDate: Date? = nil, proposedDate: Date? = nil, revision: Int = 0, observedSourceDateOnly: Bool? = nil, observedSourceTimeZone: String? = nil, proposedDateOnly: Bool? = nil, proposedTimeZone: String? = nil, endsAt: Date? = nil, location: String? = nil, submission: SubmissionStatus? = nil, academicCalendarID: String? = nil, sourceSeriesID: String? = nil) {
        self.observedSourceDateOnly = observedSourceDateOnly ?? dateOnly; self.observedSourceTimeZone = observedSourceTimeZone ?? timeZone; self.proposedDateOnly = proposedDateOnly; self.proposedTimeZone = proposedTimeZone; self.id = id; self.courseID = courseID; self.title = title; self.kind = kind; self.date = date; self.dateOnly = dateOnly; self.timeZone = timeZone; self.state = state; self.wasApproved = state == .approved; self.sourceID = sourceID; self.evidence = evidence; self.sourceURL = sourceURL; self.userEdited = userEdited; self.completed = completed; self.observedSourceDate = observedSourceDate ?? date; self.previousDate = previousDate; self.proposedDate = proposedDate; self.revision = revision
        self.academicCalendarID = academicCalendarID
        self.sourceSeriesID = sourceSeriesID
        self.endsAt = endsAt; self.location = location; self.submission = submission; self.observedSourceEndsAt = endsAt
    }
}
public struct AppArchive: Codable, Sendable {
    public var schemaVersion: Int = 4
    public var courses: [Course] = []
    public var events: [AcademicEvent] = []
    public var sources: [SourceDocument] = []
    public var lastSync: Date?
    public var canvasSelection: CanvasSelection?
    public var courseDisplayMode: CourseDisplayMode?
    public var courseAppearances: [String: CourseAppearance]?
    public var academicCalendars: [AcademicCalendarSubscription]?
    public var curationRecords: [String: SourceCurationRecord]?
    public init() {}
}
