import SwiftUI
import SyllapaceKit

struct EventEditor: View {
    @Bindable var model: AppModel
    let original: AcademicEvent
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date.now
    @State private var dateOnly = true
    @State private var courseID = ""
    @State private var kind = EventKind.assignment
    @State private var cancelConfirm = false
    @FocusState private var titleFocused: Bool
    @State private var chosenZone = TimeZone.current.identifier
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(original.state == .conflict ? "Review schedule change" : original.title.isEmpty ? "New event" : "Edit event").font(.title2.weight(.semibold)).gridProbe("editor-title", area: "event-editor")
            Form {
                TextField("Title", text: $title).focused($titleFocused)
                Picker("Course", selection: $courseID) { ForEach(model.archive.courses) { Text($0.name).tag($0.id) } }
                Picker("Type", selection: $kind) { ForEach(EventKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Toggle("Date only", isOn: $dateOnly)
                DatePicker("When", selection: $date, displayedComponents: dateOnly ? [.date] : [.date, .hourAndMinute])
                if !dateOnly { Text("Time zone: \(original.timeZone)").font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped).environment(\.timeZone, TimeZone(identifier: chosenZone) ?? .current).gridProbe("editor-form", area: "event-editor")
            if let proposed = original.proposedDate {
                HStack { Text("New source date: \(proposed.formatted(date: .abbreviated, time: .shortened))").font(.caption); Spacer(); Button("Use new date") { date = proposed; dateOnly = original.proposedDateOnly ?? dateOnly; chosenZone = original.proposedTimeZone ?? chosenZone } }.gridProbe("editor-proposal", area: "event-editor")
            }
            HStack {
                if !original.title.isEmpty { Button("Cancel event", role: .destructive) { cancelConfirm = true }.buttonStyle(.borderless) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save & confirm") {
                    var event = original; event.title = title.trimmingCharacters(in: .whitespacesAndNewlines); event.date = date; event.dateOnly = dateOnly; event.courseID = courseID; event.kind = kind; event.state = .approved; event.wasApproved = true; event.userEdited = true; event.revision += 1; event.proposedDate = nil; event.proposedDateOnly = nil; event.proposedTimeZone = nil; event.timeZone = chosenZone
                    model.update(event); dismiss()
                }.buttonStyle(.borderedProminent).tint(Palette.actionAccent).keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.gridProbe("editor-actions", area: "event-editor")
        }.padding(28).frame(width: 480).gridArea("event-editor", inset: 28).background(CalmFocus(enabled: !original.title.isEmpty))
        .onAppear { title = original.title; date = original.date ?? .now; dateOnly = original.dateOnly; courseID = original.courseID; kind = original.kind; chosenZone = original.timeZone; titleFocused = original.title.isEmpty }
        .confirmationDialog("Cancel this event?", isPresented: $cancelConfirm) { Button("Cancel event", role: .destructive) { model.reject(original); dismiss() } } message: { Text("It will leave your timeline and be removed from the connected calendar on the next sync, if it has not been edited there.") }
    }
}
struct ImportSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var newCourse = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Import a syllabus", systemImage: "doc.badge.plus").font(.title2.weight(.semibold)).gridProbe("import-title", area: "import-sheet")
            Text("Choose the course and year to give dates their context.").foregroundStyle(.secondary).gridProbe("import-context", area: "import-sheet")
            Form {
                Picker("Course", selection: $model.importCourseID) { ForEach(model.archive.courses) { Text($0.name).tag($0.id) } }
                HStack { TextField("Or create a course", text: $newCourse); Button("Add") { model.importCourseID = model.addCourse(name: newCourse); newCourse = "" }.disabled(newCourse.trimmingCharacters(in: .whitespaces).isEmpty) }
                Stepper("Academic year: \(String(model.importYear))", value: $model.importYear, in: 2020...2100)
            }.gridProbe("import-form", area: "import-sheet")
            Text("PDF, DOCX, Markdown or text. Files are processed locally; AI extraction is a separate action.").font(.caption).foregroundStyle(.secondary).gridProbe("import-formats", area: "import-sheet")
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Choose document…") { dismiss(); model.chooseDocument() }.buttonStyle(.borderedProminent).tint(Palette.actionAccent).keyboardShortcut(.defaultAction) }.gridProbe("import-actions", area: "import-sheet")
        }.padding(28).frame(width: 460).gridArea("import-sheet", inset: 28).background(CalmFocus()).onAppear { if !model.archive.courses.contains(where: { $0.id == model.importCourseID }) { model.importCourseID = model.archive.courses.first!.id } }
    }
}
struct SourcesView: View {
    @Bindable var model: AppModel
    @State private var selected: SourceDocument?
    @State private var aiSource: SourceDocument?
    var body: some View {
        Group {
            if model.archive.sources.isEmpty && model.remoteFiles.isEmpty { EmptyViewState(title: "Start with your syllabus", symbol: "doc.text.magnifyingglass", detail: "Import a document or sync Canvas to discover course materials.") }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.archive.sources.filter { model.courseFilter == nil || $0.courseID == model.courseFilter }) { source in
                            HStack(spacing: 16) {
                                Image(systemName: "doc.text").font(.title2.weight(.light)).foregroundStyle(Palette.accent)
                                VStack(alignment: .leading, spacing: 8) { Text(source.title).fontWeight(.medium); Text(model.course(source.courseID).name).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button("Read") { selected = source }
                                Button { aiSource = source } label: { Label("Extract", systemImage: "sparkles") }.disabled(model.busy).help("Extract candidates using your configured AI model")
                            }.padding(.vertical, 16).gridProbe("source-row-\(source.id)", area: "sources")
                            Divider().gridProbe("source-divider-\(source.id)", area: "sources")
                        }
                        if !model.remoteFiles.isEmpty {
                            Text("Discovered in Canvas").font(.headline).padding(.top, 16).gridProbe("discovered-heading", area: "sources")
                            ForEach(model.remoteFiles, id: \.id) { file in
                                HStack { Label(file.title, systemImage: "doc"); Spacer(); Button("Import") { model.fetch(file) }.disabled(model.busy) }.padding(.vertical, 8).gridProbe("remote-file-\(file.id)", area: "sources")
                            }
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 28).gridArea("sources", inset: 28)
                }
            }
        }
        .sheet(item: $selected) { source in SourceReader(source: source) }
        .confirmationDialog("Send this document to your model?", isPresented: Binding(get: { aiSource != nil }, set: { if !$0 { aiSource = nil } })) {
            Button("Extract candidates") { if let source = aiSource { model.extractAI(source) }; aiSource = nil }
            Button("Cancel", role: .cancel) { aiSource = nil }
        } message: { Text("The text of ‘\(aiSource?.title ?? "")’ will be sent directly to \(model.modelEndpoint) using \(model.modelName.isEmpty ? "your configured model" : model.modelName). Provider usage charges may apply. Canvas credentials are never included.") }
    }
}
struct SourceReader: View {
    let source: SourceDocument
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(source.title).font(.title2); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.gridProbe("source-reader-title", area: "source-reader")
            ScrollView { Text(source.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).lineSpacing(5) }.gridProbe("source-reader-text", area: "source-reader")
        }.padding(28).frame(width: 640, height: 560).gridArea("source-reader", inset: 28)
    }
}
