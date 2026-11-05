import SwiftUI
import SyllapaceKit

struct ContentView: View {
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        // Redraw translated content without replacing the view or its draft state.
        let _ = languagePreference
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 192, ideal: 212, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if model.isDemo {
                    HStack { Label(L10n.string("Demo workspace"), systemImage: "sparkle"); Spacer(); Text(L10n.string("Sample courses · accounts disconnected")) }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 8).background(Palette.accent.opacity(0.07))
                }
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        heading.gridProbe("heading", area: "content-column")
                        if model.page == .sources { SourcesView(model: model) }
                        else { eventList }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).gridArea("content-column", inset: 0)
                    if let event = model.selectedEvent, model.page != .sources {
                        Divider()
                        EventInspector(model: model, event: event).frame(width: 292)
                    }
                }
                if let notice = model.notice {
                    HStack(alignment: .top, spacing: 8) { Image(systemName: "info.circle"); ScrollView { Text(notice).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 80); Spacer(); Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help(L10n.string("Dismiss message")) }.font(.caption).foregroundStyle(.secondary).padding(12).background(.quaternary.opacity(0.35))
                }
            }
            .background(Palette.canvas)
            .toolbar {
                ToolbarItemGroup {
                    Button { model.syncCanvas() } label: { Label(L10n.string("Sync Canvas"), systemImage: "arrow.triangle.2.circlepath") }.disabled(model.busy).help(L10n.string("Sync Canvas (⌘R)"))
                    Button { model.showImport = true } label: { Label(L10n.string("Import syllabus"), systemImage: "square.and.arrow.down") }.disabled(model.busy).help(L10n.string("Import syllabus (⌘O)"))
                    Button { model.newEvent() } label: { Label(L10n.string("New event"), systemImage: "plus") }.help(L10n.string("New event (⌘N)"))
                }
                ToolbarItem { Button { model.showDesktop() } label: { Label(L10n.string("Desktop card"), systemImage: "rectangle.on.rectangle") }.help(L10n.string("Show desktop card")) }
            }
            .navigationTitle(model.page.localizedName)
        }
        .tint(Palette.accent)
        .frame(minWidth: 940, minHeight: 620).background(CalmFocus())
        .sheet(item: $model.editor) { event in EventEditor(model: model, original: event).tint(Palette.accent) }
        .sheet(isPresented: $model.showImport) { ImportSheet(model: model) }
        .sheet(isPresented: $model.showCourseSelection) { CourseScopeView(model: model) }
        .alert(L10n.string("Something needs attention"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button(L10n.string("OK")) { model.error = nil } } message: { Text(model.error ?? "") }
        .onChange(of: model.page) { _, _ in if !model.events.contains(where: { $0.id == model.selectedID }) { model.selectedID = nil } }
        .onAppear { model.revealMain = { openWindow(id: "main"); NSApp.activate() } }
        .task { SelfTest.runIfRequested(model: model); model.startRefreshLoop(); Snapshot.runIfRequested(model: model, openSettings: openSettings) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(Palette.accent)
                Text("Syllapace").font(.system(size: 19, weight: .semibold, design: .rounded))
            }.padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 20)
            Menu {
                ForEach(model.availableTerms) { term in
                    Button(term.name) { model.prepareCourseSelection(termID: term.id) }
                }
                if !model.availableTerms.isEmpty {
                    Button(L10n.string("All semesters")) { model.prepareCourseSelection(termID: nil) }
                    Divider()
                }
                Button(L10n.string("Manage courses…")) { model.manageCanvasCourses() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar").foregroundStyle(Palette.accent)
                    Text(model.selectedSemesterName).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }.menuStyle(.borderlessButton).disabled(model.busy).padding(.horizontal, 20).padding(.bottom, 16)
                .help(L10n.string("Choose the semester and courses shown in your workspace"))
            List(selection: $model.page) {
                Section {
                    ForEach(AppPage.allCases) { page in
                        HStack { Label { Text(page.localizedName) } icon: { if page == model.page { Image(systemName: page.symbol) } else { Image(systemName: page.symbol).foregroundStyle(Palette.accent) } }; Spacer(); if page == .review && model.pendingCount > 0 { Text("\(model.pendingCount)").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 4).tag(page)
                    }
                }
                Section(L10n.string("Courses")) {
                    Button { model.courseFilter = nil } label: { HStack { Text(L10n.string("All courses")); Spacer(); if model.courseFilter == nil { Image(systemName: "checkmark").font(.caption) } } }.buttonStyle(.plain).padding(.vertical, 4)
                    ForEach(model.scopedCourses) { course in
                        Button { model.courseFilter = model.courseFilter == course.id ? nil : course.id; if model.page == .sources { model.page = .timeline } } label: {
                            HStack(spacing: 8) { Circle().fill(Palette.course(course.color)).frame(width: 8, height: 8); Text(course.localizedCode).lineLimit(1); Spacer(); if model.courseFilter == course.id { Image(systemName: "checkmark").font(.caption) } }
                        }.buttonStyle(.plain).padding(.vertical, 4).help(course.localizedName)
                    }
                }
            }.listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 12) {
                Button { openSettings() } label: { Label(L10n.string("Settings"), systemImage: "gearshape") }.buttonStyle(.plain)
                HStack(spacing: 8) { Circle().fill(model.archive.lastSync == nil ? Color.secondary : Palette.accent).frame(width: 4, height: 4); Text(model.archive.lastSync.map { L10n.format("Synced %@", L10n.relativeDate($0)) } ?? L10n.string("Ready when you are")).lineLimit(1) }.font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.page == .today ? L10n.string("A little clarity for your day.") : model.page == .timeline ? L10n.string("Your semester, in view.") : model.page == .review ? L10n.string("Make room for certainty.") : L10n.string("Every date has a source.")).font(.system(size: 26, weight: .medium, design: .rounded)).tracking(-0.5)
                    Text(model.page == .today ? Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(L10n.locale)) : model.page == .review ? L10n.string("Check the details before they reach your calendar.") : model.page == .sources ? L10n.string("Course documents and the evidence behind your timeline.") : L10n.string("Confirmed dates, across all your courses.")).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small).padding(.top, 8).help(L10n.string("Working…")) }
            }.gridProbe("page-title", area: "heading")
            if model.page == .today { WeekRibbon(events: model.events).gridProbe("date-ribbon", area: "heading") }
            if model.page != .sources {
                HStack(spacing: 12) {
                    HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField(L10n.string("Find an event or course"), text: $model.search).accessibilityLabel(L10n.string("Find an event or course")).textFieldStyle(.plain); if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) } }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    Menu {
                        Button(L10n.string("All types")) { model.kindFilter = nil }
                        Divider()
                        ForEach(EventKind.allCases, id: \.self) { kind in Button(kind.localizedName) { model.kindFilter = kind } }
                    } label: { Label(model.kindFilter?.localizedName ?? L10n.string("All types"), systemImage: "line.3.horizontal.decrease") }
                        .fixedSize().help(L10n.string("Filter by event type"))
                }.gridProbe("search", area: "heading")
            }
        }.padding(28).gridArea("heading", inset: 28)
    }
    private var eventList: some View {
        Group {
            if model.needsCourseSelection && model.events.isEmpty {
                ContentUnavailableView {
                    Label(L10n.string("Your semester starts here"), systemImage: "graduationcap")
                } description: {
                    Text(L10n.string("Choose your semester and courses to build a focused timeline."))
                } actions: {
                    Button(L10n.string("Choose semester")) { model.manageCanvasCourses() }.disabled(model.busy)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).gridProbe("empty-state", area: "content-column")
            } else if model.events.isEmpty {
                ContentUnavailableView {
                    Label(filtered ? L10n.string("No matching events") : model.page == .review ? L10n.string("All caught up") : L10n.string("A clear space to begin"), systemImage: filtered ? "magnifyingglass" : model.page == .review ? "checkmark.seal" : "calendar")
                } description: {
                    Text(filtered ? L10n.string("Try another search or show all your courses.") : model.page == .review ? L10n.string("New dates and schedule changes will appear here.") : L10n.string("Import a syllabus, connect Canvas, or add your first event."))
                } actions: {
                    if filtered { Button(L10n.string("Clear filters")) { model.search = ""; model.courseFilter = nil; model.kindFilter = nil } } else if model.page != .review { Button(L10n.string("Import a syllabus")) { model.showImport = true } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gridProbe("empty-state", area: "content-column")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(grouped.enumerated()), id: \.offset) { _, group in
                            Text(group.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 12).padding(.bottom, 8).padding(.horizontal, 28)
                            ForEach(group.1) { event in
                                EventRow(model: model, event: event)
                            }
                        }
                    }.padding(.bottom, 28)
                }
            }
        }
    }
    private var filtered: Bool { !model.search.isEmpty || model.courseFilter != nil || model.kindFilter != nil }
    private var grouped: [(String, [AcademicEvent])] {
        var result: [(String, [AcademicEvent])] = []
        for event in model.events {
            let key = event.presentationDate.map { date in Calendar.current.isDateInToday(date) ? L10n.string("Today") : Calendar.current.isDateInTomorrow(date) ? L10n.string("Tomorrow") : date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(L10n.locale)) } ?? L10n.string("Date to confirm")
            if result.last?.0 == key { result[result.count - 1].1.append(event) } else { result.append((key, [event])) }
        }
        return result
    }
}

struct WeekRibbon: View {
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    let events: [AcademicEvent]
    var body: some View {
        // Redraw translated content without replacing the view or its draft state.
        let _ = languagePreference
        HStack(spacing: 4) {
            ForEach(0..<7) { offset in
                let day = Calendar.current.date(byAdding: .day, value: offset, to: Date.now)!
                let hasEvent = events.contains { $0.date.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }
                VStack(spacing: 8) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale))).font(.system(size: 11, weight: .medium))
                    Text(day.formatted(.dateTime.day().locale(L10n.locale))).font(.system(size: 22, weight: offset == 0 ? .semibold : .regular, design: .rounded))
                    Circle().fill(hasEvent ? (offset == 0 ? Palette.onAccent : Palette.accent) : .clear).frame(width: 4, height: 4)
                }.frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(offset == 0 ? Palette.onAccent : .primary).background(offset == 0 ? Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            }
        }.accessibilityElement(children: .combine)
    }
}

struct EventRow: View {
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    @Bindable var model: AppModel
    let event: AcademicEvent
    var body: some View {
        // Redraw translated content without replacing the view or its draft state.
        let _ = languagePreference
        Button { model.selectedID = event.id } label: {
            HStack(spacing: 16) {
                Image(systemName: event.completed ? "checkmark.circle.fill" : eventSymbol).font(.system(size: 17, weight: .light)).foregroundStyle(event.completed ? .secondary : Palette.course(model.course(event.courseID).color)).frame(width: 28)
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary).strikethrough(event.completed).lineLimit(2)
                    HStack(spacing: 8) { Text(model.course(event.courseID).localizedCode); Text("·"); Text(event.kind.localizedName); if event.state == .conflict { Label(L10n.string("Changed"), systemImage: "arrow.triangle.2.circlepath").foregroundStyle(Palette.warning) } }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(event.presentationDate.map { event.dateOnly ? L10n.string("All day") : $0.formatted(.dateTime.hour().minute().locale(L10n.locale)) } ?? L10n.string("Needs a date")).font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 28).padding(.vertical, 16).contentShape(Rectangle()).background(model.selectedID == event.id ? Palette.accent.opacity(0.08) : Color.clear)
        }.buttonStyle(.plain)
        .contextMenu {
            Button(L10n.string("Edit event")) { model.editor = event }
            if event.state == .approved { Button(event.completed ? L10n.string("Mark incomplete") : L10n.string("Mark complete")) { model.toggleComplete(event) } }
            if event.state == .pending { Button(L10n.string("Approve")) { model.approve(event) } }
        }
        Divider().padding(.leading, 72).padding(.trailing, 28)
    }
    private var eventSymbol: String {
        switch event.kind {
        case .session: "person.2"
        case .assignment: "doc.text"
        case .project: "square.stack.3d.up"
        case .quiz: "questionmark.square"
        case .exam: "graduationcap"
        case .presentation: "person.wave.2"
        case .other: "calendar"
        }
    }
}

struct EventInspector: View {
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    @Bindable var model: AppModel
    let event: AcademicEvent
    var body: some View {
        // Redraw translated content without replacing the view or its draft state.
        let _ = languagePreference
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Text(L10n.string("Event details")).font(.headline); Spacer(); Button { model.selectedID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help(L10n.string("Close details")) }.gridProbe("inspector-heading", area: "inspector")
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.course(event.courseID).localizedName).font(.caption).foregroundStyle(.secondary)
                    Text(event.title).font(.system(size: 22, weight: .medium, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                    Label(event.state == .approved ? L10n.string("Confirmed") : event.state == .conflict ? L10n.string("Schedule changed") : L10n.string("Needs review"), systemImage: event.state == .approved ? "checkmark.seal" : "questionmark.circle").font(.caption).foregroundStyle(event.state == .approved ? Palette.accent : Palette.warning)
                }.gridProbe("inspector-title", area: "inspector")
                VStack(alignment: .leading, spacing: 8) {
                    Label(event.presentationDate.map { L10n.date($0, dateOnly: event.dateOnly) } ?? L10n.string("Date not specified"), systemImage: "calendar")
                    if let end = event.endsAt { Label(L10n.format("Ends %@", L10n.date(end, dateOnly: event.dateOnly)), systemImage: "clock") }
                    if let location = event.location, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse") }
                    Text(event.dateOnly ? L10n.string("Date only · no time assumed") : event.timeZone).font(.caption).foregroundStyle(.secondary)
                    if let proposed = event.proposedDate { Text(L10n.format("Source now says %@", L10n.date(proposed, dateOnly: true))).font(.caption).foregroundStyle(Palette.warning) }
                }.gridProbe("inspector-date", area: "inspector")
                if let submission = event.submission {
                    VStack(alignment: .leading, spacing: 8) {
                        if let state = submission.state { LabeledContent(L10n.string("Submission"), value: submissionState(state)) }
                        if let grade = submission.grade { LabeledContent(L10n.string("Grade"), value: grade) }
                        else if let score = submission.score { LabeledContent(L10n.string("Score"), value: score.formatted()) }
                        if submission.excused == true { Text(L10n.string("Excused")).foregroundStyle(.secondary) }
                        if submission.missing == true { Text(L10n.string("Missing")).foregroundStyle(Palette.warning) }
                        if submission.late == true { Text(L10n.string("Late")).foregroundStyle(Palette.warning) }
                    }.font(.caption).gridProbe("inspector-submission", area: "inspector")
                }
                if !event.evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 12) { Label(L10n.string("Source evidence"), systemImage: "text.quote").font(.caption).foregroundStyle(.secondary); Text(event.evidence == "Added manually" ? L10n.string("Added manually") : event.evidence).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12)).gridProbe("inspector-evidence", area: "inspector")
                }
                if let string = event.sourceURL, let url = URL(string: string), url.scheme == "https" { Link(destination: url) { Label(L10n.string("Open original"), systemImage: "arrow.up.right") }.font(.caption).gridProbe("inspector-source-link", area: "inspector") }
                VStack(spacing: 12) {
                    if event.state == .pending {
                        Button(event.date == nil ? L10n.string("Set date & approve") : L10n.string("Approve event")) { model.approve(event) }.buttonStyle(.borderedProminent).tint(Palette.actionAccent).frame(maxWidth: .infinity)
                        Button(L10n.string("Dismiss candidate")) { model.reject(event); model.selectedID = nil }.buttonStyle(.borderless)
                    } else if event.state == .conflict { Button(L10n.string("Review change")) { model.editor = event }.buttonStyle(.borderedProminent).tint(Palette.actionAccent) }
                    else { Button(event.completed ? L10n.string("Mark incomplete") : L10n.string("Mark complete")) { model.toggleComplete(event) }.buttonStyle(.bordered) }
                    Button(L10n.string("Edit details")) { model.editor = event }.buttonStyle(.borderless)
                }.frame(maxWidth: .infinity).gridProbe("inspector-actions", area: "inspector")
            }.padding(24).gridArea("inspector", inset: 24)
        }.background(.quaternary.opacity(0.12))
    }
    private func submissionState(_ state: String) -> String {
        switch state {
        case "unsubmitted": L10n.string("Not submitted")
        case "submitted": L10n.string("Submitted")
        case "graded": L10n.string("Graded")
        case "pending_review": L10n.string("Awaiting review")
        default: state
        }
    }
}
