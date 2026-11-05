import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Written date evidence")
struct DateEvidenceRegressionTests {
    @Test(arguments: [
        ("Project proposal due Sep 11, 2026 at 11:59 p.m.", "2026-09-11T23:59:00-04:00"),
        ("Group submission deadline: Tuesday, September 8, at 11:59 p.m.", "2026-09-08T23:59:00-04:00"),
        ("Customer Discovery Report\nSubmission Date – 22nd October, 11:59 PM", "2026-10-22T23:59:00-04:00"),
        ("Project due 22 October 2026 at 9 a.m.", "2026-10-22T09:00:00-04:00"),
        ("Project due 22nd Oct., 2026 at 12:00 p.m.", "2026-10-22T12:00:00-04:00"),
        ("Project due October 22 at 12:00 a.m.", "2026-10-22T00:00:00-04:00")
    ])
    func explicitWrittenDatesSurviveModelValidation(_ fixture: (String, String)) throws {
        let source = SourceDocument(id: "written-date", courseID: "course", title: "Project", text: fixture.0)
        let item: [String: Any] = ["title": "Project", "kind": "project", "date": fixture.1,
                                  "dateOnly": false, "timeZone": "America/New_York", "evidence": fixture.0]
        let content = String(decoding: try JSONSerialization.data(withJSONObject: ["events": [item], "issues": []]), as: UTF8.self)
        let result = try LLMClient.parseCuration(content: content, source: source, year: 2026, timeZone: "America/New_York")
        #expect(result.issues.isEmpty)
        #expect(result.events.count == 1)
        #expect(result.events.first?.date == CanvasClient.instant(fixture.1))
        #expect(result.events.first?.dateOnly == false)
    }

    @Test func dottedMeridiemWorksForWeeklyRangesAndDoesNotMatchTheWrongHalfDay() {
        let clocks = EvidenceClock.values(in: "Lectures: Tuesday and Thursday, 9:30 a.m.–10:50 a.m.; Recitation 1–2:30 p.m.")
        #expect(clocks.map { $0.0 * 60 + $0.1 } == [570, 650, 780, 870])
        let evidence = "Project due September 11 at 11:59 p.m."
        #expect(!RuleExtractor.evidenceSupports(date: CanvasClient.instant("2026-09-11T11:59:00-04:00")!,
                                               dateOnly: false, timeZone: "America/New_York", year: 2026, evidence: evidence, kind: .project))
        #expect(!RuleExtractor.evidenceSupports(date: CanvasClient.instant("2026-09-11T12:00:00-04:00")!,
                                               dateOnly: true, timeZone: "America/New_York", year: 2026, evidence: evidence, kind: .project))
    }

    @Test func ambiguousAndImpossibleDatesRemainUnsupported() {
        for (text, proposed) in [
            ("Project due 09/11 at 11:59 PM", "2026-09-11T23:59:00-04:00"),
            ("Project due 31st February at 11:59 p.m.", "2026-03-03T23:59:00-05:00"),
            ("Project due November 1 at 1:30 a.m.", "2026-11-01T01:30:00-04:00"),
            ("Project due March 8 at 2:30 a.m.", "2026-03-08T03:30:00-04:00")
        ] {
            #expect(!RuleExtractor.evidenceSupports(date: CanvasClient.instant(proposed)!, dateOnly: false,
                                                   timeZone: "America/New_York", year: 2026, evidence: text, kind: .project))
        }
    }

    @Test func releaseMetadataKeepsAbsoluteTimeAndDateOnlyMeaning() throws {
        let due = CanvasClient.instant("2026-11-20T04:59:00Z")!
        let exact = try #require(RuleExtractor.releaseDate(in: "Homework 4 available from 2026-11-05T17:00:00Z; due 2026-11-20T04:59:00Z",
                                                          year: 2026, timeZone: "America/New_York", due: due))
        #expect(exact.0 == CanvasClient.instant("2026-11-05T17:00:00Z"))
        #expect(exact.1 == false)
        let civil = try #require(RuleExtractor.releaseDate(in: "Homework 4 available from 2026-11-05; due 2026-11-20",
                                                          year: 2026, timeZone: "America/New_York", due: due))
        #expect(civil.1 == true)
        #expect(RuleExtractor.releaseDate(in: "Homework 4 available from 2026-11-21T17:00:00Z; due 2026-11-20T04:59:00Z",
                                          year: 2026, timeZone: "America/New_York", due: due) == nil)
    }
}
