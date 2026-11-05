import Foundation
import SyllapaceKit

extension AppModel {
    func refreshOfficialSchedules(force: Bool = false) async {
        guard !isDemo, ProcessInfo.processInfo.environment["APP_SELFTEST"] != "1",
              OfficialCourseScheduleClient.supports(canvasHost: canvasHost), !fetchingCourseSchedules else { return }
        let host = canvasHost, selection = archive.canvasSelection
        let courses = scopedCourses.filter(\.isCanvas)
        let groups = Dictionary(grouping: courses.filter { $0.term != nil }, by: { $0.term!.name })
        guard !groups.isEmpty else { return }
        fetchingCourseSchedules = true
        defer { fetchingCourseSchedules = false }
        let client = OfficialCourseScheduleClient()
        for (semester, members) in groups.sorted(by: { $0.key < $1.key }) {
            let needsRefresh = members.contains { course in
                !archive.sources.contains { $0.courseID == course.id && $0.meetingSchedule != nil && $0.fetchedAt > Date.now.addingTimeInterval(-86400) }
            }
            guard force || needsRefresh else { continue }
            do {
                let snapshot = try await client.fetch(semester: semester)
                try Task.checkCancellation()
                guard canvasHost == host, archive.canvasSelection == selection else { return }
                let checkpoint = archive
                for course in members where scopedCourseIDs.contains(course.id) {
                    do {
                        var source = try snapshot.sourceDocument(course: course)
                        let schedule = try snapshot.events(for: course)
                        guard !schedule.isEmpty else { continue }
                        source.meetingSchedule = schedule
                        ingest(source, navigate: false)
                        archive.events = EventCuration.reorganize(existing: archive.events, incoming: schedule, sourceIDs: [source.id]).events
                        officialScheduleErrors[course.id] = nil
                    } catch { officialScheduleErrors[course.id] = error.localizedDescription }
                }
                guard save() else { archive = checkpoint; return }
            } catch is CancellationError { return }
            catch {
                for course in members { officialScheduleErrors[course.id] = error.localizedDescription }
            }
        }
    }
}
