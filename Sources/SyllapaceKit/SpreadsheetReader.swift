import Foundation

/// Reads text and cached values from an XLSX document. It never evaluates
/// formulas, follows external relationships, or writes ZIP contents to disk.
public enum SpreadsheetReader {
    private static let maxXMLBytes = 8 * 1024 * 1024
    private static let maxPartBytes = 4 * 1024 * 1024
    private static let maxSheets = 32
    private static let maxCells = 50_000

    public static func read(url: URL) throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard url.isFileURL, size.isRegularFile == true else { throw DocumentError.unreadable }
        guard let count = size.fileSize, count <= DocumentReader.maxBytes else { throw DocumentError.tooLarge }
        let deadline = Date.now.addingTimeInterval(30)
        let listing = try unzip(url, arguments: ["-Z", "-1"], limit: 128 * 1024, deadline: deadline)
        guard let names = String(data: listing, encoding: .utf8) else { throw DocumentError.invalidDocument }
        let entries = names.split(separator: "\n").map(String.init)
        guard entries.count <= 1024, Set(entries).count == entries.count else { throw DocumentError.tooLarge }
        let metadata = ["xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/sharedStrings.xml"]
        let worksheets = entries.filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }
        guard worksheets.count <= maxSheets else { throw DocumentError.tooLarge }
        var parts: [String: Data] = [:], total = 0
        for name in metadata + worksheets where entries.contains(name) {
            guard safePart(name) else { throw DocumentError.invalidDocument }
            let data = try unzip(url, arguments: ["-p"], member: name, limit: min(maxPartBytes, maxXMLBytes - total), deadline: deadline)
            total += data.count; parts[name] = data
        }
        return try text(parts: parts)
    }

    /// Kept internal so parsing fixtures can exercise the same path as a ZIP.
    static func text(parts: [String: Data]) throws -> String {
        guard parts.values.reduce(0, { $0 + $1.count }) <= maxXMLBytes,
              parts.values.allSatisfy({ $0.count <= maxPartBytes }) else { throw DocumentError.tooLarge }
        guard let workbookData = parts["xl/workbook.xml"], let relationshipsData = parts["xl/_rels/workbook.xml.rels"] else { throw DocumentError.invalidDocument }
        let workbook = WorkbookXML(); try parse(workbookData, with: workbook)
        guard !workbook.sheets.isEmpty else { throw DocumentError.noText }
        guard workbook.sheets.count <= maxSheets else { throw DocumentError.tooLarge }
        let relationships = RelationshipsXML(); try parse(relationshipsData, with: relationships)
        let strings = SharedStringsXML()
        if let data = parts["xl/sharedStrings.xml"] { try parse(data, with: strings) }
        let styles = StylesXML()
        if let data = parts["xl/styles.xml"] { try parse(data, with: styles) }
        var sections: [String] = [], totalCells = 0, totalText = 0
        for sheet in workbook.sheets {
            try Task.checkCancellation()
            guard let target = relationships.targets[sheet.relationshipID] else { throw DocumentError.invalidDocument }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard safePart(path), path.hasPrefix("xl/worksheets/"), let data = parts[path] else { throw DocumentError.invalidDocument }
            let reader = WorksheetXML(strings: strings.values, styles: styles.formats, customFormats: styles.customFormats,
                                      date1904: workbook.date1904, remainingCells: maxCells - totalCells)
            try parse(data, with: reader)
            totalCells += reader.cellCount
            if reader.rows.isEmpty { continue }
            let section = "[Sheet: \(sheet.name)\(sheet.hidden ? " (hidden)" : "")]\n" + reader.rows.joined(separator: "\n")
            totalText += section.utf8.count
            guard totalText <= DocumentReader.maxTextBytes else { throw DocumentError.tooLarge }
            sections.append(section)
        }
        guard !sections.isEmpty else { throw DocumentError.noText }
        let result = sections.joined(separator: "\n\n")
        guard result.utf8.count <= DocumentReader.maxTextBytes else { throw DocumentError.tooLarge }
        return result
    }
    private static func safePart(_ path: String) -> Bool {
        path.range(of: "^[A-Za-z0-9_./-]+$", options: .regularExpression) != nil &&
        !path.split(separator: "/").contains("..") && !path.hasPrefix("/")
    }
    private static func parse(_ data: Data, with delegate: LimitedXML) throws {
        let decoded: String?
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) { decoded = String(data: data, encoding: .utf16) }
        else { decoded = String(data: data, encoding: .utf8) }
        guard let decoded, !decoded.contains("\0"), decoded.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              decoded.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { throw DocumentError.invalidDocument }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let success = parser.parse()
        if delegate.exceeded { throw DocumentError.tooLarge }
        guard success, !delegate.invalid else { throw DocumentError.invalidDocument }
    }
    private static func unzip(_ url: URL, arguments: [String], member: String? = nil, limit: Int, deadline: Date) throws -> Data {
        try Task.checkCancellation()
        guard limit > 0, deadline > .now else { throw DocumentError.tooLarge }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments + [url.path] + (member.map { [$0] } ?? [])
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { @Sendable in if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + min(10, deadline.timeIntervalSinceNow), execute: timeout)
        defer { timeout.cancel(); try? pipe.fileHandleForReading.close(); if process.isRunning { process.terminate() } }
        var output = Data()
        while let bytes = try pipe.fileHandleForReading.read(upToCount: 64 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            guard output.count + bytes.count <= limit, deadline > .now else { throw DocumentError.tooLarge }
            output.append(bytes)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DocumentError.invalidDocument }
        return output
    }
}

private class LimitedXML: NSObject, XMLParserDelegate {
    var exceeded = false
    var invalid = false
    var stack: [String] = []
    var textBytes = 0
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        stack.append(name.split(separator: ":").last.map(String.init) ?? name)
        if stack.count > 64 { invalid = true; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) { if !stack.isEmpty { stack.removeLast() } }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBytes += string.utf8.count
        if textBytes > DocumentReader.maxTextBytes { exceeded = true; parser.abortParsing() }
    }
}
private final class WorkbookXML: LimitedXML {
    struct Sheet { var name: String; var relationshipID: String; var hidden: Bool }
    var sheets: [Sheet] = []
    var date1904 = false
    override func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        super.parser(parser, didStartElement: name, namespaceURI: namespaceURI, qualifiedName: qName, attributes: attributes)
        if stack.last == "workbookPr" { date1904 = ["1", "true"].contains(attributes["date1904"] ?? "") }
        if stack.last == "sheet" {
            guard let id = attributes["r:id"], let title = attributes["name"] else { invalid = true; parser.abortParsing(); return }
            sheets.append(Sheet(name: title, relationshipID: id, hidden: attributes["state"] == "hidden" || attributes["state"] == "veryHidden"))
            if sheets.count > 32 { exceeded = true; parser.abortParsing() }
        }
    }
}
private final class RelationshipsXML: LimitedXML {
    var targets: [String: String] = [:]
    override func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        super.parser(parser, didStartElement: name, namespaceURI: namespaceURI, qualifiedName: qName, attributes: attributes)
        guard stack.last == "Relationship", let id = attributes["Id"], let target = attributes["Target"],
              attributes["Type"]?.hasSuffix("/worksheet") == true else { return }
        guard attributes["TargetMode"]?.lowercased() != "external", targets[id] == nil else { invalid = true; parser.abortParsing(); return }
        targets[id] = target
    }
}
private final class SharedStringsXML: LimitedXML {
    var values: [String] = []
    private var current = ""
    override func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        super.parser(parser, didStartElement: name, namespaceURI: namespaceURI, qualifiedName: qName, attributes: attributes)
        if stack.last == "si" { current = "" }
    }
    override func parser(_ parser: XMLParser, foundCharacters string: String) {
        super.parser(parser, foundCharacters: string)
        if stack.last == "t", stack.contains("si"), !stack.contains("rPh") { current += string }
    }
    override func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        if stack.last == "si" {
            values.append(current)
            if values.count > 50_000 { exceeded = true; parser.abortParsing() }
        }
        super.parser(parser, didEndElement: name, namespaceURI: namespaceURI, qualifiedName: qName)
    }
}
private final class StylesXML: LimitedXML {
    var customFormats: [Int: String] = [:]
    var formats: [Int] = []
    override func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        super.parser(parser, didStartElement: name, namespaceURI: namespaceURI, qualifiedName: qName, attributes: attributes)
        if stack.last == "numFmt", let id = Int(attributes["numFmtId"] ?? ""), let format = attributes["formatCode"] { customFormats[id] = format }
        if stack.last == "xf", stack.dropLast().last == "cellXfs" { formats.append(Int(attributes["numFmtId"] ?? "") ?? 0) }
        if customFormats.count > 4096 || formats.count > 4096 { exceeded = true; parser.abortParsing() }
    }
}
private final class WorksheetXML: LimitedXML {
    let strings: [String], styles: [Int], customFormats: [Int: String], date1904: Bool, remainingCells: Int
    var rows: [String] = []
    var cellCount = 0
    private var cellType = "", cellAddress = "", cellStyle = 0, value = "", inline = "", formula = ""
    private var row: [String] = []
    private var rowNumber = ""
    private var rowCount = 0
    private var rowBytes = 0
    private var outputBytes = 0
    init(strings: [String], styles: [Int], customFormats: [Int: String], date1904: Bool, remainingCells: Int) {
        self.strings = strings; self.styles = styles; self.customFormats = customFormats
        self.date1904 = date1904; self.remainingCells = remainingCells
    }
    override func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        super.parser(parser, didStartElement: name, namespaceURI: namespaceURI, qualifiedName: qName, attributes: attributes)
        if stack.last == "row" { row = []; rowBytes = 0; rowCount += 1; rowNumber = attributes["r"] ?? String(rowCount) }
        if stack.last == "c" {
            cellCount += 1
            if cellCount > remainingCells { exceeded = true; parser.abortParsing(); return }
            cellType = attributes["t"] ?? "n"; cellAddress = attributes["r"] ?? "?"
            cellStyle = Int(attributes["s"] ?? "0") ?? 0
            value = ""; inline = ""; formula = ""
        }
    }
    override func parser(_ parser: XMLParser, foundCharacters string: String) {
        super.parser(parser, foundCharacters: string)
        guard stack.contains("c") else { return }
        if stack.last == "v" { value += string }
        if stack.last == "f" { formula += string }
        if stack.last == "t", stack.contains("is"), !stack.contains("rPh") { inline += string }
    }
    override func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        if stack.last == "c" {
            let result: String
            if cellType == "s" {
                guard let index = Int(value), strings.indices.contains(index) else { invalid = true; parser.abortParsing(); return }
                result = strings[index]
            } else if cellType == "inlineStr" { result = inline }
            else if cellType == "b" { result = value == "1" ? "TRUE" : "FALSE" }
            else if value.isEmpty, !formula.isEmpty { result = "[Formula result unavailable: \(formula)]" }
            else if cellType == "n", styles.indices.contains(cellStyle) {
                result = formatted(value, formatID: styles[cellStyle])
            } else { result = value }
            if !result.isEmpty {
                // Shared strings can expand one small XML reference into megabytes.
                // Enforce the output bound before accumulating the current row.
                rowBytes += cellAddress.utf8.count + result.utf8.count + 3
                guard outputBytes + rowBytes <= DocumentReader.maxTextBytes else {
                    exceeded = true; parser.abortParsing(); return
                }
                row.append(cellAddress + ": " + result.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " / "))
            }
        }
        if stack.last == "row", !row.isEmpty {
            let line = "[Row \(rowNumber)]\t" + row.joined(separator: "\t")
            outputBytes += line.utf8.count
            if outputBytes > DocumentReader.maxTextBytes { exceeded = true; parser.abortParsing() }
            else { rows.append(line) }
        }
        super.parser(parser, didEndElement: name, namespaceURI: namespaceURI, qualifiedName: qName)
    }
    private enum NumberKind { case number, date, time, dateTime }
    private func kind(_ id: Int) -> NumberKind {
        if [14, 15, 16, 17].contains(id) || (27...36).contains(id) || (50...58).contains(id) { return .date }
        if [18, 19, 20, 21, 45, 47].contains(id) { return .time }
        if id == 22 { return .dateTime }
        guard var code = customFormats[id]?.lowercased() else { return .number }
        code = code.replacingOccurrences(of: #""[^"]*"|\\.|_.|\*."#, with: "", options: .regularExpression)
        // Elapsed durations (for example [h]:mm) must not become a wall-clock date.
        if code.range(of: #"\[[hms]+\]"#, options: .regularExpression) != nil { return .number }
        code = code.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        let time = code.contains("h") || code.contains("s")
        let date = code.contains("y") || code.contains("d") || (code.contains("m") && !time)
        return date ? (time ? .dateTime : .date) : (time ? .time : .number)
    }
    private func formatted(_ raw: String, formatID: Int) -> String {
        let kind = kind(formatID)
        guard kind != .number, let serial = Double(raw), serial.isFinite, serial >= 0, serial < 2_958_466 else { return raw }
        let roundedSeconds = Int(((serial - floor(serial)) * 86_400).rounded())
        let days = Int(floor(serial)) + (kind == .dateTime ? roundedSeconds / 86_400 : 0)
        let seconds = roundedSeconds % 86_400
        let time = String(format: "%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
        if kind == .time { return time }
        // Excel's 1900 system contains a fictitious February 29. Keep it explicit.
        if !date1904, days == 60 { return "[Invalid Excel date: \(raw)]" }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = calendar.date(from: DateComponents(year: date1904 ? 1904 : 1899, month: date1904 ? 1 : 12, day: date1904 ? 1 : 31))!
        guard let date = calendar.date(byAdding: .day, value: days - (!date1904 && days > 60 ? 1 : 0), to: base) else { return raw }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        return kind == .dateTime ? day + " " + time : day
    }
}
