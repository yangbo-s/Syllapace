import Foundation

public struct AcademicCalendarSubscription: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var url: String
    public var termID: String?
    public var timeZone: String
    public var enabled: Bool
    public var lastFetchedAt: Date?
    public var windowStart: Date?
    public var windowEnd: Date?

    public init(id: String = UUID().uuidString, name: String, url: String, termID: String? = nil,
                timeZone: String = "America/New_York", enabled: Bool = true, lastFetchedAt: Date? = nil, windowStart: Date? = nil, windowEnd: Date? = nil) {
        self.id = id; self.name = name; self.url = url; self.termID = termID
        self.timeZone = timeZone; self.enabled = enabled; self.lastFetchedAt = lastFetchedAt
        self.windowStart = windowStart; self.windowEnd = windowEnd
    }
}

public struct AcademicCalendarPreset: Sendable {
    public var name: String
    public var feedURL: String
    public var informationURL: String
    public var yearDocumentURL: String
    public var timeZone: String

    public static let cmu = AcademicCalendarPreset(
        name: "CMU Academic Calendar",
        feedURL: "https://events.cmu.edu/live/ical/events/group/Academic%20Calendar/header/Academic%20Calendar%20Events",
        informationURL: "https://www.cmu.edu/hub/calendar/",
        yearDocumentURL: "https://www.cmu.edu/hub/calendar/docs/2627-academic-calendar.pdf",
        timeZone: "America/New_York"
    )

    public func subscription(termID: String? = nil) -> AcademicCalendarSubscription {
        AcademicCalendarSubscription(name: name, url: feedURL, termID: termID, timeZone: timeZone)
    }
    public var coverageNotice: String {
        L10n.string("This subscription may contain only upcoming dates. Import the full academic-year document to include earlier dates and check which campus and program it covers.")
    }
}

public struct ICalendarResult: Sendable {
    public var events: [AcademicEvent]
    public var warnings: [String]
    public var sourceCount: Int
    public var firstDate: Date?
    public var lastDate: Date?
    public var reviewSeriesIDs: Set<String> = []
    public var reviewEventIDs: Set<String> = []
}

public struct AcademicCalendarSyncResult: Sendable {
    public var subscription: AcademicCalendarSubscription
    public var source: SourceDocument
    public var events: [AcademicEvent]
    public var warnings: [String]
    public var coverageStart: Date?
    public var coverageEnd: Date?
    public var reviewSeriesIDs: Set<String> = []
    public var reviewEventIDs: Set<String> = []

    /// Explicit source cancellations and unresolvable series changes require a
    /// decision. Missing records alone never remove or hide saved history.
    public func reconcile(existing: [AcademicEvent]) -> [AcademicEvent] {
        let existingIDs = Set(existing.map(\.id))
        var merged = Reconciler.merge(existing: existing, incoming: events)
        for index in merged.indices {
            let event = merged[index]
            guard existingIDs.contains(event.id), event.sourceID == source.id,
                  event.academicCalendarID == subscription.id, event.state != .rejected,
                  reviewEventIDs.contains(event.id) || event.sourceSeriesID.map(reviewSeriesIDs.contains) == true else { continue }
            merged[index].wasApproved = event.wasApproved == true || event.state == .approved
            merged[index].state = .conflict
            merged[index].previousDate = event.date
            merged[index].proposedDate = nil
            merged[index].proposedEndsAt = nil
            merged[index].proposedDateOnly = nil
            merged[index].proposedTimeZone = nil
            let message = L10n.string("The source cancelled or changed this occurrence. Review the original calendar before keeping this date.")
            if !event.evidence.contains(message) { merged[index].evidence = message + "\n\n" + event.evidence }
        }
        return merged
    }
}

public enum AcademicCalendarError: LocalizedError, Sendable {
    case notCalendar, invalidTimeZone, invalidWindow
    public var errorDescription: String? {
        switch self {
        case .notCalendar: L10n.string("This address did not return an iCalendar file. Use an ICS subscription link or import the calendar document.")
        case .invalidTimeZone: L10n.string("Choose a valid time zone for this calendar.")
        case .invalidWindow: L10n.string("Choose a calendar date range of five years or less.")
        }
    }
}
