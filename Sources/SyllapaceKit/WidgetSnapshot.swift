import Foundation

/// The widget receives only the selected semester's approved, incomplete events.
/// Credentials and the application archive never enter this shared container.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let kind = "SyllapaceUpcoming"
    public static let currentVersion = 1
    public static let maximumItems = 64

    public var version: Int
    public var generatedAt: Date
    public var semesterName: String
    public var language: String
    public var items: [Item]

    public init(generatedAt: Date = .now, semesterName: String, language: String, items: [Item]) {
        version = Self.currentVersion
        self.generatedAt = generatedAt
        self.semesterName = semesterName
        self.language = language
        self.items = items
    }

    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var courseName: String
        public var colorIndex: Int
        public var kind: String
        public var date: Date
        public var dateOnly: Bool
        public var timeZone: String
        public var endsAt: Date?

        public init(id: String, title: String, courseName: String, colorIndex: Int,
                    kind: String, date: Date, dateOnly: Bool, timeZone: String, endsAt: Date? = nil) {
            self.id = id
            self.title = title
            self.courseName = courseName
            self.colorIndex = colorIndex
            self.kind = kind
            self.date = date
            self.dateOnly = dateOnly
            self.timeZone = timeZone
            self.endsAt = endsAt
        }

        /// Calendar dates float with the viewer; timed events remain absolute instants.
        public func displayDate(in displayTimeZone: TimeZone = .current) -> Date {
            guard dateOnly else { return date }
            var source = Calendar(identifier: .gregorian)
            source.timeZone = TimeZone(identifier: timeZone) ?? displayTimeZone
            var target = Calendar(identifier: .gregorian)
            target.timeZone = displayTimeZone
            return target.date(from: source.dateComponents([.year, .month, .day], from: date)) ?? date
        }

        public var deepLink: URL? {
            var components = URLComponents()
            components.scheme = "syllapace"
            components.host = "event"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
            return components.url
        }
    }

    public func upcoming(at now: Date, timeZone: TimeZone = .current) -> [Item] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        return items.filter { item in
            item.dateOnly ? item.displayDate(in: timeZone) >= today : (item.endsAt ?? item.date) >= now
        }.sorted {
            let left = $0.displayDate(in: timeZone)
            let right = $1.displayDate(in: timeZone)
            return left == right ? $0.id < $1.id : left < right
        }
    }
}

public enum WidgetSnapshotError: Error, Equatable {
    case oversized
    case unsupportedVersion
    case tooManyItems
    case invalidItem
}

/// Only the containing app writes. Widgets read an atomically replaced JSON snapshot.
public struct WidgetSnapshotStore: Sendable {
    public static let maximumBytes = 1_048_576
    public let containerURL: URL
    public var fileURL: URL { containerURL.appendingPathComponent("widget-snapshot.json") }

    public init(containerURL: URL) { self.containerURL = containerURL }

    /// Missing signing/capability configuration disables sharing; there is no home-directory fallback.
    public static func configured(bundle: Bundle = .main) -> WidgetSnapshotStore? {
        guard bundle.object(forInfoDictionaryKey: "SyllapaceWidgetEnabled") as? Bool == true,
              let group = bundle.object(forInfoDictionaryKey: "SyllapaceWidgetAppGroup") as? String,
              !group.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return WidgetSnapshotStore(containerURL: container)
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        try validate(snapshot)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(snapshot)
        guard data.count <= Self.maximumBytes else { throw WidgetSnapshotError.oversized }
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func read() throws -> WidgetSnapshot {
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumBytes else { throw WidgetSnapshotError.oversized }
        let data = try Data(contentsOf: fileURL)
        guard data.count <= Self.maximumBytes else { throw WidgetSnapshotError.oversized }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: data)
        try validate(snapshot)
        return snapshot
    }

    private func validate(_ snapshot: WidgetSnapshot) throws {
        guard snapshot.version == WidgetSnapshot.currentVersion else { throw WidgetSnapshotError.unsupportedVersion }
        guard snapshot.items.count <= WidgetSnapshot.maximumItems else { throw WidgetSnapshotError.tooManyItems }
        guard Set(snapshot.items.map(\.id)).count == snapshot.items.count,
              snapshot.items.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty &&
                  $0.date.timeIntervalSince1970.isFinite &&
                  ($0.endsAt.map { $0.timeIntervalSince1970.isFinite } ?? true) })
        else { throw WidgetSnapshotError.invalidItem }
    }
}
