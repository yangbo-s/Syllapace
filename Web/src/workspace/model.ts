import { TZDate } from "@date-fns/tz";
import type {
  AcademicEvent,
  Category,
  Course,
  Language,
  Progress,
  WorkspaceView,
} from "./types";

export type Urgency =
  | "overdue"
  | "today"
  | "soon"
  | "later"
  | "undated"
  | "done";
export type Filter = "all" | "open" | "soon" | "done";
export const progressValues: Progress[] = ["todo", "doing", "done"];

export function eventsForView(
  events: AcademicEvent[],
  view: WorkspaceView,
  category: Category | "all",
): AcademicEvent[] {
  return events.filter((event) => {
    if (view === "kanban") return event.category === "deadline";
    if (view === "gantt" && category === "all" && event.category === "meeting")
      return false;
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
export function urgency(event: AcademicEvent, now: Date): Urgency {
  if (event.progress === "done") return "done";
  const date = eventDate(event);
  if (!date) return "undated";
  const currentDay = dateKey(now, event.timeZone);
  const eventDay = dateKey(date, event.timeZone);
  if (event.dateOnly) {
    if (eventDay < currentDay) return "overdue";
    if (eventDay === currentDay) return "today";
  } else {
    if (date < now) return "overdue";
    if (eventDay === currentDay) return "today";
  }
  return date.valueOf() - now.valueOf() <= 7 * 86400000 ? "soon" : "later";
}
export function filteredEvents(
  events: AcademicEvent[],
  query: string,
  category: Category | "all",
  filter: Filter,
  now: Date,
) {
  const text = query.trim().toLocaleLowerCase();
  return events
    .filter((event) => {
      if (category !== "all" && event.category !== category) return false;
      if (
        text &&
        ![event.title, event.courseLabel, event.subtype]
          .join(" ")
          .toLocaleLowerCase()
          .includes(text)
      )
        return false;
      if (filter === "done" && event.progress !== "done") return false;
      if (filter === "open" && event.progress === "done") return false;
      if (
        filter === "soon" &&
        !["overdue", "today", "soon"].includes(urgency(event, now))
      )
        return false;
      return true;
    })
    .sort(
      (a, b) =>
        (eventDate(a)?.valueOf() ?? Infinity) -
          (eventDate(b)?.valueOf() ?? Infinity) ||
        a.courseLabel.localeCompare(b.courseLabel) ||
        a.title.localeCompare(b.title),
    );
}
export function boardColumns(
  events: AcademicEvent[],
): Record<string, AcademicEvent[]> {
  return Object.fromEntries(
    progressValues.map((progress) => [
      progress,
      events.filter((event) => event.progress === progress),
    ]),
  );
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
      ? ({ hour: "numeric", minute: "2-digit" } as const)
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
): { start: Date; end: Date; isPlan: boolean } | null {
  const due = eventDate(event);
  if (!due) return null;
  const plan = event.plannedStart ? new Date(event.plannedStart) : null;
  if (
    event.category === "deadline" &&
    plan &&
    Number.isFinite(plan.valueOf()) &&
    plan <= due
  )
    return { start: plan, end: due, isPlan: true };
  if (event.category === "meeting" && event.end) {
    const end = eventDate(event, event.end);
    if (end && end > due) return { start: due, end, isPlan: false };
  }
  return { start: due, end: due, isPlan: false };
}
