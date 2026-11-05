import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Syllabus table evidence")
struct SyllabusTableContextTests {
    private let course = Course(id: "course", name: "Synthetic systems course", code: "10-101",
                                term: AcademicTerm(id: "term", name: "Fall 2026"), timeZone: "America/New_York")

    @Test(arguments: [false, true]) func monthRowsBecomeOneVerifiableDeadlineWithReleaseAndSeconds(html: Bool) throws {
        let rows = html ? "September | 8 | Tues. | release HW1 | 22 | Tues. | HW1 due, release HW2 | October | 6 | Tues. | HW2 due" : """
        September
        [Page 6]
        6
        8 Tues. Lecture 3: Synthetic topic
        release HW 1
        22 Tues. Lecture 7: Another topic
        HW1 due, release HW2
        October
        6 Tues. Lecture 9: Final topic
        HW 2 due
        """
        let source = syllabus("Completed homeworks are due at 11:59:59pm ET at the date indicated when posted.\n" + rows)
        let prepared = CurationContext.prepare(source: source, course: course, relatedSources: [])
        let proof = "Homework 1 — released 2026-09-08; due 2026-09-23T03:59:59Z"
        #expect(prepared.text.hasPrefix(source.text))
        #expect(prepared.text.contains(proof))
        let result = try parse(prepared, title: "Homework 1", date: "2026-09-22T23:59:59-04:00", dateOnly: false, proof: proof)
        #expect(result.events.count == 1 && result.issues.isEmpty)
        #expect(result.events.first?.releasedAt == CanvasClient.instant("2026-09-08T16:00:00Z"))
        #expect(prepared.text.contains("Homework 2 — released 2026-09-22; due 2026-10-07T03:59:59Z"))
    }

    @Test func aNamedDeliverableDoesNotInheritHomeworkTime() throws {
        let source = syllabus("Completed homeworks are due at 11:59:59pm ET.\nDecember\n1 Tues. HW 5 due\n3 Thurs. Blog post due")
        let prepared = CurationContext.prepare(source: source, course: course, relatedSources: [])
        let proof = "Blog post — due 2026-12-03"
        #expect(prepared.text.contains(proof))
        let result = try parse(prepared, title: "Project · Blog post", date: "2026-12-03", dateOnly: true, proof: proof, kind: .project)
        #expect(result.events.count == 1 && result.events.first?.dateOnly == true)
    }

    @Test(arguments: ["September\n22 Thurs. HW 1 due", "22 Tues. HW 1 due", "September\n22 Tues. HW 1 Part A due", "September\n22 Tues. HW 1 due\n29 Tues. HW 1 due"])
    func ambiguousRowsDoNotCreateResolvedEvidence(_ text: String) {
        let source = syllabus(text)
        #expect(CurationContext.prepare(source: source, course: course, relatedSources: []).text == source.text)
    }

    @Test func explicitSecondsAreVerifiedWithoutRoundingOrLosingPM() throws {
        let source = syllabus("Homework 1 due September 22 at 11:59:59pm ET.")
        let result = try parse(source, title: "Homework 1", date: "2026-09-22T23:59:59-04:00", dateOnly: false, proof: source.text)
        #expect(result.events.count == 1 && result.issues.isEmpty)
        let wrong = try parse(source, title: "Homework 1", date: "2026-09-22T23:59:00-04:00", dateOnly: false, proof: source.text)
        #expect(wrong.events.isEmpty && !wrong.issues.isEmpty)
    }

    @Test func currentCanvasAssignmentDatesSupersedePreliminarySyllabusRows() {
        let source = syllabus("September\n8 Tues. release HW1\n22 Tues. HW1 due")
        var assignment = SourceDocument(id: "canvas-assignment", courseID: course.id, title: "Synthetic solver",
                                        text: "10-101: Homework 1\nReleased: September 9th\nDue: September 29th", kind: .assignment)
        assignment.effectiveDueAt = CanvasClient.instant("2026-09-30T03:59:59Z")
        let result = CurationContext.prepare(source: source, course: course, relatedSources: [assignment])
        #expect(result.text.contains("Homework 1 — released 2026-09-09; due 2026-09-30T03:59:59Z"))
        #expect(result.text.contains("Canvas effective assignment dates"))
        #expect(!result.text.contains("Homework 1 — released 2026-09-08; due 2026-09-22"))
    }

    @Test func ambiguousDaylightSavingClockNeverBecomesAnAbsoluteDate() {
        let source = syllabus("Completed homeworks are due at 1:30:59am ET.\nNovember\n1 Sun. HW 1 due")
        #expect(CurationContext.prepare(source: source, course: course, relatedSources: []).text == source.text)
    }

    private func syllabus(_ text: String) -> SourceDocument {
        SourceDocument(id: "source", courseID: course.id, title: "Course syllabus", text: text, kind: .syllabus)
    }
    private func parse(_ source: SourceDocument, title: String, date: String, dateOnly: Bool, proof: String, kind: EventKind = .assignment) throws -> CurationResult {
        let data = try JSONSerialization.data(withJSONObject: ["events": [["title": title, "kind": kind.rawValue, "date": date,
            "dateOnly": dateOnly, "timeZone": "America/New_York", "evidence": proof]], "issues": []])
        return try LLMClient.parseCuration(content: String(decoding: data, as: UTF8.self), source: source, year: 2026, timeZone: "America/New_York")
    }
}
