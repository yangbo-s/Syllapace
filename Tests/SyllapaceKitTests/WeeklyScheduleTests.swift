import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Cached syllabus schedules") struct WeeklyScheduleTests {
    let zone = "America/New_York"
    func date(_ value: String) -> Date { CanvasClient.instant(value)! }
    func extract(_ text: String, bounded: Bool = true) -> [AcademicEvent] {
        WeeklySchedule.extract(source: SourceDocument(id: "syllabus", courseID: "course", title: "syllabus", text: text, kind: .syllabus), year: 2026,
            timeZone: zone, termStart: bounded ? date("2026-10-26T04:00:00Z") : nil, termEnd: bounded ? date("2026-11-09T05:00:00Z") : nil)
    }
    @Test func explicitWeeklyLinesProduceSeparateLectureAndRecitationSeriesAcrossDST() throws {
        let events = extract("Lectures: Tuesdays and Thursdays 9:30am-10:50am ET, Room 145\nRecitations: Fridays 10:00am-10:50am ET, Room 203\nOffice hours: Mondays 1pm-2pm")
        #expect(events.count == 6)
        #expect(Set(events.compactMap(\.sourceSeriesID)).count == 2)
        #expect(events.filter { $0.subtype == .recitation }.count == 2)
        #expect(events.contains { $0.date == date("2026-10-27T13:30:00Z") })
        #expect(events.contains { $0.date == date("2026-11-03T14:30:00Z") })
        #expect(events.allSatisfy { $0.endsAt != nil && $0.state == .approved })
        let saved = Reconciler.merge(existing: [], incoming: events)
        #expect(Reconciler.merge(existing: saved, incoming: events) == saved)
        #expect(events == extract("Lectures: Tuesdays and Thursdays 9:30am-10:50am ET, Room 145\nRecitations: Fridays 10:00am-10:50am ET, Room 203\nOffice hours: Mondays 1pm-2pm"))
    }
    @Test func syllabusTimeLineNeedsBoundsAndNeverGuessesFromClassNumbers() {
        #expect(extract("Time: Thursday, 6:00 PM – 8:50 PM").count == 2)
        #expect(extract("Time: Thursday, 6:00 PM – 8:50 PM", bounded: false).isEmpty)
        #expect(extract("Class 1: Introduction\nClass 2: Ideas\nLectures: Tuesdays, time TBD").isEmpty)
        #expect(extract("Lectures: Thursdays 9:30am–10:50am except exam week").isEmpty)
    }
    @Test func fileRevisionPersistsAndUnchangedFileDoesNotDownloadAgain() throws {
        var source = SourceDocument(id: "file", courseID: "course", title: "syllabus.pdf", text: "Saved text")
        source.remoteRevision = "v1:100"
        let saved = try JSONDecoder().decode(SourceDocument.self, from: JSONEncoder().encode(source))
        var file = CanvasFile(id: "file", courseID: "course", title: "syllabus.pdf", url: "https://canvas.example.edu/file", revision: "v1:100")
        #expect(!file.needsDownload(saved: saved))
        file.revision = "v2:100"; #expect(file.needsDownload(saved: saved))
        file.revision = nil; #expect(!file.needsDownload(saved: saved))
        #expect(file.needsDownload(saved: nil))
    }
    @Test func failedCurationCheckpointSurvivesRestart() throws {
        let record = SourceCurationRecord(fingerprint: "unchanged", failure: "Network unavailable")
        let restored = try JSONDecoder().decode(SourceCurationRecord.self, from: JSONEncoder().encode(record))
        #expect(restored == record)
    }
}
