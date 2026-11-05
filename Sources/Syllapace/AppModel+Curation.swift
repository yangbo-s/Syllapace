import Foundation
import SyllapaceKit

extension AppModel {
    var unresolvedEvents: [AcademicEvent] {
        scopedEvents.filter { $0.state == .conflict && ($0.userEdited || $0.curationVersion != nil) }
    }
    var curationSources: [SourceDocument] {
        archive.sources.filter { $0.academicCalendarID == nil && isInScope(courseID: $0.courseID, calendarID: nil) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var curationIssues: [(source: SourceDocument, message: String)] {
        curationSources.compactMap { source in
            let record = archive.curationRecords?[source.id]
            let messages = (curationErrors[source.id] ?? record?.failure).map { [$0] } ?? record?.issues ?? []
            return messages.isEmpty ? nil : (source, messages.joined(separator: "\n"))
        }
    }
    var curationModelIdentity: String { [modelProvider.rawValue, modelEndpoint, modelName, modelWorkspaceID].joined(separator: "|") }
    func curationWindow(for source: SourceDocument) -> (start: Date?, end: Date?) {
        let owner = course(source.courseID)
        // A term label such as Fall 2026 is not evidence of the first or last class.
        return (owner.startsAt ?? owner.term?.startAt, owner.endsAt ?? owner.term?.endAt)
    }
    func curationFingerprint(_ source: SourceDocument) -> String {
        let owner = course(source.courseID), window = curationWindow(for: source)
        return EventCuration.fingerprint(source: source, modelIdentity: curationModelIdentity,
            year: source.curationYear ?? owner.term?.academicYear ?? importYear, timeZone: source.curationTimeZone ?? owner.timeZone ?? TimeZone.current.identifier,
            termStart: window.start, termEnd: window.end, intent: source.curationIntent ?? "")
    }
    func cancelCuration() {
        curationGeneration = UUID(); curationTask?.cancel(); curationTask = nil
        curationQueued = false; curationStatus = nil
    }
    func sourcesNeedingCuration(sourceIDs: Set<String>? = nil, force: Bool = false) -> [SourceDocument] {
        curationSources.filter { source in
            (sourceIDs == nil || sourceIDs!.contains(source.id)) &&
            (force || source.localOnly != true) &&
            (force || archive.curationRecords?[source.id]?.fingerprint != curationFingerprint(source))
        }
    }
    func scheduleCuration(sourceIDs: Set<String>? = nil, force: Bool = false) {
        guard !isDemo, !credentialsChanging, !showImport, ProcessInfo.processInfo.environment["APP_SELFTEST"] != "1", automaticCuration || force else { return }
        if curationTask != nil {
            if force { cancelCuration() } else { curationQueued = true; return }
        }
        let sources = sourcesNeedingCuration(sourceIDs: sourceIDs, force: force)
        guard !sources.isEmpty else { return }
        guard !modelName.isEmpty else {
            notice = L10n.string("Materials are saved. Choose a model in Settings to organize them automatically.")
            return
        }
        let generation = curationGeneration, modelIdentity = curationModelIdentity
        let endpoint = modelEndpoint, provider = modelProvider, name = modelName, workspace = modelWorkspaceID, account = modelCredentialAccount
        curationStatus = L10n.string("Organizing course materials…")
        curationTask = Task {
            var changed = false
            var batchUndo: [ImportUndo] = []
            defer {
                if curationGeneration == generation {
                    curationTask = nil; curationStatus = nil
                    if curationQueued { curationQueued = false; scheduleCuration() }
                }
            }
            do {
                guard let key = try await CredentialStore.readAsync(account), !key.isEmpty else {
                    notice = L10n.string("Materials are saved. Add your model API key in Settings to organize them.")
                    return
                }
                let client = try LLMClient(endpoint: endpoint, key: key, model: name, provider: provider, workspaceID: workspace.isEmpty ? nil : workspace)
                for (index, source) in sources.enumerated() {
                    try Task.checkCancellation()
                    guard generation == curationGeneration, modelIdentity == curationModelIdentity,
                          isInScope(courseID: source.courseID, calendarID: nil) else { return }
                    guard let currentSource = archive.sources.first(where: { $0.id == source.id }),
                          force || currentSource.localOnly != true,
                          curationFingerprint(currentSource) == curationFingerprint(source) else { continue }
                    let fingerprint = curationFingerprint(source)
                    let owner = course(source.courseID), window = curationWindow(for: source)
                    curationStatus = L10n.format("Organizing material %ld of %ld…", index + 1, sources.count)
                    do {
                        let result = try await client.curate(source: source, year: source.curationYear ?? owner.term?.academicYear ?? importYear,
                            timeZone: source.curationTimeZone ?? owner.timeZone ?? TimeZone.current.identifier, intent: source.curationIntent ?? "", termStart: window.start, termEnd: window.end)
                        try Task.checkCancellation()
                        guard generation == curationGeneration, modelIdentity == curationModelIdentity,
                              isInScope(courseID: source.courseID, calendarID: nil),
                              let current = archive.sources.first(where: { $0.id == source.id }),
                              force || current.localOnly != true,
                              curationFingerprint(current) == fingerprint else { continue }
                        let previous = archive
                        guard commitCuration(result, source: source, fingerprint: fingerprint) else { return }
                        if previous.events != archive.events {
                            batchUndo.append(curationUndo(before: previous, after: archive))
                            lastCurationUndo = batchUndo
                            changed = true
                        }
                        curationErrors[source.id] = nil
                    } catch is CancellationError { return }
                    catch {
                        curationErrors[source.id] = error.localizedDescription
                        guard generation == curationGeneration,
                              let current = archive.sources.first(where: { $0.id == source.id }),
                              curationFingerprint(current) == fingerprint else { continue }
                        if archive.curationRecords == nil { archive.curationRecords = [:] }
                        archive.curationRecords?[source.id] = SourceCurationRecord(fingerprint: fingerprint, failure: error.localizedDescription)
                        _ = save()
                    }
                }
                if changed { notice = L10n.string("Course dates organized. You can undo this reorganization.") }
            } catch is CancellationError { }
            catch { notice = error.localizedDescription }
        }
    }
    @discardableResult func commitCuration(_ result: CurationResult, source: SourceDocument, fingerprint: String) -> Bool {
        guard isInScope(courseID: source.courseID, calendarID: source.academicCalendarID),
              let current = archive.sources.first(where: { $0.id == source.id }),
              curationFingerprint(current) == fingerprint else { return false }
        let checkpoint = archive
        archive.events = result.issues.isEmpty
            ? EventCuration.reorganize(existing: archive.events, incoming: result.events, sourceIDs: [source.id]).events
            : Reconciler.merge(existing: archive.events, incoming: result.events)
        if archive.curationRecords == nil { archive.curationRecords = [:] }
        archive.curationRecords?[source.id] = SourceCurationRecord(fingerprint: fingerprint, eventCount: result.events.count, issues: result.issues)
        restoreLocalSchedules()
        guard save() else { archive = checkpoint; return false }
        return true
    }
    func curationUndo(before: AppArchive, after: AppArchive) -> ImportUndo {
        let old = Dictionary(before.events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let changed = Set(after.events.filter { old[$0.id] != $0 }.map(\.id))
        var sparseBefore = AppArchive(), sparseAfter = AppArchive()
        sparseBefore.events = before.events.filter { changed.contains($0.id) }
        sparseAfter.events = after.events.filter { changed.contains($0.id) }
        return ImportUndo(before: sparseBefore, after: sparseAfter)
    }
    func sanitizeLegacyData() {
        let before = archive
        for source in curationSources {
            guard let record = archive.curationRecords?[source.id], record.fingerprint != curationFingerprint(source) else { continue }
            let owner = course(source.courseID), window = curationWindow(for: source)
            if [1, 2].contains(where: { version in
                record.fingerprint == EventCuration.legacyFingerprint(source: source, version: version, modelIdentity: curationModelIdentity,
                    year: source.curationYear ?? owner.term?.academicYear ?? importYear,
                    timeZone: source.curationTimeZone ?? owner.timeZone ?? TimeZone.current.identifier,
                    termStart: window.start, termEnd: window.end, intent: source.curationIntent ?? "")
            }) {
                let fingerprint = curationFingerprint(source)
                archive.curationRecords?[source.id]?.fingerprint = fingerprint
            }
        }
        archive.events = EventCuration.sanitizeLegacyEvents(existing: archive.events, courseIDs: scopedCourseIDs).events
        restoreLocalSchedules()
        guard before.events != archive.events || before.curationRecords != archive.curationRecords else { return }
        guard save() else { archive = before; return }
        guard before.events != archive.events else { return }
        lastCurationUndo = [curationUndo(before: before, after: archive)]
        notice = L10n.string("Course dates organized. You can undo this reorganization.")
    }
    func restoreLocalSchedules() {
        for source in curationSources {
            let owner = course(source.courseID), window = curationWindow(for: source)
            let meetings = WeeklySchedule.extract(source: source, year: owner.term?.academicYear ?? importYear,
                timeZone: source.curationTimeZone ?? owner.timeZone ?? TimeZone.current.identifier, termStart: window.start, termEnd: window.end)
            archive.events = Reconciler.merge(existing: archive.events, incoming: meetings)
        }
    }
    func undoCuration() {
        guard let undo = lastCurationUndo else { return }
        cancelCuration()
        let before = archive
        let previous = archive.events
        archive.events = undo.reversed().reduce(previous) { events, operation in operation.restoreEvents(in: events) }
        let retained = Set(archive.events.map(\.id))
        archive.events += previous.filter { !retained.contains($0.id) }.map {
            var event = $0; event.state = .rejected; event.importUndone = true; return event
        }
        guard save() else { archive = before; return }
        lastCurationUndo = nil
        notice = L10n.string("Reorganization undone. Later edits were kept.")
    }
}
