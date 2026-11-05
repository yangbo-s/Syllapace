import Foundation
import PDFKit
import CryptoKit

public enum DocumentError: LocalizedError, Sendable {
    case unsupported, tooLarge, unreadable, noText, invalidDocument
    public var errorDescription: String? {
        switch self {
        case .unsupported: L10n.string("Choose a PDF, DOCX, XLSX, CSV, TXT, Markdown, or HTML document.")
        case .tooLarge: L10n.string("This document exceeds the import limit (20 MB, 150 PDF pages, or 2 MB of text).")
        case .unreadable: L10n.string("The document could not be read. Check its permissions and try again.")
        case .noText: L10n.string("No selectable text was found. Scanned documents need OCR before importing.")
        case .invalidDocument: L10n.string("The document is damaged, encrypted, or not a supported document.")
        }
    }
}

public enum DocumentReader {
    public static let maxBytes = 20 * 1024 * 1024
    public static let maxTextBytes = 2 * 1024 * 1024

    @concurrent public static func read(url: URL, courseID: String) async throws -> SourceDocument {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true else { throw DocumentError.unreadable }
        guard let byteCount = size.fileSize, byteCount <= maxBytes else { throw DocumentError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maxBytes else { throw DocumentError.tooLarge }
        let text: String
        var links: [SourceLink]?
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard data.starts(with: Data("%PDF".utf8)), let document = PDFDocument(data: data), !document.isLocked else { throw DocumentError.invalidDocument }
            guard document.pageCount <= 150 else { throw DocumentError.tooLarge }
            var pages: [String] = []
            var total = 0
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                let content = document.page(at: index)?.string ?? ""
                total += content.utf8.count
                guard total <= maxTextBytes else { throw DocumentError.tooLarge }
                if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pages.append("[Page \(index + 1)]\n\(content)")
                }
            }
            text = pages.joined(separator: "\n\n")
        case "xlsx":
            text = try SpreadsheetReader.read(url: url)
        case "docx":
            guard data.starts(with: [0x50, 0x4b]) else { throw DocumentError.invalidDocument }
            let xml = try extractDOCX(url: url)
            guard xml.range(of: Data("<!DOCTYPE".utf8)) == nil else { throw DocumentError.invalidDocument }
            let delegate = WordTextParser()
            let parser = XMLParser(data: xml)
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse(), !delegate.exceeded else { throw DocumentError.invalidDocument }
            text = delegate.text
        case "txt", "csv", "md", "markdown", "html", "htm":
            guard data.count <= maxTextBytes else { throw DocumentError.tooLarge }
            guard let raw = String(data: data, encoding: .utf8) else { throw DocumentError.unreadable }
            if ["html", "htm"].contains(url.pathExtension.lowercased()) {
                let parsed = CanvasHTML.parse(raw, baseURL: url)
                guard !parsed.truncated else { throw DocumentError.tooLarge }
                text = parsed.text; links = parsed.links
            } else { text = raw }
        default: throw DocumentError.unsupported
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DocumentError.noText }
        guard text.utf8.count <= maxTextBytes else { throw DocumentError.tooLarge }
        return SourceDocument(
            id: "local-" + fingerprint(courseID + "|" + url.standardizedFileURL.path),
            courseID: courseID,
            title: url.deletingPathExtension().lastPathComponent,
            text: text,
            hash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), kind: .file, links: links
        )
    }

    public static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func plainText(html: String) -> String {
        var text = html.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</(?:p|div|h[1-6]|li|tr)>|<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</t[dh]>", with: "\t", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractDOCX(url: URL) throws -> Data {
        // No shell is involved, and only the document XML is read. Bound the decompressed
        // stream as well as input size, so a ZIP bomb cannot grow an unlimited buffer.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "word/document.xml"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = DispatchWorkItem { @Sendable in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: deadline)
        defer {
            deadline.cancel()
            try? output.fileHandleForReading.close()
            if process.isRunning { process.terminate() }
        }
        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maxTextBytes * 4 else { throw DocumentError.tooLarge }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { throw DocumentError.invalidDocument }
        return data
    }
}

private final class WordTextParser: NSObject, XMLParserDelegate {
    var text = ""
    var exceeded = false
    private var inText = false
    private var inCell = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if name == "w:t" { inText = true }
        if name == "w:tc" { inCell = true }
        if name == "w:tab" { text += "\t" }
        if name == "w:br" { text += " " }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { text += string }
        if text.utf8.count > DocumentReader.maxTextBytes { exceeded = true; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        if name == "w:t" { inText = false }
        if name == "w:p" { text += inCell ? " " : "\n" }
        if name == "w:tc" { inCell = false; text += "\t" }
        if name == "w:tr" { text += "\n" }
    }
}
