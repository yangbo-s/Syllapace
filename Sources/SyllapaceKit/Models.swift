import Foundation

public enum EventKind: String, Codable, Sendable, CaseIterable { case assignment, exam, project, presentation, other }
public enum ReviewState: String, Codable, Sendable { case pending, approved, rejected, conflict }
public struct Course: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var code: String
    public var color: Int
    public init(id: String, name: String, code: String, color: Int = 0) { self.id = id; self.name = name; self.code = code; self.color = color }
}
public struct SourceDocument: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var courseID: String
    public var title: String
    public var text: String
    public var url: String?
    public var hash: String
    public var fetchedAt: Date
    public init(id: String = UUID().uuidString, courseID: String, title: String, text: String, url: String? = nil, hash: String = "", fetchedAt: Date = .now) {
        self.id = id; self.courseID = courseID; self.title = title; self.text = text; self.url = url; self.hash = hash; self.fetchedAt = fetchedAt
    }
}
public struct AcademicEvent: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var courseID: String
    public var title: String
    public var kind: EventKind
    public var date: Date?
    public var dateOnly: Bool
    public var timeZone: String
    public var wasApproved: Bool?
    public var state: ReviewState
    public var sourceID: String?
    public var evidence: String
    public var sourceURL: String?
    public var userEdited: Bool
    public var completed: Bool
    public var observedSourceDateOnly: Bool?
    public var observedSourceTimeZone: String?
    public var proposedDateOnly: Bool?
    public var proposedTimeZone: String?
    public var observedSourceDate: Date?
    public var previousDate: Date?
    public var proposedDate: Date?
    public var revision: Int
    public init(id: String = UUID().uuidString, courseID: String, title: String, kind: EventKind = .assignment, date: Date? = nil, dateOnly: Bool = true, timeZone: String = TimeZone.current.identifier, state: ReviewState = .pending, sourceID: String? = nil, evidence: String = "", sourceURL: String? = nil, userEdited: Bool = false, completed: Bool = false, observedSourceDate: Date? = nil, previousDate: Date? = nil, proposedDate: Date? = nil, revision: Int = 0, observedSourceDateOnly: Bool? = nil, observedSourceTimeZone: String? = nil, proposedDateOnly: Bool? = nil, proposedTimeZone: String? = nil) {
        self.observedSourceDateOnly = observedSourceDateOnly ?? dateOnly; self.observedSourceTimeZone = observedSourceTimeZone ?? timeZone; self.proposedDateOnly = proposedDateOnly; self.proposedTimeZone = proposedTimeZone; self.id = id; self.courseID = courseID; self.title = title; self.kind = kind; self.date = date; self.dateOnly = dateOnly; self.timeZone = timeZone; self.state = state; self.wasApproved = state == .approved; self.sourceID = sourceID; self.evidence = evidence; self.sourceURL = sourceURL; self.userEdited = userEdited; self.completed = completed; self.observedSourceDate = observedSourceDate ?? date; self.previousDate = previousDate; self.proposedDate = proposedDate; self.revision = revision
    }
}
public struct AppArchive: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var courses: [Course] = []
    public var events: [AcademicEvent] = []
    public var sources: [SourceDocument] = []
    public var lastSync: Date?
    public init() {}
}
