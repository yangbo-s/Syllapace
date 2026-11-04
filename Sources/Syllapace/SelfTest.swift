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
        Snapshot.log("SELFTEST complete")
        NSApp.terminate(nil)
    }
    static func fail(_ message: String) { Snapshot.log("FAIL \(message)"); exit(1) }
}
