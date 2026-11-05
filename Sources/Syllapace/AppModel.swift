import AppKit
import Observation
import SyllapaceKit
import UniformTypeIdentifiers

@Observable final class AppModel {
    var archive = AppArchive()
    var page: AppPage = .today
    var selectedID: String?
    var courseFilter: String?
    var academicCalendarFilter: String?
    var editingCourse: Course?
    var importCalendarID: String?
    var importURL = ""
    var importFixtureMode: Int?
    var modelProvider = ModelProvider(rawValue: UserDefaults.standard.string(forKey: "modelProvider") ?? "custom") ?? .custom
    var modelWorkspaceID = UserDefaults.standard.string(forKey: "modelWorkspaceID") ?? ""
    var search = ""
    var busy = false
    var notice: String?
    var error: String?
    var editor: AcademicEvent?
    var showImport = false
    var calendarStatus: [String: String] = [:]
    var lastImportUndo: ImportUndo?
    var readingSource: SourceDocument?
    var showCourseSelection = false
    var draftTermID: String?
    var draftCourseIDs: Set<String> = []
    var discoveredCanvasCourses: [Course]?
    var kindFilter: EventKind?
    var importCourseID = "personal"
    var importYear = Calendar.current.component(.year, from: .now)
    var remoteFiles: [CanvasFile] = []
    var settingsTab = 3
    var showSchoolSearch = false
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
    let tokenRenewal = CanvasTokenRenewal()
    let isDemo: Bool
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var canvasGeneration = UUID()
    @ObservationIgnored let store: ArchiveStore
    @ObservationIgnored var revealMain: () -> Void = {}
    @ObservationIgnored var panel: DesktopPanel?
    var scopedCourses: [Course] {
        archive.courses.filter { !$0.isCanvas || archive.canvasSelection?.includes($0) == true }
    }
    var scopedCourseIDs: Set<String> { Set(scopedCourses.map(\.id)) }
    var scopedEvents: [AcademicEvent] { archive.events.filter { isInScope(courseID: $0.courseID, calendarID: $0.academicCalendarID) && academicDateIsVisible($0) } }
    var scopedSources: [SourceDocument] { archive.sources.filter { isInScope(courseID: $0.courseID, calendarID: $0.academicCalendarID) && (courseFilter == nil || $0.courseID == courseFilter) && (academicCalendarFilter == nil || $0.academicCalendarID == academicCalendarFilter) } }
    var scopedRemoteFiles: [CanvasFile] { let ids = scopedCourseIDs; return remoteFiles.filter { ids.contains($0.courseID) && (courseFilter == nil || $0.courseID == courseFilter) } }
    var selectedEvent: AcademicEvent? { scopedEvents.first { $0.id == selectedID } }
    var pendingCount: Int { scopedEvents.filter { $0.state == .pending || $0.state == .conflict }.count }
    var canvasCourses: [Course] {
        if let discoveredCanvasCourses { return discoveredCanvasCourses }
        guard !isDemo, let origin = try? ConnectorURL.canvasOrigin(canvasHost), let host = origin.host else { return archive.courses.filter(\.isCanvas) }
        let prefix = "canvas:\(host.lowercased()):\(origin.port ?? 443):course:"
        return archive.courses.filter { $0.id.hasPrefix(prefix) }
    }
    var availableTerms: [AcademicTerm] {
        var seen = Set<String>()
        return canvasCourses.compactMap(\.term).filter { seen.insert($0.id).inserted }.sorted {
            if $0.startAt != $1.startAt { return ($0.startAt ?? .distantPast) > ($1.startAt ?? .distantPast) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    var selectedSemesterName: String {
        guard let selection = archive.canvasSelection else { return L10n.string("Choose semester") }
        guard let id = selection.termID else { return L10n.string("All semesters") }
        return archive.courses.compactMap(\.term).first { $0.id == id }?.name ?? L10n.string("Selected semester")
    }
    var needsCourseSelection: Bool { archive.canvasSelection == nil && (!canvasHost.isEmpty || archive.courses.contains(where: \.isCanvas)) }
    var events: [AcademicEvent] {
        scopedEvents.filter { e in
            (courseFilter == nil || e.courseID == courseFilter) &&
            (academicCalendarFilter == nil || e.academicCalendarID == academicCalendarFilter) &&
            (kindFilter == nil || e.kind == kindFilter) &&
            (search.isEmpty || e.title.localizedCaseInsensitiveContains(search) || eventSearchText(e).localizedCaseInsensitiveContains(search)) &&
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
        if isDemo || env["APP_SELFTEST"] == "1" {
            canvasHost = "https://canvas.example.edu"
            modelEndpoint = "https://api.openai.com/v1"; modelName = "example-model"
            canvasAutoSync = false; calendarAutoSync = false
        }
        if isDemo { archive = DemoData.make() } else {
            do { archive = try store.load() } catch { self.error = L10n.format("Could not open your saved data. %@", error.localizedDescription) }
        }
        if archive.courses.isEmpty { archive.courses = [Course(id: "personal", name: "Personal", code: "Personal")] }
    }
    func course(_ id: String) -> Course { archive.courses.first { $0.id == id } ?? Course(id: id, name: L10n.string("Imported course"), code: L10n.string("Course")) }
    @discardableResult func save() -> Bool {
        guard !isDemo else { return true }
        do { try store.save(archive); scheduleCalendarSync(); return true } catch { self.error = L10n.format("Could not save changes. %@", error.localizedDescription); return false }
    }
    func startRefreshLoop() {
        guard refreshTask == nil, !isDemo else { return }
        checkCanvasToken()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(600)) } catch { return }
                guard let self else { return }
                if !self.busy, let due = self.scopedAcademicCalendars.first(where: { !$0.url.isEmpty && ($0.lastFetchedAt ?? .distantPast) < Date.now.addingTimeInterval(-6 * 3600) }) { self.syncAcademicCalendar(due) }
                else if self.canvasAutoSync && !self.canvasHost.isEmpty { self.syncCanvas(promptForSelection: false) }
            }
        }
    }
    func checkCanvasToken(force: Bool = false) {
        guard !isDemo, ProcessInfo.processInfo.environment["APP_SELFTEST"] != "1",
              canvasHost == UserDefaults.standard.string(forKey: "canvasHost") else { return }
        tokenRenewal.start(host: canvasHost, account: canvasCredentialAccount, force: force)
    }
    func resolveCalendar(_ event: AcademicEvent) {
        guard !busy, !isDemo, isInScope(courseID: event.courseID, calendarID: event.academicCalendarID) else { return }; busy = true
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
                notice = try await calendar.sync(events: scopedEvents)
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    func update(_ event: AcademicEvent) {
        var event = event
        event.importUndone = nil
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
    func newEvent() { editor = AcademicEvent(courseID: academicCalendarFilter != nil ? "" : courseFilter ?? scopedCourses.first?.id ?? "personal", title: "", date: Calendar.current.startOfDay(for: .now), state: .approved, evidence: "Added manually", academicCalendarID: academicCalendarFilter) }
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
        // Structured Canvas assignments already have their own identity and due date.
        let found = source.kind == .assignment ? [] : RuleExtractor.extract(source: source, year: course(source.courseID).term?.academicYear ?? importYear, timeZone: course(source.courseID).timeZone ?? TimeZone.current.identifier)
        archive.events = Reconciler.merge(existing: archive.events, incoming: found)
        notice = found.isEmpty ? L10n.string("Document imported. Use AI extraction or add an event manually.") : L10n.format("Ready to review: %ld.", found.count)
        if navigate { save(); page = found.isEmpty ? .sources : .review }
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
    func syncCanvas(promptForSelection: Bool = true) {
        guard !busy else { return }
        guard !isDemo else { notice = L10n.string("Demo data stays separate from your accounts."); return }
        let host = canvasHost
        let account = canvasCredentialAccount
        let generation = canvasGeneration
        busy = true
        syncTask = Task {
            defer { if canvasGeneration == generation { busy = false; syncTask = nil } }
            do {
                guard let token = try await CredentialStore.readAsync(account), !token.isEmpty else { throw AppError.message(L10n.string("Add your Canvas address and token in Settings first.")) }
                try Task.checkCancellation()
                let client = try CanvasClient(host: host, token: token)
                let discovered = try await client.discoverCourses()
                guard canvasGeneration == generation, canvasHost == host else { return }
                discoveredCanvasCourses = discovered
                mergeCourses(discovered)
                let selected = discovered.filter { archive.canvasSelection?.courseIDs.contains($0.id) == true }
                guard archive.canvasSelection != nil else {
                    if promptForSelection { prepareCourseSelection(termID: recommendedTermID) }
                    notice = L10n.string("Choose a semester and courses before syncing Canvas content.")
                    save()
                    return
                }
                // A changed account has a separate set of course identities.
                if selected.isEmpty, archive.canvasSelection?.courseIDs.isEmpty == false {
                    if promptForSelection { prepareCourseSelection(termID: recommendedTermID) }
                    notice = L10n.string("Your selected courses are unavailable. Review your course selection.")
                    save()
                    return
                }
                let result = try await client.sync(courses: selected)
                guard canvasGeneration == generation, canvasHost == host else { return }
                for course in result.courses {
                    if let i = archive.courses.firstIndex(where: { $0.id == course.id }) { archive.courses[i] = course } else { archive.courses.append(course) }
                }
                archive.events = Reconciler.merge(existing: archive.events, incoming: result.events)
                for source in result.sources { ingest(source, navigate: false) }
                remoteFiles = result.files
                archive.lastSync = .now
                save()
                var messages = result.warnings
                let missing = (archive.canvasSelection?.courseIDs ?? []).subtracting(Set(discovered.map(\.id)))
                if !missing.isEmpty { messages.insert(L10n.string("Some selected courses are unavailable. Their saved materials have been kept."), at: 0) }
                notice = messages.isEmpty ? L10n.string("Canvas is up to date.") : messages.joined(separator: "\n")
                checkCanvasToken()
            } catch is CancellationError { }
            catch { if canvasGeneration == generation { self.error = error.localizedDescription } }
        }
    }
    private func mergeCourses(_ courses: [Course]) {
        for course in courses {
            if let i = archive.courses.firstIndex(where: { $0.id == course.id }) { archive.courses[i] = course }
            else { archive.courses.append(course) }
        }
    }
    private var recommendedTermID: String? {
        let terms = availableTerms.filter { $0.name.caseInsensitiveCompare("Default Term") != .orderedSame }
        return terms.first { ($0.startAt ?? .distantPast) <= .now && ($0.endAt ?? .distantFuture) >= .now }?.id ?? terms.first?.id
    }
    func prepareCourseSelection(termID: String?) {
        draftTermID = termID
        if let selection = archive.canvasSelection, selection.termID == termID {
            draftCourseIDs = selection.courseIDs.intersection(Set(canvasCourses.map(\.id)))
        } else {
            draftCourseIDs = Set(canvasCourses.filter { termID != nil && $0.term?.id == termID }.map(\.id))
        }
        showCourseSelection = true
    }
    func manageCanvasCourses() {
        guard !busy else { return }
        if discoveredCanvasCourses == nil && !isDemo { discoverCanvasCourses() }
        else { prepareCourseSelection(termID: archive.canvasSelection == nil ? recommendedTermID : archive.canvasSelection?.termID) }
    }
    func discoverCanvasCourses() {
        guard !busy, !isDemo else { return }
        let host = canvasHost
        let account = canvasCredentialAccount
        let generation = canvasGeneration
        busy = true
        syncTask = Task {
            defer { if canvasGeneration == generation { busy = false; syncTask = nil } }
            do {
                guard let token = try await CredentialStore.readAsync(account), !token.isEmpty else { throw AppError.message(L10n.string("Add your Canvas address and token in Settings first.")) }
                try Task.checkCancellation()
                let courses = try await CanvasClient(host: host, token: token).discoverCourses()
                guard canvasGeneration == generation, canvasHost == host else { return }
                discoveredCanvasCourses = courses
                mergeCourses(courses)
                save()
                prepareCourseSelection(termID: archive.canvasSelection == nil ? recommendedTermID : archive.canvasSelection?.termID)
            } catch is CancellationError { }
            catch { if canvasGeneration == generation { self.error = error.localizedDescription } }
        }
    }
    func applyCanvasSelection(sync: Bool = true) {
        guard !busy else { return }
        archive.canvasSelection = CanvasSelection(termID: draftTermID, courseIDs: draftCourseIDs.intersection(Set(canvasCourses.map(\.id))))
        selectedID = nil; courseFilter = nil; academicCalendarFilter = nil; kindFilter = nil; search = ""
        if let year = availableTerms.first(where: { $0.id == draftTermID })?.academicYear { importYear = year }
        showCourseSelection = false
        save()
        if sync && !isDemo { syncCanvas() }
    }
    func invalidateCanvasConnection() {
        canvasGeneration = UUID()
        if syncTask != nil { syncTask?.cancel(); syncTask = nil; busy = false }
        discoveredCanvasCourses = nil
        remoteFiles = []
        tokenRenewal.cancel()
    }
    func fetch(_ file: CanvasFile) {
        guard !busy, scopedCourseIDs.contains(file.courseID), !isDemo else { return }
        let host = canvasHost, account = canvasCredentialAccount, generation = canvasGeneration
        busy = true
        Task {
            defer { busy = false }
            do {
                guard let token = try await CredentialStore.readAsync(account) else { throw AppError.message(L10n.string("Connect Canvas in Settings first.")) }
                guard generation == canvasGeneration, host == canvasHost else { return }
                let url = try await CanvasClient(host: host, token: token).download(file: file)
                defer { try? FileManager.default.removeItem(at: url) }
                var source = try await DocumentReader.read(url: url, courseID: file.courseID)
                source.id = file.id; source.title = file.title; source.url = file.sourceURL
                guard generation == canvasGeneration, host == canvasHost, scopedCourseIDs.contains(file.courseID) else { return }
                ingest(source)
            } catch { self.error = error.localizedDescription }
        }
    }
    func importExternal(_ link: SourceLink, courseID: String) {
        guard !busy, scopedCourseIDs.contains(courseID) else { return }
        guard !isDemo else { notice = L10n.string("Demo data stays separate from your accounts."); return }
        busy = true
        Task {
            defer { busy = false }
            do { ingest(try await PublicDocumentClient().read(link: link, courseID: courseID)) }
            catch { self.error = error.localizedDescription }
        }
    }
    func extractAI(_ source: SourceDocument) {
        guard !busy, isInScope(courseID: source.courseID, calendarID: source.academicCalendarID) else { return }
        let endpoint = modelEndpoint, name = modelName, account = modelCredentialAccount
        let provider = modelProvider, workspace = modelWorkspaceID
        let year = course(source.courseID).term?.academicYear ?? importYear
        let zone = source.academicCalendarID.flatMap { id in archive.academicCalendars?.first { $0.id == id }?.timeZone } ?? course(source.courseID).timeZone ?? TimeZone.current.identifier
        busy = true
        Task {
            defer { busy = false }
            do {
                guard !isDemo else { throw AppError.message(L10n.string("AI requests are disabled in demo mode.")) }
                guard let key = try await CredentialStore.readAsync(account), !key.isEmpty else { throw AppError.message(L10n.string("Configure your model and API key in Settings first.")) }
                guard endpoint == modelEndpoint, name == modelName, account == modelCredentialAccount, provider == modelProvider, workspace == modelWorkspaceID else { return }
                let candidates = try await LLMClient(endpoint: endpoint, key: key, model: name, provider: provider, workspaceID: workspace.isEmpty ? nil : workspace).extract(source: source, year: year, timeZone: zone)
                guard endpoint == modelEndpoint, name == modelName, provider == modelProvider, workspace == modelWorkspaceID, isInScope(courseID: source.courseID, calendarID: source.academicCalendarID) else { return }
                archive.events = Reconciler.merge(existing: archive.events, incoming: candidates)
                save(); page = .review; notice = L10n.format("AI candidates ready to review: %ld.", candidates.count)
            } catch { self.error = error.localizedDescription }
        }
    }
    func syncCalendar() {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do { try await calendar.connect(); notice = try await calendar.sync(events: scopedEvents) }
            catch { self.error = error.localizedDescription }
        }
    }
    func exportICS() {
        let picker = NSSavePanel(); picker.nameFieldStringValue = "Syllapace.ics"; picker.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .plainText]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do { try ICSExporter.export(events: scopedEvents, courses: scopedCourses, calendars: scopedAcademicCalendars).write(to: url, atomically: true, encoding: .utf8); notice = L10n.string("Calendar exported.") }
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
