import Foundation
import SyllapaceKit

enum DemoData {
    static func make() -> AppArchive {
        var archive = AppArchive()
        archive.courses = [Course(id: "design", name: "Human–Computer Interaction", code: "05–391", color: 0), Course(id: "ml", name: "Introduction to Machine Learning", code: "10–301", color: 1), Course(id: "systems", name: "Computer Systems", code: "15–213", color: 2), Course(id: "personal", name: "Personal", code: "Personal", color: 3)]
        let day = Calendar.current.startOfDay(for: .now)
        func date(_ offset: Int, _ hour: Int = 23) -> Date { Calendar.current.date(byAdding: .hour, value: hour, to: Calendar.current.date(byAdding: .day, value: offset, to: day)!)! }
        archive.events = [
            AcademicEvent(id: "demo1", courseID: "design", title: "Research synthesis", kind: .project, date: date(0, 17), dateOnly: false, state: .approved, evidence: "Bring your research synthesis and three opportunity statements to the studio critique.", sourceURL: "https://canvas.example.edu"),
            AcademicEvent(id: "demo2", courseID: "ml", title: "Problem set 04 · Neural networks", date: date(1), dateOnly: false, state: .approved, evidence: "Problem set 04 is due before the end of the day."),
            AcademicEvent(id: "demo3", courseID: "systems", title: "Cache lab", kind: .project, date: date(2), dateOnly: false, state: .approved, evidence: "Cache lab submission deadline."),
            AcademicEvent(id: "demo4", courseID: "design", title: "Prototype walkthrough", kind: .presentation, date: date(4, 0), state: .approved, sourceID: "syllabus", evidence: "Week 11 — Prototype walkthrough. Present the key flow to your studio group."),
            AcademicEvent(id: "demo5", courseID: "ml", title: "Midterm review", kind: .exam, date: date(6, 0), state: .approved),
            AcademicEvent(id: "demo6", courseID: "design", title: "Final portfolio hand-in", kind: .project, date: date(14, 0), sourceID: "syllabus", evidence: "Final portfolio hand-in: submit the revised case study and project reflection. Date is tentative; confirm with your instructor."),
            AcademicEvent(id: "demo7", courseID: "ml", title: "Project proposal", kind: .project, date: date(7, 0), state: .conflict, sourceID: "ml-syllabus", evidence: "Project proposal — revised schedule moves the submission to the following week.", previousDate: date(7, 0), proposedDate: date(9, 0)),
            AcademicEvent(id: "demo8", courseID: "systems", title: "Final exam", kind: .exam, evidence: "Final exam date will be announced in class.")
        ]
        archive.sources = [SourceDocument(id: "syllabus", courseID: "design", title: "Course syllabus · Fall semester", text: "Human–Computer Interaction\n\nWeek 11 — Prototype walkthrough. Present the key flow to your studio group.\n\nFinal portfolio hand-in: submit the revised case study and project reflection.", hash: "demo"), SourceDocument(id: "ml-syllabus", courseID: "ml", title: "Project schedule", text: "Project proposal — revised schedule moves the submission to the following week.", hash: "demo2")]
        archive.lastSync = .now
        return archive
    }
}
