import Foundation
import CoreFoundation

/// The web workspace is a projection of native state, never a second database.
public enum WorkspaceViewMode: String, Codable, Sendable, CaseIterable { case list, gantt, calendar }
public enum WorkspaceCategory: String, Codable, Sendable { case meeting, deadline, assessment, academic }
public enum WorkspaceProgress: String, Codable, Sendable { case todo, doing, done }

public struct WorkspaceCourse: Codable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var code: String
    public var name: String
    public var color: Int
    public init(id: String, label: String, code: String, name: String, color: Int) {
        self.id = id; self.label = label; self.code = code; self.name = name; self.color = color
    }
}

public struct WorkspaceEvent: Codable, Sendable, Equatable {
    public var id: String
    public var courseID: String
    public var courseLabel: String
    public var title: String
    public var category: WorkspaceCategory
    public var subtype: String
    /// Date-only values remain calendar dates; timed values carry an ISO 8601 offset.
    public var start: String?
    public var end: String?
    public var dateOnly: Bool
    public var timeZone: String
    public var progress: WorkspaceProgress
    public var plannedStart: String?
    public var releasedAt: String?
    public var releaseDateOnly: Bool?
    public var location: String?
    public var evidence: String
    public var sourceURL: String?
    public var revision: Int

    public init(id: String, courseID: String, courseLabel: String, title: String, category: WorkspaceCategory,
                subtype: String, start: String?, end: String?, dateOnly: Bool, timeZone: String,
                progress: WorkspaceProgress, plannedStart: String? = nil, releasedAt: String? = nil, releaseDateOnly: Bool? = nil, location: String? = nil,
                evidence: String = "", sourceURL: String? = nil, revision: Int) {
        self.id = id; self.courseID = courseID; self.courseLabel = courseLabel; self.title = title
        self.category = category; self.subtype = subtype; self.start = start; self.end = end
        self.dateOnly = dateOnly; self.timeZone = timeZone; self.progress = progress
        self.releasedAt = releasedAt; self.releaseDateOnly = releaseDateOnly
        self.plannedStart = plannedStart; self.location = location; self.evidence = evidence
        self.sourceURL = sourceURL; self.revision = revision
    }

    private enum CodingKeys: String, CodingKey {
        case id, courseID, courseLabel, title, category, subtype, start, end, dateOnly, timeZone
        case progress, plannedStart, releasedAt, releaseDateOnly, location, evidence, sourceURL, revision
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(courseID, forKey: .courseID)
        try values.encode(courseLabel, forKey: .courseLabel); try values.encode(title, forKey: .title)
        try values.encode(category, forKey: .category); try values.encode(subtype, forKey: .subtype)
        try values.encode(start, forKey: .start); try values.encode(end, forKey: .end)
        try values.encode(dateOnly, forKey: .dateOnly); try values.encode(timeZone, forKey: .timeZone)
        try values.encode(progress, forKey: .progress); try values.encode(plannedStart, forKey: .plannedStart)
        try values.encode(releasedAt, forKey: .releasedAt)
        try values.encode(releaseDateOnly, forKey: .releaseDateOnly)
        try values.encode(location, forKey: .location); try values.encode(evidence, forKey: .evidence)
        try values.encode(sourceURL, forKey: .sourceURL); try values.encode(revision, forKey: .revision)
    }
}

public struct WorkspaceSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion = 1
    public var revision: Int
    public var language: String
    public var theme: [String: String]?
    public var appearance: String
    public var view: WorkspaceViewMode
    public var scope: String
    public var loading: Bool
    public var needsSemester: Bool
    public var now: String
    public var courses: [WorkspaceCourse]
    public var events: [WorkspaceEvent]
    public init(revision: Int, language: String, appearance: String, theme: [String: String]? = nil, view: WorkspaceViewMode,
                scope: String, loading: Bool = false, needsSemester: Bool = false, now: String,
                courses: [WorkspaceCourse], events: [WorkspaceEvent]) {
        self.theme = theme
        self.revision = revision; self.language = language; self.appearance = appearance; self.view = view
        self.scope = scope; self.loading = loading; self.needsSemester = needsSemester
        self.now = now; self.courses = courses; self.events = events
    }
    private enum CodingKeys: String, CodingKey {
        case revision, language, appearance, theme, view, scope, loading, needsSemester, now, courses, events
        case schemaVersion
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == 1 else { throw WorkspaceContractError.invalidMessage }
        revision = try values.decode(Int.self, forKey: .revision)
        language = try values.decode(String.self, forKey: .language)
        appearance = try values.decode(String.self, forKey: .appearance)
        theme = try values.decodeIfPresent([String: String].self, forKey: .theme)
        view = try values.decode(WorkspaceViewMode.self, forKey: .view)
        scope = try values.decode(String.self, forKey: .scope)
        loading = try values.decode(Bool.self, forKey: .loading)
        needsSemester = try values.decodeIfPresent(Bool.self, forKey: .needsSemester) ?? false
        now = try values.decode(String.self, forKey: .now)
        courses = try values.decode([WorkspaceCourse].self, forKey: .courses)
        events = try values.decode([WorkspaceEvent].self, forKey: .events)
    }
}

public enum WorkspaceCommand: Sendable, Equatable {
    case ready
    case setView(WorkspaceViewMode)
    case setProgress(eventID: String, expectedRevision: Int, progress: WorkspaceProgress)
    case setPlan(eventID: String, expectedRevision: Int, plannedStart: String?)
    case openEditor(eventID: String)
    case openSource(eventID: String)
    case addMaterial
    case chooseSemester
    case createEvent
}

public struct WorkspaceResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var snapshot: WorkspaceSnapshot?
    public var error: String?
    public init(ok: Bool = true, snapshot: WorkspaceSnapshot? = nil, error: String? = nil) {
        self.ok = ok; self.snapshot = snapshot; self.error = error
    }
}

public enum WorkspaceContractError: Error, LocalizedError, Sendable {
    case invalidMessage
    public var errorDescription: String? { "The workspace sent an invalid request. Reload the workspace and try again." }
}

public struct WorkspaceRequest: Sendable, Equatable {
    public let id: String
    public let command: WorkspaceCommand

    /// Only the finite command vocabulary may cross into the native application.
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 16_384,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["id", "method", "payload"],
              let id = object["id"] as? String, !id.isEmpty, id.utf8.count <= 128,
              let method = object["method"] as? String,
              let payload = object["payload"] as? [String: Any] else { throw WorkspaceContractError.invalidMessage }
        func keys(_ expected: Set<String>) throws {
            guard Set(payload.keys) == expected else { throw WorkspaceContractError.invalidMessage }
        }
        func eventID() throws -> String {
            guard let value = payload["eventID"] as? String, !value.isEmpty, value.utf8.count <= 512 else { throw WorkspaceContractError.invalidMessage }
            return value
        }
        func revision() throws -> Int {
            guard let value = payload["expectedRevision"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue >= 0, value.doubleValue <= 9_007_199_254_740_991,
                  value.doubleValue.rounded(.towardZero) == value.doubleValue else { throw WorkspaceContractError.invalidMessage }
            return value.intValue
        }
        let command: WorkspaceCommand
        switch method {
        case "workspace.ready": try keys([]); command = .ready
        case "workspace.addMaterial": try keys([]); command = .addMaterial
        case "workspace.chooseSemester": try keys([]); command = .chooseSemester
        case "event.create": try keys([]); command = .createEvent
        case "workspace.setView":
            try keys(["view"])
            guard let raw = payload["view"] as? String, let view = WorkspaceViewMode(rawValue: raw) else { throw WorkspaceContractError.invalidMessage }
            command = .setView(view)
        case "event.setProgress":
            try keys(["eventID", "expectedRevision", "progress"])
            guard let raw = payload["progress"] as? String, let progress = WorkspaceProgress(rawValue: raw) else { throw WorkspaceContractError.invalidMessage }
            command = .setProgress(eventID: try eventID(), expectedRevision: try revision(), progress: progress)
        case "event.setPlan":
            try keys(["eventID", "expectedRevision", "plannedStart"])
            let plannedStart: String?
            if payload["plannedStart"] is NSNull { plannedStart = nil }
            else if let value = payload["plannedStart"] as? String, WorkspaceWireDate.parseInstant(value) != nil { plannedStart = value }
            else { throw WorkspaceContractError.invalidMessage }
            command = .setPlan(eventID: try eventID(), expectedRevision: try revision(), plannedStart: plannedStart)
        case "event.openEditor": try keys(["eventID"]); command = .openEditor(eventID: try eventID())
        case "source.open": try keys(["eventID"]); command = .openSource(eventID: try eventID())
        default: throw WorkspaceContractError.invalidMessage
        }
        return Self(id: id, command: command)
    }
}

public enum WorkspaceWireDate {
    public static func instant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .gmt
        return formatter.string(from: date)
    }
    public static func parseInstant(_ text: String) -> Date? {
        guard text.utf8.count <= 40,
              text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return nil }
        for fractional in [true, false] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
            if let date = formatter.date(from: text), date.timeIntervalSince1970.isFinite { return date }
        }
        return nil
    }
    public static func dateOnly(_ date: Date, timeZone: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

public enum WorkspaceNavigation {
    public static func isLocalDocument(_ url: URL, indexURL: URL) -> Bool {
        guard url.isFileURL, url.host == indexURL.host, url.query == nil, url.user == nil, url.password == nil else { return false }
        return url.standardizedFileURL.resolvingSymlinksInPath().path == indexURL.standardizedFileURL.resolvingSymlinksInPath().path
    }
    public static func externalURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
