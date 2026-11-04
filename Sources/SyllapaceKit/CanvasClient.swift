import Foundation
import CryptoKit

public enum ConnectorError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL, missingCredential, invalidCredential, responseTooLarge, invalidResponse, invalidModelOutput(String), unsupportedFile, tooManyPages, unsafeRedirect, http(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return L10n.string("Enter a valid HTTPS address without credentials or query parameters.")
        case .missingCredential: return L10n.string("Add your access key in Settings, then try again.")
        case .invalidCredential: return L10n.string("The access key contains spaces or control characters. Paste the key again.")
        case .responseTooLarge: return L10n.string("The response exceeds the safe size limit. Choose a smaller document.")
        case .invalidResponse: return L10n.string("The service returned an unexpected response. Try again later.")
        case .invalidModelOutput(let reason): return L10n.format("The model result could not be verified: %@", L10n.string(reason))
        case .unsupportedFile: return L10n.string("This file is not a supported PDF, DOCX or UTF-8 text document.")
        case .tooManyPages: return L10n.string("The service returned too many pages. The sync was stopped without removing saved data.")
        case .unsafeRedirect: return L10n.string("The service redirected to an address this connection cannot safely follow.")
        case .http(401): return L10n.string("The access key is expired or invalid. Replace it in Settings.")
        case .http(403): return L10n.string("Your account does not have access to this resource.")
        case .http(404): return L10n.string("This resource is no longer available. Saved events have been kept.")
        case .http(429): return L10n.string("The service is rate limiting requests. Wait a moment, then sync again.")
        case .http(let status): return L10n.format("The service returned HTTP %ld. Try again later.", status)
        }
    }
}

public struct HTTPReply: Sendable {
    public var data: Data
    public var status: Int
    public var headers: [String: String]
    public init(data: Data, status: Int = 200, headers: [String: String] = [:]) {
        self.data = data; self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, new in new })
    }
}
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply
}

private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
public struct BoundedHTTPTransport: HTTPTransport {
    public init() {}
    public func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        let session = URLSession(configuration: config, delegate: RefuseRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ConnectorError.invalidResponse }
        guard response.expectedContentLength <= Int64(maxBytes) else { throw ConnectorError.responseTooLarge }
        var data = Data()
        if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
        for try await byte in stream {
            if data.count >= maxBytes { throw ConnectorError.responseTooLarge }
            data.append(byte)
        }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields { headers[String(describing: key).lowercased()] = String(describing: value) }
        return HTTPReply(data: data, status: response.statusCode, headers: headers)
    }
}

public enum ConnectorURL {
    public static func canvasOrigin(_ host: String) throws -> URL {
        let text = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: expanded), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { throw ConnectorError.invalidURL }
        return url
    }
    public static func sameOrigin(_ url: URL, _ origin: URL) -> Bool {
        url.scheme?.lowercased() == origin.scheme?.lowercased() && url.host?.lowercased() == origin.host?.lowercased()
            && (url.port ?? 443) == (origin.port ?? 443) && url.user == nil && url.password == nil
    }
    static func safeDownload(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.contains(":") { return false }
        let numbers = host.split(separator: ".").compactMap { Int($0) }
        if numbers.count == 4 {
            let a = numbers[0], b = numbers[1]
            return !(a == 0 || a == 10 || a == 127 || a >= 224 || (a == 169 && b == 254)
                     || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168))
        }
        return host.contains(".")
    }
    public static func nextPage(link: String?, current: URL, origin: URL) throws -> URL? {
        guard let link else { return nil }
        for part in link.components(separatedBy: ",") where part.contains("rel=\"next\"") || part.contains("rel=next") {
            guard let left = part.firstIndex(of: "<"), let right = part.firstIndex(of: ">"), left < right,
                  let url = URL(string: String(part[part.index(after: left)..<right]), relativeTo: current)?.absoluteURL,
                  sameOrigin(url, origin), url.path == current.path, url.fragment == nil else { throw ConnectorError.unsafeRedirect }
            return url
        }
        return nil
    }
}

public struct CanvasFile: Identifiable, Sendable, Equatable {
    public var id: String
    public var courseID: String
    public var title: String
    public var url: String
    public var sourceURL: String
    public var mimeType: String
    public var size: Int
    public init(id: String, courseID: String, title: String, url: String, sourceURL: String = "", mimeType: String = "", size: Int = 0) {
        self.id = id; self.courseID = courseID; self.title = title; self.url = url; self.sourceURL = sourceURL; self.mimeType = mimeType; self.size = size
    }
}
public struct CanvasSyncResult: Sendable {
    public var courses: [Course] = []
    public var events: [AcademicEvent] = []
    public var sources: [SourceDocument] = []
    public var warnings: [String] = []
    public var files: [CanvasFile] = []
    public init() {}
}

public struct CanvasClient: Sendable {
    private let origin: URL
    private let token: String
    private let transport: any HTTPTransport
    public init(host: String, token: String, transport: any HTTPTransport = BoundedHTTPTransport()) throws {
        origin = try ConnectorURL.canvasOrigin(host)
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConnectorError.missingCredential }
        guard token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw ConnectorError.invalidCredential }
        self.token = token; self.transport = transport
    }
    private var scope: String { "canvas:\(origin.host!.lowercased()):\(origin.port ?? 443)" }
    private func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
        var parts = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        parts.path = "/api/v1/" + path; parts.queryItems = query.isEmpty ? nil : query
        return parts.url!
    }
    private func request(_ url: URL) async throws -> HTTPReply {
        guard ConnectorURL.sameOrigin(url, origin), url.path.hasPrefix("/api/v1/") else { throw ConnectorError.unsafeRedirect }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var reply = try await transport.send(request, maxBytes: 8 * 1024 * 1024)
        if reply.status == 429 {
            let delay = Double(reply.headers["retry-after"] ?? "2") ?? 2
            if (0...30).contains(delay) {
                try await Task.sleep(for: .seconds(delay))
                reply = try await transport.send(request, maxBytes: 8 * 1024 * 1024)
            }
        }
        guard (200..<300).contains(reply.status) else { throw ConnectorError.http(reply.status) }
        return reply
    }
    private func pages<T: Decodable & Sendable>(_ type: T.Type, url: URL) async throws -> [T] {
        var next: URL? = url; var visited = Set<URL>(); var all: [T] = []
        while let page = next {
            guard visited.count < 100, visited.insert(page).inserted else { throw ConnectorError.tooManyPages }
            let reply = try await request(page)
            let items: [T]
            do { items = try JSONDecoder().decode([T].self, from: reply.data) } catch { throw ConnectorError.invalidResponse }
            all.append(contentsOf: items)
            guard all.count <= 10_000 else { throw ConnectorError.tooManyPages }
            next = try ConnectorURL.nextPage(link: reply.headers["link"], current: page, origin: origin)
        }
        return all
    }
    public func sync() async throws -> CanvasSyncResult {
        _ = try await request(endpoint("users/self/profile"))
        let records = try await pages(CanvasCourseDTO.self, url: endpoint("courses", query: [
            .init(name: "enrollment_state", value: "active"), .init(name: "include[]", value: "syllabus_body"), .init(name: "per_page", value: "100")]))
        var result = CanvasSyncResult()
        for (index, record) in records.enumerated() {
            try Task.checkCancellation()
            let courseID = "\(scope):course:\(record.id)"
            let course = Course(id: courseID, name: record.name ?? "Course \(record.id)", code: record.course_code ?? "Course \(record.id)", color: index % 5)
            result.courses.append(course)
            let timezone = record.time_zone.flatMap { TimeZone(identifier: $0) }?.identifier ?? TimeZone.current.identifier
            var syllabus = record.syllabus_body
            if syllabus == nil {
                do {
                    let reply = try await request(endpoint("courses/\(record.id)", query: [.init(name: "include[]", value: "syllabus_body")]))
                    syllabus = try JSONDecoder().decode(CanvasCourseDTO.self, from: reply.data).syllabus_body
                } catch is CancellationError { throw CancellationError() }
                catch { result.warnings.append(L10n.format("%@ syllabus: %@", course.code, Self.safeMessage(error))) }
            }
            if let html = syllabus, !html.isEmpty {
                result.sources.append(SourceDocument(id: "\(courseID):syllabus", courseID: courseID, title: "\(course.code) syllabus", text: Self.plainText(html), url: origin.appendingPathComponent("courses/\(record.id)/assignments/syllabus").absoluteString, hash: Self.hash(html)))
            }
            do {
                let assignments = try await pages(CanvasAssignmentDTO.self, url: endpoint("courses/\(record.id)/assignments", query: [.init(name: "include[]", value: "submission"), .init(name: "per_page", value: "100")]))
                result.events.append(contentsOf: assignments.map { item in
                    let date = item.due_at.flatMap(Self.instant)
                    return AcademicEvent(id: "\(scope):assignment:\(item.id)", courseID: courseID, title: item.name,
                                         date: date, dateOnly: false, timeZone: timezone, state: date == nil ? .pending : .approved,
                                         evidence: "Canvas assignment: \(item.name)\n" + (item.due_at.map { "Your effective due date: \($0)" } ?? "No due date supplied."),
                                         sourceURL: origin.appendingPathComponent("courses/\(record.id)/assignments/\(item.id)").absoluteString,
                                         completed: item.submission?.submitted_at != nil || item.submission?.excused == true)
                })
            } catch is CancellationError { throw CancellationError() }
            catch { result.warnings.append(L10n.format("%@ assignments: %@", course.code, Self.safeMessage(error))) }
            do {
                let events = try await pages(CanvasCalendarDTO.self, url: endpoint("calendar_events", query: [.init(name: "context_codes[]", value: "course_\(record.id)"), .init(name: "type", value: "event"), .init(name: "all_events", value: "true"), .init(name: "per_page", value: "100")]))
                result.events.append(contentsOf: events.filter { $0.workflow_state != "deleted" }.map { item in
                    let date = item.all_day == true
                        ? item.all_day_date.flatMap { LLMClient.localDate($0, timeZone: timezone) } ?? item.start_at.flatMap(Self.instant)
                        : item.start_at.flatMap(Self.instant)
                    var link = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
                    link.path = "/calendar"; link.queryItems = [.init(name: "event_id", value: String(item.id))]
                    return AcademicEvent(id: "\(scope):calendar:\(item.id)", courseID: courseID, title: item.title, kind: .other, date: date, dateOnly: item.all_day ?? false, timeZone: timezone, state: date == nil ? .pending : .approved,
                                         evidence: Self.plainText(item.description ?? item.title), sourceURL: link.url?.absoluteString)
                })
            } catch is CancellationError { throw CancellationError() }
            catch { result.warnings.append(L10n.format("%@ calendar: %@", course.code, Self.safeMessage(error))) }
            do {
                let files = try await pages(CanvasFileDTO.self, url: endpoint("courses/\(record.id)/files", query: [.init(name: "per_page", value: "100")]))
                for file in files where file.locked_for_user != true && file.hidden_for_user != true {
                    let title = file.display_name ?? file.filename ?? "Document"
                    guard Self.isLikelySyllabus(title), let url = file.url else { continue }
                    result.files.append(CanvasFile(id: "\(scope):file:\(file.id)", courseID: courseID, title: title, url: url, sourceURL: origin.appendingPathComponent("courses/\(record.id)/files/\(file.id)").absoluteString, mimeType: file.contentType ?? "", size: file.size ?? 0))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { result.warnings.append(L10n.format("%@ files: %@", course.code, Self.safeMessage(error))) }
        }
        return result
    }
    public func download(file: CanvasFile) async throws -> URL {
        let limit = 32 * 1024 * 1024
        guard file.size <= limit else { throw ConnectorError.responseTooLarge }
        guard var url = URL(string: file.url), ConnectorURL.safeDownload(url) else { throw ConnectorError.unsafeRedirect }
        var first = true
        for _ in 0..<6 {
            var request = URLRequest(url: url)
            // A bearer is attached only to the initial approved-origin request; redirects never inherit it.
            if first && ConnectorURL.sameOrigin(url, origin) { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            first = false
            let response = try await transport.send(request, maxBytes: limit)
            if (300..<400).contains(response.status) {
                guard let location = response.headers["location"], let redirect = URL(string: location, relativeTo: url)?.absoluteURL,
                      ConnectorURL.safeDownload(redirect) else { throw ConnectorError.unsafeRedirect }
                url = redirect; continue
            }
            guard (200..<300).contains(response.status) else { throw ConnectorError.http(response.status) }
            let ext = (file.title as NSString).pathExtension.lowercased()
            switch ext {
            case "pdf": guard response.data.starts(with: Data("%PDF-".utf8)) else { throw ConnectorError.unsupportedFile }
            case "docx": guard response.data.starts(with: [0x50, 0x4b, 0x03, 0x04]) else { throw ConnectorError.unsupportedFile }
            case "txt", "md", "html", "htm": guard String(data: response.data, encoding: .utf8) != nil else { throw ConnectorError.unsupportedFile }
            default: throw ConnectorError.unsupportedFile
            }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("syllapace-\(UUID().uuidString).\(ext)")
            try response.data.write(to: destination, options: .atomic)
            return destination
        }
        throw ConnectorError.unsafeRedirect
    }
    static func instant(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    public static func isLikelySyllabus(_ name: String) -> Bool {
        ["syllabus", "schedule", "calendar", "outline", "weekly plan", "教学大纲", "课程安排"].contains { name.localizedCaseInsensitiveContains($0) }
    }
    static func safeMessage(_ error: any Error) -> String {
        if let error = error as? ConnectorError { return error.localizedDescription }
        return L10n.string("Connection failed. Saved data has been kept.")
    }
    public static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</?(p|div|br|li|tr|h[1-6])\\b[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</?(td|th)\\b[^>]*>", with: " | ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] { text = text.replacingOccurrences(of: entity, with: value) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
private struct CanvasCourseDTO: Decodable, Sendable { var id: Int64; var name: String?; var course_code: String?; var syllabus_body: String?; var time_zone: String? }
private struct CanvasAssignmentDTO: Decodable, Sendable {
    var id: Int64; var name: String; var due_at: String?; var submission: Submission?
    struct Submission: Decodable, Sendable { var submitted_at: String?; var excused: Bool? }
}
private struct CanvasCalendarDTO: Decodable, Sendable { var id: Int64; var title: String; var start_at: String?; var all_day: Bool?; var all_day_date: String?; var description: String?; var workflow_state: String? }
private struct CanvasFileDTO: Decodable, Sendable {
    var id: Int64; var display_name: String?; var filename: String?; var url: String?; var size: Int?; var locked_for_user: Bool?; var hidden_for_user: Bool?; var contentType: String?
    enum CodingKeys: String, CodingKey { case id, display_name, filename, url, size, locked_for_user, hidden_for_user; case contentType = "content-type" }
}
