import Foundation

public extension AcademicTerm {
    /// Initial picker values, visibly editable before a subscription is saved.
    func suggestedWindow(timeZone: TimeZone) -> DateInterval? {
        if let startAt, let endAt, endAt > startAt { return DateInterval(start: startAt, end: endAt) }
        guard let year = academicYear else { return nil }
        let title = name.lowercased()
        let months: (Int, Int, Int)
        if title.contains("fall") || title.contains("autumn") || title.contains("秋") { months = (8, 1, year + 1) }
        else if title.contains("spring") || title.contains("春") { months = (1, 6, year) }
        else if title.contains("summer") || title.contains("夏") { months = (5, 9, year) }
        else if title.contains("winter") || title.contains("冬") { months = (12, 3, year + 1) }
        else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let start = calendar.date(from: DateComponents(year: year, month: months.0, day: 1)),
              let end = calendar.date(from: DateComponents(year: months.2, month: months.1, day: 1)) else { return nil }
        return DateInterval(start: start, end: end)
    }
}
