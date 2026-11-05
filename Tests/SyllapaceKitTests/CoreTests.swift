import Foundation
import Testing
@testable import SyllapaceKit

private func source(_ text: String) -> SourceDocument { SourceDocument(id: "syllabus", courseID: "course", title: "Syllabus", text: text) }
private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private func temporary() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("syllapace-test-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Dates and evidence") struct ExtractionTests {
    @Test func explicitDateRemainsDateOnly() throws {
        let event = try #require(RuleExtractor.extract(source: source("Midterm exam: November 12, 2026"), year: 2026, timeZone: "America/New_York").first)
        #expect(event.dateOnly)
        #expect(event.state == .approved)
        #expect(event.title == "Midterm exam")
        #expect(event.date == instant("2026-11-12T17:00:00Z"))
        #expect(event.evidence == "Midterm exam: November 12, 2026")
    }
    @Test func exactTimeIsPreserved() throws {
        let event = try #require(RuleExtractor.extract(source: source("Project 2 due 2026-11-12 at 11:59 PM"), year: 2026, timeZone: "America/New_York").first)
        #expect(!event.dateOnly)
        #expect(event.date == instant("2026-11-13T04:59:00Z"))
    }
    @Test(arguments: [
        "Final exam: 03/04",
        "Project due November 12 or November 20",
        "Assignment due February 30, 2026",
        "Project due 2026-03-08 02:30",
        "Project due November 12 11:59 PM PST",
        "Project due 2026-11-01 01:30"
    ]) func unresolvedDatesBecomeSourceIssuesWithoutCalendarEntries(_ text: String) {
        let result = RuleExtractor.curate(source: source(text), year: 2026, timeZone: "America/New_York")
        #expect(result.events.isEmpty)
        #expect(result.issues.count == 1)
    }
    @Test func explicitReleaseAndDueAreNoLongerAmbiguous() throws {
        let result = RuleExtractor.curate(source: source("Project released November 12, due November 20"), year: 2026, timeZone: "America/New_York")
        let event = try #require(result.events.first)
        #expect(result.events.count == 1 && result.issues.isEmpty)
        #expect(event.date.map { WorkspaceWireDate.dateOnly($0, timeZone: event.timeZone) } == "2026-11-20")
        #expect(event.releasedAt.map { WorkspaceWireDate.dateOnly($0, timeZone: event.timeZone) } == "2026-11-12")
    }
    @Test func pageEvidenceAndMissingDateSurviveInTheSource() {
        let document = source("[Page 3]\nFinal presentation slides due during week 6")
        let result = RuleExtractor.curate(source: document, year: 2026, timeZone: "UTC")
        #expect(document.text.hasPrefix("[Page 3]"))
        #expect(result.events.isEmpty)
        #expect(result.issues.count == 1)
    }
    @Test func repeatedTitlesHaveDistinctStableIdentities() {
        let value = source("Quiz: November 5\nQuiz: November 12")
        let first = RuleExtractor.extract(source: value, year: 2026, timeZone: "UTC")
        let second = RuleExtractor.extract(source: value, year: 2026, timeZone: "UTC")
        #expect(first.count == 2)
        #expect(Set(first.map(\.id)).count == 2)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(Reconciler.merge(existing: [], incoming: first).count == 2)
    }
}

@Suite("Source reconciliation") struct ReconciliationTests {
    @Test func approvedDateChangesBecomeConflictsWithoutOverwriting() throws {
        let oldDate = instant("2026-11-12T12:00:00Z"), newDate = instant("2026-11-14T12:00:00Z")
        let old = AcademicEvent(id: "one", courseID: "course", title: "Project", date: oldDate, state: .approved, sourceID: "syllabus")
        var next = old; next.date = newDate; next.observedSourceDate = newDate
        let merged = try #require(Reconciler.merge(existing: [old], incoming: [next]).first)
        #expect(merged.date == oldDate)
        #expect(merged.proposedDate == newDate)
        #expect(merged.state == .conflict)
        #expect(merged.revision == 1)
        let repeated = try #require(Reconciler.merge(existing: [merged], incoming: [next]).first)
        #expect(repeated.revision == 1)
    }
    @Test func userOverrideDoesNotConflictWithUnchangedSource() throws {
        let sourceDate = instant("2026-11-12T12:00:00Z")
        let observation = AcademicEvent(id: "one", courseID: "course", title: "Project", date: sourceDate, sourceID: "syllabus")
        var edited = observation; edited.date = instant("2026-11-14T12:00:00Z"); edited.userEdited = true; edited.state = .approved
        let result = try #require(Reconciler.merge(existing: [edited], incoming: [observation]).first)
        #expect(result.state == .approved)
        #expect(result.date == edited.date)
    }
    @Test func sourcePrecisionChangesAreReviewableAndIdempotent() throws {
        let date = instant("2026-11-12T12:00:00Z")
        let old = AcademicEvent(id: "one", courseID: "course", title: "Project", date: date, dateOnly: true, timeZone: "UTC", state: .approved)
        var next = old; next.dateOnly = false
        let result = try #require(Reconciler.merge(existing: [old], incoming: [next]).first)
        #expect(result.dateOnly)
        #expect(result.proposedDateOnly == false)
        #expect(result.state == .conflict)
        #expect(Reconciler.merge(existing: [result], incoming: [next]).first?.revision == 1)
    }
    @Test func partialFailurePreservesHistoryAndDecisions() {
        let rejected = AcademicEvent(id: "rejected", courseID: "course", title: "Quiz", state: .rejected)
        #expect(Reconciler.merge(existing: [rejected], incoming: []) == [rejected])
        #expect(Reconciler.merge(existing: [rejected], incoming: [rejected]).first?.state == .rejected)
    }
    @Test func crossSourceDuplicateRequiresDecision() {
        let date = instant("2026-11-12T12:00:00Z")
        let first = AcademicEvent(id: "canvas", courseID: "course", title: "Project 2", date: date, state: .approved, sourceID: "canvas-source")
        let second = AcademicEvent(id: "document", courseID: "course", title: "Project 2", date: date, state: .approved, sourceID: "document-source")
        let merged = Reconciler.merge(existing: [first], incoming: [second])
        #expect(merged.filter { $0.state == .approved }.count == 1)
        #expect(merged.last?.state == .conflict)
    }
}

@Suite("Archive durability") struct PersistenceTests {
    @Test func saveLoadAndBackup() throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ArchiveStore(url: directory.appendingPathComponent("library.json"))
        #expect(try store.load().events.isEmpty)
        var archive = AppArchive()
        archive.events = [AcademicEvent(id: "one", courseID: "course", title: "Assignment")]
        try store.save(archive)
        archive.events[0].title = "Updated assignment"
        try store.save(archive)
        #expect(try store.load().events.first?.title == "Updated assignment")
        #expect(try store.loadBackup().events.first?.title == "Assignment")
    }
    @Test func corruptionNeverOverwritesBackup() throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ArchiveStore(url: directory.appendingPathComponent("library.json"))
        try store.save(AppArchive()); try store.save(AppArchive())
        let originalBackup = try Data(contentsOf: store.backupURL)
        try Data("broken".utf8).write(to: store.url)
        #expect(throws: ArchiveError.self) { try store.load() }
        #expect(throws: ArchiveError.self) { try store.save(AppArchive()) }
        #expect(try Data(contentsOf: store.backupURL) == originalBackup)
    }
    @Test func unknownSchemaIsRejected() throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ArchiveStore(url: directory.appendingPathComponent("library.json"))
        var value = AppArchive(); value.schemaVersion = 99
        try JSONEncoder().encode(value).write(to: store.url)
        #expect(throws: ArchiveError.self) { try store.load() }
    }
}

@Suite("Calendar export") struct CalendarExportTests {
    @Test func allDayUsesExclusiveNextDateAndStableUID() {
        let event = AcademicEvent(id: "stable", courseID: "course", title: "Midterm", date: instant("2026-11-12T17:00:00Z"), timeZone: "America/New_York", state: .approved)
        let output = ICSExporter.export(events: [event], courses: [], exportedAt: instant("2026-11-04T12:00:00Z"))
        #expect(output.contains("UID:stable@syllapace.local\r\n"))
        #expect(output.contains("DTSTART;VALUE=DATE:20261112\r\nDTEND;VALUE=DATE:20261113"))
        #expect(output.contains("DTSTAMP:20261104T120000Z"))
    }
    @Test func unconfirmedEventsAreExcludedAndInjectionIsEscaped() {
        let approved = AcademicEvent(id: "safe", courseID: "course", title: "Report, part 1; revision\nATTENDEE:fake", date: .now, state: .approved, sourceURL: "https://canvas.example.edu/courses/1?access_token=secret")
        let pending = AcademicEvent(id: "pending", courseID: "course", title: "Pending", date: .now)
        let output = ICSExporter.export(events: [approved, pending], courses: [])
        #expect(!output.contains("pending@"))
        #expect(!output.contains("\r\nATTENDEE:"))
        #expect(output.contains("Report\\, part 1\\; revision\\nATTENDEE:fake"))
        #expect(!output.contains("secret"))
    }
    @Test func unicodeFoldingUsesOctets() {
        let event = AcademicEvent(id: "one", courseID: "course", title: String(repeating: "中文学业日程", count: 20), date: .now, state: .approved)
        let output = ICSExporter.export(events: [event], courses: [])
        #expect(output.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        #expect(output.replacingOccurrences(of: "\r\n ", with: "").contains(event.title))
    }
}

@Suite("Document ingestion") struct DocumentTests {
    @Test func pdfRetainsPageReferences() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("syllabus.pdf")
        let first = "BT /F1 12 Tf 72 720 Td (Midterm exam November 12) Tj ET"
        let second = "BT /F1 12 Tf 72 720 Td (Project due November 14) Tj ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [4 0 R 6 0 R] /Count 2 >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents 5 0 R >>",
            "<< /Length \(first.utf8.count) >>\nstream\n\(first)\nendstream",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents 7 0 R >>",
            "<< /Length \(second.utf8.count) >>\nstream\n\(second)\nendstream"
        ]
        var pdf = "%PDF-1.4\n", offsets = [Int]()
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 8\n0000000000 65535 f \n"
        for offset in offsets { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        try Data(pdf.utf8).write(to: file)
        let document = try await DocumentReader.read(url: file, courseID: "course")
        #expect(document.text.contains("[Page 1]"))
        #expect(document.text.contains("[Page 2]"))
        let events = RuleExtractor.extract(source: document, year: 2026, timeZone: "UTC")
        #expect(events.count == 2)
        #expect(events.last?.evidence.hasPrefix("[Page 2]") == true)
    }
    @Test func localIdentitySurvivesContentRevision() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("syllabus.txt")
        try "Project due November 12".write(to: file, atomically: true, encoding: .utf8)
        let first = try await DocumentReader.read(url: file, courseID: "course")
        try "Project due November 14".write(to: file, atomically: true, encoding: .utf8)
        let second = try await DocumentReader.read(url: file, courseID: "course")
        #expect(first.id == second.id)
        #expect(first.hash != second.hash)
    }
    @Test func oversizedTextFailsWithoutReadingUnlimitedContent() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("oversized.txt")
        try Data(repeating: 65, count: DocumentReader.maxTextBytes + 1).write(to: file)
        await #expect(throws: DocumentError.self) { try await DocumentReader.read(url: file, courseID: "course") }
    }
    @Test func malformedPDFIsRejected() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("broken.pdf")
        try Data("this is not a PDF".utf8).write(to: file)
        await #expect(throws: DocumentError.self) { try await DocumentReader.read(url: file, courseID: "course") }
    }
    @Test func htmlDoesNotIncludeScriptsAndKeepsRows() {
        let text = DocumentReader.plainText(html: "<script>bad()</script><table><tr><td>Nov 12</td><td>Midterm &amp; review</td></tr><tr><td>Nov 14</td><td>Project</td></tr></table>")
        #expect(!text.contains("bad"))
        #expect(text.contains("Nov 12\tMidterm & review"))
        #expect(text.contains("\nNov 14"))
    }
    @Test func docxTablesKeepCellAssociation() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let word = directory.appendingPathComponent("word", isDirectory: true)
        try FileManager.default.createDirectory(at: word, withIntermediateDirectories: true)
        let xml = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:tbl><w:tr><w:tc><w:p><w:r><w:t>November 12</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Midterm exam</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>"
        try xml.write(to: word.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", "syllabus.docx", "word/document.xml"]
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let document = try await DocumentReader.read(url: directory.appendingPathComponent("syllabus.docx"), courseID: "course")
        #expect(document.text.contains("November 12 \tMidterm exam"))
        #expect(RuleExtractor.extract(source: document, year: 2026, timeZone: "UTC").count == 1)
    }
}
