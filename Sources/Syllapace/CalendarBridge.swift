import Foundation
import EventKit
import Observation
import SyllapaceKit

@MainActor @Observable
final class CalendarBridge {
    private var statusKey = "Not connected"
    private var lastChangeCount = 0
    var status: String {
        if statusKey == "syncComplete" {
            return conflicts.isEmpty ? L10n.format("Up to date · %ld changes", lastChangeCount) : L10n.format("Calendar changes to review: %ld", conflicts.count)
        }
        if statusKey == "resolved" {
            return conflicts.isEmpty ? L10n.string("Calendar change resolved") : L10n.format("Calendar changes to review: %ld", conflicts.count)
        }
        return L10n.string(statusKey)
    }
    private(set) var isConnected = false
    private var conflictReasons: [(title: String, reason: String)] = []
    var conflicts: [String] { conflictReasons.map { "\($0.title): \(L10n.string($0.reason))" } }
    private(set) var conflictEventIDs: [String] = []
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let mappingURL: URL
    @ObservationIgnored private var archive = CalendarSyncArchive()
    @ObservationIgnored private var loadError: String?
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var isConnecting = false

    init(mappingURL: URL? = nil) {
        if let mappingURL {
            self.mappingURL = mappingURL
        } else if let path = ProcessInfo.processInfo.environment["APP_STORE"] {
            self.mappingURL = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("calendar-mapping.json")
        } else {
            self.mappingURL = URL.applicationSupportDirectory.appendingPathComponent("Syllapace/calendar-mapping.json")
        }
        if FileManager.default.fileExists(atPath: self.mappingURL.path) {
            do {
                archive = try JSONDecoder().decode(CalendarSyncArchive.self, from: Data(contentsOf: self.mappingURL))
                guard archive.version == 1 else { throw CalendarBridgeError(L10n.string("This calendar mapping was created by a newer version of Syllapace.")) }
            } catch {
                loadError = "Calendar mappings could not be read. Restore the mapping backup before reconnecting to avoid duplicates."
                statusKey = "Calendar mapping needs attention"
            }
        }
        isConnected = archive.calendarID != nil && EKEventStore.authorizationStatus(for: .event) == .fullAccess && loadError == nil
        if isConnected { statusKey = "Connected · On My Mac" }
    }

    private var isolatedRun: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["APP_DEMO"] == "1" || env["APP_SEED"] == "1" || env["APP_SNAPSHOT"] != nil
    }

    func connect() async throws {
        guard !isolatedRun else { throw CalendarBridgeError(L10n.string("Calendar access is disabled in the demo. Return to your own workspace to connect.")) }
        if let loadError { throw CalendarBridgeError(L10n.string(loadError)) }
        guard !isSyncing && !isConnecting else { throw CalendarBridgeError(L10n.string("Wait for the current calendar operation to finish.")) }
        isConnecting = true
        defer { isConnecting = false }
        let authorization = EKEventStore.authorizationStatus(for: .event)
        if authorization != .fullAccess {
            guard authorization != .denied && authorization != .restricted else {
                statusKey = "Calendar permission needed"
                throw CalendarBridgeError(L10n.string("Allow Syllapace in System Settings → Privacy & Security → Calendars, then reconnect."))
            }
            guard try await store.requestFullAccessToEvents() else {
                statusKey = "Calendar permission needed"
                throw CalendarBridgeError(L10n.string("Calendar permission was not granted. Your Syllapace timeline is still available."))
            }
        }
        if let id = archive.calendarID {
            guard let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications else {
                throw CalendarBridgeError(L10n.string("The connected Syllapace calendar is missing or read-only. Restore it in Calendar before syncing; a replacement will not be created automatically."))
            }
            guard calendar.source.sourceType == .local else {
                throw CalendarBridgeError(L10n.string("The connected calendar is no longer local. Reconnect to a calendar under On My Mac."))
            }
        } else {
            guard let local = store.sources.first(where: { $0.sourceType == .local }) else {
                throw CalendarBridgeError(L10n.string("In Calendar, choose File → New Calendar → On My Mac, then try again. Syllapace will not switch to iCloud automatically."))
            }
            // Test persistence before creating a system calendar.
            try persist()
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = "Syllapace"
            calendar.source = local
            try store.saveCalendar(calendar, commit: true)
            archive.calendarID = calendar.calendarIdentifier
            do { try persist() } catch {
                // If local binding cannot be saved, roll back the empty calendar.
                try? store.removeCalendar(calendar, commit: true)
                archive.calendarID = nil
                throw error
            }
        }
        isConnected = true
        statusKey = "Connected · On My Mac"
    }

    func sync(events: [AcademicEvent]) async throws -> String {
        guard !isolatedRun else { throw CalendarBridgeError(L10n.string("Calendar sync is disabled in the demo.")) }
        if let loadError { throw CalendarBridgeError(L10n.string(loadError)) }
        guard !isSyncing else { throw CalendarBridgeError(L10n.string("A calendar sync is already running.")) }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            isConnected = false
            statusKey = "Calendar permission needed"
            throw CalendarBridgeError(L10n.string("Connect Apple Calendar in Settings to sync confirmed events."))
        }
        guard let id = archive.calendarID, let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications else {
            isConnected = false
            throw CalendarBridgeError(L10n.string("Connect a dedicated Syllapace calendar before syncing."))
        }
        guard calendar.source.sourceType == .local else { throw CalendarBridgeError(L10n.string("The connected calendar is not local. Sync was stopped.")) }
        isSyncing = true
        defer { isSyncing = false }
        conflictReasons = []
        conflictEventIDs = []
        var changed = 0
        var processed = Set<String>()
        for event in events {
            try Task.checkCancellation()
            guard processed.insert(event.id).inserted else { continue }
            let binding = archive.bindings[event.id]
            let candidates = matchingEvents(event: event, binding: binding, calendar: calendar)
            guard candidates.count <= 1 else {
                recordConflict(event: event, reason: "Multiple linked calendar events need review.")
                continue
            }
            let currentEvent = candidates.first
            let current = currentEvent.map(snapshot)
            switch CalendarSyncPlanner.action(event: event, binding: binding, current: current) {
            case .unchanged: break
            case .blocked(let reason): recordConflict(event: event, reason: reason)
            case .forget:
                archive.bindings.removeValue(forKey: event.id)
                try persist()
            case .adopt(let current):
                archive.bindings[event.id] = CalendarEventBinding(calendarEventID: current.identifier, lastWritten: current)
                try persist()
            case .create(let payload), .update(_, let payload):
                var pending = binding ?? CalendarEventBinding()
                pending.pendingPayload = payload
                pending.pendingDeletion = false
                archive.bindings[event.id] = pending
                try persist()
                let target = currentEvent ?? EKEvent(eventStore: store)
                target.calendar = calendar
                apply(payload, to: target)
                do {
                    try store.save(target, span: .thisEvent, commit: true)
                } catch {
                    // EventKit rolls back commit failures (TN3130); preserve the
                    // prior binding so an ordinary transient failure is retryable.
                    archive.bindings[event.id] = binding
                    try persist()
                    statusKey = "Calendar sync interrupted"
                    throw CalendarBridgeError(L10n.format("Could not save “%@” in Calendar. Earlier changes were saved; try syncing again.", event.title))
                }
                archive.bindings[event.id] = CalendarEventBinding(calendarEventID: target.eventIdentifier, lastWritten: snapshot(target))
                try persist()
                changed += 1
            case .delete:
                guard let currentEvent else { continue }
                var pending = binding ?? CalendarEventBinding()
                pending.pendingDeletion = true
                archive.bindings[event.id] = pending
                try persist()
                do {
                    try store.remove(currentEvent, span: .thisEvent, commit: true)
                } catch {
                    archive.bindings[event.id] = binding
                    try persist()
                    throw CalendarBridgeError(L10n.format("Could not remove “%@” from Calendar. Try syncing again.", event.title))
                }
                archive.bindings.removeValue(forKey: event.id)
                try persist()
                changed += 1
            }
        }
        lastChangeCount = changed
        statusKey = "syncComplete"
        return status
    }

    /// Call only after an explicit user confirmation. This accepts the current
    /// Calendar contents as a baseline, then applies the user's Syllapace version.
    /// A missing event can be recreated; unrelated events and calendars stay untouched.
    func resolveUsingApp(event: AcademicEvent) async throws -> String {
        guard !isolatedRun else { throw CalendarBridgeError(L10n.string("Calendar access is disabled in the demo.")) }
        if let loadError { throw CalendarBridgeError(L10n.string(loadError)) }
        guard !isSyncing && !isConnecting else { throw CalendarBridgeError(L10n.string("Wait for the current calendar operation to finish.")) }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            isConnected = false
            throw CalendarBridgeError(L10n.string("Allow Calendar access in System Settings before resolving this change."))
        }
        guard let calendarID = archive.calendarID, let calendar = store.calendar(withIdentifier: calendarID),
              calendar.allowsContentModifications, calendar.source.sourceType == .local else {
            throw CalendarBridgeError(L10n.string("The connected local Syllapace calendar is unavailable."))
        }
        guard event.state == .approved || event.state == .rejected else {
            throw CalendarBridgeError(L10n.string("Confirm this event in Review before publishing it to Calendar."))
        }
        if event.state == .approved, CalendarEventPayload(event: event) == nil {
            throw CalendarBridgeError(L10n.string("Confirm this event's date and time zone before publishing it."))
        }
        let binding = archive.bindings[event.id]
        let expectedMarker = CalendarEventPayload(event: event)?.marker ?? binding?.lastWritten?.payload.marker ?? binding?.pendingPayload?.marker
        if let id = binding?.calendarEventID, let identified = store.event(withIdentifier: id) {
            guard identified.calendar.calendarIdentifier == calendarID else {
                throw CalendarBridgeError(L10n.string("This event was moved to another calendar. Move it back to Syllapace before replacing it."))
            }
            guard identified.url?.absoluteString == expectedMarker else {
                throw CalendarBridgeError(L10n.string("The linked event's identity was changed in Calendar. Restore its Syllapace link before replacing it."))
            }
        }
        let matches = matchingEvents(event: event, binding: binding, calendar: calendar)
        guard matches.count <= 1 else {
            throw CalendarBridgeError(L10n.string("Multiple linked events exist in Calendar. Resolve the duplicates there before replacing this event."))
        }
        let previousArchive = archive
        if let current = matches.first {
            guard !current.hasRecurrenceRules else {
                throw CalendarBridgeError(L10n.string("This event now repeats in Calendar. Remove its repeat schedule there before replacing it with a single Syllapace event."))
            }
            let baseline = snapshot(current)
            archive.bindings[event.id] = CalendarEventBinding(calendarEventID: baseline.identifier, lastWritten: baseline)
        } else {
            // The user's explicit confirmation authorizes recreating an absent
            // entry or completing a previously interrupted cancellation.
            archive.bindings.removeValue(forKey: event.id)
        }
        do { try persist() } catch {
            archive = previousArchive
            throw error
        }
        let remainingConflicts = zip(conflictEventIDs, conflictReasons).filter { $0.0 != event.id }
        do {
            _ = try await sync(events: [event])
        } catch {
            let newIDs = Set(conflictEventIDs)
            for (id, message) in remainingConflicts where !newIDs.contains(id) {
                conflictEventIDs.append(id)
                conflictReasons.append(message)
            }
            throw error
        }
        let newIDs = Set(conflictEventIDs)
        for (id, message) in remainingConflicts where !newIDs.contains(id) {
            conflictEventIDs.append(id)
            conflictReasons.append(message)
        }
        statusKey = "resolved"
        return status
    }

    private func recordConflict(event: AcademicEvent, reason: String) {
        conflictEventIDs.append(event.id)
        conflictReasons.append((title: event.title, reason: reason))
    }

    private func matchingEvents(event: AcademicEvent, binding: CalendarEventBinding?, calendar: EKCalendar) -> [EKEvent] {
        let marker = CalendarEventPayload(event: event)?.marker ?? binding?.lastWritten?.payload.marker ?? binding?.pendingPayload?.marker
        guard let marker else { return [] }
        var found: [String: EKEvent] = [:]
        if let id = binding?.calendarEventID, let matched = store.event(withIdentifier: id), matched.calendar.calendarIdentifier == calendar.calendarIdentifier,
           matched.url?.absoluteString == marker {
            found[id] = matched
        }
        // Recovery is confined to the dedicated calendar and known dates. If the
        // user moved an event elsewhere, absence becomes a conflict, never a create.
        let dates = Set([event.date, binding?.lastWritten?.payload.start, binding?.pendingPayload?.start, found.values.first?.startDate].compactMap { $0 })
        for date in dates {
            let span: TimeInterval = 366 * 24 * 60 * 60
            let predicate = store.predicateForEvents(withStart: date.addingTimeInterval(-span), end: date.addingTimeInterval(span), calendars: [calendar])
            for candidate in store.events(matching: predicate) where candidate.url?.absoluteString == marker {
                if let id = candidate.eventIdentifier { found[id] = candidate }
            }
        }
        return Array(found.values)
    }

    private func apply(_ payload: CalendarEventPayload, to event: EKEvent) {
        event.title = payload.title
        event.isAllDay = payload.allDay
        event.timeZone = payload.allDay ? nil : TimeZone(identifier: payload.timeZone)
        event.startDate = payload.start
        // EventKit on modern macOS uses an inclusive final second for all-day
        // events (TN3130). Keep this adapter detail out of the domain model.
        event.endDate = payload.allDay ? payload.end.addingTimeInterval(-1) : payload.end
        event.notes = payload.notes
        event.url = URL(string: payload.marker)
    }

    private func snapshot(_ event: EKEvent) -> CalendarEventSnapshot {
        let zone = event.isAllDay ? TimeZone.current : (event.timeZone ?? .current)
        let end = event.isAllDay ? CalendarEventPayload.normalizedAllDayEnd(event.endDate, timeZone: zone) : event.endDate!
        let payload = CalendarEventPayload(title: event.title ?? "", start: event.startDate, end: end,
                                           allDay: event.isAllDay, timeZone: zone.identifier,
                                           notes: event.notes ?? "", marker: event.url?.absoluteString ?? "")
        let alarms = (event.alarms ?? []).map { alarm in
            "\(alarm.relativeOffset):\(alarm.absoluteDate?.timeIntervalSince1970.description ?? "")"
        }.sorted().joined(separator: "|")
        let extra = "\(event.location ?? "")|\(event.availability.rawValue)|\(alarms)|\(event.hasRecurrenceRules)"
        return CalendarEventSnapshot(identifier: event.eventIdentifier ?? "", payload: payload, extraState: extra)
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: mappingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        if FileManager.default.fileExists(atPath: mappingURL.path) {
            let previous = try Data(contentsOf: mappingURL)
            try previous.write(to: mappingURL.appendingPathExtension("bak"), options: .atomic)
        }
        try data.write(to: mappingURL, options: .atomic)
    }
}

private struct CalendarBridgeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
