import Foundation

/// The subscription has no credential argument. Redirects cannot inherit Canvas
/// credentials, model keys or browser cookies.
public struct AcademicCalendarClient: Sendable {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = BoundedHTTPTransport()) { self.transport = transport }

    public static func normalizedURL(_ text: String) throws -> URL {
        guard var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw ConnectorError.invalidURL }
        if parts.scheme?.lowercased() == "webcal" { parts.scheme = "https" }
        parts.fragment = nil
        guard let url = parts.url, ConnectorURL.safeDownload(url) else { throw ConnectorError.invalidURL }
        return url
    }

    public func sync(subscription: AcademicCalendarSubscription, window: DateInterval) async throws -> AcademicCalendarSyncResult {
        guard TimeZone(identifier: subscription.timeZone) != nil else { throw AcademicCalendarError.invalidTimeZone }
        let original = try Self.normalizedURL(subscription.url)
        var current = original
        var visited = Set<URL>()
        for _ in 0..<6 {
            try Task.checkCancellation()
            guard ConnectorURL.safeDownload(current), visited.insert(current).inserted else { throw ConnectorError.unsafeRedirect }
            var request = URLRequest(url: current)
            request.setValue("text/calendar", forHTTPHeaderField: "Accept")
            let reply = try await transport.send(request, maxBytes: DocumentReader.maxBytes)
            if (300..<400).contains(reply.status), let location = reply.headers["location"], let next = URL(string: location, relativeTo: current)?.absoluteURL {
                current = next; continue
            }
            guard (200..<300).contains(reply.status) else { throw ConnectorError.http(reply.status) }
            guard reply.data.count <= DocumentReader.maxTextBytes, let text = String(data: reply.data, encoding: .utf8) else { throw ConnectorError.responseTooLarge }
            let sourceID = "academic-calendar:" + subscription.id
            let result = try ICalendarReader.parse(text: text, sourceID: sourceID, calendarID: subscription.id,
                                                   timeZone: subscription.timeZone, window: window, sourceURL: original.absoluteString)
            var updated = subscription; updated.url = original.absoluteString; updated.lastFetchedAt = .now
            var source = SourceDocument(id: sourceID, courseID: "", title: subscription.name, text: text,
                                        url: original.absoluteString, hash: CanvasClient.hash(text), kind: .external)
            source.academicCalendarID = subscription.id
            return AcademicCalendarSyncResult(subscription: updated, source: source, events: result.events, warnings: result.warnings,
                                              coverageStart: result.firstDate, coverageEnd: result.lastDate,
                                              reviewSeriesIDs: result.reviewSeriesIDs, reviewEventIDs: result.reviewEventIDs)
        }
        throw ConnectorError.unsafeRedirect
    }
}
