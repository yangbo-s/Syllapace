import Foundation

/// Keeps readable evidence and its destinations together without executing HTML.
public enum CanvasHTML {
    public static func parse(_ html: String, baseURL: URL) -> (text: String, links: [SourceLink], truncated: Bool) {
        let cleaned = html.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        let pattern = #"(?is)<a\b([^>]*)>(.*?)</a\s*>"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return (CanvasClient.plainText(cleaned), [], false) }
        var links: [SourceLink] = []
        var seen = Set<String>()
        var truncated = false
        for match in expression.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
            guard let attributesRange = Range(match.range(at: 1), in: cleaned),
                  let labelRange = Range(match.range(at: 2), in: cleaned),
                  let href = attribute("href", in: String(cleaned[attributesRange])),
                  let url = URL(string: decodeEntities(href), relativeTo: baseURL)?.absoluteURL,
                  url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
                  let host = url.host, !host.isEmpty else { continue }
            let destination = url.absoluteString
            guard seen.insert(destination).inserted else { continue }
            if links.count >= 200 { truncated = true; continue }
            let label = CanvasClient.plainText(String(cleaned[labelRange]))
            links.append(SourceLink(url: destination, title: label.isEmpty ? host : label, kind: ConnectorURL.sameOrigin(url, baseURL) ? "canvas" : "external"))
        }
        if let embeds = try? NSRegularExpression(pattern: #"(?is)<(iframe|embed|object)\b([^>]*)>"#) {
            for match in embeds.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
                guard let range = Range(match.range(at: 2), in: cleaned) else { continue }
                let attributes = String(cleaned[range])
                guard let raw = attribute("src", in: attributes) ?? attribute("data", in: attributes),
                      let url = URL(string: decodeEntities(raw), relativeTo: baseURL)?.absoluteURL,
                      url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
                      let host = url.host, !host.isEmpty, seen.insert(url.absoluteString).inserted else { continue }
                if links.count >= 200 { truncated = true; continue }
                let label = attribute("title", in: attributes).map(CanvasClient.plainText) ?? host
                links.append(SourceLink(url: url.absoluteString, title: label, kind: ConnectorURL.sameOrigin(url, baseURL) ? "canvas" : "external"))
            }
        }
        return (CanvasClient.plainText(cleaned), links, truncated)
    }

    static func attribute(_ name: String, in attributes: String) -> String? {
        let pattern = "(?is)(?:^|\\s)" + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)) else { return nil }
        for index in 1...3 {
            if let range = Range(match.range(at: index), in: attributes) { return String(attributes[range]) }
        }
        return nil
    }

    private static func decodeEntities(_ value: String) -> String {
        var text = value
        for (entity, decoded) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">") ] {
            text = text.replacingOccurrences(of: entity, with: decoded)
        }
        guard let expression = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) else { return text }
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let numberRange = Range(match.range(at: 1), in: text), let fullRange = Range(match.range, in: text) else { continue }
            let number = String(text[numberRange])
            let code = number.hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
            if let code, let scalar = UnicodeScalar(code) { text.replaceSubrange(fullRange, with: String(scalar)) }
        }
        return text
    }
}

enum CanvasClassification {
    static func kind(title: String, group: String? = nil, quiz: Bool = false, calendar: Bool = false) -> EventKind {
        let value = title + " " + (group ?? "")
        if calendar && EventCuration.matches(#"\boffice hours\b|咨询时间"#, value) { return .other }
        if calendar && EventCuration.matches(#"\b(lecture|class|lab|laboratory|recitation|seminar|demo)\b|上课|实验课|讨论课"#, value),
           !EventCuration.matches(#"\b(due|deadline|submit)\b|截止|提交"#, value) { return .session }
        if matches(#"\b(exam|midterm|final exam|test)\b|考试|期中|期末"#, value) { return .exam }
        if quiz || matches(#"\bquiz(?:zes)?\b|测验|小测"#, value) { return .quiz }
        if matches(#"\b(project|capstone|milestone|proposal)\b|项目|里程碑"#, value) { return .project }
        if matches(#"\b(presentation|presentations)\b|演示|答辩"#, value) { return .presentation }
        if calendar && matches(#"\b(homework|assignment|problem set|due|deadline|submit)\b|作业|截止|提交"#, value) { return .assignment }
        return calendar ? .other : .assignment
    }
    private static func matches(_ pattern: String, _ value: String) -> Bool { value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
}

struct CanvasTermDTO: Decodable, Sendable {
    var id: Int64; var name: String?; var start_at: String?; var end_at: String?
}
struct CanvasGroupDTO: Decodable, Sendable { var id: Int64; var name: String }
struct CanvasQuizDTO: Decodable, Sendable {
    var id: Int64; var title: String; var description: String?; var assignment_id: Int64?; var due_at: String?; var html_url: String?; var published: Bool?
}
struct CanvasAnnouncementDTO: Decodable, Sendable {
    var id: Int64; var title: String; var message: String?; var html_url: String?; var attachments: [CanvasFileDTO]?; var attachment: CanvasFileDTO?
}
struct CanvasModuleDTO: Decodable, Sendable {
    var id: Int64; var name: String?; var published: Bool?; var state: String?
}
struct CanvasModuleItemDTO: Decodable, Sendable {
    var id: Int64; var title: String?; var type: String; var content_id: Int64?; var page_url: String?; var html_url: String?; var external_url: String?; var published: Bool?
}
struct CanvasPageDTO: Decodable, Sendable {
    var page_id: Int64?; var title: String; var url: String?; var html_url: String?; var body: String?; var published: Bool?; var locked_for_user: Bool?
}
struct CanvasTabDTO: Decodable, Sendable { var id: String; var hidden: Bool?; var visibility: String? }
