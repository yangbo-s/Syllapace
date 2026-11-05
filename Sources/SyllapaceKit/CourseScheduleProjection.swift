import Foundation

/// One read model for the workspace and calendar exports. Source observations
/// remain untouched, including superseded local recurrence expansions.
public enum CourseScheduleProjection {
    public static func project(events: [AcademicEvent], sources: [SourceDocument], courses: [Course]) -> [AcademicEvent] {
        let verified = sources.filter { $0.meetingSchedule?.isEmpty == false }
        let officialIDs = Set(verified.map(\.id))
        let coveredCourses = Set(verified.filter { $0.meetingScheduleComplete == true }.map(\.courseID))
        let cancellations = sources.flatMap { source in
            courses.first(where: { $0.id == source.courseID }).map { CancellationEvidence.extract(source: source, course: $0) } ?? []
        }
        let protectedAliases = Set(events.filter { $0.userEdited || $0.state == .rejected }.flatMap { $0.relatedEventIDs ?? [] })
        let observations = events.filter { !protectedAliases.contains($0.id) || $0.userEdited }.map { original -> AcademicEvent in
            var event = original
            if event.sourceID == nil, event.id.hasPrefix("canvas:"), event.id.contains(":calendar:") {
                let suffix = event.id.components(separatedBy: ":calendar:").last!
                event.sourceID = sources.first { $0.courseID == event.courseID && $0.id.hasSuffix(":calendar:" + suffix) }?.id ?? event.id
            }
            if event.sourceID.map(officialIDs.contains) == true, event.location == "Pittsburgh, Pennsylvania" {
                event.location = nil
            }
            return event
        }
        // Corroborating syllabus occurrences first enrich the verified meeting's
        // subtype and evidence; only unmatched inferred expansions are retired.
        let labeled = withSyllabusRoles(observations, verified: verified, sources: sources, courses: courses)
        let tasks = DeadlineReconciliation.project(events: consolidateCanvasObservations(labeled), sources: sources)
        let joined = MeetingReconciliation.project(events: tasks, canonicalSourceIDs: officialIDs)
        return joined.filter { event in
            guard !event.userEdited, event.importUndone != true, event.curationExcluded != true,
                  event.state == .approved, event.kind == .session else { return true }
            let official = event.sourceID.map(officialIDs.contains) ?? false
            let generatedSeries = event.sourceSeriesID.map { $0.hasPrefix("model-series:") || $0.hasPrefix("schedule:") } ?? false
            if !official, generatedSeries, coveredCourses.contains(event.courseID) { return false }
            return !cancellations.contains(where: { $0.matches(event: event) })
        }
    }

    /// Meeting labels remain grounded in the written weekly schedule even when
    /// the model correctly omits already-scheduled recurring meetings.
    private static func withSyllabusRoles(_ events: [AcademicEvent], verified: [SourceDocument], sources: [SourceDocument], courses: [Course]) -> [AcademicEvent] {
        struct Slot: Hashable { let course: String; let date: Date; let end: Date?; let zone: String }
        var roles: [Slot: [(EventSubtype, String)]] = [:]
        for source in sources where source.kind == .syllabus {
            guard let course = courses.first(where: { $0.id == source.courseID }), let year = source.curationYear ?? course.term?.academicYear,
                  let timetable = verified.first(where: { $0.courseID == course.id && $0.teachingStartsAt != nil && $0.teachingEndsAt != nil }) else { continue }
            let meetings = WeeklySchedule.extract(source: source, year: year, timeZone: source.curationTimeZone ?? course.timeZone ?? "America/New_York",
                                                  termStart: timetable.teachingStartsAt, termEnd: timetable.teachingEndsAt)
            for event in meetings {
                guard let date = event.date, let subtype = event.subtype,
                      EventCuration.matches(#"^(?:Lectures?|Recitations?|Labs?)\s*[:：]"#, event.evidence) else { continue }
                roles[Slot(course: course.id, date: date, end: event.endsAt, zone: event.timeZone), default: []].append((subtype, source.id))
            }
        }
        let official = Set(verified.map(\.id))
        return events.map { event in
            guard !event.userEdited, event.kind == .session, let date = event.date,
                  event.sourceID.map(official.contains) == true,
                  (event.subtype ?? EventCuration.subtype(for: event.title, kind: .session)) == .classMeeting,
                  let evidence = roles[Slot(course: event.courseID, date: date, end: event.endsAt, zone: event.timeZone)],
                  Set(evidence.map { $0.0 }).count == 1, let subtype = evidence.first?.0 else { return event }
            var result = event; result.subtype = subtype
            result.title = (courses.first { $0.id == event.courseID }?.code ?? "") + " " + subtype.rawValue.capitalized
            result.relatedSourceIDs = Array(Set((event.relatedSourceIDs ?? []) + evidence.map { $0.1 })).sorted()
            return result
        }
    }

    private static func consolidateCanvasObservations(_ events: [AcademicEvent]) -> [AcademicEvent] {
        var result = events, redundant = Set<String>()
        for legacy in events where legacy.id.hasPrefix("model:") && (legacy.curationVersion ?? 0) < EventCuration.version && !legacy.userEdited && legacy.state == .approved {
            let matches = events.filter { current in
                current.id.hasPrefix("model:") && current.id != legacy.id && current.sourceID != nil && current.sourceID == legacy.sourceID &&
                current.courseID == legacy.courseID && current.kind == legacy.kind && current.subtype == legacy.subtype &&
                current.date != nil && current.date == legacy.date && current.dateOnly == legacy.dateOnly && current.timeZone == legacy.timeZone &&
                current.curationVersion == EventCuration.version && current.state == .approved && !current.userEdited
            }
            if matches.count == 1, let current = matches.first, let index = result.firstIndex(where: { $0.id == current.id }) {
                result[index].relatedEventIDs = Array(Set((result[index].relatedEventIDs ?? []) + (legacy.relatedEventIDs ?? []) + [legacy.id])).sorted()
                redundant.insert(legacy.id)
            }
        }
        for index in result.indices {
            let native = result[index]
            guard native.id.hasPrefix("canvas:"), native.state == .approved, !native.userEdited,
                  native.importUndone != true, native.date != nil else { continue }
            let derived = events.filter { event in
                event.id.hasPrefix("model:") && !redundant.contains(event.id) && (event.sourceID == native.id || event.sourceID == native.sourceID) &&
                event.state == .approved && !event.userEdited && event.importUndone != true &&
                event.kind == native.kind && event.date == native.date && event.dateOnly == native.dateOnly &&
                event.timeZone == native.timeZone &&
                (event.subtype == native.subtype || event.subtype == nil || native.subtype == nil)
            }
            // Multiple interpretations from one model are not proof of one event.
            guard derived.count == 1, let copy = derived.first else { continue }
            // A unique model interpretation of this exact Canvas event is not
            // a second meeting. Structured API bounds/location stay authoritative.
            if result[index].endsAt == nil { result[index].endsAt = copy.endsAt }
            if result[index].location == nil { result[index].location = copy.location }
            let enriched = result.first { $0.id == copy.id } ?? copy
            result[index].relatedEventIDs = Array(Set((result[index].relatedEventIDs ?? []) + (enriched.relatedEventIDs ?? []) + [copy.id])).sorted()
            result[index].relatedSourceIDs = Array(Set((result[index].relatedSourceIDs ?? []) + (enriched.relatedSourceIDs ?? []))).sorted()
            redundant.insert(copy.id)
        }
        return result.filter { !redundant.contains($0.id) }
    }

    /// Explicit tombstones let EventKit retire previously published duplicates;
    /// its planner still preserves edits made in Calendar.
    public static func publication(events: [AcademicEvent], sources: [SourceDocument], courses: [Course]) -> [AcademicEvent] {
        let visible = project(events: events, sources: sources, courses: courses)
        let ids = Set(visible.map(\.id))
        return visible + events.filter { !ids.contains($0.id) }.map {
            var retired = $0; retired.state = .rejected; return retired
        }
    }
}
