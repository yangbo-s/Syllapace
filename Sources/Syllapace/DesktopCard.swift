import SwiftUI
import SyllapaceKit

struct DesktopCard: View {
    @Bindable var model: AppModel
    var setPinned: (Bool) -> Void
    @State private var preferences: DesktopCardPreferences
    @AppStorage(L10n.preferenceKey) private var languagePreference = AppLanguage.system.rawValue

    init(model: AppModel, setPinned: @escaping (Bool) -> Void, preferences: DesktopCardPreferences? = nil) {
        self.model = model
        self.setPinned = setPinned
        _preferences = State(initialValue: preferences ?? DesktopCardPreferences(persists: !model.isDemo))
    }

    var body: some View {
        let _ = languagePreference
        TimelineView(.periodic(from: .now, by: 60)) { context in content(at: context.date) }
            .frame(width: 360, height: preferences.mode.height)
            .gridArea("desktop", inset: 20)
            .background(Palette.canvas)
            .tint(Palette.accent)
            .environment(\.locale, L10n.locale)
    }

    private func upcoming(at date: Date) -> [AcademicEvent] {
        let start = Calendar.current.startOfDay(for: date)
        return model.scopedEvents.filter { event in
            guard event.state == .approved, !event.completed, let when = event.presentationDate else { return false }
            return event.dateOnly ? when >= start : (event.endsAt ?? when) >= date
        }.sorted { ($0.presentationDate ?? .distantFuture) < ($1.presentationDate ?? .distantFuture) }
    }

    private func content(at date: Date) -> some View {
        let events = upcoming(at: date)
        let nextClass = events.first { $0.kind == .session }
        let nextDeadline = events.first { [.assignment, .project, .quiz, .exam, .presentation].contains($0.kind) }
        return VStack(alignment: .leading, spacing: 16) {
            header(date: date)
            HStack(alignment: .top, spacing: 16) {
                highlight(nextClass, label: "Next class", symbol: "book", empty: "No upcoming classes")
                Divider()
                highlight(nextDeadline, label: "Next deadline", symbol: "flag", empty: "No upcoming deadlines")
            }
            .frame(height: 128)
            .gridProbe("desktop-highlights", area: "desktop")
            if preferences.mode == .expanded { weekList(events, from: date) }
            else { Spacer(minLength: 0) }
            footer
        }
        .padding(20)
        .padding(.top, 12)
    }

    private func header(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(L10n.string("Today")).font(.system(size: 23, weight: .medium, design: .rounded))
                Spacer(minLength: 0)
                Button {
                    preferences.mode = preferences.mode == .compact ? .expanded : .compact
                } label: {
                    Label(L10n.string(preferences.mode == .compact ? "Show next 7 days" : "Compact view"),
                          systemImage: preferences.mode == .compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help(L10n.string(preferences.mode == .compact ? "Show next 7 days" : "Compact view"))
                Menu {
                    Picker(L10n.string("Desktop card view"), selection: $preferences.mode) {
                        Text(L10n.string("Compact view")).tag(DesktopCardMode.compact)
                        Text(L10n.string("Next 7 days")).tag(DesktopCardMode.expanded)
                    }
                    Divider()
                    Toggle(L10n.string("Keep above windows"), isOn: $preferences.pinned)
                    Toggle(L10n.string("Lock position"), isOn: $preferences.locked)
                    Toggle(L10n.string("Snap to screen edges"), isOn: $preferences.snapsToEdges)
                } label: {
                    Label(L10n.string("Desktop card options"), systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.string("Desktop card options"))
            }
            .gridProbe("desktop-title", area: "desktop")
            Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(L10n.locale)))
                .font(.caption).foregroundStyle(.secondary).gridProbe("desktop-date", area: "desktop")
        }
        .onChange(of: preferences.pinned) { _, value in setPinned(value) }
    }

    private func highlight(_ event: AcademicEvent?, label: String, symbol: String, empty: String) -> some View {
        Button {
            if let event { reveal(event) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.string(label), systemImage: symbol).font(.caption).foregroundStyle(.secondary)
                if let event {
                    Text(event.title).font(.system(.body, design: .rounded, weight: .semibold))
                        .lineLimit(2, reservesSpace: true).frame(maxWidth: .infinity, alignment: .leading)
                    Text(model.eventOwnerName(event)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let when = event.presentationDate {
                        Text(L10n.date(when, dateOnly: event.dateOnly)).font(.caption)
                            .foregroundStyle(Palette.accent).lineLimit(2)
                    }
                } else {
                    Text(L10n.string(empty)).font(.body).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DesktopEventButtonStyle())
        .disabled(event == nil)
        .help(event?.title ?? L10n.string(empty))
    }

    private func weekList(_ events: [AcademicEvent], from date: Date) -> some View {
        let firstDay = Calendar.current.startOfDay(for: date)
        let lastDay = Calendar.current.date(byAdding: .day, value: 7, to: firstDay) ?? date
        let week = events.filter { ($0.presentationDate ?? .distantFuture) < lastDay }
        let groups = Dictionary(grouping: week) { Calendar.current.startOfDay(for: $0.presentationDate ?? date) }
        return VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text(L10n.string("Next 7 days")).font(.headline)
            if week.isEmpty {
                Text(L10n.string("Nothing scheduled this week.")).font(.body).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groups.keys.sorted(), id: \.self) { day in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale)))
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(groups[day] ?? []) { event in
                                    Button { reveal(event) } label: {
                                        HStack(alignment: .top, spacing: 8) {
                                            Circle().fill(Palette.course(model.eventColor(event))).frame(width: 8, height: 8).padding(.top, 4)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(event.title).fontWeight(.medium).lineLimit(2)
                                                HStack(spacing: 4) {
                                                    Text(model.eventOwnerName(event)).lineLimit(1)
                                                    Spacer(minLength: 4)
                                                    if let when = event.presentationDate {
                                                        Text(event.dateOnly ? L10n.string("All day") : when.formatted(.dateTime.hour().minute().locale(L10n.locale)))
                                                    }
                                                }.font(.caption).foregroundStyle(.secondary)
                                            }
                                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(DesktopEventButtonStyle())
                                }
                            }
                        }
                    }.padding(.trailing, 4)
                }
            }
        }.frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if preferences.locked { Image(systemName: "lock.fill").help(L10n.string("Lock position")) }
            if preferences.pinned { Image(systemName: "pin.fill").help(L10n.string("Keep above windows")) }
            Text(model.isDemo ? L10n.string("Demo workspace") : "Syllapace")
            Spacer(minLength: 0)
            Button(L10n.string("Open timeline")) { model.page = .timeline; model.revealMain() }
                .buttonStyle(.plain).foregroundStyle(Palette.accent)
        }
        .font(.caption).foregroundStyle(.secondary)
        .gridProbe("desktop-footer", area: "desktop", edge: "footer")
    }

    private func reveal(_ event: AcademicEvent) {
        model.page = .timeline
        model.selectedID = event.id
        model.revealMain()
    }
}

private struct DesktopEventButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.accent.opacity(isEnabled && (isHovered || configuration.isPressed) ? 0.08 : 0))
                    .padding(-4)
            }
            .onHover { isHovered = $0 }
    }
}
