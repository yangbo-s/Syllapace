import SwiftUI
import SyllapaceKit

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 192, ideal: 212, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if model.isDemo {
                    HStack { Label("Demo workspace", systemImage: "sparkle"); Spacer(); Text("Sample courses · accounts disconnected") }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 8).background(Palette.accent.opacity(0.07))
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
                    HStack(alignment: .top, spacing: 8) { Image(systemName: "info.circle"); Text(notice).textSelection(.enabled); Spacer(); Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss message") }.font(.caption).foregroundStyle(.secondary).padding(12).background(.quaternary.opacity(0.35))
                }
            }
            .background(Palette.canvas)
            .toolbar {
                ToolbarItemGroup {
                    Button { model.syncCanvas() } label: { Label("Sync Canvas", systemImage: "arrow.triangle.2.circlepath") }.disabled(model.busy).help("Sync Canvas (⌘R)")
                    Button { model.showImport = true } label: { Label("Import syllabus", systemImage: "square.and.arrow.down") }.disabled(model.busy).help("Import syllabus (⌘O)")
                    Button { model.newEvent() } label: { Label("New event", systemImage: "plus") }.help("New event (⌘N)")
                }
                ToolbarItem { Button { model.showDesktop() } label: { Label("Desktop card", systemImage: "rectangle.on.rectangle") }.help("Show desktop card") }
            }
            .navigationTitle(model.page.rawValue)
        }
        .tint(Palette.accent)
        .frame(minWidth: 940, minHeight: 620).background(CalmFocus())
        .sheet(item: $model.editor) { event in EventEditor(model: model, original: event).tint(Palette.accent) }
        .sheet(isPresented: $model.showImport) { ImportSheet(model: model) }
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .onChange(of: model.page) { _, _ in if !model.events.contains(where: { $0.id == model.selectedID }) { model.selectedID = nil } }
        .onAppear { model.revealMain = { openWindow(id: "main"); NSApp.activate() } }
        .task { SelfTest.runIfRequested(model: model); model.startRefreshLoop(); Snapshot.runIfRequested(model: model, openSettings: openSettings) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(Palette.accent)
                Text("Syllapace").font(.system(size: 19, weight: .semibold, design: .rounded))
            }.padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 28)
            List(selection: $model.page) {
                Section {
                    ForEach(AppPage.allCases) { page in
                        HStack { Label { Text(page.rawValue) } icon: { Image(systemName: page.symbol).foregroundStyle(Palette.accent) }; Spacer(); if page == .review && model.pendingCount > 0 { Text("\(model.pendingCount)").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 4).tag(page)
                    }
                }
                Section("Courses") {
                    Button { model.courseFilter = nil } label: { HStack { Text("All courses"); Spacer(); if model.courseFilter == nil { Image(systemName: "checkmark").font(.caption) } } }.buttonStyle(.plain).padding(.vertical, 4)
                    ForEach(model.archive.courses) { course in
                        Button { model.courseFilter = model.courseFilter == course.id ? nil : course.id; if model.page == .sources { model.page = .timeline } } label: {
                            HStack(spacing: 8) { Circle().fill(Palette.course(course.color)).frame(width: 8, height: 8); Text(course.code).lineLimit(1); Spacer(); if model.courseFilter == course.id { Image(systemName: "checkmark").font(.caption) } }
                        }.buttonStyle(.plain).padding(.vertical, 4).help(course.name)
                    }
                }
            }.listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 12) {
                Button { openSettings() } label: { Label("Settings", systemImage: "gearshape") }.buttonStyle(.plain)
                HStack(spacing: 8) { Circle().fill(model.archive.lastSync == nil ? Color.secondary : Palette.accent).frame(width: 4, height: 4); Text(model.archive.lastSync.map { "Synced \($0.formatted(.relative(presentation: .numeric)))" } ?? "Ready when you are").lineLimit(1) }.font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.page == .today ? "A little clarity for your day." : model.page == .timeline ? "Your semester, in view." : model.page == .review ? "Make room for certainty." : "Every date has a source.").font(.system(size: 26, weight: .medium, design: .rounded)).tracking(-0.5)
                    Text(model.page == .today ? Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()) : model.page == .review ? "Check the details before they reach your calendar." : model.page == .sources ? "Course documents and the evidence behind your timeline." : "Confirmed dates, across all your courses.").foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small).padding(.top, 8).help("Working…") }
            }.gridProbe("page-title", area: "heading")
            if model.page == .today { WeekRibbon(events: model.events).gridProbe("date-ribbon", area: "heading") }
            if model.page != .sources {
                HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Find an event or course", text: $model.search).accessibilityLabel("Find an event or course").textFieldStyle(.plain); if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) } }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8)).gridProbe("search", area: "heading")
            }
        }.padding(28).gridArea("heading", inset: 28)
    }
    private var eventList: some View {
        Group {
            if model.events.isEmpty {
                ContentUnavailableView {
                    Label(filtered ? "No matching events" : model.page == .review ? "All caught up" : "A clear space to begin", systemImage: filtered ? "magnifyingglass" : model.page == .review ? "checkmark.seal" : "calendar")
                } description: {
                    Text(filtered ? "Try another search or show all your courses." : model.page == .review ? "New dates and schedule changes will appear here." : "Import a syllabus, connect Canvas, or add your first event.")
                } actions: {
                    if filtered { Button("Clear filters") { model.search = ""; model.courseFilter = nil } } else if model.page != .review { Button("Import a syllabus") { model.showImport = true } }
                }

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
    private var filtered: Bool { !model.search.isEmpty || model.courseFilter != nil }
    private var grouped: [(String, [AcademicEvent])] {
        var result: [(String, [AcademicEvent])] = []
        for event in model.events {
            let key = event.presentationDate.map { date in Calendar.current.isDateInToday(date) ? "Today" : Calendar.current.isDateInTomorrow(date) ? "Tomorrow" : date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) } ?? "Date to confirm"
            if result.last?.0 == key { result[result.count - 1].1.append(event) } else { result.append((key, [event])) }
        }
        return result
    }
}

struct WeekRibbon: View {
    let events: [AcademicEvent]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7) { offset in
                let day = Calendar.current.date(byAdding: .day, value: offset, to: Date.now)!
                let hasEvent = events.contains { $0.date.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }
                VStack(spacing: 8) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 11, weight: .medium))
                    Text(day.formatted(.dateTime.day())).font(.system(size: 22, weight: offset == 0 ? .semibold : .regular, design: .rounded))
                    Circle().fill(hasEvent ? (offset == 0 ? Palette.onAccent : Palette.accent) : .clear).frame(width: 4, height: 4)
                }.frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(offset == 0 ? Palette.onAccent : .primary).background(offset == 0 ? Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            }
        }.accessibilityElement(children: .combine)
    }
}

struct EventRow: View {
    @Bindable var model: AppModel
    let event: AcademicEvent
    var body: some View {
        Button { model.selectedID = event.id } label: {
            HStack(spacing: 16) {
                Image(systemName: event.completed ? "checkmark.circle.fill" : event.kind == .exam ? "graduationcap" : event.kind == .presentation ? "person.wave.2" : "doc.text").font(.system(size: 17, weight: .light)).foregroundStyle(event.completed ? .secondary : Palette.course(model.course(event.courseID).color)).frame(width: 28)
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary).strikethrough(event.completed).lineLimit(2)
                    HStack(spacing: 8) { Text(model.course(event.courseID).code); Text("·"); Text(event.sourceID == nil ? (event.evidence == "Added manually" ? "Personal" : "Canvas") : "Syllabus"); if event.state == .conflict { Label("Changed", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(Palette.warning) } }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(event.presentationDate.map { event.dateOnly ? "All day" : $0.formatted(.dateTime.hour().minute()) } ?? "Needs a date").font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 28).padding(.vertical, 16).contentShape(Rectangle()).background(model.selectedID == event.id ? Palette.accent.opacity(0.08) : Color.clear)
        }.buttonStyle(.plain)
        .contextMenu {
            Button("Edit event") { model.editor = event }
            if event.state == .approved { Button(event.completed ? "Mark incomplete" : "Mark complete") { model.toggleComplete(event) } }
            if event.state == .pending { Button("Approve") { model.approve(event) } }
        }
        Divider().padding(.leading, 72).padding(.trailing, 28)
    }
}

struct EventInspector: View {
    @Bindable var model: AppModel
    let event: AcademicEvent
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Text("Event details").font(.headline); Spacer(); Button { model.selectedID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Close details") }.gridProbe("inspector-heading", area: "inspector")
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.course(event.courseID).name).font(.caption).foregroundStyle(.secondary)
                    Text(event.title).font(.system(size: 22, weight: .medium, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                    Label(event.state == .approved ? "Confirmed" : event.state == .conflict ? "Schedule changed" : "Needs review", systemImage: event.state == .approved ? "checkmark.seal" : "questionmark.circle").font(.caption).foregroundStyle(event.state == .approved ? Palette.accent : Palette.warning)
                }.gridProbe("inspector-title", area: "inspector")
                VStack(alignment: .leading, spacing: 8) {
                    Label(event.presentationDate?.formatted(date: .abbreviated, time: event.dateOnly ? .omitted : .shortened) ?? "Date not specified", systemImage: "calendar")
                    Text(event.dateOnly ? "Date only · no time assumed" : TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary)
                    if let proposed = event.proposedDate { Text("Source now says \(proposed.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Palette.warning) }
                }.gridProbe("inspector-date", area: "inspector")
                if !event.evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 12) { Label("Source evidence", systemImage: "text.quote").font(.caption).foregroundStyle(.secondary); Text(event.evidence).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12)).gridProbe("inspector-evidence", area: "inspector")
                }
                if let string = event.sourceURL, let url = URL(string: string), url.scheme == "https" { Link(destination: url) { Label("Open original", systemImage: "arrow.up.right") }.font(.caption).gridProbe("inspector-source-link", area: "inspector") }
                VStack(spacing: 12) {
                    if event.state == .pending {
                        Button(event.date == nil ? "Set date & approve" : "Approve event") { model.approve(event) }.buttonStyle(.borderedProminent).tint(Palette.actionAccent).frame(maxWidth: .infinity)
                        Button("Dismiss candidate") { model.reject(event); model.selectedID = nil }.buttonStyle(.borderless)
                    } else if event.state == .conflict { Button("Review change") { model.editor = event }.buttonStyle(.borderedProminent).tint(Palette.actionAccent) }
                    else { Button(event.completed ? "Mark incomplete" : "Mark complete") { model.toggleComplete(event) }.buttonStyle(.bordered) }
                    Button("Edit details") { model.editor = event }.buttonStyle(.borderless)
                }.frame(maxWidth: .infinity).gridProbe("inspector-actions", area: "inspector")
            }.padding(24).gridArea("inspector", inset: 24)
        }.background(.quaternary.opacity(0.12))
    }
}
