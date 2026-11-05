import Foundation
import SyllapaceKit

enum DemoData {
    static func make() -> AppArchive {
        var archive = AppArchive()
        archive.courses = [Course(id: "canvas:demo:course:design", name: "Human–Computer Interaction", code: "05–391", color: 0), Course(id: "canvas:demo:course:ml", name: "Introduction to Machine Learning", code: "10–301", color: 1), Course(id: "canvas:demo:course:systems", name: "Computer Systems", code: "15–213", color: 2), Course(id: "personal", name: "Personal", code: "Personal", color: 3)]
        let year = Calendar.current.component(.year, from: .now)
        let term = AcademicTerm(id: "demo:term:fall", name: "Fall \(year)", startAt: Calendar.current.date(from: DateComponents(year: year, month: 8, day: 20)), endAt: Calendar.current.date(from: DateComponents(year: year + 1, month: 1, day: 15)))
        for index in archive.courses.indices where archive.courses[index].isCanvas { archive.courses[index].term = term }
        archive.courses.append(Course(id: "canvas:demo:course:history", name: "Design history seminar", code: "History seminar", color: 1, term: AcademicTerm(id: "demo:term:spring", name: "Spring \(year)", startAt: Calendar.current.date(from: DateComponents(year: year, month: 1, day: 10)), endAt: Calendar.current.date(from: DateComponents(year: year, month: 5, day: 20)))))
        archive.courses.append(Course(id: "canvas:demo:course:portal", name: "Graduate student portal", code: "Student portal", color: 2, term: AcademicTerm(id: "demo:term:default", name: "Default Term")))
        archive.canvasSelection = CanvasSelection(termID: term.id, courseIDs: Set(archive.courses.filter { $0.term?.id == term.id }.map(\.id)))
        let day = Calendar.current.startOfDay(for: .now)
        func date(_ offset: Int, _ hour: Int = 23) -> Date { Calendar.current.date(byAdding: .hour, value: hour, to: Calendar.current.date(byAdding: .day, value: offset, to: day)!)! }
        archive.events = [
            AcademicEvent(id: "demo1", courseID: "canvas:demo:course:design", title: "Research synthesis", kind: .project, date: date(0, 17), dateOnly: false, state: .approved, evidence: "Bring your research synthesis and three opportunity statements to the studio critique.", sourceURL: "https://canvas.example.edu"),
            AcademicEvent(id: "demo2", courseID: "canvas:demo:course:ml", title: "Problem set 04 · Neural networks", date: date(1), dateOnly: false, state: .approved, evidence: "Problem set 04 is due before the end of the day."),
            AcademicEvent(id: "demo3", courseID: "canvas:demo:course:systems", title: "Cache lab", kind: .project, date: date(2), dateOnly: false, state: .approved, evidence: "Cache lab submission deadline."),
            AcademicEvent(id: "demo4", courseID: "canvas:demo:course:design", title: "Prototype walkthrough", kind: .presentation, date: date(4, 0), state: .approved, sourceID: "syllabus", evidence: "Week 11 — Prototype walkthrough. Present the key flow to your studio group."),
            AcademicEvent(id: "demo5", courseID: "canvas:demo:course:ml", title: "Midterm exam", kind: .exam, date: date(6, 0), state: .approved),
            AcademicEvent(id: "demo6", courseID: "canvas:demo:course:design", title: "Final portfolio hand-in", kind: .project, date: date(14, 0), sourceID: "syllabus", evidence: "Final portfolio hand-in: submit the revised case study and project reflection. Date is tentative; confirm with your instructor."),
            AcademicEvent(id: "demo7", courseID: "canvas:demo:course:ml", title: "Project proposal", kind: .project, date: date(7, 0), state: .conflict, sourceID: "ml-syllabus", evidence: "Project proposal — revised schedule moves the submission to the following week.", previousDate: date(7, 0), proposedDate: date(9, 0)),
            AcademicEvent(id: "demo8", courseID: "canvas:demo:course:systems", title: "Final exam", kind: .exam, evidence: "Final exam date will be announced in class.")
        ]
        archive.sources = [SourceDocument(id: "syllabus", courseID: "canvas:demo:course:design", title: "Course syllabus · Fall semester", text: "Human–Computer Interaction\n\nWeek 11 — Prototype walkthrough. Present the key flow to your studio group.\n\nFinal portfolio hand-in: submit the revised case study and project reflection.", hash: "demo"), SourceDocument(id: "ml-syllabus", courseID: "canvas:demo:course:ml", title: "Project schedule", text: "Project proposal — revised schedule moves the submission to the following week.", hash: "demo2")]
        archive.events.append(AcademicEvent(id: "demo-session", courseID: "canvas:demo:course:design", title: "Studio critique", kind: .session, date: date(1, 10), dateOnly: false, state: .approved, evidence: "Studio critique runs from 10:00 to 11:30 in Studio 204.", endsAt: date(1, 10).addingTimeInterval(90 * 60), location: "Studio 204"))
        archive.events.append(AcademicEvent(id: "demo-quiz", courseID: "canvas:demo:course:ml", title: "Neural networks quiz", kind: .quiz, date: date(3, 16), dateOnly: false, state: .approved, evidence: "The quiz is held in class on the scheduled date.", submission: SubmissionStatus(state: "unsubmitted")))
        archive.events.append(AcademicEvent(id: "demo-history", courseID: "canvas:demo:course:history", title: "Archived seminar essay", date: date(-180), state: .pending))
        archive.sources.append(SourceDocument(id: "demo-announcement", courseID: "canvas:demo:course:design", title: "Week 11 schedule", text: "The studio critique is now in Studio 204. See the weekly schedule for preparation details.", hash: "demo-announcement", kind: .announcement, links: [SourceLink(url: "https://docs.google.com/spreadsheets/d/example/edit#gid=0", title: "Weekly schedule", kind: "external")]))
        archive.courseAppearances = ["canvas:demo:course:design": CourseAppearance(mode: .custom, alias: "Interaction Design")]
        archive.academicCalendars = [AcademicCalendarSubscription(id: "demo-school", name: "CMU Academic Calendar", url: AcademicCalendarPreset.cmu.feedURL, termID: term.id)]
        archive.events.append(AcademicEvent(id: "demo-school-event", courseID: "", title: "Registration opens", kind: .academic, date: date(5, 0), state: .approved, academicCalendarID: "demo-school"))
        archive.events[0].progress = .doing
        archive.events[0].plannedStart = date(-2, 9)
        archive.events[2].progress = .doing
        archive.events[2].releasedAt = date(-1, 9)
        archive.events[2].releaseDateOnly = false
        archive.events[6].userEdited = true
        archive.events.append(AcademicEvent(id: "demo-done", courseID: "canvas:demo:course:ml", title: "Problem set 03 · Optimization", date: date(-2), dateOnly: false, state: .approved, completed: true))
        for offset in [0, 2, 5, 7] {
            archive.events.append(AcademicEvent(id: "demo-lecture-\(offset)", courseID: "canvas:demo:course:systems", title: "Lecture · Virtual memory", kind: .session, date: date(offset, 11), dateOnly: false, state: .approved, evidence: "Lecture 11:00–12:20, Gates 4401.", endsAt: date(offset, 11).addingTimeInterval(80 * 60), location: "Gates 4401"))
        }
        for offset in [1, 8] {
            archive.events.append(AcademicEvent(id: "demo-recitation-\(offset)", courseID: "canvas:demo:course:ml", title: "Recitation · Backpropagation", kind: .session, date: date(offset, 14), dateOnly: false, state: .approved, evidence: "Recitation 14:00–14:50, GHC 4303.", endsAt: date(offset, 14).addingTimeInterval(50 * 60), location: "GHC 4303"))
        }
        archive.lastSync = .now
        return archive
    }
}
