import Foundation
import Testing
@testable import SyllapaceKit

private struct ContextTransport: HTTPTransport {
    func send(_ request: URLRequest, maxBytes: Int) async throws -> HTTPReply {
        let payload: String
        switch request.url!.path {
        case "/api/v1/users/self/profile": payload = "{}"
        case "/api/v1/courses/1": payload = #"{"id":1,"syllabus_body":"","time_zone":"America/New_York"}"#
        case "/api/v1/courses/1/assignments": payload = #"[{"id":2,"name":"Homework 1","description":"<p>Submit your solution.</p>","due_at":"2026-11-12T04:59:00Z","unlock_at":"2026-11-01T13:00:00Z"}]"#
        case "/api/v1/announcements": payload = #"[{"id":3,"title":"Recitation","message":"<p>Recitation today at 4 PM.</p>","posted_at":"2026-11-03T13:00:00Z","delayed_post_at":"2026-11-02T13:00:00Z","updated_at":"2026-11-03T14:00:00Z"}]"#
        default: payload = "[]"
        }
        return HTTPReply(data: Data(payload.utf8))
    }
}

@Suite("Course context and actionable questions")
struct CanvasContextTests {
    @Test func canvasKeepsEffectiveDatesAndPublicationAnchor() async throws {
        let course = Course(id: "canvas:canvas.example.edu:443:course:1", name: "Example", code: "10001", timeZone: "America/New_York")
        let result = try await CanvasClient(host: "https://canvas.example.edu", token: "synthetic", transport: ContextTransport()).sync(courses: [course])
        let assignment = try #require(result.sources.first { $0.kind == .assignment })
        #expect(assignment.effectiveDueAt == CanvasClient.instant("2026-11-12T04:59:00Z"))
        #expect(assignment.availableAt == CanvasClient.instant("2026-11-01T13:00:00Z"))
        let announcement = try #require(result.sources.first { $0.kind == .announcement })
        #expect(announcement.publishedAt == CanvasClient.instant("2026-11-03T13:00:00Z"))
        #expect(announcement.updatedAt == CanvasClient.instant("2026-11-03T14:00:00Z"))
        #expect(announcement.text.contains("today"))
    }

    @Test func aKnownCanvasDeadlineAnswersOnlyItsOwnMissingDate() {
        var source = SourceDocument(id: "s", courseID: "c", title: "Homework 1", text: "Submit your work.", kind: .assignment)
        source.effectiveDueAt = Date(timeIntervalSince1970: 1_800_000_000)
        let record = SourceCurationRecord(fingerprint: "x", issues: ["Homework 1: missing due date.", "Homework 1 Part 2: missing due date.", "Lecture · Homework results: no date stated."])
        #expect(CurationReviewPolicy.questions(source: source, record: record, events: [], hasWeeklySchedule: false) == Array(record.issues!.dropFirst()))
        let oldFailure = SourceCurationRecord(fingerprint: "old", issues: ["Homework 1: date or time is not supported by the source.", "Exam: no date stated."])
        #expect(CurationReviewPolicy.questions(source: source, record: oldFailure, events: [], hasWeeklySchedule: false) == ["Exam: no date stated."])
        source.effectiveDueAt = nil
        #expect(CurationReviewPolicy.questions(source: source, record: record, events: [], hasWeeklySchedule: false).count == 3)
    }

    @Test func failuresAndLessonOutlinesAreNotManualDateQuestions() {
        let source = SourceDocument(id: "s", courseID: "c", title: "Syllabus", text: "Lecture 1. Final report.", kind: .syllabus)
        let failure = SourceCurationRecord(fingerprint: "x", failure: "Timed out")
        #expect(CurationReviewPolicy.questions(source: source, record: failure, events: [], hasWeeklySchedule: true).isEmpty)
        let record = SourceCurationRecord(fingerprint: "x", issues: ["Lecture 1 · Introduction: no calendar date is stated.", "Final report: no submission deadline stated."])
        #expect(CurationReviewPolicy.questions(source: source, record: record, events: [], hasWeeklySchedule: true) == [record.issues![1]])
        #expect(CurationReviewPolicy.questions(source: source, record: record, events: [], hasWeeklySchedule: false).count == 2)
    }
}
