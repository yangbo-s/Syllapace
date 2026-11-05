import Foundation
import Darwin
import SyllapaceKit

// A developer-only executable. No user defaults, Keychain, application store,
// notifications or calendar writes are accessed. Every input path is explicit.
umask(0o077)
do {
    let options = try AuditOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    if options.help { print(AuditOptions.usage) }
    else {
        var audit = try AuditRun(options: options)
        try await audit.run()
    }
} catch {
    FileHandle.standardError.write(Data(("audit_failed=" + safeError(error) + "\n").utf8))
    exit(1)
}

private enum AuditError: Error { case arguments, input, credentials, outputExists, courseSelection, configuration }

private struct AuditOptions {
    static let usage = """
    SyllapaceAudit --archive PATH --config PATH --output-dir PATH
      [--credentials PATH] [--canvas] [--official] [--semester 'Fall 2026']
      [--courses 18647-A,18794-A,19688-A,18749] [--curate-limit 0..40]
      [--source-ids ID,ID] [--file-limit 0..50] [--resume] [--retry-failures]
    Inputs must be isolated copies. No model requests occur unless curate-limit > 0.
    Results: private result-archive.json (with sources), summary.json (no source text).
    Resume reuses the private result archive, including successful/failed curation checkpoints.
    """
    var archive = "", config = "", credentials: String?, output = "", semester: String?
    var courses = ["18647-A", "18794-A", "19688-A", "18749"], sourceIDs = Set<String>()
    var canvas = false, official = false, resume = false, retryFailures = false, help = false
    var curateLimit = 0, fileLimit = 12
    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]; index += 1
            switch flag {
            case "--canvas": canvas = true
            case "--official": official = true
            case "--resume": resume = true
            case "--retry-failures": retryFailures = true
            case "--help", "-h": help = true
            default:
                guard index < arguments.count else { throw AuditError.arguments }
                let value = arguments[index]; index += 1
                switch flag {
                case "--archive": archive = value
                case "--config": config = value
                case "--credentials": credentials = value
                case "--output-dir": output = value
                case "--semester": semester = value
                case "--courses": courses = value.split(separator: ",").map(String.init)
                case "--source-ids": sourceIDs = Set(value.split(separator: ",").map(String.init))
                case "--curate-limit": guard let count = Int(value), (0...40).contains(count) else { throw AuditError.arguments }; curateLimit = count
                case "--file-limit": guard let count = Int(value), (0...50).contains(count) else { throw AuditError.arguments }; fileLimit = count
                default: throw AuditError.arguments
                }
            }
        }
        if help { return }
        guard !courses.isEmpty, courses.count <= 20, Set(courses).count == courses.count,
              !archive.isEmpty, !config.isEmpty, !output.isEmpty else { throw AuditError.arguments }
        for path in [archive, config, output] + (credentials.map { [$0] } ?? []) {
            guard path.hasPrefix("/"), !path.contains("/Library/Application Support/"), !path.contains("/Library/Preferences/") else { throw AuditError.input }
        }
        if canvas || curateLimit > 0 { guard credentials != nil else { throw AuditError.credentials } }
    }
}

private struct AuditConfiguration: Decodable {
    let canvasHost: String
    let modelEndpoint: String?
    let modelName: String?
    let modelProvider: ModelProvider?
    let modelWorkspaceID: String?
}

private struct AuditCredentials: Decodable {
    let canvasToken: String?
    let modelKey: String?
    let values: [String: String]?
    func canvas(_ config: AuditConfiguration) -> String? {
        canvasToken ?? values?["canvas-token:" + config.canvasHost.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)] ?? values?["canvas-token"]
    }
    func model(_ config: AuditConfiguration) -> String? {
        modelKey ?? values?["model-key:" + (config.modelEndpoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)] ?? values?["model-key"]
    }
}

private struct AuditStep: Codable { let step: String; let status: String; let count: Int }
private struct AuditCourseSummary: Codable {
    let code: String
    let sources: Int
    let nativeCanvas: Int
    let model: Int
    let local: Int
    let official: Int
    let approvedSessions: Int
    let recurringSeries: Int
    let duplicateSlots: Int
    let duplicateExcess: Int
    let sameTypeDuplicateSlots: Int
    let pending: Int
    let conflicts: Int
    let rawIssues: Int
    let reviewQuestions: Int
    let failedSources: Int
}
private struct AuditSourceSummary: Codable {
    let sourceID: String
    let courseCode: String
    let kind: String
    let characters: Int
    let candidate: String
    let hasPublishedDate: Bool
    let hasEffectiveDueDate: Bool
    let preparedCharacters: Int
    let cachedEvents: Int
    let rawIssues: Int
    let reviewQuestions: Int
    let issueCategories: [String: Int]
    let failure: String?
}
private struct AuditCurationSummary: Codable {
    let sourceID: String
    let courseCode: String
    let status: String
    let events: Int
    let issues: Int
    let addedContextCharacters: Int
}
private struct AuditReport: Codable {
    var schemaVersion = 1
    var startedAt = Date.now
    var finishedAt: Date?
    var before: [AuditCourseSummary] = []
    var after: [AuditCourseSummary] = []
    var steps: [AuditStep] = []
    var curations: [AuditCurationSummary] = []
    var sources: [AuditSourceSummary] = []
}

private struct AuditRun {
    let options: AuditOptions
    let config: AuditConfiguration
    let secrets: AuditCredentials?
    let output: URL
    var archive: AppArchive
    var report = AuditReport()

    init(options: AuditOptions) throws {
        self.options = options
        config = try JSONDecoder().decode(AuditConfiguration.self, from: readPrivateInput(options.config, maxBytes: 128 * 1024))
        secrets = try options.credentials.map { try JSONDecoder().decode(AuditCredentials.self, from: readPrivateInput($0, maxBytes: 512 * 1024, secret: true)) }
        output = URL(fileURLWithPath: options.output).standardizedFileURL.resolvingSymlinksInPath()
        let input = URL(fileURLWithPath: options.archive).standardizedFileURL.resolvingSymlinksInPath()
        let result = output.appendingPathComponent("result-archive.json")
        guard input != result, !output.path.contains("/Library/Application Support/"),
              ![options.config, options.credentials].compactMap({ $0 }).contains(where: { URL(fileURLWithPath: $0).resolvingSymlinksInPath() == result }) else { throw AuditError.input }
        let exists = FileManager.default.fileExists(atPath: output.path)
        if exists && !options.resume { throw AuditError.outputExists }
        if !exists { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        var info = stat()
        guard lstat(output.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else { throw AuditError.input }
        let load = options.resume && FileManager.default.fileExists(atPath: result.path) ? result.path : input.path
        archive = try JSONDecoder().decode(AppArchive.self, from: readPrivateInput(load, maxBytes: 100 * 1024 * 1024))
        guard (1...4).contains(archive.schemaVersion) else { throw AuditError.input }
    }

    mutating func run() async throws {
        try selectCourses()
        report.before = summaries()
        try checkpoint()
        if options.canvas { try await syncCanvas() }
        if options.official { try await fetchOfficial() }
        archive.events = EventCuration.sanitizeLegacyEvents(existing: archive.events, courseIDs: Set(archive.courses.map(\.id))).events
        restoreSchedules()
        try checkpoint()
        if options.curateLimit > 0 { try await curate() }
        report.after = summaries()
        report.sources = sourceSummaries()
        report.finishedAt = .now
        try checkpoint()
        for course in report.after {
            print("course=\(safeCode(course.code)) sources=\(course.sources) canvas=\(course.nativeCanvas) model=\(course.model) local=\(course.local) official=\(course.official) sessions=\(course.approvedSessions) duplicate_slots=\(course.duplicateSlots) review_questions=\(course.reviewQuestions) failures=\(course.failedSources)")
        }
        print("audit_complete courses=\(report.after.count) model_requests=\(report.curations.filter { $0.status != "cached" }.count)")
    }

    mutating func selectCourses() throws {
        let requested = Set(options.courses.map(normalizedCode))
        let candidates = archive.courses.filter { requested.contains(normalizedCode($0.code)) }
        let semester = options.semester ?? Set(candidates.compactMap { $0.term?.name }).only
        guard let semester else { throw AuditError.courseSelection }
        let selected = candidates.filter { $0.term?.name.caseInsensitiveCompare(semester) == .orderedSame }
        guard selected.count == requested.count, Set(selected.map { normalizedCode($0.code) }) == requested else { throw AuditError.courseSelection }
        let ids = Set(selected.map(\.id))
        archive.courses = selected; archive.sources = archive.sources.filter { ids.contains($0.courseID) }
        archive.events = archive.events.filter { ids.contains($0.courseID) }
        let sourceIDs = Set(archive.sources.map(\.id))
        archive.curationRecords = archive.curationRecords?.filter { sourceIDs.contains($0.key) }
        archive.canvasSelection = CanvasSelection(termID: selected.first?.term?.id, courseIDs: ids)
    }

    mutating func syncCanvas() async throws {
        guard let token = secrets?.canvas(config), !token.isEmpty else { throw AuditError.credentials }
        let client = try CanvasClient(host: config.canvasHost, token: token)
        let result = try await client.sync(courses: archive.courses)
        for course in result.courses {
            if let index = archive.courses.firstIndex(where: { $0.id == course.id }) { archive.courses[index] = course }
        }
        archive.events = Reconciler.merge(existing: archive.events, incoming: result.events)
        for source in result.sources { upsert(source) }
        report.steps.append(AuditStep(step: "canvas", status: "success", count: result.sources.count))
        report.steps.append(AuditStep(step: "canvas_warnings", status: result.warnings.isEmpty ? "none" : "present", count: result.warnings.count))
        try checkpoint()
        let files = result.files.filter { CanvasClient.isLikelySyllabus($0.title) }.sorted { $0.id < $1.id }
        var downloads = 0
        for file in files {
            let old = archive.sources.first { $0.id == file.id }
            if let old, !old.text.isEmpty, file.revision == nil || old.remoteRevision == file.revision { continue }
            guard downloads < options.fileLimit else { break }
            downloads += 1
            do {
                let url = try await client.download(file: file)
                defer { try? FileManager.default.removeItem(at: url) }
                var source = try await DocumentReader.read(url: url, courseID: file.courseID)
                source.id = file.id; source.title = file.title; source.url = file.sourceURL
                source.remoteRevision = file.revision; source.kind = .syllabus
                upsert(source)
                report.steps.append(AuditStep(step: "syllabus_file", status: "success", count: 1))
            } catch is CancellationError { throw CancellationError() }
            catch { report.steps.append(AuditStep(step: "syllabus_file", status: safeError(error), count: 1)) }
            try checkpoint()
        }
        archive.lastSync = .now
        try checkpoint()
        print("canvas_complete sources=\(result.sources.count) syllabus_downloads=\(downloads) warnings=\(result.warnings.count)")
    }

    mutating func fetchOfficial() async throws {
        guard OfficialCourseScheduleClient.supports(canvasHost: config.canvasHost),
              let semester = options.semester ?? Set(archive.courses.compactMap { $0.term?.name }).only else { throw AuditError.configuration }
        let snapshot = try await OfficialCourseScheduleClient().fetch(semester: semester)
        for index in archive.courses.indices {
            do {
                let course = archive.courses[index]
                let events = try snapshot.events(for: course)
                guard !events.isEmpty else { throw OfficialCourseScheduleError.courseNotFound }
                var source = try snapshot.sourceDocument(course: course); source.meetingSchedule = events
                upsert(source)
                archive.events = EventCuration.reorganize(existing: archive.events, incoming: events, sourceIDs: [source.id]).events
                report.steps.append(AuditStep(step: "official:" + safeCode(course.code), status: "success", count: events.count))
                print("official_course=\(safeCode(course.code)) occurrences=\(events.count)")
            } catch { report.steps.append(AuditStep(step: "official:" + safeCode(archive.courses[index].code), status: safeError(error), count: 0)) }
        }
        try checkpoint()
    }

    mutating func restoreSchedules() {
        archive.events = LocalCurationRecovery.restore(existing: archive.events, sources: archive.sources, courses: archive.courses)
        for source in archive.sources {
            guard let course = archive.courses.first(where: { $0.id == source.courseID }) else { continue }
            if let events = source.meetingSchedule {
                archive.events = Reconciler.merge(existing: archive.events, incoming: events)
                continue
            }
            if archive.sources.contains(where: { $0.courseID == source.courseID && $0.meetingSchedule?.isEmpty == false }) { continue }
            let window = curationWindow(course: course)
            let events = WeeklySchedule.extract(source: source, year: source.curationYear ?? course.term?.academicYear ?? 0,
                timeZone: source.curationTimeZone ?? course.timeZone ?? "America/New_York", termStart: window.start, termEnd: window.end)
            if !events.isEmpty { archive.events = Reconciler.merge(existing: archive.events, incoming: events) }
        }
    }

    mutating func curate() async throws {
        guard let key = secrets?.model(config), !key.isEmpty, let endpoint = config.modelEndpoint, let name = config.modelName else { throw AuditError.credentials }
        let client = try LLMClient(endpoint: endpoint, key: key, model: name, provider: config.modelProvider ?? .custom, workspaceID: config.modelWorkspaceID)
        let identity = [config.modelProvider?.rawValue ?? ModelProvider.custom.rawValue, endpoint, name, config.modelWorkspaceID ?? ""].joined(separator: "|")
        var requests = 0
        for source in candidates() {
            guard requests < options.curateLimit else { break }
            guard let course = archive.courses.first(where: { $0.id == source.courseID }), let year = source.curationYear ?? course.term?.academicYear else { continue }
            let prepared = CurationContext.prepare(source: source, course: course, relatedSources: archive.sources)
            let zone = source.curationTimeZone ?? course.timeZone ?? "America/New_York"
            let window = curationWindow(course: course), start = window.start, end = window.end
            let fingerprint = EventCuration.fingerprint(source: prepared, modelIdentity: identity, year: year, timeZone: zone, termStart: start, termEnd: end, intent: source.curationIntent ?? "")
            if let record = archive.curationRecords?[source.id], record.fingerprint == fingerprint,
               record.failure == nil || !options.retryFailures {
                report.curations.append(AuditCurationSummary(sourceID: source.id, courseCode: course.code, status: "cached", events: record.eventCount,
                    issues: record.issues?.count ?? 0, addedContextCharacters: prepared.text.count - source.text.count))
                continue
            }
            requests += 1
            do {
                let result = try await client.curate(source: prepared, year: year, timeZone: zone, intent: source.curationIntent ?? "", termStart: start, termEnd: end)
                archive.events = result.issues.isEmpty
                    ? EventCuration.reorganize(existing: archive.events, incoming: result.events, sourceIDs: [source.id]).events
                    : Reconciler.merge(existing: archive.events, incoming: result.events)
                archive.curationRecords = archive.curationRecords ?? [:]
                archive.curationRecords?[source.id] = SourceCurationRecord(fingerprint: fingerprint, eventCount: result.events.count, issues: result.issues)
                report.curations.append(AuditCurationSummary(sourceID: source.id, courseCode: course.code, status: "success", events: result.events.count,
                    issues: result.issues.count, addedContextCharacters: prepared.text.count - source.text.count))
            } catch is CancellationError { throw CancellationError() }
            catch {
                archive.curationRecords = archive.curationRecords ?? [:]
                archive.curationRecords?[source.id] = SourceCurationRecord(fingerprint: fingerprint, failure: safeError(error))
                report.curations.append(AuditCurationSummary(sourceID: source.id, courseCode: course.code, status: safeError(error), events: 0, issues: 0,
                    addedContextCharacters: prepared.text.count - source.text.count))
            }
            restoreSchedules()
            try checkpoint()
            print("curation_step=\(requests) course=\(safeCode(course.code)) status=\(report.curations.last!.status) events=\(report.curations.last!.events) issues=\(report.curations.last!.issues)")
        }
    }

    func candidates() -> [SourceDocument] {
        let possible = archive.sources.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.localOnly != true && !$0.id.hasPrefix("official:") }
        if !options.sourceIDs.isEmpty { return possible.filter { options.sourceIDs.contains($0.id) }.sorted { $0.id < $1.id } }
        var preferred: [SourceDocument] = []
        // Keep the same bounded sample on resume. Cached samples must not make
        // a repeated audit silently move on to all the remaining materials.
        for kind in ["syllabus", "relative-announcement"] {
            for course in archive.courses.sorted(by: { $0.code < $1.code }) {
                let matching = possible.filter { $0.courseID == course.id && candidateKind($0) == kind }.sorted {
                    if kind == "syllabus", $0.text.count != $1.text.count { return $0.text.count > $1.text.count }
                    let left = $0.publishedAt ?? .distantPast, right = $1.publishedAt ?? .distantPast
                    return left == right ? $0.id < $1.id : left > right
                }
                if let first = matching.first { preferred.append(first) }
            }
        }
        let selected = Set(preferred.map(\.id))
        let relativeCount = preferred.filter { candidateKind($0) == "relative-announcement" }.count
        let additional = possible.filter { !selected.contains($0.id) && candidateKind($0) == "relative-announcement" }.sorted {
            let left = $0.publishedAt ?? .distantPast, right = $1.publishedAt ?? .distantPast
            return left == right ? $0.id < $1.id : left > right
        }.prefix(max(0, 4 - relativeCount))
        return preferred + additional
    }

    func curationWindow(course: Course) -> (start: Date?, end: Date?) {
        if let verified = archive.sources.first(where: {
            $0.courseID == course.id && $0.meetingSchedule?.isEmpty == false && $0.teachingStartsAt != nil && $0.teachingEndsAt != nil
        }) { return (verified.teachingStartsAt, verified.teachingEndsAt) }
        return (course.startsAt ?? course.term?.startAt, course.endsAt ?? course.term?.endAt)
    }

    mutating func upsert(_ incoming: SourceDocument) {
        var source = incoming
        if let index = archive.sources.firstIndex(where: { $0.id == source.id }) {
            let old = archive.sources[index]
            source.localOnly = source.localOnly ?? old.localOnly
            source.curationIntent = old.curationIntent; source.curationYear = old.curationYear; source.curationTimeZone = old.curationTimeZone
            source.meetingSchedule = source.meetingSchedule ?? old.meetingSchedule
            archive.sources[index] = source
        } else { archive.sources.append(source) }
    }

    func summaries() -> [AuditCourseSummary] {
        let projected = CourseScheduleProjection.project(events: archive.events, sources: archive.sources, courses: archive.courses)
        return archive.courses.sorted { $0.code < $1.code }.map { course in
            let sources = archive.sources.filter { $0.courseID == course.id }
            let visible = projected.filter { $0.courseID == course.id && $0.state != .rejected && $0.curationExcluded != true }
            let sessions = visible.filter { $0.kind == .session && $0.state == .approved && $0.date != nil }
            let slots = Dictionary(grouping: sessions) { "\($0.courseID)|\($0.date!.timeIntervalSince1970)|\($0.kind.rawValue)" }
            let duplicates = slots.values.filter { $0.count > 1 }
            let sameTypeSlots = Dictionary(grouping: sessions) { "\($0.courseID)|\($0.date!.timeIntervalSince1970)|\($0.subtype?.rawValue ?? "classMeeting")" }
            let records = sources.compactMap { archive.curationRecords?[$0.id] }
            let hasSchedule = sources.contains { $0.meetingSchedule?.isEmpty == false }
            return AuditCourseSummary(code: course.code, sources: sources.count, nativeCanvas: visible.filter { $0.id.hasPrefix("canvas:") }.count,
                model: visible.filter { $0.id.hasPrefix("model:") || $0.id.hasPrefix("model-") }.count,
                local: visible.filter { $0.id.hasPrefix("document-") || $0.id.hasPrefix("schedule:") || $0.id.hasPrefix("local-meeting:") }.count,
                official: visible.filter { $0.id.hasPrefix("official:") }.count,
                approvedSessions: sessions.count, recurringSeries: Set(sessions.compactMap(\.sourceSeriesID)).count,
                duplicateSlots: duplicates.count, duplicateExcess: duplicates.reduce(0) { $0 + $1.count - 1 }, sameTypeDuplicateSlots: sameTypeSlots.values.filter { $0.count > 1 }.count,
                pending: visible.filter { $0.state == .pending }.count, conflicts: visible.filter { $0.state == .conflict && ($0.userEdited || $0.curationVersion != nil) }.count,
                rawIssues: records.reduce(0) { $0 + ($1.issues?.count ?? 0) },
                reviewQuestions: sources.reduce(0) { $0 + LocalCurationRecovery.unresolvedIssues(CurationReviewPolicy.questions(source: $1, record: archive.curationRecords?[$1.id], events: archive.events, hasWeeklySchedule: hasSchedule), source: $1, course: course, recoveredEvents: archive.events).count },
                failedSources: records.filter { $0.failure != nil }.count)
        }
    }

    func sourceSummaries() -> [AuditSourceSummary] {
        archive.sources.sorted { $0.id < $1.id }.compactMap { source in
            guard let course = archive.courses.first(where: { $0.id == source.courseID }) else { return nil }
            let record = archive.curationRecords?[source.id]
            let initialQuestions = CurationReviewPolicy.questions(source: source, record: record, events: archive.events,
                hasWeeklySchedule: archive.sources.contains { $0.courseID == course.id && $0.meetingSchedule?.isEmpty == false })
            let prepared = CurationContext.prepare(source: source, course: course, relatedSources: archive.sources)
            let questions = LocalCurationRecovery.unresolvedIssues(initialQuestions, source: source, course: course, recoveredEvents: archive.events)
            return AuditSourceSummary(sourceID: source.id, courseCode: course.code, kind: source.kind?.rawValue ?? "unknown", characters: source.text.count,
                candidate: candidateKind(source), hasPublishedDate: source.publishedAt != nil, hasEffectiveDueDate: source.effectiveDueAt != nil,
                preparedCharacters: prepared.text.count, cachedEvents: record?.eventCount ?? 0, rawIssues: record?.issues?.count ?? 0,
                reviewQuestions: questions.count, issueCategories: questions.reduce(into: [:]) { $0[issueCategory($1), default: 0] += 1 },
                failure: record?.failure == nil ? nil : "recorded_failure")
        }
    }

    func checkpoint() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try privateWrite(encoder.encode(archive), to: output.appendingPathComponent("result-archive.json"))
        try privateWrite(encoder.encode(report), to: output.appendingPathComponent("summary.json"))
    }
}

private extension Set {
    var only: Element? { count == 1 ? first : nil }
}
private func normalizedCode(_ code: String) -> String { code.uppercased().filter { $0.isLetter || $0.isNumber } }
private func safeCode(_ code: String) -> String { String(code.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(30)) }
private func candidateKind(_ source: SourceDocument) -> String {
    if source.id.hasPrefix("official:") { return "official" }
    if source.kind == .syllabus || CanvasClient.isLikelySyllabus(source.title) { return "syllabus" }
    if source.kind == .announcement && source.text.range(of: #"\b(today|tomorrow|yesterday|this\s+(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday))\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return "relative-announcement" }
    return "other"
}
private func issueCategory(_ issue: String) -> String {
    let text = issue.lowercased()
    if text.contains("date") || text.contains("日期") || text.contains("deadline") { return "missing_or_conflicting_date" }
    if text.contains("time") || text.contains("时间") { return "missing_or_conflicting_time" }
    if text.contains("recurr") || text.contains("range") { return "recurrence_bounds" }
    return "other"
}
private func readPrivateInput(_ path: String, maxBytes: Int, secret: Bool = false) throws -> Data {
    var info = stat()
    guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_size <= maxBytes,
          !secret || info.st_mode & 0o077 == 0 else { throw AuditError.input }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard data.count <= maxBytes else { throw AuditError.input }
    return data
}
private func privateWrite(_ data: Data, to url: URL) throws {
    if FileManager.default.fileExists(atPath: url.path) {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid() else { throw AuditError.input }
    }
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
private func safeError(_ error: any Error) -> String {
    if error is CancellationError { return "cancelled" }
    if let value = error as? ConnectorError {
        switch value {
        case .http(let status): return "http_\(status)"
        case .invalidModelOutput: return "model_output_invalid"
        case .responseTooLarge: return "response_too_large"
        case .missingCredential, .invalidCredential: return "credential_invalid"
        case .unsupportedFile: return "unsupported_file"
        case .unsafeRedirect: return "unsafe_redirect"
        default: return "connector_invalid_response"
        }
    }
    if let value = error as? AuditError {
        switch value {
        case .arguments: return "invalid_arguments_use_help"
        case .input: return "invalid_or_unisolated_input"
        case .credentials: return "missing_explicit_credential"
        case .outputExists: return "output_exists_use_resume_or_new_directory"
        case .courseSelection: return "requested_courses_or_semester_ambiguous"
        case .configuration: return "invalid_configuration"
        }
    }
    if error is OfficialCourseScheduleError { return "official_schedule_unverified" }
    if error is DocumentError { return "document_unreadable" }
    if let value = error as? URLError { return "network_\(value.code.rawValue)" }
    return "operation_failed"
}
