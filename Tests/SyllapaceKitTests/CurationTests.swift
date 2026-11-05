import Foundation
import Testing
@testable import SyllapaceKit

private func curatedSource(_ text: String, id: String = "syllabus") -> SourceDocument {
    SourceDocument(id: id, courseID: "course", title: "Course schedule", text: text, hash: CanvasClient.hash(text))
}
private func curatedOutput(title: String, kind: EventKind, date: String? = nil, dateOnly: Bool = true,
                           evidence: String, zone: String = "America/New_York", recurrence: [String: Any]? = nil) throws -> String {
    let item: [String: Any] = ["title": title, "kind": kind.rawValue, "date": date as Any? ?? NSNull(),
                               "dateOnly": dateOnly, "timeZone": zone, "evidence": evidence,
                               "recurrence": recurrence as Any? ?? NSNull()]
    return String(decoding: try JSONSerialization.data(withJSONObject: ["events": [item], "issues": []]), as: UTF8.self)
}
private func curatedInstant(_ text: String) -> Date { CanvasClient.instant(text)! }
private func machineEvent(id: String = "model:one", sourceID: String = "syllabus", title: String = "Project 1", date: String = "2026-11-20T20:00:00Z") -> AcademicEvent {
    var event = AcademicEvent(id: id, courseID: "course", title: title, kind: .project, date: curatedInstant(date), dateOnly: false,
                              state: .approved, sourceID: sourceID, evidence: "Project 1 due November 20 at 15:00")
    event.curationVersion = EventCuration.version
    return event
}

@Suite("Automatic event curation") struct CurationTests {
    @Test func gradingProseNeverBecomesAnEventOrAnIssue() throws {
        let prose = "Presentations will be judged on the quality and depth of the analysis, as well as the clarity of the presentations (see attached presentation assessment forms). Students can expect not only to develop but also to provide recommendations."
        let source = curatedSource(prose)
        #expect(RuleExtractor.curate(source: source, year: 2026, timeZone: "America/New_York").events.isEmpty)
        #expect(RuleExtractor.curate(source: source, year: 2026, timeZone: "America/New_York").issues.isEmpty)
        let output = try curatedOutput(title: "Presentation", kind: .presentation, date: "2026-11-20", evidence: prose)
        let result = try LLMClient.parseCuration(content: output, source: source, year: 2026, timeZone: "America/New_York")
        #expect(result.events.isEmpty); #expect(result.issues.isEmpty)
    }
    @Test func localParsingDoesNotTurnDatedProjectAnnouncementsIntoDeadlines() {
        for text in ["Project introduced November 20", "Homework policies discussed November 20", "Report feedback available November 20"] {
            let result = RuleExtractor.curate(source: curatedSource(text), year: 2026, timeZone: "America/New_York")
            #expect(result.events.isEmpty); #expect(result.issues.isEmpty)
        }
    }
    @Test func dueDateWinsOverPublicationAndKeepsExactTime() throws {
        let text = "Project 1 released November 12, due November 20 at 11:59 PM."
        let output = try curatedOutput(title: "Project 1", kind: .project, date: "2026-11-20T23:59:00-05:00", dateOnly: false, evidence: text)
        let result = try LLMClient.parseCuration(content: output, source: curatedSource(text), year: 2026, timeZone: "America/New_York")
        let event = try #require(result.events.first)
        #expect(event.date == curatedInstant("2026-11-21T04:59:00Z"))
        #expect(event.state == .approved); #expect(event.category == .deadline)
        #expect(event.subtype == .project); #expect(result.issues.isEmpty)
        let wrong = try curatedOutput(title: "Project 1", kind: .project, date: "2026-11-12", evidence: text)
        let rejected = try LLMClient.parseCuration(content: wrong, source: curatedSource(text), year: 2026, timeZone: "America/New_York")
        #expect(rejected.events.isEmpty); #expect(rejected.issues.count == 1)
    }
    @Test func trueEvidenceDoesNotAuthorizeAnInventedDateOrDroppingTime() throws {
        for (text, date, dateOnly) in [("Midterm exam on November 12", "2026-11-13", true),
                                       ("Midterm exam on November 12 at 10:00", "2026-11-12", true)] {
            let output = try curatedOutput(title: "Midterm", kind: .exam, date: date, dateOnly: dateOnly, evidence: text)
            let result = try LLMClient.parseCuration(content: output, source: curatedSource(text), year: 2026, timeZone: "America/New_York")
            #expect(result.events.isEmpty); #expect(result.issues.count == 1)
        }
    }
    @Test func finalReportIsADeadlineAndUndatedTaskIsOnlyAnIssue() throws {
        let text = "Final report due November 20"
        let events = RuleExtractor.extract(source: curatedSource(text), year: 2026, timeZone: "America/New_York")
        #expect(events.first?.category == .deadline); #expect(events.first?.subtype == .report)
        let undated = "Project 2 is due on a date to be announced."
        let output = try curatedOutput(title: "Project 2", kind: .project, evidence: undated)
        let result = try LLMClient.parseCuration(content: output, source: curatedSource(undated), year: 2026, timeZone: "America/New_York")
        #expect(result.events.isEmpty); #expect(result.issues.count == 1)
    }
    @Test func recurrenceUsesExplicitTermAndLocalClockAcrossDST() throws {
        let text = "Lecture every Monday 10:00 to 11:00."
        let recurrence: [String: Any] = ["weekdays": [2], "startTime": "10:00", "endTime": "11:00"]
        let output = try curatedOutput(title: "Lecture", kind: .session, dateOnly: false, evidence: text, recurrence: recurrence)
        let start = curatedInstant("2026-10-26T00:00:00-04:00"), end = curatedInstant("2026-11-10T00:00:00-05:00")
        let result = try LLMClient.parseCuration(content: output, source: curatedSource(text), year: 2026, timeZone: "America/New_York", termStart: start, termEnd: end)
        #expect(result.issues.isEmpty); #expect(result.events.count == 3)
        #expect(result.events.map(\.date) == [curatedInstant("2026-10-26T14:00:00Z"), curatedInstant("2026-11-02T15:00:00Z"), curatedInstant("2026-11-09T15:00:00Z")])
        #expect(result.events.allSatisfy { $0.state == .approved && $0.subtype == .lecture && $0.sourceSeriesID != nil && $0.endsAt!.timeIntervalSince($0.date!) == 3600 })
        let missing = try LLMClient.parseCuration(content: output, source: curatedSource(text), year: 2026, timeZone: "America/New_York")
        #expect(missing.events.isEmpty); #expect(missing.issues.count == 1)
        let repeatResult = try LLMClient.parseCuration(content: output, source: curatedSource(text), year: 2026, timeZone: "America/New_York", termStart: start, termEnd: end)
        #expect(repeatResult.events.map(\.id) == result.events.map(\.id))
    }
    @Test func recurrenceCannotInventWeekdaysOrTimes() throws {
        let text = "Recitation every Friday 14:00 to 15:00."
        for recurrence: [String: Any] in [["weekdays": [2], "startTime": "14:00", "endTime": "15:00"],
                                          ["weekdays": [6], "startTime": "13:00", "endTime": "15:00"]] {
            let output = try curatedOutput(title: "Recitation", kind: .session, dateOnly: false, evidence: text, recurrence: recurrence)
            let result = try LLMClient.parseCuration(content: output, source: curatedSource(text), year: 2026, timeZone: "America/New_York", termStart: curatedInstant("2026-11-01T00:00:00Z"), termEnd: curatedInstant("2026-12-01T00:00:00Z"))
            #expect(result.events.isEmpty); #expect(result.issues.count == 1)
        }
    }
    @Test(arguments: [
        ("Lecture M/W 10–11 AM.", "10:00", "11:00"),
        ("Lecture MW 1:30–2:50 PM.", "13:30", "14:50")
    ]) func commonCourseNotationUsesSharedMeridiem(_ value: (String, String, String)) throws {
        let recurrence: [String: Any] = ["weekdays": [2, 4], "startTime": value.1, "endTime": value.2]
        let output = try curatedOutput(title: "Lecture", kind: .session, dateOnly: false, evidence: value.0, recurrence: recurrence)
        let result = try LLMClient.parseCuration(content: output, source: curatedSource(value.0), year: 2026, timeZone: "America/New_York", termStart: curatedInstant("2026-11-01T00:00:00-04:00"), termEnd: curatedInstant("2026-11-08T00:00:00-05:00"))
        #expect(result.issues.isEmpty); #expect(result.events.count == 2)
        #expect(result.events.allSatisfy { $0.subtype == .lecture })
    }
    @Test func chineseExplicitDeadlineRetainsDateTimeAndSubtype() throws {
        let text = "期末报告截止日期：2026年11月20日下午3点30分。"
        let output = try curatedOutput(title: "期末报告", kind: .assignment, date: "2026-11-20T15:30:00-05:00", dateOnly: false, evidence: text)
        let result = try LLMClient.parseCuration(content: output, source: curatedSource(text), year: 2026, timeZone: "America/New_York")
        #expect(result.issues.isEmpty); #expect(result.events.first?.date == curatedInstant("2026-11-20T20:30:00Z"))
        #expect(result.events.first?.subtype == .report)
        #expect(RuleExtractor.extract(source: curatedSource(text), year: 2026, timeZone: "America/New_York").first?.category == .deadline)
    }
    @Test func establishedHomeworkAliasesDeduplicateWithoutFuzzyMatching() {
        var first = machineEvent(id: "canvas:host:assignment:3", sourceID: "canvas", title: "HW3"); first.kind = .assignment
        var duplicate = machineEvent(id: "model:hw", sourceID: "syllabus", title: "Problem Set 03"); duplicate.kind = .assignment
        var different = duplicate; different.id = "model:hw4"; different.title = "Homework 4"
        let result = Reconciler.merge(existing: [first], incoming: [duplicate, different])
        #expect(result.count == 2); #expect(result[0].title == "HW3")
        #expect(result[0].relatedSourceIDs == ["syllabus"])
        #expect(result[1].title == "Homework 4")
    }
    @Test func sourceFingerprintIncludesPolicyModelAndExplicitBounds() {
        let source = curatedSource("Lecture Monday 10:00")
        let first = EventCuration.fingerprint(source: source, modelIdentity: "m1", year: 2026, timeZone: "UTC")
        #expect(first == EventCuration.fingerprint(source: source, modelIdentity: "m1", year: 2026, timeZone: "UTC"))
        #expect(first != EventCuration.fingerprint(source: source, modelIdentity: "m2", year: 2026, timeZone: "UTC"))
        #expect(first != EventCuration.fingerprint(source: source, modelIdentity: "m1", year: 2026, timeZone: "UTC", termStart: .distantPast))
        #expect(first != EventCuration.fingerprint(source: source, modelIdentity: "m1", year: 2026, timeZone: "UTC", intent: "Only quizzes"))
    }
    @Test func approvedSourceChangeIsAutomaticButManualOverrideIsProtected() throws {
        var old = machineEvent(); old.progress = .doing; old.plannedStart = curatedInstant("2026-11-19T20:00:00Z")
        var changed = old; changed.date = curatedInstant("2026-11-18T20:00:00Z")
        let result = try #require(Reconciler.merge(existing: [old], incoming: [changed]).first)
        #expect(result.state == .approved); #expect(result.date == changed.date)
        #expect(result.previousDate == old.date); #expect(result.revision == 1)
        #expect(result.progress == .doing); #expect(result.plannedStart == nil)
        #expect(Reconciler.merge(existing: [result], incoming: [changed]).first?.revision == 1)
        old.userEdited = true
        let protected = try #require(Reconciler.merge(existing: [old], incoming: [changed]).first)
        #expect(protected.state == .conflict); #expect(protected.date == old.date)
    }
    @Test func validLegacyPendingPromotesAndAllMeaningfulChangesIncrementRevision() throws {
        var old = machineEvent(); old.state = .pending; old.curationVersion = nil
        let incoming = machineEvent()
        let promoted = try #require(Reconciler.merge(existing: [old], incoming: [incoming]).first)
        #expect(promoted.state == .approved); #expect(promoted.revision == 1)
        var renamed = incoming; renamed.title = "Project 1 · Prototype"
        let renamedResult = try #require(Reconciler.merge(existing: [promoted], incoming: [renamed]).first)
        #expect(renamedResult.title == renamed.title); #expect(renamedResult.revision == 2)
        #expect(Reconciler.merge(existing: [renamedResult], incoming: [renamed]).first?.revision == 2)
    }
    @Test func canvasDeadlineKeepsAuthorityAndDuplicateEvidenceCollapses() {
        let canvas = machineEvent(id: "canvas:host:assignment:1", sourceID: "canvas-source")
        let syllabus = machineEvent(id: "model:syllabus", sourceID: "syllabus", date: "2026-11-22T20:00:00Z")
        let result = Reconciler.merge(existing: [canvas], incoming: [syllabus])
        #expect(result.count == 1); #expect(result[0].date == canvas.date)
        #expect(result[0].relatedSourceIDs == ["syllabus"])
        #expect(result[0].state == .approved)
        let organization = EventCuration.reorganize(existing: [canvas], incoming: [], sourceIDs: ["canvas-source"])
        #expect(organization.events == [canvas])
    }
    @Test func differentWeeklyOccurrencesAreNotCrossSourceDuplicates() {
        var first = machineEvent(id: "model:lecture1", sourceID: "one", title: "Lecture")
        first.kind = .session
        var second = first; second.id = "model:lecture2"; second.sourceID = "two"; second.date = first.date!.addingTimeInterval(7 * 86_400)
        let result = Reconciler.merge(existing: [first], incoming: [second])
        #expect(result.count == 2); #expect(result.allSatisfy { $0.state == .approved })
    }
    @Test func repeatedTitlesMatchTheCorrectOccurrenceAcrossSources() {
        var first = machineEvent(id: "model:lecture1", sourceID: "one", title: "Lecture"); first.kind = .session
        var next = first; next.id = "model:lecture2"; next.date = first.date!.addingTimeInterval(7 * 86_400)
        var duplicateFirst = first; duplicateFirst.id = "model:copy1"; duplicateFirst.sourceID = "two"
        var duplicateNext = next; duplicateNext.id = "model:copy2"; duplicateNext.sourceID = "two"
        let result = Reconciler.merge(existing: [first, next], incoming: [duplicateFirst, duplicateNext])
        #expect(result.count == 2); #expect(result.allSatisfy { $0.relatedSourceIDs == ["two"] })
        #expect(result.map(\.date) == [first.date, next.date])
    }
    @Test func newConflictingProposalHasNeverBeenApproved() throws {
        let first = machineEvent(sourceID: "first")
        let second = machineEvent(id: "model:second", sourceID: "second", date: "2026-11-22T20:00:00Z")
        let proposed = try #require(Reconciler.merge(existing: [first], incoming: [second]).last)
        #expect(proposed.state == .conflict); #expect(proposed.wasApproved == false)
    }
    @Test func reorganizationKeepsTheProposalWhenUserEditedTheEvent() throws {
        var edited = machineEvent(); edited.userEdited = true; edited.title = "My project title"
        var changed = machineEvent(); changed.date = curatedInstant("2026-11-22T20:00:00Z")
        changed.evidence = "Project 1 due November 22 at 15:00"
        let event = try #require(EventCuration.reorganize(existing: [edited], incoming: [changed], sourceIDs: ["syllabus"]).events.first)
        #expect(event.title == edited.title); #expect(event.date == edited.date)
        #expect(event.state == .conflict); #expect(event.proposedDate == changed.date)
    }
    @Test func sameSourceRepeatedQuizTitlesRemainIndependentAfterModelParsing() throws {
        let source = curatedSource("Quiz November 2\nQuiz November 9")
        let first = try curatedOutput(title: "Quiz", kind: .quiz, date: "2026-11-02", evidence: "Quiz November 2")
        let second = try curatedOutput(title: "Quiz", kind: .quiz, date: "2026-11-09", evidence: "Quiz November 9")
        let events = try [first, second].flatMap { try LLMClient.parseCuration(content: $0, source: source, year: 2026, timeZone: "America/New_York").events }
        let merged = Reconciler.merge(existing: [], incoming: events)
        #expect(merged.count == 2); #expect(merged.allSatisfy { $0.state == .approved })
        #expect(Reconciler.merge(existing: merged, incoming: events) == merged)
    }
    @Test func renamedModelTaskKeepsItsIdentityWhenSourceDueDateMoves() throws {
        let firstText = "Final project due November 20"
        let firstOutput = try curatedOutput(title: "Final project", kind: .project, date: "2026-11-20", evidence: firstText)
        var edited = try #require(try LLMClient.parseCuration(content: firstOutput, source: curatedSource(firstText), year: 2026, timeZone: "America/New_York").events.first)
        edited.title = "My final project"; edited.userEdited = true
        let secondText = "Final project due November 22"
        let secondOutput = try curatedOutput(title: "Final project", kind: .project, date: "2026-11-22", evidence: secondText)
        let observations = try LLMClient.parseCuration(content: secondOutput, source: curatedSource(secondText), year: 2026, timeZone: "America/New_York").events
        #expect(observations.first?.id != edited.id)
        let organized = EventCuration.reorganize(existing: [edited], incoming: observations, sourceIDs: ["syllabus"]).events
        #expect(organized.count == 1)
        let event = try #require(organized.first)
        #expect(event.id == edited.id); #expect(event.title == edited.title); #expect(event.date == edited.date)
        #expect(event.sourceTitle == "Final project"); #expect(event.state == .conflict)
        #expect(event.wasApproved == true); #expect(event.proposedDate == observations.first?.date)
        #expect(organized.filter { $0.state == .approved || ($0.state == .conflict && $0.wasApproved == true) }.count == 1)
    }
    @Test func legacyRenamedTaskIsRecoveredOnlyByItsProvenSourceIdentity() throws {
        let text = "Final project due November 22"
        let output = try curatedOutput(title: "Final project", kind: .project, date: "2026-11-22", evidence: text)
        let observations = try LLMClient.parseCuration(content: output, source: curatedSource(text), year: 2026, timeZone: "America/New_York").events
        var legacy = machineEvent(id: "model:" + CanvasClient.hash("syllabus:final project:project:0"), title: "My own project title")
        legacy.userEdited = true; legacy.curationVersion = nil; legacy.sourceTitle = nil
        let result = EventCuration.reorganize(existing: [legacy], incoming: observations, sourceIDs: ["syllabus"]).events
        #expect(result.count == 1); #expect(result.first?.id == legacy.id)
        #expect(result.first?.title == legacy.title); #expect(result.first?.date == legacy.date)
        #expect(result.first?.proposedDate == observations.first?.date); #expect(result.first?.sourceTitle == "Final project")
        var unrelated = legacy; unrelated.id = "model:unrelated"; unrelated.sourceID = "another-source"
        let separate = EventCuration.reorganize(existing: [unrelated], incoming: observations, sourceIDs: ["syllabus"]).events
        #expect(separate.count == 2); #expect(separate.first == unrelated)
    }
    @Test func reorganizationIsIdempotentReversibleAndPreservesLaterEdits() {
        let valid = machineEvent()
        var junk = machineEvent(id: "model:junk", title: "Grading policy"); junk.date = nil
        var manual = machineEvent(id: "manual", sourceID: "manual-source"); manual.userEdited = true
        var rejected = machineEvent(id: "model:rejected", sourceID: "rejected-source"); rejected.state = .rejected
        var undone = machineEvent(id: "model:undone", sourceID: "undone-source"); undone.importUndone = true; undone.state = .rejected
        let original = [valid, junk, manual, rejected, undone]
        let result = EventCuration.reorganize(existing: original, incoming: [valid, manual, rejected, undone], sourceIDs: ["syllabus"])
        #expect(result.events.first == valid)
        #expect(result.events[1].state == .rejected); #expect(result.events[1].curationExcluded == true)
        #expect(Array(result.events.suffix(3)) == [manual, rejected, undone])
        #expect(EventCuration.reorganize(existing: result.events, incoming: [valid], sourceIDs: ["syllabus"]).events == result.events)
        #expect(result.undo(current: result.events) == original)
        var edited = result.events; edited[0].progress = .done; edited[0].revision += 1
        #expect(result.undo(current: edited)[0].progress == .done)
    }
    @Test func cleanupTouchesOnlyMachineOwnedCourseEvents() {
        var canvasJunk = machineEvent(id: "canvas:host:calendar:1"); canvasJunk.kind = .other
        var manual = canvasJunk; manual.id = "manual"
        var edited = canvasJunk; edited.id = "canvas:host:calendar:2"; edited.userEdited = true
        var school = canvasJunk; school.academicCalendarID = "school"
        let result = EventCuration.sanitizeLegacyEvents(existing: [canvasJunk, manual, edited, school], courseIDs: ["course"])
        #expect(result.events[0].state == .rejected); #expect(result.events[0].curationExcluded == true)
        #expect(Array(result.events.suffix(3)) == [manual, edited, school])
        #expect(result.undo(current: result.events) == [canvasJunk, manual, edited, school])
    }
    @Test func oldCompletedArchivesAndNewProgressAreCompatible() throws {
        var old = machineEvent(); old.completed = true
        let encoded = try JSONEncoder().encode(old)
        let loaded = try JSONDecoder().decode(AcademicEvent.self, from: encoded)
        #expect(loaded.taskProgress == nil); #expect(loaded.progress == .done)
        var new = loaded; new.progress = .doing
        #expect(!new.completed); #expect(new.progress == .doing)
        new.progress = .done; #expect(new.completed)
        new.progress = .todo; #expect(!new.completed)
    }
    @Test func explicitClassCancellationIsExcludedAndCannotBeOmitted() throws {
        let text = "Lecture Mondays 10:00 to 11:00. No class November 2."
        let start = curatedInstant("2026-10-26T00:00:00-04:00"), end = curatedInstant("2026-11-10T00:00:00-05:00")
        var recurrence: [String: Any] = ["weekdays": [2], "startTime": "10:00", "endTime": "11:00", "excludedDates": ["2026-11-02"]]
        let output = try curatedOutput(title: "Lecture", kind: .session, dateOnly: false, evidence: text, recurrence: recurrence)
        let result = try LLMClient.parseCuration(content: output, source: curatedSource(text), year: 2026, timeZone: "America/New_York", termStart: start, termEnd: end)
        #expect(result.events.count == 2); #expect(result.issues.isEmpty)
        #expect(!result.events.contains { $0.date == curatedInstant("2026-11-02T15:00:00Z") })
        recurrence["excludedDates"] = []
        let missing = try curatedOutput(title: "Lecture", kind: .session, dateOnly: false, evidence: text, recurrence: recurrence)
        let unresolved = try LLMClient.parseCuration(content: missing, source: curatedSource(text), year: 2026, timeZone: "America/New_York", termStart: start, termEnd: end)
        #expect(unresolved.events.isEmpty); #expect(unresolved.issues.count == 1)
    }
    @Test func schemaThreeGetsAnImmutableMigrationBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("archive.json")
        var legacy = AppArchive(); legacy.schemaVersion = 3; legacy.events = [machineEvent()]
        let data = try JSONEncoder().encode(legacy); try data.write(to: url)
        let store = ArchiveStore(url: url)
        let migrated = try store.load(); #expect(migrated.schemaVersion == 4)
        #expect(try Data(contentsOf: url) == data)
        try store.save(migrated)
        #expect(try Data(contentsOf: url.appendingPathExtension("schema-3.backup")) == data)
        try store.save(migrated)
        #expect(try Data(contentsOf: url.appendingPathExtension("schema-3.backup")) == data)
    }
    @Test func modelCannotSilentlyChangeTheCourseTimeZone() throws {
        let text = "Midterm exam November 20 at 10:00."
        let output = try curatedOutput(title: "Midterm", kind: .exam, date: "2026-11-20T10:00:00-08:00", dateOnly: false, evidence: text, zone: "America/Los_Angeles")
        let result = try LLMClient.parseCuration(content: output, source: curatedSource(text), year: 2026, timeZone: "America/New_York")
        #expect(result.events.isEmpty); #expect(result.issues.count == 1)
    }
    @Test func sourceImportContextSurvivesPersistenceWithoutChangingLegacySources() throws {
        let old = curatedSource("Homework 3 due November 20")
        let legacy = try JSONDecoder().decode(SourceDocument.self, from: JSONEncoder().encode(old))
        #expect(legacy.curationYear == nil); #expect(legacy.curationTimeZone == nil); #expect(legacy.curationIntent == nil); #expect(legacy.localOnly == nil)
        var specific = old; specific.curationYear = 2027; specific.curationTimeZone = "America/Los_Angeles"; specific.curationIntent = "Only project deadlines"; specific.localOnly = true
        let restored = try JSONDecoder().decode(SourceDocument.self, from: JSONEncoder().encode(specific))
        #expect(restored.curationYear == 2027); #expect(restored.curationTimeZone == "America/Los_Angeles")
        #expect(restored.curationIntent == "Only project deadlines")
        #expect(restored.localOnly == true)
    }
}
