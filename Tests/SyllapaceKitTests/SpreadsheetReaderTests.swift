import Foundation
import Testing
@testable import SyllapaceKit

@Suite("Spreadsheet calendar documents")
struct SpreadsheetReaderTests {
    func fixture(_ cells: String, date1904: Bool = false, shared: String? = nil, customFormat: String = "yyyy-mm-dd") -> [String: Data] {
        var parts = [
            "xl/workbook.xml": "<workbook xmlns:r=\"urn:relationships\"><workbookPr date1904=\"\(date1904 ? "1" : "0")\"/><sheets><sheet name=\"Fall 2026\" r:id=\"rId1\"/></sheets></workbook>",
            "xl/_rels/workbook.xml.rels": "<Relationships><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>",
            "xl/styles.xml": "<styleSheet><numFmts><numFmt numFmtId=\"164\" formatCode=\"\(customFormat)\"/></numFmts><cellXfs><xf numFmtId=\"0\"/><xf numFmtId=\"14\"/><xf numFmtId=\"22\"/><xf numFmtId=\"164\"/><xf numFmtId=\"20\"/></cellXfs></styleSheet>",
            "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row r=\"1\">\(cells)</row></sheetData></worksheet>"
        ]
        if let shared { parts["xl/sharedStrings.xml"] = shared }
        return parts.mapValues { Data($0.utf8) }
    }
    @Test func sharedRichInlineAndSparseCellsKeepTheirAddresses() throws {
        let parts = fixture("""
        <c r="A1" t="s"><v>0</v></c><c r="C1" t="inlineStr"><is><r><t>Registration </t></r><r><t>opens</t></r></is></c>
        """, shared: "<sst><si><r><t>Academic </t></r><r><t>Calendar</t></r><rPh><t>Ignored phonetics</t></rPh></si></sst>")
        let result = try SpreadsheetReader.text(parts: parts)
        #expect(result.contains("[Sheet: Fall 2026]"))
        #expect(result.contains("[Row 1]\tA1: Academic Calendar\tC1: Registration opens"))
        #expect(!result.contains("Ignored phonetics"))
    }
    @Test func bothExcelDateSystemsPreserveTheSameCalendarDate() throws {
        let modern = try SpreadsheetReader.text(parts: fixture("<c r=\"A1\" s=\"1\"><v>46330</v></c>"))
        let oldMac = try SpreadsheetReader.text(parts: fixture("<c r=\"A1\" s=\"1\"><v>44868</v></c>", date1904: true))
        #expect(modern == oldMac)
        #expect(modern.contains("2026-11-04"))
    }
    @Test func dateTimeTimeAndCustomDatesDoNotBecomeSerialNumbers() throws {
        let result = try SpreadsheetReader.text(parts: fixture("""
        <c r="A1" s="2"><v>46330.625</v></c>
        <c r="B1" s="4"><v>0.625</v></c>
        <c r="C1" s="3"><v>46330</v></c>
        <c r="D1"><v>46330</v></c>
        """))
        #expect(result.contains("A1: 2026-11-04 15:00:00"))
        #expect(result.contains("B1: 15:00:00"))
        #expect(result.contains("C1: 2026-11-04"))
        #expect(result.contains("D1: 46330"))
    }
    @Test func formulasUseCachedValuesAndNeverExecute() throws {
        let result = try SpreadsheetReader.text(parts: fixture("""
        <c r="A1" s="1"><f>DATE(2026,11,4)</f><v>46330</v></c>
        <c r="B1"><f>HYPERLINK("https://example.com")</f></c>
        """))
        #expect(result.contains("A1: 2026-11-04"))
        #expect(result.contains("[Formula result unavailable: HYPERLINK"))
    }
    @Test func roundedMidnightCarriesIntoTheNextDate() throws {
        let result = try SpreadsheetReader.text(parts: fixture("<c r=\"A1\" s=\"2\"><v>46330.999999999</v></c>"))
        #expect(result.contains("2026-11-05 00:00:00"))
        #expect(!result.contains("24:00:00"))
    }
    @Test func elapsedDurationsStayNumericAndFictitiousLeapDateIsExplicit() throws {
        let elapsed = try SpreadsheetReader.text(parts: fixture("<c r=\"A1\" s=\"3\"><v>2.5</v></c>", customFormat: "[h]:mm"))
        #expect(elapsed.contains("A1: 2.5"))
        let leap = try SpreadsheetReader.text(parts: fixture("<c r=\"A1\" s=\"1\"><v>60</v></c>"))
        #expect(leap.contains("Invalid Excel date: 60"))
    }
    @Test func malformedSharedStringsExternalRelationshipsAndDTDareRejected() throws {
        #expect(throws: DocumentError.invalidDocument) { try SpreadsheetReader.text(parts: fixture("<c r=\"A1\" t=\"s\"><v>999</v></c>")) }
        var external = fixture("<c r=\"A1\"><v>1</v></c>")
        external["xl/_rels/workbook.xml.rels"] = Data("<Relationships><Relationship Id=\"rId1\" Type=\"urn:worksheet/worksheet\" TargetMode=\"External\" Target=\"https://example.com/sheet.xml\"/></Relationships>".utf8)
        #expect(throws: DocumentError.invalidDocument) { try SpreadsheetReader.text(parts: external) }
        var dtd = fixture("<c r=\"A1\"><v>1</v></c>")
        dtd["xl/workbook.xml"] = Data("<!DOCTYPE workbook [<!ENTITY value 'expanded'>]><workbook/>".utf8)
        #expect(throws: DocumentError.invalidDocument) { try SpreadsheetReader.text(parts: dtd) }
    }
    @Test func partAndCellLimitsRejectOversizedDocuments() throws {
        var oversized = fixture("<c r=\"A1\"><v>1</v></c>")
        oversized["xl/worksheets/sheet1.xml"] = Data(repeating: 32, count: 4 * 1024 * 1024 + 1)
        #expect(throws: DocumentError.tooLarge) { try SpreadsheetReader.text(parts: oversized) }
        let cells = String(repeating: "<c r=\"A1\"><v>1</v></c>", count: 50_001)
        #expect(throws: DocumentError.tooLarge) { try SpreadsheetReader.text(parts: fixture(cells)) }
    }
    @Test func repeatedSharedStringsAreBoundedBeforeTheRowEnds() throws {
        let text = String(repeating: "x", count: 1024 * 1024)
        let cells = String(repeating: "<c r=\"A1\" t=\"s\"><v>0</v></c>", count: 8)
        #expect(throws: DocumentError.tooLarge) {
            try SpreadsheetReader.text(parts: fixture(cells, shared: "<sst><si><t>\(text)</t></si></sst>"))
        }
    }
    @Test func actualZIPIsReadWithoutExtractingFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("syllapace-xlsx-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (path, data) in fixture("<c r=\"A1\" s=\"1\"><v>46330</v></c>") {
            let target = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        }
        let archive = directory.appendingPathComponent("calendar.xlsx")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory; process.arguments = ["-qr", archive.path, "xl"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(try SpreadsheetReader.read(url: archive).contains("2026-11-04"))
    }
}
