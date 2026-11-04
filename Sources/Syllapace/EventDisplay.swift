import Foundation
import SyllapaceKit
extension AcademicEvent {
    /// A date-only deadline is a calendar day, not a midnight instant to shift across zones.
    var presentationDate: Date? {
        guard let date, dateOnly else { return date }
        var source = Calendar(identifier: .gregorian)
        source.timeZone = TimeZone(identifier: timeZone) ?? .current
        return Calendar.current.date(from: source.dateComponents([.year, .month, .day], from: date))
    }
}
