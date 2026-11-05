import Foundation

/// Reads only written clock values. Shared AM/PM in a range belongs to both
/// endpoints; an unqualified `1–2` is deliberately not guessed as 1 PM–2 PM.
enum EvidenceClock {
    static func values(in text: String) -> [(Int, Int)] {
        var values: [(Int, Int, Int)] = []
        var covered: [NSRange] = []
        let rangePattern = #"(?<!\d)(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?\s*(?:[-–—]|to)\s*(\d{1,2})(?::(\d{2}))?\s*(AM|PM)\b"#
        if let regex = try? NSRegularExpression(pattern: rangePattern, options: .caseInsensitive) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let parts = (1...6).map { group(match, $0, text) }
                guard let first = Int(parts[0]), let last = Int(parts[3]), (1...12).contains(first), (1...12).contains(last),
                      let startMinute = Int(parts[1].isEmpty ? "0" : parts[1]), let endMinute = Int(parts[4].isEmpty ? "0" : parts[4]),
                      (0...59).contains(startMinute), (0...59).contains(endMinute) else { continue }
                let endHour = last % 12 + (parts[5].uppercased() == "PM" ? 12 : 0)
                let startPeriod = parts[2].isEmpty ? parts[5] : parts[2]
                var startHour = first % 12 + (startPeriod.uppercased() == "PM" ? 12 : 0)
                // "11–1 PM" denotes the adjacent morning-to-afternoon range.
                if parts[2].isEmpty, startHour * 60 + startMinute > endHour * 60 + endMinute { startHour = (startHour + 12) % 24 }
                guard startHour * 60 + startMinute < endHour * 60 + endMinute else { continue }
                values.append((match.range.location, startHour, startMinute))
                values.append((match.range.location + match.range.length - 1, endHour, endMinute))
                covered.append(match.range)
            }
        }
        let clockPattern = #"(上午|早上|中午|下午|晚上|傍晚)?\s*(?<!\d)(\d{1,2})(?:[:：](\d{2})|[点时](?:(\d{1,2})分?|半)?)\s*(AM|PM)?"#
        if let regex = try? NSRegularExpression(pattern: clockPattern, options: .caseInsensitive) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard !covered.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
                let parts = (1...5).map { group(match, $0, text) }
                guard var hour = Int(parts[1]) else { continue }
                let matched = group(match, 0, text)
                let rawMinute = parts[2].isEmpty ? (parts[3].isEmpty ? (matched.contains("半") ? "30" : "0") : parts[3]) : parts[2]
                guard let minute = Int(rawMinute), (0...59).contains(minute) else { continue }
                let pm = ["下午", "晚上", "傍晚"].contains(parts[0]) || parts[4].uppercased() == "PM"
                let am = ["上午", "早上"].contains(parts[0]) || parts[4].uppercased() == "AM"
                if pm || am { guard (1...12).contains(hour) else { continue }; hour = hour % 12 + (pm ? 12 : 0) }
                guard (0...23).contains(hour) else { continue }
                values.append((match.range.location, hour, minute))
                covered.append(match.range)
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})\s*(AM|PM)\b"#, options: .caseInsensitive) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard !covered.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                      let hour = Int(group(match, 1, text)), (1...12).contains(hour) else { continue }
                values.append((match.range.location, hour % 12 + (group(match, 2, text).uppercased() == "PM" ? 12 : 0), 0))
            }
        }
        return values.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
    }
    private static func group(_ match: NSTextCheckingResult, _ index: Int, _ text: String) -> String {
        Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
    }
}
