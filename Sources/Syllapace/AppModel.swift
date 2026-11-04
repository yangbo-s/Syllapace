import AppKit
import Observation
import SyllapaceKit
import UniformTypeIdentifiers

@Observable final class AppModel {
    var archive = AppArchive()
    var page: AppPage = .today
    var selectedID: String?
    var courseFilter: String?
    var search = ""
    var busy = false
    var notice: String?
    var error: String?
    var editor: AcademicEvent?
    var showImport = false
    var importCourseID = "personal"
    var importYear = Calendar.current.component(.year, from: .now)
    var remoteFiles: [CanvasFile] = []
    var settingsTab = 3
    var canvasAutoSync = UserDefaults.standard.bool(forKey: "canvasAutoSync")
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    var calendarAutoSync = UserDefaults.standard.bool(forKey: "calendarAutoSync")
    @ObservationIgnored private var calendarTask: Task<Void, Never>?
    var canvasCredentialAccount: String { CredentialStore.canvasToken + ":" + canvasHost.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
    var modelCredentialAccount: String { CredentialStore.modelKey + ":" + modelEndpoint.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canvasHost = UserDefaults.standard.string(forKey: "canvasHost") ?? ""
    var modelEndpoint = UserDefaults.standard.string(forKey: "modelEndpoint") ?? "https://api.openai.com/v1"
    var modelName = UserDefaults.standard.string(forKey: "modelName") ?? ""
    let calendar = CalendarBridge()
    let isDemo: Bool
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored let store: ArchiveStore
    @ObservationIgnored var revealMain: () -> Void = {}
    @ObservationIgnored var panel: DesktopPanel?
    var selectedEvent: AcademicEvent? { archive.events.first { $0.id == selectedID } }
    var pendingCount: Int { archive.events.filter { $0.state == .pending || $0.state == .conflict }.count }
    var events: [AcademicEvent] {
        archive.events.filter { e in
            (courseFilter == nil || e.courseID == courseFilter) &&
            (search.isEmpty || e.title.localizedCaseInsensitiveContains(search) || course(e.courseID).localizedName.localizedCaseInsensitiveContains(search)) &&
            (page == .review ? (e.state == .pending || e.state == .conflict) : (e.state == .approved || (e.state == .conflict && e.wasApproved == true))) &&
            (page != .today || (!e.completed && (e.presentationDate.map { $0 >= Calendar.current.startOfDay(for: .now) && $0 < Calendar.current.date(byAdding: .day, value: 8, to: .now)! } ?? false)))
        }.sorted { ($0.presentationDate ?? .distantFuture) < ($1.presentationDate ?? .distantFuture) }
    }
    init() {
        let env = ProcessInfo.processInfo.environment
        isDemo = env["APP_DEMO"] == "1" || env["APP_SNAPSHOT"] != nil
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Syllapace")
        let url = env["APP_STORE"].map { URL(fileURLWithPath: $0) } ?? (isDemo ? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Syllapace-demo/archive.json") : folder.appendingPathComponent("archive.json"))
        store = ArchiveStore(url: url)
        if isDemo { archive = DemoData.make() } else {
            do { archive = try store.load() } catch { self.error = L10n.format("Could not open your saved data. %@", error.localizedDescription) }
        }
        if archive.courses.isEmpty { archive.courses = [Course(id: "personal", name: "Personal", code: "Personal")] }
    }
    func course(_ id: String) -> Course { archive.courses.first { $0.id == id } ?? Course(id: id, name: L10n.string("Imported course"), code: L10n.string("Course")) }
    func save() {
        guard !isDemo else { return }
        do { try store.save(archive); scheduleCalendarSync() } catch { self.error = L10n.format("Could not save changes. %@", error.localizedDescription) }
    }
    func startRefreshLoop() {
        guard refreshTask == nil, !isDemo else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(600)) } catch { return }
                guard let self else { return }
                if self.canvasAutoSync && !self.canvasHost.isEmpty { self.syncCanvas() }
            }
        }
    }
    func resolveCalendar(_ event: AcademicEvent) {
        guard !busy, !isDemo else { return }; busy = true
        Task {
            defer { busy = false }
            do { notice = try await calendar.resolveUsingApp(event: event) }
            catch { self.error = error.localizedDescription }
        }
    }
    func scheduleCalendarSync() {
        guard calendarAutoSync, calendar.isConnected, !isDemo else { return }
        calendarTask?.cancel()
        calendarTask = Task {
            do {
                try await Task.sleep(for: .seconds(1))
                notice = try await calendar.sync(events: archive.events)
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    func update(_ event: AcademicEvent) {
        if let i = archive.events.firstIndex(where: { $0.id == event.id }) { archive.events[i] = event } else { archive.events.append(event) }
        selectedID = event.id
        save()
    }
    func approve(_ event: AcademicEvent) {
        guard event.date != nil else { editor = event; return }
        var e = event
        if e.state == .conflict { editor = e; return }
        e.state = .approved; e.wasApproved = true; update(e)
    }
    func reject(_ event: AcademicEvent) { var e = event; e.state = .rejected; update(e) }
    func toggleComplete(_ event: AcademicEvent) { var e = event; e.completed.toggle(); update(e) }
    func newEvent() { editor = AcademicEvent(courseID: courseFilter ?? archive.courses.first!.id, title: "", date: Calendar.current.startOfDay(for: .now), state: .approved, evidence: "Added manually") }
    func showDesktop() {
        if panel == nil { panel = DesktopPanel(model: self) }
        panel?.toggle()
    }
    func addCourse(name: String) -> String {
        let id = UUID().uuidString
        archive.courses.append(Course(id: id, name: name, code: name, color: archive.courses.count % 4)); save(); return id
    }
    func ingest(_ source: SourceDocument, navigate: Bool = true) {
        if !navigate, !source.hash.isEmpty, archive.sources.contains(where: { $0.id == source.id && $0.hash == source.hash }) { return }
        if let i = archive.sources.firstIndex(where: { $0.id == source.id }) { archive.sources[i] = source } else { archive.sources.append(source) }
        let found = RuleExtractor.extract(source: source, year: importYear, timeZone: TimeZone.current.identifier)
        archive.events = Reconciler.merge(existing: archive.events, incoming: found)
        notice = found.isEmpty ? L10n.string("Document imported. Use AI extraction or add an event manually.") : L10n.format("Ready to review: %ld.", found.count)
        save(); if navigate { page = found.isEmpty ? .sources : .review }
    }
    func chooseDocument() {
        let picker = NSOpenPanel(); picker.allowsMultipleSelection = false
        picker.allowedContentTypes = [.pdf, .plainText, .html, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "docx") ?? .data]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        busy = true
        Task {
            defer { busy = false }
            do { ingest(try await DocumentReader.read(url: url, courseID: importCourseID)) }
            catch { self.error = error.localizedDescription }
        }
    }
    func syncCanvas() {
        guard !busy else { return }
        guard !isDemo else { notice = L10n.string("Demo data stays separate from your accounts."); return }
        busy = true
        syncTask = Task {
            defer { busy = false }
            do {
                guard let token = try CredentialStore.read(canvasCredentialAccount), !token.isEmpty else { throw AppError.message(L10n.string("Add your Canvas address and token in Settings first.")) }
                let result = try await CanvasClient(host: canvasHost, token: token).sync()
                for course in result.courses {
                    if let i = archive.courses.firstIndex(where: { $0.id == course.id }) { archive.courses[i] = course } else { archive.courses.append(course) }
                }
                archive.events = Reconciler.merge(existing: archive.events, incoming: result.events)
                for source in result.sources { ingest(source, navigate: false) }
                remoteFiles = result.files
                if result.warnings.isEmpty { archive.lastSync = .now }
                save()
                notice = result.warnings.isEmpty ? L10n.string("Canvas is up to date.") : result.warnings.joined(separator: "\n")
            } catch { self.error = error.localizedDescription }
        }
    }
    func fetch(_ file: CanvasFile) {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                guard let token = try CredentialStore.read(canvasCredentialAccount) else { throw AppError.message(L10n.string("Connect Canvas in Settings first.")) }
                let url = try await CanvasClient(host: canvasHost, token: token).download(file: file)
                defer { try? FileManager.default.removeItem(at: url) }
                var source = try await DocumentReader.read(url: url, courseID: file.courseID)
                source.id = file.id; source.title = file.title; source.url = file.sourceURL
                ingest(source)
            } catch { self.error = error.localizedDescription }
        }
    }
    func extractAI(_ source: SourceDocument) {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                guard !isDemo else { throw AppError.message(L10n.string("AI requests are disabled in demo mode.")) }
                guard let key = try CredentialStore.read(modelCredentialAccount), !key.isEmpty else { throw AppError.message(L10n.string("Configure your model and API key in Settings first.")) }
                let candidates = try await LLMClient(endpoint: modelEndpoint, key: key, model: modelName).extract(source: source, year: importYear, timeZone: TimeZone.current.identifier)
                archive.events = Reconciler.merge(existing: archive.events, incoming: candidates)
                save(); page = .review; notice = L10n.format("AI candidates ready to review: %ld.", candidates.count)
            } catch { self.error = error.localizedDescription }
        }
    }
    func syncCalendar() {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do { try await calendar.connect(); notice = try await calendar.sync(events: archive.events) }
            catch { self.error = error.localizedDescription }
        }
    }
    func exportICS() {
        let picker = NSSavePanel(); picker.nameFieldStringValue = "Syllapace.ics"; picker.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .plainText]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do { try ICSExporter.export(events: archive.events, courses: archive.courses).write(to: url, atomically: true, encoding: .utf8); notice = L10n.string("Calendar exported.") }
        catch { self.error = error.localizedDescription }
    }
}
enum AppError: LocalizedError { case message(String); var errorDescription: String? { switch self { case let .message(s): return s } } }
enum AppPage: String, CaseIterable, Identifiable {
    case today = "Today", timeline = "Timeline", review = "Review", sources = "Sources"
    var id: String { rawValue }
    var localizedName: String { L10n.string(rawValue) }
    var symbol: String { switch self { case .today: "sun.max"; case .timeline: "calendar"; case .review: "tray"; case .sources: "doc.text" } }
}
