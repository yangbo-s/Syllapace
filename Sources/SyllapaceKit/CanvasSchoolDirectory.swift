import Foundation

public struct CanvasSchool: Identifiable, Hashable, Sendable {
    public let name: String
    public let url: URL
    public var id: String { url.absoluteString }
    public init(name: String, url: URL) { self.name = name; self.url = url }
}

/// Instructure's public school directory. Search never reads or sends account credentials.
public actor CanvasSchoolDirectory {
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    private var cache: [String: CachedSearch] = [:]
    public init(transport: any HTTPTransport = BoundedHTTPTransport(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    public func search(name: String) async throws -> [CanvasSchool] {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        guard query.count <= 200 else { throw ConnectorError.responseTooLarge }
        try Task.checkCancellation()
        let cacheKey = query.lowercased()
        if let entry = cache[cacheKey], now().timeIntervalSince(entry.date) < 15 * 60 {
            return entry.schools
        }
        var parts = URLComponents(string: "https://canvas.instructure.com/api/v1/accounts/search")!
        parts.queryItems = [URLQueryItem(name: "name", value: query)]
        var request = URLRequest(url: parts.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let reply = try await transport.send(request, maxBytes: 128 * 1024)
        try Task.checkCancellation()
        if (300..<400).contains(reply.status) { throw ConnectorError.unsafeRedirect }
        guard (200..<300).contains(reply.status) else { throw ConnectorError.http(reply.status) }
        let records: [SchoolRecord]
        do { records = try JSONDecoder().decode([SchoolRecord].self, from: reply.data) }
        catch { throw ConnectorError.invalidResponse }
        guard records.count <= 20 else { throw ConnectorError.responseTooLarge }
        var seen = Set<String>()
        let schools = records.compactMap { record -> CanvasSchool? in
            let title = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 300,
                  let origin = try? ConnectorURL.canvasOrigin(record.domain), ConnectorURL.safeDownload(origin),
                  seen.insert(origin.absoluteString).inserted else { return nil }
            return CanvasSchool(name: title, url: origin)
        }
        if cache.count >= 32, let oldest = cache.min(by: { $0.value.date < $1.value.date })?.key {
            cache.removeValue(forKey: oldest)
        }
        cache[cacheKey] = CachedSearch(date: now(), schools: schools)
        return schools
    }

    private struct CachedSearch { let date: Date; let schools: [CanvasSchool] }
    private struct SchoolRecord: Decodable { let name: String; let domain: String }
}
