import AppKit
import SyllapaceKit

enum SelfTest {
    static var ran = false
    static func runIfRequested(model: AppModel) {
        guard !ran, ProcessInfo.processInfo.environment["APP_SELFTEST"] == "1" else { return }
        ran = true
        guard let path = ProcessInfo.processInfo.environment["APP_STORE"], path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/") else { fail("Self-test requires isolated APP_STORE"); return }
        func check(_ condition: Bool, _ text: String) { if condition { Snapshot.log("PASS \(text)") } else { fail(text) } }
        let courseID = model.addCourse(name: "Integration fixture")
        let source = SourceDocument(id: "selftest-source", courseID: courseID, title: "Synthetic syllabus", text: "Final project due November 20, 2026", hash: "v1")
        model.importYear = 2026
        model.ingest(source)
        check(model.page == .review && !model.events.isEmpty, "Import creates review candidates")
        guard var event = model.events.first else { fail("No parsed fixture event"); return }
        model.approve(event)
        check(model.archive.events.first(where: { $0.id == event.id })?.state == .approved, "Approve promotes a dated candidate")
        let count = model.archive.events.count
        model.ingest(source)
        check(model.archive.events.count == count, "Repeated import keeps stable identity")
        event = model.archive.events.first(where: { $0.id == event.id })!
        event.userEdited = true; event.title = "My final project"; model.update(event)
        var changed = source; changed.text = "Final project due November 22, 2026"; changed.hash = "v2"
        model.ingest(changed)
        let result = model.archive.events.first(where: { $0.id == event.id })!
        check(result.state == .conflict && result.date == event.date && result.title == "My final project", "Source revision preserves user decision")
        model.page = .timeline
        model.ingest(changed, navigate: false)
        check(model.page == .timeline, "Unchanged background source does not navigate")
        do { let restored = try model.store.load(); check(restored.events == model.archive.events, "Archive survives reload") } catch { fail(error.localizedDescription) }
        check(model.error == nil, "No persistence error")
        check(L10n.string("Today", language: .english) == "Today"
              && L10n.string("Today", language: .simplifiedChinese) != "Today"
              && L10n.string("Canvas", language: .simplifiedChinese) == "Canvas",
              "Packaged language resources load and preserve product names")
        let updater = UpdateController()
        updater.startIfNeeded()
        check(!updater.isAvailable && !updater.canCheckForUpdates,
              "Isolated self-test cannot start update checks")
        let fall = AcademicTerm(id: "fixture:fall", name: "Fall 2026")
        let spring = AcademicTerm(id: "fixture:spring", name: "Spring 2026")
        let fallCourse = Course(id: "canvas:fixture:course:fall", name: "Fall fixture", code: "FALL", term: fall)
        let springCourse = Course(id: "canvas:fixture:course:spring", name: "Spring fixture", code: "SPRING", term: spring)
        model.archive.courses += [fallCourse, springCourse]
        model.discoveredCanvasCourses = [fallCourse, springCourse]
        model.archive.events += [AcademicEvent(id: "scope-fall", courseID: fallCourse.id, title: "Fall deadline", date: .now, state: .pending), AcademicEvent(id: "scope-spring", courseID: springCourse.id, title: "Spring deadline", date: .now, state: .pending)]
        model.archive.sources += [SourceDocument(id: "source-fall", courseID: fallCourse.id, title: "Fall syllabus", text: ""), SourceDocument(id: "source-spring", courseID: springCourse.id, title: "Spring syllabus", text: "")]
        model.archive.canvasSelection = nil
        check(!model.scopedEvents.contains { $0.id.hasPrefix("scope-") }, "Legacy Canvas data waits for course selection")
        model.prepareCourseSelection(termID: fall.id)
        model.applyCanvasSelection(sync: false)
        check(model.scopedEvents.contains { $0.id == "scope-fall" } && !model.scopedEvents.contains { $0.id == "scope-spring" }, "Semester selection scopes events")
        check(model.scopedSources.contains { $0.id == "source-fall" } && !model.scopedSources.contains { $0.id == "source-spring" }, "Semester selection scopes sources")
        model.page = .review
        check(model.events.contains { $0.id == "scope-fall" } && !model.events.contains { $0.id == "scope-spring" }, "Review respects semester selection")
        model.prepareCourseSelection(termID: spring.id)
        model.applyCanvasSelection(sync: false)
        check(model.scopedEvents.contains { $0.id == "scope-spring" } && !model.scopedEvents.contains { $0.id == "scope-fall" }
              && model.archive.events.contains { $0.id == "scope-fall" }, "Switching semesters preserves history")
        guard !model.busy, !model.isDemo, let outOfScope = model.archive.events.first(where: { $0.id == "scope-fall" }) else {
            fail("Out-of-scope Calendar check requires an idle, non-demo fixture"); return
        }
        let priorNotice = model.notice, priorError = model.error
        model.resolveCalendar(outOfScope)
        // The synchronous scope guard must return before scheduling any task
        // that could enter EventKit. This check never needs calendar permission.
        check(!model.busy && model.notice == priorNotice && model.error == priorError,
              "Calendar conflict resolution ignores events outside the selected scope")
        do { let restored = try model.store.load(); check(restored.canvasSelection == model.archive.canvasSelection, "Course selection survives reload") } catch { fail(error.localizedDescription) }
        Snapshot.log("SELFTEST complete")
        NSApp.terminate(nil)
    }
    static func fail(_ message: String) { Snapshot.log("FAIL \(message)"); exit(1) }
}
