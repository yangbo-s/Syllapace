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
    private let requestTimeout: TimeInterval
    private let resourceTimeout: TimeInterval
    public init(requestTimeout: TimeInterval = 30, resourceTimeout: TimeInterval = 90) {
        self.requestTimeout = requestTimeout; self.resourceTimeout = resourceTimeout
    }
    public func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
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
    public var revision: String?
    public init(id: String, courseID: String, title: String, url: String, sourceURL: String = "", mimeType: String = "", size: Int = 0, revision: String? = nil) {
        self.id = id; self.courseID = courseID; self.title = title; self.url = url; self.sourceURL = sourceURL; self.mimeType = mimeType; self.size = size; self.revision = revision
    }
}
public extension CanvasFile {
    func needsDownload(saved: SourceDocument?) -> Bool {
        guard let saved, !saved.text.isEmpty else { return true }
        return revision != nil && revision != saved.remoteRevision
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
    private func request(_ url: URL, method: String = "GET", body: Data? = nil) async throws -> HTTPReply {
        guard ConnectorURL.sameOrigin(url, origin), url.path.hasPrefix("/api/v1/") else { throw ConnectorError.unsafeRedirect }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
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
    public func maintainAccessToken(previousLease: CanvasTokenLease? = nil, now: Date = .now) async throws -> CanvasTokenMaintenance {
        let records = try await pages(CanvasTokenDTO.self, url: endpoint("users/self/user_generated_tokens", query: [.init(name: "per_page", value: "100")]))
        // Mask formatting varies between Canvas instances. Require consistent
        // server evidence and one unique record before changing any expiry.
        let matches = records.filter {
            CanvasTokenIdentity.matches(token: token, hint: $0.token_hint, visibleToken: $0.visible_token)
        }
        guard matches.count == 1, let record = matches.first, record.workflow_state == "active",
              let created = Self.instant(record.created_at) else { throw CanvasTokenRenewalError.unverifiable }
        let expires = record.expires_at.flatMap(Self.instant)
        guard record.expires_at == nil || expires != nil else { throw CanvasTokenRenewalError.unverifiable }
        var lease = try CanvasTokenLease(tokenID: record.id, createdAt: created, expiresAt: expires, previous: previousLease)
        guard let proposed = try lease.renewalDate(now: now) else { return CanvasTokenMaintenance(lease: lease, renewed: false) }
        try Task.checkCancellation()
        let body = try JSONSerialization.data(withJSONObject: ["token": ["expires_at": proposed.ISO8601Format()]])
        let reply = try await request(endpoint("users/self/tokens/\(record.id)"), method: "PUT", body: body)
        guard let updated = try? JSONDecoder().decode(CanvasTokenDTO.self, from: reply.data),
              updated.id == record.id, updated.workflow_state == "active",
              Self.instant(updated.created_at) == created,
              let newExpiry = updated.expires_at.flatMap(Self.instant), let oldExpiry = expires,
              newExpiry > oldExpiry, newExpiry <= proposed.addingTimeInterval(1) else {
            throw CanvasTokenRenewalError.notExtended
        }
        lease = try CanvasTokenLease(tokenID: record.id, createdAt: created, expiresAt: newExpiry, previous: lease, acceptedInterval: newExpiry.timeIntervalSince(now))
        return CanvasTokenMaintenance(lease: lease, renewed: true)
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
                result.events.append(contentsOf: assignments.filter { $0.published != false && $0.submission_types?.contains("not_graded") != true }.map { item in
                    let date = item.due_at.flatMap(Self.instant)
                    var event = AcademicEvent(id: "\(scope):assignment:\(item.id)", courseID: courseID, title: item.name, kind: CanvasClassification.kind(title: item.name, quiz: item.quiz_id != nil || item.is_quiz_assignment == true),
                                         date: date, dateOnly: false, timeZone: timezone, state: date == nil ? .pending : .approved,
                                         evidence: "Canvas assignment: \(item.name)\n" + (item.due_at.map { "Your effective due date: \($0)" } ?? "No due date supplied."),
                                         sourceURL: origin.appendingPathComponent("courses/\(record.id)/assignments/\(item.id)").absoluteString,
                                         completed: item.submission?.submitted_at != nil || item.submission?.excused == true)
                    event.releasedAt = item.unlock_at.flatMap(Self.instant).flatMap { start in date.map { start <= $0 ? start : nil } ?? nil }
                    event.releaseDateOnly = false
                    return event
                })
            } catch is CancellationError { throw CancellationError() }
            catch { result.warnings.append(L10n.format("%@ assignments: %@", course.code, Self.safeMessage(error))) }
            do {
                let events = try await pages(CanvasCalendarDTO.self, url: endpoint("calendar_events", query: [.init(name: "context_codes[]", value: "course_\(record.id)"), .init(name: "type", value: "event"), .init(name: "all_events", value: "true"), .init(name: "per_page", value: "100")]))
                result.events.append(contentsOf: events.filter { $0.workflow_state != "deleted" && $0.hidden != true }.map { item in
                    let date = item.all_day == true
                        ? item.all_day_date.flatMap { LLMClient.localDate($0, timeZone: timezone) } ?? item.start_at.flatMap(Self.instant)
                        : item.start_at.flatMap(Self.instant)
                    var link = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
                    link.path = "/calendar"; link.queryItems = [.init(name: "event_id", value: String(item.id))]
                    return AcademicEvent(id: "\(scope):calendar:\(item.id)", courseID: courseID, title: item.title, kind: CanvasClassification.kind(title: item.title, calendar: true), date: date, dateOnly: item.all_day ?? false, timeZone: timezone, state: date == nil ? .pending : .approved,
                                         evidence: Self.plainText(item.description ?? item.title), sourceURL: link.url?.absoluteString,
                                         sourceSeriesID: Self.calendarSeriesID(item.series_uuid, courseID: courseID))
                })
            } catch is CancellationError { throw CancellationError() }
            catch { result.warnings.append(L10n.format("%@ calendar: %@", course.code, Self.safeMessage(error))) }
            do {
                let files = try await pages(CanvasFileDTO.self, url: endpoint("courses/\(record.id)/files", query: [.init(name: "per_page", value: "100")]))
                for file in files where file.locked_for_user != true && file.hidden_for_user != true {
                    let title = file.display_name ?? file.filename ?? "Document"
                    guard Self.isLikelySyllabus(title), let url = file.url else { continue }
                    result.files.append(CanvasFile(id: "\(scope):file:\(file.id)", courseID: courseID, title: title, url: url, sourceURL: origin.appendingPathComponent("courses/\(record.id)/files/\(file.id)").absoluteString, mimeType: file.contentType ?? "", size: file.size ?? 0, revision: (file.modified_at ?? file.updated_at).map { $0 + ":" + String(file.size ?? 0) }))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { result.warnings.append(L10n.format("%@ files: %@", course.code, Self.safeMessage(error))) }
        }
        result.events = Self.curatedStructured(result.events)
        return result
    }

    /// Discovery intentionally excludes syllabi and other course content until the user chooses a scope.
    public func discoverCourses() async throws -> [Course] {
        _ = try await request(endpoint("users/self/profile"))
        let records = try await pages(CanvasCourseDTO.self, url: endpoint("courses", query: [
            .init(name: "include[]", value: "term"), .init(name: "include[]", value: "concluded"),
            .init(name: "state[]", value: "available"), .init(name: "state[]", value: "completed"),
            .init(name: "per_page", value: "100")]))
        var seen = Set<Int64>()
        return records.filter { $0.id > 0 && seen.insert($0.id).inserted }.enumerated().map { index, record in
            let term = record.term.map { AcademicTerm(id: "\(scope):term:\($0.id)", name: $0.name ?? L10n.string("Unknown term"), startAt: $0.start_at.flatMap(Self.instant), endAt: $0.end_at.flatMap(Self.instant)) }
            return Course(id: "\(scope):course:\(record.id)", name: record.name ?? "Course \(record.id)", code: record.course_code ?? "Course \(record.id)", color: index % 5,
                          term: term, startsAt: record.start_at.flatMap(Self.instant), endsAt: record.end_at.flatMap(Self.instant), concluded: record.concluded, timeZone: record.time_zone)
        }
    }

    /// Only these explicit, same-origin course identities may contribute content or events.
    public func sync(courses: [Course], now: Date = .now) async throws -> CanvasSyncResult {
        let prefix = scope + ":course:"
        var selected: [(Course, Int64)] = []
        var seen = Set<String>()
        for course in courses {
            guard course.id.hasPrefix(prefix), let id = Int64(course.id.dropFirst(prefix.count)), id > 0,
                  course.id == prefix + String(id) else { throw ConnectorError.invalidResponse }
            if seen.insert(course.id).inserted { selected.append((course, id)) }
        }
        var result = CanvasSyncResult()
        guard !selected.isEmpty else { return result }
        _ = try await request(endpoint("users/self/profile"))
        for (course, id) in selected {
            try Task.checkCancellation()
            let fetched = try await syncCourse(course, id: id, now: now)
            result.courses += fetched.courses; result.events += fetched.events
            result.sources += fetched.sources; result.files += fetched.files; result.warnings += fetched.warnings
        }
        return result
    }

    private func syncCourse(_ selected: Course, id: Int64, now: Date) async throws -> CanvasSyncResult {
        var result = CanvasSyncResult()
        var course = selected
        let courseURL = origin.appendingPathComponent("courses/\(id)")
        let path = "courses/\(id)"
        var references: [CanvasContentReference] = []
        var queued = Set<CanvasContentReference>()
        var sourceIDs = Set<String>()
        var fileIDs = Set<Int64>()
        func warn(_ resource: String, _ error: any Error) {
            result.warnings.append(L10n.format("%@ — %@: %@", course.code, L10n.string(resource), Self.safeMessage(error)))
        }
        func enqueue(_ reference: CanvasContentReference) {
            if references.count < 200, queued.insert(reference).inserted { references.append(reference) }
        }
        func document(_ suffix: String, title: String, html: String, url: URL, kind: SourceKind, extraLinks: [SourceLink] = []) {
            let parsed = CanvasHTML.parse(html, baseURL: url)
            if parsed.truncated { result.warnings.append(L10n.format("%@: Some links were omitted. Open the original page for all materials.", title)) }
            var links = parsed.links
            for link in extraLinks where !links.contains(where: { $0.url == link.url }) { links.append(link) }
            for link in links {
                if let reference = contentReference(link.url, courseID: id) { enqueue(reference) }
            }
            guard !parsed.text.isEmpty || !links.isEmpty else { return }
            let sourceID = "\(course.id):\(suffix)"
            guard sourceIDs.insert(sourceID).inserted else { return }
            result.sources.append(SourceDocument(id: sourceID, courseID: course.id, title: title, text: parsed.text,
                                                 url: url.absoluteString, hash: Self.hash(title + "\n" + html + links.map { $0.url + "|" + $0.title + "|" + ($0.kind ?? "") }.joined(separator: "\n")), fetchedAt: now, kind: kind, links: links))
        }
        func addFile(_ file: CanvasFileDTO, requireScheduleName: Bool = false) {
            guard file.id > 0, file.locked_for_user != true, file.hidden_for_user != true,
                  let rawURL = file.url, let url = URL(string: rawURL), ConnectorURL.safeDownload(url),
                  fileIDs.insert(file.id).inserted else { return }
            let title = file.display_name ?? file.filename ?? "Document"
            guard !requireScheduleName || Self.isLikelySyllabus(title) else { fileIDs.remove(file.id); return }
            result.files.append(CanvasFile(id: "\(scope):file:\(file.id)", courseID: course.id, title: title, url: url.absoluteString,
                                           sourceURL: courseURL.appendingPathComponent("files/\(file.id)").absoluteString, mimeType: file.contentType ?? "", size: file.size ?? 0, revision: (file.modified_at ?? file.updated_at).map { $0 + ":" + String(file.size ?? 0) }))
        }

        do {
            let reply = try await request(endpoint(path, query: [.init(name: "include[]", value: "syllabus_body")]))
            let detail = try JSONDecoder().decode(CanvasCourseDTO.self, from: reply.data)
            if let zone = detail.time_zone, TimeZone(identifier: zone) != nil { course.timeZone = zone }
            document("syllabus", title: "\(course.code) syllabus", html: detail.syllabus_body ?? "", url: courseURL.appendingPathComponent("assignments/syllabus"), kind: .syllabus)
        } catch is CancellationError { throw CancellationError() }
        catch { warn("Syllabus", error) }
        result.courses.append(course)
        let timeZone = course.timeZone.flatMap { TimeZone(identifier: $0)?.identifier } ?? TimeZone.current.identifier
        let window = Self.contentWindow(course, now: now)
        var groups: [Int64: String] = [:]
        do {
            let values = try await pages(CanvasGroupDTO.self, url: endpoint(path + "/assignment_groups", query: [.init(name: "per_page", value: "100")]))
            for group in values { groups[group.id] = group.name }
        } catch is CancellationError { throw CancellationError() }
        catch { if !Self.optionalUnavailable(error) { warn("Assignment groups", error) } }
        var assignmentIDs = Set<Int64>()
        var assignedQuizIDs = Set<Int64>()
        do {
            let assignments = try await pages(CanvasAssignmentDTO.self, url: endpoint(path + "/assignments", query: [.init(name: "include[]", value: "submission"), .init(name: "per_page", value: "100")]))
            for item in assignments where item.published != false && item.submission_types?.contains("not_graded") != true {
                guard item.id > 0, assignmentIDs.insert(item.id).inserted else { continue }
                if let quizID = item.quiz_id { assignedQuizIDs.insert(quizID) }
                let url = courseURL.appendingPathComponent("assignments/\(item.id)")
                let sourceID = "\(course.id):assignment:\(item.id)"
                document("assignment:\(item.id)", title: item.name, html: item.description ?? "", url: url, kind: .assignment)
                if let index = result.sources.firstIndex(where: { $0.id == sourceID }) {
                    result.sources[index].effectiveDueAt = item.due_at.flatMap(Self.instant)
                    result.sources[index].availableAt = item.unlock_at.flatMap(Self.instant)
                }
                let date = item.due_at.flatMap(Self.instant)
                let submission = item.submission.map { SubmissionStatus(state: $0.workflow_state, grade: $0.grade, score: $0.score, late: $0.late, missing: $0.missing, excused: $0.excused) }
                let kind = CanvasClassification.kind(title: item.name, group: item.assignment_group_id.flatMap { groups[$0] }, quiz: item.quiz_id != nil || item.is_quiz_assignment == true)
                var event = AcademicEvent(id: "\(scope):assignment:\(item.id)", courseID: course.id, title: item.name, kind: kind,
                                                   date: date, dateOnly: false, timeZone: timeZone, state: date == nil ? .pending : .approved,
                                                   sourceID: sourceIDs.contains(sourceID) ? sourceID : nil,
                                                   evidence: "Canvas assignment: \(item.name)\n" + (item.due_at.map { "Your effective due date: \($0)" } ?? "No due date supplied."),
                                                   sourceURL: url.absoluteString, completed: item.submission?.submitted_at != nil || item.submission?.excused == true, submission: submission)
                event.releasedAt = item.unlock_at.flatMap(Self.instant).flatMap { start in date.map { start <= $0 ? start : nil } ?? nil }
                event.releaseDateOnly = false
                result.events.append(event)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { warn("Assignments", error) }
        do {
            let quizzes = try await pages(CanvasQuizDTO.self, url: endpoint(path + "/quizzes", query: [.init(name: "per_page", value: "100")]))
            var seenQuizzes = Set<Int64>()
            for quiz in quizzes where quiz.published != false {
                guard quiz.id > 0, seenQuizzes.insert(quiz.id).inserted else { continue }
                let url = courseURL.appendingPathComponent("quizzes/\(quiz.id)")
                document("quiz:\(quiz.id)", title: quiz.title, html: quiz.description ?? "", url: url, kind: .assignment)
                guard quiz.quiz_type != "practice_quiz", quiz.quiz_type != "survey", !EventCuration.isPracticeAssessment(quiz.title),
                      !assignedQuizIDs.contains(quiz.id), quiz.assignment_id.map({ !assignmentIDs.contains($0) }) ?? true else { continue }
                let date = quiz.due_at.flatMap(Self.instant)
                let identity = quiz.assignment_id.map { "\(scope):assignment:\($0)" } ?? "\(scope):quiz:\(quiz.id)"
                result.events.append(AcademicEvent(id: identity, courseID: course.id, title: quiz.title, kind: CanvasClassification.kind(title: quiz.title, quiz: true),
                                                   date: date, dateOnly: false, timeZone: timeZone, state: date == nil ? .pending : .approved,
                                                   evidence: Self.plainText(quiz.description ?? quiz.title), sourceURL: url.absoluteString))
            }
        } catch is CancellationError { throw CancellationError() }
        catch { if !Self.optionalUnavailable(error) { warn("Quizzes", error) } }
        do {
            let query: [URLQueryItem] = [.init(name: "context_codes[]", value: "course_\(id)"), .init(name: "type", value: "event"),
                                        .init(name: "start_date", value: window.start.ISO8601Format()), .init(name: "end_date", value: window.end.ISO8601Format()), .init(name: "per_page", value: "100")]
            let events = try await pages(CanvasCalendarDTO.self, url: endpoint("calendar_events", query: query))
            var seenEvents = Set<Int64>()
            for item in events where item.workflow_state != "deleted" && item.hidden != true {
                guard item.id > 0, seenEvents.insert(item.id).inserted else { continue }
                let date = item.all_day == true ? item.all_day_date.flatMap { LLMClient.localDate($0, timeZone: timeZone) } ?? item.start_at.flatMap(Self.instant) : item.start_at.flatMap(Self.instant)
                var parts = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
                parts.path = "/calendar"; parts.queryItems = [.init(name: "event_id", value: String(item.id))]
                let end = item.end_at.flatMap(Self.instant)
                let safeEnd = end.flatMap { end in date.map { end > $0 ? end : nil } ?? nil }
                document("calendar:\(item.id)", title: item.title,
                         html: "<p>\(item.title)</p><p>\(item.start_at ?? item.all_day_date ?? "")</p>" + (item.description ?? ""),
                         url: parts.url ?? courseURL, kind: .page)
                result.events.append(AcademicEvent(id: "\(scope):calendar:\(item.id)", courseID: course.id, title: item.title,
                                                   kind: CanvasClassification.kind(title: item.title, calendar: true), date: date, dateOnly: item.all_day ?? false,
                                                   timeZone: timeZone, state: date == nil ? .pending : .approved, sourceID: "\(course.id):calendar:\(item.id)", evidence: Self.plainText(item.description ?? item.title), sourceURL: parts.url?.absoluteString,
                                                   endsAt: item.all_day == true ? nil : safeEnd, location: item.location_name,
                                                   sourceSeriesID: Self.calendarSeriesID(item.series_uuid, courseID: course.id)))
            }
        } catch is CancellationError { throw CancellationError() }
        catch { warn("Calendar", error) }
        do {
            let announcements = try await pages(CanvasAnnouncementDTO.self, url: endpoint("announcements", query: [
                .init(name: "context_codes[]", value: "course_\(id)"), .init(name: "start_date", value: min(window.start, now.addingTimeInterval(-30 * 86_400)).ISO8601Format()),
                .init(name: "end_date", value: min(window.end, now).ISO8601Format()), .init(name: "per_page", value: "100")]))
            for announcement in announcements {
                let attachments = (announcement.attachments ?? []) + (announcement.attachment.map { [$0] } ?? [])
                for file in attachments where file.id > 0 { enqueue(.file(file.id)) }
                let links = attachments.map { SourceLink(url: courseURL.appendingPathComponent("files/\($0.id)").absoluteString, title: $0.display_name ?? $0.filename ?? L10n.string("Attachment")) }
                document("announcement:\(announcement.id)", title: announcement.title, html: announcement.message ?? "",
                         url: courseURL.appendingPathComponent("discussion_topics/\(announcement.id)"), kind: .announcement, extraLinks: links)
                if let index = result.sources.firstIndex(where: { $0.id == "\(course.id):announcement:\(announcement.id)" }) {
                    result.sources[index].publishedAt = (announcement.posted_at ?? announcement.delayed_post_at).flatMap(Self.instant)
                    result.sources[index].updatedAt = announcement.updated_at.flatMap(Self.instant)
                }
            }
        } catch is CancellationError { throw CancellationError() }
        catch { warn("Announcements", error) }
        do {
            let modules = try await pages(CanvasModuleDTO.self, url: endpoint(path + "/modules", query: [.init(name: "per_page", value: "100")]))
            if modules.count > 100 { warn("Modules", ConnectorError.responseTooLarge) }
            for module in modules.prefix(100) where module.published != false && module.state != "locked" {
                do {
                    let items = try await pages(CanvasModuleItemDTO.self, url: endpoint(path + "/modules/\(module.id)/items", query: [.init(name: "per_page", value: "100")]))
                    var links: [SourceLink] = []
                    for item in items where item.published != false {
                        switch item.type {
                        case "Page": if let slug = item.page_url, Self.validPageSlug(slug) { enqueue(.page(slug)) }
                        case "File": if let file = item.content_id, file > 0 { enqueue(.file(file)) }
                        case "Discussion": if let discussion = item.content_id, discussion > 0 { enqueue(.discussion(discussion)) }
                        default: break
                        }
                        if let raw = item.external_url ?? item.html_url, let url = URL(string: raw, relativeTo: courseURL)?.absoluteURL,
                           url.scheme == "https", url.user == nil, url.password == nil {
                            let linkKind = item.type == "ExternalTool" ? "external_tool" : (ConnectorURL.sameOrigin(url, origin) ? "canvas" : "external")
                            links.append(SourceLink(url: url.absoluteString, title: item.title ?? module.name ?? L10n.string("Course material"), kind: linkKind))
                        }
                    }
                    document("module:\(module.id)", title: module.name ?? L10n.string("Module"), html: "", url: courseURL.appendingPathComponent("modules/\(module.id)"), kind: .page, extraLinks: links)
                } catch is CancellationError { throw CancellationError() }
                catch { warn("Module items", error) }
            }
        } catch is CancellationError { throw CancellationError() }
        catch { if !Self.optionalUnavailable(error) { warn("Modules", error) } }
        do {
            let reply = try await request(endpoint(path + "/front_page"))
            let page = try JSONDecoder().decode(CanvasPageDTO.self, from: reply.data)
            if page.published != false && page.locked_for_user != true {
                let slug = page.url ?? "front_page"
                if Self.validPageSlug(slug) { queued.insert(.page(slug)) }
                document("page:\(page.page_id.map(String.init) ?? slug)", title: page.title, html: page.body ?? "", url: courseURL.appendingPathComponent("pages/\(slug)"), kind: .page)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { if !Self.optionalUnavailable(error) { warn("Course home", error) } }
        var processed = 0
        while processed < references.count && processed < 80 {
            try Task.checkCancellation()
            let reference = references[processed]; processed += 1
            do {
                switch reference {
                case .page(let slug):
                    let reply = try await request(endpoint(path + "/pages/" + slug))
                    let page = try JSONDecoder().decode(CanvasPageDTO.self, from: reply.data)
                    guard page.published != false, page.locked_for_user != true else { continue }
                    document("page:\(page.page_id.map(String.init) ?? slug)", title: page.title, html: page.body ?? "", url: courseURL.appendingPathComponent("pages/\(slug)"), kind: .page)
                case .file(let fileID):
                    let reply = try await request(endpoint(path + "/files/\(fileID)"))
                    addFile(try JSONDecoder().decode(CanvasFileDTO.self, from: reply.data))
                case .discussion(let discussionID):
                    let reply = try await request(endpoint(path + "/discussion_topics/\(discussionID)"))
                    let discussion = try JSONDecoder().decode(CanvasAnnouncementDTO.self, from: reply.data)
                    document("discussion:\(discussion.id)", title: discussion.title, html: discussion.message ?? "", url: courseURL.appendingPathComponent("discussion_topics/\(discussion.id)"), kind: .page)
                }
            } catch is CancellationError { throw CancellationError() }
            catch { warn("Linked material", error) }
        }
        if processed < references.count { warn("Linked material", ConnectorError.responseTooLarge) }
        // Directory visibility and linked-file visibility are separate Canvas permissions.
        var directoryAvailable = true
        do {
            let tabs = try await pages(CanvasTabDTO.self, url: endpoint(path + "/tabs"))
            directoryAvailable = tabs.contains { $0.id == "files" && $0.hidden != true && $0.visibility != "none" }
        } catch is CancellationError { throw CancellationError() }
        catch { /* If navigation cannot be read, let the Files API decide access. */ }
        if directoryAvailable {
            do {
                let files = try await pages(CanvasFileDTO.self, url: endpoint(path + "/files", query: [.init(name: "per_page", value: "100")]))
                for file in files { addFile(file, requireScheduleName: true) }
            } catch is CancellationError { throw CancellationError() }
            catch ConnectorError.http(403) { directoryAvailable = false }
            catch { warn("Files", error) }
        }
        if !directoryAvailable {
            result.warnings.append(L10n.format("%@: Files directory is unavailable. Linked course materials were checked separately.", course.code))
        }
        result.events = Self.curatedStructured(result.events)
        return result
    }

    private static func curatedStructured(_ events: [AcademicEvent]) -> [AcademicEvent] {
        events.compactMap { observation in
            guard observation.date != nil, observation.category != nil else { return nil }
            if observation.id.contains(":calendar:"), !EventCuration.supports(observation.kind, evidence: observation.title) { return nil }
            var event = observation
            event.state = .approved; event.wasApproved = true
            event.curationVersion = EventCuration.version
            event.subtype = EventCuration.subtype(for: event.title, kind: event.kind)
            event.sourceTitle = event.title
            return event
        }
    }

    private func contentReference(_ value: String, courseID: Int64) -> CanvasContentReference? {
        guard let url = URL(string: value), ConnectorURL.sameOrigin(url, origin) else { return nil }
        var components = url.path.split(separator: "/").map(String.init)
        if components.prefix(2) == ["api", "v1"] { components.removeFirst(2) }
        if components.count >= 4, components[0] == "courses", components[1] == String(courseID) {
            if components[2] == "pages", Self.validPageSlug(components[3]) { return .page(components[3]) }
            if components[2] == "files", let id = Int64(components[3]), id > 0 { return .file(id) }
            if components[2] == "discussion_topics", let id = Int64(components[3]), id > 0 { return .discussion(id) }
        }
        if components.count >= 2, components[0] == "files", let id = Int64(components[1]), id > 0 { return .file(id) }
        return nil
    }
    private static func validPageSlug(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 500 && value != "." && value != ".." && value.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\?#")) == nil
    }
    private static func optionalUnavailable(_ error: any Error) -> Bool {
        guard let error = error as? ConnectorError, case .http(let status) = error else { return false }
        return status == 404
    }
    private static func contentWindow(_ course: Course, now: Date) -> (start: Date, end: Date) {
        let day: TimeInterval = 86_400
        let base = course.startsAt ?? course.term?.startAt ?? now.addingTimeInterval(-180 * day)
        let start = base.addingTimeInterval(-30 * day)
        let proposedEnd = course.endsAt ?? course.term?.endAt ?? now.addingTimeInterval(365 * day)
        if proposedEnd.timeIntervalSince(base) > 730 * day {
            return (now.addingTimeInterval(-180 * day), now.addingTimeInterval(365 * day))
        }
        let end = min(max(proposedEnd.addingTimeInterval(30 * day), start.addingTimeInterval(day)), start.addingTimeInterval(730 * day))
        return (start, end)
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
            case "docx", "xlsx": guard response.data.starts(with: [0x50, 0x4b, 0x03, 0x04]) else { throw ConnectorError.unsupportedFile }
            case "txt", "csv", "md", "markdown", "html", "htm": guard String(data: response.data, encoding: .utf8) != nil else { throw ConnectorError.unsupportedFile }
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
    private static func calendarSeriesID(_ value: String?, courseID: String) -> String? {
        // Canvas already returns occurrences. Preserve its identity; an RRULE
        // alone never authorizes expanding or inventing a recurrence series.
        guard let value, (1...128).contains(value.utf8.count),
              value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else { return nil }
        return "canvas-series:\(courseID):\(value)"
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
private struct CanvasCourseDTO: Decodable, Sendable {
    var id: Int64; var name: String?; var course_code: String?; var syllabus_body: String?; var time_zone: String?
    var term: CanvasTermDTO?; var start_at: String?; var end_at: String?; var concluded: Bool?
}
private struct CanvasTokenDTO: Decodable, Sendable {
    var id: Int64
    var created_at: String
    var expires_at: String?
    var workflow_state: String
    var token_hint: String?
    var visible_token: String?
    enum CodingKeys: String, CodingKey { case id, created_at, expires_at, workflow_state, token_hint, visible_token }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.contains(.expires_at) else {
            throw DecodingError.keyNotFound(CodingKeys.expires_at, .init(codingPath: decoder.codingPath, debugDescription: "Missing expiration metadata"))
        }
        id = try values.decode(Int64.self, forKey: .id)
        created_at = try values.decode(String.self, forKey: .created_at)
        expires_at = try values.decodeIfPresent(String.self, forKey: .expires_at)
        workflow_state = try values.decode(String.self, forKey: .workflow_state)
        token_hint = try values.decodeIfPresent(String.self, forKey: .token_hint)
        visible_token = try values.decodeIfPresent(String.self, forKey: .visible_token)
    }
}
private struct CanvasAssignmentDTO: Decodable, Sendable {
    var id: Int64; var name: String; var due_at: String?; var unlock_at: String?; var submission: Submission?
    var description: String?; var assignment_group_id: Int64?; var quiz_id: Int64?; var is_quiz_assignment: Bool?; var published: Bool?
    var submission_types: [String]?
    struct Submission: Decodable, Sendable {
        var submitted_at: String?; var excused: Bool?; var workflow_state: String?; var grade: String?; var score: Double?; var late: Bool?; var missing: Bool?
    }
}
private struct CanvasCalendarDTO: Decodable, Sendable {
    var id: Int64; var title: String; var start_at: String?; var all_day: Bool?; var all_day_date: String?; var description: String?; var workflow_state: String?
    var end_at: String?; var location_name: String?; var hidden: Bool?
    var series_uuid: String?
}
struct CanvasFileDTO: Decodable, Sendable {
    var id: Int64; var display_name: String?; var filename: String?; var url: String?; var size: Int?; var locked_for_user: Bool?; var hidden_for_user: Bool?; var contentType: String?; var modified_at: String?; var updated_at: String?
    enum CodingKeys: String, CodingKey { case id, display_name, filename, url, size, locked_for_user, hidden_for_user, modified_at, updated_at; case contentType = "content-type" }
}
private enum CanvasContentReference: Hashable { case page(String), file(Int64), discussion(Int64) }
