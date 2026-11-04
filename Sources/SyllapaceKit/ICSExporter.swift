import Foundation

public enum ICSExporter {
    public static func export(events: [AcademicEvent], courses: [Course], exportedAt: Date = .now) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Syllapace//Academic Timeline//EN", "CALSCALE:GREGORIAN", "X-WR-CALNAME:Syllapace"]
        let names = Dictionary(courses.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let instant = DateFormatter()
        instant.locale = Locale(identifier: "en_US_POSIX")
        instant.timeZone = TimeZone(secondsFromGMT: 0)
        instant.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        for event in events.filter({ $0.state == .approved && $0.date != nil }).sorted(by: { $0.id < $1.id }) {
            guard let date = event.date else { continue }
            lines += ["BEGIN:VEVENT", "UID:\(escape(event.id))@syllapace.local", "DTSTAMP:\(instant.string(from: exportedAt))", "SEQUENCE:\(max(0, event.revision))", "SUMMARY:\(escape(event.title))"]
            if event.dateOnly {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: event.timeZone) ?? .gmt
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "yyyyMMdd"
                lines.append("DTSTART;VALUE=DATE:\(formatter.string(from: date))")
                if let end = calendar.date(byAdding: .day, value: 1, to: date) { lines.append("DTEND;VALUE=DATE:\(formatter.string(from: end))") }
            } else {
                lines.append("DTSTART:\(instant.string(from: date))")
                // A deadline is a point in time. No invented event duration.
            }
            var description = names[event.courseID] ?? ""
            if !event.evidence.isEmpty { description += "\n\n" + event.evidence }
            if !description.isEmpty { lines.append("DESCRIPTION:\(escape(description))") }
            if let raw = event.sourceURL, let url = safeURL(raw) { lines.append("URL:\(url)") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    private static func safeURL(_ raw: String) -> String? {
        guard var url = URLComponents(string: raw), url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else { return nil }
        // Canvas download links can contain signed credentials. Exports retain only the
        // resource path, never query-string credentials or injected content lines.
        url.query = nil; url.fragment = nil
        guard let value = url.string, !value.contains("\n"), !value.contains("\r") else { return nil }
        return value
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }
    private static func fold(_ line: String) -> String {
        var output = "", count = 0
        for scalar in line.unicodeScalars {
            let character = String(scalar)
            let bytes = character.utf8.count
            if count + bytes > 75 { output += "\r\n "; count = 1 }
            output += character; count += bytes
        }
        return output
    }
}
