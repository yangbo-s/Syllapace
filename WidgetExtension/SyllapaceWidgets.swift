import SwiftUI
import WidgetKit

private struct UpcomingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct UpcomingProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingEntry {
        UpcomingEntry(date: .now, snapshot: sampleSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingEntry) -> Void) {
        completion(UpcomingEntry(date: .now, snapshot: context.isPreview ? sampleSnapshot : savedSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingEntry>) -> Void) {
        let now = Date.now
        let snapshot = savedSnapshot()
        // Ask for a refresh at the next date boundary or deadline. WidgetKit owns the actual budget.
        let nextDay = Calendar.current.date(byAdding: .day, value: 1,
                                           to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let transitions = (snapshot?.upcoming(at: now) ?? []).compactMap { item -> Date? in
            guard !item.dateOnly else { return nil }
            return (item.endsAt ?? item.date).addingTimeInterval(1)
        }.filter { $0 > now }
        let refresh = min(transitions.min() ?? nextDay, nextDay, now.addingTimeInterval(1_800))
        completion(Timeline(entries: [UpcomingEntry(date: now, snapshot: snapshot)], policy: .after(refresh)))
    }

    private func savedSnapshot() -> WidgetSnapshot? { try? WidgetSnapshotStore.configured()?.read() }

    private var sampleSnapshot: WidgetSnapshot {
        WidgetSnapshot(semesterName: "Fall 2026", language: "en", items: [
            .init(id: "preview", title: "Project proposal", courseName: "Design Studio", colorIndex: 0,
                  kind: "project", date: .now.addingTimeInterval(3_600), dateOnly: false,
                  timeZone: TimeZone.current.identifier)
        ])
    }
}

struct UpcomingWidgetView: View {
    let snapshot: WidgetSnapshot?
    let date: Date
    let family: WidgetFamily
    @Environment(\.colorScheme) private var colorScheme

    private var isChinese: Bool { (snapshot?.language ?? Locale.current.identifier).hasPrefix("zh") }
    private var accent: Color {
        colorScheme == .dark ? Color(red: 0.46, green: 0.79, blue: 0.73) : Color(red: 0.15, green: 0.47, blue: 0.43)
    }
    private var limit: Int { family == .systemSmall ? 1 : family == .systemMedium ? 2 : 5 }
    private var items: [WidgetSnapshot.Item] { Array((snapshot?.upcoming(at: date) ?? []).prefix(limit)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(isChinese ? "近期安排" : "Upcoming", systemImage: "calendar")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(accent)
                Spacer(minLength: 4)
                if family != .systemSmall {
                    Text(snapshot?.semesterName ?? "Syllapace")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if items.isEmpty {
                Spacer(minLength: 0)
                Text(isChinese ? "接下来，留点空白。" : "Room for what’s next.")
                    .font(.system(.headline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Text(isChinese ? "在 Syllapace 中查看课程" : "View your courses in Syllapace")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(items) { item in
                    if family == .systemSmall {
                        row(item)
                    } else if let destination = item.deepLink {
                        Link(destination: destination) { row(item) }.buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(items.first?.deepLink ?? URL(string: "syllapace://open"))
    }

    private func row(_ item: WidgetSnapshot.Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(family == .systemSmall ? .headline : .subheadline, design: .rounded, weight: .semibold))
                .lineLimit(family == .systemSmall ? 3 : 1)
                .privacySensitive()
            Text(item.courseName).font(.caption).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
            Text(dateLabel(item)).font(.caption).foregroundStyle(accent).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func dateLabel(_ item: WidgetSnapshot.Item) -> String {
        let format = Date.FormatStyle(date: .abbreviated, time: item.dateOnly ? .omitted : .shortened)
            .locale(Locale(identifier: isChinese ? "zh_Hans" : "en_US"))
        return item.displayDate().formatted(format)
    }
}

private struct SyllapaceUpcomingWidget: Widget {
    let kind = WidgetSnapshot.kind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UpcomingProvider()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Syllapace")
        .description("Your next course deadlines and events.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct WidgetEntryView: View {
    let entry: UpcomingEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        UpcomingWidgetView(snapshot: entry.snapshot, date: entry.date, family: family)
            .containerBackground(.background, for: .widget)
    }
}

@main
struct SyllapaceWidgets: WidgetBundle {
    var body: some Widget { SyllapaceUpcomingWidget() }
}
