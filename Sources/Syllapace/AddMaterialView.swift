import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import SyllapaceKit

@Observable final class MaterialImportDraft {
    var mode = 0
    var files: [URL] = []
    var text = ""
    var url = ""
    var intent = ""
    var useAI = true
    var owner = "personal"
    var year = Calendar.current.component(.year, from: Date.now)
    var zone = TimeZone.current.identifier
    var sources: [SourceDocument] = []
    var candidates: [AcademicEvent] = []
    var selected: Set<String> = []
    var baseline: [AcademicEvent] = []
    var sourceBaseline: [SourceDocument] = []
    var processing = false
    var hasPreview = false
    var progress = ""
    var errors: [String] = []
    var records: [String: SourceCurationRecord] = [:]
    var task: Task<Void, Never>?
    var parsedModelIdentity: String?
    var parsedSelection: CanvasSelection?
    var hasParseContext = false
    private static func hash(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    var hasInput: Bool { mode == 0 ? !files.isEmpty : mode == 1 ? !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func addFiles(_ urls: [URL]) { files = Array((files + urls).reduce(into: [URL]()) { if !$0.contains($1) { $0.append($1) } }.prefix(10)) }
    func parse(model: AppModel, onOrganized: (() -> Void)? = nil) {
        guard !processing, hasInput else { return }
        model.cancelCuration()
        hasParseContext = true; parsedSelection = model.archive.canvasSelection
        parsedModelIdentity = useAI ? model.curationModelIdentity : nil
        let mode = self.mode, files = self.files, text = self.text, url = self.url, year = self.year, zone = self.zone, intent = self.intent
        processing = true; errors = []; records = [:]; sources = []; candidates = []; selected = []; baseline = model.archive.events; sourceBaseline = model.archive.sources
        let courseID = owner.hasPrefix("calendar:") ? "" : owner
        let calendarID = owner.hasPrefix("calendar:") ? String(owner.dropFirst(9)) : nil
        let ai = useAI, endpoint = model.modelEndpoint, name = model.modelName, account = model.modelCredentialAccount
        let provider = model.modelProvider, workspace = model.modelWorkspaceID
        task = Task {
            defer { processing = false; task = nil }
            do {
                guard TimeZone(identifier: zone) != nil else { throw AppError.message(L10n.string("Choose a valid time zone.")) }
                guard intent.count <= 2000 else { throw AppError.message(L10n.string("Keep instructions under 2,000 characters.")) }
                var key: String?
                if ai {
                    guard !model.isDemo else { throw AppError.message(L10n.string("AI requests are disabled in demo mode.")) }
                    key = try await CredentialStore.readAsync(account)
                    guard let key, !key.isEmpty, !name.isEmpty else { throw AppError.message(L10n.string("Configure your model and API key in Settings first.")) }
                }
                let count = mode == 0 ? files.count : 1
                for index in 0..<count {
                    try Task.checkCancellation()
                    guard !ai || (model.modelEndpoint == endpoint && model.modelName == name && model.modelProvider == provider && model.modelWorkspaceID == workspace) else { throw AppError.message(L10n.string("Model settings changed. Preview the materials again.")) }
                    progress = L10n.format("Reading material %ld of %ld…", index + 1, count)
                    do {
                        var source: SourceDocument
                        if mode == 0 { source = try await DocumentReader.read(url: files[index], courseID: courseID) }
                        else if mode == 1 {
                            guard text.utf8.count <= DocumentReader.maxTextBytes else { throw DocumentError.tooLarge }
                            source = SourceDocument(courseID: courseID, title: L10n.string("Pasted text"), text: text, hash: Self.hash(text), kind: .external)
                            source.id = "text:" + Self.hash(courseID + "|" + (calendarID ?? "") + "|" + text)
                        } else { source = try await PublicDocumentClient().read(link: SourceLink(url: url.trimmingCharacters(in: .whitespacesAndNewlines), title: ""), courseID: courseID) }
                        source.academicCalendarID = calendarID
                        source.curationYear = year; source.curationTimeZone = zone; source.curationIntent = intent
                        source.localOnly = !ai
                        if let calendarID, mode != 1 { source.id += ":calendar:" + calendarID }
                        var events: [AcademicEvent]
                        var record: SourceCurationRecord?
                        let fingerprint = model.curationFingerprint(source)
                        if let key {
                            progress = L10n.format("Extracting with %@…", provider.displayName)
                            let window = model.curationWindow(for: source)
                            let result = try await LLMClient(endpoint: endpoint, key: key, model: name, provider: provider, workspaceID: workspace.isEmpty ? nil : workspace).curate(source: source, year: year, timeZone: zone, intent: intent, termStart: window.start, termEnd: window.end)
                            events = result.events
                            record = SourceCurationRecord(fingerprint: fingerprint, eventCount: result.events.count, issues: result.issues)
                        } else { events = RuleExtractor.extract(source: source, year: year, timeZone: zone) }
                        try Task.checkCancellation()
                        guard !ai || (model.modelEndpoint == endpoint && model.modelName == name && model.modelProvider == provider && model.modelWorkspaceID == workspace) else { throw AppError.message(L10n.string("Model settings changed. Preview the materials again.")) }
                        for i in events.indices { events[i].academicCalendarID = calendarID }
                        guard !ai || model.curationFingerprint(source) == fingerprint else { throw AppError.message(L10n.string("Course settings changed. Organize these materials again.")) }
                        if let record { records[source.id] = record }
                        sources.append(source); candidates += events
                    } catch is CancellationError { throw CancellationError() }
                    catch { errors.append((mode == 0 ? files[index].lastPathComponent + ": " : "") + error.localizedDescription) }
                }
                let incomingIDs = Set(candidates.map(\.id))
                let merged = Reconciler.merge(existing: baseline, incoming: candidates)
                candidates = merged.filter { event in incomingIDs.contains(event.id) || baseline.first { $0.id == event.id }.map { $0 != event } == true }
                selected = Set(candidates.filter { $0.date != nil && $0.state != .conflict && $0.state != .rejected }.map(\.id))
                hasPreview = !sources.isEmpty
                if errors.isEmpty && hasPreview { onOrganized?() }
            } catch is CancellationError { progress = "" }
            catch { errors.append(error.localizedDescription) }
        }
    }
    func commit(model: AppModel) -> Bool {
        guard !hasParseContext || (parsedSelection == model.archive.canvasSelection && (parsedModelIdentity == nil || parsedModelIdentity == model.curationModelIdentity)) else {
            errors = [L10n.string("Course or model settings changed. Organize these materials again.")]; return false
        }
        guard !model.busy, baseline == model.archive.events, sourceBaseline == model.archive.sources else { errors = [L10n.string("Your timeline changed. Go back and preview again before importing.")]; return false }
        let events = candidates.filter { selected.contains($0.id) || $0.state == .conflict }.map { event in
            var result = event
            if result.date != nil && result.state != .conflict { result.state = .approved; result.wasApproved = true }
            return result
        }
        guard model.commitImport(sources: sources, candidates: events, records: records) else { errors = [model.error ?? L10n.string("Could not save import. Try again.")]; model.error = nil; return false }
        return true
    }
}

struct ImportSheet: View {
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    @Bindable var model: AppModel
    @State private var draft = MaterialImportDraft()
    @State private var editing: AcademicEvent?
    @State private var newCourse = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let _ = languagePreference
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L10n.string(draft.hasPreview ? "Organized dates" : "Add material")).font(.title2.weight(.semibold))
                Spacer()
                if draft.processing { ProgressView().controlSize(.small) }
            }
            if draft.hasPreview { preview } else { ScrollView { input }.scrollBounceBehavior(.basedOnSize) }
            if !draft.errors.isEmpty {
                ScrollView { Text(draft.errors.joined(separator: "\n")).font(.caption).foregroundStyle(Palette.warning).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 72)
            }
            HStack(spacing: 12) {
                if draft.processing { Text(draft.progress).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                else if draft.hasPreview { Button(L10n.string("Back")) { draft.hasPreview = false } }
                Spacer()
                Button(L10n.string("Cancel")) { draft.task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                if draft.hasPreview {
                    Button(draft.selected.isEmpty ? L10n.string("Save materials") : L10n.format("Add %ld events", draft.selected.count)) { if draft.commit(model: model) { dismiss() } }
                        .buttonStyle(.borderedProminent).tint(Palette.actionAccent).keyboardShortcut(.defaultAction)
                } else {
                    Button(L10n.string("Organize & add")) { draft.parse(model: model) { if draft.commit(model: model) { dismiss() } } }.disabled(!draft.hasInput || draft.processing)
                        .buttonStyle(.borderedProminent).tint(Palette.actionAccent).keyboardShortcut(.defaultAction)
                }
            }
        }.padding(28).frame(width: 660, height: sheetHeight).gridArea("material-import", inset: 28).background(Palette.canvas).background(CalmFocus()).tint(Palette.accent)
        .onAppear {
            draft.owner = model.importCalendarID.map { "calendar:" + $0 } ?? model.importCourseID
            if !model.scopedCourses.contains(where: { $0.id == draft.owner }), model.importCalendarID == nil { draft.owner = model.scopedCourses.first?.id ?? "personal" }
            draft.year = model.importYear; draft.useAI = !model.modelName.isEmpty && !model.isDemo
            if !model.importURL.isEmpty { draft.url = model.importURL; draft.mode = 2 }
            model.importURL = ""; model.importCalendarID = nil
            if model.isDemo, let fixture = model.importFixtureMode {
                draft.mode = min(fixture, 2)
                draft.text = "Project proposal due November 18, 2026. Final presentation December 9, 2026."
                draft.url = "https://www.cmu.edu/hub/calendar/"
                draft.intent = "Only Fall 2026 deadlines and exams"
                if fixture == 3 {
                    draft.hasPreview = true
                    draft.sources = [SourceDocument(id: "preview-demo", courseID: "personal", title: "Fall schedule", text: draft.text)]
                    draft.candidates = [AcademicEvent(id: "preview-proposal", courseID: "personal", title: "Project proposal", kind: .project, date: Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18)), evidence: "Project proposal due November 18, 2026."), AcademicEvent(id: "preview-talk", courseID: "personal", title: "Final presentation", kind: .presentation, date: Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 9)), evidence: "Final presentation December 9, 2026.")]
                    draft.selected = Set(draft.candidates.map(\.id)); draft.baseline = model.archive.events; draft.sourceBaseline = model.archive.sources
                }
            }
        }
        .onDisappear { draft.task?.cancel() }
        .sheet(item: $editing) { event in
            EventEditor(model: model, original: event, onSave: { changed in
                if let index = draft.candidates.firstIndex(where: { $0.id == changed.id }) { draft.candidates[index] = changed; draft.selected.insert(changed.id) }
            })
        }
    }
    private var sheetHeight: CGFloat {
        if draft.hasPreview { return CGFloat(min(628, max(360, 184 + draft.candidates.count * 108))) }
        return draft.mode == 2 ? 484 : 580
    }
    private var input: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(L10n.string("Input"), selection: $draft.mode) {
                Text(L10n.string("Files")).tag(0); Text(L10n.string("Text")).tag(1); Text(L10n.string("Link")).tag(2)
            }.id("material-input-\(languagePreference)").pickerStyle(.segmented).labelsHidden().tint(Palette.actionAccent)
            Group {
                if draft.mode == 0 {
                    VStack(spacing: 12) {
                        if draft.files.isEmpty {
                            Image(systemName: "doc.on.doc").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                            Text(L10n.string("Drop course materials here")).font(.headline)
                        } else {
                            ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(draft.files, id: \.self) { url in
                                HStack { Image(systemName: "doc.text").foregroundStyle(.secondary); Text(url.lastPathComponent).lineLimit(1); Spacer(); Button { draft.files.removeAll { $0 == url } } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help(L10n.string("Remove file")) }
                            } } }
                        }
                        Button(L10n.string("Choose files…")) { chooseFiles() }
                        Text(L10n.string("PDF, DOCX, XLSX, CSV, Markdown or text · up to 10 files")).font(.caption).foregroundStyle(.secondary)
                    }.padding(20).frame(maxWidth: .infinity).frame(height: 168).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                        .dropDestination(for: URL.self) { urls, _ in draft.addFiles(urls.filter(\.isFileURL)); return true }
                } else if draft.mode == 1 {
                    TextEditor(text: $draft.text).font(.body).padding(8).frame(height: 208).overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator)).accessibilityLabel(L10n.string("Text to parse"))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("https://…", text: $draft.url).textFieldStyle(.roundedBorder).accessibilityLabel(L10n.string("Material link"))
                        Text(L10n.string("Public pages, PDF links and published Google Sheets. For sign-in-only pages, paste the text or import an exported file.")).font(.callout).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }.frame(height: 104)
                }
            }
            HStack(spacing: 16) {
                Picker(L10n.string("Add to"), selection: $draft.owner) {
                    ForEach(model.scopedCourses) { Text(model.courseTitle($0)).tag($0.id) }
                    ForEach((model.archive.academicCalendars ?? []).filter(\.enabled)) { Text($0.name).tag("calendar:" + $0.id) }
                }
                Stepper(L10n.format("Year: %@", String(draft.year)), value: $draft.year, in: 2020...2100).fixedSize()
            }
            HStack { TextField(L10n.string("Or create a course"), text: $newCourse); Button(L10n.string("Add")) { draft.owner = model.addCourse(name: newCourse.trimmingCharacters(in: .whitespacesAndNewlines)); newCourse = "" }.disabled(newCourse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            TextField(L10n.string("Instructions, e.g. only deadlines for Fall 2026"), text: $draft.intent).textFieldStyle(.roundedBorder)
            HStack {
                Toggle(L10n.string("Use AI"), isOn: $draft.useAI)
                if draft.useAI { Text(model.modelProvider.displayName + " · " + model.modelName).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                TextField(L10n.string("Time zone"), text: $draft.zone).frame(width: 184)
            }
            Text(L10n.string(draft.useAI ? "Organize sends these materials to your selected model. Relevant dates are added automatically; you can undo the import." : "Local parsing keeps explicit actionable dates. Connect a model for semantic filtering and recurring schedules.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.disabled(draft.processing)
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text((draft.sources.count == 1 ? L10n.string("1 material") : L10n.format("%ld materials", draft.sources.count)) + " · " + L10n.format("%ld candidate events", draft.candidates.count)).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.string("Select dated")) { draft.selected = Set(draft.candidates.filter { $0.date != nil && $0.state != .conflict && $0.state != .rejected }.map(\.id)) }.buttonStyle(.borderless)
                Button(L10n.string("Clear")) { draft.selected = [] }.buttonStyle(.borderless)
            }.font(.caption)
            if draft.candidates.isEmpty {
                ContentUnavailableView(L10n.string("No dates found"), systemImage: "calendar.badge.exclamationmark", description: Text(L10n.string("Save the materials for reference, or go back to use AI or provide more context."))).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(draft.candidates) { event in
                            HStack(alignment: .top, spacing: 12) {
                                Toggle(isOn: Binding(get: { draft.selected.contains(event.id) }, set: { if $0 { draft.selected.insert(event.id) } else { draft.selected.remove(event.id) } })) { EmptyView() }.labelsHidden().toggleStyle(.checkbox).tint(Palette.actionAccent).disabled(event.state == .conflict || event.state == .rejected).padding(.top, 4)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(event.title).fontWeight(.medium)
                                    Text((event.date.map { L10n.date($0, dateOnly: event.dateOnly) } ?? L10n.string("Needs a date")) + " · " + event.kind.localizedName).font(.caption).foregroundStyle(.secondary)
                                    Text(event.evidence).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                                    if event.state == .conflict { Text(L10n.string("Review this change before adding it.")).font(.caption).foregroundStyle(Palette.warning) }
                                }
                                Spacer(minLength: 0)
                                Button(L10n.string("Edit")) { editing = event }.buttonStyle(.borderless)
                            }.padding(.vertical, 16)
                            Divider()
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["pdf", "docx", "txt", "md", "html", "xlsx", "csv"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { draft.addFiles(panel.urls) }
    }
}
