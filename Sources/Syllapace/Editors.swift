import SwiftUI
import SyllapaceKit

struct EventEditor: View {
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    @Bindable var model: AppModel
    let original: AcademicEvent
    var onSave: ((AcademicEvent) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date.now
    @State private var dateOnly = true
    @State private var courseID = ""
    @State private var kind = EventKind.assignment
    @State private var cancelConfirm = false
    @FocusState private var titleFocused: Bool
    @State private var hasEnd = false
    @State private var hasRelease = false
    @State private var releaseDate = Date.now
    @State private var releaseDateOnly = true
    @State private var endDate = Date.now
    @State private var location = ""
    @State private var chosenZone = TimeZone.current.identifier
    @State private var saveError: String?
    private var initialDraft: AcademicEvent { model.projectedEvents.first { $0.id == original.id } ?? original }
    var body: some View {
        // Redraw translated content without replacing the view or its draft state.
        let _ = languagePreference
        VStack(alignment: .leading, spacing: 24) {
            Text(initialDraft.state == .conflict ? L10n.string("Review schedule change") : original.title.isEmpty ? L10n.string("New event") : L10n.string("Edit event")).font(.title2.weight(.semibold)).gridProbe("editor-title", area: "event-editor")
            Form {
                TextField(L10n.string("Title"), text: $title).focused($titleFocused)
                // Native menu controls cache their option labels. Rebuild just
                // the control; all selections and drafts remain in this view.
                if original.academicCalendarID != nil { LabeledContent(L10n.string("Academic calendar"), value: model.eventOwnerName(original)) } else { Picker(L10n.string("Course"), selection: $courseID) { ForEach(model.scopedCourses) { Text($0.localizedName).tag($0.id) } }.id("event-course-\(languagePreference)") }
                Picker(L10n.string("Type"), selection: $kind) { ForEach(EventKind.allCases.filter { original.academicCalendarID != nil || ![.other, .academic, .holiday].contains($0) }, id: \.self) { Text($0.localizedName).tag($0) } }.id("event-kind-\(languagePreference)")
                Toggle(L10n.string("Date only"), isOn: $dateOnly)
                DatePicker(L10n.string(isDeadline ? "Due" : "When"), selection: $date, displayedComponents: dateOnly ? [.date] : [.date, .hourAndMinute])
                    .environment(\.locale, L10n.locale).id("import-course-\(languagePreference)")
                if isDeadline {
                    Toggle(L10n.string("Release date"), isOn: $hasRelease)
                    if hasRelease {
                        DatePicker(L10n.string("Available from"), selection: $releaseDate, in: ...date, displayedComponents: releaseDateOnly ? [.date] : [.date, .hourAndMinute])
                        Toggle(L10n.string("Release date only"), isOn: $releaseDateOnly)
                    }
                }
                Group {
                    Toggle(L10n.string("End time"), isOn: $hasEnd)
                    if hasEnd {
                        DatePicker(L10n.string(dateOnly ? "End date (exclusive)" : "Ends"), selection: $endDate, in: date..., displayedComponents: dateOnly ? [.date] : [.date, .hourAndMinute])
                            .environment(\.locale, L10n.locale).id("event-end-\(languagePreference)")
                    }
                }
                TextField(L10n.string("Location"), text: $location)
                if !dateOnly { Text(L10n.format("Time zone: %@", chosenZone)).font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped).environment(\.timeZone, TimeZone(identifier: chosenZone) ?? .current).gridProbe("editor-form", area: "event-editor")
            let evidence = model.projectedEvents.first { $0.id == original.id } ?? original
            let sourceIDs = Set(([evidence.sourceID].compactMap { $0 }) + (evidence.relatedSourceIDs ?? []))
            let sources = model.archive.sources.filter { sourceIDs.contains($0.id) }
            if !sources.isEmpty {
                Menu(L10n.string("Sources")) {
                    ForEach(sources) { source in
                        Button(source.title) { model.readingSource = source }
                    }
                }.menuStyle(.borderlessButton).fixedSize()
            }
            if let proposed = evidence.proposedDate {
                HStack { Text(L10n.format("New source date: %@", L10n.date(proposed, dateOnly: evidence.proposedDateOnly ?? evidence.dateOnly))).font(.caption); Spacer(); Button(L10n.string("Use new date")) { date = proposed; dateOnly = evidence.proposedDateOnly ?? dateOnly; chosenZone = evidence.proposedTimeZone ?? chosenZone; hasEnd = evidence.proposedEndsAt != nil; endDate = evidence.proposedEndsAt ?? date } }.gridProbe("editor-proposal", area: "event-editor")
            }
            HStack {
                if !original.title.isEmpty && onSave == nil { Button(L10n.string("Cancel event"), role: .destructive) { cancelConfirm = true }.buttonStyle(.borderless) }
                Spacer()
                Button(L10n.string("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.string("Save & confirm")) {
                    var event = original; event.title = title.trimmingCharacters(in: .whitespacesAndNewlines); event.date = date; event.dateOnly = dateOnly; event.courseID = courseID; event.kind = kind; event.state = .approved; event.wasApproved = true; event.userEdited = true; event.revision += 1; event.proposedDate = nil; event.proposedDateOnly = nil; event.proposedTimeZone = nil; event.timeZone = chosenZone
                    event.endsAt = hasEnd ? endDate : nil; event.location = location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location.trimmingCharacters(in: .whitespacesAndNewlines); event.proposedEndsAt = nil
                    event.releasedAt = isDeadline && hasRelease ? releaseDate : nil
                    event.releaseDateOnly = event.releasedAt == nil ? nil : releaseDateOnly
                    if let onSave { onSave(event) }
                    else if !model.saveEditedEvent(event, replacing: original) {
                        saveError = model.error ?? L10n.string("Could not save changes. Try again."); model.error = nil
                        return
                    }
                    dismiss()
                }.buttonStyle(.borderedProminent).tint(Palette.actionAccent).keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (hasEnd && (dateOnly ? endDate <= date : endDate < date)) || (isDeadline && hasRelease && releaseAfterDue))
            }.gridProbe("editor-actions", area: "event-editor")
        }.padding(28).frame(width: 480).gridArea("event-editor", inset: 28).background(CalmFocus(enabled: !original.title.isEmpty))
        .onAppear { let draft = initialDraft; title = draft.title; date = draft.date ?? .now; dateOnly = draft.dateOnly; courseID = draft.courseID; kind = draft.kind; chosenZone = draft.timeZone; hasEnd = draft.endsAt != nil; endDate = draft.endsAt ?? date; location = draft.location ?? ""; titleFocused = original.title.isEmpty }
        .onAppear { let draft = initialDraft; hasRelease = draft.releasedAt != nil; releaseDate = draft.releasedAt ?? min(.now, draft.date ?? .now); releaseDateOnly = draft.releaseDateOnly ?? true }
        .sheet(item: $model.readingSource) { SourceReader(source: $0) }
        .alert(L10n.string("Could not save changes. Try again."), isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button(L10n.string("OK")) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .confirmationDialog(L10n.string("Cancel this event?"), isPresented: $cancelConfirm) { Button(L10n.string("Cancel event"), role: .destructive) {
            var cancelled = original; cancelled.state = .rejected
            if model.saveEditedEvent(cancelled, replacing: original) { dismiss() }
            else { saveError = model.error ?? L10n.string("Could not save changes. Try again."); model.error = nil }
        } } message: { Text(L10n.string("It will leave your timeline and be removed from the connected calendar on the next sync, if it has not been edited there.")) }
    }
    private var releaseAfterDue: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: chosenZone) ?? .current
        return (releaseDateOnly ? calendar.startOfDay(for: releaseDate) : releaseDate) > date
    }
    private var isDeadline: Bool { [.assignment, .project, .presentation].contains(kind) }
}
struct SourcesView: View {
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    @Bindable var model: AppModel
    var body: some View {
        // Redraw translated content without replacing the view or its draft state.
        let _ = languagePreference
        Group {
            if model.scopedSources.isEmpty && model.scopedRemoteFiles.isEmpty { EmptyViewState(title: L10n.string("Start with your syllabus"), symbol: "doc.text.magnifyingglass", detail: L10n.string("Import a document or sync Canvas to discover course materials.")) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.scopedSources.filter { model.courseFilter == nil || $0.courseID == model.courseFilter }) { source in
                            HStack(spacing: 16) {
                                Image(systemName: "doc.text").font(.title2.weight(.light)).foregroundStyle(Palette.accent)
                                VStack(alignment: .leading, spacing: 8) { Text(source.title).fontWeight(.medium); Text(model.sourceOwnerName(source)).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button(L10n.string("Read")) { model.readingSource = source }
                                Button { model.extractAI(source) } label: { Label(L10n.string("Organize"), systemImage: "sparkles") }.disabled(model.curationTask != nil || source.meetingSchedule != nil).help(L10n.string("Organize relevant dates with your selected model"))
                            }.padding(.vertical, 16).gridProbe("source-row-\(source.id)", area: "sources")
                            Divider().gridProbe("source-divider-\(source.id)", area: "sources")
                        }
                        if !model.scopedRemoteFiles.isEmpty {
                            Text(L10n.string("Discovered in Canvas")).font(.headline).padding(.top, 16).gridProbe("discovered-heading", area: "sources")
                            ForEach(model.scopedRemoteFiles, id: \.id) { file in
                                HStack { Label(file.title, systemImage: "doc"); Spacer(); Button(L10n.string("Import")) { model.fetch(file) }.disabled(model.busy) }.padding(.vertical, 8).gridProbe("remote-file-\(file.id)", area: "sources")
                            }
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 28).gridArea("sources", inset: 28)
                }
            }
        }
        .sheet(item: $model.readingSource) { source in SourceReader(source: source, onImport: { link in
            model.importCourseID = source.courseID; model.importCalendarID = source.academicCalendarID; model.importURL = link.url
            Task { try? await Task.sleep(for: .milliseconds(300)); model.showImport = true }
        }) }

    }
}
struct SourceReader: View {
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    let source: SourceDocument
    var onImport: ((SourceLink) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        // Redraw translated content without replacing the view or its draft state.
        let _ = languagePreference
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(source.title).font(.title2); Spacer(); Button(L10n.string("Done")) { dismiss() }.keyboardShortcut(.cancelAction) }.gridProbe("source-reader-title", area: "source-reader")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(source.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).lineSpacing(5)
                    if let links = source.links, !links.isEmpty {
                        Divider()
                        Text(L10n.string("Linked materials")).font(.headline)
                        ForEach(links) { link in
                            if let url = URL(string: link.url), url.scheme == "https", url.user == nil, url.password == nil {
                                HStack(alignment: .top, spacing: 12) {
                                    Link(destination: url) {
                                        Label(link.title.isEmpty ? (url.host ?? link.url) : link.title, systemImage: "arrow.up.right.square").multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 8)
                                    if onImport != nil, link.kind == "external" || url.host == "docs.google.com" {
                                        Button(L10n.string("Import link")) { dismiss(); onImport?(link) }
                                    }
                                }
                            }
                        }
                    }
                }
            }.gridProbe("source-reader-text", area: "source-reader")
        }.padding(28).frame(width: 640, height: 560).gridArea("source-reader", inset: 28)
    }
}
