import Foundation
import Testing
@testable import SyllapaceKit

private actor CoverageTransport: HTTPTransport {
    var routes: [String: HTTPReply]
    var requests: [URLRequest] = []
    init(_ routes: [String: HTTPReply] = [:]) { self.routes = routes }
    func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
        requests.append(request)
        let path = request.url!.path
        if let response = routes[path] { return response }
        if path == "/api/v1/users/self/profile" { return coverageJSON("{}") }
        if path.hasSuffix("/front_page") { return coverageJSON("{}", status: 404) }
        return coverageJSON("[]")
    }
}
private func coverageJSON(_ value: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPReply { HTTPReply(data: Data(value.utf8), status: status, headers: headers) }
private let coverageNow = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
private func coverageCourse(_ id: Int = 1) -> Course {
    Course(id: "canvas:canvas.example.edu:443:course:\(id)", name: "Synthetic course", code: "SYN-\(id)",
           term: AcademicTerm(id: "canvas:canvas.example.edu:443:term:6", name: "Fall 2026", startAt: ISO8601DateFormatter().date(from: "2026-08-10T04:00:00Z"), endAt: ISO8601DateFormatter().date(from: "2027-02-09T05:00:00Z")), timeZone: "America/New_York")
}

@Suite("Canvas scope and native content") struct CanvasCoverageTests {
    @Test func discoveryContainsTermsButNeverFetchesCourseContent() async throws {
        let transport = CoverageTransport(["/api/v1/courses": coverageJSON(#"[{"id":1,"name":"Synthetic Fall","course_code":"SYN-1","term":{"id":6,"name":"Fall 2026","start_at":"2026-08-10T04:00:00Z","end_at":"2027-02-09T05:00:00Z"},"concluded":false},{"id":2,"name":"Synthetic Spring","term":{"id":5,"name":"Spring 2026"},"concluded":true},{"id":3,"name":"Synthetic Portal","term":{"id":1,"name":"Default Term"}}]"#)])
        let courses = try await CanvasClient(host: "canvas.example.edu", token: "synthetic", transport: transport).discoverCourses()
        #expect(courses.count == 3)
        #expect(courses[0].term?.name == "Fall 2026")
        #expect(courses[1].concluded == true)
        #expect(courses[2].term?.startAt == nil)
        let requests = await transport.requests
        #expect(requests.count == 2)
        let query = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(query.contains(.init(name: "include[]", value: "term")))
        #expect(query.contains(.init(name: "state[]", value: "completed")))
        #expect(!query.contains(where: { $0.name == "enrollment_state" || $0.value == "syllabus_body" }))
    }

    @Test func emptyOrForeignSelectionCannotFetchContent() async throws {
        let transport = CoverageTransport()
        let client = try CanvasClient(host: "canvas.example.edu", token: "synthetic", transport: transport)
        #expect(try await client.sync(courses: []).events.isEmpty)
        let foreign = Course(id: "canvas:other.example.edu:443:course:1", name: "Other", code: "OTHER")
        await #expect(throws: ConnectorError.invalidResponse) { try await client.sync(courses: [foreign], now: coverageNow) }
        #expect(await transport.requests.isEmpty)
    }

    @Test func selectedCourseSourcesSurviveHiddenFilesAndDoNotReadOtherCourses() async throws {
        let transport = CoverageTransport([
            "/api/v1/courses/1": coverageJSON(#"{"id":1,"syllabus_body":"<p>Read the <a href='/courses/1/pages/schedule'>schedule</a>.</p>","time_zone":"America/New_York"}"#),
            "/api/v1/courses/1/assignment_groups": coverageJSON(#"[{"id":3,"name":"Projects"}]"#),
            "/api/v1/courses/1/assignments": coverageJSON(#"[{"id":10,"name":"Milestone 1","assignment_group_id":3,"description":"<p>Build the first prototype.</p>","due_at":"2026-11-20T23:00:00Z","submission":{"workflow_state":"graded","submitted_at":"2026-11-19T23:00:00Z","grade":"9","score":9,"late":false,"missing":false}}]"#),
            "/api/v1/announcements": coverageJSON(#"[{"id":50,"title":"Updated timetable","message":"<p>See <a href='https://docs.google.com/spreadsheets/d/synthetic/edit#gid=0'>schedule</a> and <a href='/courses/2/pages/private'>another course</a>.</p>","attachments":[{"id":30,"display_name":"reading.pdf"}]}]"#),
            "/api/v1/courses/1/modules": coverageJSON(#"[{"id":70,"name":"Week 1"}]"#),
            "/api/v1/courses/1/modules/70/items": coverageJSON(#"[{"id":71,"type":"Page","title":"Schedule","page_url":"schedule","html_url":"https://canvas.example.edu/courses/1/pages/schedule"},{"id":72,"type":"File","content_id":30,"title":"Reading","html_url":"https://canvas.example.edu/courses/1/files/30"},{"id":73,"type":"ExternalTool","title":"Piazza","external_url":"https://piazza.example.edu/course/synthetic"}]"#),
            "/api/v1/courses/1/pages/schedule": coverageJSON(#"{"page_id":80,"title":"Schedule","url":"schedule","body":"<p>Lecture Friday 10:00.</p><a href='/courses/1/files/30'>Reading</a>","published":true}"#),
            "/api/v1/courses/1/files/30": coverageJSON(#"{"id":30,"display_name":"reading.pdf","url":"https://files.example.net/reading.pdf","locked_for_user":false,"hidden_for_user":false}"#),
            "/api/v1/courses/1/tabs": coverageJSON(#"[{"id":"home"},{"id":"assignments"}]"#)
        ])
        let result = try await CanvasClient(host: "canvas.example.edu", token: "synthetic", transport: transport).sync(courses: [coverageCourse()], now: coverageNow)
        #expect(result.events.count == 1)
        #expect(result.events[0].kind == .project)
        #expect(result.events[0].submission?.score == 9)
        #expect(result.events[0].completed)
        #expect(result.files.count == 1)
        #expect(result.files[0].title == "reading.pdf")
        #expect(result.sources.contains { $0.kind == .announcement && $0.links?.contains(where: { $0.url.contains("docs.google.com") }) == true })
        #expect(result.sources.contains { $0.title == "Schedule" && $0.text.contains("Lecture") })
        #expect(result.warnings.contains { $0.contains("Files") })
        let requests = await transport.requests
        #expect(!requests.contains { $0.url!.path.hasPrefix("/api/v1/courses/2") })
        #expect(!requests.contains { $0.url!.path == "/api/v1/courses/1/files" })
        #expect(requests.filter { $0.url!.path == "/api/v1/courses/1/files/30" }.count == 1)
        #expect(requests.filter { $0.url!.path == "/api/v1/courses/1/pages/schedule" }.count == 1)
        #expect(requests.allSatisfy { $0.url?.host == "canvas.example.edu" && $0.httpMethod == "GET" })
        let announcementRequest = try #require(requests.first { $0.url!.path == "/api/v1/announcements" })
        let query = URLComponents(url: announcementRequest.url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(query.contains { $0.name == "start_date" && $0.value!.hasPrefix("2026-07") })
        #expect(query.contains { $0.name == "end_date" && $0.value!.hasPrefix("2026-11-04") })
    }

    @Test func quizzesJoinAssignmentsAndCalendarKeepsDuration() async throws {
        let transport = CoverageTransport([
            "/api/v1/courses/1": coverageJSON(#"{"id":1,"syllabus_body":""}"#),
            "/api/v1/courses/1/assignments": coverageJSON(#"[{"id":10,"name":"Quiz 1","quiz_id":20,"due_at":"2026-11-12T20:00:00Z"},{"id":11,"name":"New Quiz","is_quiz_assignment":true,"due_at":"2026-11-13T20:00:00Z"}]"#),
            "/api/v1/courses/1/quizzes": coverageJSON(#"[{"id":20,"assignment_id":10,"title":"Quiz 1","due_at":"2026-11-12T20:00:00Z"},{"id":21,"title":"Practice quiz","due_at":null}]"#),
            "/api/v1/calendar_events": coverageJSON(#"[{"id":90,"title":"Lecture","start_at":"2026-11-12T15:00:00Z","end_at":"2026-11-12T16:30:00Z","location_name":"Room 101"},{"id":91,"title":"Hidden parent","hidden":true}]"#)
        ])
        let result = try await CanvasClient(host: "canvas.example.edu", token: "synthetic", transport: transport).sync(courses: [coverageCourse()], now: coverageNow)
        #expect(result.events.count == 4)
        #expect(result.events.filter { $0.title == "Quiz 1" }.count == 1)
        #expect(result.events.filter { $0.kind == .quiz }.count == 3)
        let lecture = try #require(result.events.first { $0.kind == .session })
        #expect(lecture.endsAt?.timeIntervalSince(lecture.date!) == 5400)
        #expect(lecture.location == "Room 101")
        let requests = await transport.requests
        let calendar = try #require(requests.first { $0.url!.path == "/api/v1/calendar_events" })
        #expect(!calendar.url!.absoluteString.contains("all_events"))
        #expect(calendar.url!.absoluteString.contains("start_date"))
    }

    @Test func deniedDirectoryDoesNotDiscardOtherNativeResources() async throws {
        let transport = CoverageTransport([
            "/api/v1/courses/1": coverageJSON(#"{"id":1,"syllabus_body":"<p>Exam November 20.</p>"}"#),
            "/api/v1/courses/1/tabs": coverageJSON(#"[{"id":"files"}]"#),
            "/api/v1/courses/1/files": coverageJSON("{}", status: 403),
            "/api/v1/courses/1/modules": coverageJSON("{}", status: 403),
            "/api/v1/courses/1/assignments": coverageJSON(#"[{"id":10,"name":"Homework","due_at":"2026-11-20T20:00:00Z"}]"#)
        ])
        let result = try await CanvasClient(host: "canvas.example.edu", token: "synthetic", transport: transport).sync(courses: [coverageCourse()], now: coverageNow)
        #expect(result.events.count == 1)
        #expect(result.sources.first?.text == "Exam November 20.")
        #expect(result.warnings.contains { $0.contains("Files directory") })
    }

    @Test func htmlKeepsSafeLinksLabelsEntitiesAndTableText() {
        let html = #"<script><a href='https://evil.example/test'>hidden</a></script><table><tr><td>Week 1</td><td>Project</td></tr></table><a href='/courses/1/pages/schedule?view=1&amp;mode=2'>Weekly <b>schedule</b></a><a href=https://docs.google.com/spreadsheets/d/synthetic/edit#gid=42>Sheet</a><a href='javascript:alert(1)'>bad</a><a href='https://user:secret@example.net/file'>bad</a>"#
        let parsed = CanvasHTML.parse(html, baseURL: URL(string: "https://canvas.example.edu/courses/1/assignments/syllabus")!)
        #expect(parsed.links.count == 2)
        #expect(parsed.links[0].title == "Weekly schedule")
        #expect(parsed.links[0].url == "https://canvas.example.edu/courses/1/pages/schedule?view=1&mode=2")
        #expect(parsed.links[1].url.hasSuffix("#gid=42"))
        #expect(parsed.text.contains("Week 1 | "))
        #expect(!parsed.text.contains("hidden"))
    }

    @Test func embeddedScheduleRemainsAnExternalReference() {
        let result = CanvasHTML.parse(#"<iframe title='Course schedule' src='https://docs.google.com/spreadsheets/d/e/synthetic/pubhtml?widget=true&amp;headers=false'></iframe>"#, baseURL: URL(string: "https://canvas.example.edu/courses/1")!)
        #expect(result.links.count == 1)
        #expect(result.links[0].title == "Course schedule")
        #expect(result.links[0].kind == "external")
        #expect(result.links[0].url.hasSuffix("widget=true&headers=false"))
    }
}
