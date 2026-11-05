import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Workspace bridge contract")
struct WorkspaceContractTests {
    private func request(_ method: String, _ payload: [String: Any] = [:], id: String = "request-1") throws -> WorkspaceRequest {
        try WorkspaceRequest.decode(JSONSerialization.data(withJSONObject: ["id": id, "method": method, "payload": payload]))
    }

    @Test func onlyDocumentedCommandsCrossNativeBoundary() throws {
        #expect(try request("workspace.ready").command == .ready)
        #expect(try request("workspace.addMaterial").command == .addMaterial)
        #expect(try request("workspace.chooseSemester").command == .chooseSemester)
        #expect(try request("event.create").command == .createEvent)
        #expect(try request("workspace.setView", ["view": "gantt"]).command == .setView(.gantt))
        #expect(try request("event.setProgress", ["eventID": "assignment-1", "expectedRevision": 3, "progress": "doing"]).command
                == .setProgress(eventID: "assignment-1", expectedRevision: 3, progress: .doing))
        #expect(try request("event.openEditor", ["eventID": "assignment-1"]).command == .openEditor(eventID: "assignment-1"))
        #expect(try request("source.open", ["eventID": "assignment-1"]).command == .openSource(eventID: "assignment-1"))
        #expect(try request("event.setPlan", ["eventID": "assignment-1", "expectedRevision": 3, "plannedStart": NSNull()]).command
                == .setPlan(eventID: "assignment-1", expectedRevision: 3, plannedStart: nil))
        #expect(try request("event.setPlan", ["eventID": "assignment-1", "expectedRevision": 3, "plannedStart": "2026-11-04T12:30:00Z"]).command
                == .setPlan(eventID: "assignment-1", expectedRevision: 3, plannedStart: "2026-11-04T12:30:00Z"))
    }

    @Test func commandsRejectUnexpectedFieldsAndValues() throws {
        let invalid: [(String, [String: Any])] = [
            ("native.readFile", ["path": "/etc/passwd"]),
            ("workspace.ready", ["url": "https://example.com"]),
            ("workspace.setView", ["view": "review"]),
            ("event.openEditor", ["eventID": ""]),
            ("source.open", ["eventID": "event", "url": "https://example.com"]),
            ("event.setProgress", ["eventID": "event", "expectedRevision": 1, "progress": "dueSoon"]),
            ("event.setProgress", ["eventID": "event", "expectedRevision": true, "progress": "done"]),
            ("event.setProgress", ["eventID": "event", "expectedRevision": 1.5, "progress": "done"]),
            ("event.setProgress", ["eventID": "event", "expectedRevision": -1, "progress": "done"]),
            ("event.setProgress", ["eventID": "event", "expectedRevision": "1", "progress": "done"]),
            ("event.setPlan", ["eventID": "event", "expectedRevision": 1, "plannedStart": "2026-11-04"]),
            ("event.setPlan", ["eventID": "event", "expectedRevision": 1, "plannedStart": "yesterday"]),
            ("event.setPlan", ["eventID": "event", "expectedRevision": 1])
        ]
        for (method, payload) in invalid {
            #expect(throws: WorkspaceContractError.self) { try request(method, payload) }
        }
        #expect(throws: WorkspaceContractError.self) { try request("workspace.ready", id: String(repeating: "x", count: 129)) }
        #expect(throws: WorkspaceContractError.self) { try request("workspace.ready", id: "") }
        #expect(throws: WorkspaceContractError.self) { try WorkspaceRequest.decode(Data(repeating: 32, count: 16_385)) }
        #expect(throws: (any Error).self) { try WorkspaceRequest.decode(Data("not JSON".utf8)) }
    }

    @Test func snapshotRoundTripPreservesCalendarDatesAndNulls() throws {
        let title = #"Course </script><script>alert('x')</script> \"quote\""#
        let event = WorkspaceEvent(id: "event", courseID: "course", courseLabel: "18-749", title: title,
                                   category: .deadline, subtype: "project", start: "2026-11-04", end: nil,
                                   dateOnly: true, timeZone: "America/New_York", progress: .doing, revision: 2)
        let snapshot = WorkspaceSnapshot(revision: 5, language: "zh-Hans", appearance: "dark", view: .calendar,
                                         scope: "Fall 2026", now: "2026-11-04T12:30:00Z", courses: [], events: [event])
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(WorkspaceSnapshot.self, from: data) == snapshot)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let first = try #require((body["events"] as? [[String: Any]])?.first)
        #expect(first["start"] as? String == "2026-11-04")
        #expect(first["title"] as? String == title)
        #expect(first["end"] is NSNull)
        #expect(first["plannedStart"] is NSNull)
        #expect(first["sourceURL"] is NSNull)
        var unsupported = body
        unsupported["schemaVersion"] = 2
        #expect(throws: WorkspaceContractError.self) {
            try JSONDecoder().decode(WorkspaceSnapshot.self, from: JSONSerialization.data(withJSONObject: unsupported))
        }
    }

    @Test func wireDatesKeepSourceDayAcrossTimeZones() throws {
        let instant = try #require(WorkspaceWireDate.parseInstant("2026-11-04T01:30:00Z"))
        #expect(WorkspaceWireDate.dateOnly(instant, timeZone: "America/New_York") == "2026-11-03")
        #expect(WorkspaceWireDate.dateOnly(instant, timeZone: "Asia/Shanghai") == "2026-11-04")
        #expect(WorkspaceWireDate.parseInstant(WorkspaceWireDate.instant(instant)) == instant)
        #expect(WorkspaceWireDate.parseInstant("2026-11-03T20:30:00-05:00") == instant)
        #expect(WorkspaceWireDate.parseInstant("2026-11-04") == nil)
        #expect(WorkspaceWireDate.parseInstant("2026-11-04T01:30:00") == nil)
    }

    @Test func navigationCannotEscapeBundledDocument() throws {
        let index = URL(fileURLWithPath: "/Applications/Syllapace.app/Contents/Resources/Workspace/index.html")
        #expect(WorkspaceNavigation.isLocalDocument(index, indexURL: index))
        #expect(WorkspaceNavigation.isLocalDocument(URL(string: index.absoluteString + "#calendar")!, indexURL: index))
        for raw in ["file:///etc/passwd", "file://remote.example/Applications/Syllapace.app/Contents/Resources/Workspace/index.html", index.absoluteString + ".evil", index.absoluteString + "?script=remote", "https://example.com/index.html", "about:blank"] {
            #expect(!WorkspaceNavigation.isLocalDocument(try #require(URL(string: raw)), indexURL: index))
        }
        #expect(WorkspaceNavigation.externalURL(URL(string: "https://canvas.example.edu/courses/1?tab=syllabus")!) != nil)
        for raw in ["http://example.com", "file:///etc/passwd", "javascript:alert(1)", "data:text/html,hello", "https://user:secret@example.com"] {
            #expect(WorkspaceNavigation.externalURL(try #require(URL(string: raw))) == nil)
        }
    }
}
