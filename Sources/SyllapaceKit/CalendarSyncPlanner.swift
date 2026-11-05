import Foundation
import CryptoKit

/// The fields Syllapace publishes. A timed deadline remains a point in time; no
/// invented class duration or end-of-day deadline is introduced.
public struct CalendarEventPayload: Codable, Sendable, Equatable {
    public var title: String
    public var start: Date
    public var end: Date
    public var allDay: Bool
    public var timeZone: String
    public var notes: String
    public var marker: String

    public init?(event: AcademicEvent, calendarTimeZone: TimeZone = .current) {
        guard let date = event.date, let zone = TimeZone(identifier: event.timeZone),
              date.timeIntervalSince1970.isFinite, !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        title = event.title
        allDay = event.dateOnly
        timeZone = zone.identifier
        if event.dateOnly {
            // EventKit all-day events float in the device's default time zone.
            // Carry the source's calendar date across zones, not its instant.
            var sourceCalendar = Calendar(identifier: .gregorian)
            sourceCalendar.timeZone = zone
            var localCalendar = Calendar(identifier: .gregorian)
            localCalendar.timeZone = calendarTimeZone
            let components = sourceCalendar.dateComponents([.year, .month, .day], from: date)
            guard let localStart = localCalendar.date(from: components),
                  let following = localCalendar.date(byAdding: .day, value: 1, to: localStart) else { return nil }
            start = localStart
            end = following
            timeZone = calendarTimeZone.identifier
        } else {
            start = date
            guard event.endsAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= date }) ?? true else { return nil }
            end = event.endsAt ?? date
        }
        notes = event.evidence
        // Location is included in the notes to preserve the existing Calendar
        // fingerprint schema and leave Calendar-owned location edits intact.
        if let location = event.location, !location.isEmpty { notes += "\n\nLocation: \(location)" }
        if let source = event.sourceURL, let url = URL(string: source), url.scheme == "https",
           url.user == nil, url.password == nil, url.query == nil {
            notes += "\n\nSource: \(source)"
        }
        var components = URLComponents()
        components.scheme = "syllapace"
        components.host = "event"
        components.path = "/" + event.id
        guard let url = components.url else { return nil }
        marker = url.absoluteString
    }

    public static func normalizedAllDayEnd(_ end: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let midnight = calendar.startOfDay(for: end)
        // macOS 13+ returns the final day's 23:59:59; older stores may return
        // next-day midnight. Internally we consistently use an exclusive end.
        if end == midnight { return end }
        return calendar.date(byAdding: .day, value: 1, to: midnight) ?? end
    }

    var canonicalFields: [String: String] {
        func dateString(_ date: Date) -> String {
            guard allDay else { return String(date.timeIntervalSince1970) }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
        return ["title": title, "start": dateString(start), "end": dateString(end),
                "allDay": String(allDay), "timeZone": allDay ? "floating" : timeZone,
                "notes": notes, "marker": marker]
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.canonicalFields == rhs.canonicalFields }

    public init(title: String, start: Date, end: Date, allDay: Bool, timeZone: String, notes: String, marker: String) {
        self.title = title; self.start = start; self.end = end; self.allDay = allDay
        self.timeZone = timeZone; self.notes = notes; self.marker = marker
    }
}

public struct CalendarEventSnapshot: Codable, Sendable, Equatable {
    public var identifier: String
    public var payload: CalendarEventPayload
    /// Includes Calendar-owned details which the app does not otherwise edit.
    public var extraState: String
    public init(identifier: String, payload: CalendarEventPayload, extraState: String = "") {
        self.identifier = identifier; self.payload = payload; self.extraState = extraState
    }
    public var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Every field is a finite, Codable value; identifier is deliberately left
        // out because EventKit may replace it without changing the event itself.
        struct Content: Encodable { let fields: [String: String]; let extraState: String }
        guard let data = try? encoder.encode(Content(fields: payload.canonicalFields, extraState: extraState)) else { return "invalid" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct CalendarEventBinding: Codable, Sendable {
    public var calendarEventID: String?
    public var lastWritten: CalendarEventSnapshot?
    public var pendingPayload: CalendarEventPayload?
    public var pendingDeletion: Bool
    public init(calendarEventID: String? = nil, lastWritten: CalendarEventSnapshot? = nil, pendingPayload: CalendarEventPayload? = nil, pendingDeletion: Bool = false) {
        self.calendarEventID = calendarEventID; self.lastWritten = lastWritten
        self.pendingPayload = pendingPayload; self.pendingDeletion = pendingDeletion
    }
}

public struct CalendarSyncArchive: Codable, Sendable {
    public var version = 1
    public var calendarID: String?
    public var bindings: [String: CalendarEventBinding] = [:]
    public init() {}
}

public enum CalendarSyncAction: Sendable, Equatable {
    case create(CalendarEventPayload)
    case update(String, CalendarEventPayload)
    case delete(String)
    case adopt(CalendarEventSnapshot)
    case forget
    case unchanged
    case blocked(String)
}

/// No EventKit access: the safety decisions are independently testable. Absence
/// from an upstream sync is deliberately never interpreted as cancellation.
public enum CalendarSyncPlanner {
    public static func action(event: AcademicEvent, binding: CalendarEventBinding?, current: CalendarEventSnapshot?) -> CalendarSyncAction {
        if let binding, binding.pendingDeletion {
            guard let current else { return .forget }
            guard current.fingerprint == binding.lastWritten?.fingerprint else {
                return .blocked("This event changed in Calendar while its removal was pending.")
            }
            // A rejected event still expresses the user's cancellation intent.
            return event.state == .rejected ? .delete(current.identifier) : .blocked("A pending removal needs review before this event can be published again.")
        }
        if let pending = binding?.pendingPayload {
            if let current, current.payload == pending {
                return .adopt(current)
            }
            if let current, current.fingerprint == binding?.lastWritten?.fingerprint {
                // A failed update left the prior version intact; it can be retried.
                guard event.state == .approved, let wanted = CalendarEventPayload(event: event) else {
                    return .blocked("An unfinished calendar update needs review.")
                }
                return .update(current.identifier, wanted)
            }
            return .blocked("An unfinished calendar write needs review; no duplicate was created.")
        }
        if event.state == .rejected {
            guard let binding else { return .unchanged }
            guard let current else { return .forget }
            guard current.fingerprint == binding.lastWritten?.fingerprint else {
                return .blocked("This event was edited in Calendar. It has not been removed.")
            }
            return .delete(current.identifier)
        }
        guard event.state == .approved else { return .unchanged }
        guard let wanted = CalendarEventPayload(event: event) else {
            return .blocked("Confirm this event's date and time zone before syncing.")
        }
        guard let binding else {
            return current == nil ? .create(wanted) : .blocked("A matching Calendar event is not linked. Review it before syncing.")
        }
        guard let current else {
            return .blocked("This event was removed or moved in Calendar. It has not been recreated.")
        }
        guard current.fingerprint == binding.lastWritten?.fingerprint else {
            return .blocked("This event was edited in Calendar. Your changes have been preserved.")
        }
        if current.payload == wanted {
            return current.identifier == binding.calendarEventID ? .unchanged : .adopt(current)
        }
        return .update(current.identifier, wanted)
    }
}
