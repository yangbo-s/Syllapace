import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let now = Date(timeIntervalSince1970: 1_793_793_600)

    private func item(id: String = "canvas:course/123", date: Date? = nil, dateOnly: Bool = false,
                      endsAt: Date? = nil, timeZone: String = "UTC") -> WidgetSnapshot.Item {
        .init(id: id, title: "Project proposal", courseName: "Design Studio", colorIndex: 0,
              kind: "project", date: date ?? now, dateOnly: dateOnly, timeZone: timeZone, endsAt: endsAt)
    }

    @Test func sharedSnapshotRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(containerURL: directory)
        let original = WidgetSnapshot(generatedAt: now, semesterName: "Fall 2026", language: "zh-Hans", items: [item()])
        try store.write(original)
        #expect(try store.read() == original)
        let replacement = WidgetSnapshot(generatedAt: now, semesterName: "Spring 2027", language: "en", items: [])
        try store.write(replacement)
        #expect(try store.read() == replacement)
    }

    @Test func expiredTimedEventsDisappearButOngoingEventsRemain() {
        let events = [item(id: "past", date: now.addingTimeInterval(-60)),
                      item(id: "ongoing", date: now.addingTimeInterval(-60), endsAt: now.addingTimeInterval(60)),
                      item(id: "future", date: now.addingTimeInterval(120))]
        let snapshot = WidgetSnapshot(semesterName: "Fall", language: "en", items: events)
        #expect(snapshot.upcoming(at: now, timeZone: utc).map(\.id) == ["ongoing", "future"])
    }

    @Test func dateOnlyEventsKeepTheirCalendarDayAcrossTimeZones() throws {
        let sourceDate = try #require(ISO8601DateFormatter().date(from: "2026-11-04T00:00:00+09:00"))
        let viewingDate = try #require(ISO8601DateFormatter().date(from: "2026-11-04T22:00:00-08:00"))
        let pacific = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let day = item(date: sourceDate, dateOnly: true, timeZone: "Asia/Tokyo")
        let snapshot = WidgetSnapshot(semesterName: "Fall", language: "en", items: [day])
        #expect(snapshot.upcoming(at: viewingDate, timeZone: pacific).count == 1)
        #expect(snapshot.upcoming(at: viewingDate.addingTimeInterval(7_200), timeZone: pacific).isEmpty)
    }

    @Test func deepLinkPreservesOpaqueIdentifiers() throws {
        let opaqueID = "canvas:course/123?a=1&b=2#课程"
        let url = try #require(item(id: opaqueID).deepLink)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "syllapace")
        #expect(components.host == "event")
        #expect(components.queryItems == [URLQueryItem(name: "id", value: opaqueID)])
    }

    @Test func invalidSnapshotsNeverReplaceTheLastGoodSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(containerURL: directory)
        let good = WidgetSnapshot(generatedAt: now, semesterName: "Fall", language: "en", items: [item()])
        try store.write(good)
        var unsupported = good
        unsupported.version = 99
        #expect(throws: WidgetSnapshotError.unsupportedVersion) { try store.write(unsupported) }
        let tooMany = WidgetSnapshot(semesterName: "Fall", language: "en",
                                     items: (0...WidgetSnapshot.maximumItems).map { item(id: String($0)) })
        #expect(throws: WidgetSnapshotError.tooManyItems) { try store.write(tooMany) }
        let duplicates = WidgetSnapshot(semesterName: "Fall", language: "en", items: [item(), item()])
        #expect(throws: WidgetSnapshotError.invalidItem) { try store.write(duplicates) }
        #expect(try store.read() == good)
    }

    @Test func oversizedSnapshotIsRejectedBeforeDecoding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = WidgetSnapshotStore(containerURL: directory)
        try Data(repeating: 32, count: WidgetSnapshotStore.maximumBytes + 1).write(to: store.fileURL)
        #expect(throws: WidgetSnapshotError.oversized) { try store.read() }
    }
}
