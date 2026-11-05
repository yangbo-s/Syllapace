import { TZDate } from "@date-fns/tz";
import type {
  AcademicEvent,
  Category,
  Course,
  Language,
  WorkspaceView,
} from "./types";

export type ScheduleState = "historical" | "active" | "upcoming" | "undated";

export function eventsForView(
  events: AcademicEvent[],
  view: WorkspaceView,
  _category: Category | "all",
): AcademicEvent[] {
  return events.filter((event) => {
    return view === "list" || Boolean(event.start);
  });
}

export function eventDate(
  event: AcademicEvent,
  value = event.start,
): Date | null {
  if (!value) return null;
  if (event.dateOnly && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const [year, month, day] = value.split("-").map(Number);
    return new TZDate(year, month - 1, day, event.timeZone || "UTC");
  }
  const date = new Date(value);
  return Number.isFinite(date.valueOf()) ? date : null;
}
export function dateKey(date: Date, zone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: zone || "UTC",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  return ["year", "month", "day"]
    .map((type) => parts.find((part) => part.type === type)!.value)
    .join("-");
}
export function planStartToday(event: AcademicEvent, now: Date): Date {
  if (!event.dateOnly) return now;
  const [year, month, day] = dateKey(now, event.timeZone)
    .split("-")
    .map(Number);
  return new TZDate(year, month - 1, day, event.timeZone || "UTC");
}

/** All-day source dates are civil labels, not instants to move into a different day. */
export function displayDate(
  event: AcademicEvent,
  value: string | null,
  displayZone: string,
): Date | null {
  if (event.dateOnly && value && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const [year, month, day] = value.split("-").map(Number);
    return new TZDate(year, month - 1, day, displayZone);
  }
  return eventDate(event, value);
}

export function planFromDisplay(
  event: AcademicEvent,
  date: Date,
  displayZone: string,
): Date {
  return event.dateOnly ? eventDate(event, dateKey(date, displayZone))! : date;
}
/** Schedule phase only: submission/completion never decides whether an event is past. */
export function scheduleStatus(event: AcademicEvent, now: Date): ScheduleState {
  const due = eventDate(event);
  if (!due) return "undated";
  const day = dateKey(now, event.timeZone);
  const end = event.category !== "deadline" ? eventDate(event, event.end) : null;
  if (event.dateOnly) {
    const endDay = dateKey(end ?? due, event.timeZone);
    if (end ? endDay <= day : endDay < day) return "historical";
  } else if ((end ?? due) <= now) return "historical";
  const start = event.category === "deadline"
    ? (event.releasedAt ? eventDate({ ...event, dateOnly: event.releaseDateOnly ?? false }, event.releasedAt) : null)
    : due;
  if (!start) return "upcoming";
  const startsToday = event.category === "deadline" ? event.releaseDateOnly : event.dateOnly;
  return (startsToday ? dateKey(start, event.timeZone) <= day : start <= now) ? "active" : "upcoming";
}
export function filteredEvents(events: AcademicEvent[], query: string, category: Category | "all") {
  const text = query.trim().toLocaleLowerCase();
  return events.filter(event => (category === "all" || event.category === category) && (!text || [event.title, event.courseLabel, event.subtype].join(" ").toLocaleLowerCase().includes(text)))
    .sort((a, b) => (eventDate(a)?.valueOf() ?? Infinity) - (eventDate(b)?.valueOf() ?? Infinity) || a.courseLabel.localeCompare(b.courseLabel) || a.title.localeCompare(b.title));
}
export function formatDate(
  event: AcademicEvent,
  language: Language,
  displayZone = Intl.DateTimeFormat().resolvedOptions().timeZone,
): string {
  const date = eventDate(event);
  if (!date) return language === "en" ? "Date to be confirmed" : "时间未定";
  return new Intl.DateTimeFormat(language === "en" ? "en-US" : "zh-CN", {
    timeZone: event.dateOnly ? event.timeZone || "UTC" : displayZone,
    month: "short",
    day: "numeric",
    weekday: "short",
    ...(!event.dateOnly
      ? ({ hour: "numeric", minute: "2-digit", hourCycle: "h23" } as const)
      : {}),
  }).format(date);
}
export function courseColor(event: AcademicEvent, courses: Course[]): string {
  const index =
    courses.find((course) => course.id === event.courseID)?.color ?? 0;
  return `var(--course-${((index % 6) + 6) % 6})`;
}
export function ganttBounds(
  event: AcademicEvent,
): { start: Date; end: Date; isRelease: boolean } | null {
  const due = eventDate(event);
  if (!due) return null;
  if (event.category === "deadline" && event.releasedAt) {
    const release = eventDate({ ...event, dateOnly: event.releaseDateOnly ?? false }, event.releasedAt);
    if (release && release <= due) return { start: release, end: due, isRelease: true };
  }
  return { start: due, end: due, isRelease: false };
}
