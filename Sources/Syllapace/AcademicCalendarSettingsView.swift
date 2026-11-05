import SwiftUI
import SyllapaceKit

struct AcademicCalendarSettingsView: View {
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue
    @Bindable var model: AppModel
    @State private var draft: AcademicCalendarSubscription?
    @State private var validation: String?
    @State private var customZone = false
    @State private var timeZoneInput = ""
    private let commonZones = ["America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles", "Europe/London", "Asia/Shanghai", "Asia/Singapore", "UTC"]

    var body: some View {
        let _ = languagePreference
        Form {
            Section(L10n.string("Academic calendars")) {
                ForEach(model.archive.academicCalendars ?? []) { subscription in
                    HStack(spacing: 8) {
                        Toggle(subscription.name, isOn: Binding(get: {
                            model.archive.academicCalendars?.first { $0.id == subscription.id }?.enabled ?? false
                        }, set: { enabled in
                            var changed = subscription; changed.enabled = enabled
                            model.saveAcademicCalendar(changed)
                            if draft?.id == changed.id { draft?.enabled = enabled }
                        })).controlSize(.mini)
                        Button { edit(subscription) } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .help(L10n.string("Edit calendar"))
                            .accessibilityLabel(L10n.format("Edit %@", subscription.name))
                    }
                }
                HStack(spacing: 8) {
                    Menu(L10n.string("Add calendar")) {
                        Button("CMU Academic Calendar") { addCMU() }
                        Button(L10n.string("Custom calendar…")) { addCustom() }
                    }
                    Spacer()
                }
                if (model.archive.academicCalendars ?? []).isEmpty && draft == nil {
                    Text(L10n.string("Add school dates from an ICS subscription or an academic calendar document."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let selected = draft {
                editor(selected)
            }
        }
        .formStyle(.grouped)
        .onAppear { if model.isDemo, let first = model.archive.academicCalendars?.first { edit(first) } }
    }

    @ViewBuilder private func editor(_ selected: AcademicCalendarSubscription) -> some View {
        Section(L10n.string("Calendar details")) {
            TextField(L10n.string("Name"), text: field(\.name))
            TextField(L10n.string("ICS subscription URL (optional)"), text: field(\.url), prompt: Text("https://… / webcal://…"))
            Picker(L10n.string("Semester"), selection: Binding(get: { draft?.termID ?? "" }, set: { value in
                draft?.termID = value.isEmpty ? nil : value
                setSuggestedRange()
            })) {
                Text(L10n.string("All semesters")).tag("")
                ForEach(model.availableTerms) { term in Text(term.name).tag(term.id) }
                if let id = selected.termID, !model.availableTerms.contains(where: { $0.id == id }) {
                    Text(L10n.string("Saved semester")).tag(id)
                }
            }
            .id("calendar-term-\(languagePreference)")
            Picker(L10n.string("Time zone"), selection: Binding(get: {
                customZone ? "custom" : (draft?.timeZone ?? "UTC")
            }, set: { zone in
                customZone = zone == "custom"
                if !customZone { changeTimeZone(zone); timeZoneInput = zone }
            })) {
                ForEach(commonZones, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                Text(L10n.string("Other time zone…")).tag("custom")
            }
            .id("calendar-zone-\(languagePreference)")
            if customZone {
                TextField(L10n.string("Time zone identifier"), text: $timeZoneInput, prompt: Text("Europe/Paris"))
                    .onChange(of: timeZoneInput) { _, value in
                        if TimeZone(identifier: value) != nil { changeTimeZone(value) }
                    }
            }
            DatePicker(L10n.string("From"), selection: startDate, displayedComponents: .date).id("calendar-from-\(languagePreference)")
            DatePicker(L10n.string("Through"), selection: lastDate, displayedComponents: .date).id("calendar-through-\(languagePreference)")
            HStack(spacing: 8) {
                Button(L10n.string("Save calendar")) { save() }.disabled(model.busy)
                Button(L10n.string("Cancel")) { draft = nil; validation = nil }.buttonStyle(.borderless)
                Spacer()
            }
            if let validation { Text(validation).font(.caption).foregroundStyle(Palette.warning) }
        }
        .environment(\.timeZone, calendar.timeZone)
        if let saved = model.archive.academicCalendars?.first(where: { $0.id == selected.id }) {
            Section {
                HStack(spacing: 8) {
                    Button(L10n.string("Sync dates")) { model.syncAcademicCalendar(saved) }
                        .disabled(saved.url.isEmpty || model.busy || !saved.enabled || selected != saved)
                    Button(L10n.string("Import calendar document…")) { openImport(saved) }
                        .disabled(model.busy)
                    Spacer()
                }
                if saved.url.isEmpty {
                    Text(L10n.string("This calendar uses imported documents. Add an ICS URL to enable subscription sync."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let status = model.calendarStatus[saved.id] {
                    Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                } else if let date = saved.lastFetchedAt {
                    LabeledContent(L10n.string("Last synced")) { Text(date, format: .dateTime.month().day().hour().minute()).foregroundStyle(.secondary) }
                }
            }
            if isCMU(saved) {
                Section {
                    Text(AcademicCalendarPreset.cmu.coverageNotice).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button(L10n.string("Import 2026–2027 calendar PDF")) { openImport(saved, url: AcademicCalendarPreset.cmu.yearDocumentURL) }
                            .disabled(model.busy)
                        Link(L10n.string("Official calendar"), destination: URL(string: AcademicCalendarPreset.cmu.informationURL)!)
                    }
                }
            }
        }
    }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: draft?.timeZone ?? "") ?? .current
        return calendar
    }
    private var startDate: Binding<Date> {
        Binding(get: { draft?.windowStart ?? .now }, set: { draft?.windowStart = calendar.startOfDay(for: $0) })
    }
    private var lastDate: Binding<Date> {
        Binding(get: { calendar.date(byAdding: .day, value: -1, to: draft?.windowEnd ?? .now) ?? .now }, set: {
            draft?.windowEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
        })
    }
    private func field(_ keyPath: WritableKeyPath<AcademicCalendarSubscription, String>) -> Binding<String> {
        Binding(get: { draft?[keyPath: keyPath] ?? "" }, set: { draft?[keyPath: keyPath] = $0; validation = nil })
    }
    private func edit(_ subscription: AcademicCalendarSubscription) {
        draft = subscription; validation = nil
        customZone = !commonZones.contains(subscription.timeZone); timeZoneInput = subscription.timeZone
        if draft?.windowStart == nil || draft?.windowEnd == nil { setSuggestedRange() }
    }
    private func setSuggestedRange() {
        let term = model.availableTerms.first { $0.id == draft?.termID }
        if let range = term?.suggestedWindow(timeZone: calendar.timeZone) {
            draft?.windowStart = range.start; draft?.windowEnd = range.end
        } else {
            let year = term?.academicYear ?? calendar.component(.year, from: .now)
            draft?.windowStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
            draft?.windowEnd = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        }
    }
    private func changeTimeZone(_ zone: String) {
        let previous = calendar
        let start = draft?.windowStart.map { previous.dateComponents([.year, .month, .day], from: $0) }
        let end = draft?.windowEnd.map { previous.dateComponents([.year, .month, .day], from: $0) }
        draft?.timeZone = zone
        if let start { draft?.windowStart = calendar.date(from: start) }
        if let end { draft?.windowEnd = calendar.date(from: end) }
    }
    private func addCMU() {
        if let existing = model.archive.academicCalendars?.first(where: isCMU) { edit(existing); return }
        edit(AcademicCalendarPreset.cmu.subscription(termID: model.archive.canvasSelection?.termID))
    }
    private func addCustom() {
        edit(AcademicCalendarSubscription(name: L10n.string("Academic calendar"), url: "", termID: model.archive.canvasSelection?.termID, timeZone: TimeZone.current.identifier))
    }
    private func isCMU(_ subscription: AcademicCalendarSubscription) -> Bool {
        subscription.url == AcademicCalendarPreset.cmu.feedURL
    }
    private func save() {
        if customZone {
            let zone = timeZoneInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard TimeZone(identifier: zone) != nil else { validation = AcademicCalendarError.invalidTimeZone.localizedDescription; return }
            changeTimeZone(zone)
        }
        guard var value = draft else { return }
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.url = value.url.trimmingCharacters(in: .whitespacesAndNewlines)
        value.timeZone = value.timeZone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { validation = L10n.string("Enter a calendar name."); return }
        guard TimeZone(identifier: value.timeZone) != nil else { validation = AcademicCalendarError.invalidTimeZone.localizedDescription; return }
        guard let start = value.windowStart, let end = value.windowEnd, end > start, end.timeIntervalSince(start) <= 5 * 366 * 86_400 else {
            validation = AcademicCalendarError.invalidWindow.localizedDescription; return
        }
        do {
            if !value.url.isEmpty { value.url = try AcademicCalendarClient.normalizedURL(value.url).absoluteString }
            model.saveAcademicCalendar(value); draft = value; validation = nil
        } catch { validation = error.localizedDescription }
    }
    private func openImport(_ subscription: AcademicCalendarSubscription, url: String = "") {
        model.importCalendarID = subscription.id
        model.importURL = url
        model.revealMain(); model.showImport = true
    }
}
