import Foundation

public enum PublicDocumentError: LocalizedError, Sendable {
    case signInRequired, unsupported
    public var errorDescription: String? {
        switch self {
        case .signInRequired: L10n.string("This source requires a separate sign-in. Open the link in your browser or import an exported document.")
        case .unsupported: L10n.string("This link did not return a readable document. Open it in your browser or import an exported file.")
        }
    }
}

/// Explicit, user-triggered imports. This client has no credential input and
/// never uses browser cookies or a Canvas Authorization header.
public struct PublicDocumentClient: Sendable {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = BoundedHTTPTransport()) { self.transport = transport }

    public func read(link: SourceLink, courseID: String) async throws -> SourceDocument {
        guard let original = URL(string: link.url), ConnectorURL.safeDownload(original) else { throw ConnectorError.invalidURL }
        var current = try Self.downloadURL(original)
        var visited = Set<URL>()
        for _ in 0..<6 {
            try Task.checkCancellation()
            guard ConnectorURL.safeDownload(current), visited.insert(current).inserted else { throw ConnectorError.unsafeRedirect }
            if Self.isSignIn(current) { throw PublicDocumentError.signInRequired }
            var request = URLRequest(url: current)
            request.setValue("text/csv,text/html,application/pdf,text/plain,application/vnd.openxmlformats-officedocument.wordprocessingml.document", forHTTPHeaderField: "Accept")
            let reply = try await transport.send(request, maxBytes: DocumentReader.maxBytes)
            if (300..<400).contains(reply.status), let destination = reply.headers["location"],
               let next = URL(string: destination, relativeTo: current)?.absoluteURL {
                current = next; continue
            }
            if reply.status == 401 || reply.status == 403 { throw PublicDocumentError.signInRequired }
            guard (200..<300).contains(reply.status) else { throw ConnectorError.http(reply.status) }
            let mime = (reply.headers["content-type"] ?? "").lowercased()
            let ext = current.pathExtension.lowercased()
            let isPDF = reply.data.starts(with: Data("%PDF".utf8))
            let isDOCX = (mime.contains("wordprocessingml") || ext == "docx") && reply.data.starts(with: [0x50, 0x4b])
            var source: SourceDocument
            if isPDF || isDOCX {
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(isPDF ? "pdf" : "docx")
                try reply.data.write(to: temporary, options: [.atomic, .completeFileProtectionUnlessOpen])
                defer { try? FileManager.default.removeItem(at: temporary) }
                source = try await DocumentReader.read(url: temporary, courseID: courseID)
            } else {
                guard reply.data.count <= DocumentReader.maxTextBytes, let raw = String(data: reply.data, encoding: .utf8) else { throw PublicDocumentError.unsupported }
                let html = mime.contains("html") || raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<!doctype html") || raw.lowercased().contains("<html")
                if html && (raw.range(of: "type\\s*=\\s*['\"]?password", options: .regularExpression) != nil || raw.contains("accounts.google.com/ServiceLogin")) { throw PublicDocumentError.signInRequired }
                // Sheets edit pages require JavaScript; their UI shell is not
                // the schedule. Only a successful export is imported.
                if html && original.host?.lowercased() == "docs.google.com" && original.path.hasPrefix("/spreadsheets/") { throw PublicDocumentError.signInRequired }
                let parsed = html ? CanvasHTML.parse(raw, baseURL: current) : (text: raw, links: [SourceLink](), truncated: false)
                guard !parsed.truncated else { throw ConnectorError.responseTooLarge }
                guard !parsed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DocumentError.noText }
                source = SourceDocument(courseID: courseID, title: link.title, text: parsed.text, links: parsed.links.map { SourceLink(url: $0.url, title: $0.title, kind: "external") })
            }
            source.id = "external:" + CanvasClient.hash(courseID + "|" + original.absoluteString)
            source.title = link.title.isEmpty ? original.lastPathComponent : link.title
            source.url = original.absoluteString
            source.kind = .external
            source.hash = CanvasClient.hash(source.text)
            return source
        }
        throw ConnectorError.unsafeRedirect
    }

    static func downloadURL(_ url: URL) throws -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw ConnectorError.invalidURL }
        if parts.host?.lowercased() == "docs.google.com", parts.path.hasPrefix("/spreadsheets/d/") {
            let path = parts.path.split(separator: "/").map(String.init)
            let query = parts.queryItems ?? []
            let fragment = URLComponents(string: "https://example.invalid/?" + (parts.fragment ?? ""))?.queryItems ?? []
            let gid = (query + fragment).first { $0.name == "gid" }?.value
            if path.count >= 4, path[2] == "e" {
                parts.path = "/spreadsheets/d/e/" + path[3] + "/pub"
                parts.queryItems = [.init(name: "output", value: "csv")]
            } else if path.count >= 3 {
                parts.path = "/spreadsheets/d/" + path[2] + "/export"
                parts.queryItems = [.init(name: "format", value: "csv")]
            }
            if let gid, gid.allSatisfy(\.isNumber), !gid.isEmpty { parts.queryItems?.append(.init(name: "gid", value: gid)) }
        }
        parts.fragment = nil
        guard let result = parts.url else { throw ConnectorError.invalidURL }
        return result
    }

    private static func isSignIn(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "accounts.google.com" || host == "login.microsoftonline.com" || url.path.lowercased().contains("/login")
    }
}
