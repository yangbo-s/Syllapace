import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Canvas recurring calendar identities") struct CanvasRecurringSeriesTests {
    private let uuid = "d78a6690-8bfd-40e7-9769-afb0df422df8"
    private func course(_ id: Int) -> Course {
        Course(id: "canvas:canvas.example.edu:443:course:\(id)", name: "Synthetic", code: "SYN-\(id)", timeZone: "America/New_York")
    }

    @Test func selectedCourseSyncRetainsSeriesWithoutExpandingAndSeparatesCourses() async throws {
        let client = try CanvasClient(host: "canvas.example.edu", token: "synthetic", transport: SeriesTransport(series: uuid))
        let first = try await client.sync(courses: [course(10), course(20)])
        let second = try await client.sync(courses: [course(10), course(20)])
        #expect(first.events.count == 6)
        #expect(first.events == second.events)
        #expect(Set(first.events.compactMap(\.sourceSeriesID)).count == 2)
        for id in [10, 20] {
            let events = first.events.filter { $0.courseID == course(id).id }
            #expect(events.filter { $0.sourceSeriesID == "canvas-series:\(course(id).id):\(uuid)" }.count == 2)
            #expect(events.filter { $0.sourceSeriesID == nil }.count == 1)
        }
        #expect(Reconciler.merge(existing: first.events, incoming: second.events) == first.events)
    }

    @Test func legacyAndSelectedSyncUseTheSameStableSeriesIdentity() async throws {
        let client = try CanvasClient(host: "canvas.example.edu", token: "synthetic", transport: SeriesTransport(series: uuid))
        let legacy = try await client.sync(), selected = try await client.sync(courses: [course(10), course(20)])
        #expect(legacy.events.count == 6)
        let oldIdentities = Dictionary(uniqueKeysWithValues: legacy.events.map { ($0.id, $0.sourceSeriesID) })
        let newIdentities = Dictionary(uniqueKeysWithValues: selected.events.map { ($0.id, $0.sourceSeriesID) })
        #expect(oldIdentities == newIdentities)
        #expect(Set(legacy.events.compactMap(\.sourceSeriesID)).count == 2)
    }

    @Test(arguments: ["", " ", "uuid:course:other", "uuid\nInjected", String(repeating: "x", count: 129)])
    func malformedSeriesDoesNotHideOccurrencesOrInventIdentity(series: String) async throws {
        let client = try CanvasClient(host: "canvas.example.edu", token: "synthetic", transport: SeriesTransport(series: series))
        let selected = try await client.sync(courses: [course(10)])
        #expect(selected.events.count == 3)
        #expect(selected.events.allSatisfy { $0.sourceSeriesID == nil && $0.date != nil })
        let legacy = try await client.sync()
        #expect(legacy.events.count == 6)
        #expect(legacy.events.allSatisfy { $0.sourceSeriesID == nil })
    }
}

private struct SeriesTransport: HTTPTransport {
    let series: String
    func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
        let url = request.url!, path = url.path
        let body: Any
        if path == "/api/v1/users/self/profile" { body = [:] as [String: String] }
        else if path == "/api/v1/courses" {
            body = [10, 20].map { ["id": $0, "name": "Synthetic", "course_code": "SYN-\($0)", "time_zone": "America/New_York", "syllabus_body": ""] as [String: Any] }
        } else if path == "/api/v1/courses/10" || path == "/api/v1/courses/20" {
            body = ["id": Int(url.lastPathComponent)!, "syllabus_body": ""] as [String: Any]
        } else if path == "/api/v1/calendar_events" {
            let context = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "context_codes[]" }?.value ?? "course_10"
            let course = Int(context.dropFirst("course_".count))!
            // The RRULE would yield 1000 occurrences if the client incorrectly
            // expanded it. Only these three server observations may survive.
            body = (0..<3).map { index in
                var row: [String: Any] = ["id": course * 100 + index, "title": "Lecture", "start_at": "2026-11-\(String(format: "%02d", 3 + index * 7))T14:00:00Z",
                    "end_at": "2026-11-\(String(format: "%02d", 3 + index * 7))T15:00:00Z", "rrule": "FREQ=WEEKLY;COUNT=1000", "context_code": context]
                if index < 2 { row["series_uuid"] = series }
                return row
            }
        } else if path.hasSuffix("/front_page") { return HTTPReply(data: Data("{}".utf8), status: 404) }
        else { body = [] as [String] }
        return HTTPReply(data: try JSONSerialization.data(withJSONObject: body))
    }
}
