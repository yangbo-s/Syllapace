import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Semester and source semantics")
struct SemesterSemanticsTests {
    @Test func semesterYearDoesNotComeFromAccessWindow() {
        let term = AcademicTerm(id: "spring", name: "Spring 2026", startAt: Date(timeIntervalSince1970: 1_767_000_000))
        #expect(term.academicYear == 2026)
        #expect(AcademicTerm(id: "unknown", name: "Default Term").academicYear == nil)
        #expect(AcademicTerm(id: "long", name: "2025–2027").academicYear == nil)
    }
    @Test func distinctNativeAssignmentsWithSameTitleStayIndependent() {
        let first = AcademicEvent(id: "canvas:example:assignment:1", courseID: "c", title: "Reading response", date: .now, state: .approved, sourceID: "source1")
        var second = first; second.id = "canvas:example:assignment:2"; second.sourceID = "source2"; second.date = .now.addingTimeInterval(604800)
        let result = Reconciler.merge(existing: [first], incoming: [second])
        #expect(result.count == 2); #expect(result.allSatisfy { $0.state == .approved })
    }
    @Test func linkedMaterialLimitIsReported() throws {
        let url = try #require(URL(string: "https://example.edu/courses/1"))
        let html = (0..<201).map { "<a href=\"https://docs.example.net/\($0)\">Schedule \($0)</a>" }.joined()
        let parsed = CanvasHTML.parse(html, baseURL: url)
        #expect(parsed.links.count == 200); #expect(parsed.truncated)
    }
    @Test func embeddedScheduleBeyondLinkLimitIsReported() throws {
        let url = try #require(URL(string: "https://example.edu/courses/1"))
        let anchors = (0..<200).map { "<a href=\"https://docs.example.net/\($0)\">Reading \($0)</a>" }.joined()
        let schedule = #"<iframe title="Course schedule" src="https://docs.google.com/spreadsheets/d/e/synthetic/pubhtml"></iframe>"#
        let parsed = CanvasHTML.parse(anchors + schedule, baseURL: url)
        #expect(parsed.links.count == 200)
        #expect(parsed.truncated)
        #expect(!parsed.links.contains { $0.url.contains("docs.google.com") })
    }
    @Test func legacyArchiveLoadsWithoutImplicitSelection() throws {
        let legacy = #"{"schemaVersion":1,"courses":[{"id":"canvas:example.edu:443:course:7","name":"Old course","code":"OLD","color":0}],"events":[],"sources":[]}"#
        let archive = try JSONDecoder().decode(AppArchive.self, from: Data(legacy.utf8))
        #expect(archive.canvasSelection == nil)
        #expect(archive.courses.first?.term == nil)
        #expect(archive.courses.first?.isCanvas == true)
        #expect(try JSONDecoder().decode(AppArchive.self, from: JSONEncoder().encode(archive)).courses == archive.courses)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ArchiveStore(url: folder.appendingPathComponent("archive.json"))
        try Data(legacy.utf8).write(to: store.url)
        let migrated = try store.load()
        #expect(migrated.schemaVersion == 2)
        #expect(try String(contentsOf: store.url, encoding: .utf8) == legacy)
        try store.save(migrated)
        #expect(try String(contentsOf: store.backupURL, encoding: .utf8) == legacy)
        #expect(try store.load().courses == archive.courses)
    }
    @Test func explicitSelectionDoesNotIncludeUnselectedOrDefaultTerms() {
        let fall = Course(id: "canvas:example.edu:443:course:7", name: "Fall", code: "F", term: AcademicTerm(id: "fall", name: "Fall 2026"))
        let portal = Course(id: "canvas:example.edu:443:course:8", name: "Portal", code: "P")
        let personal = Course(id: "personal", name: "Personal", code: "Personal")
        let scope = CanvasSelection(termID: "fall", courseIDs: [fall.id])
        #expect(scope.includes(fall)); #expect(!scope.includes(portal)); #expect(scope.includes(personal))
        #expect(!CanvasSelection().includes(fall))
    }
    @Test func confirmedEndChangeRequiresReviewAndDoesNotRepeat() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let original = AcademicEvent(id: "session", courseID: "c", title: "Lecture", kind: .session, date: start, dateOnly: false, state: .approved, endsAt: start.addingTimeInterval(3600))
        var incoming = original; incoming.endsAt = start.addingTimeInterval(5400)
        let once = Reconciler.merge(existing: [original], incoming: [incoming])
        #expect(once[0].state == .conflict)
        #expect(once[0].endsAt == original.endsAt)
        #expect(once[0].proposedEndsAt == incoming.endsAt)
        let twice = Reconciler.merge(existing: once, incoming: [incoming])
        #expect(twice[0].revision == once[0].revision)
    }
    @Test func submissionRefreshRetainsGradeAndDoesNotInventZero() {
        let original = AcademicEvent(id: "assignment", courseID: "c", title: "Project")
        var incoming = original; incoming.submission = SubmissionStatus(state: "submitted", late: false); incoming.completed = true
        let result = Reconciler.merge(existing: [original], incoming: [incoming])[0]
        #expect(result.completed); #expect(result.submission?.score == nil)
        #expect(result.submission?.state == "submitted")
    }
    @Test func exportRetainsExplicitSessionDurationAndLocation() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let session = AcademicEvent(courseID: "c", title: "Lab", kind: .session, date: start, dateOnly: false, timeZone: "UTC", state: .approved, endsAt: start.addingTimeInterval(3600), location: "Room 2, East")
        let text = ICSExporter.export(events: [session], courses: [])
        #expect(text.contains("DTEND:")); #expect(text.contains("LOCATION:Room 2\\, East"))
        #expect(try #require(CalendarEventPayload(event: session)).end == session.endsAt)
        var deadline = session; deadline.endsAt = nil
        #expect(!ICSExporter.export(events: [deadline], courses: []).contains("DTEND:"))
        var invalid = session; invalid.endsAt = start.addingTimeInterval(-1)
        #expect(CalendarEventPayload(event: invalid) == nil)
    }
    @Test func sheetExportRetainsSelectedTab() throws {
        let shared = try #require(URL(string: "https://docs.google.com/spreadsheets/d/example/edit#gid=42"))
        let destination = try PublicDocumentClient.downloadURL(shared)
        #expect(destination.path == "/spreadsheets/d/example/export")
        #expect(destination.query?.contains("gid=42") == true)
        #expect(destination.query?.contains("format=csv") == true)
        let published = try #require(URL(string: "https://docs.google.com/spreadsheets/d/e/example/pubhtml?gid=7"))
        #expect(try PublicDocumentClient.downloadURL(published).path == "/spreadsheets/d/e/example/pub")
    }
    @Test func publicImportsNeverSendCredentialsAndRetainCellText() async throws {
        let transport = PublicSourceTransport(replies: [HTTPReply(data: Data(), status: 302, headers: ["Location": "https://files.example.net/schedule.csv"]), HTTPReply(data: Data("Week,Due\nProject,November 20 2026".utf8), headers: ["Content-Type": "text/csv"])])
        let result = try await PublicDocumentClient(transport: transport).read(link: SourceLink(url: "https://example.edu/schedule.csv", title: "Schedule"), courseID: "c")
        #expect(result.text.contains("Project,November 20 2026")); #expect(result.kind == .external)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
    }
    @Test func signInPagesAreNotImportedAsCourseContent() async throws {
        let transport = PublicSourceTransport(replies: [HTTPReply(data: Data(), status: 302, headers: ["Location": "https://accounts.google.com/ServiceLogin"])])
        await #expect(throws: PublicDocumentError.self) {
            _ = try await PublicDocumentClient(transport: transport).read(link: SourceLink(url: "https://docs.google.com/spreadsheets/d/private/edit", title: "Private schedule"), courseID: "c")
        }
        #expect(await transport.requests.count == 1)
    }
}

private actor PublicSourceTransport: HTTPTransport {
    var replies: [HTTPReply]
    var requests: [URLRequest] = []
    init(replies: [HTTPReply]) { self.replies = replies }
    func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
        requests.append(request)
        guard !replies.isEmpty else { throw ConnectorError.invalidResponse }
        return replies.removeFirst()
    }
}
