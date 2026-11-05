import { TZDate } from "@date-fns/tz";
import { addDays, startOfWeek } from "date-fns";
import { dateKey, eventDate, ganttBounds } from "./model";
import type { AcademicEvent } from "./types";

function titleKey(event: AcademicEvent): string {
  return event.title.toLowerCase().replace(/^\s*\d{2}[- ]?\d{3}(?:-[a-z])?\s*[:·-]?\s*/, "").replace(/\s+/g, " ").trim();
}
function meetingKind(event: AcademicEvent): string {
  const text = titleKey(event);
  return /recitation|习题课/.test(text) ? "recitation" : /\blab\b|实验课/.test(text) ? "lab" : /lecture|讲课/.test(text) ? "lecture" : event.subtype;
}
function independentSeries(event: AcademicEvent): string {
  return event.seriesID && !/^(model-series:|schedule:)/.test(event.seriesID) ? event.seriesID : "";
}

/** Merge duplicate observations only in the projection. Source records and edits survive. */
export function uniqueOccurrences(events: AcademicEvent[]): AcademicEvent[] {
  const result: AcademicEvent[] = [];
  for (const event of events) {
    const date = eventDate(event);
    const index = date && !event.userEdited ? result.findIndex(other => {
      if (other.userEdited || other.courseID !== event.courseID || other.category !== event.category || independentSeries(other) !== independentSeries(event)) return false;
      const otherDate = eventDate(other);
      if (!otherDate) return false;
      const sameTime = event.dateOnly || other.dateOnly ? dateKey(date, event.timeZone) === dateKey(otherDate, other.timeZone) : +date === +otherDate;
      if (!sameTime) return false;
      const a = titleKey(event), b = titleKey(other);
      if (event.category === "meeting") {
        const generic = /^(lecture|recitation|class|lab|seminar)s?$/;
        return meetingKind(event) === meetingKind(other) && (a === b || generic.test(a) || generic.test(b)) && (!event.location || !other.location || event.location === other.location);
      }
      if (event.category !== "deadline") return false;
      const core = (s: string) => s.replace(/^(?:homework|hw|assignment)\s*#?\d+\s*[·:–-]\s*/, "");
      return a === b || core(a) === core(b);
    }) : -1;
    if (index < 0) result.push(event);
    else {
      const prior = result[index];
      // Prefer exact time and richer bounds, retaining a real editor target.
      const preferred = prior.dateOnly && !event.dateOnly || !prior.end && event.end ? event : prior;
      result[index] = { ...preferred, releasedAt: preferred.releasedAt ?? prior.releasedAt ?? event.releasedAt,
        releaseDateOnly: preferred.releasedAt ? preferred.releaseDateOnly : prior.releasedAt ? prior.releaseDateOnly : event.releaseDateOnly };
    }
  }
  return result;
}
export interface ScheduleGroup { id: string; event: AcademicEvent; occurrences: AcademicEvent[] }
export function scheduleGroups(events: AcademicEvent[], now: Date): ScheduleGroup[] {
  const candidates = new Map<string, AcademicEvent[]>();
  for (const event of uniqueOccurrences(events)) {
    const date = eventDate(event);
    const clock = date ? new Intl.DateTimeFormat("en-GB", { timeZone: event.timeZone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(date) : "";
    const key = event.category === "meeting" && date && !event.dateOnly && !event.userEdited
      ? [event.courseID, independentSeries(event), meetingKind(event), clock, event.timeZone].join("|") : event.id;
    candidates.set(key, [...(candidates.get(key) ?? []), event]);
  }
  const groups: ScheduleGroup[] = [];
  for (const [key, occurrences] of candidates) {
    occurrences.sort((a,b) => +(eventDate(a) ?? Infinity) - +(eventDate(b) ?? Infinity));
    const weekdays = occurrences.map(e => eventDate(e) ? new TZDate(eventDate(e)!, e.timeZone).getDay() : -1);
    const repeatsWeekday = weekdays.some((day, index) => day >= 0 && weekdays.indexOf(day) !== index);
    if (occurrences.length > 1 && (occurrences.every(e => e.seriesID) || repeatsWeekday)) {
      const event = occurrences.find(e => +(eventDate(e, e.end ?? e.start) ?? 0) >= +now) ?? occurrences.at(-1)!;
      groups.push({ id: key, event, occurrences });
    } else groups.push(...occurrences.map(event => ({ id: event.id, event, occurrences: [event] })));
  }
  return groups.sort((a,b) => +(eventDate(a.event) ?? Infinity) - +(eventDate(b.event) ?? Infinity));
}
export function inTwoWeeks(event: AcademicEvent, now: Date, zone: string): boolean {
  const start = startOfWeek(new TZDate(now, zone), { weekStartsOn: 1 }), end = addDays(start, 14);
  const bounds = ganttBounds(event);
  if (!bounds) return false;
  const finish = eventDate(event, event.end) ?? bounds.end;
  return bounds.start < end && finish >= start;
}
